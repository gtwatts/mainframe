#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/collection.sh - Functional Collections Library
# =============================================================================
# Description: Functional programming primitives (map, filter, reduce) for
#              array manipulation with Design-by-Contract validation.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_COLLECTION_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COLLECTION_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# shellcheck source=./common.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/common.sh" 2>/dev/null || true
# shellcheck source=./json.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/json.sh" 2>/dev/null || true
# shellcheck source=./contract.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/contract.sh" 2>/dev/null || true

# =============================================================================
# CONFIGURATION
# =============================================================================

# Maximum iterations to prevent infinite loops
readonly COLLECTION_MAX_ITERATIONS="${COLLECTION_MAX_ITERATIONS:-1000000}"

# Enable/disable contract checking (can be disabled for performance)
COLLECTION_CONTRACTS="${COLLECTION_CONTRACTS:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Validate that a function exists and is callable
# @pre: name is non-empty
# @post: returns 0 if callable, 1 otherwise
_collection_is_callable() {
    local name="$1"
    [[ -n "$name" ]] && declare -f "$name" &>/dev/null
}

# JSON escape for USOP output
_collection_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit USOP JSON error
_collection_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local func="${FUNCNAME[1]:-unknown}"

    local escaped_msg escaped_func
    escaped_msg=$(_collection_escape_json "$msg")
    escaped_func=$(_collection_escape_json "$func")

    printf '{"ok":false,"error":{"code":%d,"msg":"%s","func":"%s"}}\n' \
        "$code" "$escaped_msg" "$escaped_func" >&2
    return "$code"
}

# Emit USOP JSON success
_collection_success() {
    local data="${1:-null}"
    printf '{"ok":true,"data":%s}\n' "$data"
}

# =============================================================================
# CORE FUNCTIONAL PRIMITIVES
# =============================================================================

# -----------------------------------------------------------------------------
# array_map - Transform each element using a callback function
# -----------------------------------------------------------------------------
# @description Apply a transformation function to each element of an array
# @pre        callback is a valid function name that accepts one argument
# @post       result array contains transformed values, same length as input
# @idempotent Yes - same input produces same output
# @param      $1 arr - Input array (nameref)
# @param      $2 callback - Function to apply to each element
# @param      $3 result - Output array (nameref)
# @return     0 on success, 1 on invalid callback
#
# Usage:
#   double() { printf '%s' $(($1 * 2)); }
#   arr=(1 2 3 4 5)
#   array_map arr double result
#   # result=(2 4 6 8 10)
# -----------------------------------------------------------------------------
array_map() {
    local -n _am_input=$1
    local callback="$2"
    local -n _am_output=$3

    # Contract: callback must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$callback"; then
            _collection_error 1 "callback '$callback' is not a valid function"
            return 1
        fi
    fi

    # Initialize output array
    _am_output=()

    # Apply callback to each element
    local elem transformed
    for elem in "${_am_input[@]}"; do
        transformed=$("$callback" "$elem")
        _am_output+=("$transformed")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_filter - Keep elements that match a predicate
# -----------------------------------------------------------------------------
# @description Filter array elements using a predicate function
# @pre        predicate returns 0 (true) to keep, non-zero to reject
# @post       result contains only elements where predicate returned 0
# @idempotent Yes - same input produces same output
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function that returns 0 to keep element
# @param      $3 result - Output array (nameref)
# @return     0 on success, 1 on invalid predicate
#
# Usage:
#   is_even() { (( $1 % 2 == 0 )); }
#   arr=(1 2 3 4 5 6)
#   array_filter arr is_even result
#   # result=(2 4 6)
# -----------------------------------------------------------------------------
array_filter() {
    local -n _af_input=$1
    local predicate="$2"
    local -n _af_output=$3

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Initialize output array
    _af_output=()

    # Filter elements
    local elem
    for elem in "${_af_input[@]}"; do
        if "$predicate" "$elem"; then
            _af_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_reduce - Fold array to a single value using a reducer
# -----------------------------------------------------------------------------
# @description Reduce array to single value using accumulator pattern
# @pre        reducer accepts (accumulator, element) and outputs new accumulator
# @post       single value computed from all elements
# @idempotent Yes - same input produces same output
# @param      $1 arr - Input array (nameref)
# @param      $2 reducer - Function(accumulator, element) -> new_accumulator
# @param      $3 initial - Starting accumulator value
# @param      $4 result - Output variable (nameref)
# @return     0 on success, 1 on invalid reducer
#
# Usage:
#   sum() { printf '%s' $(($1 + $2)); }
#   arr=(1 2 3 4 5)
#   array_reduce arr sum 0 result
#   # result=15
# -----------------------------------------------------------------------------
array_reduce() {
    local -n _ar_input=$1
    local reducer="$2"
    local initial="$3"
    local -n _ar_output=$4

    # Contract: reducer must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$reducer"; then
            _collection_error 1 "reducer '$reducer' is not a valid function"
            return 1
        fi
    fi

    # Start with initial value
    local acc="$initial"

    # Fold over elements
    local elem
    for elem in "${_ar_input[@]}"; do
        acc=$("$reducer" "$acc" "$elem")
    done

    _ar_output="$acc"
    return 0
}

# -----------------------------------------------------------------------------
# array_find - Find first element matching predicate
# -----------------------------------------------------------------------------
# @description Find and output the first element that matches predicate
# @pre        predicate returns 0 (true) for match
# @post       outputs matching element if found
# @idempotent Yes - same input produces same output
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function that returns 0 for match
# @stdout     The first matching element (if found)
# @return     0 if found, 1 if no match
#
# Usage:
#   is_greater_than_3() { (( $1 > 3 )); }
#   arr=(1 2 3 4 5)
#   result=$(array_find arr is_greater_than_3)
#   # result=4
# -----------------------------------------------------------------------------
array_find() {
    local -n _afind_input=$1
    local predicate="$2"

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Search for first match
    local elem
    for elem in "${_afind_input[@]}"; do
        if "$predicate" "$elem"; then
            printf '%s' "$elem"
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# array_find_index - Find index of first element matching predicate
# -----------------------------------------------------------------------------
# @description Find the index of the first element that matches predicate
# @pre        predicate returns 0 (true) for match
# @post       outputs index if found
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function that returns 0 for match
# @stdout     The index of first matching element (if found)
# @return     0 if found, 1 if no match
#
# Usage:
#   is_even() { (( $1 % 2 == 0 )); }
#   arr=(1 3 5 6 7)
#   idx=$(array_find_index arr is_even)
#   # idx=3
# -----------------------------------------------------------------------------
array_find_index() {
    local -n _afi_input=$1
    local predicate="$2"

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Search for first match
    local i
    for i in "${!_afi_input[@]}"; do
        if "$predicate" "${_afi_input[$i]}"; then
            printf '%s' "$i"
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# array_every - Check if ALL elements match predicate
# -----------------------------------------------------------------------------
# @description Test if every element satisfies the predicate
# @pre        predicate returns 0 (true) for match
# @post       returns 0 if ALL elements match, 1 otherwise
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @return     0 if all match, 1 if any fails
#
# Usage:
#   is_positive() { (( $1 > 0 )); }
#   arr=(1 2 3 4 5)
#   array_every arr is_positive && echo "all positive"
# -----------------------------------------------------------------------------
array_every() {
    local -n _ae_input=$1
    local predicate="$2"

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Empty array satisfies vacuously
    [[ ${#_ae_input[@]} -eq 0 ]] && return 0

    # Check all elements
    local elem
    for elem in "${_ae_input[@]}"; do
        if ! "$predicate" "$elem"; then
            return 1
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_some - Check if ANY element matches predicate
# -----------------------------------------------------------------------------
# @description Test if at least one element satisfies the predicate
# @pre        predicate returns 0 (true) for match
# @post       returns 0 if ANY element matches, 1 if none match
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @return     0 if any matches, 1 if none match
#
# Usage:
#   is_negative() { (( $1 < 0 )); }
#   arr=(1 2 -3 4 5)
#   array_some arr is_negative && echo "has negative"
# -----------------------------------------------------------------------------
array_some() {
    local -n _as_input=$1
    local predicate="$2"

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Empty array has no matching elements
    [[ ${#_as_input[@]} -eq 0 ]] && return 1

    # Check for any match
    local elem
    for elem in "${_as_input[@]}"; do
        if "$predicate" "$elem"; then
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# array_none - Check if NO elements match predicate
# -----------------------------------------------------------------------------
# @description Test if no elements satisfy the predicate
# @pre        predicate returns 0 (true) for match
# @post       returns 0 if NO elements match, 1 if any matches
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @return     0 if none match, 1 if any matches
#
# Usage:
#   is_zero() { (( $1 == 0 )); }
#   arr=(1 2 3 4 5)
#   array_none arr is_zero && echo "no zeros"
# -----------------------------------------------------------------------------
array_none() {
    local -n _an_input=$1
    local predicate="$2"

    # none is the negation of some
    ! array_some "$1" "$predicate"
}

# -----------------------------------------------------------------------------
# array_partition - Split array by predicate into matching/non-matching
# -----------------------------------------------------------------------------
# @description Partition array into two arrays based on predicate
# @pre        predicate returns 0 (true) for match
# @post       matches contains elements where predicate returned 0
# @post       non_matches contains elements where predicate returned non-0
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to partition by
# @param      $3 matches - Output array for matching elements (nameref)
# @param      $4 non_matches - Output array for non-matching elements (nameref)
# @return     0 on success, 1 on invalid predicate
#
# Usage:
#   is_even() { (( $1 % 2 == 0 )); }
#   arr=(1 2 3 4 5 6)
#   array_partition arr is_even evens odds
#   # evens=(2 4 6), odds=(1 3 5)
# -----------------------------------------------------------------------------
array_partition() {
    local -n _ap_input=$1
    local predicate="$2"
    local -n _ap_matches=$3
    local -n _ap_nonmatches=$4

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    # Initialize output arrays
    _ap_matches=()
    _ap_nonmatches=()

    # Partition elements
    local elem
    for elem in "${_ap_input[@]}"; do
        if "$predicate" "$elem"; then
            _ap_matches+=("$elem")
        else
            _ap_nonmatches+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_group_by - Group elements by a key function
# -----------------------------------------------------------------------------
# @description Group array elements by the result of a key function
# @pre        key_func outputs a string key for each element
# @post       outputs JSON object with keys mapped to arrays of elements
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 key_func - Function that returns grouping key
# @stdout     JSON object {"key1":["elem1","elem2"],"key2":["elem3"]}
# @return     0 on success, 1 on invalid key_func
#
# Usage:
#   get_length() { printf '%s' "${#1}"; }
#   arr=("a" "bb" "ccc" "dd" "e")
#   array_group_by arr get_length
#   # {"1":["a","e"],"2":["bb","dd"],"3":["ccc"]}
# -----------------------------------------------------------------------------
array_group_by() {
    local -n _agb_input=$1
    local key_func="$2"

    # Contract: key_func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$key_func"; then
            _collection_error 1 "key_func '$key_func' is not a valid function"
            return 1
        fi
    fi

    # Use associative array to collect groups
    declare -A groups
    declare -A group_arrays

    local elem key
    for elem in "${_agb_input[@]}"; do
        key=$("$key_func" "$elem")

        # Escape element for JSON
        local escaped
        escaped=$(_collection_escape_json "$elem")

        # Append to group (comma-separated for later processing)
        if [[ -n "${groups[$key]:-}" ]]; then
            groups[$key]="${groups[$key]},\"$escaped\""
        else
            groups[$key]="\"$escaped\""
        fi
    done

    # Build JSON output
    local first=true
    printf '{'
    for key in "${!groups[@]}"; do
        $first || printf ','
        first=false
        local escaped_key
        escaped_key=$(_collection_escape_json "$key")
        printf '"%s":[%s]' "$escaped_key" "${groups[$key]}"
    done
    printf '}'

    return 0
}

# -----------------------------------------------------------------------------
# array_flat_map - Map then flatten the results
# -----------------------------------------------------------------------------
# @description Apply function that returns array, then flatten all results
# @pre        func outputs space-separated values or newline-separated values
# @post       result contains all values from all function calls, flattened
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 func - Function that may return multiple values
# @param      $3 result - Output array (nameref)
# @return     0 on success, 1 on invalid func
#
# Usage:
#   expand_range() { seq 1 "$1"; }
#   arr=(3 2 1)
#   array_flat_map arr expand_range result
#   # result=(1 2 3 1 2 1)
# -----------------------------------------------------------------------------
array_flat_map() {
    local -n _afm_input=$1
    local func="$2"
    local -n _afm_output=$3

    # Contract: func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$func"; then
            _collection_error 1 "func '$func' is not a valid function"
            return 1
        fi
    fi

    # Initialize output array
    _afm_output=()

    # Map and flatten
    local elem
    for elem in "${_afm_input[@]}"; do
        # Capture output, handle both space and newline separation
        local output
        output=$("$func" "$elem")

        # Split by whitespace and add to result
        local item
        while IFS= read -r item || [[ -n "$item" ]]; do
            # Handle space-separated items on each line
            for word in $item; do
                [[ -n "$word" ]] && _afm_output+=("$word")
            done
        done <<< "$output"
    done

    return 0
}

# =============================================================================
# ARRAY SLICING AND CHUNKING
# =============================================================================

# -----------------------------------------------------------------------------
# array_take - Take first n elements
# -----------------------------------------------------------------------------
# @description Get the first n elements from an array
# @pre        n >= 0
# @post       result contains min(n, array_length) elements
# @idempotent Yes
# @param      $1 n - Number of elements to take
# @param      $2 arr - Input array (nameref)
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   array_take 3 arr result
#   # result=(1 2 3)
# -----------------------------------------------------------------------------
array_take() {
    local n="$1"
    local -n _at_input=$2
    local -n _at_output=$3

    # Contract: n must be non-negative integer
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if [[ ! "$n" =~ ^[0-9]+$ ]]; then
            _collection_error 1 "n must be a non-negative integer, got '$n'"
            return 1
        fi
    fi

    _at_output=()

    local count=0
    local elem
    for elem in "${_at_input[@]}"; do
        (( count >= n )) && break
        _at_output+=("$elem")
        ((count++))
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_drop - Skip first n elements
# -----------------------------------------------------------------------------
# @description Get all elements after skipping the first n
# @pre        n >= 0
# @post       result contains elements from index n onwards
# @idempotent Yes
# @param      $1 n - Number of elements to skip
# @param      $2 arr - Input array (nameref)
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   array_drop 2 arr result
#   # result=(3 4 5)
# -----------------------------------------------------------------------------
array_drop() {
    local n="$1"
    local -n _ad_input=$2
    local -n _ad_output=$3

    # Contract: n must be non-negative integer
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if [[ ! "$n" =~ ^[0-9]+$ ]]; then
            _collection_error 1 "n must be a non-negative integer, got '$n'"
            return 1
        fi
    fi

    _ad_output=()

    local count=0
    local elem
    for elem in "${_ad_input[@]}"; do
        if (( count >= n )); then
            _ad_output+=("$elem")
        fi
        ((count++))
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_take_while - Take elements while predicate is true
# -----------------------------------------------------------------------------
# @description Take elements from start while predicate returns 0
# @pre        predicate returns 0 (true) to continue taking
# @post       result contains longest prefix where predicate held
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   is_less_than_4() { (( $1 < 4 )); }
#   arr=(1 2 3 4 5 1)
#   array_take_while arr is_less_than_4 result
#   # result=(1 2 3)
# -----------------------------------------------------------------------------
array_take_while() {
    local -n _atw_input=$1
    local predicate="$2"
    local -n _atw_output=$3

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    _atw_output=()

    local elem
    for elem in "${_atw_input[@]}"; do
        if "$predicate" "$elem"; then
            _atw_output+=("$elem")
        else
            break
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_drop_while - Drop elements while predicate is true
# -----------------------------------------------------------------------------
# @description Skip elements from start while predicate returns 0
# @pre        predicate returns 0 (true) to continue dropping
# @post       result contains elements after predicate first failed
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   is_less_than_3() { (( $1 < 3 )); }
#   arr=(1 2 3 4 5)
#   array_drop_while arr is_less_than_3 result
#   # result=(3 4 5)
# -----------------------------------------------------------------------------
array_drop_while() {
    local -n _adw_input=$1
    local predicate="$2"
    local -n _adw_output=$3

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    _adw_output=()

    local dropping=true
    local elem
    for elem in "${_adw_input[@]}"; do
        if $dropping && "$predicate" "$elem"; then
            continue
        else
            dropping=false
            _adw_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_slice - Extract a slice of the array
# -----------------------------------------------------------------------------
# @description Get elements from start index to end index (exclusive)
# @pre        start >= 0, end >= start
# @post       result contains elements[start:end]
# @idempotent Yes
# @param      $1 start - Starting index (inclusive)
# @param      $2 end - Ending index (exclusive)
# @param      $3 arr - Input array (nameref)
# @param      $4 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=(a b c d e)
#   array_slice 1 4 arr result
#   # result=(b c d)
# -----------------------------------------------------------------------------
array_slice() {
    local start="$1"
    local end="$2"
    local -n _asl_input=$3
    local -n _asl_output=$4

    # Contract: indices must be valid
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if [[ ! "$start" =~ ^[0-9]+$ ]] || [[ ! "$end" =~ ^[0-9]+$ ]]; then
            _collection_error 1 "start and end must be non-negative integers"
            return 1
        fi
    fi

    _asl_output=()

    local len=${#_asl_input[@]}
    (( end > len )) && end=$len
    (( start > len )) && start=$len

    local i
    for (( i = start; i < end; i++ )); do
        _asl_output+=("${_asl_input[$i]}")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_chunk - Split array into n-sized chunks
# -----------------------------------------------------------------------------
# @description Split array into sub-arrays of size n
# @pre        n > 0
# @post       outputs JSON array of arrays
# @idempotent Yes
# @param      $1 n - Chunk size
# @param      $2 arr - Input array (nameref)
# @stdout     JSON array of arrays [[a,b],[c,d],...]
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   array_chunk 2 arr
#   # [["1","2"],["3","4"],["5"]]
# -----------------------------------------------------------------------------
array_chunk() {
    local n="$1"
    local -n _ac_input=$2

    # Contract: n must be positive
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if [[ ! "$n" =~ ^[1-9][0-9]*$ ]]; then
            _collection_error 1 "chunk size must be a positive integer, got '$n'"
            return 1
        fi
    fi

    local len=${#_ac_input[@]}
    local first_chunk=true

    printf '['

    local i=0
    while (( i < len )); do
        $first_chunk || printf ','
        first_chunk=false

        printf '['
        local first_elem=true
        local j=0
        while (( j < n && i < len )); do
            $first_elem || printf ','
            first_elem=false

            local escaped
            escaped=$(_collection_escape_json "${_ac_input[$i]}")
            printf '"%s"' "$escaped"

            ((i++))
            ((j++))
        done
        printf ']'
    done

    printf ']'

    return 0
}

# =============================================================================
# ARRAY COMBINATION OPERATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# array_zip - Combine two arrays into pairs
# -----------------------------------------------------------------------------
# @description Combine elements from two arrays into pairs
# @pre        none
# @post       result contains pairs (stops at shorter array length)
# @idempotent Yes
# @param      $1 arr1 - First input array (nameref)
# @param      $2 arr2 - Second input array (nameref)
# @param      $3 result - Output array of "elem1:elem2" pairs (nameref)
# @return     0 on success
#
# Usage:
#   a=(1 2 3)
#   b=(a b c)
#   array_zip a b result
#   # result=("1:a" "2:b" "3:c")
# -----------------------------------------------------------------------------
array_zip() {
    local -n _az_arr1=$1
    local -n _az_arr2=$2
    local -n _az_output=$3

    _az_output=()

    local len1=${#_az_arr1[@]}
    local len2=${#_az_arr2[@]}
    local len=$(( len1 < len2 ? len1 : len2 ))

    local i
    for (( i = 0; i < len; i++ )); do
        _az_output+=("${_az_arr1[$i]}:${_az_arr2[$i]}")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_zip_with - Combine two arrays using a custom function
# -----------------------------------------------------------------------------
# @description Combine elements using a binary function
# @pre        func accepts two arguments and outputs combined result
# @post       result contains combined values
# @idempotent Yes
# @param      $1 arr1 - First input array (nameref)
# @param      $2 arr2 - Second input array (nameref)
# @param      $3 func - Function(elem1, elem2) -> combined
# @param      $4 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   add() { printf '%s' $(($1 + $2)); }
#   a=(1 2 3)
#   b=(10 20 30)
#   array_zip_with a b add result
#   # result=(11 22 33)
# -----------------------------------------------------------------------------
array_zip_with() {
    local -n _azw_arr1=$1
    local -n _azw_arr2=$2
    local func="$3"
    local -n _azw_output=$4

    # Contract: func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$func"; then
            _collection_error 1 "func '$func' is not a valid function"
            return 1
        fi
    fi

    _azw_output=()

    local len1=${#_azw_arr1[@]}
    local len2=${#_azw_arr2[@]}
    local len=$(( len1 < len2 ? len1 : len2 ))

    local i combined
    for (( i = 0; i < len; i++ )); do
        combined=$("$func" "${_azw_arr1[$i]}" "${_azw_arr2[$i]}")
        _azw_output+=("$combined")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_unzip - Split pairs into two arrays
# -----------------------------------------------------------------------------
# @description Split array of "a:b" pairs into two separate arrays
# @pre        elements are in "a:b" format (colon-separated)
# @post       arr1 contains first parts, arr2 contains second parts
# @idempotent Yes
# @param      $1 pairs - Input array of pairs (nameref)
# @param      $2 arr1 - Output array for first elements (nameref)
# @param      $3 arr2 - Output array for second elements (nameref)
# @return     0 on success
#
# Usage:
#   pairs=("1:a" "2:b" "3:c")
#   array_unzip pairs nums letters
#   # nums=(1 2 3), letters=(a b c)
# -----------------------------------------------------------------------------
array_unzip() {
    local -n _au_pairs=$1
    local -n _au_arr1=$2
    local -n _au_arr2=$3

    _au_arr1=()
    _au_arr2=()

    local pair first second
    for pair in "${_au_pairs[@]}"; do
        first="${pair%%:*}"
        second="${pair#*:}"
        _au_arr1+=("$first")
        _au_arr2+=("$second")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_concat - Concatenate multiple arrays
# -----------------------------------------------------------------------------
# @description Concatenate multiple arrays into one
# @pre        none
# @post       result contains all elements from all arrays in order
# @idempotent Yes
# @param      $1 result - Output array (nameref)
# @param      $@ - Names of arrays to concatenate
# @return     0 on success
#
# Usage:
#   a=(1 2)
#   b=(3 4)
#   c=(5 6)
#   array_concat result a b c
#   # result=(1 2 3 4 5 6)
# -----------------------------------------------------------------------------
array_concat() {
    local -n _aconcat_output=$1
    shift

    _aconcat_output=()

    local arr_name
    for arr_name in "$@"; do
        local -n _aconcat_input=$arr_name
        _aconcat_output+=("${_aconcat_input[@]}")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_flatten - Flatten nested structure (one level)
# -----------------------------------------------------------------------------
# @description Flatten array where elements may be space-separated values
# @pre        elements may contain space-separated sub-elements
# @post       result contains individual words from all elements
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=("1 2" "3 4" "5")
#   array_flatten arr result
#   # result=(1 2 3 4 5)
# -----------------------------------------------------------------------------
array_flatten() {
    local -n _afl_input=$1
    local -n _afl_output=$2

    _afl_output=()

    local elem word
    for elem in "${_afl_input[@]}"; do
        for word in $elem; do
            _afl_output+=("$word")
        done
    done

    return 0
}

# =============================================================================
# ARRAY COMPARISON AND SEARCH
# =============================================================================

# -----------------------------------------------------------------------------
# array_count - Count elements matching predicate
# -----------------------------------------------------------------------------
# @description Count how many elements satisfy the predicate
# @pre        predicate returns 0 (true) for match
# @post       outputs count of matching elements
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 predicate - Function to test each element
# @stdout     Number of matching elements
# @return     0 on success
#
# Usage:
#   is_even() { (( $1 % 2 == 0 )); }
#   arr=(1 2 3 4 5 6)
#   count=$(array_count arr is_even)
#   # count=3
# -----------------------------------------------------------------------------
array_count() {
    local -n _acnt_input=$1
    local predicate="$2"

    # Contract: predicate must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$predicate"; then
            _collection_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    local count=0
    local elem
    for elem in "${_acnt_input[@]}"; do
        if "$predicate" "$elem"; then
            ((count++))
        fi
    done

    printf '%d' "$count"
    return 0
}

# -----------------------------------------------------------------------------
# array_max_by - Find element with maximum value according to comparator
# -----------------------------------------------------------------------------
# @description Find the element with the maximum value using a key function
# @pre        key_func outputs a comparable numeric value
# @post       outputs element with maximum key value
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 key_func - Function to extract comparable value
# @stdout     Element with maximum key value
# @return     0 if found, 1 if empty array
#
# Usage:
#   get_length() { printf '%s' "${#1}"; }
#   arr=("a" "bbb" "cc")
#   result=$(array_max_by arr get_length)
#   # result=bbb
# -----------------------------------------------------------------------------
array_max_by() {
    local -n _amb_input=$1
    local key_func="$2"

    # Contract: key_func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$key_func"; then
            _collection_error 1 "key_func '$key_func' is not a valid function"
            return 1
        fi
    fi

    [[ ${#_amb_input[@]} -eq 0 ]] && return 1

    local max_elem="${_amb_input[0]}"
    local max_key
    max_key=$("$key_func" "$max_elem")

    local elem key
    for elem in "${_amb_input[@]:1}"; do
        key=$("$key_func" "$elem")
        if (( key > max_key )); then
            max_key="$key"
            max_elem="$elem"
        fi
    done

    printf '%s' "$max_elem"
    return 0
}

# -----------------------------------------------------------------------------
# array_min_by - Find element with minimum value according to comparator
# -----------------------------------------------------------------------------
# @description Find the element with the minimum value using a key function
# @pre        key_func outputs a comparable numeric value
# @post       outputs element with minimum key value
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 key_func - Function to extract comparable value
# @stdout     Element with minimum key value
# @return     0 if found, 1 if empty array
#
# Usage:
#   get_length() { printf '%s' "${#1}"; }
#   arr=("aaa" "b" "cc")
#   result=$(array_min_by arr get_length)
#   # result=b
# -----------------------------------------------------------------------------
array_min_by() {
    local -n _aminb_input=$1
    local key_func="$2"

    # Contract: key_func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$key_func"; then
            _collection_error 1 "key_func '$key_func' is not a valid function"
            return 1
        fi
    fi

    [[ ${#_aminb_input[@]} -eq 0 ]] && return 1

    local min_elem="${_aminb_input[0]}"
    local min_key
    min_key=$("$key_func" "$min_elem")

    local elem key
    for elem in "${_aminb_input[@]:1}"; do
        key=$("$key_func" "$elem")
        if (( key < min_key )); then
            min_key="$key"
            min_elem="$elem"
        fi
    done

    printf '%s' "$min_elem"
    return 0
}

# -----------------------------------------------------------------------------
# array_sort_by - Sort array using a key function
# -----------------------------------------------------------------------------
# @description Sort array elements by numeric key function result
# @pre        key_func outputs a comparable numeric value
# @post       result contains sorted elements (ascending)
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 key_func - Function to extract sort key
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   get_length() { printf '%s' "${#1}"; }
#   arr=("aaa" "b" "cc")
#   array_sort_by arr get_length result
#   # result=("b" "cc" "aaa")
# -----------------------------------------------------------------------------
array_sort_by() {
    local -n _asb_input=$1
    local key_func="$2"
    local -n _asb_output=$3

    # Contract: key_func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$key_func"; then
            _collection_error 1 "key_func '$key_func' is not a valid function"
            return 1
        fi
    fi

    # Create array of "key:index" pairs
    local pairs=()
    local i key
    for i in "${!_asb_input[@]}"; do
        key=$("$key_func" "${_asb_input[$i]}")
        pairs+=("$key:$i")
    done

    # Sort pairs by key (numeric sort)
    local sorted_pairs
    mapfile -t sorted_pairs < <(printf '%s\n' "${pairs[@]}" | sort -t: -k1 -n)

    # Extract elements in sorted order
    _asb_output=()
    local pair idx
    for pair in "${sorted_pairs[@]}"; do
        idx="${pair#*:}"
        _asb_output+=("${_asb_input[$idx]}")
    done

    return 0
}

# =============================================================================
# PIPE COMPOSITION
# =============================================================================

# -----------------------------------------------------------------------------
# pipe_through - Unix pipe-style composition of array operations
# -----------------------------------------------------------------------------
# @description Apply a series of transformations to input lines
# @pre        operations are in format "type:function" where type is map/filter
# @post       outputs transformed lines
# @idempotent Yes
# @param      $@ - Operations in "type:function" format
# @stdin      Input lines to process
# @stdout     Transformed output lines
# @return     0 on success
#
# Usage:
#   double() { printf '%s' $(($1 * 2)); }
#   is_even() { (( $1 % 2 == 0 )); }
#   echo -e "1\n2\n3\n4" | pipe_through "filter:is_even" "map:double"
#   # Output: 4\n8
# -----------------------------------------------------------------------------
pipe_through() {
    local operations=("$@")

    # Read all input lines into array
    local input=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        input+=("$line")
    done

    # Apply each operation
    local op op_type op_func
    for op in "${operations[@]}"; do
        op_type="${op%%:*}"
        op_func="${op#*:}"

        local temp_result=()

        case "$op_type" in
            map)
                if _collection_is_callable "$op_func"; then
                    local elem
                    for elem in "${input[@]}"; do
                        temp_result+=("$("$op_func" "$elem")")
                    done
                fi
                ;;
            filter)
                if _collection_is_callable "$op_func"; then
                    local elem
                    for elem in "${input[@]}"; do
                        if "$op_func" "$elem"; then
                            temp_result+=("$elem")
                        fi
                    done
                fi
                ;;
            take)
                local n="$op_func"
                local count=0
                local elem
                for elem in "${input[@]}"; do
                    (( count >= n )) && break
                    temp_result+=("$elem")
                    ((count++))
                done
                ;;
            drop)
                local n="$op_func"
                local count=0
                local elem
                for elem in "${input[@]}"; do
                    if (( count >= n )); then
                        temp_result+=("$elem")
                    fi
                    ((count++))
                done
                ;;
            *)
                # Unknown operation, pass through
                temp_result=("${input[@]}")
                ;;
        esac

        input=("${temp_result[@]}")
    done

    # Output result
    local elem
    for elem in "${input[@]}"; do
        printf '%s\n' "$elem"
    done

    return 0
}

# =============================================================================
# JSON SERIALIZATION (USOP FORMAT)
# =============================================================================

# -----------------------------------------------------------------------------
# collection_to_json - Convert array to JSON array
# -----------------------------------------------------------------------------
# @description Serialize a bash array to JSON array format
# @pre        none
# @post       outputs valid JSON array
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     JSON array ["elem1","elem2",...]
# @return     0 on success
#
# Usage:
#   arr=(one two three)
#   collection_to_json arr
#   # ["one","two","three"]
# -----------------------------------------------------------------------------
collection_to_json() {
    local -n _ctj_input=$1

    local first=true
    printf '['

    local elem
    for elem in "${_ctj_input[@]}"; do
        $first || printf ','
        first=false

        local escaped
        escaped=$(_collection_escape_json "$elem")
        printf '"%s"' "$escaped"
    done

    printf ']'
    return 0
}

# -----------------------------------------------------------------------------
# collection_to_json_numbers - Convert numeric array to JSON
# -----------------------------------------------------------------------------
# @description Serialize a numeric bash array to JSON array format
# @pre        elements are valid numbers
# @post       outputs valid JSON array of numbers
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     JSON array [1,2,3]
# @return     0 on success
#
# Usage:
#   arr=(1 2 3)
#   collection_to_json_numbers arr
#   # [1,2,3]
# -----------------------------------------------------------------------------
collection_to_json_numbers() {
    local -n _ctjn_input=$1

    local first=true
    printf '['

    local elem
    for elem in "${_ctjn_input[@]}"; do
        $first || printf ','
        first=false

        # Validate numeric
        if [[ "$elem" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            printf '%s' "$elem"
        else
            printf 'null'
        fi
    done

    printf ']'
    return 0
}

# -----------------------------------------------------------------------------
# collection_from_json - Parse JSON array to bash array
# -----------------------------------------------------------------------------
# @description Parse a JSON array into a bash array
# @pre        json is a valid JSON array of strings
# @post       result array populated with parsed values
# @idempotent Yes
# @param      $1 json - JSON array string
# @param      $2 result - Output array (nameref)
# @return     0 on success, 1 on parse error
#
# Usage:
#   collection_from_json '["one","two","three"]' arr
#   # arr=(one two three)
# -----------------------------------------------------------------------------
collection_from_json() {
    local json="$1"
    local -n _cfj_output=$2

    _cfj_output=()

    # Simple JSON array parser (handles basic cases)
    # Remove outer brackets
    json="${json#[}"
    json="${json%]}"

    # Handle empty array
    [[ -z "${json// /}" ]] && return 0

    # Parse string elements (handles escaped quotes)
    local in_string=false
    local current=""
    local escaped=false
    local char
    local i

    for (( i = 0; i < ${#json}; i++ )); do
        char="${json:i:1}"

        if $escaped; then
            current+="$char"
            escaped=false
            continue
        fi

        if [[ "$char" == '\' ]]; then
            escaped=true
            continue
        fi

        if [[ "$char" == '"' ]]; then
            if $in_string; then
                # End of string
                _cfj_output+=("$current")
                current=""
                in_string=false
            else
                # Start of string
                in_string=true
            fi
            continue
        fi

        if $in_string; then
            current+="$char"
        fi
    done

    return 0
}

# =============================================================================
# FOREACH VARIANTS
# =============================================================================

# -----------------------------------------------------------------------------
# array_foreach - Execute function for each element (side effects)
# -----------------------------------------------------------------------------
# @description Execute a function for each element (for side effects)
# @pre        func accepts one argument
# @post       func called once for each element
# @idempotent Depends on func
# @param      $1 arr - Input array (nameref)
# @param      $2 func - Function to call for each element
# @return     0 on success
#
# Usage:
#   log_item() { echo "Processing: $1"; }
#   arr=(a b c)
#   array_foreach arr log_item
# -----------------------------------------------------------------------------
array_foreach() {
    local -n _afe_input=$1
    local func="$2"

    # Contract: func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$func"; then
            _collection_error 1 "func '$func' is not a valid function"
            return 1
        fi
    fi

    local elem
    for elem in "${_afe_input[@]}"; do
        "$func" "$elem"
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_foreach_indexed - Execute function with element and index
# -----------------------------------------------------------------------------
# @description Execute a function for each element with its index
# @pre        func accepts (index, element)
# @post       func called once for each element with index
# @idempotent Depends on func
# @param      $1 arr - Input array (nameref)
# @param      $2 func - Function(index, element) to call
# @return     0 on success
#
# Usage:
#   log_indexed() { echo "[$1]: $2"; }
#   arr=(a b c)
#   array_foreach_indexed arr log_indexed
#   # [0]: a
#   # [1]: b
#   # [2]: c
# -----------------------------------------------------------------------------
array_foreach_indexed() {
    local -n _afei_input=$1
    local func="$2"

    # Contract: func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$func"; then
            _collection_error 1 "func '$func' is not a valid function"
            return 1
        fi
    fi

    local i
    for i in "${!_afei_input[@]}"; do
        "$func" "$i" "${_afei_input[$i]}"
    done

    return 0
}

# =============================================================================
# SPECIALIZED REDUCERS
# =============================================================================

# -----------------------------------------------------------------------------
# array_sum - Sum numeric array elements
# -----------------------------------------------------------------------------
# @description Calculate sum of numeric elements
# @pre        elements are valid integers
# @post       outputs sum
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     Sum of elements
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   sum=$(array_sum arr)
#   # sum=15
# -----------------------------------------------------------------------------
array_sum() {
    local -n _asum_input=$1

    local sum=0
    local elem
    for elem in "${_asum_input[@]}"; do
        if [[ "$elem" =~ ^-?[0-9]+$ ]]; then
            (( sum += elem ))
        fi
    done

    printf '%d' "$sum"
    return 0
}

# -----------------------------------------------------------------------------
# array_product - Calculate product of numeric array elements
# -----------------------------------------------------------------------------
# @description Calculate product of numeric elements
# @pre        elements are valid integers
# @post       outputs product
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     Product of elements
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   product=$(array_product arr)
#   # product=120
# -----------------------------------------------------------------------------
array_product() {
    local -n _aprod_input=$1

    [[ ${#_aprod_input[@]} -eq 0 ]] && { printf '0'; return 0; }

    local product=1
    local elem
    for elem in "${_aprod_input[@]}"; do
        if [[ "$elem" =~ ^-?[0-9]+$ ]]; then
            (( product *= elem ))
        fi
    done

    printf '%d' "$product"
    return 0
}

# -----------------------------------------------------------------------------
# array_join - Join array elements with separator
# -----------------------------------------------------------------------------
# @description Join array elements into a string with separator
# @pre        none
# @post       outputs joined string
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 separator - String to place between elements (default: ",")
# @stdout     Joined string
# @return     0 on success
#
# Usage:
#   arr=(one two three)
#   result=$(array_join arr ", ")
#   # result="one, two, three"
# -----------------------------------------------------------------------------
array_join() {
    local -n _aj_input=$1
    local separator="${2:-,}"

    local first=true
    local elem
    for elem in "${_aj_input[@]}"; do
        $first || printf '%s' "$separator"
        first=false
        printf '%s' "$elem"
    done

    return 0
}

# =============================================================================
# UNIQUE AND SET OPERATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# array_unique - Remove duplicate elements
# -----------------------------------------------------------------------------
# @description Remove duplicate elements, preserving first occurrence
# @pre        none
# @post       result contains unique elements in original order
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=(1 2 2 3 1 4)
#   array_unique arr result
#   # result=(1 2 3 4)
# -----------------------------------------------------------------------------
array_unique() {
    local -n _au_input=$1
    local -n _au_output=$2

    _au_output=()
    declare -A seen

    local elem
    for elem in "${_au_input[@]}"; do
        if [[ -z "${seen[$elem]:-}" ]]; then
            seen[$elem]=1
            _au_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_unique_by - Remove duplicates by key function
# -----------------------------------------------------------------------------
# @description Remove duplicates based on key function result
# @pre        key_func outputs a string key for each element
# @post       result contains first element for each unique key
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @param      $2 key_func - Function to extract key
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   first_char() { printf '%s' "${1:0:1}"; }
#   arr=(apple apricot banana blueberry cherry)
#   array_unique_by arr first_char result
#   # result=(apple banana cherry)
# -----------------------------------------------------------------------------
array_unique_by() {
    local -n _aub_input=$1
    local key_func="$2"
    local -n _aub_output=$3

    # Contract: key_func must be callable
    if [[ "$COLLECTION_CONTRACTS" == "1" ]]; then
        if ! _collection_is_callable "$key_func"; then
            _collection_error 1 "key_func '$key_func' is not a valid function"
            return 1
        fi
    fi

    _aub_output=()
    declare -A seen

    local elem key
    for elem in "${_aub_input[@]}"; do
        key=$("$key_func" "$elem")
        if [[ -z "${seen[$key]:-}" ]]; then
            seen[$key]=1
            _aub_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_intersect - Find common elements between two arrays
# -----------------------------------------------------------------------------
# @description Find elements that exist in both arrays
# @pre        none
# @post       result contains elements present in both arrays
# @idempotent Yes
# @param      $1 arr1 - First input array (nameref)
# @param      $2 arr2 - Second input array (nameref)
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   a=(1 2 3 4)
#   b=(3 4 5 6)
#   array_intersect a b result
#   # result=(3 4)
# -----------------------------------------------------------------------------
array_intersect() {
    local -n _ai_arr1=$1
    local -n _ai_arr2=$2
    local -n _ai_output=$3

    _ai_output=()
    declare -A in_arr2

    # Build lookup from arr2
    local elem
    for elem in "${_ai_arr2[@]}"; do
        in_arr2[$elem]=1
    done

    # Find common elements
    for elem in "${_ai_arr1[@]}"; do
        if [[ -n "${in_arr2[$elem]:-}" ]]; then
            _ai_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_difference - Find elements in first array not in second
# -----------------------------------------------------------------------------
# @description Find elements that exist in arr1 but not in arr2
# @pre        none
# @post       result contains elements in arr1 but not arr2
# @idempotent Yes
# @param      $1 arr1 - First input array (nameref)
# @param      $2 arr2 - Second input array (nameref)
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   a=(1 2 3 4)
#   b=(3 4 5 6)
#   array_difference a b result
#   # result=(1 2)
# -----------------------------------------------------------------------------
array_difference() {
    local -n _adiff_arr1=$1
    local -n _adiff_arr2=$2
    local -n _adiff_output=$3

    _adiff_output=()
    declare -A in_arr2

    # Build lookup from arr2
    local elem
    for elem in "${_adiff_arr2[@]}"; do
        in_arr2[$elem]=1
    done

    # Find elements not in arr2
    for elem in "${_adiff_arr1[@]}"; do
        if [[ -z "${in_arr2[$elem]:-}" ]]; then
            _adiff_output+=("$elem")
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_symmetric_difference - Find elements in either array but not both
# -----------------------------------------------------------------------------
# @description Find elements that exist in exactly one of the arrays
# @pre        none
# @post       result contains elements unique to each array
# @idempotent Yes
# @param      $1 arr1 - First input array (nameref)
# @param      $2 arr2 - Second input array (nameref)
# @param      $3 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   a=(1 2 3 4)
#   b=(3 4 5 6)
#   array_symmetric_difference a b result
#   # result=(1 2 5 6)
# -----------------------------------------------------------------------------
array_symmetric_difference() {
    local -n _asd_arr1=$1
    local -n _asd_arr2=$2
    local -n _asd_output=$3

    local diff1=() diff2=()
    array_difference "$1" "$2" diff1
    array_difference "$2" "$1" diff2

    _asd_output=("${diff1[@]}" "${diff2[@]}")

    return 0
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# array_reverse - Reverse array order
# -----------------------------------------------------------------------------
# @description Reverse the order of array elements
# @pre        none
# @post       result contains elements in reverse order
# @idempotent No - double reverse restores original
# @param      $1 arr - Input array (nameref)
# @param      $2 result - Output array (nameref)
# @return     0 on success
#
# Usage:
#   arr=(1 2 3 4 5)
#   array_reverse arr result
#   # result=(5 4 3 2 1)
# -----------------------------------------------------------------------------
array_reverse() {
    local -n _arev_input=$1
    local -n _arev_output=$2

    _arev_output=()

    local i
    for (( i = ${#_arev_input[@]} - 1; i >= 0; i-- )); do
        _arev_output+=("${_arev_input[$i]}")
    done

    return 0
}

# -----------------------------------------------------------------------------
# array_first - Get first element
# -----------------------------------------------------------------------------
# @description Get the first element of an array
# @pre        none
# @post       outputs first element if exists
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     First element
# @return     0 if exists, 1 if empty
#
# Usage:
#   arr=(a b c)
#   first=$(array_first arr)
#   # first=a
# -----------------------------------------------------------------------------
array_first() {
    local -n _afirst_input=$1

    [[ ${#_afirst_input[@]} -eq 0 ]] && return 1
    printf '%s' "${_afirst_input[0]}"
    return 0
}

# -----------------------------------------------------------------------------
# array_last - Get last element
# -----------------------------------------------------------------------------
# @description Get the last element of an array
# @pre        none
# @post       outputs last element if exists
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     Last element
# @return     0 if exists, 1 if empty
#
# Usage:
#   arr=(a b c)
#   last=$(array_last arr)
#   # last=c
# -----------------------------------------------------------------------------
array_last() {
    local -n _alast_input=$1

    local len=${#_alast_input[@]}
    [[ $len -eq 0 ]] && return 1
    printf '%s' "${_alast_input[$((len - 1))]}"
    return 0
}

# -----------------------------------------------------------------------------
# array_nth - Get element at index
# -----------------------------------------------------------------------------
# @description Get the element at a specific index
# @pre        index >= 0
# @post       outputs element at index if exists
# @idempotent Yes
# @param      $1 n - Index (0-based)
# @param      $2 arr - Input array (nameref)
# @stdout     Element at index
# @return     0 if exists, 1 if out of bounds
#
# Usage:
#   arr=(a b c d e)
#   elem=$(array_nth 2 arr)
#   # elem=c
# -----------------------------------------------------------------------------
array_nth() {
    local n="$1"
    local -n _anth_input=$2

    [[ ! "$n" =~ ^[0-9]+$ ]] && return 1
    [[ $n -ge ${#_anth_input[@]} ]] && return 1

    printf '%s' "${_anth_input[$n]}"
    return 0
}

# -----------------------------------------------------------------------------
# array_is_empty - Check if array is empty
# -----------------------------------------------------------------------------
# @description Test if array has no elements
# @pre        none
# @post       none
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @return     0 if empty, 1 if has elements
#
# Usage:
#   arr=()
#   array_is_empty arr && echo "empty"
# -----------------------------------------------------------------------------
array_is_empty() {
    local -n _aie_input=$1
    [[ ${#_aie_input[@]} -eq 0 ]]
}

# -----------------------------------------------------------------------------
# array_length - Get array length
# -----------------------------------------------------------------------------
# @description Get the number of elements in an array
# @pre        none
# @post       outputs element count
# @idempotent Yes
# @param      $1 arr - Input array (nameref)
# @stdout     Number of elements
# @return     0 on success
#
# Usage:
#   arr=(a b c d e)
#   len=$(array_length arr)
#   # len=5
# -----------------------------------------------------------------------------
array_length() {
    local -n _alen_input=$1
    printf '%d' "${#_alen_input[@]}"
    return 0
}


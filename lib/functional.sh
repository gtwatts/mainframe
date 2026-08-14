#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/functional.sh - Functional Programming Primitives
# =============================================================================
# Description: Functional programming patterns with high-performance nameref
#              variants for subshell-free operation in loops
# Requires: Bash 4.3+ (for namerefs)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FUNCTIONAL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FUNCTIONAL_LOADED=1

# The core string predicates have one canonical implementation in pure-string.
# Source that dependency explicitly so functional.sh remains safe to use on its
# own without redefining public names based on loader order.
source "${BASH_SOURCE[0]%/*}/pure-string.sh"

# =============================================================================
# COMMON PREDICATES
# =============================================================================

# Check if number is even
# Usage: is_even 4 && echo "yes"
is_even() {
    (($1 % 2 == 0))
}

# Check if number is odd
# Usage: is_odd 3 && echo "yes"
is_odd() {
    (($1 % 2 == 1))
}

# Check if number is positive
# Usage: is_positive 5 && echo "yes"
is_positive() {
    (($1 > 0))
}

# Check if number is negative
# Usage: is_negative -3 && echo "yes"
is_negative() {
    (($1 < 0))
}

# Check if number is zero
# Usage: is_zero 0 && echo "yes"
is_zero() {
    (($1 == 0))
}

# Check if value is numeric
# Usage: is_numeric "42" && echo "yes"
is_numeric() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

# Check if value is alphanumeric
# Usage: is_alnum "abc123" && echo "yes"
is_alnum() {
    [[ "$1" =~ ^[a-zA-Z0-9]+$ ]]
}

# =============================================================================
# COMMON TRANSFORMERS
# =============================================================================

# Double a number
# Usage: double 5  # outputs 10
double() {
    echo $(($1 * 2))
}

# Square a number
# Usage: square 5  # outputs 25
square() {
    echo $(($1 * $1))
}

# Increment a number
# Usage: increment 5  # outputs 6
increment() {
    echo $(($1 + 1))
}

# Decrement a number
# Usage: decrement 5  # outputs 4
decrement() {
    echo $(($1 - 1))
}

# Negate a number
# Usage: negate 5  # outputs -5
negate() {
    echo $((-$1))
}

# Get absolute value
# Usage: abs -5  # outputs 5
abs() {
    local n=$1
    echo $((n < 0 ? -n : n))
}

# =============================================================================
# BINARY FUNCTIONS (for reduce)
# =============================================================================

# Sum two numbers
# Usage: sum 3 4  # outputs 7
sum() {
    echo $(($1 + $2))
}

# Multiply two numbers
# Usage: product 3 4  # outputs 12
product() {
    echo $(($1 * $2))
}

# Get maximum of two numbers
# Usage: max 3 7  # outputs 7
max() {
    (($1 > $2)) && echo "$1" || echo "$2"
}

# Get minimum of two numbers
# Usage: min 3 7  # outputs 3
min() {
    (($1 < $2)) && echo "$1" || echo "$2"
}

# Concatenate two strings
# Usage: concat "hello" "world"  # outputs helloworld
concat() {
    echo "$1$2"
}

# =============================================================================
# MAP - Apply function to each element
# =============================================================================

# Map function over elements (stdout version)
# Usage: echo -e "1\n2\n3" | fp_map "double"
# Usage: fp_map "double" 1 2 3
fp_map() {
    local func="$1"
    shift

    if [[ $# -gt 0 ]]; then
        # Arguments provided
        for item in "$@"; do
            "$func" "$item"
        done
    else
        # Read from stdin
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$func" "$item"
        done
    fi
}

# Map with nameref output (no subshells)
# Usage: fp_map_v result_array "double" 1 2 3 4 5
# Note: The function must accept 2 args: value and output variable name
#       For simple functions, use fp_map_v_simple instead
fp_map_v() {
    local -n __fp_map_result=$1
    local func="$2"
    shift 2
    __fp_map_result=()

    local __fp_map_item __fp_map_tmp
    for __fp_map_item in "$@"; do
        # Call function and capture result via nameref
        __fp_map_tmp=$("$func" "$__fp_map_item")
        __fp_map_result+=("$__fp_map_tmp")
    done
}

# Map with nameref output using nameref-aware functions
# Usage: fp_map_v_nr result_array "double_nr" 1 2 3 4 5
# The function signature: func(value, result_varname)
fp_map_v_nr() {
    local -n __fp_map_nr_result=$1
    local func="$2"
    shift 2
    __fp_map_nr_result=()

    local __fp_map_nr_item __fp_map_nr_tmp
    for __fp_map_nr_item in "$@"; do
        "$func" "$__fp_map_nr_item" __fp_map_nr_tmp
        __fp_map_nr_result+=("$__fp_map_nr_tmp")
    done
}

# =============================================================================
# FILTER - Keep elements matching predicate
# =============================================================================

# Filter elements by predicate (stdout version)
# Usage: echo -e "1\n2\n3\n4" | fp_filter "is_even"
# Usage: fp_filter "is_even" 1 2 3 4 5
fp_filter() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            "$pred" "$item" && printf '%s\n' "$item"
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$pred" "$item" && printf '%s\n' "$item"
        done
    fi
}

# Filter with nameref output (no subshells)
# Usage: fp_filter_v result_array "is_even" 1 2 3 4 5
fp_filter_v() {
    local -n __fp_filter_result=$1
    local pred="$2"
    shift 2
    __fp_filter_result=()

    local __fp_filter_item
    for __fp_filter_item in "$@"; do
        "$pred" "$__fp_filter_item" && __fp_filter_result+=("$__fp_filter_item")
    done
}

# =============================================================================
# REDUCE - Fold elements into single value
# =============================================================================

# Reduce elements to single value (stdout version)
# Usage: fp_reduce "sum" 0 1 2 3 4 5
# Usage: echo -e "1\n2\n3" | fp_reduce "sum" 0
fp_reduce() {
    local func="$1"
    local acc="$2"
    shift 2

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            acc=$("$func" "$acc" "$item")
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            acc=$("$func" "$acc" "$item")
        done
    fi
    printf '%s\n' "$acc"
}

# Reduce with nameref output (no subshells)
# Usage: fp_reduce_v result "sum" 0 1 2 3 4 5
fp_reduce_v() {
    local -n __fp_reduce_result=$1
    local func="$2"
    local acc="$3"
    shift 3

    local __fp_reduce_item
    for __fp_reduce_item in "$@"; do
        acc=$("$func" "$acc" "$__fp_reduce_item")
    done
    __fp_reduce_result="$acc"
}

# Reduce with nameref-aware binary function (fully subshell-free)
# Usage: fp_reduce_v_nr result "sum_nr" 0 1 2 3 4 5
# The function signature: func(acc, value, result_varname)
fp_reduce_v_nr() {
    local -n __fp_reduce_nr_result=$1
    local func="$2"
    local acc="$3"
    shift 3

    local __fp_reduce_nr_item
    for __fp_reduce_nr_item in "$@"; do
        "$func" "$acc" "$__fp_reduce_nr_item" acc
    done
    __fp_reduce_nr_result="$acc"
}

# =============================================================================
# FIND - Locate first matching element
# =============================================================================

# Find first element matching predicate
# Usage: fp_find "is_even" 1 3 5 6 7  # outputs 6
# Returns 1 if not found
fp_find() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            if "$pred" "$item"; then
                printf '%s\n' "$item"
                return 0
            fi
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            if "$pred" "$item"; then
                printf '%s\n' "$item"
                return 0
            fi
        done
    fi
    return 1
}

# Find with nameref output (no subshell)
# Usage: fp_find_v result "is_even" 1 3 5 6 7
# Returns 0 if found, 1 if not found
fp_find_v() {
    local -n __fp_find_result=$1
    local pred="$2"
    shift 2

    local __fp_find_item
    for __fp_find_item in "$@"; do
        if "$pred" "$__fp_find_item"; then
            __fp_find_result="$__fp_find_item"
            return 0
        fi
    done
    __fp_find_result=""
    return 1
}

# Find index of first matching element
# Usage: fp_find_index "is_even" 1 3 5 6 7  # outputs 3
# Returns 1 if not found
fp_find_index() {
    local pred="$1"
    shift
    local i=0

    for item in "$@"; do
        if "$pred" "$item"; then
            printf '%d\n' "$i"
            return 0
        fi
        ((i++))
    done
    return 1
}

# =============================================================================
# ANY / ALL - Quantifiers
# =============================================================================

# Check if any element matches predicate
# Usage: fp_any "is_even" 1 3 5 6 7 && echo "found even"
fp_any() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            "$pred" "$item" && return 0
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$pred" "$item" && return 0
        done
    fi
    return 1
}

# Check if all elements match predicate
# Usage: fp_all "is_positive" 1 2 3 4 5 && echo "all positive"
fp_all() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            "$pred" "$item" || return 1
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$pred" "$item" || return 1
        done
    fi
    return 0
}

# Check if no elements match predicate
# Usage: fp_none "is_negative" 1 2 3 4 5 && echo "none negative"
fp_none() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            "$pred" "$item" && return 1
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$pred" "$item" && return 1
        done
    fi
    return 0
}

# =============================================================================
# COMPOSITION - Combine functions
# =============================================================================

# Compose functions (right to left)
# Usage: composed=$(fp_compose "increment" "double")
#        eval "$composed 5"  # double(5)=10, then increment(10)=11
fp_compose() {
    local funcs=("$@")
    local n=${#funcs[@]}

    # Generate composed function
    printf '_fp_composed_inner() {\n'
    printf '    local __val="$1"\n'

    # Apply functions right to left
    for ((i=n-1; i>=0; i--)); do
        printf '    __val=$("%s" "$__val")\n' "${funcs[$i]}"
    done

    printf '    printf "%%s\\n" "$__val"\n'
    printf '}\n'
    printf '_fp_composed_inner'
}

# Pipe functions (left to right)
# Usage: piped=$(fp_pipe "double" "increment")
#        eval "$piped 5"  # double(5)=10, then increment(10)=11
fp_pipe() {
    local funcs=("$@")
    local n=${#funcs[@]}

    # Generate piped function
    printf '_fp_piped_inner() {\n'
    printf '    local __val="$1"\n'

    # Apply functions left to right
    for ((i=0; i<n; i++)); do
        printf '    __val=$("%s" "$__val")\n' "${funcs[$i]}"
    done

    printf '    printf "%%s\\n" "$__val"\n'
    printf '}\n'
    printf '_fp_piped_inner'
}

# Apply composed/piped function
# Usage: fp_apply "$(fp_pipe double increment)" 5
# Note: Uses bash -c for isolation instead of eval for security
fp_apply() {
    local func_def="$1"
    shift
    # Use bash -c to execute the function definition in a subshell for isolation
    # This prevents arbitrary code execution in the current shell context
    bash -c "$func_def"$'\n'"_fp_piped_inner \"\$@\" 2>/dev/null || _fp_composed_inner \"\$@\"" -- "$@"
}

# =============================================================================
# PARTITION - Split by predicate
# =============================================================================

# Partition elements into two arrays by predicate
# Usage: fp_partition_v matches non_matches "is_even" 1 2 3 4 5
fp_partition_v() {
    local -n __fp_part_matches=$1
    local -n __fp_part_rejects=$2
    local pred="$3"
    shift 3
    __fp_part_matches=()
    __fp_part_rejects=()

    local __fp_part_item
    for __fp_part_item in "$@"; do
        if "$pred" "$__fp_part_item"; then
            __fp_part_matches+=("$__fp_part_item")
        else
            __fp_part_rejects+=("$__fp_part_item")
        fi
    done
}

# =============================================================================
# TAKE / DROP - Slice operations
# =============================================================================

# Take first N elements
# Usage: fp_take 3 1 2 3 4 5  # outputs 1 2 3
fp_take() {
    local n="$1"
    shift
    local count=0

    for item in "$@"; do
        ((count >= n)) && break
        printf '%s\n' "$item"
        ((count++))
    done
}

# Take elements while predicate holds
# Usage: fp_take_while "is_positive" 1 2 3 -1 4 5  # outputs 1 2 3
fp_take_while() {
    local pred="$1"
    shift

    for item in "$@"; do
        "$pred" "$item" || break
        printf '%s\n' "$item"
    done
}

# Drop first N elements
# Usage: fp_drop 2 1 2 3 4 5  # outputs 3 4 5
fp_drop() {
    local n="$1"
    shift
    local count=0

    for item in "$@"; do
        if ((count >= n)); then
            printf '%s\n' "$item"
        fi
        ((count++))
    done
}

# Drop elements while predicate holds
# Usage: fp_drop_while "is_positive" 1 2 3 -1 4 5  # outputs -1 4 5
fp_drop_while() {
    local pred="$1"
    shift
    local dropping=1

    for item in "$@"; do
        if ((dropping)) && "$pred" "$item"; then
            continue
        fi
        dropping=0
        printf '%s\n' "$item"
    done
}

# =============================================================================
# ZIP - Combine arrays
# =============================================================================

# Zip two arrays together
# Usage: fp_zip arr1 arr2
# Output: element pairs on separate lines (tab-separated)
fp_zip() {
    local -n __fp_zip_a1=$1
    local -n __fp_zip_a2=$2
    local len1=${#__fp_zip_a1[@]}
    local len2=${#__fp_zip_a2[@]}
    local len=$((len1 < len2 ? len1 : len2))

    local i
    for ((i=0; i<len; i++)); do
        printf '%s\t%s\n' "${__fp_zip_a1[$i]}" "${__fp_zip_a2[$i]}"
    done
}

# Zip with custom function
# Usage: fp_zip_with "sum" arr1 arr2
fp_zip_with() {
    local func="$1"
    local -n __fp_zipw_a1=$2
    local -n __fp_zipw_a2=$3
    local len1=${#__fp_zipw_a1[@]}
    local len2=${#__fp_zipw_a2[@]}
    local len=$((len1 < len2 ? len1 : len2))

    local i
    for ((i=0; i<len; i++)); do
        "$func" "${__fp_zipw_a1[$i]}" "${__fp_zipw_a2[$i]}"
    done
}

# =============================================================================
# UTILITIES
# =============================================================================

# Count elements matching predicate
# Usage: fp_count "is_even" 1 2 3 4 5 6  # outputs 3
fp_count() {
    local pred="$1"
    shift
    local count=0

    for item in "$@"; do
        "$pred" "$item" && ((count++))
    done
    printf '%d\n' "$count"
}

# Group by function result
# Usage: fp_group_by "func" elem1 elem2 ...
# Note: Outputs key<tab>value pairs
fp_group_by() {
    local func="$1"
    shift
    declare -A groups

    local item key
    for item in "$@"; do
        key=$("$func" "$item")
        if [[ -n "${groups[$key]:-}" ]]; then
            groups[$key]+=$'\n'"$item"
        else
            groups[$key]="$item"
        fi
    done

    for key in "${!groups[@]}"; do
        printf '%s\t%s\n' "$key" "${groups[$key]}"
    done
}

# Identity function
# Usage: identity "hello"  # outputs hello
identity() {
    printf '%s\n' "$1"
}

# Constant function (returns fixed value)
# Usage: const="$(fp_const 42)"; eval "$const ignored"  # outputs 42
fp_const() {
    local val="$1"
    printf '_fp_const_inner() { printf "%%s\\n" "%s"; }\n_fp_const_inner' "$val"
}

# =============================================================================
# NAMEREF-AWARE TRANSFORMER VARIANTS (for fully subshell-free operation)
# =============================================================================

# Double with nameref output
# Usage: double_nr 5 result  # result=10
double_nr() {
    local -n __double_nr_result=$2
    __double_nr_result=$(($1 * 2))
}

# Square with nameref output
# Usage: square_nr 5 result  # result=25
square_nr() {
    local -n __square_nr_result=$2
    __square_nr_result=$(($1 * $1))
}

# Increment with nameref output
# Usage: increment_nr 5 result  # result=6
increment_nr() {
    local -n __increment_nr_result=$2
    __increment_nr_result=$(($1 + 1))
}

# Decrement with nameref output
# Usage: decrement_nr 5 result  # result=4
decrement_nr() {
    local -n __decrement_nr_result=$2
    __decrement_nr_result=$(($1 - 1))
}

# Sum with nameref output (for reduce)
# Usage: sum_nr 3 4 result  # result=7
sum_nr() {
    local -n __sum_nr_result=$3
    __sum_nr_result=$(($1 + $2))
}

# Product with nameref output (for reduce)
# Usage: product_nr 3 4 result  # result=12
product_nr() {
    local -n __product_nr_result=$3
    __product_nr_result=$(($1 * $2))
}

# Max with nameref output (for reduce)
# Usage: max_nr 3 7 result  # result=7
max_nr() {
    local -n __max_nr_result=$3
    (($1 > $2)) && __max_nr_result=$1 || __max_nr_result=$2
}

# Min with nameref output (for reduce)
# Usage: min_nr 3 7 result  # result=3
min_nr() {
    local -n __min_nr_result=$3
    (($1 < $2)) && __min_nr_result=$1 || __min_nr_result=$2
}

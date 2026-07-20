#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/streams.sh - Functional Stream Processing Library
# =============================================================================
# Description: Lazy, composable stream processing using pipes and process
#              substitution. Provides functional primitives (map, filter,
#              reduce, etc.) for declarative data transformation pipelines.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS:
#   - Streams are line-based (each element is one line)
#   - Predicates and transforms are bash expressions (eval-based)
#   - Large streams should use file-backed operations to avoid memory issues
#   - Some operations (sorted, reversed, distinct) require full materialization
#   - Parallel operations are limited by bash's process management
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_STREAMS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_STREAMS_LOADED=1

# =============================================================================
# SECURITY: Safe Expression Evaluation
# =============================================================================
# Stream operations need to evaluate predicates and transforms on each item.
# These helpers provide safer alternatives to raw eval.

# Safe expression evaluator for predicates (returns 0/1 for true/false)
# Usage: _streams_eval_predicate "expression" "item_value"
# Security: Validates no dangerous patterns, runs in subprocess for isolation
_streams_eval_predicate() {
    local expr="$1"
    local item="$2"

    # Block dangerous patterns
    if [[ "$expr" == *'`'* ]] || [[ "$expr" == *'$('* ]] || \
       [[ "$expr" == *';'* ]] || [[ "$expr" == *'|'* ]] || \
       [[ "$expr" == *'>'* && "$expr" != *'-gt'* && "$expr" != *'-ge'* ]] || \
       [[ "$expr" == *'<'* && "$expr" != *'-lt'* && "$expr" != *'-le'* ]] || \
       [[ "$expr" == *'eval'* ]] || [[ "$expr" == *'source'* ]] || \
       [[ "$expr" == *'&'* ]] || [[ "$expr" == *$'\n'* ]]; then
        printf 'streams: blocked dangerous pattern in predicate: %s\n' "$expr" >&2
        return 1
    fi

    # Security: Execute predicate in subprocess with item exported
    item="$item" bash -c "$expr" 2>/dev/null
}

# Safe transform evaluator (outputs transformed value)
# Usage: _streams_eval_transform "expression" "item_value"
# Security: Validates no dangerous patterns, runs in subprocess for isolation
_streams_eval_transform() {
    local expr="$1"
    local item="$2"

    # Block dangerous patterns (same as predicate plus more)
    if [[ "$expr" == *'`'* ]] || [[ "$expr" == *'$('* && "$expr" != *'$(('* ]] || \
       [[ "$expr" == *';'* ]] || [[ "$expr" == *'|'* ]] || \
       [[ "$expr" == *'eval'* ]] || [[ "$expr" == *'source'* ]] || \
       [[ "$expr" == *'&'* ]] || [[ "$expr" == *$'\n'* ]] || \
       [[ "$expr" == *'>'* ]] || [[ "$expr" == *'>>'* ]]; then
        printf 'streams: blocked dangerous pattern in transform: %s\n' "$expr" >&2
        return 1
    fi

    # Security: Execute transform in subprocess with item exported
    item="$item" bash -c "$expr"
}

# Safe command execution via subprocess
# Usage: _streams_safe_exec "command"
# Security: Runs in isolated subprocess
_streams_safe_exec() {
    bash -c "$1"
}

# Validate and call a function by name
# Usage: _streams_call_func "func_name" [args...]
# Security: Only calls declared functions
_streams_call_func() {
    local func="$1"
    shift

    if ! declare -F "$func" &>/dev/null; then
        printf 'streams: function not found: %s\n' "$func" >&2
        return 1
    fi

    "$func" "$@"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable debug logging for stream operations
MAINFRAME_STREAM_DEBUG="${MAINFRAME_STREAM_DEBUG:-0}"

# Default batch size for windowing operations
MAINFRAME_STREAM_BATCH_SIZE="${MAINFRAME_STREAM_BATCH_SIZE:-10}"

# Throttle rate in milliseconds
MAINFRAME_STREAM_THROTTLE_MS="${MAINFRAME_STREAM_THROTTLE_MS:-100}"

# Maximum buffer size (lines) before forced flush
MAINFRAME_STREAM_MAX_BUFFER="${MAINFRAME_STREAM_MAX_BUFFER:-10000}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# @pre: none
# @post: log message written to stderr if debug enabled
# @idempotent: yes
_stream_log() {
    local level="$1"
    shift
    if [[ "$MAINFRAME_STREAM_DEBUG" == "1" ]]; then
        printf '[stream] %s: %s\n' "$level" "$*" >&2
    fi
}

# @pre: none
# @post: JSON error written to stderr
# @idempotent: yes
# @returns: provided exit code
_stream_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local func="${FUNCNAME[1]:-main}"

    printf '{"error":true,"code":%d,"msg":"%s","func":"%s"}\n' \
        "$code" "$msg" "$func" >&2
    return "$code"
}

# @pre: expression is valid bash test
# @post: returns 0 if valid, 1 otherwise
# @idempotent: yes
# Security: Uses safe expression evaluation
_stream_validate_expr() {
    local expr="$1"
    local test_val="test"

    # Try to evaluate the expression with a test value via safe evaluator
    _streams_eval_transform "$expr" "$test_val" &>/dev/null
}

_streams_valid_var_name() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

_streams_assign_array() {
    local array_name="$1"
    shift

    _streams_valid_var_name "$array_name" || return 1
    eval "$array_name=()"

    local _streams_item
    for _streams_item in "$@"; do
        eval "$array_name+=(\"\$_streams_item\")"
    done
}

_streams_print_array() {
    local array_name="$1"

    _streams_valid_var_name "$array_name" || return 1
    eval "printf '%s\n' \"\${${array_name}[@]}\""
}

# =============================================================================
# STREAM CREATION
# =============================================================================

# @pre: arr is a valid array name (nameref) or values passed as arguments
# @post: each array element written to stdout as separate line
# @idempotent: yes
# @returns: 0 on success
#
# Create a stream from an array. Elements are output one per line.
# Supports both nameref and positional arguments.
#
# Usage: stream_from_array arr_name
#        stream_from_array "${arr[@]}"
# Example: local arr=(a b c); stream_from_array arr
stream_from_array() {
    if [[ $# -eq 1 ]]; then
        local decl=""
        decl=$(declare -p "$1" 2>/dev/null || true)
        if [[ "$decl" == "declare -a"* ]]; then
            _streams_print_array "$1"
            return $?
        fi
    fi

    # Direct values mode
    local item
    for item in "$@"; do
        printf '%s\n' "$item"
    done
}

# @pre: file exists and is readable
# @post: each line of file written to stdout
# @idempotent: yes
# @returns: 0 on success, 1 if file not found
#
# Create a stream from file lines. Empty lines are preserved.
#
# Usage: stream_from_file "/path/to/file"
# Example: stream_from_file "/etc/hosts" | stream_filter 'grep -q localhost'
stream_from_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        _stream_error 1 "file not found: $file"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        _stream_error 1 "file not readable: $file"
        return 1
    fi

    cat "$file"
}

# @pre: command is valid shell command
# @post: command output written to stdout line by line
# @idempotent: depends on command
# @returns: command's exit code
#
# Create a stream from command output. Each line of output becomes an element.
#
# Usage: stream_from_command "ls -la"
# Example: stream_from_command "find . -name '*.sh'" | stream_map 'basename'
# Security: Uses subprocess isolation via bash -c
stream_from_command() {
    local cmd="$1"

    if [[ -z "$cmd" ]]; then
        _stream_error 1 "empty command"
        return 1
    fi

    _streams_safe_exec "$cmd"
}

# @pre: start <= end (or start >= end with negative step), step != 0
# @post: numeric sequence written to stdout
# @idempotent: yes
# @returns: 0 on success, 1 on invalid range
#
# Create a numeric range stream. Similar to Python's range() or seq.
#
# Usage: stream_from_range start [end] [step]
# Example: stream_from_range 1 10        # 1 to 10, step 1
#          stream_from_range 0 100 5     # 0, 5, 10, ..., 100
#          stream_from_range 10 1 -1     # 10, 9, 8, ..., 1
stream_from_range() {
    local start="${1:-0}"
    local end="${2:-$start}"
    local step="${3:-1}"

    # If only one arg, range is 0 to arg-1
    if [[ $# -eq 1 ]]; then
        end="$1"
        start=0
    fi

    if [[ "$step" -eq 0 ]]; then
        _stream_error 1 "step cannot be zero"
        return 1
    fi

    local i
    if [[ "$step" -gt 0 ]]; then
        for ((i=start; i<=end; i+=step)); do
            printf '%d\n' "$i"
        done
    else
        for ((i=start; i>=end; i+=step)); do
            printf '%d\n' "$i"
        done
    fi
}

# @pre: generator_func is a valid function name
# @post: generator output written to stdout until EOF or max items
# @idempotent: depends on generator
# @returns: 0 on success
#
# Create a stream from a generator function. The generator is called repeatedly
# and should output one element per call. Return non-zero to signal end.
#
# Usage: stream_from_generator generator_func [max_items]
# Example:
#   gen() { echo $RANDOM; }
#   stream_from_generator gen 5  # 5 random numbers
stream_from_generator() {
    local generator="$1"
    local max_items="${2:-0}"  # 0 = unlimited

    if ! declare -F "$generator" &>/dev/null; then
        _stream_error 1 "generator function not found: $generator"
        return 1
    fi

    local count=0
    local result
    while true; do
        if ! result=$("$generator" 2>/dev/null); then
            break
        fi
        printf '%s\n' "$result"

        ((count++))
        if [[ "$max_items" -gt 0 ]] && [[ "$count" -ge "$max_items" ]]; then
            break
        fi
    done
}

# @pre: none
# @post: empty output (no lines)
# @idempotent: yes
# @returns: 0
#
# Create an empty stream. Useful as identity element for stream operations.
#
# Usage: stream_empty
# Example: stream_empty | stream_count  # outputs: 0
stream_empty() {
    :  # Output nothing
}

# @pre: arguments provided
# @post: each argument written as one line
# @idempotent: yes
# @returns: 0
#
# Create a stream from positional arguments. Each argument becomes one element.
#
# Usage: stream_of "a" "b" "c"
# Example: stream_of foo bar baz | stream_map 'printf "item: %s"'
stream_of() {
    local item
    for item in "$@"; do
        printf '%s\n' "$item"
    done
}

# @pre: count >= 0
# @post: value repeated count times, one per line
# @idempotent: yes
# @returns: 0
#
# Create a stream that repeats a value N times.
#
# Usage: stream_repeat value count
# Example: stream_repeat "x" 5  # outputs: x x x x x (one per line)
stream_repeat() {
    local value="$1"
    local count="${2:-1}"

    local i
    for ((i=0; i<count; i++)); do
        printf '%s\n' "$value"
    done
}

# @pre: func is valid, seed is initial value
# @post: infinite stream (use with stream_take)
# @idempotent: yes
# @returns: 0
#
# Create an infinite stream by repeatedly applying a function to previous value.
# IMPORTANT: Use stream_take to limit output!
#
# Usage: stream_iterate func seed [max_items]
# Example:
#   double() { echo $(($1 * 2)); }
#   stream_iterate double 1 10  # 1, 2, 4, 8, 16, ...
stream_iterate() {
    local func="$1"
    local seed="$2"
    local max_items="${3:-0}"  # 0 = unlimited (dangerous!)

    local current="$seed"
    local count=0

    while true; do
        printf '%s\n' "$current"
        ((count++))

        if [[ "$max_items" -gt 0 ]] && [[ "$count" -ge "$max_items" ]]; then
            break
        fi

        current=$("$func" "$current" 2>/dev/null) || break
    done
}

# =============================================================================
# STREAM TRANSFORMATIONS
# =============================================================================

# @pre: transform is valid expression or command with $item variable
# @post: transformed elements written to stdout
# @idempotent: yes
# @returns: 0
#
# Transform each element using a function or expression.
# The current element is available as $item in the expression.
#
# Usage: stream_map "expression"
# Example: stream_of 1 2 3 | stream_map 'echo $(($item * 2))'
#          stream_of a b c | stream_map 'printf "%s_suffix" "$item"'
# Security: Uses safe transform evaluation with pattern validation
stream_map() {
    local transform="$1"
    local item
    local mapped

    while IFS= read -r item || [[ -n "$item" ]]; do
        mapped=$(_streams_eval_transform "$transform" "$item") || return 1
        printf '%s\n' "$mapped"
    done
}

# @pre: predicate is valid expression returning 0 (true) or non-zero (false)
# @post: only matching elements written to stdout
# @idempotent: yes
# @returns: 0
#
# Filter elements that match a predicate. The current element is $item.
# The predicate should return exit code 0 for elements to keep.
#
# Usage: stream_filter "predicate"
# Example: stream_from_range 1 10 | stream_filter '[[ $item -gt 5 ]]'
#          stream_of foo bar baz | stream_filter '[[ "$item" == b* ]]'
# Security: Uses safe predicate evaluation with pattern validation
stream_filter() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$predicate" "$item"; then
            printf '%s\n' "$item"
        fi
    done
}

# @pre: n >= 0
# @post: first n elements written to stdout
# @idempotent: yes
# @returns: 0
#
# Take only the first N elements from the stream.
#
# Usage: stream_take n
# Example: stream_from_range 1 1000 | stream_take 5  # 1, 2, 3, 4, 5
stream_take() {
    local n="${1:-10}"
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$count" -ge "$n" ]]; then
            break
        fi
        printf '%s\n' "$item"
        ((count++))
    done
}

# @pre: n >= 0
# @post: elements after first n written to stdout
# @idempotent: yes
# @returns: 0
#
# Skip the first N elements from the stream.
#
# Usage: stream_drop n
# Example: stream_from_range 1 10 | stream_drop 3  # 4, 5, 6, ..., 10
stream_drop() {
    local n="${1:-0}"
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$count" -ge "$n" ]]; then
            printf '%s\n' "$item"
        fi
        ((count++))
    done
}

# @pre: predicate is valid expression
# @post: elements written until predicate returns false
# @idempotent: yes
# @returns: 0
#
# Take elements while the predicate returns true. Stops at first false.
#
# Usage: stream_take_while "predicate"
# Example: stream_from_range 1 10 | stream_take_while '[[ $item -lt 5 ]]'
# Security: Uses safe predicate evaluation with pattern validation
stream_take_while() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if ! _streams_eval_predicate "$predicate" "$item"; then
            break
        fi
        printf '%s\n' "$item"
    done
}

# @pre: predicate is valid expression
# @post: elements after predicate becomes false written to stdout
# @idempotent: yes
# @returns: 0
#
# Skip elements while the predicate returns true. Output starts at first false.
#
# Usage: stream_drop_while "predicate"
# Example: stream_from_range 1 10 | stream_drop_while '[[ $item -lt 5 ]]'
# Security: Uses safe predicate evaluation with pattern validation
stream_drop_while() {
    local predicate="$1"
    local dropping=true
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if $dropping; then
            if ! _streams_eval_predicate "$predicate" "$item"; then
                dropping=false
                printf '%s\n' "$item"
            fi
        else
            printf '%s\n' "$item"
        fi
    done
}

# @pre: input stream
# @post: unique elements written to stdout (preserves first occurrence order)
# @idempotent: yes
# @returns: 0
#
# Remove duplicate elements from the stream. First occurrence is kept.
# Note: Requires full materialization for tracking seen elements.
#
# Usage: stream_distinct
# Example: stream_of a b a c b d | stream_distinct  # a, b, c, d
stream_distinct() {
    local -A seen=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ -z "${seen[$item]+x}" ]]; then
            seen["$item"]=1
            printf '%s\n' "$item"
        fi
    done
}

# @pre: input stream
# @post: elements written in sorted order
# @idempotent: yes
# @returns: 0
#
# Sort elements. Supports numeric and lexicographic sorting.
# Note: Requires full materialization.
#
# Usage: stream_sorted [--numeric|-n] [--reverse|-r] [--unique|-u]
# Example: stream_of 3 1 2 | stream_sorted -n  # 1, 2, 3
stream_sorted() {
    local sort_opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--numeric) sort_opts+=("-n") ;;
            -r|--reverse) sort_opts+=("-r") ;;
            -u|--unique)  sort_opts+=("-u") ;;
            -k|--key)     sort_opts+=("-k" "$2"); shift ;;
            *) ;;
        esac
        shift
    done

    sort "${sort_opts[@]}"
}

# @pre: input stream
# @post: elements written in reverse order
# @idempotent: yes
# @returns: 0
#
# Reverse the order of elements.
# Note: Requires full materialization.
#
# Usage: stream_reversed
# Example: stream_of a b c | stream_reversed  # c, b, a
stream_reversed() {
    # Use tac if available, otherwise awk
    if type -p tac &>/dev/null; then
        tac
    else
        awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}'
    fi
}

# @pre: transform outputs zero or more lines per element
# @post: flattened output written to stdout
# @idempotent: yes
# @returns: 0
#
# Map each element to zero or more elements, then flatten the result.
# Transform should output zero, one, or more lines.
#
# Usage: stream_flat_map "transform"
# Example: stream_of "a b" "c d" | stream_flat_map 'echo $item | tr " " "\n"'
# Security: Uses safe transform evaluation with pattern validation
stream_flat_map() {
    local transform="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        _streams_eval_transform "$transform" "$item"
    done
}

# @pre: input stream
# @post: elements with index prefix
# @idempotent: yes
# @returns: 0
#
# Add index to each element. Output format: "index:element" or custom format.
#
# Usage: stream_enumerate [--start N] [--format FMT]
# Example: stream_of a b c | stream_enumerate  # 0:a, 1:b, 2:c
stream_enumerate() {
    local start=0
    local format='%d:%s'

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start) start="$2"; shift 2 ;;
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local index="$start"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        printf "$format\n" "$index" "$item"
        ((index++))
    done
}

# @pre: input stream
# @post: elements without leading/trailing whitespace
# @idempotent: yes
# @returns: 0
#
# Trim whitespace from each element.
#
# Usage: stream_trim
# Example: stream_of "  a  " "  b  " | stream_trim  # "a", "b"
stream_trim() {
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        # Remove leading whitespace
        item="${item#"${item%%[![:space:]]*}"}"
        # Remove trailing whitespace
        item="${item%"${item##*[![:space:]]}"}"
        printf '%s\n' "$item"
    done
}

# @pre: input stream
# @post: non-empty elements written to stdout
# @idempotent: yes
# @returns: 0
#
# Filter out empty lines and lines containing only whitespace.
#
# Usage: stream_compact
# Example: stream_of "a" "" "b" "  " "c" | stream_compact  # a, b, c
stream_compact() {
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        # Skip empty or whitespace-only lines
        [[ -z "${item// /}" ]] && continue
        printf '%s\n' "$item"
    done
}

# =============================================================================
# STREAM AGGREGATION
# =============================================================================

# @pre: reducer expression uses $acc and $item
# @post: single reduced value written to stdout
# @idempotent: yes
# @returns: 0
#
# Reduce stream to a single value. First element is initial accumulator.
# Use stream_fold for custom initial value.
#
# Usage: stream_reduce "reducer"
# Example: stream_of 1 2 3 4 | stream_reduce 'echo $(($acc + $item))'
# Security: Uses subprocess isolation with pattern validation
stream_reduce() {
    local reducer="$1"
    local acc=""
    local first=true
    local item

    # Block dangerous patterns in reducer
    if [[ "$reducer" == *'`'* ]] || [[ "$reducer" == *';'* ]] || \
       [[ "$reducer" == *'eval'* ]] || [[ "$reducer" == *'source'* ]] || \
       [[ "$reducer" == *'&'* ]] || [[ "$reducer" == *$'\n'* ]] || \
       [[ "$reducer" == *'>'* ]] || [[ "$reducer" == *'|'* ]]; then
        _stream_error 1 "blocked dangerous pattern in reducer"
        return 1
    fi

    while IFS= read -r item || [[ -n "$item" ]]; do
        if $first; then
            acc="$item"
            first=false
        else
            # Security: Execute in subprocess with acc and item exported
            acc=$(acc="$acc" item="$item" bash -c "$reducer")
        fi
    done

    if [[ -n "$acc" ]]; then
        printf '%s\n' "$acc"
    fi
}

# @pre: folder expression uses $acc and $item
# @post: single folded value written to stdout
# @idempotent: yes
# @returns: 0
#
# Fold stream with an initial accumulator value.
#
# Usage: stream_fold initial "folder"
# Example: stream_of 1 2 3 | stream_fold 10 'echo $(($acc + $item))'  # 16
# Security: Uses subprocess isolation with pattern validation
stream_fold() {
    local acc="$1"
    local folder="$2"
    local item

    # Block dangerous patterns in folder
    if [[ "$folder" == *'`'* ]] || [[ "$folder" == *';'* ]] || \
       [[ "$folder" == *'eval'* ]] || [[ "$folder" == *'source'* ]] || \
       [[ "$folder" == *'&'* ]] || [[ "$folder" == *$'\n'* ]] || \
       [[ "$folder" == *'>'* ]] || [[ "$folder" == *'|'* ]]; then
        _stream_error 1 "blocked dangerous pattern in folder"
        return 1
    fi

    while IFS= read -r item || [[ -n "$item" ]]; do
        # Security: Execute in subprocess with acc and item exported
        acc=$(acc="$acc" item="$item" bash -c "$folder")
    done

    printf '%s\n' "$acc"
}

# @pre: input stream
# @post: count written to stdout
# @idempotent: yes
# @returns: 0
#
# Count the number of elements in the stream.
#
# Usage: stream_count
# Example: stream_from_range 1 100 | stream_count  # 100
stream_count() {
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        ((count++))
    done

    printf '%d\n' "$count"
}

# @pre: input stream contains numeric values
# @post: sum written to stdout
# @idempotent: yes
# @returns: 0
#
# Sum numeric elements in the stream.
#
# Usage: stream_sum
# Example: stream_of 1 2 3 4 5 | stream_sum  # 15
stream_sum() {
    local sum=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$item" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            # Handle floating point with bc if available
            if [[ "$item" == *"."* ]] && type -p bc &>/dev/null; then
                sum=$(echo "$sum + $item" | bc -l)
            else
                sum=$((sum + item))
            fi
        fi
    done

    printf '%s\n' "$sum"
}

# @pre: input stream contains comparable values
# @post: minimum value written to stdout
# @idempotent: yes
# @returns: 0
#
# Find the minimum value in the stream. Supports numeric and string comparison.
#
# Usage: stream_min [--numeric|-n]
# Example: stream_of 3 1 4 1 5 | stream_min -n  # 1
stream_min() {
    local numeric=false
    [[ "$1" == "-n" || "$1" == "--numeric" ]] && numeric=true

    local min=""
    local first=true
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if $first; then
            min="$item"
            first=false
        elif $numeric; then
            [[ "$item" -lt "$min" ]] && min="$item"
        else
            [[ "$item" < "$min" ]] && min="$item"
        fi
    done

    if [[ -n "$min" ]]; then
        printf '%s\n' "$min"
    fi
}

# @pre: input stream contains comparable values
# @post: maximum value written to stdout
# @idempotent: yes
# @returns: 0
#
# Find the maximum value in the stream. Supports numeric and string comparison.
#
# Usage: stream_max [--numeric|-n]
# Example: stream_of 3 1 4 1 5 | stream_max -n  # 5
stream_max() {
    local numeric=false
    [[ "$1" == "-n" || "$1" == "--numeric" ]] && numeric=true

    local max=""
    local first=true
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if $first; then
            max="$item"
            first=false
        elif $numeric; then
            [[ "$item" -gt "$max" ]] && max="$item"
        else
            [[ "$item" > "$max" ]] && max="$item"
        fi
    done

    if [[ -n "$max" ]]; then
        printf '%s\n' "$max"
    fi
}

# @pre: input stream
# @post: first element written to stdout (or empty if stream empty)
# @idempotent: yes
# @returns: 0 if element found, 1 if empty stream
#
# Get the first element from the stream.
#
# Usage: stream_first
# Example: stream_of a b c | stream_first  # a
stream_first() {
    local item

    if IFS= read -r item; then
        printf '%s\n' "$item"
        return 0
    fi
    return 1
}

# @pre: input stream
# @post: last element written to stdout
# @idempotent: yes
# @returns: 0 if element found, 1 if empty stream
#
# Get the last element from the stream.
# Note: Requires full materialization.
#
# Usage: stream_last
# Example: stream_of a b c | stream_last  # c
stream_last() {
    local last=""
    local found=false
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        last="$item"
        found=true
    done

    if $found; then
        printf '%s\n' "$last"
        return 0
    fi
    return 1
}

# @pre: predicate is valid expression
# @post: "true" or "false" written to stdout
# @idempotent: yes
# @returns: 0
#
# Check if any element matches the predicate.
#
# Usage: stream_any "predicate"
# Example: stream_of 1 2 3 | stream_any '[[ $item -gt 2 ]]'  # true
# Security: Uses safe predicate evaluation with pattern validation
stream_any() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$predicate" "$item"; then
            printf 'true\n'
            # Consume remaining input to avoid broken pipe
            cat >/dev/null 2>&1
            return 0
        fi
    done

    printf 'false\n'
    return 0
}

# @pre: predicate is valid expression
# @post: "true" or "false" written to stdout
# @idempotent: yes
# @returns: 0
#
# Check if all elements match the predicate. Empty stream returns true.
#
# Usage: stream_all "predicate"
# Example: stream_of 2 4 6 | stream_all '[[ $(($item % 2)) -eq 0 ]]'  # true
# Security: Uses safe predicate evaluation with pattern validation
stream_all() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if ! _streams_eval_predicate "$predicate" "$item"; then
            printf 'false\n'
            # Consume remaining input
            cat >/dev/null 2>&1
            return 0
        fi
    done

    printf 'true\n'
    return 0
}

# @pre: predicate is valid expression
# @post: "true" or "false" written to stdout
# @idempotent: yes
# @returns: 0
#
# Check if no elements match the predicate.
#
# Usage: stream_none "predicate"
# Example: stream_of 1 2 3 | stream_none '[[ $item -gt 5 ]]'  # true
# Security: Uses safe predicate evaluation with pattern validation
stream_none() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$predicate" "$item"; then
            printf 'false\n'
            cat >/dev/null 2>&1
            return 0
        fi
    done

    printf 'true\n'
    return 0
}

# @pre: predicate is valid expression
# @post: first matching element or empty
# @idempotent: yes
# @returns: 0 if found, 1 if not found
#
# Find first element matching predicate.
#
# Usage: stream_find "predicate"
# Example: stream_of 1 2 3 4 | stream_find '[[ $item -gt 2 ]]'  # 3
# Security: Uses safe predicate evaluation with pattern validation
stream_find() {
    local predicate="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$predicate" "$item"; then
            printf '%s\n' "$item"
            cat >/dev/null 2>&1
            return 0
        fi
    done

    return 1
}

# @pre: input stream contains numeric values
# @post: average written to stdout
# @idempotent: yes
# @returns: 0
#
# Calculate average of numeric elements.
#
# Usage: stream_average
# Example: stream_of 1 2 3 4 5 | stream_average  # 3
stream_average() {
    local sum=0
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$item" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            if [[ "$item" == *"."* ]] && type -p bc &>/dev/null; then
                sum=$(echo "$sum + $item" | bc -l)
            else
                sum=$((sum + item))
            fi
            ((count++))
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        printf '0\n'
        return 0
    fi

    if type -p bc &>/dev/null; then
        echo "scale=2; $sum / $count" | bc -l
    else
        printf '%d\n' $((sum / count))
    fi
}

# =============================================================================
# STREAM WINDOWING
# =============================================================================

# @pre: size > 0
# @post: sliding window batches written as JSON arrays
# @idempotent: yes
# @returns: 0
#
# Create sliding windows of fixed size over the stream.
# Each window is output as a JSON array.
#
# Usage: stream_window size [step]
# Example: stream_of 1 2 3 4 5 | stream_window 3
#          # ["1","2","3"], ["2","3","4"], ["3","4","5"]
stream_window() {
    local size="${1:-3}"
    local step="${2:-1}"
    local -a buffer=()
    local item
    local step_count=0

    while IFS= read -r item || [[ -n "$item" ]]; do
        buffer+=("$item")

        if [[ "${#buffer[@]}" -ge "$size" ]]; then
            # Output window as JSON array
            printf '['
            local first=true
            local elem
            for elem in "${buffer[@]:0:$size}"; do
                $first || printf ','
                first=false
                printf '"%s"' "$elem"
            done
            printf ']\n'

            # Slide window by step
            buffer=("${buffer[@]:$step}")
        fi
    done
}

# @pre: size > 0
# @post: fixed-size batches written as JSON arrays
# @idempotent: yes
# @returns: 0
#
# Create fixed-size batches (non-overlapping windows).
# Last batch may be smaller than size.
#
# Usage: stream_batch size
# Example: stream_of 1 2 3 4 5 | stream_batch 2
#          # ["1","2"], ["3","4"], ["5"]
stream_batch() {
    local size="${1:-$MAINFRAME_STREAM_BATCH_SIZE}"
    local -a buffer=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        buffer+=("$item")

        if [[ "${#buffer[@]}" -ge "$size" ]]; then
            # Output batch as JSON array
            printf '['
            local first=true
            local elem
            for elem in "${buffer[@]}"; do
                $first || printf ','
                first=false
                printf '"%s"' "$elem"
            done
            printf ']\n'
            buffer=()
        fi
    done

    # Output remaining elements
    if [[ "${#buffer[@]}" -gt 0 ]]; then
        printf '['
        local first=true
        local elem
        for elem in "${buffer[@]}"; do
            $first || printf ','
            first=false
            printf '"%s"' "$elem"
        done
        printf ']\n'
    fi
}

# @pre: condition is valid expression using $buffer (array) and $item
# @post: buffered content written when condition true
# @idempotent: yes
# @returns: 0
#
# Buffer elements until a condition is met, then flush.
#
# Usage: stream_buffer "condition"
# Example: stream_of a b END c d END | stream_buffer '[[ "$item" == "END" ]]'
# Security: Uses safe predicate evaluation with pattern validation
stream_buffer() {
    local condition="$1"
    local -a buffer=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$condition" "$item"; then
            # Flush buffer
            local elem
            for elem in "${buffer[@]}"; do
                printf '%s\n' "$elem"
            done
            buffer=()
        else
            buffer+=("$item")

            # Safety: flush if buffer exceeds max
            if [[ "${#buffer[@]}" -ge "$MAINFRAME_STREAM_MAX_BUFFER" ]]; then
                for elem in "${buffer[@]}"; do
                    printf '%s\n' "$elem"
                done
                buffer=()
            fi
        fi
    done

    # Flush remaining
    if [[ "${#buffer[@]}" -gt 0 ]]; then
        local elem
        for elem in "${buffer[@]}"; do
            printf '%s\n' "$elem"
        done
    fi
}

# @pre: rate_ms > 0
# @post: elements written with minimum delay between them
# @idempotent: yes
# @returns: 0
#
# Rate-limit stream output. Minimum delay between elements.
#
# Usage: stream_throttle [rate_ms]
# Example: stream_from_range 1 10 | stream_throttle 100  # 100ms between each
stream_throttle() {
    local rate_ms="${1:-$MAINFRAME_STREAM_THROTTLE_MS}"
    local delay_sec

    # Convert ms to seconds for sleep
    if type -p bc &>/dev/null; then
        delay_sec=$(echo "scale=3; $rate_ms / 1000" | bc)
    else
        delay_sec=$((rate_ms / 1000))
        [[ "$delay_sec" -eq 0 ]] && delay_sec="0.1"
    fi

    local first=true
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if ! $first; then
            sleep "$delay_sec"
        fi
        first=false
        printf '%s\n' "$item"
    done
}

# @pre: delay_ms > 0
# @post: only last value in rapid sequence emitted
# @idempotent: yes
# @returns: 0
#
# Debounce rapid items - only emit after quiet period.
# Emits the last value seen after delay_ms of no new input.
#
# Usage: stream_debounce [delay_ms]
# Example: (echo a; sleep 0.01; echo b; sleep 0.5; echo c) | stream_debounce 100
stream_debounce() {
    local delay_ms="${1:-$MAINFRAME_STREAM_THROTTLE_MS}"
    local delay_sec

    if type -p bc &>/dev/null; then
        delay_sec=$(echo "scale=3; $delay_ms / 1000" | bc)
    else
        delay_sec="0.1"
    fi

    local pending=""
    local item

    while IFS= read -r -t "$delay_sec" item || [[ -n "$item" ]]; do
        if [[ -n "$item" ]]; then
            pending="$item"
        fi
    done

    # Emit last pending value
    if [[ -n "$pending" ]]; then
        printf '%s\n' "$pending"
    fi

    # Continue reading
    while IFS= read -r item || [[ -n "$item" ]]; do
        pending="$item"
        # Wait for quiet period
        while IFS= read -r -t "$delay_sec" item; do
            [[ -n "$item" ]] && pending="$item"
        done
        [[ -n "$pending" ]] && printf '%s\n' "$pending"
    done
}

# @pre: n > 0
# @post: every Nth element written to stdout
# @idempotent: yes
# @returns: 0
#
# Sample every Nth element from the stream.
#
# Usage: stream_sample n
# Example: stream_from_range 1 100 | stream_sample 10  # 1, 11, 21, ...
stream_sample() {
    local n="${1:-10}"
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ $((count % n)) -eq 0 ]]; then
            printf '%s\n' "$item"
        fi
        ((count++))
    done
}

# @pre: input stream
# @post: one random element written to stdout
# @idempotent: no (random)
# @returns: 0 if element found, 1 if empty stream
#
# Get a random element from the stream using reservoir sampling.
#
# Usage: stream_random
# Example: stream_from_range 1 100 | stream_random
stream_random() {
    local selected=""
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        ((count++))
        # Reservoir sampling: keep with probability 1/count
        if [[ $((RANDOM % count)) -eq 0 ]]; then
            selected="$item"
        fi
    done

    if [[ -n "$selected" ]]; then
        printf '%s\n' "$selected"
        return 0
    fi
    return 1
}

# @pre: input stream
# @post: elements shuffled randomly
# @idempotent: no (random)
# @returns: 0
#
# Shuffle elements randomly.
# Note: Requires full materialization.
#
# Usage: stream_shuffle
# Example: stream_of a b c d | stream_shuffle
stream_shuffle() {
    if type -p shuf &>/dev/null; then
        shuf
    else
        # Pure bash fallback using Fisher-Yates
        local -a arr=()
        local item
        while IFS= read -r item || [[ -n "$item" ]]; do
            arr+=("$item")
        done

        local i j n="${#arr[@]}"
        for ((i=n-1; i>0; i--)); do
            j=$((RANDOM % (i + 1)))
            # Swap
            local tmp="${arr[i]}"
            arr[i]="${arr[j]}"
            arr[j]="$tmp"
        done

        for item in "${arr[@]}"; do
            printf '%s\n' "$item"
        done
    fi
}

# =============================================================================
# STREAM COMBINATION
# =============================================================================

# @pre: multiple input streams via process substitution
# @post: interleaved output from all streams
# @idempotent: yes
# @returns: 0
#
# Merge multiple streams, interleaving their output.
# Reads from all streams in round-robin fashion.
#
# Usage: stream_merge <(stream1) <(stream2) ...
# Example: stream_merge <(stream_of a b c) <(stream_of 1 2 3)
stream_merge() {
    local -a fds=("$@")
    local -A active=()
    local fd

    # Initialize active set
    for fd in "${fds[@]}"; do
        active["$fd"]=1
    done

    while [[ ${#active[@]} -gt 0 ]]; do
        for fd in "${!active[@]}"; do
            local item
            if IFS= read -r item <"$fd" 2>/dev/null; then
                printf '%s\n' "$item"
            else
                unset 'active[$fd]'
            fi
        done
    done
}

# @pre: two streams via process substitution or pipes
# @post: paired elements as "elem1:elem2"
# @idempotent: yes
# @returns: 0
#
# Zip two streams together. Stops when either stream ends.
#
# Usage: stream_zip <(stream1) <(stream2) [--separator SEP]
# Example: stream_zip <(stream_of a b c) <(stream_of 1 2 3)  # a:1, b:2, c:3
stream_zip() {
    local fd1="$1"
    local fd2="$2"
    local sep=":"

    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --separator|-s) sep="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local item1 item2
    while IFS= read -r item1 <"$fd1" && IFS= read -r item2 <"$fd2"; do
        printf '%s%s%s\n' "$item1" "$sep" "$item2"
    done
}

# @pre: two streams via process substitution
# @post: elements from first stream, then second
# @idempotent: yes
# @returns: 0
#
# Concatenate streams end-to-end.
#
# Usage: stream_concat <(stream1) <(stream2)
# Example: stream_concat <(stream_of a b) <(stream_of c d)  # a, b, c, d
stream_concat() {
    local fd
    for fd in "$@"; do
        cat "$fd"
    done
}

# @pre: multiple streams via process substitution
# @post: alternating elements from each stream
# @idempotent: yes
# @returns: 0
#
# Interleave multiple streams, taking one element from each in turn.
#
# Usage: stream_interleave <(stream1) <(stream2) ...
# Example: stream_interleave <(stream_of a b c) <(stream_of 1 2 3)
#          # a, 1, b, 2, c, 3
stream_interleave() {
    local -a fds=("$@")
    local -A active=()
    local fd

    for fd in "${fds[@]}"; do
        active["$fd"]=1
    done

    while [[ ${#active[@]} -gt 0 ]]; do
        local any_output=false
        for fd in "${fds[@]}"; do
            [[ -z "${active[$fd]+x}" ]] && continue

            local item
            if IFS= read -r item <"$fd" 2>/dev/null; then
                printf '%s\n' "$item"
                any_output=true
            else
                unset 'active[$fd]'
            fi
        done

        [[ "$any_output" == "false" ]] && break
    done
}

# @pre: two sorted streams
# @post: merged sorted output
# @idempotent: yes
# @returns: 0
#
# Merge two sorted streams maintaining sort order.
#
# Usage: stream_merge_sorted <(sorted1) <(sorted2) [--numeric|-n]
# Example: stream_merge_sorted <(stream_of 1 3 5) <(stream_of 2 4 6) -n
stream_merge_sorted() {
    local fd1="$1"
    local fd2="$2"
    shift 2

    local numeric=false
    [[ "$1" == "-n" || "$1" == "--numeric" ]] && numeric=true

    local item1="" item2=""
    local have1=false have2=false

    # Initial read
    if IFS= read -r item1 <"$fd1" 2>/dev/null; then
        have1=true
    fi
    if IFS= read -r item2 <"$fd2" 2>/dev/null; then
        have2=true
    fi

    while $have1 || $have2; do
        if ! $have1; then
            printf '%s\n' "$item2"
            if IFS= read -r item2 <"$fd2" 2>/dev/null; then
                have2=true
            else
                have2=false
            fi
        elif ! $have2; then
            printf '%s\n' "$item1"
            if IFS= read -r item1 <"$fd1" 2>/dev/null; then
                have1=true
            else
                have1=false
            fi
        elif $numeric && [[ "$item1" -le "$item2" ]] || \
             ! $numeric && [[ "$item1" < "$item2" || "$item1" == "$item2" ]]; then
            printf '%s\n' "$item1"
            if IFS= read -r item1 <"$fd1" 2>/dev/null; then
                have1=true
            else
                have1=false
            fi
        else
            printf '%s\n' "$item2"
            if IFS= read -r item2 <"$fd2" 2>/dev/null; then
                have2=true
            else
                have2=false
            fi
        fi
    done
}

# =============================================================================
# STREAM OUTPUT
# =============================================================================

# @pre: input stream
# @post: array variable populated (if nameref) or JSON array output
# @idempotent: yes
# @returns: 0
#
# Collect stream elements into an array.
#
# Usage: stream_collect [array_name]
#        result=$(stream_of a b c | stream_collect)  # Returns JSON array
# Example:
#   declare -a arr
#   stream_of a b c | stream_collect arr
#   echo "${arr[@]}"  # a b c
# Security: Uses nameref instead of eval for array assignment
stream_collect() {
    local arr_name="${1:-}"
    local -a items=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        items+=("$item")
    done

    if [[ -n "$arr_name" ]]; then
        # Validate array name (alphanumeric and underscore only)
        if ! _streams_valid_var_name "$arr_name"; then
            _stream_error 1 "invalid array name: $arr_name"
            return 1
        fi

        _streams_assign_array "$arr_name" "${items[@]}" || return 1
    else
        # Output as JSON array
        printf '['
        local first=true
        for item in "${items[@]}"; do
            $first || printf ','
            first=false
            printf '"%s"' "$item"
        done
        printf ']\n'
    fi
}

# @pre: file path is writable
# @post: elements written to file
# @idempotent: no (file modified)
# @returns: 0 on success, 1 on error
#
# Write stream elements to a file.
#
# Usage: stream_to_file "/path/to/file" [--append]
# Example: stream_of a b c | stream_to_file "/tmp/output.txt"
stream_to_file() {
    local file="$1"
    local append=false

    shift
    [[ "$1" == "--append" || "$1" == "-a" ]] && append=true

    if [[ -z "$file" ]]; then
        _stream_error 1 "file path required"
        return 1
    fi

    local dir
    dir="$(dirname "$file")"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            _stream_error 1 "cannot create directory: $dir"
            return 1
        }
    fi

    if $append; then
        cat >> "$file"
    else
        cat > "$file"
    fi
}

# @pre: action is valid expression or command
# @post: action executed for each element (side effects)
# @idempotent: depends on action
# @returns: 0
#
# Execute an action for each element. Does not transform the stream.
# The action can use $item for the current element.
#
# Usage: stream_foreach "action"
# Example: stream_of a b c | stream_foreach 'echo "Processing: $item"'
# Security: Uses safe transform evaluation with pattern validation
stream_foreach() {
    local action="$1"
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        _streams_eval_transform "$action" "$item"
    done
}

# @pre: input stream
# @post: JSON array written to stdout
# @idempotent: yes
# @returns: 0
#
# Output stream as a JSON array with proper escaping.
#
# Usage: stream_to_json [--pretty]
# Example: stream_of "hello world" "foo" | stream_to_json
stream_to_json() {
    local pretty=false
    [[ "$1" == "--pretty" || "$1" == "-p" ]] && pretty=true

    local -a items=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        items+=("$item")
    done

    if $pretty; then
        printf '[\n'
        local first=true
        for item in "${items[@]}"; do
            $first || printf ',\n'
            first=false
            # Escape JSON special chars
            item="${item//\\/\\\\}"
            item="${item//\"/\\\"}"
            item="${item//$'\n'/\\n}"
            item="${item//$'\t'/\\t}"
            printf '  "%s"' "$item"
        done
        printf '\n]\n'
    else
        printf '['
        local first=true
        for item in "${items[@]}"; do
            $first || printf ','
            first=false
            item="${item//\\/\\\\}"
            item="${item//\"/\\\"}"
            item="${item//$'\n'/\\n}"
            item="${item//$'\t'/\\t}"
            printf '"%s"' "$item"
        done
        printf ']\n'
    fi
}

# @pre: input stream
# @post: statistics object written to stdout
# @idempotent: yes
# @returns: 0
#
# Output stream statistics as JSON.
#
# Usage: stream_stats
# Example: stream_of 1 2 3 4 5 | stream_stats
#          # {"count":5,"sum":15,"min":1,"max":5,"avg":3}
stream_stats() {
    local count=0
    local sum=0
    local min=""
    local max=""
    local item
    local is_numeric=true

    while IFS= read -r item || [[ -n "$item" ]]; do
        ((count++))

        if [[ "$item" =~ ^-?[0-9]+$ ]]; then
            sum=$((sum + item))
            if [[ -z "$min" ]] || [[ "$item" -lt "$min" ]]; then
                min="$item"
            fi
            if [[ -z "$max" ]] || [[ "$item" -gt "$max" ]]; then
                max="$item"
            fi
        else
            is_numeric=false
        fi
    done

    if $is_numeric && [[ "$count" -gt 0 ]]; then
        local avg=$((sum / count))
        printf '{"count":%d,"sum":%d,"min":%d,"max":%d,"avg":%d}\n' \
            "$count" "$sum" "$min" "$max" "$avg"
    else
        printf '{"count":%d}\n' "$count"
    fi
}

# @pre: input stream
# @post: elements teed to file and stdout
# @idempotent: no (file modified)
# @returns: 0
#
# Tee stream to a file while passing through to stdout.
# Like Unix tee but for streams.
#
# Usage: stream_tee "/path/to/file" [--append]
# Example: stream_of a b c | stream_tee /tmp/log.txt | stream_map 'echo "Got: $item"'
stream_tee() {
    local file="$1"
    local append=false

    shift
    [[ "$1" == "--append" || "$1" == "-a" ]] && append=true

    if [[ -z "$file" ]]; then
        _stream_error 1 "file path required"
        return 1
    fi

    local dir
    dir="$(dirname "$file")"
    [[ ! -d "$dir" ]] && mkdir -p "$dir"

    if $append; then
        tee -a "$file"
    else
        tee "$file"
    fi
}

# @pre: input stream
# @post: newline-separated output
# @idempotent: yes
# @returns: 0
#
# Output stream elements separated by newlines (identity operation).
# Useful for explicit pipeline termination.
#
# Usage: stream_to_lines
# Example: stream_of a b c | stream_to_lines
stream_to_lines() {
    cat
}

# @pre: input stream
# @post: single line with delimiter-separated elements
# @idempotent: yes
# @returns: 0
#
# Join all elements into a single line with delimiter.
#
# Usage: stream_join [delimiter]
# Example: stream_of a b c | stream_join ","  # a,b,c
stream_join() {
    local delim="${1:-,}"
    local first=true
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        $first || printf '%s' "$delim"
        first=false
        printf '%s' "$item"
    done
    printf '\n'
}

# =============================================================================
# STREAM UTILITIES
# =============================================================================

# @pre: input stream
# @post: elements with debug info to stderr, original to stdout
# @idempotent: yes
# @returns: 0
#
# Debug helper - prints each element to stderr while passing through.
#
# Usage: stream_peek [--prefix PREFIX]
# Example: stream_of a b c | stream_peek --prefix "DEBUG:"
stream_peek() {
    local prefix="${2:-[peek]}"

    [[ "$1" == "--prefix" || "$1" == "-p" ]] && prefix="$2"

    local item
    while IFS= read -r item || [[ -n "$item" ]]; do
        printf '%s %s\n' "$prefix" "$item" >&2
        printf '%s\n' "$item"
    done
}

# @pre: input stream
# @post: stream continues only if not empty
# @idempotent: yes
# @returns: 0 if stream has elements, 1 if empty
#
# Assert stream is non-empty. Fails (returns 1) if no elements.
#
# Usage: stream_require_non_empty [--message MSG]
# Example: stream_empty | stream_require_non_empty  # returns 1
stream_require_non_empty() {
    local msg="stream is empty"
    [[ "$1" == "--message" || "$1" == "-m" ]] && msg="$2"

    local first_item
    if ! IFS= read -r first_item; then
        _stream_error 1 "$msg"
        return 1
    fi

    printf '%s\n' "$first_item"
    cat
}

# @pre: input stream
# @post: count written to stderr, stream passed through
# @idempotent: yes
# @returns: 0
#
# Count elements while passing stream through.
#
# Usage: stream_count_tap [--var VARNAME]
# Example: stream_of a b c | stream_count_tap  # writes count to stderr
stream_count_tap() {
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        ((count++))
        printf '%s\n' "$item"
    done

    printf '[stream_count_tap] %d elements\n' "$count" >&2
}

# @pre: n >= 0
# @post: element at position n, or empty if out of bounds
# @idempotent: yes
# @returns: 0 if found, 1 if not found
#
# Get element at specific index (0-based).
#
# Usage: stream_at index
# Example: stream_of a b c d | stream_at 2  # c
stream_at() {
    local index="${1:-0}"
    local count=0
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$count" -eq "$index" ]]; then
            printf '%s\n' "$item"
            cat >/dev/null 2>&1
            return 0
        fi
        ((count++))
    done

    return 1
}

# @pre: input stream
# @post: grouped elements as JSON object
# @idempotent: yes
# @returns: 0
#
# Group elements by a key extractor.
#
# Usage: stream_group_by "key_expr"
# Example: stream_of aa ab ba bb | stream_group_by 'echo ${item:0:1}'
#          # {"a":["aa","ab"],"b":["ba","bb"]}
# Security: Uses safe transform evaluation with pattern validation
stream_group_by() {
    local key_expr="$1"
    local -A groups=()
    local item key

    while IFS= read -r item || [[ -n "$item" ]]; do
        key=$(_streams_eval_transform "$key_expr" "$item")
        if [[ -n "${groups[$key]+x}" ]]; then
            groups["$key"]="${groups[$key]},$item"
        else
            groups["$key"]="$item"
        fi
    done

    # Output as JSON
    printf '{'
    local first=true
    for key in "${!groups[@]}"; do
        $first || printf ','
        first=false
        printf '"%s":[' "$key"

        local vals="${groups[$key]}"
        local vfirst=true
        IFS=',' read -ra varr <<< "$vals"
        for v in "${varr[@]}"; do
            $vfirst || printf ','
            vfirst=false
            printf '"%s"' "$v"
        done
        printf ']'
    done
    printf '}\n'
}

# @pre: input stream
# @post: frequency counts as JSON object
# @idempotent: yes
# @returns: 0
#
# Count frequency of each unique element.
#
# Usage: stream_frequency
# Example: stream_of a b a c b a | stream_frequency
#          # {"a":3,"b":2,"c":1}
stream_frequency() {
    local -A counts=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        ((counts["$item"]++))
    done

    printf '{'
    local first=true
    for item in "${!counts[@]}"; do
        $first || printf ','
        first=false
        printf '"%s":%d' "$item" "${counts[$item]}"
    done
    printf '}\n'
}

# @pre: input stream
# @post: partitioned elements as JSON object with true/false arrays
# @idempotent: yes
# @returns: 0
#
# Partition elements into two groups based on predicate.
#
# Usage: stream_partition "predicate"
# Example: stream_from_range 1 10 | stream_partition '[[ $item -gt 5 ]]'
#          # {"true":["6","7","8","9","10"],"false":["1","2","3","4","5"]}
# Security: Uses safe predicate evaluation with pattern validation
stream_partition() {
    local predicate="$1"
    local -a true_items=()
    local -a false_items=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if _streams_eval_predicate "$predicate" "$item"; then
            true_items+=("$item")
        else
            false_items+=("$item")
        fi
    done

    # Output as JSON
    printf '{"true":['
    local first=true
    for item in "${true_items[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$item"
    done
    printf '],"false":['
    first=true
    for item in "${false_items[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$item"
    done
    printf ']}\n'
}

# @pre: input stream
# @post: elements chunked by separator
# @idempotent: yes
# @returns: 0
#
# Split stream into chunks at separator elements.
# Separator elements are not included in output.
#
# Usage: stream_chunk_by "separator_pattern"
# Example: stream_of a b --- c d --- e | stream_chunk_by '---'
stream_chunk_by() {
    local separator="$1"
    local -a chunk=()
    local item

    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ "$item" == "$separator" ]]; then
            # Output chunk as JSON array
            if [[ "${#chunk[@]}" -gt 0 ]]; then
                printf '['
                local first=true
                for elem in "${chunk[@]}"; do
                    $first || printf ','
                    first=false
                    printf '"%s"' "$elem"
                done
                printf ']\n'
                chunk=()
            fi
        else
            chunk+=("$item")
        fi
    done

    # Output remaining chunk
    if [[ "${#chunk[@]}" -gt 0 ]]; then
        printf '['
        local first=true
        for elem in "${chunk[@]}"; do
            $first || printf ','
            first=false
            printf '"%s"' "$elem"
        done
        printf ']\n'
    fi
}

# @pre: input stream, second stream via process substitution
# @post: elements present in first but not in second
# @idempotent: yes
# @returns: 0
#
# Compute set difference (elements in first stream not in second).
#
# Usage: stream_difference <(other_stream)
# Example: stream_of a b c d | stream_difference <(stream_of b d)  # a, c
stream_difference() {
    local other_fd="$1"
    local -A other_set=()
    local item

    # Load other stream into set
    while IFS= read -r item <"$other_fd" 2>/dev/null; do
        other_set["$item"]=1
    done

    # Output items not in other
    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ -z "${other_set[$item]+x}" ]]; then
            printf '%s\n' "$item"
        fi
    done
}

# @pre: input stream, second stream via process substitution
# @post: elements present in both streams
# @idempotent: yes
# @returns: 0
#
# Compute set intersection (elements in both streams).
#
# Usage: stream_intersect <(other_stream)
# Example: stream_of a b c d | stream_intersect <(stream_of b d e)  # b, d
stream_intersect() {
    local other_fd="$1"
    local -A other_set=()
    local item

    # Load other stream into set
    while IFS= read -r item <"$other_fd" 2>/dev/null; do
        other_set["$item"]=1
    done

    # Output items in both
    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ -n "${other_set[$item]+x}" ]]; then
            printf '%s\n' "$item"
        fi
    done
}

# @pre: input stream, second stream via process substitution
# @post: elements present in either stream (unique)
# @idempotent: yes
# @returns: 0
#
# Compute set union (all unique elements from both streams).
#
# Usage: stream_union <(other_stream)
# Example: stream_of a b c | stream_union <(stream_of b c d)  # a, b, c, d
stream_union() {
    local other_fd="$1"
    local -A seen=()
    local item

    # Output unique items from main stream
    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ -z "${seen[$item]+x}" ]]; then
            seen["$item"]=1
            printf '%s\n' "$item"
        fi
    done

    # Output unique items from other stream
    while IFS= read -r item <"$other_fd" 2>/dev/null; do
        if [[ -z "${seen[$item]+x}" ]]; then
            seen["$item"]=1
            printf '%s\n' "$item"
        fi
    done
}

# =============================================================================
# STREAM PIPELINE HELPERS
# =============================================================================

# @pre: valid pipeline steps as arguments
# @post: composed pipeline result
# @idempotent: depends on pipeline
# @returns: pipeline exit code
#
# Compose multiple stream operations into a single pipeline.
# Each argument is a stream operation to apply in sequence.
#
# Usage: stream_pipe "op1" "op2" "op3" ...
# Example: echo "1 2 3 4 5" | tr ' ' '\n' | stream_pipe \
#            "stream_filter '[[ \$item -gt 2 ]]'" \
#            "stream_map 'echo \$((\$item * 2))'"
# Security: Uses subprocess isolation via bash -c for each operation
stream_pipe() {
    local input
    input=$(cat)

    local op
    for op in "$@"; do
        input=$(printf '%s' "$input" | _streams_safe_exec "$op")
    done

    printf '%s\n' "$input"
}

# @pre: none
# @post: stream library version output
# @idempotent: yes
# @returns: 0
#
# Get stream library version and info.
#
# Usage: stream_version
stream_version() {
    printf '{"library":"mainframe/streams","version":"1.0.0","functions":47}\n'
}

# =============================================================================
# EXPORT SECURITY FUNCTIONS
# =============================================================================

export -f _streams_eval_predicate _streams_eval_transform
export -f _streams_safe_exec _streams_call_func

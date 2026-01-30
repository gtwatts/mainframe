#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/compose.sh - Function Composition Library
# =============================================================================
# Description: Advanced function composition primitives inspired by functional
#              programming. Provides compose, pipe, partial application, currying,
#              lazy evaluation, thunks, and memoization decorators.
# Version: 1.0.0
# Requires: Bash 4.3+ (for namerefs)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_COMPOSE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COMPOSE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Lazy thunk storage directory
MAINFRAME_THUNK_DIR="${MAINFRAME_THUNK_DIR:-${TMPDIR:-/tmp}/mainframe-thunks}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Thunk registry (maps thunk_id -> function definition)
declare -gA _MAINFRAME_THUNKS=()

# Thunk evaluation cache (maps thunk_id -> computed result)
declare -gA _MAINFRAME_THUNK_CACHE=()

# Thunk counter for unique IDs
declare -gi _MAINFRAME_THUNK_COUNTER=0

# Lazy sequence state
declare -gA _MAINFRAME_LAZY_SEQ_STATE=()

# Memoization cache for compose functions
declare -gA _MAINFRAME_COMPOSE_MEMO_CACHE=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string for USOP output
_compose_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Generate USOP success output
_compose_ok() {
    local data="$1"
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":%s}' "$data"
    else
        printf '%s' "$data"
    fi
}

# Generate USOP error output
_compose_err() {
    local msg="$1"
    local escaped_msg
    escaped_msg=$(_compose_escape "$msg")
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":false,"error":"%s"}' "$escaped_msg" >&2
    else
        printf 'compose error: %s\n' "$msg" >&2
    fi
    return 1
}

# Generate unique thunk ID
_compose_gen_thunk_id() {
    _MAINFRAME_THUNK_COUNTER=$((_MAINFRAME_THUNK_COUNTER + 1))
    printf 'thunk_%d_%d' "$$" "$_MAINFRAME_THUNK_COUNTER"
}

# Check if function exists (declared or command)
_compose_fn_exists() {
    local fn="$1"
    declare -F "$fn" &>/dev/null || type -p "$fn" &>/dev/null
}

# =============================================================================
# CORE COMPOSITION
# =============================================================================

# @pre: f and g are valid function names or callable commands
# @post: returns composed function definition as string
# @idempotent: yes
# @returns: 0 on success, composed function printed; 1 on error
#
# Mathematical function composition: (f . g)(x) = f(g(x))
# Returns a function definition string that can be evaluated or used with apply.
#
# Usage: composed=$(compose "f" "g"); $composed "x"
# Example: composed=$(compose "uppercase" "trim"); result=$($composed "  hello  ")
compose() {
    local f="$1"
    local g="$2"

    if [[ -z "$f" ]] || [[ -z "$g" ]]; then
        _compose_err "compose requires two function arguments"
        return 1
    fi

    if ! _compose_fn_exists "$f"; then
        _compose_err "compose: function '$f' not found"
        return 1
    fi

    if ! _compose_fn_exists "$g"; then
        _compose_err "compose: function '$g' not found"
        return 1
    fi

    # Generate unique composed function name
    local composed_name="_composed_${f}_${g}_$$_${RANDOM}"

    # Create the composed function
    eval "${composed_name}() {
        local _inner_result
        _inner_result=\$($g \"\$@\")
        $f \"\$_inner_result\"
    }"

    printf '%s' "$composed_name"
}

# @pre: f1, f2, ... are valid function names
# @post: returns piped function definition (left-to-right composition)
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Left-to-right function pipeline: pipe(f, g, h)(x) = h(g(f(x)))
# Opposite of mathematical composition - data flows left to right.
#
# Usage: piped=$(pipe_fn "f1" "f2" "f3"); result=$($piped "input")
# Example: piped=$(pipe_fn "trim" "uppercase" "add_prefix"); $piped "  hello  "
pipe_fn() {
    local -a funcs=("$@")
    local n=${#funcs[@]}

    if [[ $n -eq 0 ]]; then
        _compose_err "pipe_fn requires at least one function"
        return 1
    fi

    # Validate all functions exist
    local fn
    for fn in "${funcs[@]}"; do
        if ! _compose_fn_exists "$fn"; then
            _compose_err "pipe_fn: function '$fn' not found"
            return 1
        fi
    done

    # Single function - return as-is
    if [[ $n -eq 1 ]]; then
        printf '%s' "${funcs[0]}"
        return 0
    fi

    # Generate unique piped function name
    local piped_name="_piped_$$_${RANDOM}"

    # Build the function body
    local body='local __val="$1"; shift'
    local i
    for ((i=0; i<n; i++)); do
        body+=$'\n'"__val=\$(${funcs[$i]} \"\$__val\" \"\$@\")"
    done
    body+=$'\n''printf "%s" "$__val"'

    eval "${piped_name}() { $body; }"

    printf '%s' "$piped_name"
}

# @pre: f1, f2, ... are valid function names
# @post: returns chained function with error propagation
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Chain functions with error propagation - stops on first failure.
# Each function receives the output of the previous as input.
# If any function returns non-zero, the chain stops and returns that code.
#
# Usage: chained=$(chain "validate" "process" "save"); $chained "data"
chain() {
    local -a funcs=("$@")
    local n=${#funcs[@]}

    if [[ $n -eq 0 ]]; then
        _compose_err "chain requires at least one function"
        return 1
    fi

    # Validate all functions exist
    local fn
    for fn in "${funcs[@]}"; do
        if ! _compose_fn_exists "$fn"; then
            _compose_err "chain: function '$fn' not found"
            return 1
        fi
    done

    # Generate unique chained function name
    local chained_name="_chained_$$_${RANDOM}"

    # Build the function body with error checking
    local body='local __val="$1"; shift; local __rc'
    local i
    for ((i=0; i<n; i++)); do
        body+=$'\n'"__val=\$(${funcs[$i]} \"\$__val\" \"\$@\")"
        body+=$'\n''__rc=$?; [[ $__rc -ne 0 ]] && return $__rc'
    done
    body+=$'\n''printf "%s" "$__val"'

    eval "${chained_name}() { $body; }"

    printf '%s' "$chained_name"
}

# =============================================================================
# PARTIAL APPLICATION
# =============================================================================

# @pre: fn is a valid function name, args are the partial arguments
# @post: returns partially applied function name
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a new function with some arguments pre-filled.
# The partially applied function can be called with remaining arguments.
#
# Usage: add3=$(partial "add" 3); result=$($add3 7)  # 10
# Example: greet=$(partial "printf" "Hello, %s!\n"); $greet "World"
partial() {
    local fn="$1"
    shift
    local -a preset_args=("$@")

    if [[ -z "$fn" ]]; then
        _compose_err "partial requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "partial: function '$fn' not found"
        return 1
    fi

    # Generate unique partial function name
    local partial_name="_partial_${fn}_$$_${RANDOM}"

    # Serialize preset args for embedding in function
    local args_serialized=""
    local arg
    for arg in "${preset_args[@]}"; do
        # Escape single quotes for safe embedding
        arg="${arg//\'/\'\\\'\'}"
        args_serialized+="'$arg' "
    done

    # Create the partial function
    eval "${partial_name}() {
        $fn $args_serialized\"\$@\"
    }"

    printf '%s' "$partial_name"
}

# @pre: fn is a valid function name, arity is a positive integer
# @post: returns curried function name
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Transform a multi-argument function into a chain of single-argument functions.
# Each call returns a new function until all arguments are provided.
#
# Usage: curried=$(curry "add3" 3); f1=$($curried 1); f2=$($f1 2); result=$($f2 3)
# Note: Due to bash limitations, curried functions are limited to simple cases.
curry() {
    local fn="$1"
    local arity="${2:-2}"

    if [[ -z "$fn" ]]; then
        _compose_err "curry requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "curry: function '$fn' not found"
        return 1
    fi

    if ! [[ "$arity" =~ ^[0-9]+$ ]] || [[ "$arity" -lt 1 ]]; then
        _compose_err "curry: arity must be a positive integer"
        return 1
    fi

    # Generate curried function name
    local curry_name="_curry_${fn}_${arity}_$$_${RANDOM}"

    # Create the curried function (recursive partial application)
    eval "${curry_name}() {
        local _collected=\"\${_CURRY_ARGS_${curry_name}:-}\"
        if [[ -n \"\$_collected\" ]]; then
            _collected+=$'\\n'\"\$1\"
        else
            _collected=\"\$1\"
        fi
        local _count=0
        while IFS= read -r _line; do
            ((_count++))
        done <<< \"\$_collected\"

        if [[ \$_count -ge $arity ]]; then
            local -a _args=()
            while IFS= read -r _line; do
                _args+=(\"\$_line\")
            done <<< \"\$_collected\"
            unset _CURRY_ARGS_${curry_name}
            $fn \"\${_args[@]}\"
        else
            export _CURRY_ARGS_${curry_name}=\"\$_collected\"
            printf '%s' \"$curry_name\"
        fi
    }"

    printf '%s' "$curry_name"
}

# @pre: fn is a valid function name
# @post: returns function with first two arguments swapped
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a new function with the first two arguments swapped.
# Useful for adapting binary functions for use with map/reduce.
#
# Usage: flipped=$(flip "subtract"); result=$($flipped 3 10)  # 10 - 3 = 7
flip() {
    local fn="$1"

    if [[ -z "$fn" ]]; then
        _compose_err "flip requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "flip: function '$fn' not found"
        return 1
    fi

    # Generate flipped function name
    local flip_name="_flip_${fn}_$$_${RANDOM}"

    # Create the flipped function
    eval "${flip_name}() {
        local _a=\"\$1\"
        local _b=\"\$2\"
        shift 2
        $fn \"\$_b\" \"\$_a\" \"\$@\"
    }"

    printf '%s' "$flip_name"
}

# =============================================================================
# HIGHER-ORDER FUNCTIONS
# =============================================================================

# @pre: fn is a valid function name
# @post: returns function that executes fn for side effect, passes input through
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a function that executes fn for side effects but returns the original input.
# Useful for logging, debugging, or triggering actions in a pipeline.
#
# Usage: tapper=$(tap "log_value"); result=$(echo "data" | $tapper)
# The input "data" is passed to log_value AND returned unchanged.
tap() {
    local fn="$1"

    if [[ -z "$fn" ]]; then
        _compose_err "tap requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "tap: function '$fn' not found"
        return 1
    fi

    # Generate tap function name
    local tap_name="_tap_${fn}_$$_${RANDOM}"

    # Create the tap function
    eval "${tap_name}() {
        local _input=\"\$1\"
        $fn \"\$_input\" >/dev/null 2>&1 || true
        printf '%s' \"\$_input\"
    }"

    printf '%s' "$tap_name"
}

# @pre: none
# @post: returns input unchanged
# @idempotent: yes
# @returns: 0, echoes first argument
#
# The identity function - returns its input unchanged.
# Useful as a default or placeholder in composition.
#
# Usage: result=$(identity "hello")  # "hello"
identity() {
    printf '%s' "$1"
}

# @pre: value is provided
# @post: returns function that always returns value
# @idempotent: yes
# @returns: 0 on success, function name printed
#
# Create a function that ignores its input and always returns a constant value.
# Useful for providing default values or terminating recursion.
#
# Usage: always42=$(constant 42); result=$($always42 "ignored")  # 42
constant() {
    local value="$1"

    # Generate constant function name
    local const_name="_const_$$_${RANDOM}"

    # Escape the value for safe embedding
    local escaped_value="${value//\'/\'\\\'\'}"

    # Create the constant function
    eval "${const_name}() {
        printf '%s' '$escaped_value'
    }"

    printf '%s' "$const_name"
}

# @pre: fn is a valid function name, args_array is an array
# @post: fn is called with array elements as arguments
# @idempotent: yes
# @returns: return code of fn
#
# Apply a function to an array of arguments (spread operator).
# Converts array elements to function arguments.
#
# Usage: args=(1 2 3); apply "sum" args  # sum 1 2 3
apply() {
    local fn="$1"
    local -n __apply_args=$2 2>/dev/null || {
        _compose_err "apply: second argument must be an array name"
        return 1
    }

    if [[ -z "$fn" ]]; then
        _compose_err "apply requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "apply: function '$fn' not found"
        return 1
    fi

    "$fn" "${__apply_args[@]}"
}

# =============================================================================
# LAZY EVALUATION
# =============================================================================

# @pre: fn is a valid function name, args are optional
# @post: returns thunk_id, computation is deferred
# @idempotent: yes
# @returns: 0 on success, thunk_id printed; 1 on error
#
# Create a lazy thunk - a deferred computation.
# The function is not executed until force() is called.
#
# Usage: thunk=$(lazy "expensive_compute" "arg1" "arg2")
#        result=$(force "$thunk")  # Now it executes
lazy() {
    local fn="$1"
    shift
    local -a args=("$@")

    if [[ -z "$fn" ]]; then
        _compose_err "lazy requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "lazy: function '$fn' not found"
        return 1
    fi

    # Generate unique thunk ID
    local thunk_id
    thunk_id=$(_compose_gen_thunk_id)

    # Serialize args for storage
    local args_serialized=""
    local arg
    for arg in "${args[@]}"; do
        arg="${arg//\'/\'\\\'\'}"
        args_serialized+="'$arg' "
    done

    # Store thunk definition
    _MAINFRAME_THUNKS["$thunk_id"]="${fn}|${args_serialized}"

    printf '%s' "$thunk_id"
}

# @pre: thunk_id was created by lazy()
# @post: thunk is evaluated, result cached
# @idempotent: yes (returns cached result on subsequent calls)
# @returns: 0 on success, result printed; 1 on error
#
# Force evaluation of a lazy thunk.
# Results are cached - subsequent force() calls return cached value.
#
# Usage: result=$(force "$thunk_id")
force() {
    local thunk_id="$1"

    if [[ -z "$thunk_id" ]]; then
        _compose_err "force requires a thunk_id"
        return 1
    fi

    # Check if already evaluated (memoized)
    if [[ -v "_MAINFRAME_THUNK_CACHE[$thunk_id]" ]]; then
        printf '%s' "${_MAINFRAME_THUNK_CACHE[$thunk_id]}"
        return 0
    fi

    # Get thunk definition
    if [[ ! -v "_MAINFRAME_THUNKS[$thunk_id]" ]]; then
        _compose_err "force: unknown thunk '$thunk_id'"
        return 1
    fi

    local thunk_def="${_MAINFRAME_THUNKS[$thunk_id]}"
    local fn="${thunk_def%%|*}"
    local args_serialized="${thunk_def#*|}"

    # Execute the thunk
    local result
    result=$(eval "$fn $args_serialized")
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        # Cache the result
        _MAINFRAME_THUNK_CACHE["$thunk_id"]="$result"
    fi

    printf '%s' "$result"
    return $rc
}

# @pre: gen_fn is a generator function that takes an index and returns a value
# @post: returns lazy sequence ID
# @idempotent: yes
# @returns: 0 on success, sequence_id printed; 1 on error
#
# Create a lazy infinite sequence from a generator function.
# The generator receives the current index (0-based) and should return the value.
#
# Usage: seq_id=$(lazy_seq "naturals_gen")  # naturals_gen(n) returns n
#        values=$(take_lazy 5 "$seq_id")    # Gets [0,1,2,3,4]
lazy_seq() {
    local gen_fn="$1"

    if [[ -z "$gen_fn" ]]; then
        _compose_err "lazy_seq requires a generator function"
        return 1
    fi

    if ! _compose_fn_exists "$gen_fn"; then
        _compose_err "lazy_seq: generator function '$gen_fn' not found"
        return 1
    fi

    # Generate unique sequence ID
    local seq_id
    seq_id="seq_$$_${RANDOM}"

    # Store sequence state: generator and current index
    _MAINFRAME_LAZY_SEQ_STATE["${seq_id}_gen"]="$gen_fn"
    _MAINFRAME_LAZY_SEQ_STATE["${seq_id}_idx"]=0

    printf '%s' "$seq_id"
}

# @pre: n is a positive integer, seq_id is a valid lazy sequence
# @post: n values are generated and printed (newline-separated)
# @idempotent: no (advances sequence state)
# @returns: 0 on success, values printed; 1 on error
#
# Take n elements from a lazy sequence.
# Advances the sequence state so subsequent calls get next elements.
#
# Usage: take_lazy 5 "$seq_id"
take_lazy() {
    local n="$1"
    local seq_id="$2"

    if [[ -z "$n" ]] || [[ -z "$seq_id" ]]; then
        _compose_err "take_lazy requires n and seq_id"
        return 1
    fi

    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        _compose_err "take_lazy: n must be a non-negative integer"
        return 1
    fi

    # Get generator function
    local gen_fn="${_MAINFRAME_LAZY_SEQ_STATE[${seq_id}_gen]:-}"
    if [[ -z "$gen_fn" ]]; then
        _compose_err "take_lazy: unknown sequence '$seq_id'"
        return 1
    fi

    # Get current index
    local idx="${_MAINFRAME_LAZY_SEQ_STATE[${seq_id}_idx]:-0}"

    # Generate n values
    local i
    for ((i=0; i<n; i++)); do
        "$gen_fn" "$idx"
        printf '\n'
        idx=$((idx + 1))
    done

    # Update sequence state
    _MAINFRAME_LAZY_SEQ_STATE["${seq_id}_idx"]="$idx"
}

# =============================================================================
# MEMOIZATION (extending cache.sh patterns)
# =============================================================================

# @pre: fn is a declared function
# @post: fn is wrapped with in-memory memoization
# @idempotent: no (double-wrap creates nested memoization)
# @returns: 0 on success, memoized function name printed; 1 on error
#
# Create a memoized version of a function using in-memory cache.
# Faster than disk-based memoize from cache.sh for session-local caching.
#
# Usage: memo_fn=$(memoize_fn "expensive_compute")
#        result=$($memo_fn "arg")  # Computed
#        result=$($memo_fn "arg")  # Cached
memoize_fn() {
    local fn="$1"

    if [[ -z "$fn" ]]; then
        _compose_err "memoize_fn requires a function argument"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "memoize_fn: function '$fn' not found"
        return 1
    fi

    # Generate memoized function name
    local memo_name="_memo_${fn}_$$_${RANDOM}"

    # Create the memoized function
    eval "${memo_name}() {
        # Build cache key from args
        local _key=\"${fn}\"
        local _arg
        for _arg in \"\$@\"; do
            _key+=\"|\${_arg}\"
        done

        # Check cache
        if [[ -v \"_MAINFRAME_COMPOSE_MEMO_CACHE[\$_key]\" ]]; then
            printf '%s' \"\${_MAINFRAME_COMPOSE_MEMO_CACHE[\$_key]}\"
            return 0
        fi

        # Compute and cache
        local _result
        _result=\$($fn \"\$@\")
        local _rc=\$?

        if [[ \$_rc -eq 0 ]]; then
            _MAINFRAME_COMPOSE_MEMO_CACHE[\"\$_key\"]=\"\$_result\"
        fi

        printf '%s' \"\$_result\"
        return \$_rc
    }"

    printf '%s' "$memo_name"
}

# @pre: fn_pattern matches function names in memo cache
# @post: matching cache entries cleared
# @idempotent: yes
# @returns: 0, count of cleared entries printed
#
# Clear memoization cache for functions matching a pattern.
# Without pattern, clears all in-memory memo cache.
#
# Usage: cache_clear_fn "expensive_*"
# Usage: cache_clear_fn  # Clear all
cache_clear_fn() {
    local pattern="${1:-}"
    local count=0

    if [[ -z "$pattern" ]]; then
        # Clear all
        count=${#_MAINFRAME_COMPOSE_MEMO_CACHE[@]}
        _MAINFRAME_COMPOSE_MEMO_CACHE=()
    else
        # Clear matching
        local key
        for key in "${!_MAINFRAME_COMPOSE_MEMO_CACHE[@]}"; do
            if [[ "$key" == $pattern* ]]; then
                unset "_MAINFRAME_COMPOSE_MEMO_CACHE[$key]"
                count=$((count + 1))
            fi
        done
    fi

    printf '%d' "$count"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# @pre: none
# @post: all compose module state is cleared
# @idempotent: yes
# @returns: 0
#
# Reset all compose module state (thunks, sequences, memo cache).
# Useful for testing or starting fresh.
#
# Usage: compose_reset
compose_reset() {
    _MAINFRAME_THUNKS=()
    _MAINFRAME_THUNK_CACHE=()
    _MAINFRAME_THUNK_COUNTER=0
    _MAINFRAME_LAZY_SEQ_STATE=()
    _MAINFRAME_COMPOSE_MEMO_CACHE=()
}

# @pre: none
# @post: compose module statistics printed
# @idempotent: yes
# @returns: 0
#
# Display compose module statistics.
#
# Usage: compose_stats
# Usage: compose_stats --json
compose_stats() {
    local json_output=false
    [[ "${1:-}" == "--json" ]] && json_output=true

    local thunk_count=${#_MAINFRAME_THUNKS[@]}
    local cached_thunks=${#_MAINFRAME_THUNK_CACHE[@]}
    local seq_count=0
    local memo_entries=${#_MAINFRAME_COMPOSE_MEMO_CACHE[@]}

    # Count unique sequences
    local key
    for key in "${!_MAINFRAME_LAZY_SEQ_STATE[@]}"; do
        [[ "$key" == *_gen ]] && seq_count=$((seq_count + 1))
    done

    if [[ "$json_output" == true ]]; then
        printf '{"thunks":%d,"cached_thunks":%d,"lazy_sequences":%d,"memo_entries":%d}' \
            "$thunk_count" "$cached_thunks" "$seq_count" "$memo_entries"
    else
        printf 'Compose Module Statistics:\n'
        printf '  Thunks:          %d\n' "$thunk_count"
        printf '  Cached Thunks:   %d\n' "$cached_thunks"
        printf '  Lazy Sequences:  %d\n' "$seq_count"
        printf '  Memo Entries:    %d\n' "$memo_entries"
    fi
}

# =============================================================================
# ADDITIONAL COMPOSITION PATTERNS
# =============================================================================

# @pre: fns are valid function names
# @post: returns function that tries each fn until one succeeds
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a function that tries each function in order until one succeeds.
# Useful for fallback chains.
#
# Usage: fallback=$(try_each "parse_json" "parse_yaml" "parse_toml")
try_each() {
    local -a funcs=("$@")
    local n=${#funcs[@]}

    if [[ $n -eq 0 ]]; then
        _compose_err "try_each requires at least one function"
        return 1
    fi

    # Validate all functions exist
    local fn
    for fn in "${funcs[@]}"; do
        if ! _compose_fn_exists "$fn"; then
            _compose_err "try_each: function '$fn' not found"
            return 1
        fi
    done

    # Generate function name
    local try_name="_try_each_$$_${RANDOM}"

    # Build function body
    local body='local _result _rc'
    local i
    for ((i=0; i<n; i++)); do
        body+=$'\n'"_result=\$(${funcs[$i]} \"\$@\" 2>/dev/null)"
        body+=$'\n''_rc=$?'
        body+=$'\n''if [[ $_rc -eq 0 ]]; then printf "%s" "$_result"; return 0; fi'
    done
    body+=$'\n''return 1'

    eval "${try_name}() { $body; }"

    printf '%s' "$try_name"
}

# @pre: predicate and fn are valid functions
# @post: returns function that only applies fn when predicate is true
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a conditional function: applies fn only when predicate returns true.
# Otherwise returns input unchanged.
#
# Usage: upper_if_long=$(when "is_long" "uppercase"); $upper_if_long "short"
when() {
    local predicate="$1"
    local fn="$2"

    if [[ -z "$predicate" ]] || [[ -z "$fn" ]]; then
        _compose_err "when requires predicate and function arguments"
        return 1
    fi

    if ! _compose_fn_exists "$predicate"; then
        _compose_err "when: predicate '$predicate' not found"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "when: function '$fn' not found"
        return 1
    fi

    # Generate function name
    local when_name="_when_${predicate}_${fn}_$$_${RANDOM}"

    # Create conditional function
    eval "${when_name}() {
        local _input=\"\$1\"
        if $predicate \"\$_input\"; then
            $fn \"\$_input\"
        else
            printf '%s' \"\$_input\"
        fi
    }"

    printf '%s' "$when_name"
}

# @pre: predicate, then_fn, else_fn are valid functions
# @post: returns function implementing if-then-else
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create an if-then-else function based on a predicate.
#
# Usage: classify=$(if_else "is_positive" "handle_positive" "handle_negative")
if_else() {
    local predicate="$1"
    local then_fn="$2"
    local else_fn="$3"

    if [[ -z "$predicate" ]] || [[ -z "$then_fn" ]] || [[ -z "$else_fn" ]]; then
        _compose_err "if_else requires predicate, then_fn, and else_fn"
        return 1
    fi

    if ! _compose_fn_exists "$predicate"; then
        _compose_err "if_else: predicate '$predicate' not found"
        return 1
    fi

    if ! _compose_fn_exists "$then_fn"; then
        _compose_err "if_else: then_fn '$then_fn' not found"
        return 1
    fi

    if ! _compose_fn_exists "$else_fn"; then
        _compose_err "if_else: else_fn '$else_fn' not found"
        return 1
    fi

    # Generate function name
    local ifelse_name="_ifelse_$$_${RANDOM}"

    # Create if-else function
    eval "${ifelse_name}() {
        if $predicate \"\$@\"; then
            $then_fn \"\$@\"
        else
            $else_fn \"\$@\"
        fi
    }"

    printf '%s' "$ifelse_name"
}

# @pre: n is a positive integer, fn is a valid function
# @post: returns function that applies fn n times
# @idempotent: yes
# @returns: 0 on success, function name printed; 1 on error
#
# Create a function that applies fn n times to its input.
#
# Usage: triple=$(times 3 "double"); $triple 1  # 8 (1->2->4->8)
times() {
    local n="$1"
    local fn="$2"

    if [[ -z "$n" ]] || [[ -z "$fn" ]]; then
        _compose_err "times requires n and function arguments"
        return 1
    fi

    if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 0 ]]; then
        _compose_err "times: n must be a non-negative integer"
        return 1
    fi

    if ! _compose_fn_exists "$fn"; then
        _compose_err "times: function '$fn' not found"
        return 1
    fi

    # Generate function name
    local times_name="_times_${n}_${fn}_$$_${RANDOM}"

    # Build function body
    local body='local __val="$1"'
    local i
    for ((i=0; i<n; i++)); do
        body+=$'\n'"__val=\$($fn \"\$__val\")"
    done
    body+=$'\n''printf "%s" "$__val"'

    eval "${times_name}() { $body; }"

    printf '%s' "$times_name"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_COMPOSE_EXPORTS=(
    # Core Composition
    compose
    pipe_fn
    chain
    # Partial Application
    partial
    curry
    flip
    # Higher-Order Functions
    tap
    identity
    constant
    apply
    # Lazy Evaluation
    lazy
    force
    lazy_seq
    take_lazy
    # Memoization
    memoize_fn
    cache_clear_fn
    # Utility
    compose_reset
    compose_stats
    # Additional Patterns
    try_each
    when
    if_else
    times
)

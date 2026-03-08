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

# Absolute path to this library, used by generated wrapper scripts.
_MAINFRAME_COMPOSE_LIB_PATH="${BASH_SOURCE[0]}"

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

# Check if function exists (declared or command)
_compose_fn_exists() {
    local fn="$1"
    declare -F "$fn" &>/dev/null || type -t "$fn" &>/dev/null || [[ -x "$fn" ]]
}

_compose_add_wrapper_dir_to_path() {
    local wrapper_dir="${MAINFRAME_THUNK_DIR}/wrappers"
    case ":$PATH:" in
        *":$wrapper_dir:"*) ;;
        *)
            PATH="${wrapper_dir}:$PATH"
            export PATH
            ;;
    esac
}

_compose_ensure_dirs() {
    mkdir -p \
        "${MAINFRAME_THUNK_DIR}/wrappers" \
        "${MAINFRAME_THUNK_DIR}/thunks" \
        "${MAINFRAME_THUNK_DIR}/seq" \
        "${MAINFRAME_THUNK_DIR}/memo"
    _compose_add_wrapper_dir_to_path
}

_compose_sanitize_name() {
    local value="$1"
    value="${value//[^a-zA-Z0-9_]/_}"
    printf '%s' "$value"
}

_compose_unique_suffix() {
    printf '%s_%s_%s' "$$" "${BASHPID:-$$}" "${RANDOM}${RANDOM}"
}

_compose_make_name() {
    local prefix="$1"
    shift

    local name="$prefix"
    local part
    for part in "$@"; do
        [[ -n "$part" ]] || continue
        name+="_$(_compose_sanitize_name "$part")"
    done
    name+="_$(_compose_unique_suffix)"
    printf '%s' "$name"
}

_compose_wrapper_path() {
    local name="$1"
    printf '%s/wrappers/%s' "$MAINFRAME_THUNK_DIR" "$name"
}

_compose_thunk_meta_path() {
    local thunk_id="$1"
    printf '%s/thunks/%s.meta' "$MAINFRAME_THUNK_DIR" "$thunk_id"
}

_compose_thunk_cache_path() {
    local thunk_id="$1"
    printf '%s/thunks/%s.cache' "$MAINFRAME_THUNK_DIR" "$thunk_id"
}

_compose_seq_meta_path() {
    local seq_id="$1"
    printf '%s/seq/%s.meta' "$MAINFRAME_THUNK_DIR" "$seq_id"
}

_compose_memo_dir() {
    local memo_name="$1"
    printf '%s/memo/%s' "$MAINFRAME_THUNK_DIR" "$memo_name"
}

_compose_emit_context() {
    local var
    while IFS= read -r var; do
        case "$var" in
            MAINFRAME_*|TEST_*|BATS_*)
                declare -p "$var" 2>/dev/null || true
                ;;
        esac
    done < <(compgen -v)
}

_compose_array_literal() {
    local literal="("
    local arg quoted
    for arg in "$@"; do
        printf -v quoted '%q' "$arg"
        literal+=" ${quoted}"
    done
    literal+=" )"
    printf '%s' "$literal"
}

_compose_write_script() {
    local name="$1"
    local body="$2"
    local path
    local indented_body
    path=$(_compose_wrapper_path "$name")
    indented_body="${body//$'\n'/$'\n    '}"

    _compose_ensure_dirs || return 1

    {
        printf '#!/usr/bin/env bash\n'
        _compose_emit_context
        printf '\nmain() {\n    %s\n}\n\nmain "$@"\n' "$indented_body"
    } >"$path" || return 1

    chmod 700 "$path" || return 1
    printf '%s' "$path"
}

_compose_publish_wrapper() {
    local name="$1"
    local body="$2"
    _compose_write_script "$name" "$body" >/dev/null || return 1
    printf '%s' "$name"
}

_compose_result_ref() {
    local callable="$1"
    local wrapper_prefix="${MAINFRAME_THUNK_DIR}/wrappers/"
    if [[ "$callable" == "${wrapper_prefix}"* ]]; then
        printf '%s' "${callable##*/}"
    else
        printf '%s' "$callable"
    fi
}

_compose_materialize_callable() {
    local fn="$1"
    local command_path

    if [[ -x "$fn" ]]; then
        printf '%s' "$fn"
        return 0
    fi

    command_path=$(type -P "$fn" 2>/dev/null || true)
    if [[ -n "$command_path" ]]; then
        printf '%s' "$command_path"
        return 0
    fi

    if declare -F "$fn" &>/dev/null; then
        local name
        name=$(_compose_make_name "_call" "$fn")
        local fn_q
        printf -v fn_q '%q' "$fn"
        local body=""
        body+="$(declare -f "$fn")"$'\n'
        body+="${fn_q} \"\$@\""
        _compose_write_script "$name" "$body" || return 1
        return 0
    fi

    if type -t "$fn" &>/dev/null; then
        local name
        name=$(_compose_make_name "_call" "$fn")
        local fn_q
        printf -v fn_q '%q' "$fn"
        _compose_write_script "$name" "${fn_q} \"\$@\"" || return 1
        return 0
    fi

    return 1
}

_compose_hash_text() {
    local input="$1"
    local digest
    if command -v sha256sum &>/dev/null; then
        digest=$(printf '%s' "$input" | sha256sum)
    elif command -v shasum &>/dev/null; then
        digest=$(printf '%s' "$input" | shasum -a 256)
    else
        digest=$(printf '%s' "$input" | cksum)
    fi
    printf '%s' "${digest%% *}"
}

_compose_hash_args() {
    local payload=""
    local arg quoted
    for arg in "$@"; do
        printf -v quoted '%q' "$arg"
        payload+="${quoted}"$'\n'
    done
    _compose_hash_text "$payload"
}

_compose_count_regular_files() {
    local dir="$1"
    local pattern="$2"
    local count=0
    local nullglob_was_set=0
    local file
    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob
    local -a files=("$dir"/$pattern)
    if [[ $nullglob_was_set -eq 0 ]]; then
        shopt -u nullglob
    fi
    for file in "${files[@]}"; do
        [[ -f "$file" ]] && count=$((count + 1))
    done
    printf '%d' "$count"
}

_compose_memo_entry_count() {
    local memo_dir="$1"
    _compose_count_regular_files "${memo_dir}/entries" '*'
}

_compose_write_state_file() {
    local path="$1"
    shift
    {
        printf '%s\n' "$@"
    } >"$path"
}

_compose_create_curry_wrapper_internal() {
    local callable="$1"
    local label="$2"
    local arity="$3"
    shift 3
    local -a collected=("$@")

    local name
    name=$(_compose_make_name "_curry" "$label" "$arity")

    local callable_q label_q arity_q lib_q
    local collected_literal
    printf -v callable_q '%q' "$callable"
    printf -v label_q '%q' "$label"
    printf -v arity_q '%q' "$arity"
    printf -v lib_q '%q' "$_MAINFRAME_COMPOSE_LIB_PATH"
    collected_literal=$(_compose_array_literal "${collected[@]}")

    local body=""
    body+="source ${lib_q}"$'\n'
    body+="local -a _compose_collected=${collected_literal}"$'\n'
    body+='local -a _compose_combined=("${_compose_collected[@]}" "$@")'$'\n'
    body+="if [[ \${#_compose_combined[@]} -ge ${arity} ]]; then"$'\n'
    body+="    ${callable_q} \"\${_compose_combined[@]}\""$'\n'
    body+='else'$'\n'
    body+="    _compose_create_curry_wrapper_internal ${callable_q} ${label_q} ${arity_q} \"\${_compose_combined[@]}\""$'\n'
    body+='fi'

    _compose_publish_wrapper "$name" "$body"
}

_compose_memo_wrapper_run() {
    local memo_name="$1"
    local callable="$2"
    shift 2

    local memo_dir entry_dir key cache_path
    memo_dir=$(_compose_memo_dir "$memo_name")
    entry_dir="${memo_dir}/entries"
    mkdir -p "$entry_dir" || return 1

    key=$(_compose_hash_args "$@")
    cache_path="${entry_dir}/${key}"

    if [[ -f "$cache_path" ]]; then
        cat "$cache_path"
        return 0
    fi

    local result rc
    result=$("$callable" "$@")
    rc=$?
    if [[ $rc -eq 0 ]]; then
        printf '%s' "$result" >"$cache_path"
    fi
    printf '%s' "$result"
    return $rc
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

    local f_cmd g_cmd
    f_cmd=$(_compose_materialize_callable "$f") || {
        _compose_err "compose: failed to materialize '$f'"
        return 1
    }
    g_cmd=$(_compose_materialize_callable "$g") || {
        _compose_err "compose: failed to materialize '$g'"
        return 1
    }

    local composed_name body f_q g_q
    composed_name=$(_compose_make_name "_composed" "$f" "$g")
    printf -v f_q '%q' "$f_cmd"
    printf -v g_q '%q' "$g_cmd"
    body='local _compose_inner_result _compose_rc'$'\n'
    body+="_compose_inner_result=\$(${g_q} \"\$@\")"$'\n'
    body+='_compose_rc=$?'$'\n'
    body+='[[ $_compose_rc -eq 0 ]] || return $_compose_rc'$'\n'
    body+="${f_q} \"\$_compose_inner_result\""

    _compose_publish_wrapper "$composed_name" "$body"
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

    local -a callables=()
    for fn in "${funcs[@]}"; do
        local callable
        callable=$(_compose_materialize_callable "$fn") || {
            _compose_err "pipe_fn: failed to materialize '$fn'"
            return 1
        }
        callables+=("$callable")
    done

    # Single function - return as-is
    if [[ $n -eq 1 ]]; then
        _compose_result_ref "${callables[0]}"
        return 0
    fi

    local piped_name body callables_literal
    piped_name=$(_compose_make_name "_piped" "${funcs[@]}")
    callables_literal=$(_compose_array_literal "${callables[@]}")
    body+="local -a _compose_cmds=${callables_literal}"$'\n'
    body+='local _compose_value="${1-}"'$'\n'
    body+='if [[ $# -gt 0 ]]; then shift; fi'$'\n'
    body+='local _compose_cmd'$'\n'
    body+='for _compose_cmd in "${_compose_cmds[@]}"; do'$'\n'
    body+='    _compose_value=$("$_compose_cmd" "$_compose_value" "$@")'$'\n'
    body+='done'$'\n'
    body+='printf "%s" "$_compose_value"'

    _compose_publish_wrapper "$piped_name" "$body"
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

    local -a callables=()
    for fn in "${funcs[@]}"; do
        local callable
        callable=$(_compose_materialize_callable "$fn") || {
            _compose_err "chain: failed to materialize '$fn'"
            return 1
        }
        callables+=("$callable")
    done

    local chained_name body callables_literal
    chained_name=$(_compose_make_name "_chained" "${funcs[@]}")
    callables_literal=$(_compose_array_literal "${callables[@]}")
    body+="local -a _compose_cmds=${callables_literal}"$'\n'
    body+='local _compose_value="${1-}" _compose_rc'$'\n'
    body+='if [[ $# -gt 0 ]]; then shift; fi'$'\n'
    body+='local _compose_cmd'$'\n'
    body+='for _compose_cmd in "${_compose_cmds[@]}"; do'$'\n'
    body+='    _compose_value=$("$_compose_cmd" "$_compose_value" "$@")'$'\n'
    body+='    _compose_rc=$?'$'\n'
    body+='    [[ $_compose_rc -eq 0 ]] || return $_compose_rc'$'\n'
    body+='done'$'\n'
    body+='printf "%s" "$_compose_value"'

    _compose_publish_wrapper "$chained_name" "$body"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "partial: failed to materialize '$fn'"
        return 1
    }

    local partial_name body callable_q preset_literal
    partial_name=$(_compose_make_name "_partial" "$fn")
    printf -v callable_q '%q' "$callable"
    preset_literal=$(_compose_array_literal "${preset_args[@]}")
    body+="local -a _compose_preset=${preset_literal}"$'\n'
    body+="${callable_q} \"\${_compose_preset[@]}\" \"\$@\""

    _compose_publish_wrapper "$partial_name" "$body"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "curry: failed to materialize '$fn'"
        return 1
    }

    _compose_create_curry_wrapper_internal "$callable" "$fn" "$arity"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "flip: failed to materialize '$fn'"
        return 1
    }

    local flip_name body callable_q
    flip_name=$(_compose_make_name "_flip" "$fn")
    printf -v callable_q '%q' "$callable"
    body+='local _compose_a="${1-}" _compose_b="${2-}"'$'\n'
    body+='if [[ $# -ge 2 ]]; then shift 2; else shift $#; fi'$'\n'
    body+="${callable_q} \"\$_compose_b\" \"\$_compose_a\" \"\$@\""

    _compose_publish_wrapper "$flip_name" "$body"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "tap: failed to materialize '$fn'"
        return 1
    }

    local tap_name body callable_q
    tap_name=$(_compose_make_name "_tap" "$fn")
    printf -v callable_q '%q' "$callable"
    body+='local _compose_input="${1-}"'$'\n'
    body+="${callable_q} \"\$_compose_input\" >/dev/null 2>&1 || true"$'\n'
    body+='printf "%s" "$_compose_input"'

    _compose_publish_wrapper "$tap_name" "$body"
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

    local const_name body value_q
    const_name=$(_compose_make_name "_const")
    printf -v value_q '%q' "$value"
    body="printf '%s' ${value_q}"

    _compose_publish_wrapper "$const_name" "$body"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "lazy: failed to materialize '$fn'"
        return 1
    }

    local thunk_id thunk_meta
    thunk_id="thunk_$(_compose_unique_suffix)"
    thunk_meta=$(_compose_thunk_meta_path "$thunk_id")

    _compose_ensure_dirs || return 1
    _compose_write_state_file "$thunk_meta" \
        "callable=$(printf '%q' "$callable")" \
        "declare -a args=$(_compose_array_literal "${args[@]}")"

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

    _compose_ensure_dirs || return 1

    local thunk_meta thunk_cache
    thunk_meta=$(_compose_thunk_meta_path "$thunk_id")
    thunk_cache=$(_compose_thunk_cache_path "$thunk_id")

    if [[ -f "$thunk_cache" ]]; then
        cat "$thunk_cache"
        return 0
    fi

    if [[ ! -f "$thunk_meta" ]]; then
        _compose_err "force: unknown thunk '$thunk_id'"
        return 1
    fi

    local callable
    local -a args=()
    # shellcheck disable=SC1090
    source "$thunk_meta"

    local result rc
    result=$("$callable" "${args[@]}")
    rc=$?

    if [[ $rc -eq 0 ]]; then
        printf '%s' "$result" >"$thunk_cache"
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

    local callable
    callable=$(_compose_materialize_callable "$gen_fn") || {
        _compose_err "lazy_seq: failed to materialize '$gen_fn'"
        return 1
    }

    local seq_id seq_meta
    seq_id="seq_$(_compose_unique_suffix)"
    seq_meta=$(_compose_seq_meta_path "$seq_id")
    _compose_ensure_dirs || return 1
    _compose_write_state_file "$seq_meta" \
        "callable=$(printf '%q' "$callable")" \
        "idx=0"

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

    _compose_ensure_dirs || return 1

    local seq_meta callable idx=0
    seq_meta=$(_compose_seq_meta_path "$seq_id")

    if [[ ! -f "$seq_meta" ]]; then
        _compose_err "take_lazy: unknown sequence '$seq_id'"
        return 1
    fi

    # shellcheck disable=SC1090
    source "$seq_meta"

    local i
    for ((i=0; i<n; i++)); do
        "$callable" "$idx"
        printf '\n'
        idx=$((idx + 1))
    done

    _compose_write_state_file "$seq_meta" \
        "callable=$(printf '%q' "$callable")" \
        "idx=${idx}"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "memoize_fn: failed to materialize '$fn'"
        return 1
    }

    local memo_name memo_dir body callable_q memo_q lib_q
    memo_name=$(_compose_make_name "_memo" "$fn")
    memo_dir=$(_compose_memo_dir "$memo_name")
    mkdir -p "${memo_dir}/entries" || return 1
    _compose_write_state_file "${memo_dir}/meta" \
        "label=$(printf '%q' "$fn")" \
        "callable=$(printf '%q' "$callable")"

    printf -v callable_q '%q' "$callable"
    printf -v memo_q '%q' "$memo_name"
    printf -v lib_q '%q' "$_MAINFRAME_COMPOSE_LIB_PATH"
    body="source ${lib_q}"$'\n'
    body+="_compose_memo_wrapper_run ${memo_q} ${callable_q} \"\$@\""

    _compose_publish_wrapper "$memo_name" "$body"
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

    _compose_ensure_dirs || return 1

    if [[ -z "$pattern" ]]; then
        local memo_dir
        local nullglob_was_set=0
        shopt -q nullglob && nullglob_was_set=1
        shopt -s nullglob
        local -a memo_dirs=("${MAINFRAME_THUNK_DIR}/memo"/*)
        if [[ $nullglob_was_set -eq 0 ]]; then
            shopt -u nullglob
        fi
        for memo_dir in "${memo_dirs[@]}"; do
            [[ -d "$memo_dir" ]] || continue
            count=$((count + $(_compose_memo_entry_count "$memo_dir")))
            rm -rf "${memo_dir}/entries"
            mkdir -p "${memo_dir}/entries"
        done
    else
        local meta_file memo_dir label callable
        local nullglob_was_set=0
        shopt -q nullglob && nullglob_was_set=1
        shopt -s nullglob
        local -a meta_files=("${MAINFRAME_THUNK_DIR}/memo"/*/meta)
        if [[ $nullglob_was_set -eq 0 ]]; then
            shopt -u nullglob
        fi
        for meta_file in "${meta_files[@]}"; do
            label=""
            callable=""
            # shellcheck disable=SC1090
            source "$meta_file"
            if [[ "$label" == ${pattern}* ]]; then
                memo_dir="${meta_file%/meta}"
                count=$((count + $(_compose_memo_entry_count "$memo_dir")))
                rm -rf "${memo_dir}/entries"
                mkdir -p "${memo_dir}/entries"
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
    rm -rf "$MAINFRAME_THUNK_DIR"
    _compose_ensure_dirs
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

    _compose_ensure_dirs || return 1

    local thunk_count cached_thunks seq_count memo_entries
    thunk_count=$(_compose_count_regular_files "${MAINFRAME_THUNK_DIR}/thunks" '*.meta')
    cached_thunks=$(_compose_count_regular_files "${MAINFRAME_THUNK_DIR}/thunks" '*.cache')
    seq_count=$(_compose_count_regular_files "${MAINFRAME_THUNK_DIR}/seq" '*.meta')
    memo_entries=0

    local memo_dir
    local nullglob_was_set=0
    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob
    local -a memo_dirs=("${MAINFRAME_THUNK_DIR}/memo"/*)
    if [[ $nullglob_was_set -eq 0 ]]; then
        shopt -u nullglob
    fi
    for memo_dir in "${memo_dirs[@]}"; do
        [[ -d "$memo_dir" ]] || continue
        memo_entries=$((memo_entries + $(_compose_memo_entry_count "$memo_dir")))
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

    local -a callables=()
    for fn in "${funcs[@]}"; do
        local callable
        callable=$(_compose_materialize_callable "$fn") || {
            _compose_err "try_each: failed to materialize '$fn'"
            return 1
        }
        callables+=("$callable")
    done

    local try_name body callables_literal
    try_name=$(_compose_make_name "_try_each" "${funcs[@]}")
    callables_literal=$(_compose_array_literal "${callables[@]}")
    body+="local -a _compose_cmds=${callables_literal}"$'\n'
    body+='local _compose_cmd _compose_result _compose_rc'$'\n'
    body+='for _compose_cmd in "${_compose_cmds[@]}"; do'$'\n'
    body+='    _compose_result=$("$_compose_cmd" "$@" 2>/dev/null)'$'\n'
    body+='    _compose_rc=$?'$'\n'
    body+='    if [[ $_compose_rc -eq 0 ]]; then printf "%s" "$_compose_result"; return 0; fi'$'\n'
    body+='done'$'\n'
    body+='return 1'

    _compose_publish_wrapper "$try_name" "$body"
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

    local predicate_cmd fn_cmd
    predicate_cmd=$(_compose_materialize_callable "$predicate") || {
        _compose_err "when: failed to materialize predicate '$predicate'"
        return 1
    }
    fn_cmd=$(_compose_materialize_callable "$fn") || {
        _compose_err "when: failed to materialize '$fn'"
        return 1
    }

    local when_name body predicate_q fn_q
    when_name=$(_compose_make_name "_when" "$predicate" "$fn")
    printf -v predicate_q '%q' "$predicate_cmd"
    printf -v fn_q '%q' "$fn_cmd"
    body+='local _compose_input="${1-}"'$'\n'
    body+="if ${predicate_q} \"\$_compose_input\" >/dev/null 2>&1; then"$'\n'
    body+="    ${fn_q} \"\$_compose_input\""$'\n'
    body+='else'$'\n'
    body+='    printf "%s" "$_compose_input"'$'\n'
    body+='fi'

    _compose_publish_wrapper "$when_name" "$body"
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

    local predicate_cmd then_cmd else_cmd
    predicate_cmd=$(_compose_materialize_callable "$predicate") || {
        _compose_err "if_else: failed to materialize predicate '$predicate'"
        return 1
    }
    then_cmd=$(_compose_materialize_callable "$then_fn") || {
        _compose_err "if_else: failed to materialize '$then_fn'"
        return 1
    }
    else_cmd=$(_compose_materialize_callable "$else_fn") || {
        _compose_err "if_else: failed to materialize '$else_fn'"
        return 1
    }

    local ifelse_name body predicate_q then_q else_q
    ifelse_name=$(_compose_make_name "_ifelse" "$predicate" "$then_fn" "$else_fn")
    printf -v predicate_q '%q' "$predicate_cmd"
    printf -v then_q '%q' "$then_cmd"
    printf -v else_q '%q' "$else_cmd"
    body+="if ${predicate_q} \"\$@\" >/dev/null 2>&1; then"$'\n'
    body+="    ${then_q} \"\$@\""$'\n'
    body+='else'$'\n'
    body+="    ${else_q} \"\$@\""$'\n'
    body+='fi'

    _compose_publish_wrapper "$ifelse_name" "$body"
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

    local callable
    callable=$(_compose_materialize_callable "$fn") || {
        _compose_err "times: failed to materialize '$fn'"
        return 1
    }

    local times_name body callable_q
    times_name=$(_compose_make_name "_times" "$n" "$fn")
    printf -v callable_q '%q' "$callable"
    body+='local _compose_value="${1-}"'$'\n'
    body+='local _compose_i'$'\n'
    body+="for ((_compose_i=0; _compose_i<${n}; _compose_i++)); do"$'\n'
    body+="    _compose_value=\$(${callable_q} \"\$_compose_value\")"$'\n'
    body+='done'$'\n'
    body+='printf "%s" "$_compose_value"'

    _compose_publish_wrapper "$times_name" "$body"
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

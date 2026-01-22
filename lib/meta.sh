#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/meta.sh - Metaprogramming and Indirect Reference Library
# =============================================================================
# Description: Variable introspection, dynamic calls, namerefs, constants
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_META_LOADED:-}" ]] && return 0
readonly _MAINFRAME_META_LOADED=1

# =============================================================================
# INDIRECT VARIABLE ACCESS
# =============================================================================

# Get variable value by name (indirect expansion)
# Usage: var_get "varname"
# Usage: var_get "varname" result_var  (no subshell, stores in result_var)
# Returns: Variable value via stdout or result_var
var_get() {
    local varname="$1"
    local result_var="${2:-}"

    # Validate variable name
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    if [[ -n "$result_var" ]]; then
        # Use nameref to avoid subshell
        local -n _var_get_src="$varname" 2>/dev/null || return 1
        local -n _var_get_dst="$result_var"
        _var_get_dst="$_var_get_src"
    else
        # Use indirect expansion
        printf '%s' "${!varname}"
    fi
}

# Set variable by name
# Usage: var_set "varname" "value"
# Returns: 0 on success, 1 on invalid name
var_set() {
    local varname="$1"
    local value="$2"

    # Validate variable name (must be valid bash identifier)
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Use printf -v for safe assignment (no eval)
    printf -v "$varname" '%s' "$value"
}

# Check if variable is set (may be empty)
# Usage: var_exists "varname"
# Returns: 0 if set, 1 if unset
var_exists() {
    local varname="$1"

    # Validate variable name
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Use -v test for existence check
    [[ -v "$varname" ]]
}

# Check if variable is set and non-empty
# Usage: var_nonempty "varname"
# Returns: 0 if set and non-empty, 1 otherwise
var_nonempty() {
    local varname="$1"

    # Validate variable name
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Use -v and -n tests
    [[ -v "$varname" ]] && [[ -n "${!varname}" ]]
}

# Unset variable by name
# Usage: var_unset "varname"
# Returns: 0 on success
var_unset() {
    local varname="$1"

    # Validate variable name
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    unset "$varname"
}

# =============================================================================
# VARIABLE ENUMERATION
# =============================================================================

# Get all variable names matching prefix
# Usage: vars_with_prefix "PREFIX_" result_array
# Populates result_array with matching variable names
vars_with_prefix() {
    local prefix="$1"
    local -n _result_array="$2"

    # Clear result array
    _result_array=()

    # Use compgen to get matching variables
    local varname
    while IFS= read -r varname; do
        [[ -n "$varname" ]] && _result_array+=("$varname")
    done < <(compgen -v "$prefix" 2>/dev/null || true)
}

# Get all variable names matching pattern (glob)
# Usage: vars_matching "MY_*_CONFIG" result_array
vars_matching() {
    local pattern="$1"
    local -n _result_array="$2"

    # Clear result array
    _result_array=()

    # Get all variables and filter by pattern
    local varname
    while IFS= read -r varname; do
        # shellcheck disable=SC2053
        [[ -n "$varname" && "$varname" == $pattern ]] && _result_array+=("$varname")
    done < <(compgen -v 2>/dev/null || true)
}

# Get all exported variable names
# Usage: vars_exported result_array
vars_exported() {
    local -n _result_array="$1"

    # Clear result array
    _result_array=()

    # Parse export output
    local line
    while IFS= read -r line; do
        # Format: declare -x VARNAME="value" or declare -x VARNAME
        if [[ "$line" =~ ^declare\ -[^\ ]*x[^\ ]*\ ([a-zA-Z_][a-zA-Z0-9_]*)= ]]; then
            _result_array+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^declare\ -[^\ ]*x[^\ ]*\ ([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
            _result_array+=("${BASH_REMATCH[1]}")
        fi
    done < <(declare -x 2>/dev/null || true)
}

# =============================================================================
# VARIABLE COPY AND SWAP
# =============================================================================

# Copy variable to new name
# Usage: var_copy "source" "dest"
# Returns: 0 on success, 1 if source doesn't exist
var_copy() {
    local source="$1"
    local dest="$2"

    # Validate variable names
    [[ "$source" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    [[ "$dest" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Check source exists
    [[ -v "$source" ]] || return 1

    # Get type to handle arrays properly
    local decl
    decl=$(declare -p "$source" 2>/dev/null) || return 1

    if [[ "$decl" =~ ^declare\ -a ]]; then
        # Indexed array
        local -n _src="$source"
        local -n _dst="$dest"
        _dst=("${_src[@]}")
    elif [[ "$decl" =~ ^declare\ -A ]]; then
        # Associative array
        local -n _src="$source"
        local -n _dst="$dest"
        # Must use declare -A for associative arrays
        eval "declare -gA $dest"
        local -n _dst="$dest"
        local key
        for key in "${!_src[@]}"; do
            _dst["$key"]="${_src[$key]}"
        done
    else
        # Scalar
        printf -v "$dest" '%s' "${!source}"
    fi
}

# Swap two variables
# Usage: var_swap "var1" "var2"
# Returns: 0 on success, 1 if either doesn't exist
var_swap() {
    local var1="$1"
    local var2="$2"

    # Validate variable names
    [[ "$var1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    [[ "$var2" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Both must exist
    [[ -v "$var1" ]] || return 1
    [[ -v "$var2" ]] || return 1

    # Store first value temporarily
    local _swap_temp
    _swap_temp="${!var1}"

    # Swap using printf -v
    printf -v "$var1" '%s' "${!var2}"
    printf -v "$var2" '%s' "$_swap_temp"
}

# =============================================================================
# VARIABLE TYPE DETECTION
# =============================================================================

# Get variable type
# Usage: var_type "varname"
# Returns: string, array, assoc, integer, nameref, readonly, or unset
var_type() {
    local varname="$1"

    # Validate variable name
    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
        printf 'invalid'
        return 1
    }

    # Check if unset
    if ! [[ -v "$varname" ]]; then
        printf 'unset'
        return 0
    fi

    # Use declare -p to get type info
    local decl
    decl=$(declare -p "$varname" 2>/dev/null) || {
        printf 'unset'
        return 0
    }

    # Parse declare flags
    case "$decl" in
        "declare -n"*)
            printf 'nameref'
            ;;
        "declare -a"*)
            printf 'array'
            ;;
        "declare -A"*)
            printf 'assoc'
            ;;
        "declare -i"*)
            printf 'integer'
            ;;
        "declare -r"*)
            printf 'readonly'
            ;;
        "declare --"*)
            printf 'string'
            ;;
        *)
            # Check for combined flags
            if [[ "$decl" =~ declare\ -[^\ ]*n ]]; then
                printf 'nameref'
            elif [[ "$decl" =~ declare\ -[^\ ]*a ]]; then
                printf 'array'
            elif [[ "$decl" =~ declare\ -[^\ ]*A ]]; then
                printf 'assoc'
            elif [[ "$decl" =~ declare\ -[^\ ]*i ]]; then
                printf 'integer'
            else
                printf 'string'
            fi
            ;;
    esac
}

# Check if variable is array (indexed)
# Usage: var_is_array "varname"
var_is_array() {
    local varname="$1"
    [[ "$(var_type "$varname")" == "array" ]]
}

# Check if variable is associative array
# Usage: var_is_assoc "varname"
var_is_assoc() {
    local varname="$1"
    [[ "$(var_type "$varname")" == "assoc" ]]
}

# Check if variable is readonly
# Usage: var_is_readonly "varname"
var_is_readonly() {
    local varname="$1"

    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local decl
    decl=$(declare -p "$varname" 2>/dev/null) || return 1
    [[ "$decl" =~ declare\ -[^\ ]*r ]]
}

# =============================================================================
# CONSTANTS
# =============================================================================

# Define constant (readonly variable)
# Usage: const "NAME" "value"
# Returns: 0 on success, 1 if already exists as readonly
const() {
    local name="$1"
    local value="$2"

    # Validate variable name
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Check if already readonly
    if var_is_readonly "$name"; then
        return 1
    fi

    # Set and mark readonly
    printf -v "$name" '%s' "$value"
    readonly "$name"
}

# Define constant if not already set
# Usage: const_default "NAME" "default_value"
const_default() {
    local name="$1"
    local value="$2"

    # If already set (readonly or not), skip
    [[ -v "$name" ]] && return 0

    const "$name" "$value"
}

# =============================================================================
# FUNCTION INTROSPECTION
# =============================================================================

# Check if function exists
# Usage: func_exists "funcname"
# Returns: 0 if exists, 1 if not
func_exists() {
    local funcname="$1"
    declare -F "$funcname" &>/dev/null
}

# Dynamic function call by name
# Usage: call_func "funcname" arg1 arg2
# Returns: Function's return code
call_func() {
    local funcname="$1"
    shift

    # Check function exists
    func_exists "$funcname" || return 127

    # Call function with arguments
    "$funcname" "$@"
}

# Get function definition
# Usage: func_def "funcname"
# Returns: Function definition as string
func_def() {
    local funcname="$1"

    func_exists "$funcname" || return 1
    declare -f "$funcname"
}

# Get function source file and line (if available)
# Usage: func_source "funcname"
# Returns: "filename:line" or empty if not available
func_source() {
    local funcname="$1"

    func_exists "$funcname" || return 1

    # extdebug must be enabled for this to work
    shopt -s extdebug 2>/dev/null
    local info
    info=$(declare -F "$funcname" 2>/dev/null)
    shopt -u extdebug 2>/dev/null

    # Format: funcname line filename
    local line file
    read -r _ line file <<< "$info"
    [[ -n "$file" ]] && printf '%s:%s' "$file" "$line"
}

# List all functions matching prefix
# Usage: funcs_with_prefix "my_" result_array
funcs_with_prefix() {
    local prefix="$1"
    local -n _result_array="$2"

    # Clear result array
    _result_array=()

    local funcname
    while IFS= read -r funcname; do
        [[ -n "$funcname" ]] && _result_array+=("$funcname")
    done < <(compgen -A function "$prefix" 2>/dev/null || true)
}

# =============================================================================
# NAMEREF HELPERS
# =============================================================================

# Create a nameref to a variable
# Usage: var_ref "refname" "target"
# Note: Creates local nameref; useful in functions
var_ref() {
    local refname="$1"
    local target="$2"

    # Validate names
    [[ "$refname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    [[ "$target" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Use eval to create global nameref (declare -gn)
    eval "declare -gn $refname=$target"
}

# Get nameref target
# Usage: var_ref_target "refname"
# Returns: Target variable name
var_ref_target() {
    local refname="$1"

    # Validate name
    [[ "$refname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    # Check if it's a nameref
    local decl
    decl=$(declare -p "$refname" 2>/dev/null) || return 1
    [[ "$decl" =~ declare\ -[^\ ]*n ]] || return 1

    # Extract target: declare -n refname="target"
    if [[ "$decl" =~ =\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# =============================================================================
# DYNAMIC DISPATCH
# =============================================================================

# Call method on object-like structure
# Usage: call_method "prefix" "method" args...
# Example: call_method "myobj" "init" arg1  -> calls myobj_init arg1
call_method() {
    local prefix="$1"
    local method="$2"
    shift 2

    call_func "${prefix}_${method}" "$@"
}

# Check if method exists for prefix
# Usage: method_exists "prefix" "method"
method_exists() {
    local prefix="$1"
    local method="$2"

    func_exists "${prefix}_${method}"
}

# Call function if exists, otherwise return default
# Usage: call_or_default "funcname" "default" args...
call_or_default() {
    local funcname="$1"
    local default="$2"
    shift 2

    if func_exists "$funcname"; then
        "$funcname" "$@"
    else
        printf '%s' "$default"
    fi
}

# =============================================================================
# VARIABLE OPERATIONS
# =============================================================================

# Increment integer variable
# Usage: var_incr "varname" [amount]
var_incr() {
    local varname="$1"
    local amount="${2:-1}"

    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    [[ -v "$varname" ]] || { printf -v "$varname" '0'; }

    local current="${!varname}"
    [[ "$current" =~ ^-?[0-9]+$ ]] || return 1

    printf -v "$varname" '%d' "$((current + amount))"
}

# Decrement integer variable
# Usage: var_decr "varname" [amount]
var_decr() {
    local varname="$1"
    local amount="${2:-1}"

    var_incr "$varname" "-$amount"
}

# Append to variable
# Usage: var_append "varname" "suffix"
var_append() {
    local varname="$1"
    local suffix="$2"

    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local current="${!varname:-}"
    printf -v "$varname" '%s%s' "$current" "$suffix"
}

# Prepend to variable
# Usage: var_prepend "varname" "prefix"
var_prepend() {
    local varname="$1"
    local prefix="$2"

    [[ "$varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local current="${!varname:-}"
    printf -v "$varname" '%s%s' "$prefix" "$current"
}

# =============================================================================
# ARRAY OPERATIONS BY NAME
# =============================================================================

# Push to array by name
# Usage: array_push_byname "arrayname" value1 value2...
array_push_byname() {
    local arrayname="$1"
    shift

    [[ "$arrayname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local -n _arr="$arrayname"
    _arr+=("$@")
}

# Pop from array by name
# Usage: array_pop_byname "arrayname" [result_var]
array_pop_byname() {
    local arrayname="$1"
    local result_var="${2:-}"

    [[ "$arrayname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local -n _arr="$arrayname"
    [[ ${#_arr[@]} -gt 0 ]] || return 1

    local last_idx=$((${#_arr[@]} - 1))
    local last_val="${_arr[$last_idx]}"

    unset "_arr[$last_idx]"

    if [[ -n "$result_var" ]]; then
        printf -v "$result_var" '%s' "$last_val"
    else
        printf '%s' "$last_val"
    fi
}

# Get array length by name
# Usage: array_len_byname "arrayname"
array_len_byname() {
    local arrayname="$1"

    [[ "$arrayname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    local -n _arr="$arrayname"
    printf '%d' "${#_arr[@]}"
}

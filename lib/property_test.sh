#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/property_test.sh - QuickCheck-Style Property-Based Testing
# =============================================================================
# Description: Property-based testing framework for bash scripts with automatic
#              shrinking, value generation, statistical collection, and
#              reproducible test runs via seed control.
#
# Inspired by:
#   - Haskell QuickCheck (Koen Claessen, John Hughes)
#   - Python Hypothesis (David MacIver)
#   - Erlang PropEr
#
# Features:
#   - Generators for integers, floats, strings, arrays, and custom types
#   - Automatic shrinking of failing cases to minimal examples
#   - Statistical collection (classify, cover, label)
#   - Reproducible tests via seed control
#   - Design-by-Contract validation with structured JSON output
#
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROPERTY_TEST_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROPERTY_TEST_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default number of test iterations
declare -g PROP_DEFAULT_ITERATIONS="${PROP_DEFAULT_ITERATIONS:-100}"

# Maximum shrink attempts
declare -g PROP_MAX_SHRINKS="${PROP_MAX_SHRINKS:-100}"

# Random seed (set for reproducibility)
declare -g PROP_SEED="${PROP_SEED:-}"

# Verbose output mode
declare -g PROP_VERBOSE="${PROP_VERBOSE:-0}"

# Current test generation size (grows with iterations)
declare -g _PROP_SIZE=10

# Statistics collection
declare -gA _PROP_LABELS
declare -gA _PROP_CLASSIFICATIONS
declare -gA _PROP_COVERAGE
declare -gA _PROP_COVERAGE_REQUIRED

# Last counterexample
declare -g _PROP_LAST_COUNTEREXAMPLE=""
declare -g _PROP_LAST_SEED=""

# Test statistics
declare -g _PROP_TESTS_RUN=0
declare -g _PROP_TESTS_PASSED=0
declare -g _PROP_TESTS_FAILED=0
declare -g _PROP_SHRINK_STEPS=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# @pre: none
# @post: JSON-escaped string returned
# @idempotent: yes
_prop_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# @pre: none
# @post: random integer seeded appropriately
# @idempotent: no (random)
_prop_random() {
    local max="${1:-32767}"
    local val

    if [[ -n "$PROP_SEED" ]]; then
        # Use seed for reproducibility
        RANDOM="$PROP_SEED"
        PROP_SEED=$((PROP_SEED + 1))  # Advance seed
    fi

    val=$((RANDOM % (max + 1)))
    printf '%d' "$val"
}

# @pre: none
# @post: random float between 0 and 1
# @idempotent: no (random)
_prop_random_float() {
    local int_part frac_part
    int_part=$(_prop_random 1000000)
    printf '0.%06d' "$int_part"
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# @pre: iterations is positive integer
# @post: PROP_DEFAULT_ITERATIONS set
# @idempotent: yes
# @returns: 0 on success, 1 on invalid input
#
# Set the default number of test iterations
#
# Usage: prop_set_iterations 1000
prop_set_iterations() {
    local iterations="$1"

    if [[ ! "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
        printf '{"error":true,"type":"config","msg":"iterations must be positive integer"}\n' >&2
        return 1
    fi

    PROP_DEFAULT_ITERATIONS="$iterations"
}

# @pre: seed is non-negative integer
# @post: PROP_SEED set for reproducibility
# @idempotent: yes
# @returns: 0 on success, 1 on invalid input
#
# Set the random seed for reproducible tests
#
# Usage: prop_set_seed 12345
prop_set_seed() {
    local seed="$1"

    if [[ ! "$seed" =~ ^[0-9]+$ ]]; then
        printf '{"error":true,"type":"config","msg":"seed must be non-negative integer"}\n' >&2
        return 1
    fi

    PROP_SEED="$seed"
    _PROP_LAST_SEED="$seed"
}

# @pre: max_shrinks is positive integer
# @post: PROP_MAX_SHRINKS set
# @idempotent: yes
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum number of shrink attempts
#
# Usage: prop_set_max_shrinks 500
prop_set_max_shrinks() {
    local max_shrinks="$1"

    if [[ ! "$max_shrinks" =~ ^[0-9]+$ ]] || [[ "$max_shrinks" -lt 1 ]]; then
        printf '{"error":true,"type":"config","msg":"max_shrinks must be positive integer"}\n' >&2
        return 1
    fi

    PROP_MAX_SHRINKS="$max_shrinks"
}

# @pre: none
# @post: PROP_VERBOSE set to 1
# @idempotent: yes
# @returns: 0
#
# Enable verbose output during property testing
#
# Usage: prop_verbose
prop_verbose() {
    PROP_VERBOSE=1
}

# =============================================================================
# GENERATORS - INTEGER
# =============================================================================

# @pre: none
# @post: random integer output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random integer (size-bounded)
#
# Usage: val=$(gen_int)
gen_int() {
    local max="${1:-$_PROP_SIZE}"
    local min="${2:-$((-max))}"

    local range=$((max - min + 1))
    local rand_val
    rand_val=$(_prop_random 32767)
    local val=$(( rand_val % range + min ))
    printf '%d' "$val"
}

# @pre: min <= max
# @post: random integer in [min, max]
# @idempotent: no (random)
# @returns: 0
#
# Generate a random integer in a specific range
#
# Usage: port=$(gen_int_range 1 65535)
gen_int_range() {
    local min="$1"
    local max="$2"

    if [[ "$min" -gt "$max" ]]; then
        local tmp="$min"
        min="$max"
        max="$tmp"
    fi

    local range=$((max - min + 1))
    local rand_val
    rand_val=$(_prop_random 32767)
    local val=$(( rand_val % range + min ))
    printf '%d' "$val"
}

# =============================================================================
# GENERATORS - FLOAT
# =============================================================================

# @pre: none
# @post: random float output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random floating point number
#
# Usage: val=$(gen_float)
gen_float() {
    local max="${1:-$_PROP_SIZE}"
    local min="${2:-$((-max))}"

    local int_part frac_part
    int_part=$(gen_int_range "$min" "$max")
    frac_part=$(_prop_random 999999)

    printf '%d.%06d' "$int_part" "$frac_part"
}

# =============================================================================
# GENERATORS - BOOLEAN
# =============================================================================

# @pre: none
# @post: "true" or "false" output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random boolean
#
# Usage: flag=$(gen_bool)
gen_bool() {
    local val=$(_prop_random 1)
    if [[ "$val" -eq 0 ]]; then
        printf 'false'
    else
        printf 'true'
    fi
}

# =============================================================================
# GENERATORS - STRING
# =============================================================================

# Character sets for string generation
readonly _PROP_CHARS_ALPHA="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
readonly _PROP_CHARS_ALNUM="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
readonly _PROP_CHARS_PRINTABLE=" !\"#\$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\`abcdefghijklmnopqrstuvwxyz{|}~"

# @pre: none
# @post: random string output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random string (printable characters)
#
# Usage: s=$(gen_string)
# Usage: s=$(gen_string 20)  # max length 20
gen_string() {
    local max_len="${1:-$_PROP_SIZE}"
    local charset="${2:-$_PROP_CHARS_PRINTABLE}"

    local len=$(_prop_random "$max_len")
    local result=""
    local charset_len=${#charset}
    local i idx

    for ((i=0; i<len; i++)); do
        idx=$(_prop_random $((charset_len - 1)))
        result+="${charset:idx:1}"
    done

    printf '%s' "$result"
}

# @pre: none
# @post: random alphabetic string output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random alphabetic string (a-zA-Z only)
#
# Usage: name=$(gen_string_alpha)
gen_string_alpha() {
    local max_len="${1:-$_PROP_SIZE}"
    gen_string "$max_len" "$_PROP_CHARS_ALPHA"
}

# @pre: none
# @post: random alphanumeric string output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random alphanumeric string (a-zA-Z0-9)
#
# Usage: id=$(gen_string_alnum)
gen_string_alnum() {
    local max_len="${1:-$_PROP_SIZE}"
    gen_string "$max_len" "$_PROP_CHARS_ALNUM"
}

# @pre: pattern is valid extended regex character class
# @post: string matching pattern output
# @idempotent: no (random)
# @returns: 0
#
# Generate a string matching a simple pattern
# Supports: [a-z], [A-Z], [0-9], ., *, +
#
# Usage: s=$(gen_string_pattern "[a-z]+")
gen_string_pattern() {
    local pattern="$1"
    local max_len="${2:-$_PROP_SIZE}"

    local result=""
    local charset=""
    local len

    # Simple pattern parsing
    case "$pattern" in
        '[a-z]'*|'[a-z]+'|'[a-z]*')
            charset="abcdefghijklmnopqrstuvwxyz"
            ;;
        '[A-Z]'*|'[A-Z]+'|'[A-Z]*')
            charset="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            ;;
        '[0-9]'*|'[0-9]+'|'[0-9]*')
            charset="0123456789"
            ;;
        '[a-zA-Z]'*|'[a-zA-Z]+'|'[a-zA-Z]*')
            charset="$_PROP_CHARS_ALPHA"
            ;;
        '[a-zA-Z0-9]'*|'[a-zA-Z0-9]+'|'[a-zA-Z0-9]*')
            charset="$_PROP_CHARS_ALNUM"
            ;;
        *)
            charset="$_PROP_CHARS_PRINTABLE"
            ;;
    esac

    # Determine length based on quantifier
    if [[ "$pattern" == *'+' ]]; then
        local rand_len; rand_len=$(_prop_random $((max_len - 1))); len=$((1 + rand_len))
    elif [[ "$pattern" == *'*' ]]; then
        len=$(_prop_random "$max_len")
    else
        len=$(_prop_random "$max_len")
        [[ "$len" -lt 1 ]] && len=1
    fi

    local charset_len=${#charset}
    local i idx

    for ((i=0; i<len; i++)); do
        idx=$(_prop_random $((charset_len - 1)))
        result+="${charset:idx:1}"
    done

    printf '%s' "$result"
}

# =============================================================================
# GENERATORS - CHOICE
# =============================================================================

# @pre: at least one option provided
# @post: one of the options output
# @idempotent: no (random)
# @returns: 0 on success, 1 if no options
#
# Choose uniformly from a list of values
#
# Usage: color=$(gen_choice "red" "green" "blue")
gen_choice() {
    if [[ $# -eq 0 ]]; then
        printf '{"error":true,"type":"generator","msg":"gen_choice requires at least one option"}\n' >&2
        return 1
    fi

    local idx=$(_prop_random $(($# - 1)))
    local i=0

    for opt in "$@"; do
        if [[ "$i" -eq "$idx" ]]; then
            printf '%s' "$opt"
            return 0
        fi
        ((i++))
    done
}

# @pre: weights and values same length
# @post: weighted random choice output
# @idempotent: no (random)
# @returns: 0
#
# Choose from a list with weighted probabilities
# Format: weight1 val1 weight2 val2 ...
#
# Usage: result=$(gen_frequency 70 "common" 20 "rare" 10 "legendary")
gen_frequency() {
    local -a weights=()
    local -a values=()
    local total=0
    local i=0

    # Parse weight-value pairs
    while [[ $# -ge 2 ]]; do
        weights+=("$1")
        values+=("$2")
        total=$((total + $1))
        shift 2
    done

    if [[ ${#weights[@]} -eq 0 ]]; then
        printf '{"error":true,"type":"generator","msg":"gen_frequency requires weight-value pairs"}\n' >&2
        return 1
    fi

    # Pick random point in total range
    local pick=$(_prop_random $((total - 1)))
    local cumulative=0

    for ((i=0; i<${#weights[@]}; i++)); do
        cumulative=$((cumulative + weights[i]))
        if [[ "$pick" -lt "$cumulative" ]]; then
            printf '%s' "${values[i]}"
            return 0
        fi
    done

    # Fallback to last value
    printf '%s' "${values[-1]}"
}

# @pre: at least one generator function provided
# @post: result from one randomly selected generator
# @idempotent: no (random)
# @returns: 0
#
# Choose uniformly from a list of generators and run it
#
# Usage: val=$(gen_one_of gen_int gen_string gen_bool)
gen_one_of() {
    if [[ $# -eq 0 ]]; then
        printf '{"error":true,"type":"generator","msg":"gen_one_of requires at least one generator"}\n' >&2
        return 1
    fi

    local idx=$(_prop_random $(($# - 1)))
    local i=0
    local gen

    for gen in "$@"; do
        if [[ "$i" -eq "$idx" ]]; then
            "$gen"
            return $?
        fi
        ((i++))
    done
}

# =============================================================================
# GENERATORS - ARRAY
# =============================================================================

# @pre: none
# @post: bash array declaration output
# @idempotent: no (random)
# @returns: 0
#
# Generate a random array of strings
#
# Usage: eval "arr=($(gen_array))"
gen_array() {
    local max_len="${1:-$_PROP_SIZE}"

    local len=$(_prop_random "$max_len")
    local result=""
    local i elem

    for ((i=0; i<len; i++)); do
        elem=$(gen_string)
        # Quote for safe eval
        elem="${elem//\'/\'\\\'\'}"
        result+="'$elem' "
    done

    printf '%s' "$result"
}

# @pre: generator_func is valid function name
# @post: array elements generated by specified generator
# @idempotent: no (random)
# @returns: 0
#
# Generate an array using a specific generator
#
# Usage: eval "nums=($(gen_array_of gen_int 5))"
gen_array_of() {
    local generator="$1"
    local max_len="${2:-$_PROP_SIZE}"

    if ! declare -F "$generator" &>/dev/null; then
        printf '{"error":true,"type":"generator","msg":"gen_array_of: unknown generator %s"}\n' "$generator" >&2
        return 1
    fi

    local len=$(_prop_random "$max_len")
    local result=""
    local i elem

    for ((i=0; i<len; i++)); do
        elem=$("$generator")
        # Quote for safe eval
        elem="${elem//\'/\'\\\'\'}"
        result+="'$elem' "
    done

    printf '%s' "$result"
}

# =============================================================================
# GENERATORS - OPTIONAL
# =============================================================================

# @pre: generator_func is valid function name
# @post: generated value or empty string
# @idempotent: no (random)
# @returns: 0
#
# Maybe generate a value (50% chance of empty)
#
# Usage: maybe_name=$(gen_maybe gen_string)
gen_maybe() {
    local generator="$1"
    shift

    local coin=$(_prop_random 1)

    if [[ "$coin" -eq 0 ]]; then
        printf ''
    else
        "$generator" "$@"
    fi
}

# =============================================================================
# GENERATORS - SIZE CONTROL
# =============================================================================

# @pre: size is non-negative integer
# @post: generator run with specified size
# @idempotent: no (random)
# @returns: generator's return code
#
# Run a generator with specific size
#
# Usage: small_string=$(gen_sized 3 gen_string)
gen_sized() {
    local size="$1"
    local generator="$2"
    shift 2

    local old_size="$_PROP_SIZE"
    _PROP_SIZE="$size"

    local result
    result=$("$generator" "$@")
    local rc=$?

    _PROP_SIZE="$old_size"
    printf '%s' "$result"
    return $rc
}

# =============================================================================
# SHRINKING - INTEGER
# =============================================================================

# @pre: value is integer
# @post: array of smaller integers toward 0
# @idempotent: yes
# @returns: 0
#
# Generate shrink candidates for an integer
#
# Usage: candidates=$(shrink_int 100)
shrink_int() {
    local value="$1"
    local candidates=""

    # Always include 0 if not already
    if [[ "$value" -ne 0 ]]; then
        candidates+="0 "
    fi

    # Binary search toward 0
    local current="$value"
    if [[ "$current" -gt 0 ]]; then
        while [[ "$current" -gt 1 ]]; do
            current=$((current / 2))
            candidates+="$current "
        done
    elif [[ "$current" -lt 0 ]]; then
        while [[ "$current" -lt -1 ]]; do
            current=$((current / 2))
            candidates+="$current "
        done
        # Try positive equivalent
        candidates+="$((-value)) "
    fi

    # Subtract 1
    if [[ "$value" -gt 0 ]]; then
        candidates+="$((value - 1)) "
    elif [[ "$value" -lt 0 ]]; then
        candidates+="$((value + 1)) "
    fi

    printf '%s' "$candidates"
}

# =============================================================================
# SHRINKING - STRING
# =============================================================================

# @pre: value is string
# @post: array of smaller strings
# @idempotent: yes
# @returns: 0
#
# Generate shrink candidates for a string
#
# Usage: candidates=$(shrink_string "hello")
shrink_string() {
    local value="$1"
    local candidates=""
    local len=${#value}

    # Empty string is minimal
    if [[ "$len" -eq 0 ]]; then
        printf ''
        return 0
    fi

    # Always try empty
    candidates+="'' "

    # Remove each character
    local i
    for ((i=0; i<len; i++)); do
        local shorter="${value:0:i}${value:i+1}"
        shorter="${shorter//\'/\'\\\'\'}"
        candidates+="'$shorter' "
    done

    # Remove first half, second half
    if [[ "$len" -gt 1 ]]; then
        local half=$((len / 2))
        local first_half="${value:0:half}"
        local second_half="${value:half}"
        first_half="${first_half//\'/\'\\\'\'}"
        second_half="${second_half//\'/\'\\\'\'}"
        candidates+="'$first_half' '$second_half' "
    fi

    # Replace characters with 'a' (simplify toward simple characters)
    if [[ "$value" != *[^a]* ]]; then
        :  # Already all 'a's
    else
        local simplified=""
        for ((i=0; i<len; i++)); do
            local char="${value:i:1}"
            if [[ "$char" != "a" ]]; then
                simplified+="a"
            else
                simplified+="$char"
            fi
        done
        if [[ "$simplified" != "$value" ]]; then
            simplified="${simplified//\'/\'\\\'\'}"
            candidates+="'$simplified' "
        fi
    fi

    printf '%s' "$candidates"
}

# =============================================================================
# SHRINKING - ARRAY
# =============================================================================

# @pre: array elements as arguments
# @post: list of shrunk array candidates
# @idempotent: yes
# @returns: 0
#
# Generate shrink candidates for an array
#
# Usage: candidates=$(shrink_array "a" "b" "c")
shrink_array() {
    local -a arr=("$@")
    local len=${#arr[@]}
    local candidates=""

    # Empty array is minimal
    if [[ "$len" -eq 0 ]]; then
        printf ''
        return 0
    fi

    # Always try empty array
    candidates+="() "

    # Remove each element
    local i j
    for ((i=0; i<len; i++)); do
        local shrunk="("
        for ((j=0; j<len; j++)); do
            if [[ "$j" -ne "$i" ]]; then
                local elem="${arr[j]}"
                elem="${elem//\'/\'\\\'\'}"
                shrunk+="'$elem' "
            fi
        done
        shrunk+=")"
        candidates+="$shrunk "
    done

    # Remove first half
    if [[ "$len" -gt 1 ]]; then
        local half=$((len / 2))
        local first_half="("
        for ((i=0; i<half; i++)); do
            local elem="${arr[i]}"
            elem="${elem//\'/\'\\\'\'}"
            first_half+="'$elem' "
        done
        first_half+=")"
        candidates+="$first_half "

        # Second half
        local second_half="("
        for ((i=half; i<len; i++)); do
            local elem="${arr[i]}"
            elem="${elem//\'/\'\\\'\'}"
            second_half+="'$elem' "
        done
        second_half+=")"
        candidates+="$second_half "
    fi

    printf '%s' "$candidates"
}

# =============================================================================
# SHRINKING - FIND MINIMAL
# =============================================================================

# @pre: property_func fails on initial_value
# @post: minimal failing value found
# @idempotent: yes
# @returns: 0 on success, 1 if property always passes
#
# Find the minimal failing case through shrinking
#
# Usage: minimal=$(shrink_find_minimal "property_func" "failing_value" "shrink_int")
shrink_find_minimal() {
    local property_func="$1"
    local initial_value="$2"
    local shrink_func="${3:-shrink_int}"

    local current="$initial_value"
    local shrink_count=0

    while [[ "$shrink_count" -lt "$PROP_MAX_SHRINKS" ]]; do
        # Get candidates
        local candidates
        candidates=$("$shrink_func" "$current")

        if [[ -z "$candidates" ]]; then
            break
        fi

        # Try each candidate
        local found_smaller=false
        local candidate

        for candidate in $candidates; do
            # Handle quoted values
            candidate="${candidate#\'}"
            candidate="${candidate%\'}"

            # Test if this smaller value still fails
            if ! "$property_func" "$candidate" >/dev/null 2>&1; then
                current="$candidate"
                found_smaller=true
                ((shrink_count++))
                _PROP_SHRINK_STEPS=$shrink_count

                if [[ "$PROP_VERBOSE" -eq 1 ]]; then
                    printf '[shrink] step %d: %s\n' "$shrink_count" "$current" >&2
                fi
                break
            fi
        done

        if [[ "$found_smaller" == "false" ]]; then
            break
        fi
    done

    printf '%s' "$current"
}

# @pre: property_func fails on initial value
# @post: minimal integer via binary search
# @idempotent: yes
# @returns: 0
#
# Binary search shrinking for integers
#
# Usage: minimal=$(shrink_binary_search "property_func" 1000)
shrink_binary_search() {
    local property_func="$1"
    local initial_value="$2"

    local lo=0
    local hi="$initial_value"
    local shrink_count=0

    # Determine direction
    if [[ "$initial_value" -lt 0 ]]; then
        lo="$initial_value"
        hi=0
    fi

    while [[ $((hi - lo)) -gt 1 && "$shrink_count" -lt "$PROP_MAX_SHRINKS" ]]; do
        local mid=$(( (lo + hi) / 2 ))

        if ! "$property_func" "$mid" >/dev/null 2>&1; then
            # Mid still fails, search lower
            hi="$mid"
        else
            # Mid passes, search higher
            lo="$mid"
        fi

        ((shrink_count++))
        _PROP_SHRINK_STEPS=$shrink_count
    done

    printf '%d' "$hi"
}

# =============================================================================
# PROPERTY DEFINITION
# =============================================================================

# @pre: property_func is valid function, generator is valid function
# @post: property test result output
# @idempotent: no (random)
# @returns: 0 on success, 1 on failure
#
# Test a property with generated values (universal quantification)
#
# Usage: prop_forall gen_int "my_property"
prop_forall() {
    local generator="$1"
    local property_func="$2"
    local iterations="${3:-$PROP_DEFAULT_ITERATIONS}"

    local i value

    for ((i=0; i<iterations; i++)); do
        # Grow size with iterations
        _PROP_SIZE=$((10 + i / 10))

        # Generate value
        value=$("$generator")

        if [[ "$PROP_VERBOSE" -eq 1 ]]; then
            printf '[test %d] value=%s\n' "$i" "$value" >&2
        fi

        # Test property
        if ! "$property_func" "$value"; then
            _PROP_LAST_COUNTEREXAMPLE="$value"
            _PROP_TESTS_FAILED=$((_PROP_TESTS_FAILED + 1))
            return 1
        fi

        _PROP_TESTS_RUN=$((_PROP_TESTS_RUN + 1))
    done

    _PROP_TESTS_PASSED=$((_PROP_TESTS_PASSED + iterations))
    return 0
}

# @pre: property_func is valid function
# @post: property tested with N iterations
# @idempotent: no (random)
# @returns: 0 on all pass, 1 on any failure
#
# Run a property test with automatic generation and shrinking
#
# Usage: prop_check "gen_int" "is_positive" 100
prop_check() {
    local generator="$1"
    local property_func="$2"
    local iterations="${3:-$PROP_DEFAULT_ITERATIONS}"

    # Reset statistics
    _PROP_LABELS=()
    _PROP_CLASSIFICATIONS=()
    _PROP_COVERAGE=()
    _PROP_LAST_COUNTEREXAMPLE=""
    _PROP_SHRINK_STEPS=0

    local start_seed="$PROP_SEED"
    [[ -z "$start_seed" ]] && start_seed="$RANDOM"
    _PROP_LAST_SEED="$start_seed"

    local i value

    for ((i=0; i<iterations; i++)); do
        _PROP_SIZE=$((10 + i / 10))

        value=$("$generator")

        if [[ "$PROP_VERBOSE" -eq 1 ]]; then
            printf '[iteration %d/%d] testing: %s\n' "$((i+1))" "$iterations" "$value" >&2
        fi

        if ! "$property_func" "$value" >/dev/null 2>&1; then
            # Property failed - try to shrink
            local minimal

            # Detect value type and choose shrink function
            local shrink_func="shrink_int"
            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                shrink_func="shrink_int"
            else
                shrink_func="shrink_string"
            fi

            minimal=$(shrink_find_minimal "$property_func" "$value" "$shrink_func")
            _PROP_LAST_COUNTEREXAMPLE="$minimal"

            # Output failure in USOP format
            printf '{"ok":false,"type":"property_test","property":"%s","failed_after":%d,"counterexample":"%s","original":"%s","shrink_steps":%d,"seed":%d}\n' \
                "$(_prop_escape_json "$property_func")" \
                "$((i+1))" \
                "$(_prop_escape_json "$minimal")" \
                "$(_prop_escape_json "$value")" \
                "$_PROP_SHRINK_STEPS" \
                "$_PROP_LAST_SEED"

            return 1
        fi
    done

    # All passed - output success in USOP format
    printf '{"ok":true,"type":"property_test","property":"%s","passed":%d,"seed":%d}\n' \
        "$(_prop_escape_json "$property_func")" \
        "$iterations" \
        "$_PROP_LAST_SEED"

    return 0
}

# @pre: value is valid input
# @post: property tested on specific value
# @idempotent: yes
# @returns: 0 if property holds, 1 if not
#
# Verify a property holds for a specific value
#
# Usage: prop_verify "is_positive" 42
prop_verify() {
    local property_func="$1"
    local value="$2"

    if "$property_func" "$value" >/dev/null 2>&1; then
        printf '{"ok":true,"type":"verify","property":"%s","value":"%s"}\n' \
            "$(_prop_escape_json "$property_func")" \
            "$(_prop_escape_json "$value")"
        return 0
    else
        printf '{"ok":false,"type":"verify","property":"%s","value":"%s"}\n' \
            "$(_prop_escape_json "$property_func")" \
            "$(_prop_escape_json "$value")"
        return 1
    fi
}

# =============================================================================
# PROPERTY COMBINATORS
# =============================================================================

# @pre: precondition and property are valid functions
# @post: property only checked when precondition holds
# @idempotent: yes
# @returns: 0 if implication holds (precondition false or property true)
#
# Test an implication: precondition => property
#
# Usage: prop_implies "is_positive" "is_even" "$value"
prop_implies() {
    local precondition="$1"
    local property="$2"
    local value="$3"

    # If precondition doesn't hold, implication is trivially true
    if ! "$precondition" "$value" >/dev/null 2>&1; then
        return 0
    fi

    # Precondition holds, check property
    "$property" "$value"
}

# @pre: property functions are valid
# @post: returns 0 iff both properties hold
# @idempotent: yes
# @returns: 0 if both hold, 1 otherwise
#
# Combine two properties with AND
#
# Usage: prop_and "is_positive" "is_even" "$value"
prop_and() {
    local prop1="$1"
    local prop2="$2"
    local value="$3"

    "$prop1" "$value" >/dev/null 2>&1 && "$prop2" "$value" >/dev/null 2>&1
}

# @pre: property functions are valid
# @post: returns 0 if either property holds
# @idempotent: yes
# @returns: 0 if either holds, 1 if neither
#
# Combine two properties with OR
#
# Usage: prop_or "is_positive" "is_zero" "$value"
prop_or() {
    local prop1="$1"
    local prop2="$2"
    local value="$3"

    "$prop1" "$value" >/dev/null 2>&1 || "$prop2" "$value" >/dev/null 2>&1
}

# =============================================================================
# STATISTICS COLLECTION
# =============================================================================

# @pre: label is string
# @post: label counted in statistics
# @idempotent: no (increments counter)
# @returns: 0
#
# Label a test case for statistics
#
# Usage: prop_label "positive" (inside property function)
prop_label() {
    local label="$1"

    if [[ -z "${_PROP_LABELS[$label]:-}" ]]; then
        _PROP_LABELS["$label"]=1
    else
        _PROP_LABELS["$label"]=$((_PROP_LABELS["$label"] + 1))
    fi
}

# @pre: condition is true/false, name is string
# @post: classification counted if condition true
# @idempotent: no (increments counter)
# @returns: 0
#
# Classify test cases based on conditions
#
# Usage: prop_classify "$(( value > 0 ))" "positive"
prop_classify() {
    local condition="$1"
    local name="$2"

    if [[ "$condition" == "1" ]] || [[ "$condition" == "true" ]]; then
        if [[ -z "${_PROP_CLASSIFICATIONS[$name]:-}" ]]; then
            _PROP_CLASSIFICATIONS["$name"]=1
        else
            _PROP_CLASSIFICATIONS["$name"]=$((_PROP_CLASSIFICATIONS["$name"] + 1))
        fi
    fi
}

# @pre: value is the current test value
# @post: value distribution collected
# @idempotent: no (increments counter)
# @returns: 0
#
# Collect value distribution statistics
#
# Usage: prop_collect "$value"
prop_collect() {
    local value="$1"

    if [[ -z "${_PROP_LABELS[$value]:-}" ]]; then
        _PROP_LABELS["$value"]=1
    else
        _PROP_LABELS["$value"]=$((_PROP_LABELS["$value"] + 1))
    fi
}

# @pre: percent is 0-100, condition and name are valid
# @post: coverage requirement registered
# @idempotent: yes
# @returns: 0
#
# Require a minimum percentage of test cases to match a condition
#
# Usage: prop_cover 20 "$(( value > 100 ))" "large_values"
prop_cover() {
    local percent="$1"
    local condition="$2"
    local name="$3"

    _PROP_COVERAGE_REQUIRED["$name"]="$percent"

    if [[ "$condition" == "1" ]] || [[ "$condition" == "true" ]]; then
        if [[ -z "${_PROP_COVERAGE[$name]:-}" ]]; then
            _PROP_COVERAGE["$name"]=1
        else
            _PROP_COVERAGE["$name"]=$((_PROP_COVERAGE["$name"] + 1))
        fi
    fi
}

# @pre: none
# @post: JSON statistics output
# @idempotent: yes
# @returns: 0
#
# Get test statistics as JSON
#
# Usage: stats=$(prop_stats)
prop_stats() {
    local json="{"
    local first=true

    # Labels
    json+="\"labels\":{"
    local label_first=true
    for label in "${!_PROP_LABELS[@]}"; do
        $label_first || json+=","
        label_first=false
        json+="\"$(_prop_escape_json "$label")\":${_PROP_LABELS[$label]}"
    done
    json+="}"

    # Classifications
    json+=",\"classifications\":{"
    local class_first=true
    for class in "${!_PROP_CLASSIFICATIONS[@]}"; do
        $class_first || json+=","
        class_first=false
        json+="\"$(_prop_escape_json "$class")\":${_PROP_CLASSIFICATIONS[$class]}"
    done
    json+="}"

    # Coverage
    json+=",\"coverage\":{"
    local cov_first=true
    for cov in "${!_PROP_COVERAGE[@]}"; do
        $cov_first || json+=","
        cov_first=false
        local count="${_PROP_COVERAGE[$cov]}"
        local required="${_PROP_COVERAGE_REQUIRED[$cov]:-0}"
        json+="\"$(_prop_escape_json "$cov)")\":{\"count\":$count,\"required\":$required}"
    done
    json+="}"

    # Overall stats
    json+=",\"tests_run\":$_PROP_TESTS_RUN"
    json+=",\"tests_passed\":$_PROP_TESTS_PASSED"
    json+=",\"tests_failed\":$_PROP_TESTS_FAILED"
    json+=",\"shrink_steps\":$_PROP_SHRINK_STEPS"

    json+="}"
    printf '%s' "$json"
}

# =============================================================================
# SAMPLING AND REPLAY
# =============================================================================

# @pre: generator is valid function
# @post: N sample values output
# @idempotent: no (random)
# @returns: 0
#
# Sample values from a generator (for debugging)
#
# Usage: prop_sample gen_int 10
prop_sample() {
    local generator="$1"
    local count="${2:-10}"

    local i
    printf '["'
    for ((i=0; i<count; i++)); do
        [[ "$i" -gt 0 ]] && printf '","'
        local val
        val=$("$generator")
        printf '%s' "$(_prop_escape_json "$val")"
    done
    printf '"]\n'
}

# @pre: _PROP_LAST_COUNTEREXAMPLE is set
# @post: last counterexample returned
# @idempotent: yes
# @returns: 0 if exists, 1 if not
#
# Get the last counterexample that caused a test failure
#
# Usage: example=$(prop_counterexample)
prop_counterexample() {
    if [[ -z "$_PROP_LAST_COUNTEREXAMPLE" ]]; then
        printf '{"error":true,"msg":"no counterexample recorded"}\n' >&2
        return 1
    fi

    printf '{"counterexample":"%s","seed":%d,"shrink_steps":%d}\n' \
        "$(_prop_escape_json "$_PROP_LAST_COUNTEREXAMPLE")" \
        "$_PROP_LAST_SEED" \
        "$_PROP_SHRINK_STEPS"
}

# @pre: seed is valid seed value
# @post: test replayed with specific seed
# @idempotent: yes (same seed = same sequence)
# @returns: 0 on success, 1 on failure
#
# Replay a property test with a specific seed
#
# Usage: prop_replay 12345 gen_int "my_property"
prop_replay() {
    local seed="$1"
    local generator="$2"
    local property_func="$3"
    local iterations="${4:-$PROP_DEFAULT_ITERATIONS}"

    prop_set_seed "$seed"
    prop_check "$generator" "$property_func" "$iterations"
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

# @pre: none
# @post: full test results as JSON
# @idempotent: yes
# @returns: 0
#
# Output complete test results as JSON
#
# Usage: results=$(prop_to_json)
prop_to_json() {
    local json="{"

    json+="\"tests_run\":$_PROP_TESTS_RUN"
    json+=",\"tests_passed\":$_PROP_TESTS_PASSED"
    json+=",\"tests_failed\":$_PROP_TESTS_FAILED"
    json+=",\"shrink_steps\":$_PROP_SHRINK_STEPS"

    if [[ -n "$_PROP_LAST_COUNTEREXAMPLE" ]]; then
        json+=",\"last_counterexample\":\"$(_prop_escape_json "$_PROP_LAST_COUNTEREXAMPLE")\""
    fi

    if [[ -n "$_PROP_LAST_SEED" ]]; then
        json+=",\"last_seed\":$_PROP_LAST_SEED"
    fi

    # Labels
    json+=",\"labels\":{"
    local label_first=true
    for label in "${!_PROP_LABELS[@]}"; do
        $label_first || json+=","
        label_first=false
        json+="\"$(_prop_escape_json "$label")\":${_PROP_LABELS[$label]}"
    done
    json+="}"

    # Classifications
    json+=",\"classifications\":{"
    local class_first=true
    for class in "${!_PROP_CLASSIFICATIONS[@]}"; do
        $class_first || json+=","
        class_first=false
        json+="\"$(_prop_escape_json "$class")\":${_PROP_CLASSIFICATIONS[$class]}"
    done
    json+="}"

    json+="}"
    printf '%s\n' "$json"
}

# =============================================================================
# RESET STATE
# =============================================================================

# @pre: none
# @post: all statistics reset
# @idempotent: yes
# @returns: 0
#
# Reset all test state and statistics
#
# Usage: _prop_reset
_prop_reset() {
    _PROP_LABELS=()
    _PROP_CLASSIFICATIONS=()
    _PROP_COVERAGE=()
    _PROP_COVERAGE_REQUIRED=()
    _PROP_LAST_COUNTEREXAMPLE=""
    _PROP_LAST_SEED=""
    _PROP_TESTS_RUN=0
    _PROP_TESTS_PASSED=0
    _PROP_TESTS_FAILED=0
    _PROP_SHRINK_STEPS=0
    _PROP_SIZE=10
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_PROPERTY_TEST_EXPORTS=(
    # Configuration
    prop_set_iterations
    prop_set_seed
    prop_set_max_shrinks
    prop_verbose
    # Generators - Integer
    gen_int
    gen_int_range
    # Generators - Float
    gen_float
    # Generators - Boolean
    gen_bool
    # Generators - String
    gen_string
    gen_string_alpha
    gen_string_alnum
    gen_string_pattern
    # Generators - Choice
    gen_choice
    gen_frequency
    gen_one_of
    # Generators - Array
    gen_array
    gen_array_of
    # Generators - Optional
    gen_maybe
    # Generators - Size
    gen_sized
    # Shrinking
    shrink_int
    shrink_string
    shrink_array
    shrink_find_minimal
    shrink_binary_search
    # Property Definition
    prop_forall
    prop_check
    prop_verify
    # Property Combinators
    prop_implies
    prop_and
    prop_or
    # Statistics
    prop_collect
    prop_classify
    prop_label
    prop_cover
    prop_stats
    # Sampling and Replay
    prop_sample
    prop_counterexample
    prop_replay
    # JSON Output
    prop_to_json
)

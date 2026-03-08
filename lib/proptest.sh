#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/proptest.sh - Property-Based Testing Framework
# =============================================================================
# Description: Generates random inputs to find edge cases in functions.
#              Inspired by QuickCheck, Hypothesis, and fast-check.
# Version: 1.0.0
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROPTEST_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_PROPTEST_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Number of test iterations (default: 100)
declare -g PROPTEST_ITERATIONS="${PROPTEST_ITERATIONS:-100}"

# Random seed for reproducibility (default: current time in nanoseconds)
declare -g PROPTEST_SEED="${PROPTEST_SEED:-}"

# Verbose mode: show each test case
declare -g PROPTEST_VERBOSE="${PROPTEST_VERBOSE:-0}"

# Maximum shrink attempts
declare -g PROPTEST_MAX_SHRINKS="${PROPTEST_MAX_SHRINKS:-50}"

# Output format: text or json
declare -g PROPTEST_OUTPUT="${PROPTEST_OUTPUT:-text}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Global state for current test run
declare -g _PROPTEST_CURRENT_TEST=""
declare -g _PROPTEST_PASS_COUNT=0
declare -g _PROPTEST_FAIL_COUNT=0
declare -g _PROPTEST_SHRINK_COUNT=0
declare -ga _PROPTEST_FAILURES=()
declare -g _PROPTEST_LAST_SEED=""
declare -g _PROPTEST_ITERATION=0

# Random state (Linear Congruential Generator for reproducibility)
declare -g _PROPTEST_RAND_STATE=0

# =============================================================================
# RANDOM NUMBER GENERATION (Reproducible)
# =============================================================================

# Initialize random state from seed
# Usage: _proptest_srand [seed]
_proptest_srand() {
    local seed="${1:-}"

    if [[ -z "$seed" ]]; then
        # Use nanoseconds if available, otherwise microseconds, otherwise seconds
        if [[ -r /proc/sys/kernel/random/uuid ]]; then
            seed=$(od -An -tu4 -N4 /dev/urandom 2>/dev/null | tr -d ' ')
        elif command -v date &>/dev/null && date +%N &>/dev/null 2>&1; then
            seed=$(date +%s%N 2>/dev/null || date +%s)
        else
            seed=$SECONDS
        fi
    fi

    # Ensure seed is numeric
    seed="${seed//[^0-9]/}"
    [[ -z "$seed" ]] && seed=$RANDOM

    _PROPTEST_RAND_STATE=$((seed % 2147483647))
    [[ $_PROPTEST_RAND_STATE -eq 0 ]] && _PROPTEST_RAND_STATE=1
    _PROPTEST_LAST_SEED="$seed"
}

# Generate next random number (0 to 2^31-1)
# Usage: _proptest_rand
_proptest_rand() {
    # LCG parameters (same as glibc)
    local a=1103515245
    local c=12345
    local m=2147483648  # 2^31

    _PROPTEST_RAND_STATE=$(( (a * _PROPTEST_RAND_STATE + c) % m ))
    printf '%d' "$_PROPTEST_RAND_STATE"
}

# Generate random number in range [min, max]
# Usage: _proptest_rand_range min max
_proptest_rand_range() {
    local min="$1"
    local max="$2"
    local range=$((max - min + 1))
    local rand

    rand=$(_proptest_rand)
    printf '%d' $((min + (rand % range)))
}

# =============================================================================
# CORE GENERATORS
# =============================================================================

# Generate random integer
# Usage: gen_int [min] [max]
# Default: -1000000 to 1000000
gen_int() {
    local min="${1:--1000000}"
    local max="${2:-1000000}"

    _proptest_rand_range "$min" "$max"
}

# Generate random positive integer
# Usage: gen_positive_int [max]
gen_positive_int() {
    local max="${1:-1000000}"

    _proptest_rand_range 1 "$max"
}

# Generate random natural number (including 0)
# Usage: gen_nat [max]
gen_nat() {
    local max="${1:-1000000}"

    _proptest_rand_range 0 "$max"
}

# Generate random string of alphanumeric characters
# Usage: gen_string [min_len] [max_len] [charset]
# Default charset: a-zA-Z0-9
gen_string() {
    local min_len="${1:-0}"
    local max_len="${2:-100}"
    local charset="${3:-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789}"

    local len
    len=$(_proptest_rand_range "$min_len" "$max_len")

    local result=""
    local charset_len=${#charset}

    for ((i=0; i<len; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 $((charset_len - 1)))
        result+="${charset:idx:1}"
    done

    printf '%s' "$result"
}

# Generate random ASCII string (printable characters)
# Usage: gen_ascii [min_len] [max_len]
gen_ascii() {
    local min_len="${1:-0}"
    local max_len="${2:-100}"

    # Printable ASCII: space (32) through tilde (126)
    local charset=' !"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'
    gen_string "$min_len" "$max_len" "$charset"
}

# Generate random alphabetic string
# Usage: gen_alpha [min_len] [max_len]
gen_alpha() {
    local min_len="${1:-0}"
    local max_len="${2:-100}"
    local charset="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

    gen_string "$min_len" "$max_len" "$charset"
}

# Generate random lowercase string
# Usage: gen_lower [min_len] [max_len]
gen_lower() {
    local min_len="${1:-0}"
    local max_len="${2:-100}"
    local charset="abcdefghijklmnopqrstuvwxyz"

    gen_string "$min_len" "$max_len" "$charset"
}

# Generate random uppercase string
# Usage: gen_upper [min_len] [max_len]
gen_upper() {
    local min_len="${1:-0}"
    local max_len="${2:-100}"
    local charset="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    gen_string "$min_len" "$max_len" "$charset"
}

# Generate random choice from list
# Usage: gen_choice item1 item2 item3 ...
gen_choice() {
    [[ $# -eq 0 ]] && return 1

    local idx
    idx=$(_proptest_rand_range 0 $(($# - 1)))

    # Get the item at index
    shift "$idx"
    printf '%s' "$1"
}

# Generate random boolean
# Usage: gen_bool
gen_bool() {
    local val
    val=$(_proptest_rand_range 0 1)

    if [[ $val -eq 1 ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

# Generate array of values
# Usage: gen_array gen_cmd [min_size] [max_size]
# Example: gen_array "gen_int 1 100" 1 10
gen_array() {
    local gen_cmd="$1"
    local min_size="${2:-0}"
    local max_size="${3:-20}"

    local size
    size=$(_proptest_rand_range "$min_size" "$max_size")

    local result=()
    for ((i=0; i<size; i++)); do
        # Execute generator command
        result+=("$(eval "$gen_cmd")")
    done

    # Print as space-separated values (bash array compatible)
    printf '%s\n' "${result[@]}"
}

# Generate random email address
# Usage: gen_email
gen_email() {
    local user
    local domain
    local tld

    user=$(gen_lower 3 12)
    domain=$(gen_lower 3 10)
    tld=$(gen_choice "com" "org" "net" "io" "dev" "app" "co")

    printf '%s@%s.%s' "$user" "$domain" "$tld"
}

# Generate random UUID v4
# Usage: gen_uuid
# shellcheck disable=SC2178,SC2179,SC2128  # result is a string, not array
gen_uuid() {
    local hex="0123456789abcdef"
    local result=""

    # Format: 8-4-4-4-12
    # Version 4: 4th group starts with 4, 5th group starts with 8/9/a/b

    # First 8 hex chars
    for ((i=0; i<8; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 15)
        result+="${hex:idx:1}"
    done
    result+="-"

    # Next 4 hex chars
    for ((i=0; i<4; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 15)
        result+="${hex:idx:1}"
    done
    result+="-"

    # Version 4: starts with 4
    result+="4"
    for ((i=0; i<3; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 15)
        result+="${hex:idx:1}"
    done
    result+="-"

    # Variant: starts with 8, 9, a, or b
    local variant_hex="89ab"
    local vidx
    vidx=$(_proptest_rand_range 0 3)
    result+="${variant_hex:vidx:1}"
    for ((i=0; i<3; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 15)
        result+="${hex:idx:1}"
    done
    result+="-"

    # Last 12 hex chars
    for ((i=0; i<12; i++)); do
        local idx
        idx=$(_proptest_rand_range 0 15)
        result+="${hex:idx:1}"
    done

    printf '%s' "$result"
}

# Generate random JSON object with simple key-value pairs
# Usage: gen_json_object [max_keys]
# shellcheck disable=SC2178,SC2179,SC2128  # result is a string, not array
gen_json_object() {
    local max_keys="${1:-5}"
    local num_keys

    num_keys=$(_proptest_rand_range 0 "$max_keys")

    local result="{"
    local first=true

    for ((i=0; i<num_keys; i++)); do
        $first || result+=","
        first=false

        local key
        local val_type
        local value

        key=$(gen_lower 3 10)
        val_type=$(_proptest_rand_range 0 3)

        case $val_type in
            0)  # String
                value="\"$(gen_string 1 20)\""
                ;;
            1)  # Number
                value=$(gen_int -1000 1000)
                ;;
            2)  # Boolean
                value=$(gen_bool)
                ;;
            3)  # Null
                value="null"
                ;;
        esac

        result+="\"$key\":$value"
    done

    result+="}"
    printf '%s' "$result"
}

# Generate random URL
# Usage: gen_url
gen_url() {
    local scheme
    local domain
    local tld
    local path_len

    scheme=$(gen_choice "http" "https")
    domain=$(gen_lower 3 12)
    tld=$(gen_choice "com" "org" "net" "io")
    path_len=$(_proptest_rand_range 0 3)

    local url="$scheme://$domain.$tld"

    for ((i=0; i<path_len; i++)); do
        local segment
        segment=$(gen_lower 2 8)
        url+="/$segment"
    done

    printf '%s' "$url"
}

# Generate random date in ISO format (YYYY-MM-DD)
# Usage: gen_date [min_year] [max_year]
gen_date() {
    local min_year="${1:-1970}"
    local max_year="${2:-2030}"

    local year
    local month
    local day
    local max_day

    year=$(_proptest_rand_range "$min_year" "$max_year")
    month=$(_proptest_rand_range 1 12)

    # Calculate max days in month
    case $month in
        1|3|5|7|8|10|12) max_day=31 ;;
        4|6|9|11) max_day=30 ;;
        2)
            if (( (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 )); then
                max_day=29
            else
                max_day=28
            fi
            ;;
    esac

    day=$(_proptest_rand_range 1 "$max_day")

    printf '%04d-%02d-%02d' "$year" "$month" "$day"
}

# Generate random IPv4 address
# Usage: gen_ipv4
gen_ipv4() {
    local o1 o2 o3 o4

    o1=$(_proptest_rand_range 0 255)
    o2=$(_proptest_rand_range 0 255)
    o3=$(_proptest_rand_range 0 255)
    o4=$(_proptest_rand_range 0 255)

    printf '%d.%d.%d.%d' "$o1" "$o2" "$o3" "$o4"
}

# Generate random port number
# Usage: gen_port [privileged]
# If privileged is true, includes ports 1-1023
gen_port() {
    local privileged="${1:-false}"
    if [[ "$privileged" == "true" ]]; then
        # Intentionally sample from privileged ports some of the time so the
        # generator actually exercises that range during a normal test run.
        if [[ $(_proptest_rand_range 0 1) -eq 0 ]]; then
            _proptest_rand_range 1 1023
        else
            _proptest_rand_range 1024 65535
        fi
    else
        _proptest_rand_range 1024 65535
    fi
}

# Generate one of several types (sum type)
# Usage: gen_oneof gen_cmd1 gen_cmd2 gen_cmd3 ...
gen_oneof() {
    [[ $# -eq 0 ]] && return 1

    local idx
    idx=$(_proptest_rand_range 0 $(($# - 1)))

    # Get the generator at index
    shift "$idx"
    eval "$1"
}

# Generate random hex string
# Usage: gen_hex [min_len] [max_len]
gen_hex() {
    local min_len="${1:-1}"
    local max_len="${2:-32}"
    local charset="0123456789abcdef"

    gen_string "$min_len" "$max_len" "$charset"
}

# Generate random float (as string)
# Usage: gen_float [min] [max] [precision]
gen_float() {
    local min="${1:-0}"
    local max="${2:-1000}"
    local precision="${3:-2}"

    local int_part
    local frac_part
    local sign=""

    # Handle negative range
    if [[ $min -lt 0 && $max -gt 0 ]]; then
        local choose_neg
        choose_neg=$(_proptest_rand_range 0 1)
        if [[ $choose_neg -eq 1 ]]; then
            int_part=$(_proptest_rand_range 0 "${min#-}")
            sign="-"
        else
            int_part=$(_proptest_rand_range 0 "$max")
        fi
    elif [[ $max -lt 0 ]]; then
        int_part=$(_proptest_rand_range "${max#-}" "${min#-}")
        sign="-"
    else
        int_part=$(_proptest_rand_range "$min" "$max")
    fi

    # Generate fractional part
    local max_frac=$((10 ** precision - 1))
    frac_part=$(_proptest_rand_range 0 "$max_frac")

    printf '%s%d.%0*d' "$sign" "$int_part" "$precision" "$frac_part"
}

# =============================================================================
# SHRINKING
# =============================================================================

# Shrink an integer towards 0
# Usage: proptest_shrink_int value
proptest_shrink_int() {
    local value="$1"
    local shrunk=()

    # Always include 0
    shrunk+=(0)

    # If negative, try positive
    if [[ $value -lt 0 ]]; then
        shrunk+=("${value#-}")
    fi

    # Binary shrink towards 0
    local half=$((value / 2))
    [[ $half -ne 0 ]] && shrunk+=("$half")

    # Decrement
    if [[ $value -gt 0 ]]; then
        shrunk+=($((value - 1)))
    elif [[ $value -lt 0 ]]; then
        shrunk+=($((value + 1)))
    fi

    printf '%s\n' "${shrunk[@]}" | sort -u
}

# Shrink a string by removing characters
# Usage: proptest_shrink_string value
proptest_shrink_string() {
    local value="$1"
    local len=${#value}
    local shrunk=()

    # Always include empty string
    shrunk+=("")

    if [[ $len -gt 0 ]]; then
        # Remove first character
        shrunk+=("${value:1}")

        # Remove last character
        shrunk+=("${value:0:$((len-1))}")

        # Take first half
        shrunk+=("${value:0:$((len/2))}")

        # Remove middle character
        if [[ $len -gt 2 ]]; then
            local mid=$((len/2))
            shrunk+=("${value:0:mid}${value:$((mid+1))}")
        fi
    fi

    printf '%s\n' "${shrunk[@]}" | sort -u
}

# Generic shrink dispatcher
# Usage: proptest_shrink value [type]
proptest_shrink() {
    local value="$1"
    local type="${2:-auto}"

    case "$type" in
        int|integer|number)
            proptest_shrink_int "$value"
            ;;
        string)
            proptest_shrink_string "$value"
            ;;
        auto)
            # Auto-detect type
            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                proptest_shrink_int "$value"
            else
                proptest_shrink_string "$value"
            fi
            ;;
        *)
            # Unknown type, return as-is
            printf '%s\n' "$value"
            ;;
    esac
}

# =============================================================================
# ASSERTIONS
# =============================================================================

# Check a property condition
# Usage: proptest_check condition message
# Returns: 0 if condition true, 1 if false
proptest_check() {
    local condition="$1"
    local message="${2:-Property check failed}"

    if eval "$condition"; then
        return 0
    else
        if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
            printf 'FAIL: %s\n' "$message" >&2
        fi
        return 1
    fi
}

# Assert equality
# Usage: proptest_assert_eq expected actual [message]
# shellcheck disable=SC2016  # single quotes in message are literal
proptest_assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected' but got '$actual'}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
            printf 'FAIL: %s\n' "$message" >&2
        fi
        return 1
    fi
}

# Assert not equal
# Usage: proptest_assert_ne value1 value2 [message]
# shellcheck disable=SC2016  # single quotes in message are literal
proptest_assert_ne() {
    local value1="$1"
    local value2="$2"
    local message="${3:-Values should not be equal: '$value1'}"

    if [[ "$value1" != "$value2" ]]; then
        return 0
    else
        if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
            printf 'FAIL: %s\n' "$message" >&2
        fi
        return 1
    fi
}

# Assert value matches pattern
# Usage: proptest_assert_match pattern value [message]
# shellcheck disable=SC2016  # single quotes in message are literal
proptest_assert_match() {
    local pattern="$1"
    local value="$2"
    local message="${3:-Value '$value' does not match pattern '$pattern'}"

    if [[ "$value" =~ $pattern ]]; then
        return 0
    else
        if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
            printf 'FAIL: %s\n' "$message" >&2
        fi
        return 1
    fi
}

# =============================================================================
# TEST RUNNER
# =============================================================================

# Run a property-based test
# Usage: proptest_run name generator property
# Arguments:
#   name: Test name for reporting
#   generator: Command to generate test input
#   property: Command/function to test (receives input as $1)
# Example:
#   proptest_run "reverse_reverse" "gen_string 1 50" '
#     local input="$1"
#     local reversed=$(echo "$input" | rev)
#     local double_reversed=$(echo "$reversed" | rev)
#     [[ "$input" == "$double_reversed" ]]
#   '
proptest_run() {
    local name="$1"
    local generator="$2"
    local property="$3"
    local iterations="${4:-$PROPTEST_ITERATIONS}"

    _PROPTEST_CURRENT_TEST="$name"
    _PROPTEST_ITERATION=0

    # Initialize random seed
    if [[ -n "$PROPTEST_SEED" ]]; then
        _proptest_srand "$PROPTEST_SEED"
    else
        _proptest_srand
    fi

    local seed_used="$_PROPTEST_LAST_SEED"
    local failed=0
    local failing_input=""
    local shrunk_input=""

    if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
        printf 'Running: %s (seed=%s, iterations=%d)\n' "$name" "$seed_used" "$iterations"
    fi

    for ((i=1; i<=iterations; i++)); do
        _PROPTEST_ITERATION=$i

        # Generate test input
        local input
        input=$(eval "$generator")

        if [[ "$PROPTEST_VERBOSE" == "1" ]]; then
            printf '  [%d/%d] Testing with: %s\n' "$i" "$iterations" "$input"
        fi

        # Run property test in isolated subshell
        local test_result=0
        (
            _proptest_property() {
                # shellcheck disable=SC2030  # subshell isolation is intentional
                local input="$1"
                eval "$property"
            }
            _proptest_property "$input"
        ) || test_result=$?

        if [[ $test_result -ne 0 ]]; then
            failed=1
            # shellcheck disable=SC2031  # input is from outer scope, not subshell
            failing_input="$input"

            # Attempt shrinking
            if [[ "$PROPTEST_MAX_SHRINKS" -gt 0 ]]; then
                shrunk_input=$(_proptest_shrink_failing "$generator" "$property" "$failing_input")
            else
                shrunk_input="$failing_input"
            fi

            break
        fi
    done

    # Report results
    if [[ $failed -eq 0 ]]; then
        ((_PROPTEST_PASS_COUNT++))

        if [[ "$PROPTEST_OUTPUT" == "json" ]]; then
            printf '{"test":"%s","status":"pass","iterations":%d,"seed":"%s"}\n' \
                "$name" "$iterations" "$seed_used"
        else
            printf 'PASS: %s (%d iterations, seed=%s)\n' "$name" "$iterations" "$seed_used"
        fi
        return 0
    else
        ((_PROPTEST_FAIL_COUNT++))
        _PROPTEST_FAILURES+=("$name: $shrunk_input")

        if [[ "$PROPTEST_OUTPUT" == "json" ]]; then
            local escaped_input
            escaped_input=$(printf '%s' "$shrunk_input" | sed 's/"/\\"/g; s/\\/\\\\/g')
            printf '{"test":"%s","status":"fail","iteration":%d,"seed":"%s","original_input":"%s","shrunk_input":"%s"}\n' \
                "$name" "$_PROPTEST_ITERATION" "$seed_used" \
                "$(printf '%s' "$failing_input" | sed 's/"/\\"/g; s/\\/\\\\/g')" \
                "$escaped_input"
        else
            printf 'FAIL: %s\n' "$name"
            printf '  Seed: %s (use PROPTEST_SEED=%s to reproduce)\n' "$seed_used" "$seed_used"
            printf '  Failed at iteration: %d\n' "$_PROPTEST_ITERATION"
            printf '  Original failing input: %s\n' "$failing_input"
            if [[ "$shrunk_input" != "$failing_input" ]]; then
                printf '  Shrunk to minimal example: %s\n' "$shrunk_input"
            fi
        fi
        return 1
    fi
}

# Internal: Shrink a failing input to minimal example
# Usage: _proptest_shrink_failing generator property failing_input
_proptest_shrink_failing() {
    local generator="$1"
    local property="$2"
    local failing_input="$3"
    local max_attempts="$PROPTEST_MAX_SHRINKS"

    local current="$failing_input"
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))
        ((_PROPTEST_SHRINK_COUNT++))

        # Get candidate shrinks
        local shrinks
        mapfile -t shrinks < <(proptest_shrink "$current")

        local found_smaller=false

        for candidate in "${shrinks[@]}"; do
            # Skip if same as current
            [[ "$candidate" == "$current" ]] && continue

            # Test if candidate still fails
            local test_result=0
            (
                _proptest_property() {
                    local input="$1"
                    eval "$property"
                }
                _proptest_property "$candidate"
            ) || test_result=$?

            if [[ $test_result -ne 0 ]]; then
                # Found a smaller failing case
                current="$candidate"
                found_smaller=true
                break
            fi
        done

        # If no smaller case found, we're done
        $found_smaller || break
    done

    printf '%s' "$current"
}

# Run multiple property tests
# Usage: proptest_suite test_function1 test_function2 ...
# Each test function should call proptest_run
proptest_suite() {
    local start_time
    start_time=$(date +%s)

    _PROPTEST_PASS_COUNT=0
    _PROPTEST_FAIL_COUNT=0
    _PROPTEST_SHRINK_COUNT=0
    _PROPTEST_FAILURES=()

    for test_fn in "$@"; do
        if declare -F "$test_fn" &>/dev/null; then
            "$test_fn" || true
        else
            printf 'WARNING: Test function not found: %s\n' "$test_fn" >&2
        fi
    done

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Print summary
    printf '\n'
    printf '=%.0s' {1..60}
    printf '\n'
    printf 'Property Test Summary\n'
    printf '=%.0s' {1..60}
    printf '\n'
    printf 'Passed: %d\n' "$_PROPTEST_PASS_COUNT"
    printf 'Failed: %d\n' "$_PROPTEST_FAIL_COUNT"
    printf 'Shrink attempts: %d\n' "$_PROPTEST_SHRINK_COUNT"
    printf 'Duration: %ds\n' "$duration"

    if [[ ${#_PROPTEST_FAILURES[@]} -gt 0 ]]; then
        printf '\nFailing tests:\n'
        for failure in "${_PROPTEST_FAILURES[@]}"; do
            printf '  - %s\n' "$failure"
        done
    fi

    printf '\n'

    [[ $_PROPTEST_FAIL_COUNT -eq 0 ]]
}

# =============================================================================
# USOP OUTPUT (Universal Structured Output Protocol)
# =============================================================================

# Output test result in USOP format
# Usage: proptest_usop_result name status [details]
proptest_usop_result() {
    local name="$1"
    local status="$2"
    local details="${3:-}"

    if [[ "$PROPTEST_OUTPUT" == "json" ]]; then
        local json
        json=$(printf '{"test":"%s","status":"%s"' "$name" "$status")
        if [[ -n "$details" ]]; then
            json+=",\"details\":\"$details\""
        fi
        json+="}"
        printf '%s\n' "$json"
    else
        printf '[%s] %s' "$status" "$name"
        [[ -n "$details" ]] && printf ': %s' "$details"
        printf '\n'
    fi
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Quick property test with inline property
# Usage: proptest name generator property
proptest() {
    proptest_run "$@"
}

# Reset test statistics
# Usage: proptest_reset
proptest_reset() {
    _PROPTEST_PASS_COUNT=0
    _PROPTEST_FAIL_COUNT=0
    _PROPTEST_SHRINK_COUNT=0
    _PROPTEST_FAILURES=()
    _PROPTEST_CURRENT_TEST=""
    _PROPTEST_ITERATION=0
}

# Get test statistics
# Usage: proptest_stats
proptest_stats() {
    printf 'passed=%d failed=%d shrinks=%d\n' \
        "$_PROPTEST_PASS_COUNT" "$_PROPTEST_FAIL_COUNT" "$_PROPTEST_SHRINK_COUNT"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _PROPTEST_EXPORTS=(
    # Core functions
    proptest_run
    proptest_check
    proptest_shrink
    proptest_suite
    proptest
    proptest_reset
    proptest_stats
    # Assertions
    proptest_assert_eq
    proptest_assert_ne
    proptest_assert_match
    # Generators
    gen_int
    gen_positive_int
    gen_nat
    gen_string
    gen_ascii
    gen_alpha
    gen_lower
    gen_upper
    gen_choice
    gen_bool
    gen_array
    gen_email
    gen_uuid
    gen_json_object
    gen_url
    gen_date
    gen_ipv4
    gen_port
    gen_oneof
    gen_hex
    gen_float
    # Shrinking
    proptest_shrink_int
    proptest_shrink_string
    # USOP
    proptest_usop_result
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_PROPTEST_EXPORTS[@]}" 2>/dev/null || true
fi

#!/usr/bin/env bash
# =============================================================================
# basher/lib/args.sh - Argument parsing helpers for Basher toolkit
# =============================================================================

[[ -n "${_BASHER_ARGS_LOADED:-}" ]] && return 0
readonly _BASHER_ARGS_LOADED=1

# Source common library if not already loaded
[[ -z "${_BASHER_COMMON_LOADED:-}" ]] && source "${BASH_SOURCE%/*}/common.sh"

# =============================================================================
# ARGUMENT PARSER STATE
# =============================================================================

# Option definitions: array of "short:long:has_arg:description:default"
declare -ga _ARGS_OPTIONS=()

# Positional argument definitions: array of "name:required:description:default"
declare -ga _ARGS_POSITIONALS=()

# Parsed values (associative array)
declare -gA _ARGS_VALUES=()

# Remaining positional arguments
declare -ga _ARGS_REMAINING=()

# Script metadata
_ARGS_SCRIPT_NAME=""
_ARGS_SCRIPT_VERSION=""
_ARGS_SCRIPT_DESCRIPTION=""
_ARGS_SCRIPT_EXAMPLES=""

# =============================================================================
# ARGUMENT DEFINITION
# =============================================================================

# Set script metadata
args_script() {
    _ARGS_SCRIPT_NAME="${1:-$(basename "$0")}"
    _ARGS_SCRIPT_VERSION="${2:-1.0.0}"
    _ARGS_SCRIPT_DESCRIPTION="${3:-}"
}

# Add option definition
# Usage: args_option "short" "long" "has_arg" "description" "default"
args_option() {
    local short="$1"
    local long="$2"
    local has_arg="${3:-false}"
    local description="${4:-}"
    local default="${5:-}"

    _ARGS_OPTIONS+=("${short}:${long}:${has_arg}:${description}:${default}")

    # Set default value
    if [[ -n "$long" ]]; then
        _ARGS_VALUES["$long"]="$default"
    elif [[ -n "$short" ]]; then
        _ARGS_VALUES["$short"]="$default"
    fi
}

# Add positional argument definition
# Usage: args_positional "name" "required" "description" "default"
args_positional() {
    local name="$1"
    local required="${2:-false}"
    local description="${3:-}"
    local default="${4:-}"

    _ARGS_POSITIONALS+=("${name}:${required}:${description}:${default}")
    _ARGS_VALUES["$name"]="$default"
}

# Add example usage
args_example() {
    _ARGS_SCRIPT_EXAMPLES+="  $1\n"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

# Parse command line arguments
args_parse() {
    local -a args=("$@")
    local -i i=0
    local -i pos_idx=0

    while [[ $i -lt ${#args[@]} ]]; do
        local arg="${args[$i]}"

        case "$arg" in
            -h|--help)
                args_usage
                exit 0
                ;;
            -V|--version)
                printf "%s version %s\n" "$_ARGS_SCRIPT_NAME" "$_ARGS_SCRIPT_VERSION"
                exit 0
                ;;
            --)
                # End of options, rest are positional
                ((i++))
                while [[ $i -lt ${#args[@]} ]]; do
                    _ARGS_REMAINING+=("${args[$i]}")
                    ((i++))
                done
                break
                ;;
            --*=*)
                # Long option with value: --option=value
                local opt="${arg%%=*}"
                local val="${arg#*=}"
                opt="${opt#--}"

                if _args_set_option "" "$opt" "$val"; then
                    ((i++))
                    continue
                else
                    die_usage "Unknown option: --$opt"
                fi
                ;;
            --*)
                # Long option: --option [value]
                local opt="${arg#--}"

                local has_arg
                has_arg=$(_args_option_has_arg "" "$opt")

                if [[ "$has_arg" == "true" ]]; then
                    if [[ $((i + 1)) -lt ${#args[@]} ]]; then
                        ((i++))
                        _args_set_option "" "$opt" "${args[$i]}"
                    else
                        die_usage "Option --$opt requires an argument"
                    fi
                elif [[ "$has_arg" == "false" ]]; then
                    _args_set_option "" "$opt" "true"
                else
                    die_usage "Unknown option: --$opt"
                fi
                ;;
            -*)
                # Short option(s): -abc or -a value
                local opts="${arg#-}"
                local -i j=0

                while [[ $j -lt ${#opts} ]]; do
                    local opt="${opts:$j:1}"
                    local has_arg
                    has_arg=$(_args_option_has_arg "$opt" "")

                    if [[ "$has_arg" == "true" ]]; then
                        # Check if value is rest of string or next arg
                        if [[ $((j + 1)) -lt ${#opts} ]]; then
                            _args_set_option "$opt" "" "${opts:$((j + 1))}"
                            break
                        elif [[ $((i + 1)) -lt ${#args[@]} ]]; then
                            ((i++))
                            _args_set_option "$opt" "" "${args[$i]}"
                        else
                            die_usage "Option -$opt requires an argument"
                        fi
                    elif [[ "$has_arg" == "false" ]]; then
                        _args_set_option "$opt" "" "true"
                    else
                        die_usage "Unknown option: -$opt"
                    fi
                    ((j++))
                done
                ;;
            *)
                # Positional argument
                if [[ $pos_idx -lt ${#_ARGS_POSITIONALS[@]} ]]; then
                    local spec="${_ARGS_POSITIONALS[$pos_idx]}"
                    local name="${spec%%:*}"
                    _ARGS_VALUES["$name"]="$arg"
                    ((pos_idx++))
                else
                    _ARGS_REMAINING+=("$arg")
                fi
                ;;
        esac
        ((i++))
    done

    # Validate required positional arguments
    for spec in "${_ARGS_POSITIONALS[@]}"; do
        local IFS=':'
        read -ra parts <<< "$spec"
        local name="${parts[0]}"
        local required="${parts[1]}"

        if [[ "$required" == "true" && -z "${_ARGS_VALUES[$name]:-}" ]]; then
            die_usage "Missing required argument: $name"
        fi
    done
}

# Check if option takes an argument
_args_option_has_arg() {
    local short="$1"
    local long="$2"

    for spec in "${_ARGS_OPTIONS[@]}"; do
        local IFS=':'
        read -ra parts <<< "$spec"
        local s="${parts[0]}"
        local l="${parts[1]}"
        local has_arg="${parts[2]}"

        if [[ (-n "$short" && "$s" == "$short") || (-n "$long" && "$l" == "$long") ]]; then
            printf '%s' "$has_arg"
            return 0
        fi
    done

    printf ''  # Unknown option
}

# Set option value
_args_set_option() {
    local short="$1"
    local long="$2"
    local value="$3"

    for spec in "${_ARGS_OPTIONS[@]}"; do
        local IFS=':'
        read -ra parts <<< "$spec"
        local s="${parts[0]}"
        local l="${parts[1]}"

        if [[ (-n "$short" && "$s" == "$short") || (-n "$long" && "$l" == "$long") ]]; then
            # Use long name as key, fall back to short
            local key="${l:-$s}"
            _ARGS_VALUES["$key"]="$value"
            return 0
        fi
    done

    return 1  # Unknown option
}

# =============================================================================
# ARGUMENT ACCESS
# =============================================================================

# Get argument value
args_get() {
    local name="$1"
    local default="${2:-}"

    printf '%s' "${_ARGS_VALUES[$name]:-$default}"
}

# Get argument as boolean
args_get_bool() {
    local name="$1"
    local value="${_ARGS_VALUES[$name]:-false}"

    [[ "$value" == "true" ]]
}

# Get argument as integer
args_get_int() {
    local name="$1"
    local default="${2:-0}"
    local value="${_ARGS_VALUES[$name]:-$default}"

    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%d' "$value"
    else
        printf '%d' "$default"
    fi
}

# Get remaining positional arguments
args_remaining() {
    printf '%s\n' "${_ARGS_REMAINING[@]}"
}

# Get number of remaining arguments
args_remaining_count() {
    printf '%d' "${#_ARGS_REMAINING[@]}"
}

# Check if option was provided
args_has() {
    local name="$1"

    [[ -n "${_ARGS_VALUES[$name]:-}" ]]
}

# =============================================================================
# USAGE GENERATION
# =============================================================================

# Generate and print usage message
args_usage() {
    local script_name="${_ARGS_SCRIPT_NAME:-$(basename "$0")}"

    # Header
    printf "%bUsage:%b %s [OPTIONS]" "$CLR_BOLD" "$CLR_RESET" "$script_name"

    # Positional arguments
    for spec in "${_ARGS_POSITIONALS[@]}"; do
        local IFS=':'
        read -ra parts <<< "$spec"
        local name="${parts[0]}"
        local required="${parts[1]}"

        if [[ "$required" == "true" ]]; then
            printf " <%s>" "$name"
        else
            printf " [%s]" "$name"
        fi
    done
    printf "\n"

    # Description
    if [[ -n "$_ARGS_SCRIPT_DESCRIPTION" ]]; then
        printf "\n%s\n" "$_ARGS_SCRIPT_DESCRIPTION"
    fi

    # Options
    if [[ ${#_ARGS_OPTIONS[@]} -gt 0 ]]; then
        printf "\n%bOptions:%b\n" "$CLR_BOLD" "$CLR_RESET"

        for spec in "${_ARGS_OPTIONS[@]}"; do
            local IFS=':'
            read -ra parts <<< "$spec"
            local short="${parts[0]}"
            local long="${parts[1]}"
            local has_arg="${parts[2]}"
            local description="${parts[3]}"
            local default="${parts[4]}"

            local opt_str=""

            if [[ -n "$short" && -n "$long" ]]; then
                opt_str="  -$short, --$long"
            elif [[ -n "$short" ]]; then
                opt_str="  -$short"
            else
                opt_str="      --$long"
            fi

            if [[ "$has_arg" == "true" ]]; then
                opt_str+=" <value>"
            fi

            printf "%-28s %s" "$opt_str" "$description"

            if [[ -n "$default" ]]; then
                printf " %b(default: %s)%b" "$CLR_DIM" "$default" "$CLR_RESET"
            fi
            printf "\n"
        done

        # Built-in options
        printf "  %-26s %s\n" "-h, --help" "Show this help message"
        printf "  %-26s %s\n" "-V, --version" "Show version information"
    fi

    # Positional arguments description
    if [[ ${#_ARGS_POSITIONALS[@]} -gt 0 ]]; then
        printf "\n%bArguments:%b\n" "$CLR_BOLD" "$CLR_RESET"

        for spec in "${_ARGS_POSITIONALS[@]}"; do
            local IFS=':'
            read -ra parts <<< "$spec"
            local name="${parts[0]}"
            local required="${parts[1]}"
            local description="${parts[2]}"
            local default="${parts[3]}"

            local req_str=""
            [[ "$required" == "true" ]] && req_str=" (required)"

            printf "  %-26s %s%s" "$name" "$description" "$req_str"

            if [[ -n "$default" ]]; then
                printf " %b(default: %s)%b" "$CLR_DIM" "$default" "$CLR_RESET"
            fi
            printf "\n"
        done
    fi

    # Examples
    if [[ -n "$_ARGS_SCRIPT_EXAMPLES" ]]; then
        printf "\n%bExamples:%b\n" "$CLR_BOLD" "$CLR_RESET"
        printf "%b" "$_ARGS_SCRIPT_EXAMPLES"
    fi
}

# Generate usage string (for USAGE variable used by die_usage)
args_usage_string() {
    USAGE=$(args_usage 2>&1)
}

# =============================================================================
# COMMON OPTION PRESETS
# =============================================================================

# Add common options (verbose, quiet, etc.)
args_common_options() {
    args_option "v" "verbose"  "false" "Enable verbose output"
    args_option "q" "quiet"    "false" "Suppress non-error output"
    args_option "n" "dry-run"  "false" "Show what would be done without doing it"
    args_option ""  "no-color" "false" "Disable colored output"
    args_option ""  "debug"    "false" "Enable debug output"
}

# Apply common options (call after args_parse)
args_apply_common() {
    if args_get_bool "verbose"; then
        BASHER_LOG_LEVEL=$LOG_LEVEL_DEBUG
    fi

    if args_get_bool "quiet"; then
        BASHER_LOG_LEVEL=$LOG_LEVEL_ERROR
    fi

    if args_get_bool "debug"; then
        BASHER_LOG_LEVEL=$LOG_LEVEL_DEBUG
        set -x
    fi

    if args_get_bool "no-color"; then
        export NO_COLOR=1
    fi
}

# =============================================================================
# RESET FUNCTIONS
# =============================================================================

# Reset argument parser state
args_reset() {
    _ARGS_OPTIONS=()
    _ARGS_POSITIONALS=()
    _ARGS_VALUES=()
    _ARGS_REMAINING=()
    _ARGS_SCRIPT_NAME=""
    _ARGS_SCRIPT_VERSION=""
    _ARGS_SCRIPT_DESCRIPTION=""
    _ARGS_SCRIPT_EXAMPLES=""
}

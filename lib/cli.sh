#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/cli.sh - Declarative CLI Framework
# =============================================================================
# Description: A declarative, intuitive CLI framework for building command-line
#              applications with automatic help generation, validation, and
#              subcommand support.
# Purpose: Enables clean, maintainable CLI definitions without boilerplate
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CLI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CLI_LOADED=1

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Application metadata
declare -g _CLI_NAME=""
declare -g _CLI_VERSION=""
declare -g _CLI_DESCRIPTION=""

# Flag definitions: array of "long:short:description"
declare -ga _CLI_FLAGS=()

# Option definitions: array of "long:short:description:default"
declare -ga _CLI_OPTIONS=()

# Positional definitions: array of "name:description:required:multiple"
declare -ga _CLI_POSITIONALS=()

# Subcommand definitions: array of "name:description:handler"
declare -ga _CLI_SUBCOMMANDS=()

# Example usage lines
declare -ga _CLI_EXAMPLES=()

# Parsed values - exported to caller as CLI_* variables
declare -gA _CLI_VALUES=()

# Remaining arguments after parsing
declare -ga _CLI_REMAINING=()

# Currently active subcommand (if any)
declare -g _CLI_SUBCOMMAND=""

# Validation rules: array of "name:type"
declare -gA _CLI_VALIDATIONS=()

# =============================================================================
# METADATA FUNCTIONS
# =============================================================================

# Set the application name
# Usage: cli::name "myapp"
cli::name() {
    _CLI_NAME="$1"
}

# Set the application version
# Usage: cli::version "1.0.0"
cli::version() {
    _CLI_VERSION="$1"
}

# Set the application description
# Usage: cli::description "My awesome application"
cli::description() {
    _CLI_DESCRIPTION="$1"
}

# =============================================================================
# FLAG AND OPTION DEFINITIONS
# =============================================================================

# Define a boolean flag (--flag or -f)
# Usage: cli::flag "long-name" "short" "description"
# Example: cli::flag "verbose" "v" "Enable verbose output"
cli::flag() {
    local long="$1"
    local short="${2:-}"
    local description="${3:-}"
    
    _CLI_FLAGS+=("${long}:${short}:${description}")
    
    # Initialize to false
    local var_name="_CLI_${long//-/_}"
    _CLI_VALUES["$long"]=false
}

# Define an option that takes a value (--option value or -o value)
# Usage: cli::option "long-name" "short" "description" [default]
# Example: cli::option "output" "o" "Output file" "out.txt"
cli::option() {
    local long="$1"
    local short="${2:-}"
    local description="${3:-}"
    local default="${4:-}"
    
    _CLI_OPTIONS+=("${long}:${short}:${description}:${default}")
    
    # Set default value
    _CLI_VALUES["$long"]="$default"
}

# Define a positional argument
# Usage: cli::positional "name" "description" [required|optional] [single|multiple]
# Example: cli::positional "input" "Input file" required
# Example: cli::positional "files" "Extra files" optional multiple
cli::positional() {
    local name="$1"
    local description="${2:-}"
    local required="${3:-required}"
    local multiple="${4:-single}"
    
    # Normalize
    [[ "$required" != "optional" ]] && required="required"
    [[ "$multiple" != "multiple" ]] && multiple="single"
    
    _CLI_POSITIONALS+=("${name}:${description}:${required}:${multiple}")
    
    # Initialize
    if [[ "$multiple" == "multiple" ]]; then
        _CLI_VALUES["$name"]=""
    else
        _CLI_VALUES["$name"]=""
    fi
}

# Add an example usage line
# Usage: cli::example "myapp --verbose input.txt"
cli::example() {
    _CLI_EXAMPLES+=("$1")
}

# =============================================================================
# SUBCOMMAND SUPPORT
# =============================================================================

# Define a subcommand
# Usage: cli::subcommand "name" "description" [handler_function]
# Example: cli::subcommand "init" "Initialize project" "cmd_init"
cli::subcommand() {
    local name="$1"
    local description="${2:-}"
    local handler="${3:-}"
    
    _CLI_SUBCOMMANDS+=("${name}:${description}:${handler}")
}

# Get the active subcommand
# Usage: subcmd=$(cli::get_subcommand)
cli::get_subcommand() {
    printf '%s' "$_CLI_SUBCOMMAND"
}

# Check if a specific subcommand is active
# Usage: if cli::is_subcommand "init"; then ...; fi
cli::is_subcommand() {
    [[ "$_CLI_SUBCOMMAND" == "$1" ]]
}

# =============================================================================
# PARSING
# =============================================================================

# Parse command line arguments and populate CLI_* variables
# Usage: cli::parse "$@"
cli::parse() {
    local -a args=("$@")
    local -i i=0
    local -i pos_idx=0
    local found_double_dash=false
    
    # Check for subcommand first (if subcommands are defined)
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 && ${#args[@]} -gt 0 ]]; then
        local first_arg="${args[0]}"
        
        # Check if first arg is a subcommand
        for spec in "${_CLI_SUBCOMMANDS[@]}"; do
            local name="${spec%%:*}"
            if [[ "$first_arg" == "$name" ]]; then
                _CLI_SUBCOMMAND="$name"
                args=("${args[@]:1}")  # Remove subcommand from args
                break
            fi
        done
    fi
    
    while [[ $i -lt ${#args[@]} ]]; do
        local arg="${args[$i]}"
        
        if $found_double_dash; then
            # After --, everything is positional
            _cli_add_positional "$pos_idx" "$arg" && ((pos_idx++)) || true
            ((i++))
            continue
        fi
        
        case "$arg" in
            -h|--help)
                cli::help
                exit 0
                ;;
            -V|--version)
                printf '%s version %s\n' "${_CLI_NAME:-$(basename "$0")}" "${_CLI_VERSION:-1.0.0}"
                exit 0
                ;;
            --)
                found_double_dash=true
                ((i++))
                continue
                ;;
            --*=*)
                # Long option with value: --option=value
                local opt="${arg%%=*}"
                local val="${arg#*=}"
                opt="${opt#--}"
                
                if ! _cli_set_option "$opt" "$val"; then
                    cli::error "Unknown option: --$opt"
                fi
                ;;
            --no-*)
                # Negated flag: --no-verbose
                local opt="${arg#--no-}"
                if _cli_is_flag "$opt"; then
                    _CLI_VALUES["$opt"]=false
                else
                    cli::error "Unknown option: $arg"
                fi
                ;;
            --*)
                # Long option or flag: --option [value]
                local opt="${arg#--}"
                
                if _cli_is_flag "$opt"; then
                    _CLI_VALUES["$opt"]=true
                elif _cli_is_option "$opt"; then
                    if [[ $((i + 1)) -lt ${#args[@]} && "${args[$((i + 1))]}" != -* ]]; then
                        ((i++))
                        _cli_set_option "$opt" "${args[$i]}"
                    else
                        cli::error "Option --$opt requires a value"
                    fi
                else
                    cli::error "Unknown option: --$opt"
                fi
                ;;
            -*)
                # Short options: -v, -abc, -o value
                local opts="${arg#-}"
                local -i j=0
                
                while [[ $j -lt ${#opts} ]]; do
                    local short="${opts:$j:1}"
                    local long
                    long=$(_cli_short_to_long "$short")
                    
                    if [[ -z "$long" ]]; then
                        cli::error "Unknown option: -$short"
                    fi
                    
                    if _cli_is_flag "$long"; then
                        _CLI_VALUES["$long"]=true
                        ((j++))
                    elif _cli_is_option "$long"; then
                        # Check if value is rest of string or next arg
                        if [[ $((j + 1)) -lt ${#opts} ]]; then
                            _cli_set_option "$long" "${opts:$((j + 1))}"
                            break
                        elif [[ $((i + 1)) -lt ${#args[@]} ]]; then
                            ((i++))
                            _cli_set_option "$long" "${args[$i]}"
                        else
                            cli::error "Option -$short requires a value"
                        fi
                        break
                    fi
                done
                ;;
            *)
                # Positional argument
                _cli_add_positional "$pos_idx" "$arg" && ((pos_idx++)) || true
                ;;
        esac
        ((i++))
    done
    
    # Export CLI_* variables to caller's scope
    _cli_export_values
    
    return 0
}

# =============================================================================
# INTERNAL PARSING HELPERS
# =============================================================================

# Check if a long name is a flag
_cli_is_flag() {
    local name="$1"
    for spec in "${_CLI_FLAGS[@]}"; do
        local long="${spec%%:*}"
        [[ "$long" == "$name" ]] && return 0
    done
    return 1
}

# Check if a long name is an option
_cli_is_option() {
    local name="$1"
    for spec in "${_CLI_OPTIONS[@]}"; do
        local long="${spec%%:*}"
        [[ "$long" == "$name" ]] && return 0
    done
    return 1
}

# Convert short option to long name
_cli_short_to_long() {
    local short="$1"
    
    # Check flags
    for spec in "${_CLI_FLAGS[@]}"; do
        local rest="${spec#*:}"
        local s="${rest%%:*}"
        [[ "$s" == "$short" ]] && { printf '%s' "${spec%%:*}"; return 0; }
    done
    
    # Check options
    for spec in "${_CLI_OPTIONS[@]}"; do
        local rest="${spec#*:}"
        local s="${rest%%:*}"
        [[ "$s" == "$short" ]] && { printf '%s' "${spec%%:*}"; return 0; }
    done
    
    return 1
}

# Set an option value
_cli_set_option() {
    local name="$1"
    local value="$2"
    
    if _cli_is_option "$name"; then
        _CLI_VALUES["$name"]="$value"
        return 0
    elif _cli_is_flag "$name"; then
        # Allow --flag=true or --flag=false
        case "${value,,}" in
            true|yes|1|on) _CLI_VALUES["$name"]=true ;;
            false|no|0|off) _CLI_VALUES["$name"]=false ;;
            *) _CLI_VALUES["$name"]=true ;;
        esac
        return 0
    fi
    
    return 1
}

# Add a positional argument
_cli_add_positional() {
    local idx="$1"
    local value="$2"
    
    if [[ $idx -lt ${#_CLI_POSITIONALS[@]} ]]; then
        local spec="${_CLI_POSITIONALS[$idx]}"
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        rest="${rest#*:}"
        local multiple="${rest%%:*}"
        
        if [[ "$multiple" == "multiple" ]]; then
            # Append to existing value with newline separator
            if [[ -n "${_CLI_VALUES[$name]:-}" ]]; then
                _CLI_VALUES["$name"]+=$'\n'"$value"
            else
                _CLI_VALUES["$name"]="$value"
            fi
            return 1  # Don't advance index for multiple
        else
            _CLI_VALUES["$name"]="$value"
        fi
    else
        _CLI_REMAINING+=("$value")
    fi
    
    return 0
}

# Export values as CLI_* variables
_cli_export_values() {
    for key in "${!_CLI_VALUES[@]}"; do
        local var_name="CLI_${key//-/_}"
        local value="${_CLI_VALUES[$key]}"
        
        # Use printf -v for dynamic variable assignment
        printf -v "$var_name" '%s' "$value"
        
        # Export the variable
        export "${var_name?}"
    done
    
    # Export remaining args as CLI_REMAINING array
    # shellcheck disable=SC2034  # CLI_REMAINING is exported for external use
    CLI_REMAINING=("${_CLI_REMAINING[@]}")
}

# =============================================================================
# VALUE ACCESS
# =============================================================================

# Get a parsed value
# Usage: value=$(cli::get "option-name")
cli::get() {
    local name="$1"
    local default="${2:-}"
    
    printf '%s' "${_CLI_VALUES[$name]:-$default}"
}

# Get a flag as boolean (returns 0 for true, 1 for false)
# Usage: if cli::is "verbose"; then ...; fi
cli::is() {
    local name="$1"
    local value="${_CLI_VALUES[$name]:-false}"
    
    [[ "$value" == "true" ]]
}

# Get an array value (for multiple positionals)
# Usage: cli::get_array "files" arr
cli::get_array() {
    local name="$1"
    # shellcheck disable=SC2034
    local -n result_ref="$2"
    local value="${_CLI_VALUES[$name]:-}"
    
    if [[ -n "$value" ]]; then
        IFS=$'\n' read -r -d '' -a result_ref <<< "$value" || true
    else
        result_ref=()
    fi
}

# Get remaining (extra) positional arguments
# Usage: cli::remaining arr
cli::remaining() {
    # shellcheck disable=SC2178
    local -n result_ref="$1"
    # shellcheck disable=SC2034
    result_ref=("${_CLI_REMAINING[@]}")
}

# Check if a value was provided
# Usage: if cli::has "output"; then ...; fi
cli::has() {
    local name="$1"
    [[ -n "${_CLI_VALUES[$name]:-}" ]]
}

# =============================================================================
# VALIDATION
# =============================================================================

# Set validation type for an option
# Usage: cli::validate_type "count" integer
cli::validate_type() {
    local name="$1"
    local type="$2"
    
    _CLI_VALIDATIONS["$name"]="$type"
}

# Validate all required arguments are present
# Usage: cli::validate_required
cli::validate_required() {
    local errors=()
    
    for spec in "${_CLI_POSITIONALS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        local required="${rest%%:*}"
        
        if [[ "$required" == "required" && -z "${_CLI_VALUES[$name]:-}" ]]; then
            errors+=("Missing required argument: $name")
        fi
    done
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for err in "${errors[@]}"; do
            cli::error "$err" --no-exit
        done
        printf '\n' >&2
        cli::help >&2
        exit 1
    fi
    
    return 0
}

# Validate types for all registered validations
# Usage: cli::validate
cli::validate() {
    local errors=()
    
    for name in "${!_CLI_VALIDATIONS[@]}"; do
        local type="${_CLI_VALIDATIONS[$name]}"
        local value="${_CLI_VALUES[$name]:-}"
        
        # Skip empty optional values
        [[ -z "$value" ]] && continue
        
        case "$type" in
            integer|int)
                if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
                    errors+=("$name must be an integer, got: $value")
                fi
                ;;
            positive)
                if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
                    errors+=("$name must be a positive integer, got: $value")
                fi
                ;;
            float|number)
                if [[ ! "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
                    errors+=("$name must be a number, got: $value")
                fi
                ;;
            file)
                if [[ ! -f "$value" ]]; then
                    errors+=("$name must be an existing file: $value")
                fi
                ;;
            dir|directory)
                if [[ ! -d "$value" ]]; then
                    errors+=("$name must be an existing directory: $value")
                fi
                ;;
            path)
                if [[ ! -e "$value" ]]; then
                    errors+=("$name must be an existing path: $value")
                fi
                ;;
            nonempty)
                if [[ -z "$value" ]]; then
                    errors+=("$name cannot be empty")
                fi
                ;;
            *)
                # Treat as regex pattern
                if [[ ! "$value" =~ $type ]]; then
                    errors+=("$name has invalid format: $value")
                fi
                ;;
        esac
    done
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for err in "${errors[@]}"; do
            cli::error "$err" --no-exit
        done
        exit 1
    fi
    
    return 0
}

# Validate a specific value against a type
# Usage: cli::check "count" integer && echo "valid"
cli::check() {
    local name="$1"
    local type="$2"
    local value="${_CLI_VALUES[$name]:-}"
    
    case "$type" in
        integer|int)
            [[ "$value" =~ ^-?[0-9]+$ ]]
            ;;
        positive)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]
            ;;
        float|number)
            [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]
            ;;
        file)
            [[ -f "$value" ]]
            ;;
        dir|directory)
            [[ -d "$value" ]]
            ;;
        path)
            [[ -e "$value" ]]
            ;;
        nonempty)
            [[ -n "$value" ]]
            ;;
        *)
            # Treat as regex
            [[ "$value" =~ $type ]]
            ;;
    esac
}

# =============================================================================
# HELP GENERATION
# =============================================================================

# Generate and print help message
# Usage: cli::help
cli::help() {
    local name="${_CLI_NAME:-$(basename "$0")}"
    
    # Usage line
    printf '%bUsage:%b %s' "${CLR_BOLD:-}" "${CLR_RESET:-}" "$name"
    
    # Subcommand placeholder if defined
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
        printf ' <command>'
    fi
    
    # Options placeholder
    if [[ ${#_CLI_FLAGS[@]} -gt 0 || ${#_CLI_OPTIONS[@]} -gt 0 ]]; then
        printf ' [options]'
    fi
    
    # Positional arguments
    for spec in "${_CLI_POSITIONALS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        local required="${rest%%:*}"
        local multiple="${rest#*:}"
        
        if [[ "$required" == "required" ]]; then
            if [[ "$multiple" == "multiple" ]]; then
                printf ' <%s>...' "$name"
            else
                printf ' <%s>' "$name"
            fi
        else
            if [[ "$multiple" == "multiple" ]]; then
                printf ' [%s]...' "$name"
            else
                printf ' [%s]' "$name"
            fi
        fi
    done
    printf '\n'
    
    # Description
    if [[ -n "$_CLI_DESCRIPTION" ]]; then
        printf '\n%s\n' "$_CLI_DESCRIPTION"
    fi
    
    # Subcommands
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
        printf '\n%bCommands:%b\n' "${CLR_BOLD:-}" "${CLR_RESET:-}"
        
        for spec in "${_CLI_SUBCOMMANDS[@]}"; do
            local cmd="${spec%%:*}"
            local rest="${spec#*:}"
            local desc="${rest%%:*}"
            
            printf '  %-20s %s\n' "$cmd" "$desc"
        done
    fi
    
    # Options
    if [[ ${#_CLI_FLAGS[@]} -gt 0 || ${#_CLI_OPTIONS[@]} -gt 0 ]]; then
        printf '\n%bOptions:%b\n' "${CLR_BOLD:-}" "${CLR_RESET:-}"
        
        # Flags
        for spec in "${_CLI_FLAGS[@]}"; do
            local long="${spec%%:*}"
            local rest="${spec#*:}"
            local short="${rest%%:*}"
            local desc="${rest#*:}"
            
            local opt_str=""
            if [[ -n "$short" && -n "$long" ]]; then
                opt_str="  -$short, --$long"
            elif [[ -n "$short" ]]; then
                opt_str="  -$short"
            else
                opt_str="      --$long"
            fi
            
            printf '%-28s %s\n' "$opt_str" "$desc"
        done
        
        # Options with values
        for spec in "${_CLI_OPTIONS[@]}"; do
            local long="${spec%%:*}"
            local rest="${spec#*:}"
            local short="${rest%%:*}"
            rest="${rest#*:}"
            local desc="${rest%%:*}"
            local default="${rest#*:}"
            
            local opt_str=""
            if [[ -n "$short" && -n "$long" ]]; then
                opt_str="  -$short, --$long <val>"
            elif [[ -n "$short" ]]; then
                opt_str="  -$short <val>"
            else
                opt_str="      --$long <val>"
            fi
            
            printf '%-28s %s' "$opt_str" "$desc"
            if [[ -n "$default" ]]; then
                printf ' %b(default: %s)%b' "${CLR_DIM:-}" "$default" "${CLR_RESET:-}"
            fi
            printf '\n'
        done
        
        # Built-in options
        printf '  %-26s %s\n' "-h, --help" "Show this help message"
        printf '  %-26s %s\n' "-V, --version" "Show version information"
    fi
    
    # Positional arguments help
    if [[ ${#_CLI_POSITIONALS[@]} -gt 0 ]]; then
        printf '\n%bArguments:%b\n' "${CLR_BOLD:-}" "${CLR_RESET:-}"
        
        for spec in "${_CLI_POSITIONALS[@]}"; do
            local pname="${spec%%:*}"
            local rest="${spec#*:}"
            local desc="${rest%%:*}"
            rest="${rest#*:}"
            local required="${rest%%:*}"
            local multiple="${rest#*:}"
            
            local type_str=""
            [[ "$required" == "required" ]] && type_str=" (required)"
            [[ "$multiple" == "multiple" ]] && type_str+=" (multiple)"
            
            printf '  %-26s %s%s\n' "$pname" "$desc" "$type_str"
        done
    fi
    
    # Examples
    if [[ ${#_CLI_EXAMPLES[@]} -gt 0 ]]; then
        printf '\n%bExamples:%b\n' "${CLR_BOLD:-}" "${CLR_RESET:-}"
        for example in "${_CLI_EXAMPLES[@]}"; do
            printf '  %s\n' "$example"
        done
    fi
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Print an error message and exit
# Usage: cli::error "message" [--no-exit]
cli::error() {
    local message="$1"
    local no_exit=false
    
    [[ "${2:-}" == "--no-exit" ]] && no_exit=true
    
    printf '%sError:%s %s\n' "${CLR_RED:-}" "${CLR_RESET:-}" "$message" >&2
    
    if ! $no_exit; then
        exit 1
    fi
}

# Print a warning message
# Usage: cli::warn "message"
cli::warn() {
    printf '%sWarning:%s %s\n' "${CLR_YELLOW:-}" "${CLR_RESET:-}" "$1" >&2
}

# =============================================================================
# RESET / CLEANUP
# =============================================================================

# Reset all CLI state (useful for testing or defining multiple commands)
# Usage: cli::reset
cli::reset() {
    _CLI_NAME=""
    _CLI_VERSION=""
    _CLI_DESCRIPTION=""
    _CLI_FLAGS=()
    _CLI_OPTIONS=()
    _CLI_POSITIONALS=()
    _CLI_SUBCOMMANDS=()
    _CLI_EXAMPLES=()
    _CLI_VALUES=()
    _CLI_REMAINING=()
    _CLI_SUBCOMMAND=""
    _CLI_VALIDATIONS=()
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Quick setup: set name, version, and description in one call
# Usage: cli::init "myapp" "1.0.0" "My application description"
cli::init() {
    cli::reset
    _CLI_NAME="$1"
    _CLI_VERSION="${2:-1.0.0}"
    _CLI_DESCRIPTION="${3:-}"
}

# Add common options (verbose, quiet, dry-run)
# Usage: cli::common_options
cli::common_options() {
    cli::flag "verbose" "v" "Enable verbose output"
    cli::flag "quiet" "q" "Suppress non-error output"
    cli::flag "dry-run" "n" "Show what would be done without doing it"
}

# Run a subcommand handler if defined
# Usage: cli::run_subcommand
cli::run_subcommand() {
    if [[ -z "$_CLI_SUBCOMMAND" ]]; then
        return 1
    fi
    
    for spec in "${_CLI_SUBCOMMANDS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        local handler="${rest%%:*}"
        
        if [[ "$name" == "$_CLI_SUBCOMMAND" && -n "$handler" ]]; then
            "$handler"
            return $?
        fi
    done
    
    return 1
}

# =============================================================================
# DEBUGGING
# =============================================================================

# Print current CLI state for debugging
# Usage: cli::debug
cli::debug() {
    printf 'CLI Debug Info:\n'
    printf '  Name: %s\n' "$_CLI_NAME"
    printf '  Version: %s\n' "$_CLI_VERSION"
    printf '  Subcommand: %s\n' "$_CLI_SUBCOMMAND"
    printf '  Values:\n'
    for key in "${!_CLI_VALUES[@]}"; do
        printf '    %s = %s\n' "$key" "${_CLI_VALUES[$key]}"
    done
    if [[ ${#_CLI_REMAINING[@]} -gt 0 ]]; then
        printf '  Remaining: %s\n' "${_CLI_REMAINING[*]}"
    fi
}

# =============================================================================
# ENHANCED VALIDATION (v7.4 additions)
# =============================================================================

# Choice restrictions for options
declare -gA _CLI_CHOICES=()

# Range restrictions for numeric options
declare -gA _CLI_RANGES=()

# @pre: option defined
# @post: choice restriction registered
# @idempotent: yes (overwrites)
# @returns: 0
#
# Restrict option to specific choices.
#
# Usage: cli::choices "format" "json" "yaml" "toml"
cli::choices() {
    local name="$1"
    shift
    local choices_str=""
    local first=true

    for choice in "$@"; do
        $first || choices_str+="|"
        first=false
        choices_str+="$choice"
    done

    _CLI_CHOICES["$name"]="$choices_str"
}

# @pre: option defined
# @post: range restriction registered
# @idempotent: yes (overwrites)
# @returns: 0
#
# Restrict numeric option to a range.
#
# Usage: cli::range "port" 1 65535
cli::range() {
    local name="$1"
    local min="$2"
    local max="$3"

    _CLI_RANGES["$name"]="${min}|${max}"
}

# @pre: value exists
# @post: errors emitted for failed choice validation
# @returns: 0 if valid, 1 if invalid
#
# Validate a value against defined choices.
#
# Usage: cli::validate_choices "format"
cli::validate_choices() {
    local name="$1"
    local value="${_CLI_VALUES[$name]:-}"

    if [[ -n "$value" && -n "${_CLI_CHOICES[$name]:-}" ]]; then
        local choices="${_CLI_CHOICES[$name]}"
        local valid=false
        local IFS='|'
        read -ra choice_arr <<< "$choices"
        for choice in "${choice_arr[@]}"; do
            if [[ "$value" == "$choice" ]]; then
                valid=true
                break
            fi
        done
        if ! $valid; then
            local choice_list="${choices//|/, }"
            cli::error "Invalid value '$value' for $name. Choose one of: $choice_list" --no-exit
            return 1
        fi
    fi
    return 0
}

# @pre: value exists
# @post: errors emitted for failed range validation
# @returns: 0 if valid, 1 if invalid
#
# Validate a numeric value against defined range.
#
# Usage: cli::validate_range "port"
cli::validate_range() {
    local name="$1"
    local value="${_CLI_VALUES[$name]:-}"

    if [[ -n "$value" && -n "${_CLI_RANGES[$name]:-}" ]]; then
        local range="${_CLI_RANGES[$name]}"
        local IFS='|'
        read -ra range_parts <<< "$range"
        local min="${range_parts[0]}"
        local max="${range_parts[1]}"

        if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
            cli::error "$name must be an integer" --no-exit
            return 1
        elif (( value < min || value > max )); then
            cli::error "$name must be between $min and $max (got: $value)" --no-exit
            return 1
        fi
    fi
    return 0
}

# =============================================================================
# MAN PAGE GENERATION (v7.4 additions)
# =============================================================================

# @pre: CLI defined
# @post: man page content printed to stdout
# @idempotent: yes
# @returns: 0
#
# Generate a man page in troff format.
#
# Usage: cli::man > myapp.1
cli::man() {
    local prog="${_CLI_NAME:-$(basename "$0")}"
    local version="${_CLI_VERSION:-1.0.0}"
    local date
    date=$(date +"%Y-%m-%d")

    # Man page header
    printf '.TH %s 1 "%s" "%s" "User Commands"\n' "${prog^^}" "$date" "$version"

    # NAME section
    printf '.SH NAME\n'
    printf '%s \\- %s\n' "$prog" "${_CLI_DESCRIPTION:-command line tool}"

    # SYNOPSIS section
    printf '.SH SYNOPSIS\n'
    printf '.B %s\n' "$prog"
    [[ ${#_CLI_FLAGS[@]} -gt 0 || ${#_CLI_OPTIONS[@]} -gt 0 ]] && printf '[\\fIOPTIONS\\fR]\n'

    for spec in "${_CLI_POSITIONALS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        local required="${rest%%:*}"

        if [[ "$required" == "required" ]]; then
            printf '\\fI%s\\fR\n' "$name"
        else
            printf '[\\fI%s\\fR]\n' "$name"
        fi
    done

    # DESCRIPTION section
    printf '.SH DESCRIPTION\n'
    printf '%s\n' "${_CLI_DESCRIPTION:-No description available.}"

    # OPTIONS section
    if [[ ${#_CLI_FLAGS[@]} -gt 0 || ${#_CLI_OPTIONS[@]} -gt 0 ]]; then
        printf '.SH OPTIONS\n'

        for spec in "${_CLI_FLAGS[@]}"; do
            local long="${spec%%:*}"
            local rest="${spec#*:}"
            local short="${rest%%:*}"
            local desc="${rest#*:}"

            printf '.TP\n'
            if [[ -n "$short" ]]; then
                printf '.BR \\-%s ", " \\-\\-%s\n' "$short" "$long"
            else
                printf '.B \\-\\-%s\n' "$long"
            fi
            printf '%s\n' "$desc"
        done

        for spec in "${_CLI_OPTIONS[@]}"; do
            local long="${spec%%:*}"
            local rest="${spec#*:}"
            local short="${rest%%:*}"
            rest="${rest#*:}"
            local desc="${rest%%:*}"
            local default="${rest#*:}"

            printf '.TP\n'
            if [[ -n "$short" ]]; then
                printf '.BR \\-%s ", " \\-\\-%s " " \\fIvalue\\fR\n' "$short" "$long"
            else
                printf '.B \\-\\-%s " " \\fIvalue\\fR\n' "$long"
            fi
            printf '%s' "$desc"
            [[ -n "$default" ]] && printf ' (default: %s)' "$default"
            printf '\n'
        done

        # Built-in options
        printf '.TP\n.BR \\-h ", " \\-\\-help\nShow help message and exit.\n'
        printf '.TP\n.BR \\-V ", " \\-\\-version\nShow version information and exit.\n'
    fi

    # EXAMPLES section
    if [[ ${#_CLI_EXAMPLES[@]} -gt 0 ]]; then
        printf '.SH EXAMPLES\n'

        for example in "${_CLI_EXAMPLES[@]}"; do
            printf '.PP\n.RS\n.nf\n%s\n.fi\n.RE\n' "$example"
        done
    fi

    # VERSION section
    printf '.SH VERSION\n'
    printf '%s\n' "$version"
}

# =============================================================================
# SHELL COMPLETION GENERATION (v7.4 additions)
# =============================================================================

# @pre: CLI defined
# @post: bash completion script printed
# @idempotent: yes
# @returns: 0
#
# Generate bash completion script.
#
# Usage: cli::complete_bash > myapp.bash-completion
cli::complete_bash() {
    local script="${_CLI_NAME:-$(basename "$0")}"
    local script_safe="${script//-/_}"

    cat << EOF
# Bash completion for $script
# Generated by MAINFRAME cli.sh

_${script_safe}_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    prev="\${COMP_WORDS[COMP_CWORD-1]}"

EOF

    # Build options list
    local opts="--help --version"

    for spec in "${_CLI_FLAGS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        opts+=" --$long"
        [[ -n "$short" ]] && opts+=" -$short"
    done

    for spec in "${_CLI_OPTIONS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        opts+=" --$long"
        [[ -n "$short" ]] && opts+=" -$short"
    done

    printf '    opts="%s"\n\n' "$opts"

    # Subcommands
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
        local cmds=""
        for spec in "${_CLI_SUBCOMMANDS[@]}"; do
            local cmd="${spec%%:*}"
            cmds+="$cmd "
        done
        printf '    local commands="%s"\n' "$cmds"
        printf '\n    # Complete subcommands at position 1\n'
        printf '    if [[ $COMP_CWORD -eq 1 ]]; then\n'
        printf '        COMPREPLY=( $(compgen -W "$commands $opts" -- "$cur") )\n'
        printf '        return 0\n'
        printf '    fi\n\n'
    fi

    # Handle options with choices
    for name in "${!_CLI_CHOICES[@]}"; do
        local choices="${_CLI_CHOICES[$name]//|/ }"
        printf '    case "$prev" in\n'
        printf '        --%s)\n' "$name"
        printf '            COMPREPLY=( $(compgen -W "%s" -- "$cur") )\n' "$choices"
        printf '            return 0\n'
        printf '            ;;\n'
        printf '    esac\n\n'
    done

    cat << 'EOF'
    # Default to options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # Default to files
    COMPREPLY=( $(compgen -f -- "$cur") )
    return 0
}

EOF

    printf 'complete -F _%s_completions %s\n' "$script_safe" "$script"
}

# @pre: CLI defined
# @post: zsh completion script printed
# @idempotent: yes
# @returns: 0
#
# Generate zsh completion script.
#
# Usage: cli::complete_zsh > _myapp
cli::complete_zsh() {
    local script="${_CLI_NAME:-$(basename "$0")}"

    printf '#compdef %s\n\n' "$script"
    printf '# Zsh completion for %s\n' "$script"
    printf '# Generated by MAINFRAME cli.sh\n\n'

    printf '_arguments \\\n'

    # Flags
    for spec in "${_CLI_FLAGS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        local desc="${rest#*:}"

        desc="${desc//\'/\'\\\'\'}"
        desc="${desc//\"/\\\"}"

        if [[ -n "$short" ]]; then
            printf "    '(-%s --%-s)'{-%s,--%-s}'[%s]' \\\\\n" "$short" "$long" "$short" "$long" "$desc"
        else
            printf "    '--%-s[%s]' \\\\\n" "$long" "$desc"
        fi
    done

    # Options
    for spec in "${_CLI_OPTIONS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        rest="${rest#*:}"
        local desc="${rest%%:*}"

        desc="${desc//\'/\'\\\'\'}"
        desc="${desc//\"/\\\"}"

        local action=":value:"

        # Check for choices
        if [[ -n "${_CLI_CHOICES[$long]:-}" ]]; then
            local choices="${_CLI_CHOICES[$long]//|/ }"
            action=":choice:(${choices})"
        fi

        if [[ -n "$short" ]]; then
            printf "    '(-%s --%-s)'{-%s,--%-s}'[%s]%s' \\\\\n" "$short" "$long" "$short" "$long" "$desc" "$action"
        else
            printf "    '--%-s[%s]%s' \\\\\n" "$long" "$desc" "$action"
        fi
    done

    # Built-in
    printf "    '(-h --help)'{-h,--help}'[Show help]' \\\\\n"
    printf "    '(-V --version)'{-V,--version}'[Show version]' \\\\\n"

    # Positional arguments
    local pos_idx=1
    for spec in "${_CLI_POSITIONALS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        local desc="${rest%%:*}"
        rest="${rest#*:}"
        local required="${rest%%:*}"

        desc="${desc//\'/\'\\\'\'}"

        if [[ "$required" == "required" ]]; then
            printf "    '%d:%s:_files' \\\\\n" "$pos_idx" "$desc"
        else
            printf "    '%d::%s:_files' \\\\\n" "$pos_idx" "$desc"
        fi
        ((pos_idx++))
    done

    # Subcommands
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
        printf "    '1:command:->commands' \\\\\n"
        printf "    '*::arg:->args'\n\n"

        printf 'case "$state" in\n'
        printf '    commands)\n'
        printf '        local -a commands\n'
        printf '        commands=(\n'
        for spec in "${_CLI_SUBCOMMANDS[@]}"; do
            local cmd="${spec%%:*}"
            local rest="${spec#*:}"
            local desc="${rest%%:*}"
            desc="${desc//\'/\'\\\'\'}"
            printf "            '%s:%s'\n" "$cmd" "$desc"
        done
        printf '        )\n'
        printf '        _describe -t commands "command" commands\n'
        printf '        ;;\n'
        printf 'esac\n'
    else
        printf "    && return 0\n"
    fi
}

# @pre: CLI defined
# @post: fish completion script printed
# @idempotent: yes
# @returns: 0
#
# Generate fish completion script.
#
# Usage: cli::complete_fish > myapp.fish
cli::complete_fish() {
    local script="${_CLI_NAME:-$(basename "$0")}"

    printf '# Fish completion for %s\n' "$script"
    printf '# Generated by MAINFRAME cli.sh\n\n'

    # Disable file completion by default
    printf 'complete -c %s -f\n\n' "$script"

    # Flags
    for spec in "${_CLI_FLAGS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        local desc="${rest#*:}"

        printf 'complete -c %s' "$script"
        [[ -n "$short" ]] && printf ' -s %s' "$short"
        printf ' -l %s' "$long"
        [[ -n "$desc" ]] && printf ' -d "%s"' "$desc"
        printf '\n'
    done

    # Options
    for spec in "${_CLI_OPTIONS[@]}"; do
        local long="${spec%%:*}"
        local rest="${spec#*:}"
        local short="${rest%%:*}"
        rest="${rest#*:}"
        local desc="${rest%%:*}"

        printf 'complete -c %s' "$script"
        [[ -n "$short" ]] && printf ' -s %s' "$short"
        printf ' -l %s' "$long"
        printf ' -r'  # requires argument
        [[ -n "$desc" ]] && printf ' -d "%s"' "$desc"

        # Handle choices
        if [[ -n "${_CLI_CHOICES[$long]:-}" ]]; then
            local choices="${_CLI_CHOICES[$long]//|/ }"
            printf ' -a "%s"' "$choices"
        fi

        printf '\n'
    done

    # Built-in
    printf 'complete -c %s -s h -l help -d "Show help"\n' "$script"
    printf 'complete -c %s -s V -l version -d "Show version"\n' "$script"

    # Subcommands
    if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
        printf '\n# Subcommands\n'
        for spec in "${_CLI_SUBCOMMANDS[@]}"; do
            local cmd="${spec%%:*}"
            local rest="${spec#*:}"
            local desc="${rest%%:*}"

            printf 'complete -c %s -n "__fish_use_subcommand" -a %s' "$script" "$cmd"
            [[ -n "$desc" ]] && printf ' -d "%s"' "$desc"
            printf '\n'
        done
    fi
}

# =============================================================================
# STRUCTURED ERROR OUTPUT - USOP (v7.4 additions)
# =============================================================================

# JSON escape helper for USOP output
_cli_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# @pre: error occurred
# @post: JSON error emitted to stderr
# @returns: provided exit code
#
# Emit a structured USOP error.
#
# Usage: cli::usop_error "CLI_MISSING_ARG" "Missing required argument" "field"
cli::usop_error() {
    local code="$1"
    local msg="$2"
    local field="${3:-}"
    local suggestion="${4:-}"

    local escaped_msg escaped_field escaped_suggestion
    escaped_msg=$(_cli_json_escape "$msg")
    escaped_field=$(_cli_json_escape "$field")
    escaped_suggestion=$(_cli_json_escape "$suggestion")

    local json="{"
    json+="\"ok\":false"
    json+=",\"error\":{\"code\":\"$code\",\"msg\":\"$escaped_msg\""
    [[ -n "$field" ]] && json+=",\"field\":\"$escaped_field\""
    [[ -n "$suggestion" ]] && json+=",\"suggestion\":\"$escaped_suggestion\""
    json+="}}"

    printf '%s\n' "$json" >&2
}

# @pre: CLI parsed
# @post: JSON output with all parsed values
# @returns: 0
#
# Output parsed CLI values as JSON (for debugging or chaining).
#
# Usage: cli::to_json
cli::to_json() {
    local json="{"
    local first=true

    for key in "${!_CLI_VALUES[@]}"; do
        $first || json+=","
        first=false
        local value="${_CLI_VALUES[$key]}"
        local escaped_key escaped_value
        escaped_key=$(_cli_json_escape "$key")
        escaped_value=$(_cli_json_escape "$value")

        # Handle booleans
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            json+="\"$escaped_key\":$value"
        # Handle integers
        elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
            json+="\"$escaped_key\":$value"
        else
            json+="\"$escaped_key\":\"$escaped_value\""
        fi
    done

    json+="}"
    printf '%s\n' "$json"
}

# =============================================================================
# DISPATCH HELPER (v7.4 additions)
# =============================================================================

# @pre: subcommands registered, args parsed
# @post: appropriate subcommand function called
# @returns: subcommand exit code or 1 if not found
#
# Dispatch to the appropriate subcommand based on parsed state.
# Alternative to cli::run_subcommand with better error handling.
#
# Usage: cli::dispatch "$@"
cli::dispatch() {
    if [[ -z "$_CLI_SUBCOMMAND" ]]; then
        if [[ ${#_CLI_SUBCOMMANDS[@]} -gt 0 ]]; then
            cli::usop_error "CLI_NO_COMMAND" "No command specified" "" "Use --help to see available commands"
            return 1
        fi
        return 0
    fi

    for spec in "${_CLI_SUBCOMMANDS[@]}"; do
        local name="${spec%%:*}"
        local rest="${spec#*:}"
        rest="${rest#*:}"
        local handler="${rest%%:*}"

        if [[ "$name" == "$_CLI_SUBCOMMAND" ]]; then
            if [[ -n "$handler" ]]; then
                if declare -F "$handler" &>/dev/null; then
                    "$handler" "$@"
                    return $?
                else
                    cli::usop_error "CLI_HANDLER_NOT_FOUND" "Handler function not found: $handler" "$name"
                    return 1
                fi
            else
                # No handler defined, return success (command recognized but no-op)
                return 0
            fi
        fi
    done

    cli::usop_error "CLI_UNKNOWN_COMMAND" "Unknown command: $_CLI_SUBCOMMAND" "" "Use --help to see available commands"
    return 1
}

# =============================================================================
# SPEC-BASED PARSING (v7.4 additions)
# =============================================================================

# @pre: spec is valid format string
# @post: arguments parsed according to spec
# @idempotent: no
# @returns: 0 on success
#
# Parse arguments using a compact spec format.
# Spec format: "flag:f,option:o:default,positional:required"
#
# Usage: cli::parse_spec "verbose:v,output:o:/tmp,input:required" "$@"
cli::parse_spec() {
    local spec="$1"
    shift

    # Reset state
    cli::reset

    # Parse spec
    local IFS=','
    read -ra entries <<< "$spec"

    for entry in "${entries[@]}"; do
        local IFS=':'
        read -ra parts <<< "$entry"
        local name="${parts[0]}"

        case ${#parts[@]} in
            1)
                # Simple flag
                cli::flag "$name" "" ""
                ;;
            2)
                # name:short (flag) or name:required (positional)
                if [[ "${parts[1]}" == "required" || "${parts[1]}" == "optional" ]]; then
                    cli::positional "$name" "" "${parts[1]}"
                else
                    cli::flag "$name" "${parts[1]}" ""
                fi
                ;;
            3|*)
                # name:short:default (option)
                cli::option "$name" "${parts[1]}" "" "${parts[2]}"
                ;;
        esac
    done

    # Parse arguments
    cli::parse "$@"
}

# =============================================================================
# LEGACY COMPATIBILITY ALIASES (v7.4 additions)
# =============================================================================
# These functions provide backward compatibility with the specification API.

# Alias: cli_parse -> cli::parse
cli_parse() { cli::parse "$@"; }

# Alias: cli_arg -> cli::option
cli_arg() {
    local name="$1"
    local type="${2:-string}"
    local default="${3:-}"
    local description="${4:-}"
    cli::option "$name" "" "$description" "$default"
}

# Alias: cli_flag -> cli::flag
cli_flag() { cli::flag "$@"; }

# Alias: cli_option -> cli::option
cli_option() {
    local name="$1"
    local short="${2:-}"
    local type="${3:-string}"
    local default="${4:-}"
    local description="${5:-}"
    cli::option "$name" "$short" "$description" "$default"
}

# Alias: cli_positional -> cli::positional
cli_positional() {
    local name="$1"
    local required="${2:-false}"
    local description="${3:-}"
    local default="${4:-}"
    [[ "$required" == "true" ]] && required="required" || required="optional"
    cli::positional "$name" "$description" "$required"
}

# Alias: cli_rest_args -> cli::remaining
cli_rest_args() {
    printf '%s\n' "${_CLI_REMAINING[@]}"
}

# Alias: cli_require -> cli::validate_type with nonempty
cli_require() {
    local arg="$1"
    local message="${2:-$arg is required}"
    cli::validate_type "$arg" "nonempty"
}

# Alias: cli_validate -> cli::validate_type
cli_validate() {
    local arg="$1"
    local validator="$2"
    cli::validate_type "$arg" "$validator"
}

# Alias: cli_choices -> cli::choices
cli_choices() { cli::choices "$@"; }

# Alias: cli_range -> cli::range
cli_range() { cli::range "$@"; }

# Alias: cli_usage -> cli::description
cli_usage() { cli::description "$1"; }

# Alias: cli_example -> cli::example
cli_example() { cli::example "$1"; }

# Alias: cli_help_generate -> cli::help
cli_help_generate() { cli::help; }

# Alias: cli_version -> cli::version
cli_version() {
    if [[ $# -gt 0 ]]; then
        cli::version "$1"
    else
        printf '%s version %s\n' "${_CLI_NAME:-$(basename "$0")}" "${_CLI_VERSION:-unknown}"
    fi
}

# Alias: cli_man_generate -> cli::man
cli_man_generate() { cli::man; }

# Alias: cli_complete_bash -> cli::complete_bash
cli_complete_bash() { cli::complete_bash; }

# Alias: cli_complete_zsh -> cli::complete_zsh
cli_complete_zsh() { cli::complete_zsh; }

# Alias: cli_complete_fish -> cli::complete_fish
cli_complete_fish() { cli::complete_fish; }

# Alias: cli_subcommand -> cli::subcommand
cli_subcommand() { cli::subcommand "$@"; }

# Alias: cli_dispatch -> cli::dispatch
cli_dispatch() { cli::dispatch "$@"; }

# Alias: cli_get -> cli::get
cli_get() { cli::get "$@"; }

# Alias: cli_get_bool -> cli::is
cli_get_bool() { cli::is "$@"; }

# Alias: cli_get_int -> cli::get as integer
cli_get_int() {
    local name="$1"
    local default="${2:-0}"
    local value
    value=$(cli::get "$name" "$default")
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%d' "$value"
    else
        printf '%d' "$default"
    fi
}

# Alias: cli_has -> cli::has
cli_has() { cli::has "$@"; }

# Alias: cli_reset -> cli::reset
cli_reset() {
    cli::reset
    _CLI_CHOICES=()
    _CLI_RANGES=()
}

# Alias: cli_init -> cli::init
cli_init() { cli::init "$@"; }

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_CLI_EXPORTS=(
    # Namespace API (primary)
    cli::name
    cli::version
    cli::description
    cli::flag
    cli::option
    cli::positional
    cli::example
    cli::subcommand
    cli::get_subcommand
    cli::is_subcommand
    cli::parse
    cli::get
    cli::is
    cli::get_array
    cli::remaining
    cli::has
    cli::validate_type
    cli::validate_required
    cli::validate
    cli::check
    cli::choices
    cli::range
    cli::validate_choices
    cli::validate_range
    cli::help
    cli::man
    cli::complete_bash
    cli::complete_zsh
    cli::complete_fish
    cli::error
    cli::warn
    cli::usop_error
    cli::to_json
    cli::reset
    cli::init
    cli::common_options
    cli::run_subcommand
    cli::dispatch
    cli::parse_spec
    cli::debug
    # Legacy/Compatibility API
    cli_parse
    cli_arg
    cli_flag
    cli_option
    cli_positional
    cli_rest_args
    cli_require
    cli_validate
    cli_choices
    cli_range
    cli_usage
    cli_example
    cli_help_generate
    cli_version
    cli_man_generate
    cli_complete_bash
    cli_complete_zsh
    cli_complete_fish
    cli_subcommand
    cli_dispatch
    cli_get
    cli_get_bool
    cli_get_int
    cli_has
    cli_reset
    cli_init
)

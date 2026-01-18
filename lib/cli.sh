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
    # shellcheck disable=SC2178,SC2034
    local -n result_ref="$1"
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

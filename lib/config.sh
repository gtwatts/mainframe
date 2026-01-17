#!/usr/bin/env bash
# =============================================================================
# basher/lib/config.sh - Configuration management for Basher toolkit
# =============================================================================

[[ -n "${_BASHER_CONFIG_LOADED:-}" ]] && return 0
readonly _BASHER_CONFIG_LOADED=1

# Source common library if not already loaded
[[ -z "${_BASHER_COMMON_LOADED:-}" ]] && source "${BASH_SOURCE%/*}/common.sh"

# =============================================================================
# CONFIGURATION PATHS
# =============================================================================

# Default configuration locations (in order of precedence)
readonly BASHER_CONFIG_PATHS=(
    "${BASHER_CONFIG:-}"                           # 1. Explicit env var
    "./.basher.conf"                               # 2. Current directory
    "${XDG_CONFIG_HOME:-$HOME/.config}/basher/basher.conf"  # 3. XDG config
    "$HOME/.basherrc"                              # 4. Home directory
    "/etc/basher/basher.conf"                      # 5. System-wide
)

# Active configuration file
BASHER_CONFIG_FILE=""

# Configuration cache (associative array)
declare -gA _BASHER_CONFIG_CACHE=()

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Find and load the first available configuration file
config_load() {
    local config_file="${1:-}"

    # If specific file provided, use it
    if [[ -n "$config_file" ]]; then
        if [[ -f "$config_file" && -r "$config_file" ]]; then
            BASHER_CONFIG_FILE="$config_file"
        else
            log_warn "Configuration file not readable: $config_file"
            return 1
        fi
    else
        # Search through default paths
        for path in "${BASHER_CONFIG_PATHS[@]}"; do
            [[ -z "$path" ]] && continue
            if [[ -f "$path" && -r "$path" ]]; then
                BASHER_CONFIG_FILE="$path"
                break
            fi
        done
    fi

    if [[ -z "$BASHER_CONFIG_FILE" ]]; then
        log_debug "No configuration file found, using defaults"
        return 0
    fi

    log_debug "Loading configuration from: $BASHER_CONFIG_FILE"

    # Parse the configuration file
    _config_parse "$BASHER_CONFIG_FILE"
}

# Parse configuration file (INI-style format)
_config_parse() {
    local file="$1"
    local current_section=""
    local line_num=0
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Remove leading/trailing whitespace
        line=$(trim "$line")

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[#\;] ]] && continue

        # Section header [section]
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key = value
        if [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Store with section prefix
            if [[ -n "$current_section" ]]; then
                _BASHER_CONFIG_CACHE["${current_section}.${key}"]="$value"
            else
                _BASHER_CONFIG_CACHE["$key"]="$value"
            fi
        else
            log_warn "Invalid configuration at $file:$line_num: $line"
        fi
    done < "$file"

    log_debug "Loaded ${#_BASHER_CONFIG_CACHE[@]} configuration values"
}

# =============================================================================
# CONFIGURATION ACCESS
# =============================================================================

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"

    # Check environment variable first (uppercase, with BASHER_ prefix)
    local env_key="BASHER_${key^^}"
    env_key="${env_key//./_}"  # Replace dots with underscores

    if [[ -n "${!env_key:-}" ]]; then
        printf '%s' "${!env_key}"
        return 0
    fi

    # Check cache
    if [[ -n "${_BASHER_CONFIG_CACHE[$key]:-}" ]]; then
        printf '%s' "${_BASHER_CONFIG_CACHE[$key]}"
        return 0
    fi

    # Return default
    printf '%s' "$default"
}

# Get configuration value as integer
config_get_int() {
    local key="$1"
    local default="${2:-0}"
    local value

    value=$(config_get "$key" "$default")

    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%d' "$value"
    else
        log_warn "Configuration '$key' is not a valid integer: $value"
        printf '%d' "$default"
    fi
}

# Get configuration value as boolean
config_get_bool() {
    local key="$1"
    local default="${2:-false}"
    local value

    value=$(config_get "$key" "$default")
    value=$(lowercase "$value")

    case "$value" in
        true|yes|on|1)  return 0 ;;
        false|no|off|0) return 1 ;;
        *)
            log_warn "Configuration '$key' is not a valid boolean: $value"
            [[ "$default" =~ ^(true|yes|on|1)$ ]]
            ;;
    esac
}

# Get configuration value as array (comma-separated)
config_get_array() {
    local key="$1"
    local default="${2:-}"
    local value

    value=$(config_get "$key" "$default")

    # Split by comma, trim each element
    local IFS=','
    local -a result=()
    for item in $value; do
        result+=("$(trim "$item")")
    done

    printf '%s\n' "${result[@]}"
}

# Set configuration value (runtime only)
config_set() {
    local key="$1"
    local value="$2"

    _BASHER_CONFIG_CACHE["$key"]="$value"
}

# Check if configuration key exists
config_has() {
    local key="$1"

    [[ -n "${_BASHER_CONFIG_CACHE[$key]:-}" ]]
}

# List all configuration keys
config_keys() {
    local pattern="${1:-*}"

    for key in "${!_BASHER_CONFIG_CACHE[@]}"; do
        if [[ "$key" == $pattern ]]; then
            printf '%s\n' "$key"
        fi
    done | sort
}

# Dump all configuration values
config_dump() {
    local show_source="${1:-false}"

    for key in $(config_keys); do
        if [[ "$show_source" == "true" ]]; then
            printf '%s = %s (from: %s)\n' "$key" "${_BASHER_CONFIG_CACHE[$key]}" "$BASHER_CONFIG_FILE"
        else
            printf '%s = %s\n' "$key" "${_BASHER_CONFIG_CACHE[$key]}"
        fi
    done
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Require a configuration value to be set
config_require() {
    local key="$1"
    local description="${2:-$key}"
    local value

    value=$(config_get "$key")

    if [[ -z "$value" ]]; then
        die "$EXIT_CONFIG" "Required configuration missing: $description ($key)"
    fi
}

# Validate configuration against schema
config_validate() {
    local -n schema_ref=$1
    local errors=0

    for key in "${!schema_ref[@]}"; do
        local spec="${schema_ref[$key]}"
        local value
        value=$(config_get "$key")

        # Parse spec: type:required:default
        local IFS=':'
        read -ra parts <<< "$spec"
        local type="${parts[0]:-string}"
        local required="${parts[1]:-false}"
        local default="${parts[2]:-}"

        # Check required
        if [[ "$required" == "true" && -z "$value" ]]; then
            log_error "Required configuration missing: $key"
            ((errors++))
            continue
        fi

        # Set default if not provided
        [[ -z "$value" ]] && value="$default"

        # Type validation
        case "$type" in
            int|integer)
                if [[ -n "$value" && ! "$value" =~ ^-?[0-9]+$ ]]; then
                    log_error "Configuration '$key' must be an integer: $value"
                    ((errors++))
                fi
                ;;
            bool|boolean)
                if [[ -n "$value" && ! "$value" =~ ^(true|false|yes|no|on|off|1|0)$ ]]; then
                    log_error "Configuration '$key' must be a boolean: $value"
                    ((errors++))
                fi
                ;;
            path)
                if [[ -n "$value" && ! -e "$value" ]]; then
                    log_error "Configuration '$key' path does not exist: $value"
                    ((errors++))
                fi
                ;;
            url)
                if [[ -n "$value" && ! "$value" =~ ^https?:// ]]; then
                    log_error "Configuration '$key' must be a valid URL: $value"
                    ((errors++))
                fi
                ;;
            email)
                if [[ -n "$value" ]] && ! is_valid_email "$value"; then
                    log_error "Configuration '$key' must be a valid email: $value"
                    ((errors++))
                fi
                ;;
        esac
    done

    return $errors
}

# =============================================================================
# CONFIGURATION FILE WRITING
# =============================================================================

# Write configuration to file
config_save() {
    local file="${1:-$BASHER_CONFIG_FILE}"

    if [[ -z "$file" ]]; then
        log_error "No configuration file specified"
        return 1
    fi

    # Create directory if needed
    local dir
    dir=$(dirname "$file")
    mkdir -p "$dir"

    # Write configuration
    {
        printf "# Basher configuration file\n"
        printf "# Generated: %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"

        local current_section=""

        for key in $(config_keys); do
            # Check for section
            if [[ "$key" == *.* ]]; then
                local section="${key%%.*}"
                local subkey="${key#*.}"

                if [[ "$section" != "$current_section" ]]; then
                    [[ -n "$current_section" ]] && printf "\n"
                    printf "[%s]\n" "$section"
                    current_section="$section"
                fi

                printf "%s = %s\n" "$subkey" "${_BASHER_CONFIG_CACHE[$key]}"
            else
                if [[ -n "$current_section" ]]; then
                    printf "\n"
                    current_section=""
                fi
                printf "%s = %s\n" "$key" "${_BASHER_CONFIG_CACHE[$key]}"
            fi
        done
    } > "$file"

    log_info "Configuration saved to: $file"
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Auto-load configuration on source (can be disabled)
if [[ "${BASHER_CONFIG_AUTOLOAD:-true}" == "true" ]]; then
    config_load
fi

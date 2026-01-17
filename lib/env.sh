#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/env.sh - Environment Variable Management
# =============================================================================
# Description: Environment variable handling, PATH management, and dotenv support
# Council Priority: #3 - "Environment variables are ubiquitous in Bash.
#                         Every script deals with environment handling."
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ENV_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ENV_LOADED=1

# =============================================================================
# SHELL DETECTION
# =============================================================================

# Detect current shell type
# Usage: env_detect_shell
# Returns: bash, zsh, fish, sh, dash, ksh
env_detect_shell() {
    local shell_path shell_name

    # Try to get shell from $SHELL or the current process
    if [[ -n "${BASH_VERSION:-}" ]]; then
        printf '%s\n' "bash"
        return 0
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        printf '%s\n' "zsh"
        return 0
    elif [[ -n "${FISH_VERSION:-}" ]]; then
        printf '%s\n' "fish"
        return 0
    elif [[ -n "${KSH_VERSION:-}" ]]; then
        printf '%s\n' "ksh"
        return 0
    fi

    # Fallback to checking $SHELL
    shell_path="${SHELL:-/bin/sh}"
    shell_name="${shell_path##*/}"

    case "$shell_name" in
        bash|zsh|fish|ksh|dash|sh)
            printf '%s\n' "$shell_name"
            ;;
        *)
            # Default to sh if unknown
            printf '%s\n' "sh"
            ;;
    esac
}

# Get config file path for a shell
# Usage: env_config_file [shell]
# Returns: Path to .bashrc, .zshrc, etc.
env_config_file() {
    local shell="${1:-$(env_detect_shell)}"
    local home="${HOME:-$(eval echo ~)}"

    case "$shell" in
        bash)
            # Prefer .bashrc, but check for .bash_profile on macOS
            if [[ -f "${home}/.bashrc" ]]; then
                printf '%s\n' "${home}/.bashrc"
            elif [[ -f "${home}/.bash_profile" ]]; then
                printf '%s\n' "${home}/.bash_profile"
            else
                # Default to .bashrc
                printf '%s\n' "${home}/.bashrc"
            fi
            ;;
        zsh)
            printf '%s\n' "${home}/.zshrc"
            ;;
        fish)
            printf '%s\n' "${home}/.config/fish/config.fish"
            ;;
        ksh)
            printf '%s\n' "${home}/.kshrc"
            ;;
        dash|sh)
            printf '%s\n' "${home}/.profile"
            ;;
        *)
            printf '%s\n' "${home}/.profile"
            ;;
    esac
}

# =============================================================================
# VARIABLE MANAGEMENT
# =============================================================================

# Set environment variable (current session only)
# Usage: env_set "VAR_NAME" "value"
env_set() {
    local name="$1"
    local value="$2"

    # Validate variable name
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'env_set: invalid variable name: %s\n' "$name" >&2
        return 1
    fi

    export "$name=$value"
}

# Persist environment variable to shell config
# Usage: env_persist "VAR_NAME" "value" [shell]
env_persist() {
    local name="$1"
    local value="$2"
    local shell="${3:-$(env_detect_shell)}"
    local config_file export_line

    # Validate variable name
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'env_persist: invalid variable name: %s\n' "$name" >&2
        return 1
    fi

    config_file=$(env_config_file "$shell")

    # First, set it in current session
    export "$name=$value"

    # Build export line based on shell type
    case "$shell" in
        fish)
            export_line="set -gx ${name} \"${value}\""
            ;;
        *)
            # Escape value for shell
            local escaped_value
            escaped_value="${value//\\/\\\\}"
            escaped_value="${escaped_value//\"/\\\"}"
            escaped_value="${escaped_value//\$/\\\$}"
            escaped_value="${escaped_value//\`/\\\`}"
            export_line="export ${name}=\"${escaped_value}\""
            ;;
    esac

    # Ensure config file exists
    if [[ ! -f "$config_file" ]]; then
        local config_dir
        config_dir=$(dirname "$config_file")
        [[ ! -d "$config_dir" ]] && mkdir -p "$config_dir"
        touch "$config_file"
    fi

    # Remove existing definition if present
    env_remove_persist "$name" "$shell" 2>/dev/null || true

    # Append new definition
    printf '\n# Added by MAINFRAME env_persist\n%s\n' "$export_line" >> "$config_file"
}

# Get environment variable with optional default
# Usage: env_get "VAR_NAME" [default]
# Returns: Variable value or default
env_get() {
    local name="$1"
    local default="${2:-}"

    # Use indirect expansion to get the variable value
    local value="${!name:-}"

    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    elif [[ -n "$default" ]]; then
        printf '%s\n' "$default"
    fi
}

# Unset environment variable (current session only)
# Usage: env_unset "VAR_NAME"
env_unset() {
    local name="$1"

    # Validate variable name
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'env_unset: invalid variable name: %s\n' "$name" >&2
        return 1
    fi

    unset "$name"
}

# Remove persisted variable from config file
# Usage: env_remove_persist "VAR_NAME" [shell]
env_remove_persist() {
    local name="$1"
    local shell="${2:-$(env_detect_shell)}"
    local config_file temp_file

    # Validate variable name
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'env_remove_persist: invalid variable name: %s\n' "$name" >&2
        return 1
    fi

    config_file=$(env_config_file "$shell")

    [[ ! -f "$config_file" ]] && return 0

    # Create temp file
    temp_file=$(mktemp)

    # Build pattern based on shell type
    local pattern
    case "$shell" in
        fish)
            pattern="^set -gx ${name} "
            ;;
        *)
            pattern="^export ${name}="
            ;;
    esac

    # Remove matching lines and the MAINFRAME comment before them
    local prev_line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            # Skip this line and check if previous was MAINFRAME comment
            if [[ "$prev_line" == "# Added by MAINFRAME env_persist" ]]; then
                # Remove the comment too (already not written)
                :
            fi
            prev_line=""
            continue
        fi

        # Write previous line if not a MAINFRAME comment followed by our export
        if [[ -n "$prev_line" ]]; then
            printf '%s\n' "$prev_line" >> "$temp_file"
        fi
        prev_line="$line"
    done < "$config_file"

    # Write last line
    if [[ -n "$prev_line" ]]; then
        printf '%s\n' "$prev_line" >> "$temp_file"
    fi

    # Replace original file
    mv "$temp_file" "$config_file"
}

# =============================================================================
# PATH MANAGEMENT
# =============================================================================

# Prepend directory to PATH (if not already present)
# Usage: env_path_prepend "/new/path"
env_path_prepend() {
    local new_path="$1"

    # Don't add if already in PATH
    if env_path_has "$new_path"; then
        return 0
    fi

    # Don't add if directory doesn't exist (optional warning)
    if [[ ! -d "$new_path" ]]; then
        printf 'env_path_prepend: directory does not exist: %s\n' "$new_path" >&2
        return 1
    fi

    export PATH="${new_path}:${PATH}"
}

# Append directory to PATH (if not already present)
# Usage: env_path_append "/new/path"
env_path_append() {
    local new_path="$1"

    # Don't add if already in PATH
    if env_path_has "$new_path"; then
        return 0
    fi

    # Don't add if directory doesn't exist
    if [[ ! -d "$new_path" ]]; then
        printf 'env_path_append: directory does not exist: %s\n' "$new_path" >&2
        return 1
    fi

    export PATH="${PATH}:${new_path}"
}

# Remove directory from PATH
# Usage: env_path_remove "/path/to/remove"
env_path_remove() {
    local remove_path="$1"
    local new_path=""
    local IFS=':'

    for path_entry in $PATH; do
        # Skip the path we want to remove (exact match)
        [[ "$path_entry" == "$remove_path" ]] && continue

        if [[ -z "$new_path" ]]; then
            new_path="$path_entry"
        else
            new_path="${new_path}:${path_entry}"
        fi
    done

    export PATH="$new_path"
}

# List PATH entries (one per line)
# Usage: env_path_list
env_path_list() {
    local IFS=':'

    for path_entry in $PATH; do
        [[ -n "$path_entry" ]] && printf '%s\n' "$path_entry"
    done
}

# Check if path is in PATH
# Usage: env_path_has "/usr/local/bin"
# Returns: 0 if present, 1 if not
env_path_has() {
    local check_path="$1"
    local IFS=':'

    for path_entry in $PATH; do
        [[ "$path_entry" == "$check_path" ]] && return 0
    done

    return 1
}

# Persist PATH prepend to shell config
# Usage: env_path_persist_prepend "/new/path" [shell]
env_path_persist_prepend() {
    local new_path="$1"
    local shell="${2:-$(env_detect_shell)}"
    local config_file export_line

    # First prepend to current PATH
    env_path_prepend "$new_path" || return 1

    config_file=$(env_config_file "$shell")

    # Build export line based on shell type
    case "$shell" in
        fish)
            export_line="set -gx PATH \"${new_path}\" \$PATH"
            ;;
        *)
            export_line="export PATH=\"${new_path}:\${PATH}\""
            ;;
    esac

    # Ensure config file exists
    if [[ ! -f "$config_file" ]]; then
        local config_dir
        config_dir=$(dirname "$config_file")
        [[ ! -d "$config_dir" ]] && mkdir -p "$config_dir"
        touch "$config_file"
    fi

    # Check if already present
    if grep -qF "$new_path" "$config_file" 2>/dev/null; then
        return 0
    fi

    # Append new definition
    printf '\n# Added by MAINFRAME env_path_persist_prepend\n%s\n' "$export_line" >> "$config_file"
}

# Persist PATH append to shell config
# Usage: env_path_persist_append "/new/path" [shell]
env_path_persist_append() {
    local new_path="$1"
    local shell="${2:-$(env_detect_shell)}"
    local config_file export_line

    # First append to current PATH
    env_path_append "$new_path" || return 1

    config_file=$(env_config_file "$shell")

    # Build export line based on shell type
    case "$shell" in
        fish)
            export_line="set -gx PATH \$PATH \"${new_path}\""
            ;;
        *)
            export_line="export PATH=\"\${PATH}:${new_path}\""
            ;;
    esac

    # Ensure config file exists
    if [[ ! -f "$config_file" ]]; then
        local config_dir
        config_dir=$(dirname "$config_file")
        [[ ! -d "$config_dir" ]] && mkdir -p "$config_dir"
        touch "$config_file"
    fi

    # Check if already present
    if grep -qF "$new_path" "$config_file" 2>/dev/null; then
        return 0
    fi

    # Append new definition
    printf '\n# Added by MAINFRAME env_path_persist_append\n%s\n' "$export_line" >> "$config_file"
}

# Clean PATH by removing duplicates and non-existent directories
# Usage: env_path_clean
env_path_clean() {
    local -a seen=()
    local new_path=""
    local IFS=':'

    for path_entry in $PATH; do
        # Skip empty entries
        [[ -z "$path_entry" ]] && continue

        # Skip if already seen
        local found=0
        for s in "${seen[@]}"; do
            [[ "$s" == "$path_entry" ]] && { found=1; break; }
        done
        [[ $found -eq 1 ]] && continue

        # Skip if directory doesn't exist
        [[ ! -d "$path_entry" ]] && continue

        # Add to new PATH and seen list
        seen+=("$path_entry")
        if [[ -z "$new_path" ]]; then
            new_path="$path_entry"
        else
            new_path="${new_path}:${path_entry}"
        fi
    done

    export PATH="$new_path"
}

# =============================================================================
# DOTENV SUPPORT
# =============================================================================

# Load .env file into environment
# Usage: env_load_dotenv [file]
env_load_dotenv() {
    local file="${1:-.env}"

    [[ ! -f "$file" ]] && {
        printf 'env_load_dotenv: file not found: %s\n' "$file" >&2
        return 1
    }

    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Parse key=value (handle quoted values)
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Handle escape sequences in double-quoted values
            value="${value//\\n/$'\n'}"
            value="${value//\\t/$'\t'}"
            value="${value//\\\"/\"}"

            # Export the variable
            export "$key=$value"
        fi
    done < "$file"
}

# Save variables to .env file
# Usage: env_save_dotenv "file" "VAR1" "VAR2" ...
env_save_dotenv() {
    local file="$1"
    shift

    [[ $# -eq 0 ]] && {
        printf 'env_save_dotenv: no variables specified\n' >&2
        return 1
    }

    # Ensure parent directory exists
    local dir
    dir=$(dirname "$file")
    [[ ! -d "$dir" ]] && mkdir -p "$dir"

    # Write header
    printf '# Generated by MAINFRAME env_save_dotenv\n' > "$file"
    printf '# %s\n\n' "$(date)" >> "$file"

    local var_name value

    for var_name in "$@"; do
        # Validate variable name
        if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf 'env_save_dotenv: invalid variable name: %s\n' "$var_name" >&2
            continue
        fi

        # Get value using indirect expansion
        value="${!var_name:-}"

        # Quote the value if it contains special characters
        if [[ "$value" =~ [[:space:]\"\'\$\`\\] ]] || [[ -z "$value" ]]; then
            # Escape special characters for double quotes
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            value="${value//$'\t'/\\t}"
            printf '%s="%s"\n' "$var_name" "$value" >> "$file"
        else
            printf '%s=%s\n' "$var_name" "$value" >> "$file"
        fi
    done
}

# =============================================================================
# VALIDATION
# =============================================================================

# Check if variable is set (may be empty)
# Usage: env_is_set "VAR_NAME"
# Returns: 0 if set, 1 if not
env_is_set() {
    local name="$1"

    # Use indirect expansion to check if variable is set
    [[ -n "${!name+x}" ]]
}

# Check if variable is set and non-empty
# Usage: env_is_nonempty "VAR_NAME"
# Returns: 0 if set and non-empty, 1 otherwise
env_is_nonempty() {
    local name="$1"

    [[ -n "${!name:-}" ]]
}

# Require variable to be set or error
# Usage: env_require "VAR_NAME" [message]
env_require() {
    local name="$1"
    local message="${2:-Required environment variable '$name' is not set}"

    if ! env_is_nonempty "$name"; then
        printf '%s\n' "$message" >&2
        return 1
    fi
}

# Require multiple variables
# Usage: env_require_all "VAR1" "VAR2" "VAR3"
env_require_all() {
    local missing=()

    for var in "$@"; do
        if ! env_is_nonempty "$var"; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'Missing required environment variables: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# =============================================================================
# UTILITIES
# =============================================================================

# List exported variables matching pattern
# Usage: env_list [pattern]
env_list() {
    local pattern="${1:-}"

    if [[ -n "$pattern" ]]; then
        env | grep -E "^${pattern}" | sort
    else
        env | sort
    fi
}

# Export variables from a file (key=value format)
# Usage: env_export_from "file"
env_export_from() {
    local file="$1"

    [[ ! -f "$file" ]] && {
        printf 'env_export_from: file not found: %s\n' "$file" >&2
        return 1
    }

    # Use dotenv loader
    env_load_dotenv "$file"
}

# Run command with modified environment
# Usage: env_with "VAR=value" command args...
env_with() {
    local -a env_vars=()
    local cmd_start=0

    # Parse environment variables until we hit the command
    for ((i=1; i<=$#; i++)); do
        local arg="${!i}"
        if [[ "$arg" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            env_vars+=("$arg")
        else
            cmd_start=$i
            break
        fi
    done

    [[ $cmd_start -eq 0 ]] && {
        printf 'env_with: no command specified\n' >&2
        return 1
    }

    # Build command array
    local -a cmd=("${@:$cmd_start}")

    # Run with environment
    env "${env_vars[@]}" "${cmd[@]}"
}

# Copy environment variable to another name
# Usage: env_copy "SOURCE_VAR" "DEST_VAR"
env_copy() {
    local source="$1"
    local dest="$2"

    if ! env_is_set "$source"; then
        printf 'env_copy: source variable not set: %s\n' "$source" >&2
        return 1
    fi

    export "$dest=${!source}"
}

# Swap two environment variables
# Usage: env_swap "VAR1" "VAR2"
env_swap() {
    local var1="$1"
    local var2="$2"

    local temp="${!var1:-}"
    export "$var1=${!var2:-}"
    export "$var2=$temp"
}

# Get variable with type coercion
# Usage: env_get_int "VAR_NAME" [default]
env_get_int() {
    local name="$1"
    local default="${2:-0}"
    local value="${!name:-$default}"

    # Validate integer
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%d\n' "$value"
    else
        printf '%d\n' "$default"
    fi
}

# Get boolean environment variable
# Usage: env_get_bool "VAR_NAME" [default]
# Returns: 0 for truthy values, 1 for falsy
env_get_bool() {
    local name="$1"
    local default="${2:-false}"
    local value="${!name:-$default}"

    # Lowercase for comparison
    value="${value,,}"

    case "$value" in
        true|yes|1|on|y)
            return 0
            ;;
        false|no|0|off|n|"")
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get array from colon-separated variable
# Usage: env_get_array "VAR_NAME" array_name
env_get_array() {
    local name="$1"
    local -n result_array="$2"
    local value="${!name:-}"

    result_array=()
    [[ -z "$value" ]] && return 0

    local IFS=':'
    read -ra result_array <<< "$value"
}

# Set variable from array (colon-separated)
# Usage: env_set_array "VAR_NAME" "${array[@]}"
env_set_array() {
    local name="$1"
    shift

    local IFS=':'
    export "$name=$*"
}

# Print environment variable for debugging
# Usage: env_debug "VAR_NAME"
env_debug() {
    local name="$1"

    if env_is_set "$name"; then
        if env_is_nonempty "$name"; then
            printf '%s=%s\n' "$name" "${!name}"
        else
            printf '%s= (empty)\n' "$name"
        fi
    else
        printf '%s (not set)\n' "$name"
    fi
}

# Get environment diff (compare current to file)
# Usage: env_diff "file.env"
env_diff() {
    local file="$1"

    [[ ! -f "$file" ]] && {
        printf 'env_diff: file not found: %s\n' "$file" >&2
        return 1
    }

    local line key file_value current_value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            file_value="${BASH_REMATCH[2]}"

            # Remove quotes
            if [[ "$file_value" =~ ^\"(.*)\"$ ]]; then
                file_value="${BASH_REMATCH[1]}"
            elif [[ "$file_value" =~ ^\'(.*)\'$ ]]; then
                file_value="${BASH_REMATCH[1]}"
            fi

            current_value="${!key:-}"

            if [[ "$current_value" != "$file_value" ]]; then
                if [[ -z "${!key+x}" ]]; then
                    printf '+ %s=%s\n' "$key" "$file_value"
                else
                    printf '~ %s: %s -> %s\n' "$key" "$current_value" "$file_value"
                fi
            fi
        fi
    done < "$file"
}

# =============================================================================
# SPECIAL ENVIRONMENT HANDLING
# =============================================================================

# Expand environment variables in a string
# Usage: env_expand "string with $VAR"
env_expand() {
    local str="$1"
    eval "printf '%s\\n' \"$str\""
}

# Get shell environment summary
# Usage: env_summary
env_summary() {
    local shell user home

    shell=$(env_detect_shell)
    user="${USER:-$(whoami)}"
    home="${HOME:-$(eval echo ~)}"

    printf 'Shell: %s\n' "$shell"
    printf 'User: %s\n' "$user"
    printf 'Home: %s\n' "$home"
    printf 'Config: %s\n' "$(env_config_file "$shell")"
    printf 'PATH entries: %d\n' "$(env_path_list | wc -l)"
    printf 'Environment variables: %d\n' "$(env | wc -l)"
}

# Backup environment to file
# Usage: env_backup "backup.env"
env_backup() {
    local file="$1"

    env | sort > "$file"
    printf 'Environment backed up to: %s\n' "$file" >&2
}

# Restore environment from file
# Usage: env_restore "backup.env"
env_restore() {
    local file="$1"

    [[ ! -f "$file" ]] && {
        printf 'env_restore: file not found: %s\n' "$file" >&2
        return 1
    }

    env_load_dotenv "$file"
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/secrets.sh - Runtime Secrets Management
# =============================================================================
# Description: Secure in-memory credential handling with automatic redaction.
#              Secrets are stored only in bash associative array (memory only).
#              Never written to disk. Pattern-based detection for accidental
#              exposure. Complements the encrypted file-based secrets library.
# Version: 2.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SECRETS_RUNTIME_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SECRETS_RUNTIME_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# In-memory secret storage (never persisted)
declare -gA _SECRETS_STORE=()

# Secret metadata (creation time, etc.)
declare -gA _SECRETS_META=()

# Auto-wrap tracking
# Key: function name, Value: original function name

# Redaction pattern cache
declare -ga _SECRETS_PATTERNS=()

# Security configuration
SECRETS_MAX_LENGTH="${SECRETS_MAX_LENGTH:-8192}"
SECRETS_PATTERN_ESCAPE="${SECRETS_PATTERN_ESCAPE:-1}"

# =============================================================================
# LOGGING HELPERS
# =============================================================================

_secrets_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[secrets] $*"
    else
        printf '[%s] [secrets] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "$*" >&2
    fi
}

_secrets_error() { _secrets_log error "$@"; }
_secrets_warn() { _secrets_log warn "$@"; }
_secrets_info() { _secrets_log info "$@"; }
_secrets_debug() { _secrets_log debug "$@"; }

# =============================================================================
# SECRET REGISTRATION
# =============================================================================

# Register a secret for secure handling
# Usage: secret_register --name "API_KEY" --value "..."
# Returns: 0 on success, 1 on failure
secret_register() {
    local name=""
    local value=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --value)
                value="$2"
                shift 2
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                    shift
                elif [[ -z "$value" ]]; then
                    value="$1"
                    shift
                else
                    shift
                fi
                ;;
        esac
    done

    # Validate name
    if [[ -z "$name" ]]; then
        _secrets_error "secret_register: name required"
        return 1
    fi

    # Name must be valid identifier
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        _secrets_error "secret_register: invalid name format: $name"
        return 1
    fi

    # Validate value
    if [[ -z "$value" ]]; then
        _secrets_error "secret_register: value required"
        return 1
    fi

    if [[ ${#value} -gt $SECRETS_MAX_LENGTH ]]; then
        _secrets_error "secret_register: value exceeds maximum length (${#value} > $SECRETS_MAX_LENGTH)"
        return 1
    fi

    # Check for newlines (not allowed in secrets)
    if [[ "$value" == *$'\n'* ]]; then
        _secrets_error "secret_register: value cannot contain newlines"
        return 1
    fi

    # Store the secret
    _SECRETS_STORE["$name"]="$value"
    _SECRETS_META["$name"]="registered:$(date +%s)"

    # Add to redaction patterns
    if [[ "$SECRETS_PATTERN_ESCAPE" == "1" ]]; then
        # Escape special regex characters
        local escaped
        escaped=$(printf '%s' "$value" | sed 's/[][$.\^()*+?{|}]/\\&/g')
        _SECRETS_PATTERNS+=("$escaped")
    else
        _SECRETS_PATTERNS+=("$value")
    fi

    _secrets_debug "Secret registered: $name"
    return 0
}

# Unregister a secret
# Usage: secret_unregister --name "API_KEY"
# Returns: 0 on success, 1 on failure
secret_unregister() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        _secrets_error "secret_unregister: name required"
        return 1
    fi

    if [[ -z "${_SECRETS_STORE[$name]:-}" ]]; then
        _secrets_warn "secret_unregister: secret not found: $name"
        return 0  # Idempotent
    fi

    # Overwrite before removal (defense in depth)
    _SECRETS_STORE["$name"]="$(head -c ${#_SECRETS_STORE[$name]} /dev/urandom | base64 | head -c ${#_SECRETS_STORE[$name]})"
    
    # Remove from storage
    unset '_SECRETS_STORE[$name]'
    unset '_SECRETS_META[$name]'

    # Rebuild patterns
    _SECRETS_PATTERNS=()
    local key
    for key in "${!_SECRETS_STORE[@]}"; do
        local val="${_SECRETS_STORE[$key]}"
        if [[ "$SECRETS_PATTERN_ESCAPE" == "1" ]]; then
            local escaped
            escaped=$(printf '%s' "$val" | sed 's/[][$.\^()*+?{|}]/\\&/g')
            _SECRETS_PATTERNS+=("$escaped")
        else
            _SECRETS_PATTERNS+=("$val")
        fi
    done

    _secrets_debug "Secret unregistered: $name"
    return 0
}

# Get a secret value
# Usage: secret_get --name "API_KEY"
# Returns: secret value on stdout, exit code 0 on success
secret_get() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        _secrets_error "secret_get: name required"
        return 1
    fi

    if [[ -z "${_SECRETS_STORE[$name]:-}" ]]; then
        _secrets_error "secret_get: secret not found: $name"
        return 1
    fi

    _secrets_debug "Secret accessed: $name"
    printf '%s' "${_SECRETS_STORE[$name]}"
    return 0
}

# List all registered secret names (values NOT included)
# Usage: secret_list
# Returns: names only, one per line
secret_list() {
    local key
    for key in "${!_SECRETS_STORE[@]}"; do
        printf '%s\n' "$key"
    done | sort
}

# Check if a secret exists
# Usage: secret_exists --name "API_KEY"
# Returns: 0 if exists, 1 if not
secret_exists() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    [[ -n "${_SECRETS_STORE[$name]:-}" ]]
}

# Clear all secrets
# Usage: secret_clear
# Returns: 0 on success
secret_clear() {
    # Overwrite all values first
    local key
    for key in "${!_SECRETS_STORE[@]}"; do
        _SECRETS_STORE["$key"]="$(head -c 32 /dev/urandom | base64)"
    done

    # Clear all data structures
    _SECRETS_STORE=()
    _SECRETS_META=()
    _SECRETS_PATTERNS=()

    _secrets_info "All secrets cleared"
    return 0
}

# =============================================================================
# REDACTION
# =============================================================================

# Redact secrets from text
# Usage: secret_redact --text "..." [--format "***REDACTED:name***"]
# Returns: redacted text on stdout
secret_redact() {
    local text=""
    local format="***REDACTED:%s***"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --text)
                text="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            *)
                if [[ -z "$text" ]]; then
                    text="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$text" ]]; then
        return 0
    fi

    if [[ ${#_SECRETS_STORE[@]} -eq 0 ]]; then
        printf '%s' "$text"
        return 0
    fi

    local result="$text"
    local name value placeholder

    for name in "${!_SECRETS_STORE[@]}"; do
        value="${_SECRETS_STORE[$name]}"
        # Skip empty values to avoid errors
        [[ -z "$value" ]] && continue
        
        placeholder=$(printf "$format" "$name")
        
        # Simple string replacement (safe for most cases)
        # Use parameter expansion for replacement
        result="${result//$value/$placeholder}"
    done

    printf '%s' "$result"
}

# Check if text contains any registered secrets
# Usage: secret_scan --text "..."
# Returns: 0 if secrets found, 1 if clean
secret_scan() {
    local text=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --text)
                text="$2"
                shift 2
                ;;
            *)
                text="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$text" ]]; then
        return 1  # Empty is clean
    fi

    if [[ ${#_SECRETS_STORE[@]} -eq 0 ]]; then
        return 1  # No secrets registered, so nothing to leak
    fi

    local name value
    for name in "${!_SECRETS_STORE[@]}"; do
        value="${_SECRETS_STORE[$name]}"
        [[ -z "$value" ]] && continue
        
        if [[ "$text" == *"$value"* ]]; then
            _secrets_warn "Secret '$name' detected in text"
            return 0  # Found a secret
        fi
    done

    return 1  # Clean
}

# =============================================================================
# SECURE EXECUTION
# =============================================================================

# Execute command with secret injection from template
# Usage: secret_exec --template "curl -H 'Authorization: {API_KEY}' {URL}"
# Template variables are replaced with secret values
# Returns: exit code of executed command
secret_exec() {
    local template=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template)
                template="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                if [[ -z "$template" ]]; then
                    template="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$template" ]]; then
        _secrets_error "secret_exec: template required"
        return 1
    fi

    # Replace placeholders with secret values
    local cmd="$template"
    local name value

    for name in "${!_SECRETS_STORE[@]}"; do
        value="${_SECRETS_STORE[$name]}"
        # Replace {NAME} with value
        cmd="${cmd//\{$name\}/$value}"
        # Also replace {name} (lowercase)
        cmd="${cmd//\{${name,,}\}/$value}"
    done

    # Check for unreplaced placeholders
    if [[ "$cmd" =~ \{[A-Za-z_][A-Za-z0-9_]*\} ]]; then
        local placeholder="${BASH_REMATCH[0]}"
        _secrets_error "secret_exec: unreplaced placeholder $placeholder"
        return 1
    fi

    if [[ "$dry_run" == true ]]; then
        # Show redacted version
        local redacted
        redacted=$(secret_redact --text "$cmd")
        printf '[DRY-RUN] Would execute: %s\n' "$redacted"
        return 0
    fi

    _secrets_debug "Executing templated command"
    
    # Execute the command
    eval "$cmd"
    return $?
}

# Execute a command with environment variables set from secrets
# Usage: secret_exec_env --env "API_KEY:MY_API_KEY" -- command [args...]
secret_exec_env() {
    local -a env_mappings=()
    local -a cmd_args=()
    local in_cmd=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                env_mappings+=("$2")
                shift 2
                ;;
            --)
                in_cmd=true
                shift
                ;;
            *)
                if [[ "$in_cmd" == true ]]; then
                    cmd_args+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ ${#cmd_args[@]} -eq 0 ]]; then
        _secrets_error "secret_exec_env: command required"
        return 1
    fi

    # Build environment variable exports
    local mapping secret_name env_name secret_value
    for mapping in "${env_mappings[@]}"; do
        secret_name="${mapping%%:*}"
        env_name="${mapping##*:}"
        
        if [[ -z "${_SECRETS_STORE[$secret_name]:-}" ]]; then
            _secrets_error "secret_exec_env: secret not found: $secret_name"
            return 1
        fi
        
        secret_value="${_SECRETS_STORE[$secret_name]}"
        export "$env_name=$secret_value"
        _secrets_debug "Exported $env_name from secret $secret_name"
    done

    # Execute command
    "${cmd_args[@]}"
    local exit_code=$?

    # Unset environment variables (cleanup)
    for mapping in "${env_mappings[@]}"; do
        env_name="${mapping##*:}"
        unset "$env_name"
    done

    return $exit_code
}

# =============================================================================
# AUTO-WRAP FUNCTIONS
# =============================================================================

# Wrap a function to automatically redact its output
# Usage: secret_wrap FUNCTION_NAME
# After wrapping, all output from FUNCTION_NAME will have secrets redacted
secret_wrap() {
    local func_name="$1"

    if [[ -z "$func_name" ]]; then
        _secrets_error "secret_wrap: function name required"
        return 1
    fi

    # Check if function exists
    if ! declare -F "$func_name" &>/dev/null; then
        _secrets_error "secret_wrap: function not found: $func_name"
        return 1
    fi

    # Check if already wrapped
    if [[ -n "${_SECRETS_WRAPPED[$func_name]:-}" ]]; then
        _secrets_warn "secret_wrap: function already wrapped: $func_name"
        return 0
    fi

    # Get original function definition
    local original_name="_secret_original_$func_name"
    
    # Create renamed copy
    eval "${original_name}() { $(declare -f "$func_name" | tail -n +2 | head -n -1); }"
    
    # Create wrapped version
    eval "${func_name}() {
        local _output
        _output=$("$original_name" \"\$@\" 2>&1)
        local _exit_code=\$?
        secret_redact --text \"\$_output\"
        return \$_exit_code
    }"

    _SECRETS_WRAPPED["$func_name"]="$original_name"
    _secrets_debug "Function wrapped: $func_name"
    
    return 0
}

# Unwrap a previously wrapped function
# Usage: secret_unwrap FUNCTION_NAME
secret_unwrap() {
    local func_name="$1"

    if [[ -z "$func_name" ]]; then
        _secrets_error "secret_unwrap: function name required"
        return 1
    fi

    if [[ -z "${_SECRETS_WRAPPED[$func_name]:-}" ]]; then
        _secrets_warn "secret_unwrap: function not wrapped: $func_name"
        return 0
    fi

    local original_name="${_SECRETS_WRAPPED[$func_name]}"

    # Restore original
    unset -f "$func_name"
    eval "${func_name}() { ${original_name} \"\$@\"; }"
    unset -f "$original_name"
    unset '_SECRETS_WRAPPED[$func_name]'

    _secrets_debug "Function unwrapped: $func_name"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get count of registered secrets
secret_count() {
    echo "${#_SECRETS_STORE[@]}"
}

# Show secret metadata (without values)
# Usage: secret_info --name "API_KEY"
secret_info() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        # Show all secrets info
        printf '%-30s %s\n' "NAME" "REGISTERED"
        printf '%s\n' "------------------------------------------"
        local key meta registered
        for key in "${!_SECRETS_STORE[@]}"; do
            meta="${_SECRETS_META[$key]}"
            registered="${meta#registered:}"
            if [[ -n "$registered" ]]; then
                printf '%-30s %s\n' "$key" "$(date -d "@$registered" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$registered")"
            else
                printf '%-30s %s\n' "$key" "unknown"
            fi
        done
    else
        if [[ -z "${_SECRETS_STORE[$name]:-}" ]]; then
            _secrets_error "secret_info: secret not found: $name"
            return 1
        fi
        
        printf 'Name: %s\n' "$name"
        printf 'Length: %d bytes\n' "${#_SECRETS_STORE[$name]}"
        local meta="${_SECRETS_META[$name]}"
        if [[ -n "$meta" ]]; then
            local registered="${meta#registered:}"
            printf 'Registered: %s\n' "$(date -d "@$registered" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$registered")"
        fi
    fi
}

# Validate secret strength (basic checks)
# Usage: secret_validate --name "API_KEY" --min-length 16
secret_validate() {
    local name=""
    local min_length=8

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --min-length)
                min_length="$2"
                shift 2
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        _secrets_error "secret_validate: name required"
        return 1
    fi

    if [[ -z "${_SECRETS_STORE[$name]:-}" ]]; then
        _secrets_error "secret_validate: secret not found: $name"
        return 1
    fi

    local value="${_SECRETS_STORE[$name]}"
    local issues=0

    # Check length
    if [[ ${#value} -lt $min_length ]]; then
        _secrets_warn "Secret '$name' is too short (${#value} < $min_length)"
        ((issues++))
    fi

    # Check for common weak patterns
    if [[ "$value" =~ ^(password|secret|key|token|admin|root|test|123)?[0-9]*$ ]]; then
        _secrets_warn "Secret '$name' appears to be a common/weak value"
        ((issues++))
    fi

    # Check for repeated characters
    if [[ "$value" =~ (.)\1{4,} ]]; then
        _secrets_warn "Secret '$name' has repeated characters"
        ((issues++))
    fi

    return $((issues > 0 ? 1 : 0))
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_SECRETS_EXPORTS=(
    # Registration
    secret_register
    secret_unregister
    secret_get
    secret_list
    secret_exists
    secret_clear

    # Redaction
    secret_redact
    secret_scan

    # Execution
    secret_exec
    secret_exec_env

    # Auto-wrap
    secret_wrap
    secret_unwrap

    # Utilities
    secret_count
    secret_info
    secret_validate
)

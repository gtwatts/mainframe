#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/guard.sh - Defensive Programming Guards
# =============================================================================
# Description: Pre-execution guards and runtime checks for common failure modes
#              targeting AI coding assistant error prevention.
# Purpose: Prevent the most common AI-generated script failures:
#          - Path errors (35% of failures)
#          - Variable errors (25% of failures)
#          - Command errors (20% of failures)
#          - State errors (10% of failures)
#          - Input validation (10% of failures)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GUARD_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GUARD_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Cleanup registry
declare -ga _GUARD_CLEANUP_HANDLERS=()
declare -g _GUARD_INITIALIZED=false

# Lock tracking
declare -gA _GUARD_HELD_LOCKS=()

# =============================================================================
# LOGGING HELPERS (minimal dependency)
# =============================================================================

_guard_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    else
        printf '[%s] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "$*" >&2
    fi
}

_guard_error() { _guard_log error "$@"; }
_guard_warn() { _guard_log warn "$@"; }
_guard_info() { _guard_log info "$@"; }

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize all guards - call at script start
# Usage: guard_init
# Sets: -euo pipefail, error handlers, cleanup traps
guard_init() {
    $_GUARD_INITIALIZED && return 0

    # Strict mode
    set -euo pipefail

    # Error handler
    trap '_guard_error_handler $? $LINENO "$BASH_COMMAND"' ERR

    # Cleanup handler
    trap '_guard_cleanup_handler' EXIT

    _GUARD_INITIALIZED=true
}

# Internal error handler
_guard_error_handler() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"

    _guard_error "Command failed: $command"
    _guard_error "  Exit code: $exit_code"
    _guard_error "  Line: $line_number"
    _guard_error "  Script: ${BASH_SOURCE[1]:-unknown}"

    # Print stack trace if available
    if declare -F error::stack_trace &>/dev/null; then
        error::stack_trace 2
    else
        _guard_print_stack 2
    fi
}

# Simple stack trace
_guard_print_stack() {
    local start="${1:-0}"
    local i

    _guard_error "Stack trace:"
    for ((i=start; i < ${#FUNCNAME[@]}; i++)); do
        _guard_error "  ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]}"
    done
}

# Internal cleanup handler
_guard_cleanup_handler() {
    local handler

    # Release any held locks
    for lockfile in "${!_GUARD_HELD_LOCKS[@]}"; do
        _guard_warn "Auto-releasing lock: $lockfile"
        guard_unlock "$lockfile" 2>/dev/null || true
    done

    # Run registered cleanup handlers in reverse order
    for ((i=${#_GUARD_CLEANUP_HANDLERS[@]}-1; i>=0; i--)); do
        handler="${_GUARD_CLEANUP_HANDLERS[$i]}"
        eval "$handler" 2>/dev/null || true
    done
}

# Register cleanup handler
# Usage: guard_on_exit "rm -f /tmp/myfile"
guard_on_exit() {
    _GUARD_CLEANUP_HANDLERS+=("$*")
}

# =============================================================================
# PATH GUARDS
# =============================================================================

# Guard: Path must exist
# Usage: guard_path_exists "/path" [file|dir|any] ["context"]
# Returns: 0 if exists, 1 if not
guard_path_exists() {
    local path="$1"
    local path_type="${2:-any}"
    local context="${3:-}"

    # Check for empty path
    if [[ -z "$path" ]]; then
        _guard_error "Empty path provided${context:+ in $context}"
        return 1
    fi

    # Check existence based on type
    case "$path_type" in
        file)
            if [[ ! -f "$path" ]]; then
                _guard_error "File not found: $path${context:+ in $context}"
                _guard_error "  Current directory: $(pwd)"
                _guard_error "  Tried: $(realpath -m "$path" 2>/dev/null || echo "[cannot resolve]")"
                return 1
            fi
            ;;
        dir|directory)
            if [[ ! -d "$path" ]]; then
                _guard_error "Directory not found: $path${context:+ in $context}"
                _guard_error "  Current directory: $(pwd)"
                return 1
            fi
            ;;
        any|*)
            if [[ ! -e "$path" ]]; then
                _guard_error "Path not found: $path${context:+ in $context}"
                _guard_error "  Current directory: $(pwd)"
                return 1
            fi
            ;;
    esac

    return 0
}

# Guard: Path must be safe (no traversal outside base)
# Usage: guard_path_safe "/base" "/user/provided/path"
# Returns: 0 if safe, 1 if traversal detected
guard_path_safe() {
    local base_dir="$1"
    local user_path="$2"

    # Resolve base directory
    local real_base
    real_base=$(realpath -m "$base_dir" 2>/dev/null) || {
        _guard_error "Cannot resolve base directory: $base_dir"
        return 1
    }

    # Build and resolve full path
    local full_path="${base_dir}/${user_path}"
    local real_path
    real_path=$(realpath -m "$full_path" 2>/dev/null) || {
        _guard_error "Cannot resolve path: $full_path"
        return 1
    }

    # Check for traversal
    if [[ "$real_path" != "$real_base"/* && "$real_path" != "$real_base" ]]; then
        _guard_error "Path traversal detected!"
        _guard_error "  User input: $user_path"
        _guard_error "  Resolved: $real_path"
        _guard_error "  Allowed base: $real_base"
        return 1
    fi

    # Also check for encoded traversal attempts in original input
    if [[ "$user_path" == *".."* ]] || \
       [[ "$user_path" == *"%2e%2e"* ]] || \
       [[ "$user_path" == *"%2E%2E"* ]] || \
       [[ "$user_path" == *"%00"* ]]; then
        _guard_warn "Suspicious path pattern detected: $user_path"
    fi

    return 0
}

# Guard: Path characters are safe
# Usage: guard_path_chars "/path" [strict]
# Returns: 0 if safe, 1 if dangerous characters found
guard_path_chars() {
    local path="$1"
    local strict="${2:-false}"

    # Always reject null bytes (bash can't store them but check for encoded)
    if [[ "$path" == *"%00"* ]]; then
        _guard_error "Path contains null byte encoding: $path"
        return 1
    fi

    # Reject newlines
    if [[ "$path" == *$'\n'* ]]; then
        _guard_error "Path contains newline character"
        return 1
    fi

    # In strict mode, warn about potentially problematic characters
    if [[ "$strict" == "true" ]]; then
        if [[ "$path" =~ [[:space:]] ]]; then
            _guard_warn "Path contains whitespace: $path"
            _guard_warn "  Ensure all uses are properly quoted"
        fi
        if [[ "$path" =~ [\'\"\`\$\!] ]]; then
            _guard_warn "Path contains shell metacharacters: $path"
            _guard_warn "  Use printf %q for escaping if needed"
        fi
    fi

    return 0
}

# Guard: Handle symlinks safely
# Usage: guard_symlink "/path" [warn|follow|reject]
# Returns: Resolved path on stdout, exit code based on policy
guard_symlink() {
    local path="$1"
    local policy="${2:-warn}"

    if [[ -L "$path" ]]; then
        local target
        target=$(readlink -f "$path" 2>/dev/null) || target="[broken symlink]"

        case "$policy" in
            warn)
                _guard_warn "Path is symlink: $path -> $target"
                printf '%s\n' "$path"
                return 0
                ;;
            follow)
                _guard_info "Following symlink: $path -> $target"
                printf '%s\n' "$target"
                return 0
                ;;
            reject)
                _guard_error "Symlinks not allowed: $path -> $target"
                return 1
                ;;
        esac
    fi

    printf '%s\n' "$path"
    return 0
}

# Guard: Check before destructive operations
# Usage: guard_destructive_path "/path/to/delete"
# Returns: 0 if safe to delete, 1 if dangerous
guard_destructive_path() {
    local path="$1"

    # Reject empty path
    if [[ -z "$path" ]]; then
        _guard_error "Refusing destructive operation on empty path"
        return 1
    fi

    # Reject root
    if [[ "$path" == "/" ]]; then
        _guard_error "Refusing destructive operation on root filesystem"
        return 1
    fi

    # Reject common dangerous paths
    case "$path" in
        /bin|/sbin|/lib|/lib64|/usr|/var|/etc|/home|/root|/boot|/sys|/proc|/dev)
            _guard_error "Refusing destructive operation on system directory: $path"
            return 1
            ;;
        "$HOME"|"$HOME/")
            _guard_error "Refusing destructive operation on home directory"
            return 1
            ;;
    esac

    # Check if it's a mount point
    if command -v mountpoint &>/dev/null && mountpoint -q "$path" 2>/dev/null; then
        _guard_error "Refusing destructive operation on mount point: $path"
        return 1
    fi

    # Warn if path is outside common temp/work directories
    case "$path" in
        /tmp/*|/var/tmp/*|"$HOME"/tmp/*|"$HOME"/.cache/*)
            # These are expected locations for temp files
            return 0
            ;;
        *)
            _guard_warn "Destructive operation on non-temp path: $path"
            ;;
    esac

    return 0
}

# =============================================================================
# VARIABLE GUARDS
# =============================================================================

# Guard: Variable must be set (and optionally non-empty)
# Usage: guard_var_set "VAR_NAME" [require_nonempty] [default]
# Returns: 0 if set (and applied default if needed), 1 if not set
# shellcheck disable=SC2163  # Dynamic export is intentional
guard_var_set() {
    local var_name="$1"
    local require_nonempty="${2:-true}"
    local default="${3:-}"

    # Validate variable name
    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        _guard_error "Invalid variable name: $var_name"
        return 1
    fi

    # Check if set using indirect expansion
    if [[ -z "${!var_name+x}" ]]; then
        if [[ -n "$default" ]]; then
            _guard_warn "Variable $var_name not set, using default: $default"
            eval "$var_name=\$default"
            export "$var_name"
            return 0
        else
            _guard_error "Required variable not set: $var_name"
            return 1
        fi
    fi

    # Check if non-empty when required
    if [[ "$require_nonempty" == "true" && -z "${!var_name}" ]]; then
        if [[ -n "$default" ]]; then
            _guard_warn "Variable $var_name is empty, using default: $default"
            eval "$var_name=\$default"
            export "$var_name"
            return 0
        else
            _guard_error "Variable $var_name is set but empty"
            return 1
        fi
    fi

    return 0
}

# Guard: Variable is safe for shell use (no injection characters)
# Usage: guard_var_safe "value"
# Returns: 0 if safe, 1 if contains dangerous characters
guard_var_safe() {
    local value="$1"

    # Check for command separators
    if [[ "$value" == *";"* ]] || \
       [[ "$value" == *"|"* ]] || \
       [[ "$value" == *"&"* ]] || \
       [[ "$value" == *$'\n'* ]]; then
        _guard_error "Value contains command separator characters"
        return 1
    fi

    # Check for command substitution
    if [[ "$value" == *'$('* ]] || [[ "$value" == *'`'* ]]; then
        _guard_error "Value contains command substitution syntax"
        return 1
    fi

    # Check for redirections
    if [[ "$value" == *">"* ]] || [[ "$value" == *"<"* ]]; then
        _guard_error "Value contains redirection characters"
        return 1
    fi

    return 0
}

# Guard: Array index in bounds
# Usage: guard_array_bounds arr_name index
# Returns: 0 if in bounds, 1 if out of bounds
guard_array_bounds() {
    local arr_name="$1"
    local index="$2"

    # Validate index is integer
    if [[ ! "$index" =~ ^-?[0-9]+$ ]]; then
        _guard_error "Invalid array index (not integer): $index"
        return 1
    fi

    # Get array length via nameref
    local -n arr_ref="$arr_name"
    local length=${#arr_ref[@]}

    # Handle negative indices
    local effective_index=$index
    if ((index < 0)); then
        effective_index=$((length + index))
    fi

    # Bounds check
    if ((effective_index < 0 || effective_index >= length)); then
        _guard_error "Array index out of bounds: $index"
        _guard_error "  Array: $arr_name"
        _guard_error "  Length: $length"
        _guard_error "  Valid range: 0 to $((length - 1)) (or -$length to -1)"
        return 1
    fi

    return 0
}

# =============================================================================
# COMMAND GUARDS
# =============================================================================

# Guard: Command must exist
# Usage: guard_command "cmd" ["install hint"]
# Returns: 0 if exists, 1 if not
guard_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &>/dev/null; then
        _guard_error "Required command not found: $cmd"

        if [[ -n "$install_hint" ]]; then
            _guard_error "  Install with: $install_hint"
        else
            # Try to suggest installation
            local suggestion=""
            case "$cmd" in
                jq)       suggestion="apt install jq / brew install jq" ;;
                yq)       suggestion="snap install yq / brew install yq" ;;
                realpath) suggestion="apt install coreutils / brew install coreutils" ;;
                timeout)  suggestion="apt install coreutils / brew install coreutils" ;;
                curl)     suggestion="apt install curl / brew install curl" ;;
                wget)     suggestion="apt install wget / brew install wget" ;;
                git)      suggestion="apt install git / brew install git" ;;
                *)        suggestion="Check your package manager" ;;
            esac
            _guard_error "  Try: $suggestion"
        fi
        return 1
    fi

    return 0
}

# Guard: All required commands must exist
# Usage: guard_commands cmd1 cmd2 cmd3
# Returns: 0 if all exist, 1 if any missing
guard_commands() {
    local -a missing=()

    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        _guard_error "Missing required commands: ${missing[*]}"
        return 1
    fi

    return 0
}

# Guard: OS compatibility
# Usage: guard_os linux|macos|bsd
# Returns: 0 if running on specified OS, 1 if not
guard_os() {
    local required_os="$1"
    local current_os

    case "$(uname -s)" in
        Linux*)   current_os="linux" ;;
        Darwin*)  current_os="macos" ;;
        FreeBSD*) current_os="bsd" ;;
        OpenBSD*) current_os="bsd" ;;
        NetBSD*)  current_os="bsd" ;;
        *)        current_os="unknown" ;;
    esac

    if [[ "$current_os" != "$required_os" ]]; then
        _guard_error "OS mismatch: requires $required_os, running on $current_os"
        return 1
    fi

    return 0
}

# =============================================================================
# LOCK GUARDS
# =============================================================================

# Guard: Acquire lock or fail
# Usage: guard_lock "/lockfile" [timeout_seconds]
# Returns: 0 if acquired, 1 if failed
guard_lock() {
    local lockfile="$1"
    local timeout="${2:-0}"
    local lockdir="${lockfile}.d"
    local start elapsed

    start=$(date +%s)

    while true; do
        # Try atomic directory creation
        if mkdir "$lockdir" 2>/dev/null; then
            # Write PID for debugging
            echo $$ > "$lockfile"
            _GUARD_HELD_LOCKS["$lockfile"]=1
            return 0
        fi

        # Check for stale lock
        if [[ -f "$lockfile" ]]; then
            local holder_pid
            holder_pid=$(cat "$lockfile" 2>/dev/null)
            if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
                _guard_warn "Removing stale lock (dead process $holder_pid)"
                rm -rf "$lockdir" "$lockfile" 2>/dev/null
                continue
            fi
        fi

        # Check timeout
        if ((timeout > 0)); then
            elapsed=$(($(date +%s) - start))
            if ((elapsed >= timeout)); then
                _guard_error "Lock acquisition timeout after ${timeout}s: $lockfile"
                return 1
            fi
            sleep 0.1
        else
            _guard_error "Lock already held: $lockfile"
            return 1
        fi
    done
}

# Release lock
# Usage: guard_unlock "/lockfile"
guard_unlock() {
    local lockfile="$1"
    local lockdir="${lockfile}.d"

    rmdir "$lockdir" 2>/dev/null
    rm -f "$lockfile" 2>/dev/null
    unset '_GUARD_HELD_LOCKS[$lockfile]'

    return 0
}

# Execute command with lock
# Usage: guard_with_lock "/lockfile" command [args...]
guard_with_lock() {
    local lockfile="$1"
    shift

    if guard_lock "$lockfile"; then
        local result=0
        "$@" || result=$?
        guard_unlock "$lockfile"
        return $result
    fi

    return 1
}

# =============================================================================
# RESOURCE GUARDS
# =============================================================================

# Guard: Disk space available
# Usage: guard_disk_space "/path" min_bytes
# Returns: 0 if sufficient space, 1 if not
guard_disk_space() {
    local path="$1"
    local min_bytes="$2"

    # Get available space in bytes
    local available
    if [[ "$(uname)" == "Darwin" ]]; then
        available=$(df -k "$path" 2>/dev/null | awk 'NR==2 {print $4 * 1024}')
    else
        available=$(df -B1 "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    fi

    if [[ -z "$available" ]]; then
        _guard_error "Cannot determine available disk space for: $path"
        return 1
    fi

    if ((available < min_bytes)); then
        _guard_error "Insufficient disk space on $path"
        _guard_error "  Available: $available bytes"
        _guard_error "  Required: $min_bytes bytes"
        return 1
    fi

    return 0
}

# Guard: Memory available
# Usage: guard_memory min_bytes
# Returns: 0 if sufficient memory, 1 if not
guard_memory() {
    local min_bytes="$1"
    local available

    if [[ -f /proc/meminfo ]]; then
        available=$(awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo 2>/dev/null)
    elif [[ "$(uname)" == "Darwin" ]]; then
        # macOS: use vm_stat (approximate)
        local pages_free
        pages_free=$(vm_stat 2>/dev/null | awk '/Pages free:/ {gsub(/\./, "", $3); print $3}')
        available=$((pages_free * 4096))
    fi

    if [[ -z "$available" ]]; then
        _guard_warn "Cannot determine available memory"
        return 0  # Don't fail if we can't check
    fi

    if ((available < min_bytes)); then
        _guard_error "Insufficient memory"
        _guard_error "  Available: $available bytes"
        _guard_error "  Required: $min_bytes bytes"
        return 1
    fi

    return 0
}

# =============================================================================
# INPUT VALIDATION GUARDS
# =============================================================================

# Guard: Integer within range
# Usage: guard_integer "value" [min] [max] ["name"]
# Returns: 0 if valid, 1 if invalid
guard_integer() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    local name="${4:-value}"

    # Check it's a valid integer
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        _guard_error "$name is not a valid integer: $value"
        return 1
    fi

    # Check minimum
    if [[ -n "$min" ]] && ((value < min)); then
        _guard_error "$name is below minimum ($min): $value"
        return 1
    fi

    # Check maximum
    if [[ -n "$max" ]] && ((value > max)); then
        _guard_error "$name exceeds maximum ($max): $value"
        return 1
    fi

    return 0
}

# Guard: Safe filename (no path separators)
# Usage: guard_filename "name"
# Returns: 0 if safe, 1 if not
guard_filename() {
    local name="$1"

    # Reject empty
    if [[ -z "$name" ]]; then
        _guard_error "Empty filename"
        return 1
    fi

    # Reject path separators
    if [[ "$name" == *"/"* ]] || [[ "$name" == *"\\"* ]]; then
        _guard_error "Filename contains path separator: $name"
        return 1
    fi

    # Reject . and ..
    if [[ "$name" == "." ]] || [[ "$name" == ".." ]]; then
        _guard_error "Invalid filename: $name"
        return 1
    fi

    # Reject dangerous characters
    if [[ "$name" == *$'\0'* ]] || [[ "$name" == *$'\n'* ]]; then
        _guard_error "Filename contains null or newline"
        return 1
    fi

    return 0
}

# =============================================================================
# COMPOSITE GUARDS
# =============================================================================

# Guard: File operation safety (combines multiple checks)
# Usage: guard_file_op "read|write|delete" "/path"
# Returns: 0 if safe to proceed, 1 if not
guard_file_op() {
    local operation="$1"
    local path="$2"

    # Common checks
    guard_path_chars "$path" strict || return 1

    case "$operation" in
        read)
            guard_path_exists "$path" file || return 1
            [[ -r "$path" ]] || {
                _guard_error "File not readable: $path"
                return 1
            }
            ;;
        write)
            local dir
            dir=$(dirname "$path")
            guard_path_exists "$dir" dir || return 1
            [[ -w "$dir" ]] || {
                _guard_error "Directory not writable: $dir"
                return 1
            }
            if [[ -e "$path" && ! -w "$path" ]]; then
                _guard_error "File exists and not writable: $path"
                return 1
            fi
            ;;
        delete)
            guard_destructive_path "$path" || return 1
            guard_path_exists "$path" || return 1
            ;;
        *)
            _guard_error "Unknown file operation: $operation"
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_GUARD_EXPORTS=(
    # Initialization
    guard_init
    guard_on_exit

    # Path guards
    guard_path_exists
    guard_path_safe
    guard_path_chars
    guard_symlink
    guard_destructive_path

    # Variable guards
    guard_var_set
    guard_var_safe
    guard_array_bounds

    # Command guards
    guard_command
    guard_commands
    guard_os

    # Lock guards
    guard_lock
    guard_unlock
    guard_with_lock

    # Resource guards
    guard_disk_space
    guard_memory

    # Input validation guards
    guard_integer
    guard_filename

    # Composite guards
    guard_file_op
)

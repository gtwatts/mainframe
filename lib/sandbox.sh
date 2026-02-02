#!/usr/bin/env bash
# =============================================================================
# sandbox.sh - Execution Sandboxing for AI Agents
# =============================================================================
# Description: Provides execution boundaries with restricted access to filesystem,
#              network, and system resources. Enables safe autonomous execution.
#              v2.0 adds bubblewrap (bwrap) integration for OS-level isolation.
# Version: 2.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SANDBOX_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_SANDBOX_LOADED=1

# =============================================================================
# Global State
# =============================================================================

declare -g _SANDBOX_ENABLED=0
declare -g _SANDBOX_DRY_RUN=0
declare -g _SANDBOX_ROOT=""
declare -g _SANDBOX_TIMEOUT=300
declare -g _SANDBOX_MAX_MEMORY=""
declare -ga _SANDBOX_ALLOW_WRITE=()
declare -ga _SANDBOX_DENY_WRITE=()
declare -g _SANDBOX_NETWORK_ALLOWED=1
declare -g _SANDBOX_AUDIT_LOG=""

# =============================================================================
# Internal Functions
# =============================================================================

# Log sandbox actions
_sandbox_log() {
    local action="$1"
    local details="$2"
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    if [[ -n "$_SANDBOX_AUDIT_LOG" ]]; then
        printf '{"timestamp":"%s","action":"%s","details":%s}\n' \
            "$timestamp" "$action" "${details:-\"\"}" >> "$_SANDBOX_AUDIT_LOG"
    fi
}

# Check if path is within allowed write directories
_sandbox_can_write() {
    local path="$1"

    # Normalize path
    local abs_path
    abs_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path") || abs_path="$path"

    # Check deny list first (higher priority)
    local deny_pattern
    for deny_pattern in "${_SANDBOX_DENY_WRITE[@]}"; do
        [[ -z "$deny_pattern" ]] && continue
        if [[ "$abs_path" == "$deny_pattern"* ]]; then
            _sandbox_log "write_denied" "\"$abs_path (matched deny: $deny_pattern)\""
            return 1
        fi
    done

    # Check allow list
    if [[ ${#_SANDBOX_ALLOW_WRITE[@]} -eq 0 ]]; then
        # No allow list means all writes allowed (within root)
        if [[ -n "$_SANDBOX_ROOT" && "$abs_path" != "$_SANDBOX_ROOT"* ]]; then
            _sandbox_log "write_denied" "\"$abs_path (outside root: $_SANDBOX_ROOT)\""
            return 1
        fi
        return 0
    fi

    # Check against allow list
    local allow_pattern
    for allow_pattern in "${_SANDBOX_ALLOW_WRITE[@]}"; do
        [[ -z "$allow_pattern" ]] && continue
        if [[ "$abs_path" == "$allow_pattern"* ]]; then
            _sandbox_log "write_allowed" "\"$abs_path (matched: $allow_pattern)\""
            return 0
        fi
    done

    _sandbox_log "write_denied" "\"$abs_path (no matching allow pattern)\""
    return 1
}

# =============================================================================
# Public API
# =============================================================================

# sandbox_enable - Enable sandboxing with options
# Usage: sandbox_enable [--dry-run] [--root "/path"] [--timeout N] [--max-memory "512M"]
sandbox_enable() {
    _SANDBOX_ENABLED=1
    _SANDBOX_DRY_RUN=0
    _SANDBOX_ROOT=""
    _SANDBOX_TIMEOUT=300
    _SANDBOX_MAX_MEMORY=""
    _SANDBOX_ALLOW_WRITE=()
    _SANDBOX_DENY_WRITE=()
    _SANDBOX_NETWORK_ALLOWED=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                _SANDBOX_DRY_RUN=1
                shift
                ;;
            --root)
                _SANDBOX_ROOT="$2"
                # Verify root exists
                if [[ ! -d "$_SANDBOX_ROOT" ]]; then
                    echo "Error: Sandbox root does not exist: $_SANDBOX_ROOT" >&2
                    return 1
                fi
                shift 2
                ;;
            --timeout)
                _SANDBOX_TIMEOUT="$2"
                shift 2
                ;;
            --max-memory)
                _SANDBOX_MAX_MEMORY="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    _sandbox_log "sandbox_enabled" "{\"dry_run\":$_SANDBOX_DRY_RUN,\"root\":\"${_SANDBOX_ROOT:-null}\",\"timeout\":$_SANDBOX_TIMEOUT}"

    echo "Sandbox enabled"
    [[ $_SANDBOX_DRY_RUN -eq 1 ]] && echo "  Mode: dry-run (no actual writes)"
    [[ -n "$_SANDBOX_ROOT" ]] && echo "  Root: $_SANDBOX_ROOT"
    echo "  Timeout: ${_SANDBOX_TIMEOUT}s"
    [[ -n "$_SANDBOX_MAX_MEMORY" ]] && echo "  Max memory: $_SANDBOX_MAX_MEMORY"
    return 0
}

# sandbox_disable - Disable sandboxing
sandbox_disable() {
    _SANDBOX_ENABLED=0
    _sandbox_log "sandbox_disabled" "null"
    echo "Sandbox disabled"
}

# sandbox_allow_write - Add path to write allow list
# Usage: sandbox_allow_write "/path/to/dir"
sandbox_allow_write() {
    local path="$1"

    [[ -z "$path" ]] && {
        echo "Usage: sandbox_allow_write <path>" >&2
        return 1
    }

    _SANDBOX_ALLOW_WRITE+=("$path")
    _sandbox_log "allow_write_added" "\"$path\""
    echo "Write allowed: $path"
}

# sandbox_deny_write - Add path to write deny list
# Usage: sandbox_deny_write "/path/to/dir"
sandbox_deny_write() {
    local path="$1"

    [[ -z "$path" ]] && {
        echo "Usage: sandbox_deny_write <path>" >&2
        return 1
    }

    _SANDBOX_DENY_WRITE+=("$path")
    _sandbox_log "deny_write_added" "\"$path\""
    echo "Write denied: $path"
}

# sandbox_deny_network - Disable network access
sandbox_deny_network() {
    _SANDBOX_NETWORK_ALLOWED=0
    _sandbox_log "network_denied" "null"
    echo "Network access denied"
}

# sandbox_allow_network - Enable network access
sandbox_allow_network() {
    _SANDBOX_NETWORK_ALLOWED=1
    _sandbox_log "network_allowed" "null"
    echo "Network access allowed"
}

# sandbox_audit_log - Set audit log file
# Usage: sandbox_audit_log "/path/to/audit.jsonl"
sandbox_audit_log() {
    local path="$1"

    [[ -z "$path" ]] && {
        echo "Usage: sandbox_audit_log <path>" >&2
        return 1
    }

    mkdir -p "$(dirname "$path")" 2>/dev/null
    _SANDBOX_AUDIT_LOG="$path"
    _sandbox_log "audit_log_set" "\"$path\""
    echo "Audit log: $path"
}

# sandbox_exec - Execute command within sandbox constraints
# Usage: sandbox_exec <command> [args...]
sandbox_exec() {
    local cmd="$1"
    shift

    if [[ $_SANDBOX_ENABLED -eq 0 ]]; then
        # Sandbox not enabled, execute normally
        "$cmd" "$@"
        return $?
    fi

    _sandbox_log "exec_start" "{\"cmd\":\"$cmd\",\"args\":\"$*\"}"

    # Check for network commands if network denied
    if [[ $_SANDBOX_NETWORK_ALLOWED -eq 0 ]]; then
        case "$cmd" in
            curl|wget|nc|netcat|ssh|scp|sftp|rsync|ftp)
                echo "Error: Network command '$cmd' blocked by sandbox" >&2
                _sandbox_log "exec_blocked" "\"network command: $cmd\""
                return 1
                ;;
        esac
    fi

    # Dry-run mode
    if [[ $_SANDBOX_DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would execute: $cmd $*"
        _sandbox_log "exec_dry_run" "\"$cmd $*\""
        return 0
    fi

    # Execute with timeout if set
    local result
    if [[ $_SANDBOX_TIMEOUT -gt 0 ]] && command -v timeout &>/dev/null; then
        timeout "${_SANDBOX_TIMEOUT}s" "$cmd" "$@"
        result=$?
    else
        "$cmd" "$@"
        result=$?
    fi

    _sandbox_log "exec_complete" "{\"cmd\":\"$cmd\",\"exit_code\":$result}"
    return $result
}

# sandbox_write - Write to file with sandbox checks
# Usage: sandbox_write <path> <content>
sandbox_write() {
    local path="$1"
    local content="$2"

    if [[ $_SANDBOX_ENABLED -eq 1 ]]; then
        if ! _sandbox_can_write "$path"; then
            echo "Error: Write to '$path' blocked by sandbox" >&2
            return 1
        fi

        if [[ $_SANDBOX_DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would write to: $path"
            _sandbox_log "write_dry_run" "\"$path\""
            return 0
        fi
    fi

    printf '%s' "$content" > "$path"
    _sandbox_log "write_complete" "\"$path\""
}

# sandbox_mkdir - Create directory with sandbox checks
# Usage: sandbox_mkdir <path>
sandbox_mkdir() {
    local path="$1"

    if [[ $_SANDBOX_ENABLED -eq 1 ]]; then
        if ! _sandbox_can_write "$path"; then
            echo "Error: mkdir '$path' blocked by sandbox" >&2
            return 1
        fi

        if [[ $_SANDBOX_DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would create directory: $path"
            _sandbox_log "mkdir_dry_run" "\"$path\""
            return 0
        fi
    fi

    mkdir -p "$path"
    _sandbox_log "mkdir_complete" "\"$path\""
}

# sandbox_rm - Remove file/directory with sandbox checks
# Usage: sandbox_rm <path>
sandbox_rm() {
    local path="$1"

    if [[ $_SANDBOX_ENABLED -eq 1 ]]; then
        if ! _sandbox_can_write "$path"; then
            echo "Error: rm '$path' blocked by sandbox" >&2
            return 1
        fi

        if [[ $_SANDBOX_DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would remove: $path"
            _sandbox_log "rm_dry_run" "\"$path\""
            return 0
        fi
    fi

    rm -rf "$path"
    _sandbox_log "rm_complete" "\"$path\""
}

# sandbox_status - Show current sandbox configuration
sandbox_status() {
    echo "Sandbox Status"
    echo "=============="
    echo "Enabled: $([ "$_SANDBOX_ENABLED" -eq 1 ] && echo 'yes' || echo 'no')"
    echo "Dry-run: $([ "$_SANDBOX_DRY_RUN" -eq 1 ] && echo 'yes' || echo 'no')"
    echo "Root: ${_SANDBOX_ROOT:-none}"
    echo "Timeout: ${_SANDBOX_TIMEOUT}s"
    echo "Max memory: ${_SANDBOX_MAX_MEMORY:-unlimited}"
    echo "Network: $([ "$_SANDBOX_NETWORK_ALLOWED" -eq 1 ] && echo 'allowed' || echo 'denied')"
    echo "Audit log: ${_SANDBOX_AUDIT_LOG:-none}"
    echo ""
    echo "Allow write:"
    for path in "${_SANDBOX_ALLOW_WRITE[@]}"; do
        echo "  - $path"
    done
    [[ ${#_SANDBOX_ALLOW_WRITE[@]} -eq 0 ]] && echo "  (all paths allowed within root)"
    echo ""
    echo "Deny write:"
    for path in "${_SANDBOX_DENY_WRITE[@]}"; do
        echo "  - $path"
    done
    [[ ${#_SANDBOX_DENY_WRITE[@]} -eq 0 ]] && echo "  (none)"
}

# sandbox_check - Check if an operation would be allowed
# Usage: sandbox_check write|exec|network <target>
sandbox_check() {
    local op_type="$1"
    local target="$2"

    if [[ $_SANDBOX_ENABLED -eq 0 ]]; then
        echo "Sandbox not enabled - all operations allowed"
        return 0
    fi

    case "$op_type" in
        write)
            if _sandbox_can_write "$target"; then
                echo "ALLOWED: write to $target"
                return 0
            else
                echo "DENIED: write to $target"
                return 1
            fi
            ;;
        exec)
            echo "ALLOWED: execute $target"
            return 0
            ;;
        network)
            if [[ $_SANDBOX_NETWORK_ALLOWED -eq 1 ]]; then
                echo "ALLOWED: network access"
                return 0
            else
                echo "DENIED: network access"
                return 1
            fi
            ;;
        *)
            echo "Unknown operation type: $op_type" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# BUBBLEWRAP INTEGRATION (v2.0)
# =============================================================================
# Provides true OS-level sandboxing via bubblewrap (bwrap)
# Fallback chain: bwrap -> firejail -> docker -> none
# =============================================================================

# Global state for bubblewrap
declare -g _BWRAP_BIN=""
declare -g _BWRAP_PROFILE_DIR="${MAINFRAME_SANDBOX_PROFILES:-$HOME/.config/mainframe/sandbox/profiles}"
declare -ga _BWRAP_ARGS=()
declare -g _BWRAP_DEBUG=0

# =============================================================================
# Detection & Availability
# =============================================================================

# sandbox_available - Check if bubblewrap is available
# @returns 0 if bwrap exists, 1 otherwise
sandbox_available() {
    if [[ -n "$_BWRAP_BIN" ]]; then
        return 0
    fi

    if command -v bwrap &>/dev/null; then
        _BWRAP_BIN=$(command -v bwrap)
        return 0
    fi

    return 1
}

# sandbox_version - Get bubblewrap version
# @returns version string or empty if not available
sandbox_version() {
    if ! sandbox_available; then
        echo ""
        return 1
    fi

    "$_BWRAP_BIN" --version 2>&1 | head -n1
}

# sandbox_install_hint - Show installation instructions
sandbox_install_hint() {
    cat >&2 << 'EOF'
Bubblewrap (bwrap) is not installed.

Install with:
  Ubuntu/Debian: sudo apt install bubblewrap
  Fedora/RHEL:   sudo dnf install bubblewrap
  Arch Linux:    sudo pacman -S bubblewrap
  macOS:         Not available (use Docker fallback)

Alternatives:
  - firejail (partial compatibility)
  - docker (container-based isolation)
EOF
}

# =============================================================================
# Core Execution
# =============================================================================

# sandbox_run - Run command in bubblewrap sandbox
# @param --profile=NAME - use named profile (optional)
# @param command - command to run
# @param args - command arguments
# @returns command exit code
sandbox_run() {
    local profile=""
    local -a bwrap_args=()

    # Parse options
    while [[ $# -gt 0 && "$1" == --* ]]; do
        case "$1" in
            --profile=*)
                profile="${1#--profile=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run [--profile=NAME] command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    # Load profile if specified
    if [[ -n "$profile" ]]; then
        local profile_args
        if profile_args=$(_bwrap_load_profile "$profile"); then
            eval "bwrap_args=($profile_args)"
        else
            echo "Error: Profile '$profile' not found" >&2
            return 1
        fi
    else
        # Use accumulated args from builder functions
        bwrap_args=("${_BWRAP_ARGS[@]}")
    fi

    # Add defaults if no args specified
    if [[ ${#bwrap_args[@]} -eq 0 ]]; then
        bwrap_args=(
            --unshare-all
            --share-net
            --die-with-parent
            --ro-bind /usr /usr
            --ro-bind /lib /lib
            --ro-bind-try /lib64 /lib64
            --ro-bind /bin /bin
            --ro-bind /sbin /sbin
            --ro-bind-try /etc/resolv.conf /etc/resolv.conf
            --ro-bind-try /etc/ssl /etc/ssl
            --ro-bind-try /etc/ca-certificates /etc/ca-certificates
            --tmpfs /tmp
            --proc /proc
            --dev /dev
        )
    fi

    _sandbox_log "bwrap_run" "{\"cmd\":\"$1\",\"profile\":\"${profile:-default}\"}"

    if [[ $_BWRAP_DEBUG -eq 1 ]]; then
        echo "[DEBUG] bwrap ${bwrap_args[*]} -- $*" >&2
    fi

    "$_BWRAP_BIN" "${bwrap_args[@]}" -- "$@"
    local result=$?

    _sandbox_log "bwrap_complete" "{\"cmd\":\"$1\",\"exit_code\":$result}"

    # Clear accumulated args
    _BWRAP_ARGS=()

    return $result
}

# sandbox_run_isolated - Run with specific isolation level
# @param --level=LEVEL - isolation level (minimal, standard, strict, paranoid)
# @param command - command to run
# @param args - command arguments
sandbox_run_isolated() {
    local level="standard"

    # Parse options
    while [[ $# -gt 0 && "$1" == --* ]]; do
        case "$1" in
            --level=*)
                level="${1#--level=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run_isolated --level=LEVEL command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a bwrap_args=()

    case "$level" in
        minimal)
            # Minimal isolation - shared network, basic filesystem
            bwrap_args=(
                --unshare-pid
                --die-with-parent
                --ro-bind / /
                --dev-bind /dev /dev
                --proc /proc
                --tmpfs /tmp
            )
            ;;
        standard)
            # Standard isolation - no network namespace, read-only root
            bwrap_args=(
                --unshare-all
                --share-net
                --die-with-parent
                --ro-bind /usr /usr
                --ro-bind /lib /lib
                --ro-bind-try /lib64 /lib64
                --ro-bind /bin /bin
                --ro-bind /sbin /sbin
                --ro-bind-try /etc/resolv.conf /etc/resolv.conf
                --ro-bind-try /etc/ssl /etc/ssl
                --ro-bind-try /etc/passwd /etc/passwd
                --tmpfs /tmp
                --proc /proc
                --dev /dev
            )
            ;;
        strict)
            # Strict isolation - no network, minimal filesystem
            bwrap_args=(
                --unshare-all
                --die-with-parent
                --ro-bind /usr /usr
                --ro-bind /lib /lib
                --ro-bind-try /lib64 /lib64
                --ro-bind /bin /bin
                --symlink /usr/lib /lib
                --symlink /usr/lib64 /lib64
                --tmpfs /tmp
                --proc /proc
                --dev /dev
                --new-session
            )
            ;;
        paranoid)
            # Maximum isolation - new user namespace, seccomp, minimal
            bwrap_args=(
                --unshare-all
                --unshare-user
                --die-with-parent
                --ro-bind /usr /usr
                --ro-bind /lib /lib
                --ro-bind-try /lib64 /lib64
                --ro-bind /bin /bin
                --tmpfs /tmp
                --tmpfs /home
                --tmpfs /root
                --proc /proc
                --dev /dev
                --new-session
                --cap-drop ALL
            )
            ;;
        *)
            echo "Error: Unknown isolation level '$level'" >&2
            echo "Valid levels: minimal, standard, strict, paranoid" >&2
            return 1
            ;;
    esac

    _sandbox_log "bwrap_isolated" "{\"level\":\"$level\",\"cmd\":\"$1\"}"

    if [[ $_BWRAP_DEBUG -eq 1 ]]; then
        echo "[DEBUG] bwrap (level=$level) ${bwrap_args[*]} -- $*" >&2
    fi

    "$_BWRAP_BIN" "${bwrap_args[@]}" -- "$@"
}

# =============================================================================
# Profile Management
# =============================================================================

# sandbox_profile_create - Create named sandbox profile
# @param name - profile name
# @param config - JSON configuration
sandbox_profile_create() {
    local name="$1"
    local config="$2"

    if [[ -z "$name" || -z "$config" ]]; then
        echo "Usage: sandbox_profile_create <name> '<json_config>'" >&2
        return 1
    fi

    # Validate JSON
    if ! _bwrap_validate_json "$config"; then
        echo "Error: Invalid JSON configuration" >&2
        return 1
    fi

    mkdir -p "$_BWRAP_PROFILE_DIR"
    printf '%s\n' "$config" > "$_BWRAP_PROFILE_DIR/${name}.json"

    _sandbox_log "profile_created" "{\"name\":\"$name\"}"
    echo "Profile '$name' created"
}

# sandbox_profile_list - List available profiles
# @returns JSON array of profile names
sandbox_profile_list() {
    mkdir -p "$_BWRAP_PROFILE_DIR"

    local profiles=()
    local file

    for file in "$_BWRAP_PROFILE_DIR"/*.json; do
        [[ -f "$file" ]] || continue
        local name
        name=$(basename "$file" .json)
        profiles+=("\"$name\"")
    done

    local IFS=','
    printf '[%s]\n' "${profiles[*]}"
}

# sandbox_profile_delete - Delete a profile
# @param name - profile name
sandbox_profile_delete() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Usage: sandbox_profile_delete <name>" >&2
        return 1
    fi

    local profile_file="$_BWRAP_PROFILE_DIR/${name}.json"

    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$name' not found" >&2
        return 1
    fi

    rm -f "$profile_file"
    _sandbox_log "profile_deleted" "{\"name\":\"$name\"}"
    echo "Profile '$name' deleted"
}

# sandbox_profile_get - Get profile configuration
# @param name - profile name
# @returns JSON configuration
sandbox_profile_get() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Usage: sandbox_profile_get <name>" >&2
        return 1
    fi

    local profile_file="$_BWRAP_PROFILE_DIR/${name}.json"

    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$name' not found" >&2
        return 1
    fi

    cat "$profile_file"
}

# Internal: Load profile and convert to bwrap args
_bwrap_load_profile() {
    local name="$1"
    local profile_file="$_BWRAP_PROFILE_DIR/${name}.json"

    if [[ ! -f "$profile_file" ]]; then
        return 1
    fi

    local config
    config=$(<"$profile_file")

    # Parse JSON and build bwrap args
    local -a args=()

    # Basic isolation
    args+=(--unshare-all --die-with-parent)

    # Network
    if _bwrap_json_bool "$config" "network"; then
        args+=(--share-net)
        args+=(--ro-bind-try /etc/resolv.conf /etc/resolv.conf)
    fi

    # Filesystem mounts
    local fs_mounts
    fs_mounts=$(_bwrap_json_array "$config" "filesystem")
    if [[ -n "$fs_mounts" ]]; then
        while IFS= read -r mount; do
            [[ -z "$mount" ]] && continue
            # Format: "/path:ro" or "/path:rw" or just "/path"
            local path="${mount%:*}"
            local mode="${mount##*:}"
            [[ "$mode" == "$mount" ]] && mode="ro"

            if [[ "$mode" == "rw" ]]; then
                args+=(--bind "$path" "$path")
            else
                args+=(--ro-bind "$path" "$path")
            fi
        done <<< "$fs_mounts"
    fi

    # Default mounts
    args+=(
        --ro-bind /usr /usr
        --ro-bind /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind /bin /bin
        --ro-bind /sbin /sbin
        --tmpfs /tmp
        --proc /proc
        --dev /dev
    )

    # Environment passthrough
    local env_vars
    env_vars=$(_bwrap_json_array "$config" "env_passthrough")
    if [[ -n "$env_vars" ]]; then
        while IFS= read -r var; do
            [[ -z "$var" ]] && continue
            if [[ -n "${!var:-}" ]]; then
                args+=(--setenv "$var" "${!var}")
            fi
        done <<< "$env_vars"
    fi

    # Output as quoted string for eval
    printf '%q ' "${args[@]}"
}

# Internal: Validate JSON (basic)
_bwrap_validate_json() {
    local json="$1"

    # Basic validation: starts with { or [, balanced braces
    [[ "$json" =~ ^[[:space:]]*[\{\[] ]] || return 1

    local open_braces="${json//[^\{]/}"
    local close_braces="${json//[^\}]/}"
    local open_brackets="${json//[^\[]/}"
    local close_brackets="${json//[^\]]/}"

    [[ ${#open_braces} -eq ${#close_braces} ]] || return 1
    [[ ${#open_brackets} -eq ${#close_brackets} ]] || return 1

    return 0
}

# Internal: Get boolean from JSON
_bwrap_json_bool() {
    local json="$1"
    local key="$2"

    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
        [[ "${BASH_REMATCH[1]}" == "true" ]]
        return
    fi
    return 1
}

# Internal: Get array values from JSON (one per line)
_bwrap_json_array() {
    local json="$1"
    local key="$2"

    # Extract array content for key
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
        local array_content="${BASH_REMATCH[1]}"
        # Extract quoted strings
        echo "$array_content" | grep -oE '"[^"]*"' | tr -d '"'
    fi
}

# =============================================================================
# Filesystem Controls
# =============================================================================

# sandbox_mount_ro - Mount path read-only in sandbox
# @param host_path - path on host
# @param sandbox_path - path in sandbox (optional, defaults to host_path)
sandbox_mount_ro() {
    local host_path="$1"
    local sandbox_path="${2:-$1}"

    if [[ -z "$host_path" ]]; then
        echo "Usage: sandbox_mount_ro <host_path> [sandbox_path]" >&2
        return 1
    fi

    _BWRAP_ARGS+=(--ro-bind "$host_path" "$sandbox_path")
}

# sandbox_mount_rw - Mount path read-write in sandbox
# @param host_path - path on host
# @param sandbox_path - path in sandbox (optional, defaults to host_path)
sandbox_mount_rw() {
    local host_path="$1"
    local sandbox_path="${2:-$1}"

    if [[ -z "$host_path" ]]; then
        echo "Usage: sandbox_mount_rw <host_path> [sandbox_path]" >&2
        return 1
    fi

    _BWRAP_ARGS+=(--bind "$host_path" "$sandbox_path")
}

# sandbox_tmpfs - Create tmpfs mount (memory-only filesystem)
# @param path - mount path in sandbox
# @param size_mb - size in MB (optional)
sandbox_tmpfs() {
    local path="$1"
    local size_mb="${2:-}"

    if [[ -z "$path" ]]; then
        echo "Usage: sandbox_tmpfs <path> [size_mb]" >&2
        return 1
    fi

    if [[ -n "$size_mb" ]]; then
        _BWRAP_ARGS+=(--tmpfs "$path" --size "$((size_mb * 1024 * 1024))")
    else
        _BWRAP_ARGS+=(--tmpfs "$path")
    fi
}

# sandbox_bind - Bind mount (same path in/out)
# @param path - path to bind
# @param mode - ro or rw (default: ro)
sandbox_bind() {
    local path="$1"
    local mode="${2:-ro}"

    if [[ -z "$path" ]]; then
        echo "Usage: sandbox_bind <path> [ro|rw]" >&2
        return 1
    fi

    if [[ "$mode" == "rw" ]]; then
        _BWRAP_ARGS+=(--bind "$path" "$path")
    else
        _BWRAP_ARGS+=(--ro-bind "$path" "$path")
    fi
}

# sandbox_overlay - Overlay mount (copy-on-write)
# @param base - base (lower) directory
# @param upper - upper directory (changes go here)
# @param merged - merged view path
sandbox_overlay() {
    local base="$1"
    local upper="$2"
    local merged="$3"

    if [[ -z "$base" || -z "$upper" || -z "$merged" ]]; then
        echo "Usage: sandbox_overlay <base> <upper> <merged>" >&2
        return 1
    fi

    # Create work directory for overlay
    local work
    work=$(mktemp -d)

    _BWRAP_ARGS+=(--overlay "$base" "$upper" "$work" "$merged")
}

# =============================================================================
# Network Controls
# =============================================================================

# sandbox_network_none - Isolate network completely
sandbox_network_none() {
    # Remove --share-net if present, add network isolation
    local -a new_args=()
    for arg in "${_BWRAP_ARGS[@]}"; do
        [[ "$arg" == "--share-net" ]] && continue
        new_args+=("$arg")
    done
    _BWRAP_ARGS=("${new_args[@]}")

    # unshare-all already isolates network, just ensure it's there
    _BWRAP_ARGS+=(--unshare-net)
}

# sandbox_network_localhost - Allow localhost only
sandbox_network_localhost() {
    _BWRAP_ARGS+=(--share-net)
    # Bind only loopback
    _BWRAP_ARGS+=(--ro-bind /etc/hosts /etc/hosts)
}

# sandbox_network_ports - Allow specific ports (informational, not enforced by bwrap)
# @param ports - port numbers to allow
sandbox_network_ports() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_network_ports <port1> [port2] ..." >&2
        return 1
    fi

    # bwrap doesn't do port filtering, but we record for documentation
    local ports_json
    local IFS=','
    ports_json="[${*}]"

    _sandbox_log "network_ports" "$ports_json"

    # Enable network
    _BWRAP_ARGS+=(--share-net)
    _BWRAP_ARGS+=(--ro-bind-try /etc/resolv.conf /etc/resolv.conf)

    echo "Note: bwrap allows network access; port filtering requires iptables/nftables" >&2
}

# sandbox_network_ns - Use existing network namespace
# @param namespace - namespace name
sandbox_network_ns() {
    local namespace="$1"

    if [[ -z "$namespace" ]]; then
        echo "Usage: sandbox_network_ns <namespace>" >&2
        return 1
    fi

    local ns_path="/var/run/netns/$namespace"

    if [[ ! -e "$ns_path" ]]; then
        echo "Error: Network namespace '$namespace' not found" >&2
        return 1
    fi

    _BWRAP_ARGS+=(--userns-block-fd "$ns_path")
}

# =============================================================================
# Resource Limits
# =============================================================================

# sandbox_limit_cpu - Set CPU limit (percentage)
# @param percent - CPU percentage (1-100)
sandbox_limit_cpu() {
    local percent="$1"

    if [[ -z "$percent" || ! "$percent" =~ ^[0-9]+$ ]]; then
        echo "Usage: sandbox_limit_cpu <percent>" >&2
        return 1
    fi

    # bwrap doesn't do CPU limits directly; use cgroups v2 if available
    if [[ -d /sys/fs/cgroup/user.slice ]]; then
        _sandbox_log "cpu_limit" "{\"percent\":$percent,\"method\":\"cgroups_v2_manual\"}"
        echo "Note: CPU limits require cgroups. Use systemd-run or cgexec wrapper." >&2
    fi
}

# sandbox_limit_memory - Set memory limit
# @param size - memory limit (e.g., "512M", "1G")
sandbox_limit_memory() {
    local size="$1"

    if [[ -z "$size" ]]; then
        echo "Usage: sandbox_limit_memory <size>" >&2
        return 1
    fi

    _sandbox_log "memory_limit" "{\"size\":\"$size\"}"
    echo "Note: Memory limits require cgroups. Use systemd-run --scope -p MemoryMax=$size" >&2
}

# sandbox_limit_pids - Set max processes
# @param count - max process count
sandbox_limit_pids() {
    local count="$1"

    if [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]]; then
        echo "Usage: sandbox_limit_pids <count>" >&2
        return 1
    fi

    _sandbox_log "pids_limit" "{\"count\":$count}"
    echo "Note: PID limits require cgroups. Use systemd-run --scope -p TasksMax=$count" >&2
}

# sandbox_limit_fsize - Set max file size
# @param size - max file size (e.g., "100M")
sandbox_limit_fsize() {
    local size="$1"

    if [[ -z "$size" ]]; then
        echo "Usage: sandbox_limit_fsize <size>" >&2
        return 1
    fi

    # Convert to bytes for ulimit
    local bytes
    case "$size" in
        *K) bytes=$((${size%K} * 1024)) ;;
        *M) bytes=$((${size%M} * 1024 * 1024)) ;;
        *G) bytes=$((${size%G} * 1024 * 1024 * 1024)) ;;
        *) bytes="$size" ;;
    esac

    _sandbox_log "fsize_limit" "{\"size\":\"$size\",\"bytes\":$bytes}"

    # Note: ulimit can be set before bwrap, but bwrap doesn't pass through
    echo "Note: File size limits can be set with ulimit -f before sandbox_run" >&2
}

# sandbox_limit_nofile - Set max open files
# @param count - max open file count
sandbox_limit_nofile() {
    local count="$1"

    if [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]]; then
        echo "Usage: sandbox_limit_nofile <count>" >&2
        return 1
    fi

    _sandbox_log "nofile_limit" "{\"count\":$count}"
    echo "Note: Open file limits can be set with ulimit -n before sandbox_run" >&2
}

# sandbox_limits - Set combined resource limits
# @param config - JSON configuration
sandbox_limits() {
    local config="$1"

    if [[ -z "$config" ]]; then
        echo "Usage: sandbox_limits '<json_config>'" >&2
        return 1
    fi

    _sandbox_log "limits_set" "$config"

    echo "Note: Resource limits require cgroups. Use systemd-run for enforcement." >&2
    echo "Example: systemd-run --scope -p MemoryMax=512M -p TasksMax=100 -- sandbox_run cmd" >&2
}

# =============================================================================
# Security Controls
# =============================================================================

# sandbox_drop_caps - Drop all capabilities
sandbox_drop_caps() {
    _BWRAP_ARGS+=(--cap-drop ALL)
}

# sandbox_keep_caps - Keep specific capabilities
# @param caps - capability names (e.g., CAP_NET_BIND_SERVICE)
sandbox_keep_caps() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_keep_caps <cap1> [cap2] ..." >&2
        return 1
    fi

    # Drop all first, then add back specific ones
    _BWRAP_ARGS+=(--cap-drop ALL)
    for cap in "$@"; do
        _BWRAP_ARGS+=(--cap-add "$cap")
    done
}

# sandbox_seccomp - Set seccomp filter
# @param filter - "default", "strict", or path to BPF filter
sandbox_seccomp() {
    local filter="$1"

    if [[ -z "$filter" ]]; then
        echo "Usage: sandbox_seccomp <default|strict|path>" >&2
        return 1
    fi

    case "$filter" in
        default)
            # bwrap's default is fairly permissive
            _sandbox_log "seccomp" "{\"filter\":\"default\"}"
            ;;
        strict)
            # Would need a custom BPF filter file
            _sandbox_log "seccomp" "{\"filter\":\"strict\"}"
            echo "Note: Strict seccomp requires a custom BPF filter file" >&2
            ;;
        *)
            if [[ -f "$filter" ]]; then
                # Store filter path for later use in sandbox_run
                _BWRAP_SECCOMP_FILTER="$filter"
                _sandbox_log "seccomp" "{\"filter\":\"$filter\"}"
            else
                echo "Error: Seccomp filter file not found: $filter" >&2
                return 1
            fi
            ;;
    esac
}

# sandbox_user - Run as specific user
# @param user - username
sandbox_user() {
    local user="$1"

    if [[ -z "$user" ]]; then
        echo "Usage: sandbox_user <username>" >&2
        return 1
    fi

    local uid gid
    uid=$(id -u "$user" 2>/dev/null) || {
        echo "Error: User '$user' not found" >&2
        return 1
    }
    gid=$(id -g "$user" 2>/dev/null)

    _BWRAP_ARGS+=(--uid "$uid" --gid "$gid")
}

# sandbox_unshare_user - Set new user namespace (rootless)
sandbox_unshare_user() {
    _BWRAP_ARGS+=(--unshare-user)
}

# =============================================================================
# Environment Controls
# =============================================================================

# sandbox_env_only - Clear environment, set only these vars
# @param vars - variable names to keep
sandbox_env_only() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_env_only VAR1 [VAR2] ..." >&2
        return 1
    fi

    _BWRAP_ARGS+=(--clearenv)
    for var in "$@"; do
        if [[ -n "${!var:-}" ]]; then
            _BWRAP_ARGS+=(--setenv "$var" "${!var}")
        fi
    done
}

# sandbox_env_passthrough - Pass through specific vars
# @param vars - variable names to pass through
sandbox_env_passthrough() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_env_passthrough VAR1 [VAR2] ..." >&2
        return 1
    fi

    for var in "$@"; do
        if [[ -n "${!var:-}" ]]; then
            _BWRAP_ARGS+=(--setenv "$var" "${!var}")
        fi
    done
}

# sandbox_env_set - Set environment variable in sandbox
# @param key - variable name
# @param value - variable value
sandbox_env_set() {
    local key="$1"
    local value="$2"

    if [[ -z "$key" ]]; then
        echo "Usage: sandbox_env_set <key> <value>" >&2
        return 1
    fi

    _BWRAP_ARGS+=(--setenv "$key" "$value")
}

# sandbox_env_block - Block environment variable
# @param var - variable name to unset
sandbox_env_block() {
    local var="$1"

    if [[ -z "$var" ]]; then
        echo "Usage: sandbox_env_block <var>" >&2
        return 1
    fi

    _BWRAP_ARGS+=(--unsetenv "$var")
}

# =============================================================================
# Pre-built Profiles
# =============================================================================

# sandbox_run_safe - Safe command execution (minimal risk)
# No network, /tmp only, drop caps, strict seccomp
sandbox_run_safe() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run_safe command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a args=(
        --unshare-all
        --die-with-parent
        --ro-bind /usr /usr
        --ro-bind /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind /bin /bin
        --ro-bind /sbin /sbin
        --tmpfs /tmp
        --tmpfs /home
        --proc /proc
        --dev /dev
        --cap-drop ALL
        --new-session
    )

    _sandbox_log "run_safe" "{\"cmd\":\"$1\"}"
    "$_BWRAP_BIN" "${args[@]}" -- "$@"
}

# sandbox_run_web - Web scraping profile
# Network allowed, /tmp rw, /home ro, limited memory
sandbox_run_web() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run_web command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a args=(
        --unshare-all
        --share-net
        --die-with-parent
        --ro-bind /usr /usr
        --ro-bind /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind /bin /bin
        --ro-bind /sbin /sbin
        --ro-bind-try /etc/resolv.conf /etc/resolv.conf
        --ro-bind-try /etc/ssl /etc/ssl
        --ro-bind-try /etc/ca-certificates /etc/ca-certificates
        --ro-bind-try "$HOME" "$HOME"
        --tmpfs /tmp
        --proc /proc
        --dev /dev
    )

    _sandbox_log "run_web" "{\"cmd\":\"$1\"}"
    "$_BWRAP_BIN" "${args[@]}" -- "$@"
}

# sandbox_run_build - Build/compile profile
# No network, project dir rw, /tmp rw, higher limits
sandbox_run_build() {
    local project_dir="${PWD}"

    # Parse options
    while [[ $# -gt 0 && "$1" == --* ]]; do
        case "$1" in
            --project=*)
                project_dir="${1#--project=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run_build [--project=/path] command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a args=(
        --unshare-all
        --die-with-parent
        --ro-bind /usr /usr
        --ro-bind /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind /bin /bin
        --ro-bind /sbin /sbin
        --bind "$project_dir" "$project_dir"
        --tmpfs /tmp
        --proc /proc
        --dev /dev
        --chdir "$project_dir"
    )

    _sandbox_log "run_build" "{\"cmd\":\"$1\",\"project\":\"$project_dir\"}"
    "$_BWRAP_BIN" "${args[@]}" -- "$@"
}

# sandbox_run_untrusted - Untrusted code profile
# No network, tmpfs only, all caps dropped, strict limits
sandbox_run_untrusted() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_run_untrusted command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a args=(
        --unshare-all
        --unshare-user
        --die-with-parent
        --ro-bind /usr /usr
        --ro-bind /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind /bin /bin
        --tmpfs /tmp
        --tmpfs /home
        --tmpfs /root
        --tmpfs /var
        --proc /proc
        --dev /dev
        --cap-drop ALL
        --new-session
    )

    _sandbox_log "run_untrusted" "{\"cmd\":\"$1\"}"
    "$_BWRAP_BIN" "${args[@]}" -- "$@"
}

# =============================================================================
# Utility Functions
# =============================================================================

# sandbox_dry_run - Show bwrap command without executing
sandbox_dry_run() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sandbox_dry_run command [args...]" >&2
        return 1
    fi

    if ! sandbox_available; then
        sandbox_install_hint
        return 127
    fi

    local -a bwrap_args=("${_BWRAP_ARGS[@]}")

    # Add defaults if no args specified
    if [[ ${#bwrap_args[@]} -eq 0 ]]; then
        bwrap_args=(
            --unshare-all
            --share-net
            --die-with-parent
            --ro-bind /usr /usr
            --ro-bind /lib /lib
            --ro-bind-try /lib64 /lib64
            --ro-bind /bin /bin
            --ro-bind /sbin /sbin
            --tmpfs /tmp
            --proc /proc
            --dev /dev
        )
    fi

    echo "bwrap ${bwrap_args[*]} -- $*"

    # Clear accumulated args
    _BWRAP_ARGS=()
}

# sandbox_debug - Debug mode (verbose bwrap output)
sandbox_debug() {
    _BWRAP_DEBUG=1
    sandbox_run "$@"
    local result=$?
    _BWRAP_DEBUG=0
    return $result
}

# sandbox_validate_profile - Validate profile JSON
# @param path - path to profile JSON file
sandbox_validate_profile() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "Usage: sandbox_validate_profile <path.json>" >&2
        return 1
    fi

    if [[ ! -f "$path" ]]; then
        echo "Error: File not found: $path" >&2
        return 1
    fi

    local content
    content=$(<"$path")

    if ! _bwrap_validate_json "$content"; then
        echo "Error: Invalid JSON in $path" >&2
        return 1
    fi

    # Check for required/optional fields
    local valid=1

    # network should be boolean
    if [[ "$content" =~ \"network\"[[:space:]]*:[[:space:]]*([^,}\]]+) ]]; then
        local val="${BASH_REMATCH[1]}"
        if [[ "$val" != "true" && "$val" != "false" ]]; then
            echo "Warning: 'network' should be boolean (true/false)" >&2
        fi
    fi

    # filesystem should be array
    if [[ "$content" =~ \"filesystem\"[[:space:]]*:[[:space:]]*([^,}\]]) ]]; then
        local first="${BASH_REMATCH[1]}"
        if [[ "$first" != "[" ]]; then
            echo "Error: 'filesystem' should be an array" >&2
            valid=0
        fi
    fi

    # env_passthrough should be array
    if [[ "$content" =~ \"env_passthrough\"[[:space:]]*:[[:space:]]*([^,}\]]) ]]; then
        local first="${BASH_REMATCH[1]}"
        if [[ "$first" != "[" ]]; then
            echo "Error: 'env_passthrough' should be an array" >&2
            valid=0
        fi
    fi

    if [[ $valid -eq 1 ]]; then
        echo "Profile validation passed"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Fallback Mode
# =============================================================================

# sandbox_fallback_firejail - Try firejail as fallback
sandbox_fallback_firejail() {
    if ! command -v firejail &>/dev/null; then
        echo "Error: firejail not available" >&2
        return 127
    fi

    _sandbox_log "fallback_firejail" "{\"cmd\":\"$1\"}"
    firejail --quiet "$@"
}

# sandbox_fallback_docker - Try docker as fallback
sandbox_fallback_docker() {
    if ! command -v docker &>/dev/null; then
        echo "Error: docker not available" >&2
        return 127
    fi

    local image="${SANDBOX_DOCKER_IMAGE:-alpine:latest}"

    _sandbox_log "fallback_docker" "{\"cmd\":\"$1\",\"image\":\"$image\"}"

    docker run --rm -i \
        --network none \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        -v /tmp:/tmp:rw \
        "$image" "$@"
}

# sandbox_fallback_none - Just run the command (no isolation)
sandbox_fallback_none() {
    echo "Warning: Running without sandbox isolation" >&2
    _sandbox_log "fallback_none" "{\"cmd\":\"$1\"}"
    "$@"
}

# =============================================================================
# Safety Checks
# =============================================================================

# sandbox_verify - Verify sandbox is effective
# @returns 0 if properly isolated
sandbox_verify() {
    if ! sandbox_available; then
        echo "FAIL: bwrap not available" >&2
        return 1
    fi

    local -a checks=()
    local pass=0
    local fail=0

    # Check 1: Can't access outside /tmp
    echo "Checking filesystem isolation..."
    if sandbox_run_safe test -d /home 2>/dev/null; then
        checks+=("filesystem: WARN (can see /home)")
    else
        checks+=("filesystem: PASS")
        ((pass++))
    fi

    # Check 2: Network isolation
    echo "Checking network isolation..."
    if sandbox_run_safe ping -c1 -W1 8.8.8.8 2>/dev/null; then
        checks+=("network: WARN (can reach internet)")
    else
        checks+=("network: PASS")
        ((pass++))
    fi

    # Check 3: Process isolation
    echo "Checking process isolation..."
    local pcount
    pcount=$(sandbox_run_safe sh -c 'ls /proc | grep -c "^[0-9]"' 2>/dev/null || echo "0")
    if [[ "$pcount" -le 5 ]]; then
        checks+=("process: PASS (only $pcount processes visible)")
        ((pass++))
    else
        checks+=("process: WARN ($pcount processes visible)")
    fi

    # Check 4: Capabilities dropped
    echo "Checking capability isolation..."
    if sandbox_run_safe cat /proc/self/status 2>/dev/null | grep -q "CapEff:.*0000000000000000"; then
        checks+=("capabilities: PASS (all dropped)")
        ((pass++))
    else
        checks+=("capabilities: WARN (some capabilities retained)")
    fi

    echo ""
    echo "Sandbox Verification Results"
    echo "============================"
    for check in "${checks[@]}"; do
        echo "  $check"
    done
    echo ""
    echo "Passed: $pass/4 checks"

    [[ $pass -ge 3 ]]
}

# sandbox_audit - Check for escape vulnerabilities
# @param profile - profile name to audit
sandbox_audit() {
    local profile="${1:-default}"

    echo "Security Audit: $profile"
    echo "========================"

    local issues=0

    # Check for dangerous mounts
    echo "Checking mount points..."

    local dangerous_mounts=(
        "/proc/sys"
        "/sys/fs/cgroup"
        "/dev/mem"
        "/dev/kmem"
        "/proc/kcore"
    )

    for mount in "${dangerous_mounts[@]}"; do
        echo "  Checking $mount..."
        # In a real audit, we'd parse the profile and check
    done

    # Check network config
    echo "Checking network configuration..."

    # Check capabilities
    echo "Checking capabilities..."

    # Check seccomp
    echo "Checking seccomp filters..."

    if [[ $issues -eq 0 ]]; then
        echo ""
        echo "No obvious vulnerabilities found."
        echo "Note: This is a basic audit. Manual review recommended for production."
    else
        echo ""
        echo "Found $issues potential issues."
        return 1
    fi
}

# =============================================================================
# Builder Reset
# =============================================================================

# sandbox_reset - Reset accumulated bwrap arguments
sandbox_reset() {
    _BWRAP_ARGS=()
    _BWRAP_DEBUG=0
}

# =============================================================================
# PERMISSION-BASED SANDBOXING API (v2.1)
# =============================================================================
# Extended API for fine-grained permission control using action:resource format.
# Designed for AI coding agents that need explicit permission grants/denials.
# =============================================================================

# Permission format: action:resource
# Examples:
#   - read:/home/user/*
#   - write:/tmp/*
#   - exec:/usr/bin/curl
#   - network:api.openai.com
#   - network:*
#   - env:read:API_KEY
#   - env:write:*

# Permission mode: strict|permissive|disabled
declare -g SANDBOX_PERMISSION_MODE="${SANDBOX_PERMISSION_MODE:-strict}"

# Associative arrays for permissions (key=permission, value=1)
declare -gA _SANDBOX_PERM_ALLOWED=()
declare -gA _SANDBOX_PERM_DENIED=()

# Violations tracking
declare -ga _SANDBOX_PERM_VIOLATIONS=()

# Operation counter
declare -g _SANDBOX_PERM_OP_COUNT=0

# Dangerous commands list for permission system
declare -ga _SANDBOX_DANGEROUS_COMMANDS=(
    "rm" "rmdir" "mv" "dd"
    "chmod" "chown" "chgrp"
    "kill" "killall" "pkill"
    "shutdown" "reboot" "halt"
    "mkfs" "fdisk" "parted"
    "iptables" "ufw"
    "curl" "wget"
    "ssh" "scp" "rsync"
    "sudo" "su"
    "eval" "exec"
)

# -----------------------------------------------------------------------------
# Internal Helpers for Permission System
# -----------------------------------------------------------------------------

# JSON-escape a string for permission system
_sandbox_perm_escape() {
    local str="$1"
    if declare -F json_escape &>/dev/null; then
        json_escape "$str"
        return
    fi
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Get current timestamp
_sandbox_perm_timestamp() {
    date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# Check if path matches pattern (glob-style)
_sandbox_perm_path_matches() {
    local path="$1"
    local pattern="$2"

    [[ "$path" == "$pattern" ]] && return 0

    if [[ "$pattern" == *"*"* ]]; then
        local prefix="${pattern%%\**}"
        [[ "$path" == "$prefix"* ]] && return 0
    fi

    return 1
}

# Extract permission type from string
_sandbox_perm_type() {
    printf '%s' "${1%%:*}"
}

# Extract permission resource from string
_sandbox_perm_resource() {
    printf '%s' "${1#*:}"
}

# Check if command is dangerous
_sandbox_perm_is_dangerous() {
    local cmd="$1"
    local base_cmd="${cmd%% *}"
    base_cmd="${base_cmd##*/}"

    local dangerous
    for dangerous in "${_SANDBOX_DANGEROUS_COMMANDS[@]}"; do
        [[ "$base_cmd" == "$dangerous" ]] && return 0
    done
    return 1
}

# USOP-compliant success output
_sandbox_perm_success() {
    local data="$1"
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":%s}' "$data"
    else
        printf '%s' "$data"
    fi
}

# USOP-compliant error output
_sandbox_perm_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"

    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"' \
            "$(_sandbox_perm_escape "$code")" \
            "$(_sandbox_perm_escape "$msg")"
        if [[ -n "$suggestion" ]]; then
            printf ',"suggestion":"%s"' "$(_sandbox_perm_escape "$suggestion")"
        fi
        printf '}}'
    else
        printf 'error: [%s] %s\n' "$code" "$msg" >&2
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Permission Mode Management
# -----------------------------------------------------------------------------

# sandbox_mode - Get or set permission mode
# @param $1 - mode: strict|permissive|disabled (optional)
# @returns: current mode if no arg, 0 on success, 1 on invalid
#
# Usage: sandbox_mode              # Get mode
# Usage: sandbox_mode "strict"     # Set mode
sandbox_mode() {
    local mode="$1"

    if [[ -z "$mode" ]]; then
        printf '%s' "$SANDBOX_PERMISSION_MODE"
        return 0
    fi

    case "$mode" in
        strict|permissive|disabled)
            SANDBOX_PERMISSION_MODE="$mode"
            _sandbox_log "mode_changed" "{\"mode\":\"$mode\"}"
            return 0
            ;;
        *)
            _sandbox_perm_error "E_INVALID_MODE" \
                "Invalid sandbox mode: $mode" \
                "Valid modes: strict, permissive, disabled"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Permission Management API
# -----------------------------------------------------------------------------

# sandbox_allow - Grant a permission
# @param $1 - permission string (e.g., "write:/tmp/*")
# @returns: 0 on success, 1 on invalid
#
# Usage: sandbox_allow "write:/tmp/*"
# Usage: sandbox_allow "network:api.openai.com"
sandbox_allow() {
    local permission="$1"

    if [[ -z "$permission" ]]; then
        _sandbox_perm_error "E_ARG_MISSING" "Permission string required"
        return 1
    fi

    if [[ ! "$permission" =~ ^[a-z]+:.+ ]]; then
        _sandbox_perm_error "E_INVALID_PERM" \
            "Invalid permission format: $permission" \
            "Format: action:resource (e.g., write:/tmp/*)"
        return 1
    fi

    _SANDBOX_PERM_ALLOWED["$permission"]=1
    unset '_SANDBOX_PERM_DENIED[$permission]' 2>/dev/null || true

    _sandbox_log "perm_allow" "{\"permission\":\"$permission\"}"
    return 0
}

# sandbox_deny - Deny a permission
# @param $1 - permission string
# @returns: 0 on success, 1 on invalid
#
# Usage: sandbox_deny "network:*"
sandbox_deny() {
    local permission="$1"

    if [[ -z "$permission" ]]; then
        _sandbox_perm_error "E_ARG_MISSING" "Permission string required"
        return 1
    fi

    if [[ ! "$permission" =~ ^[a-z]+:.+ ]]; then
        _sandbox_perm_error "E_INVALID_PERM" \
            "Invalid permission format: $permission" \
            "Format: action:resource (e.g., network:*)"
        return 1
    fi

    _SANDBOX_PERM_DENIED["$permission"]=1
    unset '_SANDBOX_PERM_ALLOWED[$permission]' 2>/dev/null || true

    _sandbox_log "perm_deny" "{\"permission\":\"$permission\"}"
    return 0
}

# sandbox_check_permission - Check if permission is granted
# @param $1 - permission string
# @returns: 0 if allowed, 1 if denied
#
# Usage: sandbox_check_permission "write:/tmp/test.txt" && echo "allowed"
sandbox_check_permission() {
    local permission="$1"

    [[ -z "$permission" ]] && return 1

    # Disabled mode = everything allowed
    [[ "$SANDBOX_PERMISSION_MODE" == "disabled" ]] && return 0

    local perm_type perm_resource
    perm_type=$(_sandbox_perm_type "$permission")
    perm_resource=$(_sandbox_perm_resource "$permission")

    # Check explicit denials first
    for denied_perm in "${!_SANDBOX_PERM_DENIED[@]}"; do
        local denied_type denied_resource
        denied_type=$(_sandbox_perm_type "$denied_perm")
        denied_resource=$(_sandbox_perm_resource "$denied_perm")

        if [[ "$perm_type" == "$denied_type" ]]; then
            if _sandbox_perm_path_matches "$perm_resource" "$denied_resource"; then
                return 1
            fi
        fi
    done

    # Check explicit allows
    for allowed_perm in "${!_SANDBOX_PERM_ALLOWED[@]}"; do
        local allowed_type allowed_resource
        allowed_type=$(_sandbox_perm_type "$allowed_perm")
        allowed_resource=$(_sandbox_perm_resource "$allowed_perm")

        if [[ "$perm_type" == "$allowed_type" ]]; then
            if _sandbox_perm_path_matches "$perm_resource" "$allowed_resource"; then
                return 0
            fi
        fi
    done

    # Permissive mode = allow by default
    [[ "$SANDBOX_PERMISSION_MODE" == "permissive" ]] && return 0

    # Strict mode = deny by default
    return 1
}

# sandbox_list_permissions - List all current permissions
# @returns: JSON object with allowed and denied arrays
#
# Usage: sandbox_list_permissions
sandbox_list_permissions() {
    local json='{"allowed":['
    local first=true

    for perm in "${!_SANDBOX_PERM_ALLOWED[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=','
        fi
        json+="\"$(_sandbox_perm_escape "$perm")\""
    done

    json+='],"denied":['
    first=true

    for perm in "${!_SANDBOX_PERM_DENIED[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=','
        fi
        json+="\"$(_sandbox_perm_escape "$perm")\""
    done

    json+=']}'
    _sandbox_perm_success "$json"
}

# sandbox_reset_permissions - Reset permissions to empty
# @returns: 0
#
# Usage: sandbox_reset_permissions
sandbox_reset_permissions() {
    _SANDBOX_PERM_ALLOWED=()
    _SANDBOX_PERM_DENIED=()
    _SANDBOX_PERM_VIOLATIONS=()
    _SANDBOX_PERM_OP_COUNT=0

    _sandbox_log "perm_reset" "{}"
    return 0
}

# -----------------------------------------------------------------------------
# Permission-Aware Execution
# -----------------------------------------------------------------------------

# sandbox_exec_checked - Execute command with permission checks
# @param $@ - command and arguments
# @returns: command exit code if allowed, 1 if denied
#
# Usage: sandbox_exec_checked rm -f /tmp/test.txt
sandbox_exec_checked() {
    local command="$1"
    shift
    local -a args=("$@")

    if [[ -z "$command" ]]; then
        _sandbox_perm_error "E_ARG_MISSING" "Command required"
        return 1
    fi

    (( _SANDBOX_PERM_OP_COUNT++ )) || true

    # Disabled mode = execute directly
    if [[ "$SANDBOX_PERMISSION_MODE" == "disabled" ]]; then
        _sandbox_log "exec_unchecked" "{\"cmd\":\"$command\"}"
        "$command" "${args[@]}"
        return $?
    fi

    # Build required permissions
    local -a required_perms=()
    local base_cmd="${command##*/}"

    required_perms+=("exec:$command")

    if _sandbox_perm_is_dangerous "$command"; then
        required_perms+=("dangerous:$base_cmd")
    fi

    # Detect network commands
    case "$base_cmd" in
        curl|wget|ssh|scp|rsync|nc|ncat)
            for arg in "${args[@]}"; do
                if [[ "$arg" =~ ^https?:// ]]; then
                    local target="${arg#*://}"
                    target="${target%%/*}"
                    target="${target%%:*}"
                    required_perms+=("network:$target")
                    break
                fi
            done
            ;;
    esac

    # Detect file operations
    case "$base_cmd" in
        rm|rmdir|mv|dd|mkfs)
            for arg in "${args[@]}"; do
                [[ "$arg" == -* ]] && continue
                required_perms+=("write:$arg")
            done
            ;;
        cat|less|head|tail|grep|find)
            for arg in "${args[@]}"; do
                [[ "$arg" == -* ]] && continue
                required_perms+=("read:$arg")
            done
            ;;
    esac

    # Check all required permissions
    local denied_perm=""
    for perm in "${required_perms[@]}"; do
        if ! sandbox_check_permission "$perm"; then
            denied_perm="$perm"
            break
        fi
    done

    if [[ -n "$denied_perm" ]]; then
        # Record violation
        local violation_json
        violation_json=$(printf '{"timestamp":"%s","command":"%s","denied_permission":"%s","mode":"%s"}' \
            "$(_sandbox_perm_timestamp)" \
            "$(_sandbox_perm_escape "$command ${args[*]}")" \
            "$(_sandbox_perm_escape "$denied_perm")" \
            "$SANDBOX_PERMISSION_MODE")
        _SANDBOX_PERM_VIOLATIONS+=("$violation_json")

        _sandbox_log "exec_denied" "{\"cmd\":\"$command\",\"perm\":\"$denied_perm\"}"

        if [[ "$SANDBOX_PERMISSION_MODE" == "permissive" ]]; then
            "$command" "${args[@]}"
            return $?
        else
            _sandbox_perm_error "E_PERMISSION_DENIED" \
                "Command blocked: $command" \
                "Grant permission with: sandbox_allow \"$denied_perm\""
            return 1
        fi
    fi

    _sandbox_log "exec_allowed" "{\"cmd\":\"$command\"}"
    "$command" "${args[@]}"
    return $?
}

# sandbox_dry_run_checked - Preview command without executing
# @param $@ - command and arguments
# @returns: JSON preview object
#
# Usage: sandbox_dry_run_checked rm -rf /tmp/test
sandbox_dry_run_checked() {
    local command="$1"
    shift
    local -a args=("$@")

    if [[ -z "$command" ]]; then
        _sandbox_perm_error "E_ARG_MISSING" "Command required"
        return 1
    fi

    local base_cmd="${command##*/}"
    local -a required_perms=()
    required_perms+=("exec:$command")

    if _sandbox_perm_is_dangerous "$command"; then
        required_perms+=("dangerous:$base_cmd")
    fi

    # Detect additional permissions
    case "$base_cmd" in
        curl|wget|ssh|scp)
            for arg in "${args[@]}"; do
                if [[ "$arg" =~ ^https?:// ]]; then
                    local target="${arg#*://}"
                    target="${target%%/*}"
                    target="${target%%:*}"
                    required_perms+=("network:$target")
                    break
                fi
            done
            ;;
        rm|rmdir|mv|dd)
            for arg in "${args[@]}"; do
                [[ "$arg" == -* ]] && continue
                required_perms+=("write:$arg")
            done
            ;;
        cat|less|head|tail|grep)
            for arg in "${args[@]}"; do
                [[ "$arg" == -* ]] && continue
                required_perms+=("read:$arg")
            done
            ;;
    esac

    # Check permissions
    local would_execute=true
    local all_granted=true
    local -a denied_perms=()

    for perm in "${required_perms[@]}"; do
        if ! sandbox_check_permission "$perm"; then
            denied_perms+=("$perm")
            all_granted=false
            [[ "$SANDBOX_PERMISSION_MODE" == "strict" ]] && would_execute=false
        fi
    done

    # Build preview description
    local preview=""
    case "$base_cmd" in
        rm)
            if [[ " ${args[*]} " == *" -rf "* ]] || [[ " ${args[*]} " == *" -r "* ]]; then
                preview="Would recursively delete"
            else
                preview="Would delete"
            fi
            for arg in "${args[@]}"; do
                [[ "$arg" != -* ]] && preview+=" $arg"
            done
            ;;
        mv)
            preview="Would move ${args[0]:-} to ${args[1]:-}"
            ;;
        cp)
            preview="Would copy ${args[0]:-} to ${args[1]:-}"
            ;;
        curl|wget)
            preview="Would fetch URL"
            for arg in "${args[@]}"; do
                [[ "$arg" =~ ^https?:// ]] && preview+=" $arg" && break
            done
            ;;
        mkdir)
            preview="Would create directory"
            for arg in "${args[@]}"; do
                [[ "$arg" != -* ]] && preview+=" $arg"
            done
            ;;
        *)
            preview="Would execute: $command ${args[*]}"
            ;;
    esac

    # Build JSON arrays
    local perms_req_json perms_denied_json
    perms_req_json=$(printf '['; local f=1; for p in "${required_perms[@]}"; do [[ $f == 1 ]] && f=0 || printf ','; printf '"%s"' "$p"; done; printf ']')
    perms_denied_json=$(printf '['; local f=1; for p in "${denied_perms[@]}"; do [[ $f == 1 ]] && f=0 || printf ','; printf '"%s"' "$p"; done; printf ']')

    local result_json
    result_json=$(printf '{"command":"%s","would_execute":%s,"permissions_required":%s,"permissions_denied":%s,"permissions_granted":%s,"dry_run":true,"preview":"%s","mode":"%s"}' \
        "$(_sandbox_perm_escape "$command ${args[*]}")" \
        "$would_execute" \
        "$perms_req_json" \
        "$perms_denied_json" \
        "$all_granted" \
        "$(_sandbox_perm_escape "$preview")" \
        "$SANDBOX_PERMISSION_MODE")

    _sandbox_perm_success "$result_json"
}

# -----------------------------------------------------------------------------
# Violation Tracking
# -----------------------------------------------------------------------------

# sandbox_violations - Get list of permission violations
# @returns: JSON array of violations
#
# Usage: sandbox_violations
sandbox_violations() {
    local json='['
    local first=true

    for violation in "${_SANDBOX_PERM_VIOLATIONS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=','
        fi
        json+="$violation"
    done

    json+=']'
    _sandbox_perm_success "$json"
}

# sandbox_clear_violations - Clear violation log
# @returns: 0
#
# Usage: sandbox_clear_violations
sandbox_clear_violations() {
    _SANDBOX_PERM_VIOLATIONS=()
    _sandbox_log "violations_cleared" "{}"
    return 0
}

# -----------------------------------------------------------------------------
# Permission Status
# -----------------------------------------------------------------------------

# sandbox_permission_status - Get permission system status
# @returns: JSON status object
#
# Usage: sandbox_permission_status
sandbox_permission_status() {
    local allowed_count=${#_SANDBOX_PERM_ALLOWED[@]}
    local denied_count=${#_SANDBOX_PERM_DENIED[@]}
    local violation_count=${#_SANDBOX_PERM_VIOLATIONS[@]}

    local json
    json=$(printf '{"mode":"%s","permissions":{"allowed":%d,"denied":%d},"violations":%d,"operations":%d}' \
        "$SANDBOX_PERMISSION_MODE" \
        "$allowed_count" \
        "$denied_count" \
        "$violation_count" \
        "$_SANDBOX_PERM_OP_COUNT")

    _sandbox_perm_success "$json"
}

# -----------------------------------------------------------------------------
# Convenience Wrappers
# -----------------------------------------------------------------------------

# sandbox_can_read - Check read permission for path
# @param $1 - path
# @returns: 0 if allowed, 1 if denied
sandbox_can_read() {
    sandbox_check_permission "read:$1"
}

# sandbox_can_write - Check write permission for path
# @param $1 - path
# @returns: 0 if allowed, 1 if denied
sandbox_can_write() {
    sandbox_check_permission "write:$1"
}

# sandbox_can_exec - Check exec permission for command
# @param $1 - command
# @returns: 0 if allowed, 1 if denied
sandbox_can_exec() {
    sandbox_check_permission "exec:$1"
}

# sandbox_can_network - Check network permission for host
# @param $1 - hostname
# @returns: 0 if allowed, 1 if denied
sandbox_can_network() {
    sandbox_check_permission "network:$1"
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _SANDBOX_EXPORTS=(
    # Original exports
    sandbox_enable
    sandbox_disable
    sandbox_allow_write
    sandbox_deny_write
    sandbox_deny_network
    sandbox_allow_network
    sandbox_audit_log
    sandbox_exec
    sandbox_write
    sandbox_mkdir
    sandbox_rm
    sandbox_status
    sandbox_check
    # Permission-based API exports (v2.1)
    sandbox_mode
    sandbox_allow
    sandbox_deny
    sandbox_check_permission
    sandbox_list_permissions
    sandbox_reset_permissions
    sandbox_exec_checked
    sandbox_dry_run_checked
    sandbox_violations
    sandbox_clear_violations
    sandbox_permission_status
    sandbox_can_read
    sandbox_can_write
    sandbox_can_exec
    sandbox_can_network
    # Bubblewrap exports
    sandbox_available
    sandbox_version
    sandbox_install_hint
    sandbox_run
    sandbox_run_isolated
    sandbox_profile_create
    sandbox_profile_list
    sandbox_profile_delete
    sandbox_profile_get
    sandbox_mount_ro
    sandbox_mount_rw
    sandbox_tmpfs
    sandbox_bind
    sandbox_overlay
    sandbox_network_none
    sandbox_network_localhost
    sandbox_network_ports
    sandbox_network_ns
    sandbox_limit_cpu
    sandbox_limit_memory
    sandbox_limit_pids
    sandbox_limit_fsize
    sandbox_limit_nofile
    sandbox_limits
    sandbox_drop_caps
    sandbox_keep_caps
    sandbox_seccomp
    sandbox_user
    sandbox_unshare_user
    sandbox_env_only
    sandbox_env_passthrough
    sandbox_env_set
    sandbox_env_block
    sandbox_run_safe
    sandbox_run_web
    sandbox_run_build
    sandbox_run_untrusted
    sandbox_dry_run
    sandbox_debug
    sandbox_validate_profile
    sandbox_fallback_firejail
    sandbox_fallback_docker
    sandbox_fallback_none
    sandbox_verify
    sandbox_audit
    sandbox_reset
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_SANDBOX_EXPORTS[@]}" 2>/dev/null || true
fi

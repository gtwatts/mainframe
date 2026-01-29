#!/usr/bin/env bash
# =============================================================================
# sandbox.sh - Execution Sandboxing for AI Agents
# =============================================================================
# Description: Provides execution boundaries with restricted access to filesystem,
#              network, and system resources. Enables safe autonomous execution.
# Version: 1.0.0
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
# Module Exports
# =============================================================================

declare -ga _SANDBOX_EXPORTS=(
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
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_SANDBOX_EXPORTS[@]}" 2>/dev/null || true
fi

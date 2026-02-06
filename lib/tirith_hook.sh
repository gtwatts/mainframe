#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith_hook.sh - Shell Preexec Hook for Tirith
# =============================================================================
# Description: Installs a bash DEBUG trap that intercepts commands before
#              execution, running tirith security scans. Chains with existing
#              DEBUG traps rather than replacing them. Supports bypass via
#              TIRITH=0 prefix.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_HOOK_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_HOOK_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Track whether the hook is active
declare -g _TIRITH_HOOK_ACTIVE=0

# Store original DEBUG trap for chaining
declare -g _TIRITH_ORIGINAL_DEBUG_TRAP=""

# Builtins and trivial commands to skip (no security risk)
readonly _TIRITH_SKIP_CMDS="^(cd|pwd|echo|printf|type|which|alias|unalias|export|local|declare|readonly|set|unset|shopt|enable|help|history|fc|bg|fg|jobs|wait|disown|kill|trap|true|false|:|return|exit|break|continue|shift|getopts|read|mapfile|readarray|source|\\.)[[:space:]]*"

# =============================================================================
# DEBUG TRAP HANDLER
# =============================================================================

# _tirith_preexec_handler
# Called by the DEBUG trap before each command execution.
# Scans the command for security issues and blocks/warns as configured.
_tirith_preexec_handler() {
    # Skip if hook is disabled
    (( _TIRITH_HOOK_ACTIVE == 0 )) && return 0

    # Get the command about to execute
    local cmd="${BASH_COMMAND:-}"
    [[ -z "$cmd" ]] && return 0

    # Check for TIRITH=0 bypass prefix
    if [[ "$cmd" == "TIRITH=0 "* ]]; then
        return 0
    fi

    # Skip builtins and trivial commands
    if [[ "$cmd" =~ $_TIRITH_SKIP_CMDS ]]; then
        return 0
    fi

    # Skip if we're inside a function call from tirith itself (prevent recursion)
    local caller_func="${FUNCNAME[1]:-}"
    if [[ "$caller_func" == tirith_* ]] || [[ "$caller_func" == _tirith_* ]]; then
        return 0
    fi

    # Clear previous findings before scanning
    tirith_clear 2>/dev/null

    # Run the full scan
    tirith_scan_command "$cmd" "preexec" 2>/dev/null || true

    # Check if we have findings
    if ! tirith_has_findings 2>/dev/null; then
        return 0
    fi

    # Log to audit
    local action="allowed"

    # Determine action based on severity and fail mode
    if tirith_should_block 2>/dev/null; then
        action="blocked"

        # Print findings report
        tirith_report 2>/dev/null

        # Block the command
        printf 'Tirith: Command blocked due to security findings.\n' >&2
        printf 'Tirith: Use TIRITH=0 %s to bypass.\n' "$cmd" >&2

        tirith_audit_log "$cmd" "blocked" 2>/dev/null

        # Return non-zero to prevent execution
        return 1
    fi

    # HIGH findings in open mode: warn but allow
    if tirith_has_findings "high" 2>/dev/null; then
        action="warned"
        tirith_report 2>/dev/null
        printf 'Tirith: Proceeding despite warnings (fail_mode=open).\n' >&2
    fi

    tirith_audit_log "$cmd" "$action" 2>/dev/null

    return 0
}

# =============================================================================
# HOOK MANAGEMENT
# =============================================================================

# tirith_hook_install
# Install the tirith preexec hook using the bash DEBUG trap.
# Chains with any existing DEBUG trap rather than replacing it.
tirith_hook_install() {
    if (( _TIRITH_HOOK_ACTIVE )); then
        printf 'Tirith hook already installed.\n' >&2
        return 0
    fi

    # Initialize tirith subsystem
    tirith_init 2>/dev/null

    # Save existing DEBUG trap for chaining
    _TIRITH_ORIGINAL_DEBUG_TRAP=$(trap -p DEBUG 2>/dev/null || true)

    # Install our handler
    # shellcheck disable=SC2064
    if [[ -n "$_TIRITH_ORIGINAL_DEBUG_TRAP" ]]; then
        # Chain: run original trap first, then our handler
        local original_cmd="${_TIRITH_ORIGINAL_DEBUG_TRAP#trap -- }"
        original_cmd="${original_cmd% DEBUG}"
        # Remove surrounding quotes if present
        original_cmd="${original_cmd#\'}"
        original_cmd="${original_cmd%\'}"

        trap "${original_cmd}; _tirith_preexec_handler" DEBUG
    else
        trap '_tirith_preexec_handler' DEBUG
    fi

    _TIRITH_HOOK_ACTIVE=1
    printf 'Tirith hook installed (fail_mode=%s).\n' "$TIRITH_FAIL_MODE" >&2
}

# tirith_hook_uninstall
# Remove the tirith preexec hook and restore the original DEBUG trap.
tirith_hook_uninstall() {
    if (( ! _TIRITH_HOOK_ACTIVE )); then
        printf 'Tirith hook not installed.\n' >&2
        return 0
    fi

    # Restore original trap
    if [[ -n "$_TIRITH_ORIGINAL_DEBUG_TRAP" ]]; then
        eval "$_TIRITH_ORIGINAL_DEBUG_TRAP" 2>/dev/null || trap - DEBUG
        _TIRITH_ORIGINAL_DEBUG_TRAP=""
    else
        trap - DEBUG
    fi

    _TIRITH_HOOK_ACTIVE=0
    printf 'Tirith hook uninstalled.\n' >&2
}

# tirith_hook_status
# Print the current hook status.
tirith_hook_status() {
    if (( _TIRITH_HOOK_ACTIVE )); then
        printf 'Tirith hook: active (fail_mode=%s)\n' "$TIRITH_FAIL_MODE"
    else
        printf 'Tirith hook: inactive\n'
    fi

    if [[ -n "$_TIRITH_ORIGINAL_DEBUG_TRAP" ]]; then
        printf 'Chained DEBUG trap: %s\n' "$_TIRITH_ORIGINAL_DEBUG_TRAP"
    fi

    printf 'Audit log: %s\n' "${TIRITH_AUDIT_LOG:-disabled}"

    if (( ${#_TIRITH_ALLOWLIST[@]} > 0 )); then
        printf 'Allowlist: %d entries\n' "${#_TIRITH_ALLOWLIST[@]}"
    fi
    if (( ${#_TIRITH_BLOCKLIST[@]} > 0 )); then
        printf 'Blocklist: %d entries\n' "${#_TIRITH_BLOCKLIST[@]}"
    fi
}

# tirith_hook_toggle
# Toggle the hook on/off without installing/uninstalling the trap.
tirith_hook_toggle() {
    if (( _TIRITH_HOOK_ACTIVE )); then
        _TIRITH_HOOK_ACTIVE=0
        printf 'Tirith hook paused.\n' >&2
    else
        _TIRITH_HOOK_ACTIVE=1
        printf 'Tirith hook resumed.\n' >&2
    fi
}

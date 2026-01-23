#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/safewrap.sh - Transparent Command Wrapping Safety Pipeline
# =============================================================================
# Description: Provides a transparent safety pipeline that wraps command execution
#              with scope checking, risk scoring, limit enforcement, and confirmation
#              gates. Integrates with scope.sh, risk.sh, limits.sh, and confirm.sh
#              when available, gracefully degrading when modules are absent.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SAFEWRAP_LOADED:-}" ]] && return 0
_MAINFRAME_SAFEWRAP_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Global enable/disable toggle
declare -g _MAINFRAME_WRAP_ENABLED=0

# Policy level: strict, moderate, permissive
declare -g _MAINFRAME_WRAP_POLICY="moderate"

# Policy thresholds (risk score at which action is taken)
declare -g _MAINFRAME_WRAP_BLOCK_THRESHOLD_STRICT=4
declare -g _MAINFRAME_WRAP_BLOCK_THRESHOLD_MODERATE=6
declare -g _MAINFRAME_WRAP_BLOCK_THRESHOLD_PERMISSIVE=8

declare -g _MAINFRAME_WRAP_CONFIRM_THRESHOLD_STRICT=2
declare -g _MAINFRAME_WRAP_CONFIRM_THRESHOLD_MODERATE=5
declare -g _MAINFRAME_WRAP_CONFIRM_THRESHOLD_PERMISSIVE=7

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Registered custom wrappers: associative array of CMD -> FUNCTION_NAME
declare -gA _MAINFRAME_WRAP_REGISTRY=()

# Execution log: indexed array of JSON entries
declare -ga _MAINFRAME_WRAP_LOG=()

# Statistics counters
declare -g _MAINFRAME_WRAP_STATS_TOTAL=0
declare -g _MAINFRAME_WRAP_STATS_EXECUTED=0
declare -g _MAINFRAME_WRAP_STATS_BLOCKED=0
declare -g _MAINFRAME_WRAP_STATS_BYPASSED=0
declare -g _MAINFRAME_WRAP_STATS_CONFIRMED=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_wrap_escape() {
    local str="$1"
    if type -t json_escape &>/dev/null; then
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

# Get current timestamp in ISO-8601 format
_wrap_timestamp() {
    if type -t now_iso &>/dev/null; then
        now_iso
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '%d' "$(date +%s 2>/dev/null || printf '0')"
    fi
}

# Build a JSON array from bash array arguments
_wrap_json_array() {
    local result="["
    local first=true
    local item
    for item in "$@"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="\"$(_wrap_escape "$item")\""
    done
    result+="]"
    printf '%s' "$result"
}

# Get the block threshold for current policy
_wrap_block_threshold() {
    case "$_MAINFRAME_WRAP_POLICY" in
        strict)     printf '%d' "$_MAINFRAME_WRAP_BLOCK_THRESHOLD_STRICT" ;;
        moderate)   printf '%d' "$_MAINFRAME_WRAP_BLOCK_THRESHOLD_MODERATE" ;;
        permissive) printf '%d' "$_MAINFRAME_WRAP_BLOCK_THRESHOLD_PERMISSIVE" ;;
        *)          printf '%d' "$_MAINFRAME_WRAP_BLOCK_THRESHOLD_MODERATE" ;;
    esac
}

# Get the confirm threshold for current policy
_wrap_confirm_threshold() {
    case "$_MAINFRAME_WRAP_POLICY" in
        strict)     printf '%d' "$_MAINFRAME_WRAP_CONFIRM_THRESHOLD_STRICT" ;;
        moderate)   printf '%d' "$_MAINFRAME_WRAP_CONFIRM_THRESHOLD_MODERATE" ;;
        permissive) printf '%d' "$_MAINFRAME_WRAP_CONFIRM_THRESHOLD_PERMISSIVE" ;;
        *)          printf '%d' "$_MAINFRAME_WRAP_CONFIRM_THRESHOLD_MODERATE" ;;
    esac
}

# Append a log entry
_wrap_add_log() {
    local cmd="$1"
    local decision="$2"
    local risk_score="$3"
    local exit_code="$4"
    shift 4
    local -a args=("$@")

    local ts
    ts=$(_wrap_timestamp)

    local args_json
    args_json=$(_wrap_json_array "${args[@]}")

    local escaped_cmd
    escaped_cmd=$(_wrap_escape "$cmd")

    local entry
    entry=$(printf '{"timestamp":"%s","command":"%s","args":%s,"risk_score":%d,"decision":"%s","exit_code":%d}' \
        "$ts" "$escaped_cmd" "$args_json" "$risk_score" "$decision" "$exit_code")

    _MAINFRAME_WRAP_LOG+=("$entry")
}

# Increment a stats counter safely
_wrap_inc_total() {
    _MAINFRAME_WRAP_STATS_TOTAL=$(( _MAINFRAME_WRAP_STATS_TOTAL + 1 ))
}

_wrap_inc_executed() {
    _MAINFRAME_WRAP_STATS_EXECUTED=$(( _MAINFRAME_WRAP_STATS_EXECUTED + 1 ))
}

_wrap_inc_blocked() {
    _MAINFRAME_WRAP_STATS_BLOCKED=$(( _MAINFRAME_WRAP_STATS_BLOCKED + 1 ))
}

_wrap_inc_bypassed() {
    _MAINFRAME_WRAP_STATS_BYPASSED=$(( _MAINFRAME_WRAP_STATS_BYPASSED + 1 ))
}

_wrap_inc_confirmed() {
    _MAINFRAME_WRAP_STATS_CONFIRMED=$(( _MAINFRAME_WRAP_STATS_CONFIRMED + 1 ))
}

# Check if a function exists (integration check)
_wrap_has_func() {
    type -t "$1" &>/dev/null
}

# =============================================================================
# PIPELINE STAGES
# =============================================================================

# Stage 1: Scope check
# Returns 0 if allowed, 1 if blocked
_wrap_stage_scope() {
    local cmd="$1"
    shift
    local -a args=("$@")

    # Skip if scope.sh not loaded
    _wrap_has_func mainframe_scope_check || return 0

    # Check command scope
    if ! mainframe_scope_check "commands" "$cmd" 2>/dev/null; then
        return 1
    fi

    # Check filesystem scope for path arguments
    local arg
    for arg in "${args[@]}"; do
        [[ "$arg" == -* ]] && continue
        if [[ "$arg" == /* || "$arg" == ~* || "$arg" == ./* || "$arg" == ../* ]]; then
            if ! mainframe_scope_check "filesystem" "$arg" 2>/dev/null; then
                return 1
            fi
        fi
    done

    return 0
}

# Stage 2: Risk scoring
# Sets _WRAP_CURRENT_RISK_SCORE global
declare -g _WRAP_CURRENT_RISK_SCORE=0

_wrap_stage_risk() {
    local cmd="$1"
    shift

    # Skip if risk.sh not loaded
    if ! _wrap_has_func mainframe_risk_score; then
        _WRAP_CURRENT_RISK_SCORE=0
        return 0
    fi

    # Get risk score (capture stdout, avoid JSON mode interference)
    local saved_output="${MAINFRAME_OUTPUT:-}"
    local saved_risk_json="${MAINFRAME_RISK_JSON:-1}"
    MAINFRAME_OUTPUT=""
    MAINFRAME_RISK_JSON="0"

    _WRAP_CURRENT_RISK_SCORE=$(mainframe_risk_score "$cmd" "$@")

    MAINFRAME_OUTPUT="$saved_output"
    MAINFRAME_RISK_JSON="$saved_risk_json"

    # Check against block threshold
    local threshold
    threshold=$(_wrap_block_threshold)
    if (( _WRAP_CURRENT_RISK_SCORE > threshold )); then
        return 1
    fi

    return 0
}

# Stage 3: Limit check
# Returns 0 if within limits, 1 if exceeded
_wrap_stage_limits() {
    local cmd="$1"
    shift

    # Skip if limits.sh not loaded
    _wrap_has_func mainframe_limit_check || return 0

    if ! mainframe_limit_check "$cmd" "$@" 2>/dev/null; then
        return 1
    fi

    return 0
}

# Stage 4: Confirmation
# Returns 0 if confirmed or not needed, 1 if denied
_wrap_stage_confirm() {
    local cmd="$1"
    shift

    local threshold
    threshold=$(_wrap_confirm_threshold)

    # Only confirm if risk score meets threshold
    if (( _WRAP_CURRENT_RISK_SCORE < threshold )); then
        return 0
    fi

    # Skip if confirm.sh not loaded
    _wrap_has_func mainframe_confirm || return 0

    if ! mainframe_confirm "$cmd" "$@" 2>/dev/null; then
        return 1
    fi

    _wrap_inc_confirmed
    return 0
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: CMD is non-empty
# @post: command executed through safety pipeline or blocked
# @returns: command exit code if executed, 1 if blocked
#
# Run a command through the full safety pipeline:
#   1. Check if wrapping enabled (passthrough if not)
#   2. Check scope (if scope.sh loaded)
#   3. Score risk (if risk.sh loaded)
#   4. Check limits (if limits.sh loaded)
#   5. Confirm if needed (if confirm.sh loaded)
#   6. Execute and log result
#
# Usage: safewrap rm -rf /tmp/test_dir
# Usage: safewrap git push origin main
safewrap() {
    if [[ $# -eq 0 ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_NO_CMD","msg":"No command provided"}}\n' >&2
        fi
        return 1
    fi

    local cmd="$1"
    shift
    local -a args=("$@")

    _wrap_inc_total

    # If wrapping is disabled, passthrough directly
    if [[ "$_MAINFRAME_WRAP_ENABLED" -ne 1 ]]; then
        "$cmd" "${args[@]}"
        local rc=$?
        _wrap_add_log "$cmd" "passthrough" 0 "$rc" "${args[@]}"
        _wrap_inc_executed
        return "$rc"
    fi

    # Check for custom wrapper
    local base_cmd="${cmd##*/}"
    if [[ -n "${_MAINFRAME_WRAP_REGISTRY[$base_cmd]:-}" ]]; then
        local wrapper_func="${_MAINFRAME_WRAP_REGISTRY[$base_cmd]}"
        if _wrap_has_func "$wrapper_func"; then
            "$wrapper_func" "$cmd" "${args[@]}"
            local rc=$?
            _wrap_add_log "$cmd" "custom_wrapper" 0 "$rc" "${args[@]}"
            _wrap_inc_executed
            return "$rc"
        fi
    fi

    # Stage 1: Scope check
    if ! _wrap_stage_scope "$cmd" "${args[@]}"; then
        _wrap_add_log "$cmd" "blocked" "$_WRAP_CURRENT_RISK_SCORE" 1 "${args[@]}"
        _wrap_inc_blocked
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_SCOPE","msg":"Command blocked by scope","command":"%s"}}\n' \
                "$(_wrap_escape "$cmd")" >&2
        fi
        return 1
    fi

    # Stage 2: Risk scoring
    if ! _wrap_stage_risk "$cmd" "${args[@]}"; then
        _wrap_add_log "$cmd" "blocked" "$_WRAP_CURRENT_RISK_SCORE" 1 "${args[@]}"
        _wrap_inc_blocked
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_RISK","msg":"Risk score %d exceeds threshold","command":"%s","score":%d}}\n' \
                "$_WRAP_CURRENT_RISK_SCORE" "$(_wrap_escape "$cmd")" "$_WRAP_CURRENT_RISK_SCORE" >&2
        fi
        return 1
    fi

    # Stage 3: Limit check
    if ! _wrap_stage_limits "$cmd" "${args[@]}"; then
        _wrap_add_log "$cmd" "blocked" "$_WRAP_CURRENT_RISK_SCORE" 1 "${args[@]}"
        _wrap_inc_blocked
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_LIMIT","msg":"Command blocked by limit","command":"%s"}}\n' \
                "$(_wrap_escape "$cmd")" >&2
        fi
        return 1
    fi

    # Stage 4: Confirmation
    if ! _wrap_stage_confirm "$cmd" "${args[@]}"; then
        _wrap_add_log "$cmd" "blocked" "$_WRAP_CURRENT_RISK_SCORE" 1 "${args[@]}"
        _wrap_inc_blocked
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_CONFIRM","msg":"User denied confirmation","command":"%s"}}\n' \
                "$(_wrap_escape "$cmd")" >&2
        fi
        return 1
    fi

    # Stage 5: Execute
    "$cmd" "${args[@]}"
    local rc=$?

    _wrap_add_log "$cmd" "executed" "$_WRAP_CURRENT_RISK_SCORE" "$rc" "${args[@]}"
    _wrap_inc_executed

    return "$rc"
}

# @pre: CMD is non-empty, WRAPPER_FUNC is a valid function name
# @post: custom wrapper registered for CMD
# @returns: 0 on success, 1 on invalid input
#
# Register a custom wrapper function for a specific command.
# The wrapper function receives the full command and arguments.
#
# Usage: safewrap_register "rm" "my_safe_rm"
safewrap_register() {
    local cmd="$1"
    local wrapper_func="$2"

    if [[ -z "$cmd" ]] || [[ -z "$wrapper_func" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_REGISTER","msg":"Command and wrapper function required"}}\n' >&2
        fi
        return 1
    fi

    # Strip path from command for consistent lookup
    local base_cmd="${cmd##*/}"
    _MAINFRAME_WRAP_REGISTRY["$base_cmd"]="$wrapper_func"
    return 0
}

# @pre: CMD is registered
# @post: custom wrapper removed for CMD
# @returns: 0 on success, 1 if not registered
#
# Remove a custom wrapper registration for a command.
#
# Usage: safewrap_unregister "rm"
safewrap_unregister() {
    local cmd="$1"

    if [[ -z "$cmd" ]]; then
        return 1
    fi

    local base_cmd="${cmd##*/}"
    if [[ -z "${_MAINFRAME_WRAP_REGISTRY[$base_cmd]:-}" ]]; then
        return 1
    fi

    unset '_MAINFRAME_WRAP_REGISTRY[$base_cmd]'
    return 0
}

# @pre: none
# @post: safety wrapping enabled globally
# @idempotent: yes
# @returns: 0
#
# Enable the safety wrapping pipeline for all safewrap calls.
#
# Usage: safewrap_enable
safewrap_enable() {
    _MAINFRAME_WRAP_ENABLED=1
    return 0
}

# @pre: none
# @post: safety wrapping disabled (passthrough mode)
# @idempotent: yes
# @returns: 0
#
# Disable the safety wrapping pipeline. Commands pass through directly.
#
# Usage: safewrap_disable
safewrap_disable() {
    _MAINFRAME_WRAP_ENABLED=0
    return 0
}

# @pre: none
# @post: none (read-only check)
# @idempotent: yes
# @returns: 0 if enabled, 1 if disabled
#
# Check if safety wrapping is currently active.
#
# Usage: safewrap_is_enabled && echo "wrapping active"
safewrap_is_enabled() {
    [[ "$_MAINFRAME_WRAP_ENABLED" -eq 1 ]]
}

# @pre: none
# @post: JSON status printed to stdout
# @idempotent: yes
# @returns: 0
#
# Show comprehensive status including enabled state, policy, registered
# wrappers, and execution statistics.
#
# Usage: safewrap_status
safewrap_status() {
    local enabled="false"
    [[ "$_MAINFRAME_WRAP_ENABLED" -eq 1 ]] && enabled="true"

    local block_thresh confirm_thresh
    block_thresh=$(_wrap_block_threshold)
    confirm_thresh=$(_wrap_confirm_threshold)

    # Build registered wrappers JSON object
    local wrappers="{"
    local first=true
    local key
    for key in "${!_MAINFRAME_WRAP_REGISTRY[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            wrappers+=","
        fi
        wrappers+="\"$(_wrap_escape "$key")\":\"$(_wrap_escape "${_MAINFRAME_WRAP_REGISTRY[$key]}")\""
    done
    wrappers+="}"

    # Integration status
    local has_scope="false" has_risk="false" has_limits="false" has_confirm="false"
    _wrap_has_func mainframe_scope_check && has_scope="true"
    _wrap_has_func mainframe_risk_score && has_risk="true"
    _wrap_has_func mainframe_limit_check && has_limits="true"
    _wrap_has_func mainframe_confirm && has_confirm="true"

    local wrapper_count=0
    for key in "${!_MAINFRAME_WRAP_REGISTRY[@]}"; do
        wrapper_count=$(( wrapper_count + 1 ))
    done

    printf '{"enabled":%s,"policy":"%s","block_threshold":%d,"confirm_threshold":%d,"registered_wrappers":%s,"wrapper_count":%d,"integrations":{"scope":%s,"risk":%s,"limits":%s,"confirm":%s},"stats":{"total":%d,"executed":%d,"blocked":%d,"bypassed":%d,"confirmed":%d}}\n' \
        "$enabled" \
        "$_MAINFRAME_WRAP_POLICY" \
        "$block_thresh" \
        "$confirm_thresh" \
        "$wrappers" \
        "$wrapper_count" \
        "$has_scope" \
        "$has_risk" \
        "$has_limits" \
        "$has_confirm" \
        "$_MAINFRAME_WRAP_STATS_TOTAL" \
        "$_MAINFRAME_WRAP_STATS_EXECUTED" \
        "$_MAINFRAME_WRAP_STATS_BLOCKED" \
        "$_MAINFRAME_WRAP_STATS_BYPASSED" \
        "$_MAINFRAME_WRAP_STATS_CONFIRMED"
}

# @pre: none
# @post: execution log printed as JSON array to stdout
# @idempotent: yes
# @returns: 0
#
# Show the execution log as a JSON array of log entries.
# Each entry contains timestamp, command, args, risk_score, decision, exit_code.
#
# Usage: safewrap_log
safewrap_log() {
    local result="["
    local first=true
    local entry

    for entry in "${_MAINFRAME_WRAP_LOG[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="$entry"
    done
    result+="]"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"count":%d}}\n' "$result" "${#_MAINFRAME_WRAP_LOG[@]}"
    else
        printf '%s\n' "$result"
    fi
    return 0
}

# @pre: none
# @post: execution log cleared
# @idempotent: yes
# @returns: 0
#
# Clear the execution log. Statistics are preserved.
#
# Usage: safewrap_clear_log
safewrap_clear_log() {
    _MAINFRAME_WRAP_LOG=()
    return 0
}

# @pre: none
# @post: statistics printed as JSON to stdout
# @idempotent: yes
# @returns: 0
#
# Show execution statistics: total calls, executed, blocked, bypassed, confirmed.
#
# Usage: safewrap_stats
safewrap_stats() {
    local approval_rate=0
    if (( _MAINFRAME_WRAP_STATS_TOTAL > 0 )); then
        approval_rate=$(( (_MAINFRAME_WRAP_STATS_EXECUTED * 100) / _MAINFRAME_WRAP_STATS_TOTAL ))
    fi

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"total":%d,"executed":%d,"blocked":%d,"bypassed":%d,"confirmed":%d,"approval_rate":%d}}\n' \
            "$_MAINFRAME_WRAP_STATS_TOTAL" \
            "$_MAINFRAME_WRAP_STATS_EXECUTED" \
            "$_MAINFRAME_WRAP_STATS_BLOCKED" \
            "$_MAINFRAME_WRAP_STATS_BYPASSED" \
            "$_MAINFRAME_WRAP_STATS_CONFIRMED" \
            "$approval_rate"
    else
        printf '{"total":%d,"executed":%d,"blocked":%d,"bypassed":%d,"confirmed":%d,"approval_rate":%d}\n' \
            "$_MAINFRAME_WRAP_STATS_TOTAL" \
            "$_MAINFRAME_WRAP_STATS_EXECUTED" \
            "$_MAINFRAME_WRAP_STATS_BLOCKED" \
            "$_MAINFRAME_WRAP_STATS_BYPASSED" \
            "$_MAINFRAME_WRAP_STATS_CONFIRMED" \
            "$approval_rate"
    fi
    return 0
}

# @pre: LEVEL is one of: strict, moderate, permissive
# @post: wrapping policy updated
# @returns: 0 on success, 1 on invalid level
#
# Set the wrapping policy level which controls block/confirm thresholds.
#   strict:     block >= 5, confirm >= 3
#   moderate:   block >= 7, confirm >= 5
#   permissive: block >= 9, confirm >= 7
#
# Usage: safewrap_policy strict
# Usage: safewrap_policy permissive
safewrap_policy() {
    local level="${1:-}"

    if [[ -z "$level" ]]; then
        # No arg: report current policy
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":true,"data":{"policy":"%s","block_threshold":%d,"confirm_threshold":%d}}\n' \
                "$_MAINFRAME_WRAP_POLICY" "$(_wrap_block_threshold)" "$(_wrap_confirm_threshold)"
        else
            printf '%s\n' "$_MAINFRAME_WRAP_POLICY"
        fi
        return 0
    fi

    case "$level" in
        strict|moderate|permissive)
            _MAINFRAME_WRAP_POLICY="$level"
            return 0
            ;;
        *)
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_WRAP_POLICY","msg":"Invalid policy level: %s","valid":["strict","moderate","permissive"]}}\n' \
                    "$(_wrap_escape "$level")" >&2
            fi
            return 1
            ;;
    esac
}

# @pre: CMD is non-empty
# @post: command executed bypassing ALL safety checks
# @returns: command exit code
#
# Execute a command bypassing all safety pipeline stages.
# Use as an escape hatch when you know a command is safe.
# Still logged for audit trail.
#
# Usage: safewrap_bypass rm -rf /tmp/build_artifacts
safewrap_bypass() {
    if [[ $# -eq 0 ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WRAP_NO_CMD","msg":"No command provided for bypass"}}\n' >&2
        fi
        return 1
    fi

    local cmd="$1"
    shift
    local -a args=("$@")

    _wrap_inc_total
    _wrap_inc_bypassed

    "$cmd" "${args[@]}"
    local rc=$?

    _wrap_add_log "$cmd" "bypassed" 0 "$rc" "${args[@]}"

    return "$rc"
}

# @pre: none
# @post: all statistics counters reset to zero
# @idempotent: yes
# @returns: 0
#
# Reset all execution statistics to zero. Log is NOT cleared.
#
# Usage: safewrap_reset_stats
safewrap_reset_stats() {
    _MAINFRAME_WRAP_STATS_TOTAL=0
    _MAINFRAME_WRAP_STATS_EXECUTED=0
    _MAINFRAME_WRAP_STATS_BLOCKED=0
    _MAINFRAME_WRAP_STATS_BYPASSED=0
    _MAINFRAME_WRAP_STATS_CONFIRMED=0
    return 0
}

# @pre: none
# @post: all state reset (stats, log, registry, policy)
# @idempotent: yes
# @returns: 0
#
# Full reset of safewrap state. Useful for testing or session boundaries.
#
# Usage: safewrap_reset
safewrap_reset() {
    safewrap_reset_stats
    safewrap_clear_log
    _MAINFRAME_WRAP_REGISTRY=()
    _MAINFRAME_WRAP_POLICY="moderate"
    _MAINFRAME_WRAP_ENABLED=0
    _WRAP_CURRENT_RISK_SCORE=0
    return 0
}

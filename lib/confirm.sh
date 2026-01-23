#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/confirm.sh - Human/Orchestrator Approval Gates
# =============================================================================
# Description: Interactive and automated confirmation gates for AI agent
#              operations. Supports policy-based auto-approve/deny, risk-based
#              decisions (integrates with risk.sh), timeout-based denials,
#              batch confirmations, and full audit history as JSON.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONFIRM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONFIRM_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Confirmation mode: interactive | auto_approve | auto_deny
_MAINFRAME_CONFIRM_MODE="${_MAINFRAME_CONFIRM_MODE:-interactive}"

# Policy: always | never | risk
_MAINFRAME_CONFIRM_POLICY="${_MAINFRAME_CONFIRM_POLICY:-always}"

# Risk threshold for auto-approve in risk policy mode (0-10)
_MAINFRAME_CONFIRM_THRESHOLD="${_MAINFRAME_CONFIRM_THRESHOLD:-5}"

# History storage (file-backed to survive subshell boundaries)
# Use a temp file so that `run` (subshell) writes are visible to parent
_MAINFRAME_CONFIRM_HISTORY_FILE="${_MAINFRAME_CONFIRM_HISTORY_FILE:-$(mktemp /tmp/mainframe-confirm-history.XXXXXX)}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_confirm_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    local escaped_nl='\\n'
    local escaped_tab='\\t'
    local escaped_cr='\\r'
    str="${str//$'\n'/${escaped_nl}}"
    str="${str//$'\t'/${escaped_tab}}"
    str="${str//$'\r'/${escaped_cr}}"
    printf '%s' "$str"
}

# Get current timestamp as ISO-8601
_confirm_timestamp() {
    if command -v date &>/dev/null; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "1970-01-01T00:00:00Z"
    else
        printf '%s' "1970-01-01T00:00:00Z"
    fi
}

# Get epoch seconds
_confirm_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s 2>/dev/null || printf '0'
    fi
}

# Append entry to history (file-backed)
_confirm_history_add() {
    local message="$1"
    local decision="$2"
    local method="$3"

    local ts
    ts=$(_confirm_timestamp)

    local escaped_msg
    escaped_msg=$(_confirm_escape "$message")
    local escaped_decision
    escaped_decision=$(_confirm_escape "$decision")
    local escaped_method
    escaped_method=$(_confirm_escape "$method")

    local entry
    entry=$(printf '{"timestamp":"%s","message":"%s","decision":"%s","method":"%s"}' \
        "$ts" "$escaped_msg" "$escaped_decision" "$escaped_method")

    printf '%s\n' "$entry" >> "$_MAINFRAME_CONFIRM_HISTORY_FILE"
}

# Read yes/no from /dev/tty (for interactive mode)
_confirm_read_tty() {
    local prompt="$1"
    local response=""

    printf '%s [y/N]: ' "$prompt" > /dev/tty 2>/dev/null || printf '%s [y/N]: ' "$prompt" >&2
    read -r response < /dev/tty 2>/dev/null || response="n"

    case "${response,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# Read yes/no with timeout from /dev/tty
_confirm_read_tty_timeout() {
    local prompt="$1"
    local timeout="$2"
    local response=""

    printf '%s [y/N] (%ds timeout): ' "$prompt" "$timeout" > /dev/tty 2>/dev/null || \
        printf '%s [y/N] (%ds timeout): ' "$prompt" "$timeout" >&2
    read -r -t "$timeout" response < /dev/tty 2>/dev/null || response="n"

    case "${response,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: MESSAGE is non-empty
# @post: user prompted for yes/no; decision recorded in history
# @idempotent: no - each call prompts and records
# @returns: 0 if approved, 1 if denied
#
# Interactive yes/no confirmation prompt. Respects _MAINFRAME_CONFIRM_MODE
# for auto-approve/deny in CI/testing environments.
#
# Usage: mainframe_confirm "Delete all temp files?" && rm -rf /tmp/myapp*
# Usage: if mainframe_confirm "Deploy to production?"; then deploy; fi
mainframe_confirm() {
    local message="${1:-Confirm?}"
    local decision=""
    local method=""

    case "$_MAINFRAME_CONFIRM_MODE" in
        auto_approve)
            decision="approved"
            method="auto"
            _confirm_history_add "$message" "$decision" "$method"
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":true,"data":{"decision":"approved","method":"auto","message":"%s"}}\n' \
                    "$(_confirm_escape "$message")"
            fi
            return 0
            ;;
        auto_deny)
            decision="denied"
            method="auto"
            _confirm_history_add "$message" "$decision" "$method"
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":true,"data":{"decision":"denied","method":"auto","message":"%s"}}\n' \
                    "$(_confirm_escape "$message")"
            fi
            return 1
            ;;
        interactive|*)
            if _confirm_read_tty "$message"; then
                decision="approved"
            else
                decision="denied"
            fi
            method="interactive"
            _confirm_history_add "$message" "$decision" "$method"
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":true,"data":{"decision":"%s","method":"interactive","message":"%s"}}\n' \
                    "$decision" "$(_confirm_escape "$message")"
            fi
            [[ "$decision" == "approved" ]] && return 0
            return 1
            ;;
    esac
}

# @pre: CMD is non-empty
# @post: command risk score checked; approved/denied based on threshold
# @idempotent: no - each call evaluates and records
# @returns: 0 if approved, 1 if denied
#
# Auto-approve if the command's risk score is below the threshold.
# If mainframe_risk_score is available (from risk.sh), uses it for scoring.
# Falls back to always-ask if risk.sh is not loaded.
#
# Usage: mainframe_confirm_risk rm -rf /tmp/test && rm -rf /tmp/test
# Usage: mainframe_confirm_risk chmod 777 /etc/passwd || echo "blocked"
mainframe_confirm_risk() {
    if [[ $# -eq 0 ]]; then
        _confirm_history_add "(empty command)" "denied" "risk"
        return 1
    fi

    local cmd_display="$*"

    # In auto modes, bypass risk check
    case "$_MAINFRAME_CONFIRM_MODE" in
        auto_approve)
            _confirm_history_add "$cmd_display" "approved" "auto"
            return 0
            ;;
        auto_deny)
            _confirm_history_add "$cmd_display" "denied" "auto"
            return 1
            ;;
    esac

    # Check if risk.sh is loaded
    if declare -F mainframe_risk_score &>/dev/null; then
        local score
        score=$(mainframe_risk_score "$@")

        # Remove any non-numeric characters (in case of JSON output)
        if [[ "$score" =~ ^[0-9]+$ ]]; then
            : # score is already numeric
        else
            # Try to extract numeric score from JSON
            score="${score##*\"data\":}"
            score="${score%%,*}"
            score="${score%%\}*}"
            [[ ! "$score" =~ ^[0-9]+$ ]] && score=10
        fi

        if (( score < _MAINFRAME_CONFIRM_THRESHOLD )); then
            _confirm_history_add "$cmd_display" "approved" "risk"
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":true,"data":{"decision":"approved","method":"risk","score":%d,"threshold":%d}}\n' \
                    "$score" "$_MAINFRAME_CONFIRM_THRESHOLD"
            fi
            return 0
        else
            # Risk is high - fall through to interactive prompt
            local prompt
            prompt=$(printf 'Risk score %d/%d (threshold %d). Approve "%s"?' \
                "$score" 10 "$_MAINFRAME_CONFIRM_THRESHOLD" "$cmd_display")
            if _confirm_read_tty "$prompt"; then
                _confirm_history_add "$cmd_display" "approved" "risk"
                return 0
            else
                _confirm_history_add "$cmd_display" "denied" "risk"
                return 1
            fi
        fi
    else
        # No risk.sh available - fall back to regular confirm
        mainframe_confirm "Approve command: $cmd_display"
        return $?
    fi
}

# @pre: DESCRIPTION is non-empty; at least one CMD provided
# @post: all commands shown; user approves or denies the batch
# @idempotent: no - each call prompts and records
# @returns: 0 if all approved, 1 if denied
#
# Show a batch of commands and confirm all-or-nothing.
# User sees the full list before making a single decision.
#
# Usage: mainframe_confirm_batch "Deploy changes" "git add ." "git commit" "git push"
mainframe_confirm_batch() {
    if [[ $# -lt 2 ]]; then
        _confirm_history_add "(invalid batch)" "denied" "batch"
        return 1
    fi

    local description="$1"
    shift
    local -a commands=("$@")
    local cmd_count=${#commands[@]}

    # In auto modes, bypass
    case "$_MAINFRAME_CONFIRM_MODE" in
        auto_approve)
            _confirm_history_add "batch:$description ($cmd_count cmds)" "approved" "auto"
            return 0
            ;;
        auto_deny)
            _confirm_history_add "batch:$description ($cmd_count cmds)" "denied" "auto"
            return 1
            ;;
    esac

    # Display batch to user
    {
        printf '\n=== Batch Confirmation: %s ===\n' "$description"
        printf 'Commands (%d):\n' "$cmd_count"
        local i=1
        local cmd
        for cmd in "${commands[@]}"; do
            printf '  %d. %s\n' "$i" "$cmd"
            i=$(( i + 1 ))
        done
        printf '\n'
    } > /dev/tty 2>/dev/null || {
        printf '\n=== Batch Confirmation: %s ===\n' "$description"
        printf 'Commands (%d):\n' "$cmd_count"
        local i=1
        local cmd
        for cmd in "${commands[@]}"; do
            printf '  %d. %s\n' "$i" "$cmd"
            i=$(( i + 1 ))
        done
        printf '\n'
    } >&2

    if _confirm_read_tty "Approve all $cmd_count commands?"; then
        _confirm_history_add "batch:$description ($cmd_count cmds)" "approved" "interactive"
        return 0
    else
        _confirm_history_add "batch:$description ($cmd_count cmds)" "denied" "interactive"
        return 1
    fi
}

# @pre: MESSAGE is non-empty; SECONDS is a positive integer
# @post: user prompted with timeout; auto-denied after timeout expires
# @idempotent: no - each call prompts and records
# @returns: 0 if approved within timeout, 1 if denied or timed out
#
# Confirmation with a timeout. If the user does not respond within
# the specified number of seconds, the request is automatically denied.
#
# Usage: mainframe_confirm_timeout "Apply hotfix?" 30
# Usage: mainframe_confirm_timeout "Restart service?" 10 || echo "timed out"
mainframe_confirm_timeout() {
    local message="${1:-Confirm?}"
    local timeout="${2:-30}"

    # Validate timeout is numeric
    if [[ ! "$timeout" =~ ^[0-9]+$ ]]; then
        timeout=30
    fi

    # In auto modes, bypass
    case "$_MAINFRAME_CONFIRM_MODE" in
        auto_approve)
            _confirm_history_add "$message" "approved" "auto"
            return 0
            ;;
        auto_deny)
            _confirm_history_add "$message" "denied" "timeout"
            return 1
            ;;
    esac

    if _confirm_read_tty_timeout "$message" "$timeout"; then
        _confirm_history_add "$message" "approved" "interactive"
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":true,"data":{"decision":"approved","method":"interactive","timeout":%d}}\n' "$timeout"
        fi
        return 0
    else
        _confirm_history_add "$message" "denied" "timeout"
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":true,"data":{"decision":"denied","method":"timeout","timeout":%d}}\n' "$timeout"
        fi
        return 1
    fi
}

# @pre: LEVEL is one of: always, never, risk
# @post: _MAINFRAME_CONFIRM_POLICY updated
# @idempotent: yes
# @returns: 0 on valid level, 1 on invalid
#
# Set the confirmation policy for subsequent operations.
#   always - always prompt for confirmation
#   never  - auto-approve everything (dangerous for production)
#   risk   - use risk scoring to decide (requires risk.sh)
#
# Usage: mainframe_confirm_policy "risk"
# Usage: mainframe_confirm_policy "never"  # CI environments
mainframe_confirm_policy() {
    local level="${1:-}"

    case "$level" in
        always|never|risk)
            _MAINFRAME_CONFIRM_POLICY="$level"
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":true,"data":{"policy":"%s"}}\n' "$level"
            fi
            return 0
            ;;
        *)
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_INVALID_POLICY","msg":"Invalid policy: %s. Use: always, never, risk"}}\n' \
                    "$(_confirm_escape "${level:-empty}")" >&2
            fi
            return 1
            ;;
    esac
}

# @pre: SCORE is a valid integer 0-10
# @post: _MAINFRAME_CONFIRM_THRESHOLD updated
# @idempotent: yes
# @returns: 0 on valid score, 1 on invalid
#
# Set the risk threshold for auto-approve in risk-based policy mode.
# Commands with risk scores below this threshold are auto-approved.
# Commands at or above this threshold require interactive confirmation.
#
# Usage: mainframe_confirm_threshold 3   # More cautious
# Usage: mainframe_confirm_threshold 8   # More permissive
mainframe_confirm_threshold() {
    local score="${1:-}"

    if [[ ! "$score" =~ ^[0-9]+$ ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_INVALID_THRESHOLD","msg":"Threshold must be integer 0-10"}}\n' >&2
        fi
        return 1
    fi

    if (( score < 0 || score > 10 )); then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_INVALID_THRESHOLD","msg":"Threshold must be 0-10, got %d"}}\n' "$score" >&2
        fi
        return 1
    fi

    _MAINFRAME_CONFIRM_THRESHOLD=$score

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"threshold":%d}}\n' "$score"
    fi
    return 0
}

# @pre: none
# @post: history printed as JSON array to stdout
# @idempotent: yes
# @returns: 0 always
#
# Show the full confirmation history as a JSON array.
# Each entry contains timestamp, message, decision, and method.
#
# Usage: mainframe_confirm_log
# Usage: history=$(mainframe_confirm_log)
mainframe_confirm_log() {
    if [[ ! -s "$_MAINFRAME_CONFIRM_HISTORY_FILE" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":true,"data":[]}\n'
        else
            printf '[]\n'
        fi
        return 0
    fi

    local result="["
    local first=true
    local entry
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="$entry"
    done < "$_MAINFRAME_CONFIRM_HISTORY_FILE"
    result+="]"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":%s}\n' "$result"
    else
        printf '%s\n' "$result"
    fi
    return 0
}

# @pre: none
# @post: history array cleared
# @idempotent: yes
# @returns: 0 always
#
# Clear the confirmation history.
#
# Usage: mainframe_confirm_clear_log
mainframe_confirm_clear_log() {
    : > "$_MAINFRAME_CONFIRM_HISTORY_FILE"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"cleared":true}}\n'
    fi
    return 0
}

# @pre: none
# @post: count printed to stdout
# @idempotent: yes
# @returns: 0 always
#
# Return the number of entries in the confirmation history.
#
# Usage: count=$(mainframe_confirm_count)
mainframe_confirm_count() {
    local count=0
    if [[ -s "$_MAINFRAME_CONFIRM_HISTORY_FILE" ]]; then
        count=$(wc -l < "$_MAINFRAME_CONFIRM_HISTORY_FILE")
        count=$(( count + 0 ))  # Trim whitespace
    fi

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"count":%d}}\n' "$count"
    else
        printf '%d' "$count"
    fi
    return 0
}

# @pre: at least one history entry exists
# @post: last entry printed as JSON to stdout
# @idempotent: yes
# @returns: 0 if history non-empty, 1 if empty
#
# Show the most recent confirmation decision.
#
# Usage: mainframe_confirm_last
# Usage: last=$(mainframe_confirm_last)
mainframe_confirm_last() {
    if [[ ! -s "$_MAINFRAME_CONFIRM_HISTORY_FILE" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_NO_HISTORY","msg":"No confirmation history"}}\n' >&2
        fi
        return 1
    fi

    local entry
    entry=$(tail -n 1 "$_MAINFRAME_CONFIRM_HISTORY_FILE")

    if [[ -z "$entry" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_NO_HISTORY","msg":"No confirmation history"}}\n' >&2
        fi
        return 1
    fi

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":%s}\n' "$entry"
    else
        printf '%s\n' "$entry"
    fi
    return 0
}

# @pre: none
# @post: _MAINFRAME_CONFIRM_MODE set to auto_approve
# @idempotent: yes
# @returns: 0 always
#
# Force auto-approve mode. All confirmations return 0 without prompting.
# Useful for CI/testing environments where interactive input is unavailable.
#
# Usage: mainframe_confirm_auto_approve
mainframe_confirm_auto_approve() {
    _MAINFRAME_CONFIRM_MODE="auto_approve"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"mode":"auto_approve"}}\n'
    fi
    return 0
}

# @pre: none
# @post: _MAINFRAME_CONFIRM_MODE set to auto_deny
# @idempotent: yes
# @returns: 0 always
#
# Force auto-deny mode. All confirmations return 1 without prompting.
# Useful for CI/testing environments to verify denial paths.
#
# Usage: mainframe_confirm_auto_deny
mainframe_confirm_auto_deny() {
    _MAINFRAME_CONFIRM_MODE="auto_deny"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"mode":"auto_deny"}}\n'
    fi
    return 0
}

# @pre: none
# @post: _MAINFRAME_CONFIRM_MODE set to interactive
# @idempotent: yes
# @returns: 0 always
#
# Reset to interactive mode. Confirmations will prompt via /dev/tty.
# Also resets policy to "always" and threshold to 5.
#
# Usage: mainframe_confirm_reset
mainframe_confirm_reset() {
    _MAINFRAME_CONFIRM_MODE="interactive"
    _MAINFRAME_CONFIRM_POLICY="always"
    _MAINFRAME_CONFIRM_THRESHOLD=5

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"mode":"interactive","policy":"always","threshold":5}}\n'
    fi
    return 0
}

# @pre: none
# @post: JSON status object printed to stdout
# @idempotent: yes
# @returns: 0 always
#
# Show current confirmation module status including mode, policy,
# threshold, and history count.
#
# Usage: mainframe_confirm_status
# Usage: status=$(mainframe_confirm_status)
mainframe_confirm_status() {
    local count=0
    if [[ -s "$_MAINFRAME_CONFIRM_HISTORY_FILE" ]]; then
        count=$(wc -l < "$_MAINFRAME_CONFIRM_HISTORY_FILE")
        count=$(( count + 0 ))
    fi
    local risk_available="false"
    declare -F mainframe_risk_score &>/dev/null && risk_available="true"

    local result
    result=$(printf '{"mode":"%s","policy":"%s","threshold":%d,"history_count":%d,"risk_integration":%s}' \
        "$_MAINFRAME_CONFIRM_MODE" \
        "$_MAINFRAME_CONFIRM_POLICY" \
        "$_MAINFRAME_CONFIRM_THRESHOLD" \
        "$count" \
        "$risk_available")

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":%s}\n' "$result"
    else
        printf '%s\n' "$result"
    fi
    return 0
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_safety.sh - AI Agent Safety Stack
# =============================================================================
# Description: Safe command dispatch, structured errors, and audit trail
#              for AI agents executing bash commands
# Purpose: AI agents use bash to control computers. Every operation must be
#          safe, correct the first time, and provide clear feedback to
#          minimize token usage.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_SAFETY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_SAFETY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Audit log file (JSONL format for structured logging)
declare -g AGENT_AUDIT_LOG="${AGENT_AUDIT_LOG:-/tmp/mainframe_agent_$$.audit.jsonl}"

# Audit log rotation: cap size, keep N generations
# (unbounded JSONL grows forever - the repo root audit.log reached 9.6MB)
declare -g AGENT_AUDIT_MAX_BYTES="${AGENT_AUDIT_MAX_BYTES:-10485760}"  # 10MB
declare -g AGENT_AUDIT_KEEP="${AGENT_AUDIT_KEEP:-5}"

# Safe base directory for file operations (defaults to current directory)
declare -g AGENT_SAFE_BASE="${AGENT_SAFE_BASE:-}"

# Current security profile
declare -g AGENT_CURRENT_PROFILE="${AGENT_CURRENT_PROFILE:-project}"

# Risk threshold (0-100, operations above this score require confirmation)
declare -g AGENT_RISK_THRESHOLD="${AGENT_RISK_THRESHOLD:-50}"

# =============================================================================
# SANDBOX PROFILES
# =============================================================================

# Profile definitions with permissions
declare -gA AGENT_PROFILES=(
    [readonly]="read files, no writes"
    [project]="read/write within project"
    [system]="full system access"
)

# Profile permission flags
declare -gA _AGENT_PROFILE_CAN_WRITE=(
    [readonly]=0
    [project]=1
    [system]=1
)

declare -gA _AGENT_PROFILE_CAN_SYSTEM=(
    [readonly]=0
    [project]=0
    [system]=1
)

declare -gA _AGENT_PROFILE_CAN_NETWORK=(
    [readonly]=0
    [project]=0
    [system]=1
)

# Destructive disk/system operations require the highest tier.
# Even the system profile should treat these as exceptional.
declare -gA _AGENT_PROFILE_CAN_DESTRUCTIVE=(
    [readonly]=0
    [project]=0
    [system]=1
)

# One-shot operator approval for above-threshold commands (consumed on use)
declare -g AGENT_APPROVED="${AGENT_APPROVED:-0}"

# Rate limiting: cap executions per sliding window (0 = unlimited, opt-in)
declare -g AGENT_RATE_LIMIT="${AGENT_RATE_LIMIT:-0}"
declare -g AGENT_RATE_WINDOW="${AGENT_RATE_WINDOW:-60}"
declare -ga _AGENT_EXEC_TIMES=()

# =============================================================================
# CALLBACK WHITELIST (NO EVAL)
# =============================================================================

# Registered callbacks that are allowed to be invoked
declare -gA _AGENT_ALLOWED_CALLBACKS=()

# Register a callback function for safe invocation
# @pre: function must be defined (declare -F check)
# @post: function added to whitelist
# @returns: 0 on success, 1 if function not defined
#
# Usage: agent_register_callback "my_handler"
agent_register_callback() {
    local name="$1"

    if [[ -z "$name" ]]; then
        agent_error "callback name required"
        return 1
    fi

    # Verify function exists
    if ! declare -F "$name" &>/dev/null; then
        agent_error "callback '$name' is not a defined function"
        return 1
    fi

    _AGENT_ALLOWED_CALLBACKS["$name"]=1
    agent_audit "callback_registered" "name=$name"
    return 0
}

# Unregister a callback function
# @post: function removed from whitelist
# @returns: 0
#
# Usage: agent_unregister_callback "my_handler"
agent_unregister_callback() {
    local name="$1"
    unset "_AGENT_ALLOWED_CALLBACKS[$name]"
    return 0
}

# Invoke a registered callback safely (no eval)
# @pre: callback must be registered via agent_register_callback
# @post: callback executed with provided arguments
# @returns: callback's return code, or 1 if not registered
#
# Usage: agent_callback "my_handler" arg1 arg2
agent_callback() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        agent_error "callback name required"
        return 1
    fi

    if [[ -z "${_AGENT_ALLOWED_CALLBACKS[$name]:-}" ]]; then
        agent_error "callback '$name' not registered" \
            "suggestion=Register with agent_register_callback first"
        return 1
    fi

    agent_audit "callback_invoked" "name=$name" "args=$*"

    # Safe invocation: function name as command, no eval
    "$name" "$@"
}

# List all registered callbacks
# @returns: 0
#
# Usage: agent_list_callbacks
agent_list_callbacks() {
    local name
    for name in "${!_AGENT_ALLOWED_CALLBACKS[@]}"; do
        printf '%s\n' "$name"
    done | sort
}

# =============================================================================
# STRUCTURED ERROR OUTPUT (TOKEN-EFFICIENT)
# =============================================================================

# Output structured JSON error for AI agent self-correction
# @post: JSON error written to stderr
# @returns: 1 (always fails to allow chaining with ||)
#
# Usage: agent_error "message" "context1" "context2"
agent_error() {
    local msg="$1"
    shift
    local -a context=("$@")

    # Build context array manually to avoid subshell
    local ctx_json="["
    local first=true
    for item in "${context[@]}"; do
        $first || ctx_json+=","
        first=false
        # Simple escape for JSON strings
        item="${item//\\/\\\\}"
        item="${item//\"/\\\"}"
        item="${item//$'\n'/\\n}"
        item="${item//$'\t'/\\t}"
        ctx_json+="\"$item\""
    done
    ctx_json+="]"

    # Get function name and line from call stack
    local func="${FUNCNAME[1]:-unknown}"
    local line="${BASH_LINENO[0]:-0}"

    # Build JSON manually (avoid subshell for json_object)
    # msg must be fully escaped or the envelope is not valid JSON
    local json _esc_msg="${msg//\"/\\\"}"
    _esc_msg="${_esc_msg//$'\n'/\\n}"
    _esc_msg="${_esc_msg//$'\t'/\\t}"
    _esc_msg="${_esc_msg//$'\r'/\\r}"
    printf -v json '{"success":false,"error":"%s","function":"%s","line":%d,"context":%s,"timestamp":"%s"}' \
        "$_esc_msg" \
        "${func//\"/\\\"}" \
        "$line" \
        "$ctx_json" \
        "$(date -Iseconds)"

    printf '%s\n' "$json" >&2
    return 1
}

# Output structured JSON success for AI agent feedback
# @post: JSON success written to stdout
# @returns: 0
#
# Usage: agent_success "message" "key1=value1" "key2=value2"
agent_success() {
    local msg="$1"
    shift
    local -a data=("$@")

    # Build data object from key=value pairs
    local data_json="{"
    local first=true
    for item in "${data[@]}"; do
        if [[ "$item" == *"="* ]]; then
            $first || data_json+=","
            first=false
            local key="${item%%=*}"
            local val="${item#*=}"
            # Simple escape for JSON strings
            key="${key//\\/\\\\}"
            key="${key//\"/\\\"}"
            val="${val//\\/\\\\}"
            val="${val//\"/\\\"}"
            val="${val//$'\n'/\\n}"
            data_json+="\"$key\":\"$val\""
        fi
    done
    data_json+="}"

    local json _esc_msg="${msg//\"/\\\"}"
    _esc_msg="${_esc_msg//$'\n'/\\n}"
    _esc_msg="${_esc_msg//$'\t'/\\t}"
    _esc_msg="${_esc_msg//$'\r'/\\r}"
    printf -v json '{"success":true,"message":"%s","data":%s,"timestamp":"%s"}' \
        "$_esc_msg" \
        "$data_json" \
        "$(date -Iseconds)"

    printf '%s\n' "$json"
    return 0
}

# Output structured JSON result with typed data
# @post: JSON result written to stdout
# @returns: 0
#
# Usage: agent_result "result_key" "result_value" "type"
# Types: string, number, bool, raw
agent_result() {
    local key="$1"
    local value="$2"
    local type="${3:-string}"

    local formatted_value
    case "$type" in
        number)
            formatted_value="$value"
            ;;
        bool)
            case "${value,,}" in
                true|1|yes|on) formatted_value="true" ;;
                *) formatted_value="false" ;;
            esac
            ;;
        raw)
            formatted_value="$value"
            ;;
        *)
            # String: escape and quote
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            formatted_value="\"$value\""
            ;;
    esac

    printf '{"success":true,"%s":%s,"timestamp":"%s"}\n' \
        "${key//\"/\\\"}" \
        "$formatted_value" \
        "$(date -Iseconds)"
}

# =============================================================================
# COMMAND VALIDATION
# =============================================================================

# Command classification tiers (policy is checked BEFORE existence so
# outcomes are host-independent and fail closed on policy, not on what
# happens to be installed).
#
# Tier 1 - DESTRUCTIVE: raw disk / irreversible system operations
#   Requires: destructive tier (system profile only)
declare -ga _AGENT_DESTRUCTIVE_COMMANDS=(
    "dd" "mkfs" "mkswap" "newfs"
    "fdisk" "parted" "diskutil"
    "shred" "wipe" "hdparm" "nvme"
)

# Tier 2 - SYSTEM: system administration
#   Requires: system profile
declare -ga _AGENT_SYSTEM_COMMANDS=(
    "systemctl" "service" "launchctl"
    "reboot" "shutdown" "halt" "poweroff"
    "useradd" "userdel" "usermod" "passwd"
    "crontab" "iptables" "ip6tables" "nft"
    "mount" "umount"
)

# Tier 3 - NETWORK: outbound network operations
#   Requires: system profile
declare -ga _AGENT_NETWORK_COMMANDS=(
    "curl" "wget"
)

# Tier 4 - WRITE: filesystem/process mutation
#   Requires: project or system profile
declare -ga _AGENT_WRITE_COMMANDS=(
    "rm" "rmdir" "unlink" "mv" "cp"
    "chmod" "chown" "chgrp"
    "kill" "killall" "pkill"
)

# Kept for backward compatibility (union of all tiers)
declare -ga _AGENT_DANGEROUS_COMMANDS=(
    "${_AGENT_DESTRUCTIVE_COMMANDS[@]}"
    "${_AGENT_SYSTEM_COMMANDS[@]}"
    "${_AGENT_NETWORK_COMMANDS[@]}"
    "${_AGENT_WRITE_COMMANDS[@]}"
)

# Internal: membership test against a command tier
# Usage: _agent_in_tier "$cmd" "${_AGENT_SYSTEM_COMMANDS[@]}"
_agent_in_tier() {
    local cmd="$1"
    shift
    local tier_cmd
    for tier_cmd in "$@"; do
        [[ "$cmd" == "$tier_cmd" ]] && return 0
    done
    # mkfs family: match mkfs.ext4, mkfs.xfs, ... against literal "mkfs"
    case "$cmd" in
        mkfs.*)
            for tier_cmd in "$@"; do
                [[ "$tier_cmd" == "mkfs" ]] && return 0
            done
            ;;
    esac
    return 1
}

# =============================================================================
# COMMAND TOKENIZATION (STRING-FORM API)
# =============================================================================
# AI agents naturally produce command strings ("ls -la"). The validation and
# execution API accepts both argv form and a single string form. String form
# is tokenized WITHOUT a shell: quotes and escapes are honored, but shell
# operators, variable expansion, and command substitution are rejected
# (agent_safe_exec never invokes a shell, so such input could never execute
# anyway - rejecting it here produces first-time-correct errors).

# Normalized argv output buffer (avoids nameref for bash 4.0 compat)
declare -ga _AGENT_NORMALIZED_ARGV=()

# Internal: tokenize a command string into _AGENT_NORMALIZED_ARGV
# @returns: 0 on success, 1 with agent_error on unsafe/unparseable input
_agent_tokenize() {
    local input="$1"
    _AGENT_NORMALIZED_ARGV=()

    local cur="" token_started=0 in_squote=0 in_dquote=0
    local i ch next
    local len=${#input}

    for (( i=0; i<len; i++ )); do
        ch="${input:i:1}"

        if (( in_squote )); then
            if [[ "$ch" == "'" ]]; then in_squote=0; else cur+="$ch"; fi
            continue
        fi

        if (( in_dquote )); then
            case "$ch" in
                '"') in_dquote=0 ;;
                '\\')
                    next="${input:i+1:1}"
                    if [[ "$next" == '"' || "$next" == '\\' ]]; then
                        cur+="$next"; (( i++ )) || true
                    else
                        cur+="$ch"
                    fi
                    ;;
                '$'|'`')
                    agent_error "expansion not allowed in validated command string" \
                        "suggestion=Expand variables yourself and pass argv form: agent_validate_command cmd arg1 arg2"
                    return 1
                    ;;
                *) cur+="$ch" ;;
            esac
            continue
        fi

        case "$ch" in
            "'") in_squote=1; token_started=1 ;;
            '"') in_dquote=1; token_started=1 ;;
            '\\')
                next="${input:i+1:1}"
                if [[ -z "$next" ]]; then
                    agent_error "trailing backslash in command string"
                    return 1
                fi
                cur+="$next"; (( i++ )) || true; token_started=1
                ;;
            [[:space:]])
                if (( token_started )); then
                    _AGENT_NORMALIZED_ARGV+=("$cur")
                    cur=""; token_started=0
                fi
                ;;
            '$'|'`')
                agent_error "variable/command expansion not allowed in validated command string" \
                    "suggestion=Expand variables yourself and pass argv form: agent_validate_command cmd arg1 arg2"
                return 1
                ;;
            '|'|'&'|';'|'<'|'>'|'('|')')
                agent_error "shell operators are not supported in validated command strings" \
                    "operator=$ch" \
                    "suggestion=Run one simple command per call; agent_safe_exec never uses a shell"
                return 1
                ;;
            *) cur+="$ch"; token_started=1 ;;
        esac
    done

    if (( in_squote || in_dquote )); then
        agent_error "unbalanced quotes in command string"
        return 1
    fi

    if (( token_started )); then
        _AGENT_NORMALIZED_ARGV+=("$cur")
    fi

    if (( ${#_AGENT_NORMALIZED_ARGV[@]} == 0 )); then
        agent_error "empty command"
        return 1
    fi

    return 0
}

# Internal: normalize argv-or-string input into _AGENT_NORMALIZED_ARGV
# @returns: 0 on success (buffer populated), 1 with agent_error otherwise
_agent_normalize_argv() {
    _AGENT_NORMALIZED_ARGV=()

    if (( $# == 0 )); then
        agent_error "no command provided"
        return 1
    fi

    if (( $# > 1 )); then
        _AGENT_NORMALIZED_ARGV=("$@")
        return 0
    fi

    local input="$1"
    # Fast path: single token with no whitespace, quoting, or shell syntax
    case "$input" in
        *[[:space:]\"\'\`\$\\\|\&\;\<\>\(\)]*)
            _agent_tokenize "$input"
            ;;
        *)
            _AGENT_NORMALIZED_ARGV=("$input")
            ;;
    esac
}

# =============================================================================
# FLAG NORMALIZATION
# =============================================================================
# Flag detection must handle bundled (-rf), split (-r -f), and long
# (--recursive --force) forms uniformly, and stop at "--".

# Internal: returns 0 if args contain recursive AND force flags (rm-style)
_agent_has_recursive_force() {
    local has_r=0 has_f=0 arg
    for arg in "$@"; do
        [[ "$arg" == "--" ]] && break
        [[ "$arg" != -* ]] && continue
        case "$arg" in
            --recursive) has_r=1 ;;
            --force) has_f=1 ;;
            --*) ;;
            *)
                [[ "$arg" == *[rR]* ]] && has_r=1
                [[ "$arg" == *f* ]] && has_f=1
                ;;
        esac
    done
    (( has_r && has_f ))
}

# Internal: returns 0 if args contain a recursive flag (chmod/chown-style)
_agent_has_recursive_flag() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == "--" ]] && break
        [[ "$arg" != -* ]] && continue
        case "$arg" in
            --recursive) return 0 ;;
            --*) ;;
            *) [[ "$arg" == *R* ]] && return 0 ;;
        esac
    done
    return 1
}

# =============================================================================
# PATH CONFINEMENT
# =============================================================================

# Internal: confine a single path to AGENT_SAFE_BASE (emits agent_error)
_agent_confine_path() {
    local path="$1"
    local op_context="$2"
    if ! _agent_validate_path_safe "$path" "$AGENT_SAFE_BASE"; then
        agent_error "unsafe $op_context target: $path" \
            "base=$AGENT_SAFE_BASE" \
            "suggestion=Keep operations inside AGENT_SAFE_BASE"
        return 1
    fi
    return 0
}

# Internal: enforce AGENT_SAFE_BASE on the write targets of a command
# @pre: AGENT_SAFE_BASE is non-empty
_agent_confine_write_targets() {
    local cmd="$1"
    shift

    local arg skip_next=0 confine_next=0 first_operand=1

    case "$cmd" in
        rm|rmdir|unlink)
            # Recursive+force deletion is the destructive combination;
            # confine every operand when it is present.
            if _agent_has_recursive_force "$@"; then
                for arg in "$@"; do
                    [[ "$arg" == -* ]] && continue
                    _agent_confine_path "$arg" "$cmd" || return 1
                done
            fi
            ;;
        chmod|chown|chgrp)
            # Confine path operands (after the mode/owner spec) when recursive.
            if _agent_has_recursive_flag "$@"; then
                for arg in "$@"; do
                    case "$arg" in
                        --reference*) first_operand=0; continue ;;
                        -*) continue ;;
                    esac
                    if (( first_operand )); then
                        first_operand=0   # mode/owner spec, not a path
                        continue
                    fi
                    _agent_confine_path "$arg" "$cmd" || return 1
                done
            fi
            ;;
        dd)
            # Only of= is a write target
            for arg in "$@"; do
                if [[ "$arg" == of=* ]]; then
                    _agent_confine_path "${arg#of=}" "dd output" || return 1
                fi
            done
            ;;
        mv|cp|truncate|tee)
            for arg in "$@"; do
                if (( confine_next )); then
                    confine_next=0
                    _agent_confine_path "$arg" "$cmd" || return 1
                    continue
                fi
                if (( skip_next )); then
                    skip_next=0
                    continue
                fi
                case "$arg" in
                    -t|--target-directory) confine_next=1 ;;
                    --target-directory=*) _agent_confine_path "${arg#*=}" "$cmd" || return 1 ;;
                    -s|--size|--reference|-o|--option|-S|--suffix|--backup) skip_next=1 ;;
                    --reference=*) _agent_confine_path "${arg#*=}" "$cmd" || return 1 ;;
                    --*=*) ;;
                    -*) ;;
                    *) _agent_confine_path "$arg" "$cmd" || return 1 ;;
                esac
            done
            ;;
    esac
    return 0
}

# Validate command before execution
# @pre: command and args provided (argv form), or a single command string
# @post: validates command is permitted by policy and safe to execute
# @returns: 0 if valid, 1 if invalid
#
# Policy checks run BEFORE existence checks so that policy decisions are
# host-independent: a forbidden command is forbidden even on hosts where
# it is not installed (fail closed on policy, not on environment).
#
# Usage: agent_validate_command "cmd" "arg1" "arg2"
#        agent_validate_command "cmd arg1 arg2"   # string form, safely tokenized
agent_validate_command() {
    if ! _agent_normalize_argv "$@"; then
        return 1
    fi

    local cmd="${_AGENT_NORMALIZED_ARGV[0]}"
    local -a args=("${_AGENT_NORMALIZED_ARGV[@]:1}")

    if [[ -z "$cmd" ]]; then
        agent_error "empty command"
        return 1
    fi

    # -----------------------------------------------------------------
    # POLICY CHECKS FIRST (host-independent, fail closed)
    # -----------------------------------------------------------------
    local can_write="${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0}"
    local can_system="${_AGENT_PROFILE_CAN_SYSTEM[$AGENT_CURRENT_PROFILE]:-0}"
    local can_network="${_AGENT_PROFILE_CAN_NETWORK[$AGENT_CURRENT_PROFILE]:-0}"
    local can_destructive="${_AGENT_PROFILE_CAN_DESTRUCTIVE[$AGENT_CURRENT_PROFILE]:-0}"

    # Tier 1: destructive disk/system commands
    if _agent_in_tier "$cmd" "${_AGENT_DESTRUCTIVE_COMMANDS[@]}"; then
        if (( ! can_destructive )); then
            agent_error "destructive command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                "suggestion=Use 'system' profile for destructive disk operations"
            return 1
        fi
    # Tier 3: network commands
    elif _agent_in_tier "$cmd" "${_AGENT_NETWORK_COMMANDS[@]}"; then
        if (( ! can_network )); then
            agent_error "network command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                "suggestion=Use 'system' profile for network operations"
            return 1
        fi
    # Tier 2: system administration commands
    elif _agent_in_tier "$cmd" "${_AGENT_SYSTEM_COMMANDS[@]}"; then
        if (( ! can_system )); then
            agent_error "system command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                "suggestion=Use 'system' profile for system administration"
            return 1
        fi
    # Tier 4: write-class commands
    elif _agent_in_tier "$cmd" "${_AGENT_WRITE_COMMANDS[@]}"; then
        if (( ! can_write )); then
            agent_error "write command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                "suggestion=Use 'project' or 'system' profile"
            return 1
        fi
    fi

    # -----------------------------------------------------------------
    # EXISTENCE CHECK (after policy: existence is host-dependent, policy is not)
    # -----------------------------------------------------------------
    if ! type -P "$cmd" &>/dev/null && ! declare -F "$cmd" &>/dev/null; then
        agent_error "command not found: $cmd" \
            "suggestion=Check spelling or install package"
        return 1
    fi

    # -----------------------------------------------------------------
    # PATH CONFINEMENT (when AGENT_SAFE_BASE is set)
    # -----------------------------------------------------------------
    if [[ -n "${AGENT_SAFE_BASE:-}" ]]; then
        if ! _agent_confine_write_targets "$cmd" "${args[@]}"; then
            return 1
        fi
    fi

    return 0
}

# Internal: validate path is within safe base
_agent_validate_path_safe() {
    local path="$1"
    local base="$2"

    [[ -z "$path" ]] && return 1
    [[ -z "$base" ]] && return 0  # No base = allow all

    # Decode URL-encoded traversal markers before inspection (fail closed)
    local decoded="$path"
    decoded="${decoded//%2e/.}"; decoded="${decoded//%2E/.}"
    decoded="${decoded//%2f//}"; decoded="${decoded//%2F//}"
    decoded="${decoded//%5c/\\}"; decoded="${decoded//%5C/\\}"
    [[ "$decoded" == *"%00"* ]] && return 1

    # Reject backslash (Windows-style path manipulation)
    [[ "$decoded" == *"\\"* ]] && return 1

    # Reject '..' as an exact path component (allows names like foo..bar)
    local -a _avps_parts
    IFS='/' read -r -a _avps_parts <<< "$decoded"
    local _avps_part
    for _avps_part in "${_avps_parts[@]}"; do
        [[ "$_avps_part" == ".." ]] && return 1
    done

    # Resolve paths
    local abs_base abs_path

    if [[ -d "$base" ]]; then
        abs_base=$(cd "$base" && pwd -P) || return 1
    else
        return 1
    fi

    # Handle existing paths (resolve the FULL path, including a
    # final-component symlink: a link inside the base must not point
    # outside it), then non-existing paths via deepest existing ancestor.
    if [[ -e "$path" || -L "$path" ]]; then
        abs_path=$(realpath "$path" 2>/dev/null) || abs_path=""
        if [[ -z "$abs_path" ]]; then
            abs_path=$(cd "$(dirname -- "$path")" && pwd -P)/$(basename -- "$path")
        fi
    else
        local check_path="$path"
        local -a missing=()
        while [[ ! -e "$check_path" ]]; do
            missing+=("$(basename -- "$check_path")")
            check_path=$(dirname -- "$check_path")
            if [[ "$check_path" == "/" || -z "$check_path" ]]; then
                return 1
            fi
        done
        # '..' in the uncreated remainder cannot be resolved safely - reject
        local _avps_miss
        for _avps_miss in "${missing[@]}"; do
            [[ "$_avps_miss" == ".." ]] && return 1
        done
        if [[ -d "$check_path" ]]; then
            abs_path=$(cd "$check_path" && pwd -P) || return 1
        else
            # Deepest existing component is a file: resolve its directory
            abs_path=$(cd "$(dirname -- "$check_path")" && pwd -P)/$(basename -- "$check_path") || return 1
        fi
        local _avps_i
        for (( _avps_i=${#missing[@]}-1; _avps_i>=0; _avps_i-- )); do
            abs_path="$abs_path/${missing[_avps_i]}"
        done
    fi

    # Boundary-aware containment: exact match or proper subdirectory
    [[ "$abs_path" == "$abs_base" || "$abs_path" == "$abs_base"/* ]]
}

# =============================================================================
# SEMANTIC RISK ANALYSIS (RESOLVED-COMMAND SCORING)
# =============================================================================
# Scoring the literal command string misses indirection: "FLAGS=-rf; rm
# $FLAGS /x" looks benign until the shell expands it. Resolution happens in
# two stages, without ever invoking a shell:
#   1. Harvest leading VAR=value assignments from the command itself
#      (self-contained indirection - the real evasion pattern)
#   2. Expand simple $VAR and ${VAR} references from those assignments,
#      then from the current environment
# Command substitution, operators, and complex ${...} forms stay opaque.

# Internal: resolve simple variable references in a command string
# @returns: resolved string on stdout
_agent_resolve_command() {
    local input="$1"

    # Stage 1: harvest leading assignments (VAR=value, quoted or bare)
    local -A _resolve_env=()
    local rest="$input" name value
    # Value stops at command separators; regex via variable ([[ ]] parses
    # bare | and & in unquoted patterns as shell syntax)
    local assign_re='^([A-Za-z_][A-Za-z0-9_]*)=([^[:space:];&|]*)[[:space:];&|]+'
    while [[ "$rest" =~ $assign_re ]]; do
        name="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # Strip surrounding quotes from the value
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        _resolve_env["$name"]="$value"
        rest="${rest#"${BASH_REMATCH[0]}"}"
    done

    # Stage 2: expand simple $VAR / ${VAR} (assignment vars win over env)
    local out="" i ch varname next rest2
    local len=${#rest}
    for (( i=0; i<len; i++ )); do
        ch="${rest:i:1}"
        if [[ "$ch" == '$' ]]; then
            next="${rest:i+1:1}"
            varname=""
            if [[ "$next" == "{" ]]; then
                rest2="${rest:i+2}"
                if [[ "$rest2" =~ ^([A-Za-z_][A-Za-z0-9_]*)\} ]]; then
                    varname="${BASH_REMATCH[1]}"
                    i=$(( i + ${#varname} + 2 ))
                else
                    out+="$ch"
                    continue
                fi
            elif [[ "$next" =~ [A-Za-z_] ]]; then
                rest2="${rest:i+1}"
                [[ "$rest2" =~ ^[A-Za-z_][A-Za-z0-9_]* ]] && varname="${BASH_REMATCH[0]}"
                if [[ -n "$varname" ]]; then
                    i=$(( i + ${#varname} ))
                else
                    out+="$ch"
                    continue
                fi
            else
                out+="$ch"
                continue
            fi
            if [[ -n "${_resolve_env[$varname]+x}" ]]; then
                out+="${_resolve_env[$varname]}"
            else
                out+="${!varname:-}"
            fi
        else
            out+="$ch"
        fi
    done
    printf '%s' "$out"
}

# =============================================================================
# DESTRUCTIVE COMMAND GATE (SHARED RULE SET)
# =============================================================================
# String-level pattern gate for destructive commands. This is the canonical
# rule set: host integrations (Pi extension, hooks, CI checks) should call
# agent_gate_classify instead of maintaining their own regex lists, so the
# rules never diverge between enforcement points.
#
# Tiers: critical (irreversible/system), high (destructive but scoped),
# medium (externally visible / hard to reverse), low (everything else).

# Internal: decode only shell quoting and backslash escaping in one word.
# Expansion is intentionally out of scope here; _agent_resolve_command handles
# the small, supported variable-expansion subset before lexical analysis.
_agent_gate_decode_word() {
    local input="$1" output="" quote="" ch next body decoded ansi_ch
    local i j escaped len=${#input}

    for (( i=0; i<len; i++ )); do
        ch="${input:i:1}"
        if [[ "$quote" == "'" ]]; then
            [[ "$ch" == "'" ]] && quote="" || output+="$ch"
            continue
        fi
        if [[ "$quote" == '"' ]]; then
            if [[ "$ch" == '"' ]]; then
                quote=""
            elif [[ "$ch" == $'\\' && $((i + 1)) -lt len ]]; then
                next="${input:i+1:1}"
                case "$next" in
                    '$'|'`'|'"'|$'\\') output+="$next"; i=$((i + 1)) ;;
                    $'\n') i=$((i + 1)) ;;
                    *) output+="$ch" ;;
                esac
            else
                output+="$ch"
            fi
            continue
        fi

        case "$ch" in
            "'"|'"') quote="$ch" ;;
            '$')
                # ANSI-C quoted words become literal argv after shell decoding.
                # Bash printf is a builtin and receives data, never shell code.
                if [[ "${input:i+1:1}" == "'" ]]; then
                    body=""
                    escaped=0
                    for (( j=i+2; j<len; j++ )); do
                        ansi_ch="${input:j:1}"
                        if [[ "$ansi_ch" == "'" && "$escaped" -eq 0 ]]; then
                            break
                        fi
                        body+="$ansi_ch"
                        if [[ "$ansi_ch" == $'\\' && "$escaped" -eq 0 ]]; then
                            escaped=1
                        else
                            escaped=0
                        fi
                    done
                    if (( j < len )); then
                        # \c truncates printf %b output. Preserve it as dynamic
                        # syntax rather than canonicalizing an incomplete word.
                        if [[ "$body" == *'\c'* ]]; then
                            output+="\$'$body'"
                        else
                            printf -v decoded '%b' "$body"
                            output+="$decoded"
                        fi
                        i=$j
                    else
                        output+="$ch"
                    fi
                else
                    output+="$ch"
                fi
                ;;
            $'\\')
                if (( i + 1 < len )); then
                    i=$((i + 1))
                    [[ "${input:i:1}" == $'\n' ]] || output+="${input:i:1}"
                else
                    output+="$ch"
                fi
                ;;
            *) output+="$ch" ;;
        esac
    done

    printf '%s' "$output"
}

# Internal: identify executable words that still contain shell expansion or
# encoding syntax after lexical command-position analysis. The record marker
# is emitted only for executable tokens (including wrapper targets and shell
# -c programs), so benign arguments such as `rg '$('` remain outside this
# conservative rule.
_agent_gate_has_dynamic_executable() {
    local remaining="$1" marker=$'\036' token

    while [[ "$remaining" == *"$marker"* ]]; do
        remaining="${remaining#*"$marker"}"
        token="${remaining%%[[:space:];\&\|\(\)]*}"
        case "$token" in
            *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 0 ;;
        esac
    done
    return 1
}

_agent_gate_has_executable_named() {
    local remaining="$1" expected="$2" marker=$'\036' token

    while [[ "$remaining" == *"$marker"* ]]; do
        remaining="${remaining#*"$marker"}"
        token="${remaining%%[[:space:];\&\|\(\)]*}"
        [[ "${token##*/}" == "$expected" ]] && return 0
    done
    return 1
}

# Internal: find lexically active command/process substitution without
# executing or rewriting the command. Single-quoted data and backslash-escaped
# characters are intentionally ignored; substitutions remain active inside
# double quotes, while process substitution does not.
# Internal: find lexically active command/process substitution without
# executing or rewriting the command. Single-quoted data and backslash-escaped
# characters are intentionally ignored; substitutions remain active inside
# double quotes, while process substitution does not.
#
# Heredoc awareness: a heredoc body introduced by a QUOTED delimiter
# (<<'EOF', <<"EOF", <<\EOF, and mixed forms) is inert data - the shell
# performs no expansion there - so the body is skipped entirely. A body with
# an UNQUOTED delimiter (<<EOF) really does undergo $/` expansion, so it is
# still scanned; nested heredoc detection is suppressed inside it because the
# body is text to the shell, not syntax.
_agent_gate_has_dynamic_shell_expansion() {
    local input="$1" quote="" ch next i len=${#1}
    local hd_body_mode=0 hd_bdelim="" hd_bstrip=0 hd_line=""

    for (( i=0; i<len; i++ )); do
        ch="${input:i:1}"

        # Unquoted-heredoc body: scan with ordinary quote semantics, but track
        # lines so the closing delimiter ends the body, and never treat body
        # text as new heredoc syntax.
        if (( hd_body_mode )); then
            if [[ "$ch" == $'\n' ]]; then
                local _hd_chk="$hd_line"
                if (( hd_bstrip )); then
                    while [[ "$_hd_chk" == $'\t'* ]]; do _hd_chk="${_hd_chk#$'\t'}"; done
                fi
                hd_line=""
                [[ "$_hd_chk" == "$hd_bdelim" ]] && hd_body_mode=0
                continue
            fi
            hd_line+="$ch"
        fi

        if [[ "$quote" == "'" ]]; then
            [[ "$ch" == "'" ]] && quote=""
            continue
        fi
        if [[ "$quote" == '"' ]]; then
            if [[ "$ch" == '"' ]]; then
                quote=""
            elif [[ "$ch" == $'\\' && $((i + 1)) -lt len ]]; then
                next="${input:i+1:1}"
                case "$next" in
                    '$'|'`'|'"'|$'\\'|$'\n') i=$((i + 1)) ;;
                esac
            elif [[ "$ch" == '$' && "${input:i+1:1}" == '(' ]]; then
                return 0
            elif [[ "$ch" == '`' ]]; then
                return 0
            fi
            continue
        fi

        case "$ch" in
            "'") quote="'" ;;
            '"') quote='"' ;;
            $'\\') i=$((i + 1)) ;;
            '$') [[ "${input:i+1:1}" == '(' ]] && return 0 ;;
            '`') return 0 ;;
            '>') [[ "${input:i+1:1}" == '(' ]] && return 0 ;;
            '<')
                [[ "${input:i+1:1}" == '(' ]] && return 0
                if (( ! hd_body_mode )) && [[ "${input:i+1:1}" == '<' && "${input:i+2:1}" != '<' ]]; then
                    # Candidate heredoc operator: parse optional strip-tabs
                    # dash, whitespace, then the delimiter word.
                    local j=$(( i + 2 )) hd_strip=0 hd_spec="" hd_ch
                    [[ "${input:j:1}" == '-' ]] && { hd_strip=1; j=$(( j + 1 )); }
                    while [[ "${input:j:1}" == ' ' || "${input:j:1}" == $'\t' ]]; do j=$(( j + 1 )); done
                    while (( j < len )); do
                        hd_ch="${input:j:1}"
                        case "$hd_ch" in
                            ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')'|'<'|'>') break ;;
                        esac
                        hd_spec+="$hd_ch"; j=$(( j + 1 ))
                    done
                    if [[ -n "$hd_spec" ]]; then
                        # Decode the delimiter (quotes/backslashes removed) and
                        # record whether any quoting made the body inert.
                        local hd_delim="" hd_quoted=0 k hd_c
                        for (( k=0; k<${#hd_spec}; k++ )); do
                            hd_c="${hd_spec:k:1}"
                            case "$hd_c" in
                                "'"|'"') hd_quoted=1 ;;
                                $'\\')
                                    hd_quoted=1
                                    if (( k + 1 < ${#hd_spec} )); then
                                        k=$(( k + 1 )); hd_delim+="${hd_spec:k:1}"
                                    fi
                                    ;;
                                *) hd_delim+="$hd_c" ;;
                            esac
                        done
                        # Dynamic or empty delimiters cannot be matched safely;
                        # leave the text to ordinary scanning.
                        if [[ -n "$hd_delim" && "$hd_delim" != *'$'* && "$hd_delim" != *'`'* && "$hd_delim" != *$'\n'* ]]; then
                            local _hd_after="${input:j}"
                            if [[ "$_hd_after" == *$'\n'* ]]; then
                                local _hd_body="${_hd_after#*$'\n'}"
                                local _hd_pos=$(( ${#input} - ${#_hd_body} ))
                                if (( hd_quoted )); then
                                    # Inert body: skip lines through the
                                    # closing delimiter.
                                    local _hd_rest="$_hd_body" _hd_line2 _hd_chk2
                                    while :; do
                                        if [[ "$_hd_rest" == *$'\n'* ]]; then
                                            _hd_line2="${_hd_rest%%$'\n'*}"
                                            _hd_pos=$(( _hd_pos + ${#_hd_line2} + 1 ))
                                        else
                                            _hd_line2="$_hd_rest"
                                            _hd_pos=$len
                                        fi
                                        _hd_chk2="$_hd_line2"
                                        if (( hd_strip )); then
                                            while [[ "$_hd_chk2" == $'\t'* ]]; do _hd_chk2="${_hd_chk2#$'\t'}"; done
                                        fi
                                        [[ "$_hd_chk2" == "$hd_delim" ]] && break
                                        [[ "$_hd_rest" != *$'\n'* ]] && break
                                        _hd_rest="${_hd_rest#*$'\n'}"
                                    done
                                    i=$(( _hd_pos - 1 ))
                                    continue
                                fi
                                # Expansion-capable body: scan it, suppressing
                                # nested heredoc detection until its delimiter.
                                hd_body_mode=1
                                hd_bdelim="$hd_delim"
                                hd_bstrip=$hd_strip
                                hd_line=""
                                i=$(( _hd_pos - 1 ))
                                continue
                            fi
                        fi
                    fi
                fi
                ;;
        esac
    done
    return 1
}

_agent_gate_has_unsupported_control() {
    local input="$1" ch code i
    local LC_ALL=C

    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        printf -v code '%d' "'$ch"
        if (( (code < 32 && code != 9 && code != 10) || code == 127 )); then
            return 0
        fi
    done
    return 1
}

# Internal: create an analysis-only form of a POSIX shell command string.
# Executables are marked with an ASCII record separator and path prefixes are
# removed only at command positions. The marker lets destructive classifiers
# distinguish an executable `rm` from prose such as a commit message that
# merely mentions "rm -rf".
#
# This is deliberately a bounded, honest-but-fallible lexer, not a complete
# shell parser. It understands command separators, simple quotes/escapes,
# common command wrappers, git/terraform global options, find -exec, and shell
# -c. Dynamic evaluation constructs are rejected conservatively by the gate
# before ordinary command matching. Inline Git alias definitions and the
# documented option arity of supported wrappers are covered; pre-existing
# aliases, functions, and unknown implementation-specific wrapper options
# remain outside this lexer's scope.
# Most importantly, it never executes or rewrites caller input.
_agent_gate_normalize_command_paths() {
    local input="$1" output="" token="" quote="" ch raw plain command inner
    local marker=$'\036'
    local -a words=() types=()
    local i len=${#input}

    # First pass: split into shell words, whitespace, and command separators
    # while keeping quoted and escaped separators inside their original word.
    for (( i=0; i<len; i++ )); do
        ch="${input:i:1}"
        if [[ -n "$quote" ]]; then
            token+="$ch"
            if [[ "$ch" == "$quote" ]]; then
                quote=""
            elif [[ "$ch" == $'\\' && "$quote" == '"' && $((i + 1)) -lt len ]]; then
                i=$((i + 1))
                token+="${input:i:1}"
            fi
            continue
        fi

        case "$ch" in
            "'"|'"') quote="$ch"; token+="$ch" ;;
            $'\\')
                token+="$ch"
                if (( i + 1 < len )); then
                    i=$((i + 1))
                    token+="${input:i:1}"
                fi
                ;;
            ' '|$'\t')
                if [[ -n "$token" ]]; then
                    words+=("$token"); types+=(word); token=""
                fi
                words+=("$ch"); types+=(space)
                ;;
            '<'|'>')
                if [[ -n "$token" ]]; then
                    words+=("$token"); types+=(word); token=""
                fi
                words+=("$ch"); types+=(operator)
                ;;
            $'\n'|';'|'|'|'&'|'('|')')
                if [[ -n "$token" ]]; then
                    words+=("$token"); types+=(word); token=""
                fi
                words+=("$ch"); types+=(separator)
                ;;
            *) token+="$ch" ;;
        esac
    done
    if [[ -n "$token" ]]; then
        words+=("$token"); types+=(word)
    fi

    local at_command=1 wrapper="" wrapper_arg_pending=0
    local wrapper_split_string_pending=0
    local wrapper_timeout_duration=0
    local current_command="" shell_code_pending=0
    local find_exec_pending=0 find_embedded_shell=0
    local git_preamble=0 terraform_preamble=0 option_arg_pending=0
    local git_config_arg_pending=0
    local redirect_target_pending=0
    local function_name_pending=0

    # Heredoc tracking. `<<`/`<<-` queue a body that begins at the next
    # newline. Bodies are data, never commands, so they are dropped from the
    # analysis form - except when the receiving command (or the pipe target
    # on the opening line) is a shell/interpreter, in which case the body is
    # recursively analyzed as shell code.
    local -a heredoc_queue=()
    local heredoc_delim_pending=0 heredoc_strip_tabs=0
    local body_mode=0 body_cmd="" body_tabs=0 body_delim="" body_code=0
    local body_line="" body_text="" body_line_piped=0
    local lt_prev=0 pending_pipe=0 line_pipes_to_shell=0

    # Second pass: identify the words the shell treats as executables. Wrapper
    # options are omitted from the analysis form so their operands cannot be
    # mistaken for the wrapped command.
    for (( i=0; i<${#words[@]}; i++ )); do
        raw="${words[i]}"

        # Heredoc body: accumulate lines until the closing delimiter. Body
        # words are data, so they never receive executable markers; a body
        # feeding a shell/interpreter is analyzed recursively as shell code.
        if (( body_mode )); then
            if [[ "${types[i]}" == separator && "$raw" == $'\n' ]]; then
                local _hd_line="$body_line"
                if (( body_tabs )); then
                    while [[ "$_hd_line" == $'\t'* ]]; do _hd_line="${_hd_line#$'\t'}"; done
                fi
                if [[ "$_hd_line" == "$body_delim" ]]; then
                    if (( body_code )) && [[ -n "$body_text" ]]; then
                        output+=" ; "
                        output+=$(_agent_gate_normalize_command_paths "$body_text")
                    fi
                    output+=$'\n'
                    if (( ${#heredoc_queue[@]} > 0 )); then
                        local _hd_entry="${heredoc_queue[0]}"
                        heredoc_queue=("${heredoc_queue[@]:1}")
                        body_cmd="${_hd_entry%%$'\x1f'*}"
                        local _hd_rest="${_hd_entry#*$'\x1f'}"
                        body_tabs="${_hd_rest%%$'\x1f'*}"
                        body_delim="${_hd_rest#*$'\x1f'}"
                        body_code=0
                        case "$body_cmd" in
                            sh|bash|dash|zsh|ksh|ssh) body_code=1 ;;
                        esac
                        (( body_line_piped )) && body_code=1
                        body_line=""; body_text=""
                    else
                        body_mode=0; body_line=""; body_text=""
                        # The delimiter line ended the body; the next line is
                        # a fresh command position.
                        at_command=1
                        wrapper=""; wrapper_arg_pending=0
                        wrapper_split_string_pending=0
                        wrapper_timeout_duration=0
                        current_command=""; shell_code_pending=0
                        find_exec_pending=0; find_embedded_shell=0
                        git_preamble=0; terraform_preamble=0; option_arg_pending=0
                        git_config_arg_pending=0
                        redirect_target_pending=0
                        function_name_pending=0
                    fi
                else
                    body_text+="$body_line"$'\n'
                    body_line=""
                fi
                continue
            fi
            body_line+="$raw"
            continue
        fi
        case "${types[i]}" in
            space)
                output+="$raw"
                lt_prev=0
                continue
                ;;
            separator)
                output+="$raw"
                at_command=1
                wrapper=""; wrapper_arg_pending=0
                wrapper_split_string_pending=0
                wrapper_timeout_duration=0
                current_command=""; shell_code_pending=0
                find_exec_pending=0; find_embedded_shell=0
                git_preamble=0; terraform_preamble=0; option_arg_pending=0
                git_config_arg_pending=0
                redirect_target_pending=0
                function_name_pending=0
                lt_prev=0
                heredoc_delim_pending=0
                if [[ "$raw" == '|' ]]; then
                    pending_pipe=1
                else
                    pending_pipe=0
                fi
                if [[ "$raw" == $'\n' ]]; then
                    if (( ${#heredoc_queue[@]} > 0 )); then
                        local _hd_entry="${heredoc_queue[0]}"
                        heredoc_queue=("${heredoc_queue[@]:1}")
                        body_cmd="${_hd_entry%%$'\x1f'*}"
                        local _hd_rest="${_hd_entry#*$'\x1f'}"
                        body_tabs="${_hd_rest%%$'\x1f'*}"
                        body_delim="${_hd_rest#*$'\x1f'}"
                        body_line_piped=$line_pipes_to_shell
                        body_code=0
                        case "$body_cmd" in
                            sh|bash|dash|zsh|ksh|ssh) body_code=1 ;;
                        esac
                        (( body_line_piped )) && body_code=1
                        body_mode=1
                        body_line=""; body_text=""
                    fi
                    line_pipes_to_shell=0
                fi
                continue
                ;;
            operator)
                output+="$raw"
                if [[ "$raw" == '>' ]]; then
                    redirect_target_pending=1
                elif [[ "$raw" == '<' ]]; then
                    if (( lt_prev )); then
                        lt_prev=0
                        # '<<' introduces a heredoc unless a third '<' makes
                        # it a herestring. A heredoc needs a command on this
                        # line to receive the body.
                        if [[ "${types[i+1]:-}" == operator && "${words[i+1]:-}" == '<' ]]; then
                            : # '<<<' herestring: no body lines follow
                        elif [[ -n "$current_command" ]]; then
                            heredoc_delim_pending=1
                            heredoc_strip_tabs=0
                        fi
                    else
                        lt_prev=1
                    fi
                fi
                continue
                ;;
        esac

        plain=$(_agent_gate_decode_word "$raw")
        lt_prev=0

        # Heredoc delimiter word: queue the body spec instead of treating the
        # word as an argument. `<<-` strips leading tabs from body lines.
        if (( heredoc_delim_pending )); then
            if [[ "$raw" == "-" ]]; then
                heredoc_strip_tabs=1
                output+="$raw"
                continue
            fi
            local _hd_spec="$raw"
            if [[ "$_hd_spec" == -* ]]; then
                heredoc_strip_tabs=1
                _hd_spec="${_hd_spec#-}"
            fi
            local _hd_delim
            _hd_delim=$(_agent_gate_decode_word "$_hd_spec")
            local _hd_quoted=0 _hd_valid=1
            [[ "$_hd_spec" == *"'"* || "$_hd_spec" == *'"'* || "$_hd_spec" == *'\'* ]] && _hd_quoted=1
            [[ -z "$_hd_delim" || "$_hd_delim" == *$'\n'* ]] && _hd_valid=0
            if (( ! _hd_quoted )) && [[ "$_hd_delim" == *'$'* || "$_hd_delim" == *'`'* ]]; then
                _hd_valid=0   # dynamic delimiter: cannot locate the body end
            fi
            if (( _hd_valid )); then
                heredoc_queue+=("${current_command}"$'\x1f'"${heredoc_strip_tabs}"$'\x1f'"${_hd_delim}")
                output+="$raw"
                heredoc_delim_pending=0
                continue
            fi
            heredoc_delim_pending=0
            # Invalid spec: fall through and treat the word as an argument.
        fi

        if (( redirect_target_pending )); then
            if [[ "${plain,,}" =~ ^/dev/(sd|disk|rdisk|nvme) ]]; then
                output+="${marker}mainframe-raw-device-redirect "
            fi
            output+="$plain"
            redirect_target_pending=0
            continue
        fi

        # GNU env -S/--split-string reparses its operand as command argv. Treat
        # that operand as a nested shell command for policy analysis. This is
        # analysis-only and never evaluates caller input.
        if (( wrapper_split_string_pending )); then
            inner=$(_agent_gate_normalize_command_paths "$plain")
            output+=" $inner"
            wrapper_split_string_pending=0
            continue
        fi

        # A code operand to sh -c is itself a shell program. Analyze that
        # operand recursively and place it behind an explicit command boundary.
        if (( shell_code_pending )); then
            inner=$(_agent_gate_normalize_command_paths "$plain")
            output+=" ; $inner"
            shell_code_pending=0
            continue
        fi

        # find -exec/-execdir introduces a nested command position.
        if (( find_exec_pending )); then
            command="${plain##*/}"
            command="${command,,}"
            output+="${marker}${command}"
            find_exec_pending=0
            case "$command" in
                sh|bash|dash|zsh) find_embedded_shell=1 ;;
                *) find_embedded_shell=0 ;;
            esac
            continue
        fi

        if (( at_command )); then
            if (( function_name_pending )); then
                output+="$plain"
                function_name_pending=0
                at_command=1
                continue
            fi
            # Shell control words introduce (or preserve) a real command
            # position; they are syntax, not the executable. Treat `)` as a
            # boundary as well so case-pattern actions are analyzed.
            case "$plain" in
                function)
                    output+="$raw"
                    function_name_pending=1
                    at_command=1
                    continue
                    ;;
                if|then|elif|else|while|until|do|fi|done|'esac'|in|'!'|'{'|'}'|for|select|case)
                    output+="$raw"
                    at_command=1
                    continue
                    ;;
            esac

            # Assignment words precede, but do not consume, a command position.
            if [[ -z "$wrapper" && "$plain" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                output+="$raw"
                continue
            fi

            if [[ -n "$wrapper" ]]; then
                if (( wrapper_arg_pending )); then
                    wrapper_arg_pending=$((wrapper_arg_pending - 1))
                    continue
                fi
                if [[ "$wrapper" == timeout && "$wrapper_timeout_duration" -eq 1 &&
                      "$plain" =~ ^[0-9]+([.][0-9]+)?[smhd]?$ ]]; then
                    wrapper_timeout_duration=0
                    continue
                fi
                if [[ "$wrapper" == env && "$plain" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                    continue
                fi
                if [[ "$plain" == '--' ]]; then
                    continue
                fi
                if [[ "$plain" == -* ]]; then
                    if [[ "$wrapper" == env &&
                          ( "$plain" == --split-string=* ||
                            ( "$plain" == -S?* && "$plain" != -S ) ) ]]; then
                        if [[ "$plain" == --split-string=* ]]; then
                            inner=${plain#*=}
                        else
                            inner=${plain#-S}
                        fi
                        inner=$(_agent_gate_normalize_command_paths "$inner")
                        output+=" $inner"
                        continue
                    fi
                    case "$wrapper:$plain" in
                        env:-S|env:--split-string)
                            wrapper_split_string_pending=1
                            ;;
                        sudo:-u|sudo:--user|sudo:-g|sudo:--group|sudo:-h|sudo:--host|sudo:-p|sudo:--prompt|sudo:-C|sudo:--chdir|sudo:-R|sudo:--role|sudo:-T|sudo:--command-timeout|sudo:-D|sudo:--chroot|sudo:-U|sudo:--other-user|sudo:-t|sudo:--type|\
                        env:-u|env:--unset|env:-C|env:--chdir|\
                        nice:-n|nice:--adjustment|time:-o|time:--output|time:-f|time:--format|\
                        exec:-a|exec:--argv0|timeout:-s|timeout:--signal|timeout:-k|timeout:--kill-after|\
                        stdbuf:-i|stdbuf:--input|stdbuf:-o|stdbuf:--output|stdbuf:-e|stdbuf:--error)
                            wrapper_arg_pending=1
                            ;;
                    esac
                    continue
                fi
            fi

            command="${plain##*/}"
            command="${command,,}"
            output+="${marker}${command}"
            current_command="$command"
            at_command=0
            wrapper=""
            git_preamble=0; terraform_preamble=0; option_arg_pending=0
            case "$command" in
                sudo|env|nice|command|builtin|exec|nohup|time|timeout|stdbuf)
                    wrapper="$command"
                    at_command=1
                    current_command=""
                    [[ "$command" == timeout ]] && wrapper_timeout_duration=1
                    ;;
                git) git_preamble=1 ;;
                terraform|tofu) terraform_preamble=1 ;;
            esac
            # A non-wrapper command consumes a pending pipe; remember when a
            # shell receives it so a queued heredoc body stays shell code.
            if [[ "$wrapper" != "$command" ]] && (( pending_pipe )); then
                case "$command" in
                    sh|bash|dash|zsh) line_pipes_to_shell=1 ;;
                esac
                pending_pipe=0
            fi
            continue
        fi

        if (( find_embedded_shell )) && [[ "$plain" =~ ^-[^-]*c[^-]*$ ]]; then
            output+="$plain"
            shell_code_pending=1
            continue
        fi
        if [[ "$current_command" =~ ^(sh|bash|dash|zsh)$ && "$plain" =~ ^-[^-]*c[^-]*$ ]]; then
            output+="$plain"
            shell_code_pending=1
            continue
        fi

        if (( git_preamble )); then
            if (( option_arg_pending )); then
                option_arg_pending=$((option_arg_pending - 1))
                if (( git_config_arg_pending )) &&
                   [[ "${plain,,}" == alias.*=* ]]; then
                    output+="${marker}mainframe-inline-git-alias"
                fi
                git_config_arg_pending=0
                continue
            fi
            case "$plain" in
                -c)
                    option_arg_pending=1
                    git_config_arg_pending=1
                    continue
                    ;;
                -C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)
                    option_arg_pending=1
                    git_config_arg_pending=0
                    continue
                    ;;
                -calias.*=*)
                    output+="${marker}mainframe-inline-git-alias"
                    continue
                    ;;
                --git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|--config-env=*|-*)
                    continue
                    ;;
                *) git_preamble=0 ;;
            esac
        elif (( terraform_preamble )); then
            if (( option_arg_pending )); then
                option_arg_pending=$((option_arg_pending - 1))
                continue
            fi
            case "$plain" in
                -chdir) option_arg_pending=1; continue ;;
                -chdir=*|-*) continue ;;
                *) terraform_preamble=0 ;;
            esac
        fi

        if [[ "$current_command" == find && "$plain" =~ ^-exec(dir)?$ ]]; then
            find_exec_pending=1
        fi
        output+="$plain"
    done

    # End of input closes a heredoc body whose final line has no newline
    # (the shell accepts EOF-terminated heredocs with a warning).
    if (( body_mode )); then
        local _hd_line="$body_line"
        if (( body_tabs )); then
            while [[ "$_hd_line" == $'\t'* ]]; do _hd_line="${_hd_line#$'\t'}"; done
        fi
        [[ "$_hd_line" == "$body_delim" ]] || body_text+="$body_line"
        if (( body_code )) && [[ -n "$body_text" ]]; then
            output+=" ; "
            output+=$(_agent_gate_normalize_command_paths "$body_text")
        fi
    fi

    printf '%s' "$output"
}

# Internal: classify rm recursion/force flags independent of flag order.
# The earlier regex rules handled common `rm -rf` spellings but could miss an
# unrelated option placed first (`rm -v -rf`) or multiple long options. This
# parser examines every rm option word up to `--` without evaluating the shell.
# Prints one of: critical, high, low.
_agent_gate_rm_flag_tier() {
    local remaining="$1" args word next
    local marker=$'\036' needle
    needle="${marker}rm"
    local has_recursive has_force

    while [[ "$remaining" == *"$needle"* ]]; do
        remaining="${remaining#*"$needle"}"
        next="${remaining:0:1}"
        case "$next" in
            ''|' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')') ;;
            *) continue ;;
        esac

        args="$remaining"
        args="${args%%"$marker"*}"
        args="${args%%$'\n'*}"
        args="${args%%';'*}"
        args="${args%%'&'*}"
        args="${args%%'|'*}"
        args="${args%%'('*}"
        args="${args%%')'*}"
        has_recursive=0
        has_force=0

        # Shell word splitting is intentional and analysis-only here. Flags
        # cannot contain meaningful whitespace; quoted operands are ignored.
        for word in $args; do
            word="${word#\"}"; word="${word%\"}"
            word="${word#\'}"; word="${word%\'}"
            [[ "$word" == "--" ]] && break
            [[ "$word" == -* ]] || continue
            case "$word" in
                --recursive) has_recursive=1 ;;
                --force) has_force=1 ;;
                --*) ;;
                *)
                    [[ "$word" == *[rR]* ]] && has_recursive=1
                    [[ "$word" == *f* ]] && has_force=1
                    ;;
            esac
        done

        if (( has_recursive && has_force )); then
            printf 'critical'
            return 0
        fi
        if (( has_recursive )); then
            printf 'high'
            return 0
        fi

    done

    printf 'low'
}

# Internal: detect mutation of MAINFRAME's own runtime in one normalized
# executable segment. Read-only release preview remains allowed; update,
# confirmed upgrade, and Homebrew mutation require a human terminal.
_agent_gate_has_runtime_mutation() {
    local normalized="${1,,}" marker=$'\036' rest chunk
    local re_update='^mainframe[[:space:]]+update([[:space:];&|()]|$)'
    local re_upgrade='^mainframe[[:space:]]+upgrade([[:space:];&|()]|$)'
    local re_uninstall='^mainframe[[:space:]]+uninstall([[:space:];&|()]|$)'
    local re_dry_run='(^|[[:space:]])--dry-run([[:space:];&|()]|$)'
    local re_brew='^brew[[:space:]]+(upgrade|uninstall)([[:space:];&|()]|$)'
    local re_formula='(^|[[:space:]])(gtwatts/mainframe/mainframe|mainframe)([[:space:];&|()]|$)'

    rest="$normalized"
    while [[ "$rest" == *"$marker"* ]]; do
        rest="${rest#*"$marker"}"
        if [[ "$rest" == *"$marker"* ]]; then
            chunk="${rest%%"$marker"*}"
            rest="$marker${rest#*"$marker"}"
        else
            chunk="$rest"
            rest=''
        fi
        [[ "$chunk" =~ $re_update ]] && return 0
        if [[ "$chunk" =~ $re_upgrade ]] && ! [[ "$chunk" =~ $re_dry_run ]]; then
            return 0
        fi
        if [[ "$chunk" =~ $re_uninstall ]] && ! [[ "$chunk" =~ $re_dry_run ]]; then
            return 0
        fi
        if [[ "$chunk" =~ $re_brew ]] && [[ "$chunk" =~ $re_formula ]]; then
            return 0
        fi
    done
    return 1
}

# Internal: match a command string against the gate rules
# Prints: "<tier> <rule_id>" for the first (highest-severity) match
_agent_gate_match() {
    local raw="${2:-$1}" s structured raw_structured marker=$'\036'
    local LC_ALL=C dynamic_executable=false shell_eval=false
    local dynamic_shell_expansion=false unsupported_control=false
    local runtime_mutation=false
    _agent_gate_has_unsupported_control "$raw" && unsupported_control=true
    structured=$(_agent_gate_normalize_command_paths "$1")
    raw_structured=$(_agent_gate_normalize_command_paths "$raw")
    s="${structured,,}"
    if _agent_gate_has_dynamic_executable "$structured" ||
       _agent_gate_has_dynamic_executable "$raw_structured"; then
        dynamic_executable=true
    fi
    if _agent_gate_has_executable_named "$structured" eval ||
       _agent_gate_has_executable_named "$raw_structured" eval; then
        shell_eval=true
    fi
    _agent_gate_has_dynamic_shell_expansion "$raw" && dynamic_shell_expansion=true
    _agent_gate_has_runtime_mutation "$s" && runtime_mutation=true
    local rm_flag_tier
    rm_flag_tier=$(_agent_gate_rm_flag_tier "$s")

    # Regexes as variables: [[ =~ ]] parses bare >, &, |, (, ) in unquoted
    # patterns as shell syntax; indirection avoids that class of bug.
    # These two rules are intentionally conservative. A hook cannot safely
    # prove what eval, command/process substitution, or legacy backticks will
    # execute after approval, so their presence is itself a blocking risk.
    local re_sudo_rm="${marker}sudo[[:space:]]+${marker}rm([[:space:]]|$)"
    local re_mkfs="${marker}(mkfs|mkfs\\.[a-z0-9]+|newfs|mkswap)([[:space:]]|$)"
    local re_dd="${marker}dd[[:space:]][^${marker}]*of=/dev/"
    local re_diskutil="${marker}diskutil[[:space:]]+(erase|partition|unmountdisk|apfs)"
    local re_forkbomb="${marker}:\\(\\)\\{[[:space:]]+${marker}:\\|${marker}:&[[:space:]]+\\};${marker}:|${marker}:\\(\\)[[:space:]]+${marker}\\{:\\|${marker}:&\\};${marker}:"
    local re_devredir="${marker}mainframe-raw-device-redirect([[:space:]]|$)"
    local re_chmod777="${marker}chmod[[:space:]]+(([^${marker}]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)[[:space:]]+([^${marker}]*[[:space:]])?777([[:space:]]|$)|([^${marker}]*[[:space:]])?777[[:space:]]+([^${marker}]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$))"
    local re_chownR="${marker}chown[[:space:]]+([^${marker}]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$)"
    local re_gitclean="${marker}git[[:space:]]+clean[[:space:]]+([^${marker}]*[[:space:]])?-[a-zA-Z]*[fxd][a-zA-Z]*([[:space:]]|$)"
    local re_gitreset="${marker}git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$)"
    local re_dockerprune="${marker}docker[[:space:]]+system[[:space:]]+prune[^${marker}]*(-a|--all|--volumes)"
    local re_kubectl="${marker}kubectl[[:space:]]+delete([[:space:]]|$)"
    local re_tfdestroy="${marker}(terraform|tofu)[[:space:]]+destroy([[:space:]]|$)"
    local re_s3rm="${marker}aws[[:space:]]+s3[[:space:]]+rm[^${marker}]*--recursive"
    local re_finddelete="${marker}find[[:space:]][^${marker}]*-delete([[:space:]]|$)"
    local re_xargsrm="\\|[[:space:]]*${marker}xargs[[:space:]][^${marker}]*rm([[:space:]]|$)"
    local re_rsyncdel="${marker}rsync[[:space:]][^${marker}]*--delete"
    local re_pipeshell="\\|[[:space:]]*(${marker}(sudo|env|nice|command|nohup|time)[[:space:]]*)*${marker}(bash|sh|dash|zsh)([[:space:]]|$)"
    local re_pushmirror="${marker}git[[:space:]]+push[[:space:]][^${marker}]*--mirror"
    local re_killall1="${marker}kill[[:space:]]+(-9|-kill)[[:space:]]+-1([[:space:]]|$)"
    local re_pushforce="${marker}git[[:space:]]+push[[:space:]][^${marker}]*(--force|-f)([[:space:]]|$)"
    local re_findexec="${marker}find[[:space:]][^${marker}]*-exec[[:space:]]+${marker}(sh|bash|dash|zsh|rm)([[:space:]]|$)"
    local re_pyrmtree="${marker}python[0-9.]*[[:space:]][^${marker}]*(rmtree|os\\.remove|os\\.unlink|os\\.rmdir|\\.unlink\\()"
    local re_perlunlink="${marker}perl[[:space:]][^${marker}]*(unlink|rmtree)"
    local re_rbrm="${marker}ruby[[:space:]][^${marker}]*(rm_rf|rmtree|fileutils)"
    local re_noderm="${marker}node[[:space:]][^${marker}]*(rmsync|unlinksync|fs\\.rm)"
    local re_project_memory_init="${marker}mainframe[[:space:]]+awm[[:space:]]+(project[[:space:]]+ensure([[:space:]]|$)|init[[:space:]][^${marker}]*--namespace(=|[[:space:]]+)projects([[:space:]]|$))|${marker}awm_project_ensure([[:space:]]|$)|${marker}awm_init[[:space:]][^${marker}]*--namespace(=|[[:space:]]+)projects([[:space:]]|$)"
    local re_project_memory_close="${marker}mainframe[[:space:]]+awm[[:space:]]+project[[:space:]]+close([[:space:]]|$)"
    local re_mainframe_yes="${marker}mainframe[[:space:]][^${marker}]*--yes([[:space:]]|$)"
    local re_truncate="${marker}truncate[[:space:]]+(-s|--size)[[:space:]]"
    local re_gitwipe="${marker}git[[:space:]]+(checkout|restore)[[:space:]]+(--[[:space:]]+)?\\.([[:space:]]|$)"
    local re_killall="${marker}killall([[:space:]]|$)"
    local re_npmpub="${marker}npm[[:space:]]+publish([[:space:]]|$)"
    local re_crontab="${marker}crontab[[:space:]]+-r([[:space:]]|$)"
    local re_launchctl="${marker}launchctl[[:space:]]+(load|unload|remove|kickstart)([[:space:]]|$)"
    local re_inline_git_alias="${marker}mainframe-inline-git-alias([[:space:]]|$)"

    # --- critical -------------------------------------------------------------
    [[ "$unsupported_control" == "true" ]] \
        && { printf 'critical unsupported-control-byte'; return 0; }
    [[ "$dynamic_executable" == "true" ]] \
        && { printf 'critical dynamic-executable-word'; return 0; }
    [[ "$shell_eval" == "true" ]] \
        && { printf 'critical shell-eval'; return 0; }
    [[ "$dynamic_shell_expansion" == "true" ]] \
        && { printf 'critical dynamic-shell-expansion'; return 0; }
    [[ "$s" =~ $re_inline_git_alias ]] \
        && { printf 'critical inline-git-alias'; return 0; }
    [[ "$rm_flag_tier" == "critical" ]] \
        && { printf 'critical recursive-force-rm'; return 0; }
    [[ "$s" =~ $re_sudo_rm ]]  && { printf 'critical sudo-rm'; return 0; }
    [[ "$s" =~ $re_mkfs ]]     && { printf 'critical filesystem-format'; return 0; }
    [[ "$s" =~ $re_dd ]]       && { printf 'critical dd-raw-disk-write'; return 0; }
    [[ "$s" =~ $re_diskutil ]] && { printf 'critical diskutil-erase'; return 0; }
    [[ "$s" =~ $re_forkbomb ]] && { printf 'critical fork-bomb'; return 0; }
    [[ "$s" =~ $re_devredir ]] && { printf 'critical raw-device-redirect'; return 0; }

    # --- high -----------------------------------------------------------------
    [[ "$rm_flag_tier" == "high" ]] \
        && { printf 'high rm-recursive'; return 0; }
    [[ "$s" =~ $re_chmod777 ]]   && { printf 'high chmod-recursive-777'; return 0; }
    [[ "$s" =~ $re_chownR ]]     && { printf 'high chown-recursive'; return 0; }
    [[ "$s" =~ $re_gitclean ]]   && { printf 'high git-clean-destructive'; return 0; }
    [[ "$s" =~ $re_gitreset ]]   && { printf 'high git-reset-hard'; return 0; }
    [[ "$s" =~ $re_dockerprune ]] && { printf 'high docker-system-prune'; return 0; }
    [[ "$s" =~ $re_kubectl ]]    && { printf 'high kubectl-delete'; return 0; }
    [[ "$s" =~ $re_tfdestroy ]]  && { printf 'high terraform-destroy'; return 0; }
    [[ "$s" =~ $re_s3rm ]]       && { printf 'high s3-recursive-delete'; return 0; }
    [[ "$s" =~ $re_finddelete ]] && { printf 'high find-delete'; return 0; }
    [[ "$s" =~ $re_xargsrm ]]    && { printf 'high xargs-rm-pipeline'; return 0; }
    [[ "$s" =~ $re_rsyncdel ]]   && { printf 'high rsync-delete'; return 0; }
    [[ "$s" =~ $re_pipeshell ]]  && { printf 'high opaque-pipe-to-shell'; return 0; }
    [[ "$s" =~ $re_pushmirror ]] && { printf 'high git-push-mirror'; return 0; }
    [[ "$s" =~ $re_killall1 ]]   && { printf 'high kill-all-processes'; return 0; }
    [[ "$s" =~ $re_findexec ]]    && { printf 'high find-exec-shell'; return 0; }
    [[ "$s" =~ $re_pyrmtree ]]    && { printf 'high python-rmtree'; return 0; }
    [[ "$s" =~ $re_perlunlink ]]  && { printf 'high perl-unlink'; return 0; }
    [[ "$s" =~ $re_rbrm ]]        && { printf 'high ruby-rmrf'; return 0; }
    [[ "$s" =~ $re_noderm ]]      && { printf 'high node-rmsync'; return 0; }
    [[ "$s" =~ $re_project_memory_init ]] \
        && { printf 'high mainframe-project-memory-initialization'; return 0; }
    [[ "$s" =~ $re_project_memory_close ]] \
        && { printf 'high mainframe-project-memory-close'; return 0; }
    [[ "$s" =~ $re_mainframe_yes ]] \
        && { printf 'high mainframe-explicit-confirmation'; return 0; }
    [[ "$runtime_mutation" == "true" ]] \
        && { printf 'high mainframe-runtime-mutation'; return 0; }

    # --- medium ---------------------------------------------------------------
    [[ "$s" =~ $re_pushforce ]]  && { printf 'medium git-push-force'; return 0; }
    [[ "$s" =~ $re_truncate ]]    && { printf 'medium truncate-resize'; return 0; }
    [[ "$s" =~ $re_gitwipe ]]    && { printf 'medium git-worktree-reset'; return 0; }
    [[ "$s" =~ $re_killall ]]    && { printf 'medium killall'; return 0; }
    [[ "$s" =~ $re_npmpub ]]     && { printf 'medium npm-publish'; return 0; }
    [[ "$s" =~ $re_crontab ]]    && { printf 'medium crontab-remove'; return 0; }
    [[ "$s" =~ $re_launchctl ]]  && { printf 'medium launchctl-mutate'; return 0; }

    printf 'low none'
    return 0
}

# Classify a command string against the destructive-command gate
# @returns: 0 always; JSON on stdout: {"risk":...,"rule":...,"blocked":...}
#
# blocked=true when the tier meets or exceeds AGENT_GATE_BLOCK_TIER
# (default: high; critical/high block, medium/low pass).
#
# Usage: agent_gate_classify "rm -rf /tmp/x"
#        agent_gate_classify "${cmd[*]}"
agent_gate_classify() {
    local raw_cmd="$*" cmd_string
    cmd_string=$(_agent_resolve_command "$raw_cmd")
    local block_tier="${AGENT_GATE_BLOCK_TIER:-high}"

    local match tier rule
    match=$(_agent_gate_match "$cmd_string" "$raw_cmd")
    tier="${match%% *}"
    rule="${match#* }"

    local blocked=false
    case "$block_tier" in
        critical) [[ "$tier" == "critical" ]] && blocked=true ;;
        high)     [[ "$tier" == "critical" || "$tier" == "high" ]] && blocked=true ;;
        medium)   [[ "$tier" != "low" ]] && blocked=true ;;
        *)        blocked=false ;;
    esac

    printf '{"risk":"%s","rule":"%s","blocked":%s}\n' "$tier" "$rule" "$blocked"
}

# =============================================================================
# RISK ASSESSMENT
# =============================================================================

# Calculate risk score for a command (0-100)
# @returns: risk score via stdout
#
# Usage: score=$(agent_risk_score "rm" "-rf" "/tmp/test")
agent_risk_score() {
    if ! _agent_normalize_argv "$@"; then
        return 1
    fi
    local cmd="${_AGENT_NORMALIZED_ARGV[0]}"
    local -a args=("${_AGENT_NORMALIZED_ARGV[@]:1}")
    local score=0

    # Base risk for dangerous commands
    case "$cmd" in
        rm|rmdir|unlink)
            score=$((score + 30))
            # Higher risk for recursive (handles -r, -rf, -r -f, --recursive)
            local _rs_r=0 _rs_f=0 _rs_arg
            for _rs_arg in "${args[@]}"; do
                [[ "$_rs_arg" == "--" ]] && break
                [[ "$_rs_arg" != -* ]] && continue
                case "$_rs_arg" in
                    --recursive) _rs_r=1 ;;
                    --force) _rs_f=1 ;;
                    --*) ;;
                    *)
                        [[ "$_rs_arg" == *[rR]* ]] && _rs_r=1
                        [[ "$_rs_arg" == *f* ]] && _rs_f=1
                        ;;
                esac
            done
            (( _rs_r )) && score=$((score + 20))
            (( _rs_f )) && score=$((score + 10))
            ;;
        dd|mkfs|mkfs.*|mkswap|newfs|fdisk|parted|diskutil|shred|wipe|hdparm|nvme)
            score=$((score + 80))
            ;;
        chmod|chown)
            score=$((score + 40))
            # Recursive increases risk
            [[ " ${args[*]} " == *" -R "* ]] && score=$((score + 20))
            ;;
        kill|killall|pkill)
            score=$((score + 50))
            # -9 is more dangerous
            [[ " ${args[*]} " == *" -9 "* || " ${args[*]} " == *" KILL "* ]] && score=$((score + 20))
            ;;
        reboot|shutdown|halt|poweroff)
            score=$((score + 90))
            ;;
        curl|wget)
            score=$((score + 20))
            # Executing downloaded content increases risk
            [[ " ${args[*]} " == *" | "* ]] && score=$((score + 40))
            ;;
        systemctl|service)
            score=$((score + 60))
            ;;
        *)
            score=10  # Default low risk
            ;;
    esac

    # Path-based risk adjustments
    local arg
    for arg in "${args[@]}"; do
        [[ "$arg" == -* ]] && continue

        # Critical system paths
        case "$arg" in
            /|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/boot|/boot/*)
                score=$((score + 30))
                ;;
            /home|/home/*)
                score=$((score + 10))
                ;;
            /tmp|/tmp/*|/var/tmp|/var/tmp/*)
                # Temp directories are lower risk
                ;;
        esac
    done

    # Cap at 100
    (( score > 100 )) && score=100

    printf '%d' "$score"
}

# Check if command requires confirmation based on risk
# @returns: 0 if requires confirmation, 1 if safe to proceed
#
# Usage: agent_requires_confirmation "rm" "-rf" "/important"
agent_requires_confirmation() {
    local score
    score=$(agent_risk_score "$@")
    (( score >= AGENT_RISK_THRESHOLD ))
}

# =============================================================================
# EXECUTION APPROVAL
# =============================================================================
# Above-threshold commands are blocked unless explicitly approved. Two
# approval channels:
#   1. AGENT_APPROVED=1 - one-shot operator approval (consumed on use)
#   2. An approval callback registered via agent_register_approval_callback
#      (receives the command argv, returns 0 to approve)

# Registered approval callback (function name, empty = none)
declare -g _AGENT_APPROVAL_CALLBACK=""

# Register a callback invoked to approve above-threshold commands
# @pre: function must be defined
# @returns: 0 on success, 1 if function not defined
#
# Usage: agent_register_approval_callback "my_approval_fn"
agent_register_approval_callback() {
    local name="$1"

    if [[ -z "$name" ]]; then
        agent_error "callback name required"
        return 1
    fi

    if ! declare -F "$name" &>/dev/null; then
        agent_error "callback '$name' is not a defined function"
        return 1
    fi

    _AGENT_APPROVAL_CALLBACK="$name"
    _AGENT_ALLOWED_CALLBACKS["$name"]=1
    agent_audit "approval_callback_registered" "name=$name"
    return 0
}

# Clear the approval callback
# @returns: 0
agent_clear_approval_callback() {
    _AGENT_APPROVAL_CALLBACK=""
    return 0
}

# Internal: check whether an above-threshold command is approved
# @returns: 0 if approved, 1 otherwise
_agent_execution_approved() {
    # One-shot operator approval via environment (consumed on use)
    case "${AGENT_APPROVED:-0}" in
        1|true|yes|TRUE|YES)
            AGENT_APPROVED=0
            return 0
            ;;
    esac

    # Approval callback receives the command argv; 0 = approve
    if [[ -n "$_AGENT_APPROVAL_CALLBACK" ]]; then
        if "$_AGENT_APPROVAL_CALLBACK" "$@"; then
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# RATE LIMITING
# =============================================================================
# An agent in a retry loop can do a lot of damage fast even when every
# individual command is allowed. When AGENT_RATE_LIMIT > 0, at most that
# many executions may pass through agent_safe_exec/_capture per
# AGENT_RATE_WINDOW seconds; the excess blocks with a structured error.

# Internal: sliding-window rate check (records this execution on success)
_agent_rate_check() {
    (( AGENT_RATE_LIMIT <= 0 )) && return 0

    local now cutoff t
    now=$(date +%s)
    cutoff=$(( now - AGENT_RATE_WINDOW ))

    local -a recent=()
    for t in "${_AGENT_EXEC_TIMES[@]:-}"; do
        [[ -n "$t" ]] && (( t >= cutoff )) && recent+=("$t")
    done
    _AGENT_EXEC_TIMES=("${recent[@]}")

    if (( ${#_AGENT_EXEC_TIMES[@]} >= AGENT_RATE_LIMIT )); then
        agent_audit "exec_blocked_rate" "count=${#_AGENT_EXEC_TIMES[@]}" "window=$AGENT_RATE_WINDOW" "limit=$AGENT_RATE_LIMIT"
        agent_error "rate limit exceeded: ${#_AGENT_EXEC_TIMES[@]} executions in ${AGENT_RATE_WINDOW}s (limit $AGENT_RATE_LIMIT)" \
            "suggestion=Slow down, batch operations, or raise AGENT_RATE_LIMIT"
        return 1
    fi

    _AGENT_EXEC_TIMES+=("$now")
    return 0
}

# =============================================================================
# ANOMALY DETECTION ON THE EXECUTION STREAM
# =============================================================================
# Rate limiting caps VOLUME. Anomaly detection spots PATTERNS that indicate
# an agent has lost the plot even when each command is individually allowed:
#   1. Identical-command burst: the same command string repeatedly executed
#      (retry loop) - AGENT_ANOMALY_BURST_LIMIT per AGENT_RATE_WINDOW seconds
#   2. Blocked-command probing: a streak of consecutively blocked commands
#      (guessing/probing around the gate) - AGENT_ANOMALY_BLOCK_LIMIT
#
# Modes (AGENT_ANOMALY_MODE):
#   off  - disabled (default)
#   warn - audit + structured stderr warning, execution continues
#   pause- auto-pause the profile: subsequent executions require
#          AGENT_APPROVED=1 to resume (agent_anomaly_resume)

declare -g AGENT_ANOMALY_MODE="${AGENT_ANOMALY_MODE:-off}"
declare -g AGENT_ANOMALY_BURST_LIMIT="${AGENT_ANOMALY_BURST_LIMIT:-8}"
declare -g AGENT_ANOMALY_BLOCK_LIMIT="${AGENT_ANOMALY_BLOCK_LIMIT:-5}"
declare -g _AGENT_PAUSED=0
declare -gA _AGENT_CMD_HISTORY=()   # cmd -> "count:first_ts"
declare -g _AGENT_BLOCKED_STREAK=0

# Internal: evaluate one command string against the anomaly rules.
# Sets _AGENT_ANOMALY_RESULT (empty when clean). Called DIRECTLY, never
# via $() - it mutates the history array, which a subshell would discard.
_AGENT_ANOMALY_RESULT=""
_agent_anomaly_eval() {
    _AGENT_ANOMALY_RESULT=""
    local cmd_str="$1"
    local now
    now=$(date +%s)
    local cutoff=$(( now - AGENT_RATE_WINDOW ))

    # Rule 1: identical-command burst within the window
    local entry="${_AGENT_CMD_HISTORY[$cmd_str]:-0:$now}"
    local count="${entry%%:*}" first_ts="${entry##*:}"
    (( first_ts < cutoff )) && { count=0; first_ts=$now; }
    count=$(( count + 1 ))
    _AGENT_CMD_HISTORY[$cmd_str]="$count:$first_ts"
    if (( count >= AGENT_ANOMALY_BURST_LIMIT )); then
        _AGENT_ANOMALY_RESULT="burst-identical"
        return 0
    fi

    # Rule 2: consecutive blocked streak (fed by _agent_anomaly_note_blocked)
    if (( _AGENT_BLOCKED_STREAK >= AGENT_ANOMALY_BLOCK_LIMIT )); then
        _AGENT_ANOMALY_RESULT="probing-streak"
        return 0
    fi

    return 0
}

# Internal: record a blocked execution (resets on successful execution)
_agent_anomaly_note_blocked() {
    _AGENT_BLOCKED_STREAK=$(( _AGENT_BLOCKED_STREAK + 1 ))
}

# Internal: record a successful execution
_agent_anomaly_note_success() {
    _AGENT_BLOCKED_STREAK=0
}

# Internal: act on an anomaly evaluation result per AGENT_ANOMALY_MODE
_agent_anomaly_check() {
    local cmd_str="$1"
    [[ "$AGENT_ANOMALY_MODE" == "off" ]] && return 0

    _agent_anomaly_eval "$cmd_str"
    local anomaly="$_AGENT_ANOMALY_RESULT"
    [[ -z "$anomaly" ]] && return 0

    agent_audit "anomaly_detected" "type=$anomaly" "cmd=$cmd_str" "mode=$AGENT_ANOMALY_MODE"

    if [[ "$AGENT_ANOMALY_MODE" == "warn" ]]; then
        agent_error "anomaly detected ($anomaly): execution continues (warn mode)" \
            "cmd=$cmd_str" \
            "suggestion=Review the agent's recent behavior; set AGENT_ANOMALY_MODE=pause for enforcement"
        return 0   # warn: non-fatal
    fi

    # pause mode: engage the pause latch
    _AGENT_PAUSED=1
    agent_audit "anomaly_pause_engaged" "type=$anomaly" "cmd=$cmd_str"
    agent_error "execution paused: anomaly detected ($anomaly)" \
        "cmd=$cmd_str" \
        "suggestion=Human review required; resume with AGENT_APPROVED=1 or agent_anomaly_resume"
    return 1
}

# Resume from an anomaly pause (requires AGENT_APPROVED=1)
agent_anomaly_resume() {
    if [[ "${AGENT_APPROVED:-0}" != "1" ]]; then
        agent_error "resume requires AGENT_APPROVED=1"
        return 1
    fi
    _AGENT_PAUSED=0
    _AGENT_BLOCKED_STREAK=0
    AGENT_APPROVED=0
    agent_audit "anomaly_pause_resumed" "pid=$$"
    agent_success "anomaly pause cleared"
}

# =============================================================================
# GATE TELEMETRY
# =============================================================================

# Analyze the agent audit log into gate telemetry (JSON on stdout).
# Reports execution volume, block reasons, anomalies, top triggered rules,
# and false-positive candidates (commands blocked then later approved -
# operator overrides are the best available FP signal for gate tuning).
# Pure awk implementation (zero-dependency discipline).
#
# Usage: agent_gate_report [audit_log_path]
agent_gate_report() {
    local log_file="${1:-$AGENT_AUDIT_LOG}"

    [[ -f "$log_file" ]] || {
        agent_error "no audit log at $log_file"
        return 1
    }

    awk '
    function count(s) { return (s in c) ? c[s] : 0 }
    {
        action = ""
        if (match($0, /"action":"[^"]*"/)) {
            action = substr($0, RSTART + 10, RLENGTH - 11)
            c[action]++
        }
        cmd = ""
        if (match($0, /cmd=[^,"]*/)) {
            cmd = substr($0, RSTART + 4, RLENGTH - 4)
        }
        if (action ~ /^exec(_capture)?_blocked_risk$/) blocked[cmd] = 1
        if (action ~ /^exec(_capture)?_approved$/) approved[cmd] = 1
        if (action == "anomaly_detected") {
            if (match($0, /"type=[^,"]*"?/)) {
                t = substr($0, RSTART + 6, RLENGTH - 6)
                sub(/"$/, "", t)
                atypes[t]++
            }
        }
    }
    END {
        started = count("exec_start") + count("exec_capture_start")
        completed = count("exec_complete") + count("exec_capture_complete")
        appr = count("exec_approved") + count("exec_capture_approved")
        br = count("exec_blocked_risk") + count("exec_capture_blocked_risk")
        brl = count("exec_blocked_rate")
        bp = count("exec_blocked_paused") + count("exec_capture_blocked_paused")
        ad = count("anomaly_detected")
        ap = count("anomaly_pause_engaged")

        # false-positive candidates: blocked then later approved
        nfp = 0
        fp_json = ""
        for (cmd in blocked) {
            if (cmd in approved && cmd != "") {
                nfp++
                gsub(/\\/, "\\\\", cmd); gsub(/"/, "\\\"", cmd)
                if (nfp <= 20) fp_json = fp_json (fp_json ? "," : "") "\"" cmd "\""
            }
        }

        # top 5 anomaly types
        top_json = ""
        n = 0
        for (t in atypes) {
            n++
            top_json = top_json (top_json ? "," : "") "{\"type\":\"" t "\",\"count\":" atypes[t] "}"
        }

        printf "{\n"
        printf "  \"executions_started\": %d,\n", started
        printf "  \"executions_completed\": %d,\n", completed
        printf "  \"approved\": %d,\n", appr
        printf "  \"blocked_risk\": %d,\n", br
        printf "  \"blocked_rate_limited\": %d,\n", brl
        printf "  \"blocked_paused\": %d,\n", bp
        printf "  \"anomalies_detected\": %d,\n", ad
        printf "  \"anomaly_pauses\": %d,\n", ap
        printf "  \"top_anomaly_types\": [%s],\n", top_json
        printf "  \"fp_candidates\": [%s],\n", fp_json
        printf "  \"fp_candidate_count\": %d\n", nfp
        printf "}\n"
    }
    ' "$log_file"
}

# =============================================================================
# SAFE COMMAND DISPATCH (NO EVAL)
# =============================================================================

# Execute command with full safety checks and audit trail
# @pre: command validated
# @post: command executed with audit logging
# @returns: command's exit code (1 with structured error if blocked)
#
# Commands whose risk score meets or exceeds AGENT_RISK_THRESHOLD are
# BLOCKED unless approved via AGENT_APPROVED=1 (one-shot) or an approval
# callback (agent_register_approval_callback). Advisory scoring is not a
# guardrail - enforcement happens here.
#
# Usage: agent_safe_exec ls -la /tmp
#        agent_safe_exec "ls -la /tmp"   # string form, safely tokenized
agent_safe_exec() {
    if ! _agent_normalize_argv "$@"; then
        return 1
    fi
    local -a cmd=("${_AGENT_NORMALIZED_ARGV[@]}")

    if (( ${#cmd[@]} == 0 )); then
        agent_error "no command provided"
        return 1
    fi

    # Pre-execution validation (policy -> existence -> confinement)
    if ! agent_validate_command "${cmd[@]}"; then
        return 1
    fi

    # Anomaly pause latch: after an anomaly, everything requires a resume
    if (( _AGENT_PAUSED )); then
        agent_audit "exec_blocked_paused" "cmd=${cmd[*]}"
        agent_error "execution paused: anomaly latch engaged" \
            "suggestion=Resume with agent_anomaly_resume (requires AGENT_APPROVED=1)"
        return 1
    fi

    # Risk assessment (on the resolved command: indirection is analyzed,
    # execution still uses the original argv)
    local risk_score
    local _resolved_cmd
    _resolved_cmd=$(_agent_resolve_command "${cmd[*]}")
    # shellcheck disable=SC2086
    risk_score=$(agent_risk_score $_resolved_cmd) || risk_score=""
    # Resolution can produce operators the tokenizer rejects; fall back
    if [[ -z "$risk_score" ]]; then
        risk_score=$(agent_risk_score "${cmd[@]}")
    fi

    # Floor the score via the destructive-command gate (string patterns)
    local _gate_match
    _gate_match=$(_agent_gate_match "$_resolved_cmd")
    case "${_gate_match%% *}" in
        critical) (( risk_score < 90 )) && risk_score=90 ;;
        high)     (( risk_score < 60 )) && risk_score=60 ;;
        medium)   (( risk_score < 30 )) && risk_score=30 ;;
    esac

    # Enforce the risk threshold
    if (( risk_score >= AGENT_RISK_THRESHOLD )); then
        if _agent_execution_approved "${cmd[@]}"; then
            agent_audit "exec_approved" "cmd=${cmd[*]}" "risk=$risk_score" "profile=$AGENT_CURRENT_PROFILE"
        else
            agent_audit "exec_blocked_risk" "cmd=${cmd[*]}" "risk=$risk_score" "threshold=$AGENT_RISK_THRESHOLD" "profile=$AGENT_CURRENT_PROFILE"
            _agent_anomaly_note_blocked
            agent_error "command blocked: risk score $risk_score meets threshold $AGENT_RISK_THRESHOLD" \
                "cmd=${cmd[*]}" \
                "risk_score=$risk_score" \
                "threshold=$AGENT_RISK_THRESHOLD" \
                "suggestion=Obtain operator approval (AGENT_APPROVED=1) or register an approval callback"
            return 1
        fi
    fi

    # Audit the execution attempt
    agent_audit "exec_start" "cmd=${cmd[*]}" "risk=$risk_score" "profile=$AGENT_CURRENT_PROFILE"

    # Rate limiting (only executions that passed all gates count)
    if ! _agent_rate_check; then
        _agent_anomaly_note_blocked
        return 1
    fi

    # Anomaly detection (burst/probing patterns)
    if ! _agent_anomaly_check "${cmd[*]}"; then
        return 1
    fi

    # Execute the command (array expansion preserves arguments; no shell)
    local exit_code
    "${cmd[@]}"
    exit_code=$?

    (( exit_code == 0 )) && _agent_anomaly_note_success

    # Audit the result
    agent_audit "exec_complete" "cmd=${cmd[0]}" "exit_code=$exit_code"

    return $exit_code
}

# Execute command capturing output for structured result
# @returns: 0 on success with JSON output, 1 on failure with JSON error
#
# Usage: agent_safe_exec_capture ls -la /tmp
agent_safe_exec_capture() {
    if ! _agent_normalize_argv "$@"; then
        return 1
    fi
    local -a cmd=("${_AGENT_NORMALIZED_ARGV[@]}")

    if (( ${#cmd[@]} == 0 )); then
        agent_error "no command provided"
        return 1
    fi

    # Pre-execution validation (policy -> existence -> confinement)
    if ! agent_validate_command "${cmd[@]}"; then
        return 1
    fi

    # Anomaly pause latch: after an anomaly, everything requires a resume
    if (( _AGENT_PAUSED )); then
        agent_audit "exec_capture_blocked_paused" "cmd=${cmd[*]}"
        agent_error "execution paused: anomaly latch engaged" \
            "suggestion=Resume with agent_anomaly_resume (requires AGENT_APPROVED=1)"
        return 1
    fi

    # Enforce the risk threshold (same gate as agent_safe_exec)
    local risk_score
    local _resolved_cmd
    _resolved_cmd=$(_agent_resolve_command "${cmd[*]}")
    # shellcheck disable=SC2086
    risk_score=$(agent_risk_score $_resolved_cmd) || risk_score=""
    if [[ -z "$risk_score" ]]; then
        risk_score=$(agent_risk_score "${cmd[@]}")
    fi

    # Floor the score via the destructive-command gate (string patterns)
    local _gate_match
    _gate_match=$(_agent_gate_match "$_resolved_cmd")
    case "${_gate_match%% *}" in
        critical) (( risk_score < 90 )) && risk_score=90 ;;
        high)     (( risk_score < 60 )) && risk_score=60 ;;
        medium)   (( risk_score < 30 )) && risk_score=30 ;;
    esac

    if (( risk_score >= AGENT_RISK_THRESHOLD )); then
        if _agent_execution_approved "${cmd[@]}"; then
            agent_audit "exec_capture_approved" "cmd=${cmd[*]}" "risk=$risk_score" "profile=$AGENT_CURRENT_PROFILE"
        else
            agent_audit "exec_capture_blocked_risk" "cmd=${cmd[*]}" "risk=$risk_score" "threshold=$AGENT_RISK_THRESHOLD" "profile=$AGENT_CURRENT_PROFILE"
            _agent_anomaly_note_blocked
            agent_error "command blocked: risk score $risk_score meets threshold $AGENT_RISK_THRESHOLD" \
                "cmd=${cmd[*]}" \
                "risk_score=$risk_score" \
                "threshold=$AGENT_RISK_THRESHOLD" \
                "suggestion=Obtain operator approval (AGENT_APPROVED=1) or register an approval callback"
            return 1
        fi
    fi

    agent_audit "exec_capture_start" "cmd=${cmd[*]}"

    # Rate limiting (only executions that passed all gates count)
    if ! _agent_rate_check; then
        _agent_anomaly_note_blocked
        return 1
    fi

    # Anomaly detection (burst/probing patterns)
    if ! _agent_anomaly_check "${cmd[*]}"; then
        return 1
    fi

    # Capture both stdout and stderr
    local stdout exit_code
    stdout=$("${cmd[@]}" 2>&1)
    exit_code=$?

    agent_audit "exec_capture_complete" "cmd=${cmd[0]}" "exit_code=$exit_code"

    if (( exit_code == 0 )); then
        agent_success "command completed" "cmd=${cmd[0]}" "output=$stdout"
    else
        agent_error "command failed with exit code $exit_code" \
            "cmd=${cmd[*]}" \
            "output=$stdout" \
            "suggestion=Check command syntax and permissions"
    fi

    return $exit_code
}

# =============================================================================
# IDEMPOTENT OPERATIONS
# =============================================================================

# Ensure file exists with exact content (idempotent)
# @pre: parent directory exists or will be created
# @post: file contains exactly the given content
# @idempotent: yes - no-op if file already has correct content
# @returns: 0 on success (with JSON output)
#
# Usage: agent_ensure_file "/path/to/file" "content" [mode]
agent_ensure_file() {
    local path="$1"
    local content="$2"
    local mode="${3:-0644}"

    if [[ -z "$path" ]]; then
        agent_error "path required"
        return 1
    fi

    # Profile permission check
    if (( ! ${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0} )); then
        agent_error "write operation not allowed in profile '$AGENT_CURRENT_PROFILE'"
        return 1
    fi

    # Path safety check
    if [[ -n "$AGENT_SAFE_BASE" ]]; then
        if ! _agent_validate_path_safe "$path" "$AGENT_SAFE_BASE"; then
            agent_error "path outside safe base" "path=$path" "base=$AGENT_SAFE_BASE"
            return 1
        fi
    fi

    # Check if file already has correct content
    if [[ -f "$path" ]]; then
        local current
        current=$(<"$path")
        if [[ "$current" == "$content" ]]; then
            agent_audit "ensure_file_unchanged" "path=$path"
            agent_success "file already correct" "path=$path" "action=none"
            return 0
        fi
    fi

    # Create parent directory if needed
    local parent_dir
    parent_dir=$(dirname "$path")
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || {
            agent_error "failed to create parent directory" "path=$parent_dir"
            return 1
        }
    fi

    # Write atomically if atomic_write is available
    if declare -F atomic_write &>/dev/null; then
        atomic_write "$path" "$content" "$mode" || {
            agent_error "failed to write file" "path=$path"
            return 1
        }
    else
        # Fallback: direct write
        printf '%s' "$content" > "$path" || {
            agent_error "failed to write file" "path=$path"
            return 1
        }
        chmod "$mode" "$path"
    fi

    agent_audit "ensure_file_written" "path=$path" "mode=$mode"
    agent_success "file written" "path=$path" "action=created"
}

# Ensure directory exists (idempotent)
# @pre: parent exists or will be created
# @post: directory exists with given mode
# @idempotent: yes - no-op if directory already exists
# @returns: 0 on success (with JSON output)
#
# Usage: agent_ensure_dir "/path/to/dir" [mode]
agent_ensure_dir() {
    local path="$1"
    local mode="${2:-0755}"

    if [[ -z "$path" ]]; then
        agent_error "path required"
        return 1
    fi

    # Profile permission check
    if (( ! ${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0} )); then
        agent_error "write operation not allowed in profile '$AGENT_CURRENT_PROFILE'"
        return 1
    fi

    # Path safety check
    if [[ -n "$AGENT_SAFE_BASE" ]]; then
        if ! _agent_validate_path_safe "$path" "$AGENT_SAFE_BASE"; then
            agent_error "path outside safe base" "path=$path" "base=$AGENT_SAFE_BASE"
            return 1
        fi
    fi

    if [[ -d "$path" ]]; then
        agent_audit "ensure_dir_exists" "path=$path"
        agent_success "directory exists" "path=$path" "action=none"
        return 0
    fi

    mkdir -p "$path" && chmod "$mode" "$path" || {
        agent_error "failed to create directory" "path=$path"
        return 1
    }

    agent_audit "ensure_dir_created" "path=$path" "mode=$mode"
    agent_success "directory created" "path=$path" "action=created"
}

# Ensure line exists in file (idempotent)
# @pre: file exists or will be created
# @post: file contains the line
# @idempotent: yes - no-op if line already exists
# @returns: 0 on success
#
# Usage: agent_ensure_line "/path/to/file" "line content"
agent_ensure_line() {
    local path="$1"
    local line="$2"

    if [[ -z "$path" ]] || [[ -z "$line" ]]; then
        agent_error "path and line required"
        return 1
    fi

    # Profile permission check
    if (( ! ${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0} )); then
        agent_error "write operation not allowed in profile '$AGENT_CURRENT_PROFILE'"
        return 1
    fi

    # Check if line exists
    if [[ -f "$path" ]] && grep -qxF "$line" "$path" 2>/dev/null; then
        agent_audit "ensure_line_exists" "path=$path"
        agent_success "line already exists" "path=$path" "action=none"
        return 0
    fi

    # Append line
    printf '%s\n' "$line" >> "$path" || {
        agent_error "failed to append line" "path=$path"
        return 1
    }

    agent_audit "ensure_line_added" "path=$path"
    agent_success "line added" "path=$path" "action=appended"
}

# Ensure symlink exists (idempotent)
# @pre: target exists
# @post: symlink points to target
# @idempotent: yes - no-op if link correct, updates if wrong
# @returns: 0 on success
#
# Usage: agent_ensure_symlink "/path/to/link" "/path/to/target"
agent_ensure_symlink() {
    local link="$1"
    local target="$2"

    if [[ -z "$link" ]] || [[ -z "$target" ]]; then
        agent_error "link and target required"
        return 1
    fi

    # Profile permission check
    if (( ! ${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0} )); then
        agent_error "write operation not allowed in profile '$AGENT_CURRENT_PROFILE'"
        return 1
    fi

    # Check if correct symlink already exists
    if [[ -L "$link" ]]; then
        local current_target
        current_target=$(readlink "$link")
        if [[ "$current_target" == "$target" ]]; then
            agent_audit "ensure_symlink_correct" "link=$link" "target=$target"
            agent_success "symlink correct" "link=$link" "action=none"
            return 0
        fi
        # Wrong target, remove and recreate
        rm -f "$link"
    elif [[ -e "$link" ]]; then
        agent_error "path exists and is not a symlink" "path=$link"
        return 1
    fi

    ln -s "$target" "$link" || {
        agent_error "failed to create symlink" "link=$link" "target=$target"
        return 1
    }

    agent_audit "ensure_symlink_created" "link=$link" "target=$target"
    agent_success "symlink created" "link=$link" "action=created"
}

# Ensure command is available (idempotent check only)
# @returns: 0 if available, 1 if not (with suggestion)
#
# Usage: agent_ensure_command "git"
agent_ensure_command() {
    local cmd_name="$1"
    local package="${2:-$cmd_name}"

    if [[ -z "$cmd_name" ]]; then
        agent_error "command name required"
        return 1
    fi

    if command -v "$cmd_name" &>/dev/null; then
        agent_success "command available" "cmd=$cmd_name" "action=none"
        return 0
    fi

    agent_error "command not found: $cmd_name" \
        "suggestion=Install with: sudo apt install $package (or equivalent)"
    return 1
}

# =============================================================================
# AUDIT TRAIL
# =============================================================================

# Internal: encode one Bash string as JSON string content without invoking a
# parser or trusting locale character classes. JSON forbids every byte below
# 0x20 unless escaped; handling the full range keeps hook metadata such as tool
# names from corrupting the append-only JSONL stream.
_agent_audit_json_escape() {
    local input="$1" output="" ch code escaped i
    local LC_ALL=C

    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        case "$ch" in
            $'\\') output+='\\' ;;
            '"') output+='\"' ;;
            $'\b') output+='\b' ;;
            $'\f') output+='\f' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *)
                printf -v code '%d' "'$ch"
                if (( code < 32 )); then
                    printf -v escaped '\\u%04x' "$code"
                    output+="$escaped"
                else
                    output+="$ch"
                fi
                ;;
        esac
    done
    printf '%s' "$output"
}

# Write audit entry to log file
# @post: entry appended to AGENT_AUDIT_LOG
# @returns: 0
#
# Usage: agent_audit "action" "key1=value1" "key2=value2"
agent_audit() {
    local action="$1"
    shift

    # Build details as JSON array
    local details_json="[" escaped_action escaped_item
    local first=true
    for item in "$@"; do
        $first || details_json+=","
        first=false
        escaped_item="$(_agent_audit_json_escape "$item")"
        details_json+="\"$escaped_item\""
    done
    details_json+="]"
    escaped_action="$(_agent_audit_json_escape "$action")"

    local entry
    printf -v entry '{"ts":"%s","pid":%d,"action":"%s","details":%s}' \
        "$(date -Iseconds)" \
        "$$" \
        "$escaped_action" \
        "$details_json"

    # The privileged agent gateway supplies an already-open append descriptor
    # so a path swap after validation cannot redirect its decision record.
    if [[ "${AGENT_AUDIT_FD:-}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$entry" >&"$AGENT_AUDIT_FD"
    else
        # General library callers retain the existing rotation behavior.
        _agent_audit_rotate "$AGENT_AUDIT_LOG"
        printf '%s\n' "$entry" >> "$AGENT_AUDIT_LOG"
    fi
}

# Internal: rotate an audit log when it exceeds AGENT_AUDIT_MAX_BYTES,
# keeping AGENT_AUDIT_KEEP numbered generations (file.1 newest)
_agent_audit_rotate() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local size
    size=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
    [[ "$size" =~ ^[0-9]+$ ]] || return 0
    (( size < AGENT_AUDIT_MAX_BYTES )) && return 0

    local i
    for (( i=AGENT_AUDIT_KEEP-1; i>=1; i-- )); do
        [[ -f "$file.$i" ]] && mv -f "$file.$i" "$file.$((i+1))"
    done
    mv -f "$file" "$file.1"
    : > "$file"
    return 0
}

# Replay audit log entries
# @returns: 0
#
# Usage: agent_audit_replay [filter]
agent_audit_replay() {
    local filter="${1:-}"

    if [[ ! -f "$AGENT_AUDIT_LOG" ]]; then
        printf 'No audit log found: %s\n' "$AGENT_AUDIT_LOG" >&2
        return 0
    fi

    if [[ -z "$filter" ]]; then
        cat "$AGENT_AUDIT_LOG"
    else
        grep "$filter" "$AGENT_AUDIT_LOG"
    fi
}

# Clear audit log
# @post: audit log file truncated
# @returns: 0
#
# Usage: agent_audit_clear
agent_audit_clear() {
    : > "$AGENT_AUDIT_LOG"
    agent_audit "log_cleared"
}

# Get audit log path
# @returns: 0
#
# Usage: agent_audit_path
agent_audit_path() {
    printf '%s\n' "$AGENT_AUDIT_LOG"
}

# Get audit log statistics
# @returns: 0 (outputs JSON)
#
# Usage: agent_audit_stats
agent_audit_stats() {
    if [[ ! -f "$AGENT_AUDIT_LOG" ]]; then
        printf '{"entries":0,"size_bytes":0}\n'
        return 0
    fi

    local entries size_bytes
    entries=$(wc -l < "$AGENT_AUDIT_LOG" | tr -d ' ')
    size_bytes=$(wc -c < "$AGENT_AUDIT_LOG" | tr -d ' ')

    printf '{"entries":%d,"size_bytes":%d,"path":"%s"}\n' \
        "$entries" "$size_bytes" "${AGENT_AUDIT_LOG//\"/\\\"}"
}

# =============================================================================
# PROFILE MANAGEMENT
# =============================================================================

# Set current security profile
# @pre: profile must be valid
# @post: AGENT_CURRENT_PROFILE and AGENT_SAFE_BASE updated
# @returns: 0 on success, 1 on invalid profile
#
# Usage: agent_set_profile "project" "/path/to/project"
agent_set_profile() {
    local profile="$1"
    local base="${2:-$PWD}"

    if [[ -z "${AGENT_PROFILES[$profile]:-}" ]]; then
        agent_error "unknown profile: $profile" \
            "valid_profiles=readonly,project,system"
        return 1
    fi

    AGENT_CURRENT_PROFILE="$profile"
    AGENT_SAFE_BASE="$base"

    agent_audit "profile_set" "profile=$profile" "base=$base"
    agent_success "profile set" "profile=$profile" "base=$base"
}

# Get current profile information
# @returns: 0 (outputs JSON)
#
# Usage: agent_get_profile
agent_get_profile() {
    local base_escaped="${AGENT_SAFE_BASE:-}"
    base_escaped="${base_escaped//\\/\\\\}"
    base_escaped="${base_escaped//\"/\\\"}"

    printf '{"profile":"%s","base":"%s","description":"%s","can_write":%s,"can_system":%s,"can_network":%s}\n' \
        "$AGENT_CURRENT_PROFILE" \
        "$base_escaped" \
        "${AGENT_PROFILES[$AGENT_CURRENT_PROFILE]}" \
        "${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0}" \
        "${_AGENT_PROFILE_CAN_SYSTEM[$AGENT_CURRENT_PROFILE]:-0}" \
        "${_AGENT_PROFILE_CAN_NETWORK[$AGENT_CURRENT_PROFILE]:-0}"
}

# List available profiles
# @returns: 0
#
# Usage: agent_list_profiles
agent_list_profiles() {
    local profile
    for profile in "${!AGENT_PROFILES[@]}"; do
        printf '%s: %s\n' "$profile" "${AGENT_PROFILES[$profile]}"
    done | sort
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize agent with profile and base directory
# @post: profile set, audit log initialized
# @returns: 0
#
# Usage: agent_safety_init "project" "/path/to/project"
agent_safety_init() {
    local profile="${1:-project}"
    local base="${2:-$PWD}"

    agent_set_profile "$profile" "$base" || return 1
    agent_audit "agent_safety_initialized" "profile=$profile" "base=$base" "pid=$$"

    # Persist the profile into the active AWM session so child agents
    # inheriting the session cannot exceed the parent's profile
    if declare -F awm_checkpoint &>/dev/null && [[ -n "${_AWM_SESSION_ID:-}" ]]; then
        awm_checkpoint "agent_profile" "$AGENT_CURRENT_PROFILE" >/dev/null 2>&1 || true
    fi
}

# Adopt the agent profile from a parent AWM session. The child may only go
# LOWER (more restrictive) than the parent's profile, never higher -
# sandbox permissions attenuate across handoffs, they never amplify.
# @returns: 0 on success (JSON result), 1 if no profile checkpoint exists
#
# Usage: agent_adopt_session_profile "$PARENT_SID" [requested_profile] [base]
agent_adopt_session_profile() {
    local sid="$1"
    local requested="${2:-}"
    local base="${3:-$PWD}"

    if ! declare -F _awm_session_dir &>/dev/null; then
        agent_error "AWM not available for session profile adoption"
        return 1
    fi

    local parent_profile session_dir
    session_dir=$(_awm_session_dir "$sid" 2>/dev/null) || true
    if [[ -z "$session_dir" || ! -f "$session_dir/data/agent_profile" ]]; then
        agent_error "no agent_profile checkpoint in session '$sid'" \
            "suggestion=Run agent_safety_init in the parent session first"
        return 1
    fi
    parent_profile=$(< "$session_dir/data/agent_profile")

    # Profile hierarchy: readonly(0) < project(1) < system(2)
    local -A _profile_rank=([readonly]=0 [project]=1 [system]=2)
    local parent_rank="${_profile_rank[$parent_profile]:-1}"
    local requested_rank="${_profile_rank[${requested:-$parent_profile}]:-$parent_rank}"

    local effective
    if (( requested_rank > parent_rank )); then
        effective="$parent_profile"
        agent_audit "profile_adoption_capped" "parent=$parent_profile" "requested=$requested" "session=$sid"
    else
        effective="${requested:-$parent_profile}"
    fi

    agent_set_profile "$effective" "$base" >/dev/null
    agent_audit "profile_adopted" "session=$sid" "parent=$parent_profile" "effective=$effective"
    agent_success "profile adopted from session" "session=$sid" "parent_profile=$parent_profile" "effective_profile=$effective"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup agent resources (call on script exit)
# @post: final audit entry written
# @returns: 0
#
# Usage: agent_safety_cleanup
agent_safety_cleanup() {
    agent_audit "agent_safety_cleanup" "pid=$$"
}

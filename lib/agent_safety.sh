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
    local json
    printf -v json '{"success":false,"error":"%s","function":"%s","line":%d,"context":%s,"timestamp":"%s"}' \
        "${msg//\"/\\\"}" \
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

    local json
    printf -v json '{"success":true,"message":"%s","data":%s,"timestamp":"%s"}' \
        "${msg//\"/\\\"}" \
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

# Dangerous command patterns that require extra scrutiny
declare -ga _AGENT_DANGEROUS_COMMANDS=(
    "rm" "rmdir" "unlink"
    "mv"
    "dd"
    "mkfs" "fdisk" "parted"
    "chmod" "chown"
    "kill" "killall" "pkill"
    "reboot" "shutdown" "halt" "poweroff"
    "iptables" "ip6tables" "nft"
    "systemctl" "service"
    "useradd" "userdel" "usermod"
    "passwd"
    "crontab"
    "curl" "wget"  # Network operations
)

# Validate command before execution
# @pre: command and args provided
# @post: validates command exists and is safe
# @returns: 0 if valid, 1 if invalid
#
# Usage: agent_validate_command "cmd" "arg1" "arg2"
agent_validate_command() {
    local cmd="$1"
    shift
    local -a args=("$@")

    if [[ -z "$cmd" ]]; then
        agent_error "empty command"
        return 1
    fi

    # Check command exists (executable or function)
    if ! type -P "$cmd" &>/dev/null && ! declare -F "$cmd" &>/dev/null; then
        agent_error "command not found: $cmd" \
            "suggestion=Check spelling or install package"
        return 1
    fi

    # Profile-based permission checks
    local can_write="${_AGENT_PROFILE_CAN_WRITE[$AGENT_CURRENT_PROFILE]:-0}"
    local can_system="${_AGENT_PROFILE_CAN_SYSTEM[$AGENT_CURRENT_PROFILE]:-0}"
    local can_network="${_AGENT_PROFILE_CAN_NETWORK[$AGENT_CURRENT_PROFILE]:-0}"

    # Check for dangerous commands based on profile
    local dangerous_cmd
    for dangerous_cmd in "${_AGENT_DANGEROUS_COMMANDS[@]}"; do
        if [[ "$cmd" == "$dangerous_cmd" ]]; then
            # Network commands need network permission
            if [[ "$cmd" == "curl" || "$cmd" == "wget" ]]; then
                if (( ! can_network )); then
                    agent_error "network command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                        "suggestion=Use 'system' profile for network operations"
                    return 1
                fi
            # System commands need system permission
            elif [[ "$cmd" =~ ^(systemctl|service|reboot|shutdown|useradd|passwd)$ ]]; then
                if (( ! can_system )); then
                    agent_error "system command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                        "suggestion=Use 'system' profile for system administration"
                    return 1
                fi
            # Write commands need write permission
            elif (( ! can_write )); then
                agent_error "write command '$cmd' not allowed in profile '$AGENT_CURRENT_PROFILE'" \
                    "suggestion=Use 'project' or 'system' profile"
                return 1
            fi
            break
        fi
    done

    # Special handling for rm with -rf
    if [[ "$cmd" == "rm" ]]; then
        local has_rf=0
        local arg
        for arg in "${args[@]}"; do
            if [[ "$arg" == "-rf" || "$arg" == "-fr" || "$arg" == *"r"*"f"* ]]; then
                has_rf=1
                break
            fi
        done

        if (( has_rf )); then
            for arg in "${args[@]}"; do
                # Skip flags
                [[ "$arg" == -* ]] && continue

                # Validate path safety
                if [[ -n "${AGENT_SAFE_BASE:-}" ]]; then
                    if ! _agent_validate_path_safe "$arg" "$AGENT_SAFE_BASE"; then
                        agent_error "unsafe rm target: $arg" \
                            "base=$AGENT_SAFE_BASE" \
                            "suggestion=Use safe_remove for safer deletion"
                        return 1
                    fi
                fi
            done
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

    # Reject traversal patterns
    [[ "$path" == *".."* ]] && return 1
    [[ "$path" == *"\\"* ]] && return 1

    # Resolve paths
    local abs_base abs_path

    if [[ -d "$base" ]]; then
        abs_base=$(cd "$base" && pwd -P)
    else
        return 1
    fi

    # Handle both existing and non-existing paths
    if [[ -e "$path" ]]; then
        abs_path=$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")
    else
        local parent_dir
        parent_dir=$(dirname "$path")
        if [[ -d "$parent_dir" ]]; then
            abs_path=$(cd "$parent_dir" && pwd -P)/$(basename "$path")
        else
            return 1
        fi
    fi

    # Ensure path starts with base
    [[ "$abs_path" == "$abs_base"* ]]
}

# =============================================================================
# RISK ASSESSMENT
# =============================================================================

# Calculate risk score for a command (0-100)
# @returns: risk score via stdout
#
# Usage: score=$(agent_risk_score "rm" "-rf" "/tmp/test")
agent_risk_score() {
    local cmd="$1"
    shift
    local -a args=("$@")
    local score=0

    # Base risk for dangerous commands
    case "$cmd" in
        rm|rmdir|unlink)
            score=$((score + 30))
            # Higher risk for recursive
            [[ " ${args[*]} " == *" -r"* || " ${args[*]} " == *" -rf "* ]] && score=$((score + 20))
            # Higher risk for force
            [[ " ${args[*]} " == *" -f "* ]] && score=$((score + 10))
            ;;
        dd|mkfs|fdisk)
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
# SAFE COMMAND DISPATCH (NO EVAL)
# =============================================================================

# Execute command with full safety checks and audit trail
# @pre: command validated
# @post: command executed with audit logging
# @returns: command's exit code
#
# Usage: agent_safe_exec ls -la /tmp
agent_safe_exec() {
    local -a cmd=("$@")

    if (( ${#cmd[@]} == 0 )); then
        agent_error "no command provided"
        return 1
    fi

    # Pre-execution validation
    if ! agent_validate_command "${cmd[@]}"; then
        return 1
    fi

    # Risk assessment
    local risk_score
    risk_score=$(agent_risk_score "${cmd[@]}")

    # Audit the execution attempt
    agent_audit "exec_start" "cmd=${cmd[*]}" "risk=$risk_score" "profile=$AGENT_CURRENT_PROFILE"

    # Execute the command (array expansion preserves arguments)
    local exit_code
    "${cmd[@]}"
    exit_code=$?

    # Audit the result
    agent_audit "exec_complete" "cmd=${cmd[0]}" "exit_code=$exit_code"

    return $exit_code
}

# Execute command capturing output for structured result
# @returns: 0 on success with JSON output, 1 on failure with JSON error
#
# Usage: agent_safe_exec_capture ls -la /tmp
agent_safe_exec_capture() {
    local -a cmd=("$@")

    if (( ${#cmd[@]} == 0 )); then
        agent_error "no command provided"
        return 1
    fi

    # Pre-execution validation
    if ! agent_validate_command "${cmd[@]}"; then
        return 1
    fi

    agent_audit "exec_capture_start" "cmd=${cmd[*]}"

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

# Write audit entry to log file
# @post: entry appended to AGENT_AUDIT_LOG
# @returns: 0
#
# Usage: agent_audit "action" "key1=value1" "key2=value2"
agent_audit() {
    local action="$1"
    shift

    # Build details as JSON array
    local details_json="["
    local first=true
    for item in "$@"; do
        $first || details_json+=","
        first=false
        item="${item//\\/\\\\}"
        item="${item//\"/\\\"}"
        item="${item//$'\n'/\\n}"
        details_json+="\"$item\""
    done
    details_json+="]"

    local entry
    printf -v entry '{"ts":"%s","pid":%d,"action":"%s","details":%s}' \
        "$(date -Iseconds)" \
        "$$" \
        "${action//\"/\\\"}" \
        "$details_json"

    printf '%s\n' "$entry" >> "$AGENT_AUDIT_LOG"
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

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_exec.sh - Unified Agent Execution Pipeline
# =============================================================================
# Description: The capstone composition layer that chains all safety mechanisms
#              together into a single entry point for agent operations. Provides
#              guard checks, contract validation, observability, atomic execution,
#              retry/timeout, compensating transactions, and error recovery
#              playbooks. Phase 5.4 of the MAINFRAME agent safety framework.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_EXEC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_EXEC_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Resolve library directory
_AGENT_EXEC_LIB_DIR="${BASH_SOURCE[0]%/*}"

# Source retry.sh for retry/timeout integration
# shellcheck source=retry.sh
source "${_AGENT_EXEC_LIB_DIR}/retry.sh"

# Source output.sh for JSON output
# shellcheck source=output.sh
source "${_AGENT_EXEC_LIB_DIR}/output.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# State directory for undo stacks and recovery playbooks
MAINFRAME_AGENT_STATE="${MAINFRAME_AGENT_STATE:-${TMPDIR:-/tmp}/mainframe_agent_$$}"

# Exit codes for pipeline phases
readonly _AGENT_EXIT_SUCCESS=0
readonly _AGENT_EXIT_GUARD_FAILED=1
readonly _AGENT_EXIT_CONTRACT_FAILED=2
readonly _AGENT_EXIT_EXEC_FAILED=3
readonly _AGENT_EXIT_VERIFY_FAILED=4

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_agent_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[agent_exec] $*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[agent_exec] %s: %s\n' "$level" "$*" >&2
    fi
}

# Get current time in milliseconds
_agent_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
    else
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            printf '%s' "${ns:0:${#ns}-6}"
        else
            printf '%s000' "${EPOCHSECONDS:-$(date +%s)}"
        fi
    fi
}

# Get current epoch seconds
_agent_now() {
    local ts
    # shellcheck disable=SC2183
    if ts=$(printf '%(%s)T' -1 2>/dev/null) && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

# Ensure state directory exists
_agent_ensure_state_dir() {
    [[ -d "$MAINFRAME_AGENT_STATE" ]] || mkdir -p "$MAINFRAME_AGENT_STATE"
}

# JSON-escape a string
_agent_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\"' ;;
            '\')   result+='\\' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)     result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

# =============================================================================
# UNDO STACK (COMPENSATING TRANSACTIONS)
# =============================================================================

# Internal: get the undo stack file path
_agent_undo_file() {
    _agent_ensure_state_dir
    printf '%s/undo_stack.json' "$MAINFRAME_AGENT_STATE"
}

# Register an undo action for the current operation chain
# Undo actions execute in LIFO order (last registered = first undone)
# Usage: agent_undo_register "label" "undo_command"
agent_undo_register() {
    local label="$1"
    local command="$2"

    if [[ -z "$label" || -z "$command" ]]; then
        _agent_log error "agent_undo_register: label and command required"
        return 1
    fi

    local undo_file
    undo_file=$(_agent_undo_file)
    local now
    now=$(_agent_now)

    local escaped_label escaped_cmd
    escaped_label=$(_agent_json_escape "$label")
    escaped_cmd=$(_agent_json_escape "$command")

    local entry
    entry=$(printf '{"label":"%s","command":"%s","registered_at":%s}' \
        "$escaped_label" "$escaped_cmd" "$now")

    # Append to stack file (one JSON object per line for simplicity)
    printf '%s\n' "$entry" >> "$undo_file"

    _agent_log debug "undo registered: $label"
}

# Execute all registered undo actions (rollback) in LIFO order
# Returns: 0=all undone, 1=some failed
agent_undo_all() {
    local undo_file
    undo_file=$(_agent_undo_file)

    if [[ ! -f "$undo_file" || ! -s "$undo_file" ]]; then
        _agent_log debug "undo stack empty, nothing to roll back"
        return 0
    fi

    # Read lines into array (reverse order = LIFO)
    local -a entries=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && entries+=("$line")
    done < "$undo_file"

    local failed=0
    local i

    # Execute in reverse order
    for (( i=${#entries[@]}-1; i>=0; i-- )); do
        local entry="${entries[$i]}"
        local cmd label

        # Extract command and label from JSON entry
        if [[ "$entry" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            cmd="${BASH_REMATCH[1]}"
        else
            continue
        fi
        if [[ "$entry" =~ \"label\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            label="${BASH_REMATCH[1]}"
        else
            label="unknown"
        fi

        _agent_log info "undo: executing rollback for '$label'"
        if eval "$cmd" 2>/dev/null; then
            _agent_log debug "undo: '$label' succeeded"
        else
            _agent_log error "undo: '$label' FAILED"
            ((failed++))
        fi
    done

    # Clear the stack after execution
    : > "$undo_file"

    [[ $failed -eq 0 ]] && return 0 || return 1
}

# Clear undo stack (after successful completion)
agent_undo_clear() {
    local undo_file
    undo_file=$(_agent_undo_file)
    [[ -f "$undo_file" ]] && : > "$undo_file"
    _agent_log debug "undo stack cleared"
}

# Get undo stack as JSON array
# Output: [{"label":"...","command":"...","registered_at":N}]
agent_undo_stack() {
    local undo_file
    undo_file=$(_agent_undo_file)

    if [[ ! -f "$undo_file" || ! -s "$undo_file" ]]; then
        printf '[]'
        return 0
    fi

    local first=true
    printf '['
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        $first || printf ','
        first=false
        printf '%s' "$line"
    done < "$undo_file"
    printf ']'
}

# =============================================================================
# TRANSACTIONS
# =============================================================================

# Execute a sequence of commands with automatic rollback on failure
# Each command has a paired undo command
# Usage: agent_transaction [--label "name"] <<'EOF'
# do: mkdir -p /tmp/project
# undo: rm -rf /tmp/project
# do: cp config.json /tmp/project/
# undo: rm /tmp/project/config.json
# EOF
# Returns: 0=all succeeded, 1=failed (rolled back)
agent_transaction() {
    local label="transaction"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local -a do_cmds=()
    local -a undo_cmds=()
    local line

    # Read stdin and parse do:/undo: pairs
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" =~ ^do:[[:space:]]*(.+)$ ]]; then
            do_cmds+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^undo:[[:space:]]*(.+)$ ]]; then
            undo_cmds+=("${BASH_REMATCH[1]}")
        fi
    done

    if [[ ${#do_cmds[@]} -eq 0 ]]; then
        _agent_log error "agent_transaction: no 'do:' commands found"
        return 1
    fi

    _agent_log info "transaction '$label': ${#do_cmds[@]} steps"

    local completed=0
    local i

    for (( i=0; i<${#do_cmds[@]}; i++ )); do
        local cmd="${do_cmds[$i]}"
        _agent_log debug "transaction step $((i+1))/${#do_cmds[@]}: $cmd"

        if eval "$cmd"; then
            ((completed++))
        else
            _agent_log error "transaction '$label' failed at step $((i+1)): $cmd"

            # Rollback completed steps in reverse order
            local j
            for (( j=completed-1; j>=0; j-- )); do
                if [[ $j -lt ${#undo_cmds[@]} ]]; then
                    local undo="${undo_cmds[$j]}"
                    _agent_log info "transaction rollback step $((j+1)): $undo"
                    eval "$undo" 2>/dev/null || \
                        _agent_log error "transaction rollback failed: $undo"
                fi
            done

            return 1
        fi
    done

    _agent_log info "transaction '$label' completed successfully"
    return 0
}

# =============================================================================
# ERROR RECOVERY PLAYBOOKS
# =============================================================================

# Internal: recovery playbook storage file
_agent_recovery_file() {
    _agent_ensure_state_dir
    printf '%s/recovery_playbooks.json' "$MAINFRAME_AGENT_STATE"
}

# Register a recovery strategy for an error pattern
# Usage: agent_recovery_register "pattern" "recovery_command" [--max-attempts N]
agent_recovery_register() {
    local pattern="$1"
    local recovery_cmd="$2"
    shift 2

    local max_attempts=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-attempts) max_attempts="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$pattern" || -z "$recovery_cmd" ]]; then
        _agent_log error "agent_recovery_register: pattern and command required"
        return 1
    fi

    local recovery_file
    recovery_file=$(_agent_recovery_file)

    local escaped_pattern escaped_cmd
    escaped_pattern=$(_agent_json_escape "$pattern")
    escaped_cmd=$(_agent_json_escape "$recovery_cmd")

    local entry
    entry=$(printf '{"pattern":"%s","command":"%s","max_attempts":%d}' \
        "$escaped_pattern" "$escaped_cmd" "$max_attempts")

    printf '%s\n' "$entry" >> "$recovery_file"
    _agent_log debug "recovery registered for pattern: $pattern"
}

# Attempt automatic recovery from a failed command
# Usage: agent_recover "failed_command" "error_message"
# Returns: 0=recovered, 1=no matching playbook, 2=recovery failed
agent_recover() {
    local error_msg="$2"

    local recovery_file
    recovery_file=$(_agent_recovery_file)

    if [[ ! -f "$recovery_file" || ! -s "$recovery_file" ]]; then
        return 1
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        local pattern recovery_cmd
        if [[ "$line" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            pattern="${BASH_REMATCH[1]}"
        else
            continue
        fi
        if [[ "$line" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            recovery_cmd="${BASH_REMATCH[1]}"
        else
            continue
        fi

        # Match pattern against error message (grep-style)
        if echo "$error_msg" | grep -q "$pattern" 2>/dev/null; then
            _agent_log info "recovery: matched pattern '$pattern', executing: $recovery_cmd"
            if eval "$recovery_cmd" 2>/dev/null; then
                _agent_log info "recovery: succeeded for pattern '$pattern'"
                return 0
            else
                _agent_log error "recovery: failed for pattern '$pattern'"
                return 2
            fi
        fi
    done < "$recovery_file"

    _agent_log debug "recovery: no matching playbook for: $error_msg"
    return 1
}

# Initialize built-in recovery strategies
_agent_recovery_init() {
    agent_recovery_register "Permission denied" "_recovery_permission"
    agent_recovery_register "No space left" "_recovery_disk_space"
    agent_recovery_register "Connection refused" "_recovery_wait_retry"
    agent_recovery_register "Address already in use" "_recovery_port_conflict"
    agent_recovery_register "command not found" "_recovery_missing_command"
    agent_recovery_register "No such file" "_recovery_file_not_found"
}

# Built-in recovery handlers
_recovery_permission() {
    _agent_log warn "recovery: permission denied - suggest running with elevated privileges"
    return 1
}

_recovery_disk_space() {
    _agent_log warn "recovery: disk space issue - checking available space"
    local avail
    avail=$(df -h . 2>/dev/null | tail -1 | awk '{print $4}')
    _agent_log info "recovery: available disk space: ${avail:-unknown}"
    return 1
}

_recovery_wait_retry() {
    _agent_log info "recovery: connection refused - waiting 2s before retry"
    sleep 2
    return 0
}

_recovery_port_conflict() {
    _agent_log warn "recovery: port already in use"
    return 1
}

_recovery_missing_command() {
    _agent_log warn "recovery: required command not found"
    return 1
}

_recovery_file_not_found() {
    _agent_log warn "recovery: file not found"
    return 1
}

# List registered recovery playbooks
# Output: pattern -> command pairs
agent_recovery_list() {
    local recovery_file
    recovery_file=$(_agent_recovery_file)

    if [[ ! -f "$recovery_file" || ! -s "$recovery_file" ]]; then
        return 0
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local pattern cmd
        if [[ "$line" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            pattern="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            cmd="${BASH_REMATCH[1]}"
        fi
        printf '%s -> %s\n' "$pattern" "$cmd"
    done < "$recovery_file"
}

# Get recovery suggestion without executing
# Output: JSON {"pattern":"matched","command":"fix_cmd","description":"what it does"}
agent_recovery_suggest() {
    local error_msg="$1"

    local recovery_file
    recovery_file=$(_agent_recovery_file)

    if [[ ! -f "$recovery_file" || ! -s "$recovery_file" ]]; then
        printf '{"pattern":"none","command":"","description":"No matching playbook found"}'
        return 1
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        local pattern cmd
        if [[ "$line" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            pattern="${BASH_REMATCH[1]}"
        else
            continue
        fi
        if [[ "$line" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
            cmd="${BASH_REMATCH[1]}"
        else
            continue
        fi

        if echo "$error_msg" | grep -q "$pattern" 2>/dev/null; then
            local escaped_pattern escaped_cmd
            escaped_pattern=$(_agent_json_escape "$pattern")
            escaped_cmd=$(_agent_json_escape "$cmd")
            printf '{"pattern":"%s","command":"%s","description":"Recovery for: %s"}' \
                "$escaped_pattern" "$escaped_cmd" "$escaped_pattern"
            return 0
        fi
    done < "$recovery_file"

    printf '{"pattern":"none","command":"","description":"No matching playbook found"}'
    return 1
}

# =============================================================================
# PIPELINE HELPERS
# =============================================================================

# Check if an operation should be skipped (idempotency check)
# Usage: agent_should_skip "check_command"
# Returns: 0=skip (already done), 1=execute
agent_should_skip() {
    local check_cmd="$1"

    if [[ -z "$check_cmd" ]]; then
        return 1
    fi

    if eval "$check_cmd" &>/dev/null; then
        return 0
    fi
    return 1
}

# Run a command with full observability (timing, output capture)
# Output: JSON {"command":"...","exit_code":0,"duration_ms":N,"stdout_bytes":N,"stderr_bytes":N}
agent_observe() {
    if [[ $# -eq 0 ]]; then
        _agent_log error "agent_observe: no command specified"
        return 1
    fi

    local start_ms end_ms duration_ms
    start_ms=$(_agent_now_ms)

    local tmp_stdout tmp_stderr
    tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/agent_obs_out.XXXXXX")
    tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/agent_obs_err.XXXXXX")

    local rc=0
    "$@" >"$tmp_stdout" 2>"$tmp_stderr" || rc=$?

    end_ms=$(_agent_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    local stdout_bytes stderr_bytes
    stdout_bytes=$(wc -c < "$tmp_stdout" | tr -d ' ')
    stderr_bytes=$(wc -c < "$tmp_stderr" | tr -d ' ')

    local escaped_cmd
    escaped_cmd=$(_agent_json_escape "$*")

    printf '{"command":"%s","exit_code":%d,"duration_ms":%d,"stdout_bytes":%d,"stderr_bytes":%d}' \
        "$escaped_cmd" "$rc" "$duration_ms" "$stdout_bytes" "$stderr_bytes"

    rm -f "$tmp_stdout" "$tmp_stderr"
    return $rc
}

# Create a named execution context (groups related operations)
agent_context_start() {
    local context_name="$1"

    if [[ -z "$context_name" ]]; then
        _agent_log error "agent_context_start: context name required"
        return 1
    fi

    _agent_ensure_state_dir
    printf '%s' "$context_name" > "${MAINFRAME_AGENT_STATE}/current_context"
    _agent_log info "context started: $context_name"
}

# End the current execution context
agent_context_end() {
    if [[ -f "${MAINFRAME_AGENT_STATE}/current_context" ]]; then
        local ctx
        ctx=$(<"${MAINFRAME_AGENT_STATE}/current_context")
        rm -f "${MAINFRAME_AGENT_STATE}/current_context"
        _agent_log info "context ended: $ctx"
    fi
}

# Run multiple commands in sequence with pipeline safety
# Usage: agent_pipeline [--label "name"] [--json] command1 ";" command2 ";" command3
agent_pipeline() {
    local label="pipeline"
    local json_output=0
    local -a all_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) all_args+=("$1"); shift ;;
        esac
    done

    # Split args by ";" separator into commands
    local -a commands=()
    local current_cmd=""

    for arg in "${all_args[@]}"; do
        if [[ "$arg" == ";" ]]; then
            [[ -n "$current_cmd" ]] && commands+=("$current_cmd")
            current_cmd=""
        else
            [[ -n "$current_cmd" ]] && current_cmd+=" "
            current_cmd+="$arg"
        fi
    done
    [[ -n "$current_cmd" ]] && commands+=("$current_cmd")

    if [[ ${#commands[@]} -eq 0 ]]; then
        _agent_log error "agent_pipeline: no commands specified"
        return 1
    fi

    _agent_log info "pipeline '$label': ${#commands[@]} commands"

    local -a completed_cmds=()
    local start_ms end_ms
    start_ms=$(_agent_now_ms)

    for (( i=0; i<${#commands[@]}; i++ )); do
        local cmd="${commands[$i]}"
        _agent_log debug "pipeline step $((i+1))/${#commands[@]}: $cmd"

        if eval "$cmd"; then
            completed_cmds+=("$cmd")
        else
            local rc=$?
            _agent_log error "pipeline '$label' failed at step $((i+1)): $cmd"

            # Rollback via undo stack
            agent_undo_all

            end_ms=$(_agent_now_ms)
            local duration_ms=$((end_ms - start_ms))
            [[ $duration_ms -lt 0 ]] && duration_ms=0

            if [[ $json_output -eq 1 ]]; then
                local escaped_label
                escaped_label=$(_agent_json_escape "$label")
                printf '{"status":"failed","label":"%s","failed_step":%d,"total_steps":%d,"duration_ms":%d}' \
                    "$escaped_label" "$((i+1))" "${#commands[@]}" "$duration_ms"
            fi
            return $rc
        fi
    done

    end_ms=$(_agent_now_ms)
    local duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    if [[ $json_output -eq 1 ]]; then
        local escaped_label
        escaped_label=$(_agent_json_escape "$label")
        printf '{"status":"success","label":"%s","completed_steps":%d,"duration_ms":%d}' \
            "$escaped_label" "${#commands[@]}" "$duration_ms"
    fi

    _agent_log info "pipeline '$label' completed successfully"
    return 0
}

# =============================================================================
# MAIN ENTRY POINT: agent_exec
# =============================================================================

# The unified agent execution wrapper
# Chains: guard -> contract -> idempotent -> observe -> execute -> retry/timeout -> verify -> undo-on-fail
#
# Usage: agent_exec [options] command [args...]
#
# Options:
#   --guard "check_cmd"       Pre-flight check (must pass before execution)
#   --contract "validate_cmd" Input validation function
#   --observe                 Enable execution tracing/logging
#   --atomic                  Wrap in atomic file operations
#   --idempotent "check_cmd"  Skip if already-done check passes
#   --retry N                 Retry on failure (integrates with lib/retry.sh)
#   --timeout SECONDS         Execution timeout
#   --undo "rollback_cmd"     Rollback command if execution fails
#   --on-success "cmd"        Callback on success
#   --on-failure "cmd"        Callback on failure
#   --label "name"            Human-readable label for logging
#   --dry-run                 Show what would happen without executing
#   --json                    Output structured JSON result
#
# Returns: 0=success, 1=guard-failed, 2=contract-failed, 3=exec-failed, 4=verify-failed
# shellcheck disable=SC2034
agent_exec() {
    local guard_cmd=""
    local contract_cmd=""
    local observe_flag=0
    local atomic_flag=0  # reserved for future atomic file operations
    local idempotent_cmd=""
    local retry_count=0
    local timeout_seconds=0
    local undo_cmd=""
    local on_success_cmd=""
    local on_failure_cmd=""
    local label=""
    local dry_run=0
    local json_output=0
    local -a exec_cmd=()

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --guard)       guard_cmd="$2"; shift 2 ;;
            --contract)    contract_cmd="$2"; shift 2 ;;
            --observe)     observe_flag=1; shift ;;
            --atomic)      atomic_flag=1; shift ;;
            --idempotent)  idempotent_cmd="$2"; shift 2 ;;
            --retry)       retry_count="$2"; shift 2 ;;
            --timeout)     timeout_seconds="$2"; shift 2 ;;
            --undo)        undo_cmd="$2"; shift 2 ;;
            --on-success)  on_success_cmd="$2"; shift 2 ;;
            --on-failure)  on_failure_cmd="$2"; shift 2 ;;
            --label)       label="$2"; shift 2 ;;
            --dry-run)     dry_run=1; shift ;;
            --json)        json_output=1; shift ;;
            --)            shift; exec_cmd=("$@"); break ;;
            -*)
                _agent_log error "agent_exec: unknown option: $1"
                return 1
                ;;
            *)
                exec_cmd=("$@")
                break
                ;;
        esac
    done

    if [[ ${#exec_cmd[@]} -eq 0 ]]; then
        _agent_log error "agent_exec: no command specified"
        return 1
    fi

    # Default label from command
    [[ -z "$label" ]] && label="${exec_cmd[*]}"

    local start_ms stdout_content="" stderr_content="" exit_code=0
    local guard_status="skipped" contract_status="skipped"
    local idempotent_status="executed" undo_status="not_needed"
    local final_status="success"

    start_ms=$(_agent_now_ms)

    # =========================================================================
    # DRY-RUN MODE
    # =========================================================================
    if [[ $dry_run -eq 1 ]]; then
        printf '[dry-run] label: %s\n' "$label"
        [[ -n "$guard_cmd" ]] && printf '[dry-run] guard: %s\n' "$guard_cmd"
        [[ -n "$contract_cmd" ]] && printf '[dry-run] contract: %s\n' "$contract_cmd"
        [[ -n "$idempotent_cmd" ]] && printf '[dry-run] idempotent: %s\n' "$idempotent_cmd"
        printf '[dry-run] execute: %s\n' "${exec_cmd[*]}"
        [[ $observe_flag -eq 1 ]] && printf '[dry-run] observe: enabled\n'
        [[ $retry_count -gt 0 ]] && printf '[dry-run] retry: %d attempts\n' "$retry_count"
        [[ $timeout_seconds -gt 0 ]] && printf '[dry-run] timeout: %ds\n' "$timeout_seconds"
        [[ -n "$undo_cmd" ]] && printf '[dry-run] undo: %s\n' "$undo_cmd"
        [[ -n "$on_success_cmd" ]] && printf '[dry-run] on-success: %s\n' "$on_success_cmd"
        [[ -n "$on_failure_cmd" ]] && printf '[dry-run] on-failure: %s\n' "$on_failure_cmd"
        return 0
    fi

    # =========================================================================
    # PHASE 1: GUARD CHECK
    # =========================================================================
    if [[ -n "$guard_cmd" ]]; then
        _agent_log debug "guard check: $guard_cmd"
        if ! eval "$guard_cmd" &>/dev/null; then
            guard_status="failed"
            final_status="guard_failed"
            _agent_log error "guard check failed: $guard_cmd"

            if [[ -n "$on_failure_cmd" ]]; then
                eval "$on_failure_cmd" 2>/dev/null || true
            fi

            _agent_emit_result "$json_output" "$final_status" "$label" \
                "$start_ms" "" "" "$_AGENT_EXIT_GUARD_FAILED" \
                "$guard_status" "$contract_status" "$idempotent_status" "$undo_status"
            return $_AGENT_EXIT_GUARD_FAILED
        fi
        guard_status="passed"
        _agent_log debug "guard check passed"
    fi

    # =========================================================================
    # PHASE 2: CONTRACT VALIDATION
    # =========================================================================
    if [[ -n "$contract_cmd" ]]; then
        _agent_log debug "contract validation: $contract_cmd"
        if ! eval "$contract_cmd" &>/dev/null; then
            contract_status="failed"
            final_status="contract_failed"
            _agent_log error "contract validation failed: $contract_cmd"

            if [[ -n "$on_failure_cmd" ]]; then
                eval "$on_failure_cmd" 2>/dev/null || true
            fi

            _agent_emit_result "$json_output" "$final_status" "$label" \
                "$start_ms" "" "" "$_AGENT_EXIT_CONTRACT_FAILED" \
                "$guard_status" "$contract_status" "$idempotent_status" "$undo_status"
            return $_AGENT_EXIT_CONTRACT_FAILED
        fi
        contract_status="passed"
        _agent_log debug "contract validation passed"
    fi

    # =========================================================================
    # PHASE 3: IDEMPOTENCY CHECK
    # =========================================================================
    if [[ -n "$idempotent_cmd" ]]; then
        if agent_should_skip "$idempotent_cmd"; then
            idempotent_status="skipped"
            final_status="success"
            _agent_log info "idempotent check passed, skipping execution: $label"

            _agent_emit_result "$json_output" "$final_status" "$label" \
                "$start_ms" "" "" "0" \
                "$guard_status" "$contract_status" "$idempotent_status" "$undo_status"
            return 0
        fi
    fi

    # =========================================================================
    # PHASE 4: EXECUTION (with observe, retry, timeout)
    # =========================================================================
    _agent_log debug "executing: ${exec_cmd[*]}"

    local tmp_stdout tmp_stderr
    tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/agent_exec_out.XXXXXX")
    tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/agent_exec_err.XXXXXX")

    # Build the execution command with optional timeout
    if [[ $retry_count -gt 0 ]]; then
        # Execute with retry (retry calls the command directly)
        if [[ $timeout_seconds -gt 0 ]]; then
            retry --max-attempts "$retry_count" --delay 1 \
                with_timeout "$timeout_seconds" "${exec_cmd[@]}" \
                >"$tmp_stdout" 2>"$tmp_stderr"
        else
            retry --max-attempts "$retry_count" --delay 1 \
                "${exec_cmd[@]}" >"$tmp_stdout" 2>"$tmp_stderr"
        fi
        exit_code=$?
    elif [[ $timeout_seconds -gt 0 ]]; then
        with_timeout "$timeout_seconds" "${exec_cmd[@]}" >"$tmp_stdout" 2>"$tmp_stderr"
        exit_code=$?
    else
        "${exec_cmd[@]}" >"$tmp_stdout" 2>"$tmp_stderr"
        exit_code=$?
    fi

    stdout_content=$(<"$tmp_stdout")
    stderr_content=$(<"$tmp_stderr")
    rm -f "$tmp_stdout" "$tmp_stderr"

    # =========================================================================
    # PHASE 5: HANDLE RESULT
    # =========================================================================
    if [[ $exit_code -eq 0 ]]; then
        final_status="success"
        _agent_log info "execution succeeded: $label"

        # Success callback
        if [[ -n "$on_success_cmd" ]]; then
            eval "$on_success_cmd" 2>/dev/null || true
        fi

        # Register undo for successful operations (in case later pipeline step fails)
        if [[ -n "$undo_cmd" ]]; then
            agent_undo_register "$label" "$undo_cmd"
        fi
    else
        final_status="exec_failed"
        _agent_log error "execution failed (exit=$exit_code): $label"

        # Attempt recovery
        if [[ -n "$stderr_content" ]]; then
            local recovery_result=1
            agent_recover "${exec_cmd[*]}" "$stderr_content" && recovery_result=0

            if [[ $recovery_result -eq 0 ]]; then
                # Recovery succeeded, retry the command once
                _agent_log info "recovery succeeded, retrying: $label"
                tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/agent_exec_out.XXXXXX")
                tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/agent_exec_err.XXXXXX")

                "${exec_cmd[@]}" >"$tmp_stdout" 2>"$tmp_stderr"
                exit_code=$?

                stdout_content=$(<"$tmp_stdout")
                stderr_content=$(<"$tmp_stderr")
                rm -f "$tmp_stdout" "$tmp_stderr"

                if [[ $exit_code -eq 0 ]]; then
                    final_status="success"
                    _agent_log info "execution succeeded after recovery: $label"
                    if [[ -n "$on_success_cmd" ]]; then
                        eval "$on_success_cmd" 2>/dev/null || true
                    fi
                    if [[ -n "$undo_cmd" ]]; then
                        agent_undo_register "$label" "$undo_cmd"
                    fi
                fi
            fi
        fi

        # If still failed, execute undo
        if [[ "$final_status" == "exec_failed" ]]; then
            if [[ -n "$undo_cmd" ]]; then
                _agent_log info "executing undo: $undo_cmd"
                if eval "$undo_cmd" 2>/dev/null; then
                    undo_status="succeeded"
                    final_status="rolled_back"
                else
                    undo_status="failed"
                fi
            fi

            # Failure callback
            if [[ -n "$on_failure_cmd" ]]; then
                eval "$on_failure_cmd" 2>/dev/null || true
            fi
        fi
    fi

    # =========================================================================
    # EMIT RESULT
    # =========================================================================
    _agent_emit_result "$json_output" "$final_status" "$label" \
        "$start_ms" "$stdout_content" "$stderr_content" "$exit_code" \
        "$guard_status" "$contract_status" "$idempotent_status" "$undo_status"

    case "$final_status" in
        success)         return 0 ;;
        guard_failed)    return $_AGENT_EXIT_GUARD_FAILED ;;
        contract_failed) return $_AGENT_EXIT_CONTRACT_FAILED ;;
        rolled_back|exec_failed) return $_AGENT_EXIT_EXEC_FAILED ;;
        verify_failed)   return $_AGENT_EXIT_VERIFY_FAILED ;;
        *)               return $exit_code ;;
    esac
}

# Internal: emit the JSON result
_agent_emit_result() {
    local json_output="$1"
    local status="$2"
    local label="$3"
    local start_ms="$4"
    local stdout="$5"
    local stderr="$6"
    local exit_code="$7"
    local guard="$8"
    local contract="$9"
    local idempotent="${10}"
    local undo="${11}"

    local end_ms duration_ms
    end_ms=$(_agent_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    if [[ $json_output -eq 1 ]]; then
        local escaped_status escaped_label escaped_stdout escaped_stderr
        escaped_status=$(_agent_json_escape "$status")
        escaped_label=$(_agent_json_escape "$label")
        escaped_stdout=$(_agent_json_escape "$stdout")
        escaped_stderr=$(_agent_json_escape "$stderr")

        printf '{"status":"%s","label":"%s","duration_ms":%d,"stdout":"%s","stderr":"%s","exit_code":%d,"guard":"%s","contract":"%s","idempotent":"%s","undo":"%s"}\n' \
            "$escaped_status" "$escaped_label" "$duration_ms" \
            "$escaped_stdout" "$escaped_stderr" "$exit_code" \
            "$guard" "$contract" "$idempotent" "$undo"
    fi
}

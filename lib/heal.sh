#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/heal.sh - Self-Healing and Error Recovery System
# =============================================================================
# Description: Intelligent error diagnosis, classification, and automated
#              recovery for shell commands. Learns from AMMA history and
#              provides confidence-scored suggestions for fixing common errors.
#
# Version: 1.0.0
# Requires: Bash 4.0+, ammma.sh (optional, for history learning)
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "The best error is the one that fixes itself."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_HEAL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_HEAL_LOADED=1

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly HEAL_VERSION="1.0.0"
readonly HEAL_SCHEMA_VERSION="1.0"

# Error categories
readonly HEAL_CAT_PERMISSION="permission"
readonly HEAL_CAT_NOTFOUND="notfound"
readonly HEAL_CAT_NETWORK="network"
readonly HEAL_CAT_RESOURCE="resource"
readonly HEAL_CAT_SYNTAX="syntax"
readonly HEAL_CAT_LOGIC="logic"
readonly HEAL_CAT_UNKNOWN="unknown"

# Confidence thresholds
readonly HEAL_CONFIDENCE_HIGH=0.85
readonly HEAL_CONFIDENCE_MEDIUM=0.60
readonly HEAL_CONFIDENCE_LOW=0.30

# Configuration
HEAL_HISTORY_LIMIT="${HEAL_HISTORY_LIMIT:-100}"
HEAL_AUTO_DRYRUN="${HEAL_AUTO_DRYRUN:-1}"
HEAL_MAX_SUGGESTIONS="${HEAL_MAX_SUGGESTIONS:-5}"
HEAL_STATE_DIR="${HEAL_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_heal}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -gA _HEAL_STRATEGIES=()
declare -gA _HEAL_STRATEGY_META=()

declare -g _HEAL_ORIGINAL_COMMAND=""
declare -g _HEAL_ORIGINAL_ERROR=""
declare -g _HEAL_ORIGINAL_EXITCODE=0

declare -gi _HEAL_DIAGNOSIS_COUNT=0
declare -gi _HEAL_SUCCESSFUL_FIXES=0

# =============================================================================
# USOP OUTPUT HELPERS
# =============================================================================

_heal_usop_success() {
    local data="${1:-null}"
    local hint="${2:-}"
    local elapsed="${3:-}"
    
    [[ -z "$elapsed" ]] && elapsed="0"
    
    if [[ -z "$hint" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"elapsed_ms":%s,"timestamp":%s}}' \
            "$data" "$elapsed" "$(_heal_epoch_ms)"
    else
        printf '{"ok":true,"data":%s,"meta":{"elapsed_ms":%s,"timestamp":%s},"hint":"%s"}' \
            "$data" "$elapsed" "$(_heal_epoch_ms)" "$(_heal_json_escape "$hint")"
    fi
}

_heal_usop_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    
    if [[ -z "$suggestion" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"},"meta":{"timestamp":%s}}' \
            "$code" "$(_heal_json_escape "$msg")" "$(_heal_epoch_ms)"
    else
        printf '{"ok":false,"error":{"code":"%s","msg":"%s","suggestion":"%s"},"meta":{"timestamp":%s}}' \
            "$code" "$(_heal_json_escape "$msg")" "$(_heal_json_escape "$suggestion")" "$(_heal_epoch_ms)"
    fi
}

_heal_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

_heal_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

_heal_epoch_ms() {
    local epoch
    epoch=$(_heal_epoch)
    printf '%s000' "$epoch"
}

_heal_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "heal" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[heal] %s: %s\n' "$level" "$*" >&2
    fi
}


# =============================================================================
# COMMAND WRAPPING
# =============================================================================

heal_wrap() {
    local start_time
    start_time=$(_heal_epoch)
    
    local command=""
    local retries=0
    local backoff="exponential"
    local delay=1
    local max_delay=30
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --retries)
                retries="$2"
                shift 2
                ;;
            --backoff)
                backoff="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            --max-delay)
                max_delay="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_wrap: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    command="$command $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$command" ]]; then
        _heal_usop_error "MISSING_COMMAND" "No command specified for heal_wrap"
        return 1
    fi
    
    _HEAL_ORIGINAL_COMMAND="$command"
    
    local attempt=1
    local exit_code=0
    local output=""
    
    while [[ $attempt -le $((retries + 1)) ]]; do
        output=$(eval "$command" 2>&1) || exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
                local elapsed=$(( $(_heal_epoch) - start_time ))
                local data
                data=$(printf '{"output":"%s","attempts":%d}' "$(_heal_json_escape "$output")" "$attempt")
                _heal_usop_success "$data" "heal_diagnose" "$((elapsed * 1000))"
            else
                printf '%s' "$output"
            fi
            return 0
        fi
        
        _HEAL_ORIGINAL_ERROR="$output"
        _HEAL_ORIGINAL_EXITCODE=$exit_code
        
        _heal_log debug "heal_wrap: attempt $attempt/$((retries + 1)) failed (exit=$exit_code)"
        
        if [[ $attempt -gt $retries ]]; then
            break
        fi
        
        local current_delay=$delay
        case "$backoff" in
            linear)
                current_delay=$((delay * attempt))
                ;;
            exponential)
                local power=1
                local i
                for ((i = 1; i < attempt; i++)); do
                    power=$((power * 2))
                done
                current_delay=$((delay * power))
                ;;
        esac
        
        if [[ $current_delay -gt $max_delay ]]; then
            current_delay=$max_delay
        fi
        
        _heal_log debug "heal_wrap: waiting ${current_delay}s before retry"
        sleep "$current_delay"
        attempt=$((attempt + 1))
    done
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    _heal_log info "heal_wrap: all attempts failed, attempting diagnosis"
    
    local category
    category=$(heal_classify_error "$_HEAL_ORIGINAL_ERROR")
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local data
        data=$(printf '{"command":"%s","exit_code":%d,"category":"%s","error":"%s","attempts":%d}' \
            "$(_heal_json_escape "$command")" "$exit_code" "$category" "$(_heal_json_escape "$_HEAL_ORIGINAL_ERROR")" "$attempt")
        _heal_usop_success "$data" "heal_diagnose" "$((elapsed * 1000))"
    else
        printf '[FAIL] Command failed after %d attempt(s)\n' "$attempt" >&2
        printf 'Error: %s\n' "$_HEAL_ORIGINAL_ERROR" >&2
        printf 'Category: %s\n' "$category" >&2
    fi
    
    return $exit_code
}

heal_execute() {
    local start_time
    start_time=$(_heal_epoch)
    
    local command=""
    local on_error=""
    local capture_output=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --on_error)
                on_error="$2"
                shift 2
                ;;
            --capture-output)
                capture_output=1
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_execute: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    command="$command $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$command" ]]; then
        _heal_usop_error "MISSING_COMMAND" "No command specified for heal_execute"
        return 1
    fi
    
    _HEAL_ORIGINAL_COMMAND="$command"
    
    local output=""
    local exit_code=0
    
    if [[ -n "$capture_output" ]]; then
        output=$(eval "$command" 2>&1) || exit_code=$?
    else
        # Capture stderr for diagnostics while letting stdout flow through.
        # This avoids needing to re-execute the command on failure (which would
        # cause side-effect commands to run twice).
        local _heal_stderr_tmp
        _heal_stderr_tmp=$(mktemp "${TMPDIR:-/tmp}/heal_stderr.XXXXXX")
        eval "$command" 2>"$_heal_stderr_tmp" || exit_code=$?
        output=$(<"$_heal_stderr_tmp")
        rm -f "$_heal_stderr_tmp"
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        local elapsed=$(( $(_heal_epoch) - start_time ))
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            local data='{"executed":true,"recovered":false}'
            [[ -n "$capture_output" ]] && data=$(printf '{"executed":true,"recovered":false,"output":"%s"}' "$(_heal_json_escape "$output")")
            _heal_usop_success "$data" "" "$((elapsed * 1000))"
        fi
        return 0
    fi
    
    # NOTE: Previously this re-executed the failed command to capture output when
    # --capture-output was not used. This caused side-effect commands to run twice.
    # Now we capture stderr from the first execution instead. If output is still
    # empty (no --capture-output and no stderr), we log a warning rather than
    # re-executing a potentially destructive command.
    if [[ -z "$output" ]]; then
        _heal_log warn "heal_execute: command failed but no output captured (use --capture-output to enable diagnostics)"
        output="Command failed with exit code $exit_code (no output captured)"
    fi
    _HEAL_ORIGINAL_ERROR="$output"
    _HEAL_ORIGINAL_EXITCODE=$exit_code

    _heal_log warn "heal_execute: command failed (exit=$exit_code), executing recovery: $on_error"
    
    local recovery_result=0
    if [[ -n "$on_error" ]]; then
        eval "$on_error" || recovery_result=$?
    fi
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local data
        data=$(printf '{"executed":false,"recovered":%s,"exit_code":%d,"recovery_exit":%d}' \
            "$([[ $recovery_result -eq 0 ]] && echo "true" || echo "false")" "$exit_code" "$recovery_result")
        _heal_usop_success "$data" "" "$((elapsed * 1000))"
    else
        [[ $recovery_result -eq 0 ]] && printf '[RECOVERED] Command failed but recovery succeeded\n' >&2
    fi
    
    return $recovery_result
}


# =============================================================================
# ERROR DIAGNOSIS
# =============================================================================

heal_diagnose() {
    local start_time
    start_time=$(_heal_epoch)
    
    local error_output=""
    local context=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --context)
                context="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_diagnose: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$error_output" ]]; then
                    error_output="$1"
                else
                    error_output="$error_output $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$error_output" ]]; then
        _heal_usop_error "MISSING_ERROR" "No error output provided for diagnosis"
        return 1
    fi
    
    _HEAL_DIAGNOSIS_COUNT=$((_HEAL_DIAGNOSIS_COUNT + 1))
    
    local category
    category=$(heal_classify_error "$error_output")
    
    local root_cause
    root_cause=$(heal_root_cause "$error_output")
    
    local context_json="{}"
    if [[ -n "$context" ]]; then
        context_json=$(_heal_gather_context "$context")
    fi
    
    local suggestions
    suggestions=$(heal_suggest "$error_output" --format json)
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local data
        data=$(printf '{"category":"%s","root_cause":"%s","context":%s,"suggestions":%s}' \
            "$category" "$(_heal_json_escape "$root_cause")" "$context_json" "$suggestions")
        _heal_usop_success "$data" "heal_suggest" "$((elapsed * 1000))"
    else
        printf '=== HEAL DIAGNOSIS ===\n'
        printf 'Category: %s\n' "$category"
        printf 'Root Cause: %s\n' "$root_cause"
        printf '\nSuggestions:\n'
        printf '%s\n' "$suggestions"
    fi
}

heal_classify_error() {
    local error="${1:-}"
    
    if [[ -z "$error" ]]; then
        printf '%s' "$HEAL_CAT_UNKNOWN"
        return 0
    fi
    
    local lower_error
    lower_error=$(printf '%s' "$error" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$lower_error" =~ (permission denied|eacces|eperm|operation not permitted) ]]; then
        printf '%s' "$HEAL_CAT_PERMISSION"
        return 0
    fi
    
    if [[ "$lower_error" =~ (no such file|command not found|enoent|not found) ]]; then
        printf '%s' "$HEAL_CAT_NOTFOUND"
        return 0
    fi
    
    if [[ "$lower_error" =~ (connection refused|epipe|econnrefused|etimedout|network|timeout|could not resolve) ]]; then
        printf '%s' "$HEAL_CAT_NETWORK"
        return 0
    fi
    
    if [[ "$lower_error" =~ (cannot allocate memory|enomem|no space left|enospc|too many open files|emfile) ]]; then
        printf '%s' "$HEAL_CAT_RESOURCE"
        return 0
    fi
    
    if [[ "$lower_error" =~ (syntax error|unexpected|unclosed|missing quote|parse error) ]]; then
        printf '%s' "$HEAL_CAT_SYNTAX"
        return 0
    fi
    
    if [[ "$lower_error" =~ (wrong directory|not a git repository|prerequisite|dependency|required) ]]; then
        printf '%s' "$HEAL_CAT_LOGIC"
        return 0
    fi
    
    printf '%s' "$HEAL_CAT_UNKNOWN"
}

heal_root_cause() {
    local error="${1:-}"
    
    if [[ -z "$error" ]]; then
        printf 'Unknown error - no error message provided'
        return 0
    fi
    
    local category
    category=$(heal_classify_error "$error")
    
    case "$category" in
        "$HEAL_CAT_PERMISSION")
            local path
            path=$(printf '%s' "$error" | grep -oE '/[^[:space:]]+' | head -1)
            if [[ -n "$path" ]]; then
                if [[ -e "$path" ]]; then
                    local owner perms
                    owner=$(stat -c '%U' "$path" 2>/dev/null || echo "unknown")
                    perms=$(stat -c '%a' "$path" 2>/dev/null || echo "unknown")
                    printf 'Permission denied on %s (owned by %s, permissions %s)' "$path" "$owner" "$perms"
                else
                    printf 'Permission denied - parent directory may lack write permission'
                fi
            else
                printf 'Insufficient privileges for operation'
            fi
            ;;
        "$HEAL_CAT_NOTFOUND")
            if [[ "$error" =~ command[[:space:]]not[[:space:]]found ]]; then
                local cmd
                cmd=$(printf '%s' "$error" | grep -oE "'[^']+'" | head -1 | tr -d "'")
                [[ -z "$cmd" ]] && cmd=$(printf '%s' "$error" | awk '{print $NF}')
                printf 'Command "%s" not found in PATH' "$cmd"
            else
                local path
                path=$(printf '%s' "$error" | grep -oE '/[^[:space:]]+' | head -1)
                printf 'File or directory not found: %s' "${path:-unknown}"
            fi
            ;;
        "$HEAL_CAT_NETWORK")
            if [[ "$error" =~ connection[[:space:]]refused ]]; then
                printf 'Target service not accepting connections - service may be down or wrong port'
            elif [[ "$error" =~ timeout ]]; then
                printf 'Network operation timed out - host may be unreachable or network congested'
            elif [[ "$error" =~ resolve ]]; then
                printf 'DNS resolution failed - check network connectivity and DNS settings'
            else
                printf 'Network communication failure'
            fi
            ;;
        "$HEAL_CAT_RESOURCE")
            if [[ "$error" =~ memory ]]; then
                printf 'System memory exhausted - process requires more RAM than available'
            elif [[ "$error" =~ space ]]; then
                printf 'Disk space exhausted - partition is full'
            elif [[ "$error" =~ files ]]; then
                printf 'File descriptor limit reached - too many open files'
            else
                printf 'System resource exhausted'
            fi
            ;;
        "$HEAL_CAT_SYNTAX")
            printf 'Command syntax error - check shell syntax and special characters'
            ;;
        "$HEAL_CAT_LOGIC")
            printf 'Logic error - check prerequisites and execution context'
            ;;
        *)
            printf 'Unknown error cause - manual investigation required'
            ;;
    esac
}


# =============================================================================
# RECOVERY SUGGESTIONS
# =============================================================================

heal_suggest() {
    local start_time
    start_time=$(_heal_epoch)
    
    local error=""
    local format="text"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_suggest: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$error" ]]; then
                    error="$1"
                else
                    error="$error $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$error" ]]; then
        printf '[]'
        return 0
    fi
    
    local category
    category=$(heal_classify_error "$error")
    
    local suggestions=""
    
    case "$category" in
        "$HEAL_CAT_PERMISSION")
            suggestions=$(_heal_suggest_permission "$error")
            ;;
        "$HEAL_CAT_NOTFOUND")
            suggestions=$(_heal_suggest_notfound "$error")
            ;;
        "$HEAL_CAT_NETWORK")
            suggestions=$(_heal_suggest_network "$error")
            ;;
        "$HEAL_CAT_RESOURCE")
            suggestions=$(_heal_suggest_resource "$error")
            ;;
        "$HEAL_CAT_SYNTAX")
            suggestions=$(_heal_suggest_syntax "$error")
            ;;
        "$HEAL_CAT_LOGIC")
            suggestions=$(_heal_suggest_logic "$error")
            ;;
    esac
    
    local custom_suggestions
    custom_suggestions=$(_heal_match_strategies "$error")
    if [[ -n "$custom_suggestions" ]]; then
        [[ -n "$suggestions" ]] && suggestions+=","
        suggestions+="$custom_suggestions"
    fi
    
    local historical
    historical=$(_heal_learn_from_history "$error")
    if [[ -n "$historical" ]]; then
        [[ -n "$suggestions" ]] && suggestions+=","
        suggestions+="$historical"
    fi
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    
    if [[ "$format" == "json" ]]; then
        printf '[%s]' "$suggestions"
    else
        # Parse JSON for text output - process complete JSON objects
        local i=1
        # Use a different approach - extract complete objects
        local objs
        objs=$(printf '%s' "$suggestions" | grep -oE '\{[^}]+\}')
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            local sugg_text
            sugg_text=$(printf '%s' "$entry" | grep -oE '\"suggestion\":\"[^\"]+\"' | head -1 | sed 's/\"suggestion\":\"//;s/\"$//')
            local conf
            conf=$(printf '%s' "$entry" | grep -oE '\"confidence\":[0-9.]+' | head -1 | sed 's/\"confidence\"://')
            local desc
            desc=$(printf '%s' "$entry" | grep -oE '\"description\":\"[^\"]+\"' | head -1 | sed 's/\"description\":\"//;s/\"$//')
            [[ -z "$sugg_text" ]] && continue
            printf '%d. [%s confidence] %s\n   Command: %s\n' "$i" "${conf:-unknown}" "${desc:-Suggestion}" "$sugg_text"
            i=$((i + 1))
        done <<< "$objs"
    fi
}

_heal_suggest_permission() {
    local error="$1"
    local sugg=""
    
    local path
    path=$(printf '%s' "$error" | grep -oE '/[^[:space:]]+' | head -1)
    
    if sudo -n true 2>/dev/null; then
        if [[ -n "$_HEAL_ORIGINAL_COMMAND" ]]; then
            sugg='{"suggestion":"sudo '"$_HEAL_ORIGINAL_COMMAND"'","confidence":0.95,"description":"Execute with elevated privileges"}'
        fi
    fi
    
    if [[ -n "$path" && -e "$path" ]]; then
        local owner
        owner=$(stat -c '%U' "$path" 2>/dev/null)
        if [[ "$owner" != "$USER" ]]; then
            [[ -n "$sugg" ]] && sugg+=","
            sugg+='{"suggestion":"sudo chown '"$USER"' '"$path"'","confidence":0.70,"description":"Change file ownership to current user"}'
            sugg+=',{"suggestion":"sudo chmod u+w '"$path"'","confidence":0.60,"description":"Add write permission for user"}'
        fi
    fi
    
    printf '%s' "$sugg"
}

_heal_suggest_notfound() {
    local error="$1"
    local sugg=""
    
    if [[ "$error" =~ command[[:space:]]not[[:space:]]found ]]; then
        local cmd
        cmd=$(printf '%s' "$error" | grep -oE "'[^']+'" | head -1 | tr -d "'")
        [[ -z "$cmd" ]] && cmd=$(printf '%s' "$error" | awk '{print $NF}')
        
        sugg='{"suggestion":"Install '"$cmd"' using system package manager","confidence":0.80,"description":"Command not found - install required"}'
        sugg+=',{"suggestion":"export PATH=\"/usr/local/bin:$PATH\"","confidence":0.50,"description":"Check if command is in non-standard location"}'
        
        local similar
        similar=$(compgen -c 2>/dev/null | grep -i "^${cmd:0:3}" | head -3 | tr '\n' ', ')
        if [[ -n "$similar" ]]; then
            sugg+=',{"suggestion":"Did you mean: '"$similar"'","confidence":0.40,"description":"Similar commands found"}'
        fi
    else
        local path
        path=$(printf '%s' "$error" | grep -oE '/[^[:space:]]+' | head -1)
        sugg='{"suggestion":"mkdir -p \""${path%/*}"\"","confidence":0.85,"description":"Create missing parent directories"}'
        sugg+=',{"suggestion":"Check if path exists: test -d \""$path"\"","confidence":0.70,"description":"Verify path exists"}'
    fi
    
    printf '%s' "$sugg"
}

_heal_suggest_network() {
    local error="$1"
    local sugg=""
    
    sugg='{"suggestion":"Retry with exponential backoff","confidence":0.90,"description":"Transient network issue - retry may succeed"}'
    sugg+=',{"suggestion":"Check network connectivity: ping -c 3 8.8.8.8","confidence":0.75,"description":"Verify internet connection"}'
    
    if [[ "$error" =~ connection[[:space:]]refused ]]; then
        sugg+=',{"suggestion":"Verify service is running on target host","confidence":0.80,"description":"Target service may be down"}'
    fi
    
    if [[ "$error" =~ resolve ]]; then
        sugg+=',{"suggestion":"Check DNS settings in /etc/resolv.conf","confidence":0.70,"description":"DNS resolution failed"}'
    fi
    
    printf '%s' "$sugg"
}

_heal_suggest_resource() {
    local error="$1"
    local sugg=""
    
    if [[ "$error" =~ memory ]]; then
        sugg='{"suggestion":"Close other applications to free memory","confidence":0.85,"description":"System memory low"}'
        sugg+=',{"suggestion":"Increase swap space or add more RAM","confidence":0.60,"description":"Hardware limitation"}'
    elif [[ "$error" =~ space ]]; then
        sugg='{"suggestion":"Clean up disk space: df -h","confidence":0.90,"description":"Disk full - cleanup required"}'
        sugg+=',{"suggestion":"Remove temporary files: rm -rf /tmp/*","confidence":0.70,"description":"Free up temporary space"}'
    elif [[ "$error" =~ files ]]; then
        sugg='{"suggestion":"Increase ulimit: ulimit -n 4096","confidence":0.85,"description":"File descriptor limit reached"}'
        sugg+=',{"suggestion":"Close unused file descriptors in application","confidence":0.75,"description":"Application leak suspected"}'
    fi
    
    printf '%s' "$sugg"
}

_heal_suggest_syntax() {
    local error="$1"
    local sugg=""
    
    sugg='{"suggestion":"Check for missing quotes around variables","confidence":0.80,"description":"Common syntax issue"}'
    sugg+=',{"suggestion":"Verify all brackets and parentheses are closed","confidence":0.75,"description":"Unclosed delimiter"}'
    sugg+=',{"suggestion":"Check for special characters that need escaping","confidence":0.60,"description":"Special character handling"}'
    
    printf '%s' "$sugg"
}

_heal_suggest_logic() {
    local error="$1"
    local sugg=""
    
    sugg='{"suggestion":"Verify current working directory: pwd","confidence":0.85,"description":"Wrong directory context"}'
    sugg+=',{"suggestion":"Check prerequisites are installed","confidence":0.70,"description":"Missing dependency"}'
    sugg+=',{"suggestion":"Verify environment variables are set","confidence":0.65,"description":"Environment issue"}'
    
    printf '%s' "$sugg"
}


# =============================================================================
# SAFE EXECUTION ENGINE
# =============================================================================
# Whitelist-based command execution for auto-generated fix suggestions.
# Only commands in the whitelist are executed directly. All others are logged
# for manual review. This prevents command injection through crafted error
# messages or manipulated suggestion data.
# =============================================================================

# Whitelist of commands that are safe for auto-fix to execute.
# Each entry is a simple command name (no paths). The function validates
# that the actual command resolves to an executable before running.
readonly _HEAL_SAFE_COMMANDS=(
    # Filesystem operations (non-destructive)
    mkdir
    touch
    chmod
    chown
    ln
    cp
    mv
    # Package management (install only, not remove)
    pip
    pip3
    npm
    bun
    apt
    apt-get
    brew
    dnf
    yum
    pacman
    # System configuration
    export
    ulimit
    usermod
    # Network diagnostics
    ping
    curl
    wget
    # Version control
    git
    # Service management
    systemctl
    service
    # Container management
    docker
)

# Subcommand blocklist for commands that have destructive subcommands.
# Format: "command:blocked_subcommand"
readonly _HEAL_BLOCKED_SUBCOMMANDS=(
    "pip:uninstall"
    "pip3:uninstall"
    "npm:uninstall"
    "bun:remove"
    "apt:remove"
    "apt:purge"
    "apt-get:remove"
    "apt-get:purge"
    "dnf:remove"
    "yum:remove"
    "pacman:-R"
    "pacman:-Rs"
    "docker:rm"
    "docker:rmi"
    "git:push"
    "git:reset"
    "systemctl:stop"
    "systemctl:disable"
)

_heal_safe_execute() {
    local suggestion="$1"
    local confirmed="${2:-}"  # --confirmed flag from heal_confirm_and_fix

    if [[ -z "$suggestion" ]]; then
        _heal_log error "_heal_safe_execute: empty suggestion"
        return 1
    fi

    # Strip leading/trailing whitespace
    suggestion="${suggestion#"${suggestion%%[![:space:]]*}"}"
    suggestion="${suggestion%"${suggestion##*[![:space:]]}"}"

    # Check for shell metacharacters that indicate injection attempts.
    # These should never appear in legitimate fix suggestions which are
    # simple single commands like "mkdir -p /path" or "chmod 755 /file".
    # NOTE: The regex must be stored in a variable (not quoted on the RHS of =~)
    # for bash to treat it as a regex rather than a literal string.
    local _dangerous_re='[;|&`$(){}]|>>|<<'
    if [[ "$suggestion" =~ $_dangerous_re ]]; then
        _heal_log warn "_heal_safe_execute: BLOCKED - suggestion contains shell metacharacters: $suggestion"
        _heal_usop_error "INJECTION_BLOCKED" \
            "Fix suggestion contains potentially dangerous shell metacharacters" \
            "Manual review required: $suggestion"
        return 1
    fi

    # Parse the command: handle "sudo <command> ..." pattern
    local -a tokens
    read -ra tokens <<< "$suggestion"

    if [[ ${#tokens[@]} -eq 0 ]]; then
        _heal_log error "_heal_safe_execute: no tokens in suggestion"
        return 1
    fi

    local base_cmd="${tokens[0]}"
    local check_cmd="$base_cmd"
    local subcmd_index=1

    # Handle sudo prefix: the actual command to whitelist-check is the one after sudo
    if [[ "$base_cmd" == "sudo" ]]; then
        if [[ ${#tokens[@]} -lt 2 ]]; then
            _heal_log error "_heal_safe_execute: sudo with no command"
            return 1
        fi
        # Skip sudo flags like -n, -u, etc.
        subcmd_index=1
        while [[ $subcmd_index -lt ${#tokens[@]} ]] && [[ "${tokens[$subcmd_index]}" == -* ]]; do
            subcmd_index=$((subcmd_index + 1))
        done
        if [[ $subcmd_index -ge ${#tokens[@]} ]]; then
            _heal_log error "_heal_safe_execute: sudo with only flags, no command"
            return 1
        fi
        check_cmd="${tokens[$subcmd_index]}"
        subcmd_index=$((subcmd_index + 1))
    fi

    # Verify command is in the whitelist
    local allowed=false
    local cmd_name
    for cmd_name in "${_HEAL_SAFE_COMMANDS[@]}"; do
        if [[ "$check_cmd" == "$cmd_name" ]]; then
            allowed=true
            break
        fi
    done

    if [[ "$allowed" != "true" ]]; then
        _heal_log warn "_heal_safe_execute: BLOCKED - command '$check_cmd' not in whitelist"
        _heal_log info "_heal_safe_execute: suggestion logged for manual review: $suggestion"
        _heal_usop_error "NOT_WHITELISTED" \
            "Command '$check_cmd' is not in the auto-fix whitelist" \
            "Manual execution required: $suggestion"
        return 1
    fi

    # Check subcommand blocklist (e.g., "pip uninstall" is blocked)
    if [[ $subcmd_index -lt ${#tokens[@]} ]]; then
        local subcmd="${tokens[$subcmd_index]}"
        local blocked_entry
        for blocked_entry in "${_HEAL_BLOCKED_SUBCOMMANDS[@]}"; do
            local blocked_cmd="${blocked_entry%%:*}"
            local blocked_sub="${blocked_entry#*:}"
            if [[ "$check_cmd" == "$blocked_cmd" && "$subcmd" == "$blocked_sub" ]]; then
                _heal_log warn "_heal_safe_execute: BLOCKED - destructive subcommand '$check_cmd $subcmd'"
                _heal_usop_error "DESTRUCTIVE_BLOCKED" \
                    "Destructive subcommand '$check_cmd $subcmd' is blocked" \
                    "Manual execution required: $suggestion"
                return 1
            fi
        done
    fi

    # Additional safety: block any argument that looks like a path traversal attack
    local token
    for token in "${tokens[@]}"; do
        if [[ "$token" == *".."* && "$token" == *"/"* ]]; then
            # Allow legitimate relative paths but block obvious traversal
            local resolved
            resolved=$(realpath -m "$token" 2>/dev/null || true)
            if [[ -n "$resolved" ]] && [[ "$resolved" == /proc/* || "$resolved" == /sys/* || "$resolved" == /dev/* ]]; then
                _heal_log warn "_heal_safe_execute: BLOCKED - suspicious path traversal to system path: $token"
                _heal_usop_error "PATH_BLOCKED" \
                    "Path traversal to system directory blocked" \
                    "Manual review required: $suggestion"
                return 1
            fi
        fi
    done

    # Verify the command resolves to a real executable
    if [[ "$check_cmd" != "export" && "$check_cmd" != "ulimit" ]]; then
        if ! command -v "$check_cmd" &>/dev/null; then
            _heal_log warn "_heal_safe_execute: command '$check_cmd' not found on system"
            _heal_usop_error "CMD_NOT_FOUND" \
                "Command '$check_cmd' not found" \
                "Install '$check_cmd' first, then retry"
            return 1
        fi
    fi

    # Execute the validated command using the parsed token array (no eval)
    _heal_log info "_heal_safe_execute: executing whitelisted command: ${tokens[*]}"
    "${tokens[@]}"
}

# =============================================================================
# AUTO-FIX FUNCTIONS
# =============================================================================

heal_auto_fix() {
    local start_time
    start_time=$(_heal_epoch)
    
    local error=""
    local dry_run=${HEAL_AUTO_DRYRUN:-1}
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                shift
                ;;
            --no-dry-run)
                dry_run=0
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_auto_fix: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$error" ]]; then
                    error="$1"
                else
                    error="$error $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$error" ]]; then
        _heal_usop_error "MISSING_ERROR" "No error provided for auto-fix"
        return 1
    fi
    
    local suggestions_json
    suggestions_json=$(heal_suggest "$error" --format json)
    
    local best_suggestion=""
    local best_confidence=0
    
    local entries
    entries=$(printf '%s' "$suggestions_json" | grep -oE '\"suggestion\":\"[^\"]*\"[^}]*\"confidence\":[0-9.]*' 2>/dev/null)
    
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local sugg conf
        sugg=$(printf '%s' "$entry" | grep -oE '\"suggestion\":\"[^\"]*\"' | sed 's/\"suggestion\":\"//;s/\"$//')
        conf=$(printf '%s' "$entry" | grep -oE '\"confidence\":[0-9.]*' | sed 's/\"confidence\"://')
        
        if [[ -n "$conf" ]]; then
            local cmp
            cmp=$(echo "$conf > $best_confidence" | bc 2>/dev/null || echo "0")
            if [[ "$cmp" == "1" ]]; then
                best_confidence=$conf
                best_suggestion=$sugg
            fi
        fi
    done <<< "$entries"
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    
    if [[ -z "$best_suggestion" ]]; then
        _heal_usop_error "NO_SUGGESTION" "No fix suggestion available for this error"
        return 1
    fi
    
    if [[ $dry_run -eq 1 ]]; then
        local data
        data=$(printf '{"dry_run":true,"suggestion":"%s","confidence":%s}' \
            "$(_heal_json_escape "$best_suggestion")" "$best_confidence")
        _heal_usop_success "$data" "" "$((elapsed * 1000))"
        return 0
    fi
    
    _heal_log info "heal_auto_fix: applying fix (confidence: $best_confidence): $best_suggestion"

    local fix_result=0
    _heal_safe_execute "$best_suggestion" || fix_result=$?
    
    if [[ $fix_result -eq 0 ]]; then
        _HEAL_SUCCESSFUL_FIXES=$((_HEAL_SUCCESSFUL_FIXES + 1))
        _heal_log info "heal_auto_fix: fix applied successfully"
        
        if declare -F ammma_episode_log &>/dev/null; then
            ammma_episode_log --content "Auto-healed: $error -> $best_suggestion" --importance high &>/dev/null || true
        fi
        
        local data
        data=$(printf '{"applied":true,"suggestion":"%s","confidence":%s}' \
            "$(_heal_json_escape "$best_suggestion")" "$best_confidence")
        _heal_usop_success "$data" "" "$((elapsed * 1000))"
        return 0
    else
        _heal_log error "heal_auto_fix: fix failed"
        _heal_usop_error "FIX_FAILED" "Fix application failed" "Try manual execution of: $best_suggestion"
        return 1
    fi
}

heal_confirm_and_fix() {
    local start_time
    start_time=$(_heal_epoch)
    
    local error=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                break
                ;;
            -*)
                _heal_log error "heal_confirm_and_fix: unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$error" ]]; then
                    error="$1"
                else
                    error="$error $1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$error" ]]; then
        _heal_usop_error "MISSING_ERROR" "No error provided for confirmation fix"
        return 1
    fi
    
    local suggestions
    suggestions=$(heal_suggest "$error" --format json)
    
    printf '\n=== HEALING SUGGESTIONS ===\n' >&2
    printf 'Error: %s\n' "$error" >&2
    printf '\nSuggested fixes:\n' >&2
    
    local i=1
    local entries
    entries=$(printf '%s' "$suggestions" | grep -o '"suggestion":"[^"]*"[^}]*"confidence":[0-9.]*[^}]*"description":"[^"]*"' 2>/dev/null)
    
    local -a sugg_list=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local sugg conf desc
        sugg=$(printf '%s' "$entry" | grep -oE '\"suggestion\":\"[^\"]*\"' | sed 's/\"suggestion\":\"//;s/\"$//')
        conf=$(printf '%s' "$entry" | grep -oE '\"confidence\":[0-9.]*' | sed 's/\"confidence\"://')
        desc=$(printf '%s' "$entry" | grep -oE '\"description\":\"[^\"]*\"' | sed 's/\"description\":\"//;s/\"$//')
        
        printf '  %d. [%s%% confidence] %s\n' "$i" "${conf:-0}" "$desc" >&2
        printf '     Command: %s\n' "$sugg" >&2
        sugg_list+=("$sugg")
        i=$((i + 1))
    done <<< "$entries"
    
    if [[ ${#sugg_list[@]} -eq 0 ]]; then
        printf '  No suggestions available.\n' >&2
        return 1
    fi
    
    printf '\n' >&2
    local response
    read -r -p "Select fix to apply (1-$((i-1)) or 'n' to cancel): " response
    
    if [[ "$response" == "n" || "$response" == "N" ]]; then
        printf 'Cancelled.\n' >&2
        return 1
    fi
    
    if ! [[ "$response" =~ ^[0-9]+$ ]] || [[ $response -lt 1 || $response -ge $i ]]; then
        printf 'Invalid selection.\n' >&2
        return 1
    fi
    
    local selected_sugg="${sugg_list[$((response-1))]}"
    
    printf 'Executing: %s\n' "$selected_sugg" >&2
    local fix_result=0
    _heal_safe_execute "$selected_sugg" --confirmed || fix_result=$?
    
    local elapsed=$(( $(_heal_epoch) - start_time ))
    
    if [[ $fix_result -eq 0 ]]; then
        _HEAL_SUCCESSFUL_FIXES=$((_HEAL_SUCCESSFUL_FIXES + 1))
        printf '[OK] Fix applied successfully\n' >&2
        
        if declare -F ammma_episode_log &>/dev/null; then
            ammma_episode_log --content "Healed with confirmation: $error -> $selected_sugg" --importance high &>/dev/null || true
        fi
        
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            local data
            data=$(printf '{"applied":true,"suggestion":"%s"}' "$(_heal_json_escape "$selected_sugg")")
            _heal_usop_success "$data" "" "$((elapsed * 1000))"
        fi
        return 0
    else
        printf '[FAIL] Fix failed with exit code %d\n' "$fix_result" >&2
        return 1
    fi
}


# =============================================================================
# STRATEGY MANAGEMENT
# =============================================================================

heal_register_strategy() {
    local pattern="${1:-}"
    local fix_command="${2:-}"
    
    if [[ -z "$pattern" || -z "$fix_command" ]]; then
        _heal_usop_error "MISSING_ARGUMENTS" "Both pattern and fix_command are required"
        return 1
    fi
    
    local strategy_id="strategy_$(date +%s)_$RANDOM"
    
    _HEAL_STRATEGIES["$pattern"]="$fix_command"
    _HEAL_STRATEGY_META["$pattern"]="$strategy_id"
    
    _heal_log debug "heal_register_strategy: registered '$pattern' -> '$fix_command'"
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local data
        data=$(printf '{"registered":true,"id":"%s","pattern":"%s"}' "$strategy_id" "$(_heal_json_escape "$pattern")")
        _heal_usop_success "$data"
    fi
    
    return 0
}

heal_list_strategies() {
    local format="${1:-text}"
    
    if [[ "${#_HEAL_STRATEGIES[@]}" -eq 0 ]]; then
        if [[ "$format" == "json" ]]; then
            printf '{"strategies":[]}'
        else
            printf 'No custom strategies registered.\n'
        fi
        return 0
    fi
    
    if [[ "$format" == "json" ]]; then
        printf '{"strategies":['
        local first=true
        for pattern in "${!_HEAL_STRATEGIES[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '{"pattern":"%s","fix_command":"%s"}' \
                "$(_heal_json_escape "$pattern")" "$(_heal_json_escape "${_HEAL_STRATEGIES[$pattern]}")"
        done
        printf ']}'
    else
        printf '=== REGISTERED HEALING STRATEGIES ===\n'
        local i=1
        for pattern in "${!_HEAL_STRATEGIES[@]}"; do
            printf '%d. Pattern: %s\n' "$i" "$pattern"
            printf '   Fix: %s\n' "${_HEAL_STRATEGIES[$pattern]}"
            i=$((i + 1))
        done
    fi
    
    return 0
}

_heal_match_strategies() {
    local error="$1"
    local matches=""
    
    for pattern in "${!_HEAL_STRATEGIES[@]}"; do
        if printf '%s' "$error" | grep -qE "$pattern" 2>/dev/null; then
            local fix_cmd="${_HEAL_STRATEGIES[$pattern]}"
            [[ -n "$matches" ]] && matches+=","
            matches+='{"suggestion":"'"$fix_cmd"'","confidence":0.75,"description":"Custom strategy: '"$pattern"'"}'
        fi
    done
    
    printf '%s' "$matches"
}

# =============================================================================
# LEARNING FROM HISTORY
# =============================================================================

_heal_learn_from_history() {
    local error="$1"
    
    if ! declare -F ammma_episode_log &>/dev/null; then
        return 0
    fi
    
    local category
    category=$(heal_classify_error "$error")
    
    local amma_root="${AMMA_ROOT:-${HOME}/.mainframe/amma}"
    local l4_path="$amma_root/l4_long/episodes"
    
    if [[ ! -d "$l4_path" ]]; then
        return 0
    fi
    
    local learnings=""
    local found_files
    found_files=$(find "$l4_path" -name "*.json" -exec grep -l "healed\|heal\|fixed" {} \; 2>/dev/null | head -5)
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local content
        content=$(cat "$file" 2>/dev/null)
        [[ -z "$content" ]] && continue
        
        if printf '%s' "$content" | grep -q "$category" 2>/dev/null; then
            local desc
            desc=$(printf '%s' "$content" | grep -o '\"description\":\"[^\"]*\"' | head -1 | cut -d'"' -f4)
            if [[ -n "$desc" ]]; then
                [[ -n "$learnings" ]] && learnings+=","
                learnings+='{"suggestion":"Previously worked: '"$desc"'","confidence":0.65,"description":"From AMMA history"}'
            fi
        fi
    done <<< "$found_files"
    
    printf '%s' "$learnings"
}

# =============================================================================
# CONTEXT GATHERING
# =============================================================================

_heal_gather_context() {
    local context_spec="$1"
    local json="{"
    local first=true
    
    IFS=',' read -ra ctx_parts <<< "$context_spec"
    
    for part in "${ctx_parts[@]}"; do
        case "$part" in
            cwd)
                [[ "$first" == "true" ]] || json+=","
                first=false
                json+='"cwd":"'"$PWD"'"'
                ;;
            env)
                [[ "$first" == "true" ]] || json+=","
                first=false
                json+='"user":"'"$USER"'","path":"'"${PATH//\"/\\\"}"'"'
                ;;
            command)
                [[ "$first" == "true" ]] || json+=","
                first=false
                json+='"original_command":"'"${_HEAL_ORIGINAL_COMMAND//\"/\\\"}"'"'
                ;;
        esac
    done
    
    json+="}"
    printf '%s' "$json"
}

# =============================================================================
# ADVANCED HEALING FUNCTIONS
# =============================================================================

verify_and_heal() {
    local command="$1"
    
    if [[ -z "$command" ]]; then
        _heal_usop_error "MISSING_COMMAND" "No command provided for verify_and_heal"
        return 1
    fi
    
    local output=""
    local exit_code=0
    
    output=$(eval "$command" 2>&1) || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            local data
            data=$(printf '{"success":true,"output":"%s"}' "$(_heal_json_escape "$output")")
            _heal_usop_success "$data"
        else
            printf '%s' "$output"
        fi
        return 0
    fi
    
    _HEAL_ORIGINAL_COMMAND="$command"
    _HEAL_ORIGINAL_ERROR="$output"
    _HEAL_ORIGINAL_EXITCODE=$exit_code
    
    _heal_log info "verify_and_heal: command failed, attempting healing"
    
    local suggestions
    suggestions=$(heal_suggest "$output" --format json)
    
    if [[ "$suggestions" == "[]" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            local data
            data=$(printf '{"success":false,"healed":false,"error":"%s"}' "$(_heal_json_escape "$output")")
            _heal_usop_success "$data"
        else
            printf '[FAIL] %s\n' "$output" >&2
        fi
        return $exit_code
    fi
    
    local fix_result
    fix_result=$(heal_auto_fix "$output" --dry-run 2>/dev/null)
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local data
        data=$(printf '{"success":false,"healed":false,"error":"%s","suggestions":%s,"dry_run_fix":%s}' \
            "$(_heal_json_escape "$output")" "$suggestions" "$fix_result")
        _heal_usop_success "$data"
    else
        printf '[FAIL - HEALABLE] %s\n' "$output" >&2
        printf 'Run "heal_confirm_and_fix" to see suggestions.\n' >&2
    fi
    
    return $exit_code
}

heal_stats() {
    local format="${1:-text}"
    
    if [[ "$format" == "json" ]]; then
        printf '{"diagnoses":%d,"successful_fixes":%d,"strategies_registered":%d}' \
            "$_HEAL_DIAGNOSIS_COUNT" "$_HEAL_SUCCESSFUL_FIXES" "${#_HEAL_STRATEGIES[@]}"
    else
        printf '=== HEAL STATISTICS ===\n'
        printf 'Diagnoses performed: %d\n' "$_HEAL_DIAGNOSIS_COUNT"
        printf 'Successful fixes: %d\n' "$_HEAL_SUCCESSFUL_FIXES"
        printf 'Custom strategies: %d\n' "${#_HEAL_STRATEGIES[@]}"
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

_heal_init() {
    mkdir -p "$HEAL_STATE_DIR" 2>/dev/null || true
    
    # NOTE: Strategy fix commands are resolved at registration time (no shell
    # expansion at execution time) to avoid command injection via _heal_safe_execute.
    heal_register_strategy "npm.*EACCES" "sudo chown -R $USER $HOME/.npm" &>/dev/null || true
    heal_register_strategy "pip.*Permission" "pip install --user" &>/dev/null || true
    heal_register_strategy "docker.*permission" "sudo usermod -aG docker $USER" &>/dev/null || true
    
    _heal_log debug "heal: initialized v$HEAL_VERSION"
}

_heal_init

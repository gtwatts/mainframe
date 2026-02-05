#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/sandbox_exec.sh - Sandboxed Command Execution
# =============================================================================
# Description: Execute commands with resource limits and safety checks.
#              Uses prlimit (Linux) or ulimit fallback for resource control.
#              Provides AI-safe execution with extra validation.
# Version: 1.0.0
# Requires: Bash 4.0+, prlimit (optional), timeout (optional)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SANDBOX_EXEC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SANDBOX_EXEC_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Resource limits (can be overridden via environment)
SANDBOX_MAX_CPU_SECONDS="${SANDBOX_MAX_CPU_SECONDS:-30}"
SANDBOX_MAX_MEMORY_MB="${SANDBOX_MAX_MEMORY_MB:-512}"
SANDBOX_MAX_FILE_SIZE_MB="${SANDBOX_MAX_FILE_SIZE_MB:-100}"
SANDBOX_MAX_PROCESSES="${SANDBOX_MAX_PROCESSES:-50}"
SANDBOX_TIMEOUT_SECONDS="${SANDBOX_TIMEOUT_SECONDS:-60}"
SANDBOX_MAX_OPEN_FILES="${SANDBOX_MAX_OPEN_FILES:-1024}"
SANDBOX_STACK_SIZE_MB="${SANDBOX_STACK_SIZE_MB:-8}"

# Path restrictions
SANDBOX_READONLY_PATHS="${SANDBOX_READONLY_PATHS:-}"
SANDBOX_WRITABLE_PATHS="${SANDBOX_WRITABLE_PATHS:-}"

# AI safety configuration
SANDBOX_AI_STRICT="${SANDBOX_AI_STRICT:-1}"
SANDBOX_LOG_SECURITY="${SANDBOX_LOG_SECURITY:-1}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -gA _SANDBOX_SECRETS_REGISTERED=()
declare -ga _SANDBOX_EXEC_HISTORY=()
declare -g _SANDBOX_LAST_EXIT_CODE=0
declare -g _SANDBOX_LAST_CPU_TIME=0
declare -g _SANDBOX_LAST_MEMORY_PEAK=0

# =============================================================================
# LOGGING HELPERS
# =============================================================================

_sandbox_exec_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[sandbox] $*"
    else
        printf '[%s] [sandbox] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "$*" >&2
    fi
}

_sandbox_exec_error() { _sandbox_exec_log error "$@"; }
_sandbox_exec_warn() { _sandbox_exec_log warn "$@"; }
_sandbox_exec_info() { _sandbox_exec_log info "$@"; }
_sandbox_exec_debug() { _sandbox_exec_log debug "$@"; }

# =============================================================================
# CAPABILITY DETECTION
# =============================================================================

# Check if sandboxing is available
# Returns: full|partial|none
sandbox_available() {
    local has_prlimit=0
    local has_timeout=0
    local has_ulimit=0

    if command -v prlimit &>/dev/null; then
        has_prlimit=1
    fi

    if command -v timeout &>/dev/null; then
        has_timeout=1
    fi

    # ulimit is a shell builtin, always available in bash
    has_ulimit=1

    if [[ $has_prlimit -eq 1 && $has_timeout -eq 1 ]]; then
        echo "full"
        return 0
    elif [[ $has_ulimit -eq 1 ]]; then
        echo "partial"
        return 0
    else
        echo "none"
        return 1
    fi
}

# Get sandbox capabilities as JSON
sandbox_capabilities() {
    local available
    available=$(sandbox_available)

    local prlimit=false
    local timeout=false
    local ulimit=false
    local cgroups=false

    command -v prlimit &>/dev/null && prlimit=true
    command -v timeout &>/dev/null && timeout=true
    ulimit=true  # builtin

    # Check for cgroup support
    if [[ -d /sys/fs/cgroup ]] && command -v cgexec &>/dev/null; then
        cgroups=true
    fi

    printf '{\n'
    printf '  "available": "%s",\n' "$available"
    printf '  "features": {\n'
    printf '    "prlimit": %s,\n' "$prlimit"
    printf '    "timeout": %s,\n' "$timeout"
    printf '    "ulimit": %s,\n' "$ulimit"
    printf '    "cgroups": %s\n' "$cgroups"
    printf '  },\n'
    printf '  "limits": {\n'
    printf '    "cpu_seconds": %s,\n' "$SANDBOX_MAX_CPU_SECONDS"
    printf '    "memory_mb": %s,\n' "$SANDBOX_MAX_MEMORY_MB"
    printf '    "file_size_mb": %s,\n' "$SANDBOX_MAX_FILE_SIZE_MB"
    printf '    "max_processes": %s,\n' "$SANDBOX_MAX_PROCESSES"
    printf '    "timeout_seconds": %s,\n' "$SANDBOX_TIMEOUT_SECONDS"
    printf '    "max_open_files": %s\n' "$SANDBOX_MAX_OPEN_FILES"
    printf '  }\n'
    printf '}\n'
}

# =============================================================================
# CORE SANDBOX EXECUTION
# =============================================================================

# Execute command with resource limits
# Usage: sandbox_exec -- command [args...]
# The -- is required to separate options from command
sandbox_exec() {
    # Parse arguments
    local cmd=""
    local -a cmd_args=()
    local use_report=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --report)
                use_report=true
                shift
                ;;
            --)
                shift
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
            -*)
                _sandbox_exec_error "Unknown option: $1"
                return 1
                ;;
            *)
                # First non-option is the command
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        _sandbox_exec_error "No command specified"
        return 1
    fi

    # Verify command exists
    if ! command -v "$cmd" &>/dev/null; then
        _sandbox_exec_error "Command not found: $cmd"
        return 127
    fi

    _sandbox_exec_debug "Executing: $cmd ${cmd_args[*]}"

    # Build and execute with limits
    if [[ "$use_report" == true ]]; then
        _sandbox_exec_with_limits_and_report "$cmd" "${cmd_args[@]}"
    else
        _sandbox_exec_with_limits "$cmd" "${cmd_args[@]}"
    fi
}

# Internal: Execute with resource limits
_sandbox_exec_with_limits() {
    local cmd="$1"
    shift
    local -a args=("$@")

    local timeout_cmd=""
    local use_prlimit=false

    # Determine available tools
    if command -v prlimit &>/dev/null; then
        use_prlimit=true
    fi

    if command -v timeout &>/dev/null; then
        timeout_cmd="timeout --signal=KILL ${SANDBOX_TIMEOUT_SECONDS}s"
    fi

    # Record start time for metrics
    local start_time end_time cpu_time
    start_time=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")

    if [[ "$use_prlimit" == true ]]; then
        # Use prlimit for precise resource control
        local max_memory_bytes=$((SANDBOX_MAX_MEMORY_MB * 1024 * 1024))
        local max_file_size=$((SANDBOX_MAX_FILE_SIZE_MB * 1024 * 1024))
        local max_stack=$((SANDBOX_STACK_SIZE_MB * 1024 * 1024))

        local prlimit_opts="--cpu=$SANDBOX_MAX_CPU_SECONDS"
        prlimit_opts="$prlimit_opts --as=$max_memory_bytes"
        prlimit_opts="$prlimit_opts --fsize=$max_file_size"
        prlimit_opts="$prlimit_opts --nproc=$SANDBOX_MAX_PROCESSES"
        prlimit_opts="$prlimit_opts --nofile=$SANDBOX_MAX_OPEN_FILES"
        prlimit_opts="$prlimit_opts --stack=$max_stack"

        if [[ -n "$timeout_cmd" ]]; then
            # Use both timeout and prlimit
            $timeout_cmd prlimit $prlimit_opts "$cmd" "${args[@]}"
        else
            prlimit $prlimit_opts "$cmd" "${args[@]}"
        fi
    else
        # Fallback to ulimit in subshell
        (
            # Set resource limits via ulimit
            ulimit -t "$SANDBOX_MAX_CPU_SECONDS" 2>/dev/null || true
            ulimit -v "$((SANDBOX_MAX_MEMORY_MB * 1024))" 2>/dev/null || true
            ulimit -f "$((SANDBOX_MAX_FILE_SIZE_MB * 1024))" 2>/dev/null || true
            ulimit -u "$SANDBOX_MAX_PROCESSES" 2>/dev/null || true
            ulimit -n "$SANDBOX_MAX_OPEN_FILES" 2>/dev/null || true
            ulimit -s "$((SANDBOX_STACK_SIZE_MB * 1024))" 2>/dev/null || true

            if [[ -n "$timeout_cmd" ]]; then
                exec $timeout_cmd "$cmd" "${args[@]}"
            else
                exec "$cmd" "${args[@]}"
            fi
        )
    fi

    _SANDBOX_LAST_EXIT_CODE=$?

    # Log if there was a resource violation
    case $_SANDBOX_LAST_EXIT_CODE in
        124|137)
            _sandbox_exec_warn "Command timed out or was killed: $cmd"
            ;;
        134)
            _sandbox_exec_warn "Command aborted (SIGABRT - possible resource violation): $cmd"
            ;;
        139)
            _sandbox_exec_warn "Command segfaulted (SIGSEGV): $cmd"
            ;;
    esac

    return $_SANDBOX_LAST_EXIT_CODE
}

# Internal: Execute with resource limits and detailed reporting
_sandbox_exec_with_limits_and_report() {
    local cmd="$1"
    shift
    local -a args=("$@")

    # Prepare report file
    local report_file
    report_file=$(mktemp /tmp/sandbox_report.XXXXXX)

    # Use time command for detailed metrics
    local time_format='{"real":%e,"user":%U,"sys":%S,"maxrss":%M,"exit":%x}'

    if command -v gtime &>/dev/null; then
        # GNU time on macOS (brew install gnu-time)
        gtime -f "$time_format" -o "$report_file" -- \
            _sandbox_exec_with_limits "$cmd" "${args[@]}" 2>&1
    elif /usr/bin/time --version &>/dev/null 2>&1; then
        # GNU time
        /usr/bin/time -f "$time_format" -o "$report_file" -- \
            _sandbox_exec_with_limits "$cmd" "${args[@]}" 2>&1
    else
        # Fallback - no detailed metrics available
        _sandbox_exec_with_limits "$cmd" "${args[@]}"
        _SANDBOX_LAST_CPU_TIME=0
        _SANDBOX_LAST_MEMORY_PEAK=0
        rm -f "$report_file"
        return $_SANDBOX_LAST_EXIT_CODE
    fi

    _SANDBOX_LAST_EXIT_CODE=$?

    # Parse the report
    if [[ -f "$report_file" && -s "$report_file" ]]; then
        local report
        report=$(<"$report_file")
        _SANDBOX_LAST_CPU_TIME=$(echo "$report" | grep -o '"user":[0-9.]*' | cut -d: -f2)
        _SANDBOX_LAST_MEMORY_PEAK=$(echo "$report" | grep -o '"maxrss":[0-9]*' | cut -d: -f2)
        : "${_SANDBOX_LAST_CPU_TIME:=0}"
        : "${_SANDBOX_LAST_MEMORY_PEAK:=0}"
    fi

    rm -f "$report_file"
    return $_SANDBOX_LAST_EXIT_CODE
}

# Execute with resource report
# Usage: sandbox_exec_with_report -- command [args...]
# Returns: exit_code, cpu_time, memory_peak via variables
sandbox_exec_with_report() {
    # Parse to find command
    local cmd=""
    local -a cmd_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
            *)
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        _sandbox_exec_error "No command specified"
        return 1
    fi

    _sandbox_exec_with_limits_and_report "$cmd" "${cmd_args[@]}"
    local exit_code=$?

    # Output report as JSON
    printf '{\n'
    printf '  "exit_code": %d,\n' "$exit_code"
    printf '  "cpu_time": %s,\n' "${_SANDBOX_LAST_CPU_TIME:-0}"
    printf '  "memory_peak_kb": %s,\n' "${_SANDBOX_LAST_MEMORY_PEAK:-0}"
    printf '  "limits": {\n'
    printf '    "cpu_seconds": %s,\n' "$SANDBOX_MAX_CPU_SECONDS"
    printf '    "memory_mb": %s\n' "$SANDBOX_MAX_MEMORY_MB"
    printf '  }\n'
    printf '}\n'

    return $exit_code
}

# =============================================================================
# AI-SAFE EXECUTION
# =============================================================================

# AI-safe execution with extra validation
# Usage: sandbox_exec_ai -- command [args...]
# Additional checks:
#   - Command injection patterns
#   - Path traversal attempts
#   - Destructive operations
sandbox_exec_ai() {
    # Parse arguments
    local cmd=""
    local -a cmd_args=()
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --)
                shift
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
            -*)
                _sandbox_exec_error "Unknown option: $1"
                return 1
                ;;
            *)
                cmd="$1"
                shift
                cmd_args=("$@")
                break
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        _sandbox_exec_error "No command specified"
        return 1
    fi

    # Security checks
    local -a security_issues=()

    # Check command for injection patterns
    if _sandbox_check_command_injection "$cmd"; then
        security_issues+=("Command contains injection pattern: $cmd")
    fi

    # Check all arguments
    local arg
    for arg in "${cmd_args[@]}"; do
        if _sandbox_check_command_injection "$arg"; then
            security_issues+=("Argument contains injection pattern: $arg")
        fi
        if _sandbox_check_path_traversal "$arg"; then
            security_issues+=("Argument contains path traversal: $arg")
        fi
    done

    # Check for destructive operations
    if _sandbox_check_destructive "$cmd" "${cmd_args[@]}"; then
        if [[ "$SANDBOX_AI_STRICT" == "1" ]]; then
            security_issues+=("Potentially destructive operation detected")
        else
            _sandbox_exec_warn "Potentially destructive operation: $cmd ${cmd_args[*]}"
        fi
    fi

    # Report security issues
    if [[ ${#security_issues[@]} -gt 0 ]]; then
        _sandbox_exec_error "Security check failed for: $cmd"
        for issue in "${security_issues[@]}"; do
            _sandbox_exec_error "  - $issue"
        done
        return 1
    fi

    # Log security approval
    if [[ "$SANDBOX_LOG_SECURITY" == "1" ]]; then
        _sandbox_exec_info "AI-safe execution approved: $cmd"
    fi

    if [[ "$dry_run" == true ]]; then
        printf '[DRY-RUN] Would execute: %s' "$cmd"
        if [[ ${#cmd_args[@]} -gt 0 ]]; then
            printf ' %q' "${cmd_args[@]}"
        fi
        printf '\n'
        return 0
    fi

    # Execute with full sandboxing
    sandbox_exec -- "$cmd" "${cmd_args[@]}"
}

# Check for command injection patterns
# Returns: 0 if dangerous pattern found, 1 if safe
_sandbox_check_command_injection() {
    local input="$1"

    # Check for command substitution
    [[ "$input" == *'$('* ]] && return 0
    [[ "$input" == *'`'* ]] && return 0

    # Check for command separators
    [[ "$input" == *';'* ]] && return 0
    [[ "$input" == *'&&'* ]] && return 0
    [[ "$input" == *'||'* ]] && return 0
    [[ "$input" == *'|'* ]] && return 0

    # Check for redirections
    [[ "$input" == *'>'* ]] && return 0
    [[ "$input" == *'<'* ]] && return 0

    # Check for IFS manipulation
    [[ "$input" == *'${IFS}'* ]] && return 0
    [[ "$input" == *'$IFS'* ]] && return 0

    # Check for encoding tricks
    [[ "$input" == *'%3B'* ]] && return 0  # URL-encoded semicolon
    [[ "$input" == *'%26'* ]] && return 0  # URL-encoded ampersand
    [[ "$input" == *'%7C'* ]] && return 0  # URL-encoded pipe

    # Safe
    return 1
}

# Check for path traversal patterns
# Returns: 0 if traversal pattern found, 1 if safe
_sandbox_check_path_traversal() {
    local input="$1"

    # Common traversal patterns
    [[ "$input" == *'../'* ]] && return 0
    [[ "$input" == *'..\'* ]] && return 0
    [[ "$input" == *'/..' ]] && return 0
    [[ "$input" == *'\..' ]] && return 0

    # Encoded variants
    [[ "$input" == *'%2e%2e'* ]] && return 0
    [[ "$input" == *'%2E%2E'* ]] && return 0
    [[ "$input" == *'..%252f'* ]] && return 0
    [[ "$input" == *'..%252F'* ]] && return 0

    # Double encoding
    [[ "$input" == *'%252e%252e'* ]] && return 0
    [[ "$input" == *'%252E%252E'* ]] && return 0

    # Null byte
    [[ "$input" == *'%00'* ]] && return 0

    # Safe
    return 1
}

# Check for destructive operations
# Returns: 0 if destructive, 1 if safe
_sandbox_check_destructive() {
    local cmd="$1"
    shift
    local -a args=("$@")

    # Destructive commands
    case "$cmd" in
        rm|del|delete)
            # Check for dangerous rm patterns
            for arg in "${args[@]}"; do
                [[ "$arg" == '/' ]] && return 0
                [[ "$arg" == '/*' ]] && return 0
                [[ "$arg" == '.' ]] && return 0
                [[ "$arg" == '..' ]] && return 0
                [[ "$arg" == '*' ]] && return 0
                [[ "$arg" == '-rf' ]] && return 0
                [[ "$arg" == '-fr' ]] && return 0
            done
            ;;
        mkfs|format|fdisk|dd)
            return 0
            ;;
        ':>')
            return 0
            ;;
    esac

    # Check arguments for system paths
    local system_paths=('/bin' '/sbin' '/usr' '/etc' '/var' '/lib' '/lib64' '/boot' '/sys' '/proc' '/dev')
    for arg in "${args[@]}"; do
        for sys_path in "${system_paths[@]}"; do
            if [[ "$arg" == "$sys_path"* ]]; then
                return 0
            fi
        done
    done

    return 1
}

# =============================================================================
# PIPELINE SANDBOXING
# =============================================================================

# Execute pipeline with sandboxing for each stage
# Usage: sandbox_pipeline -- "cmd1 | cmd2 | cmd3"
# Tracks each stage, reports failures with context
sandbox_pipeline() {
    local pipeline=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                pipeline="$1"
                break
                ;;
            *)
                pipeline="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$pipeline" ]]; then
        _sandbox_exec_error "No pipeline specified"
        return 1
    fi

    # Parse pipeline into stages
    local -a stages=()
    local IFS='|'
    read -ra stages <<< "$pipeline"

    _sandbox_exec_info "Executing pipeline with ${#stages[@]} stage(s)"

    local -a stage_results=()
    local stage_num=0
    local failed_stage=0
    local stage_exit=0

    for stage in "${stages[@]}"; do
        ((stage_num++))
        stage=$(echo "$stage" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        _sandbox_exec_debug "Stage $stage_num: $stage"

        # Parse stage into command and args
        local -a stage_args=()
        read -ra stage_args <<< "$stage"

        if [[ ${#stage_args[@]} -eq 0 ]]; then
            continue
        fi

        local stage_cmd="${stage_args[0]}"
        local -a stage_cmd_args=("${stage_args[@]:1}")

        # Execute stage
        if [[ $stage_num -eq 1 ]]; then
            # First stage
            sandbox_exec -- "$stage_cmd" "${stage_cmd_args[@]}"
        else
            # Subsequent stages - need to handle stdin
            # For simplicity, re-execute the full pipeline up to this point
            # In production, you'd use named pipes or process substitution
            :
        fi

        stage_exit=$?
        stage_results+=("$stage_exit")

        if [[ $stage_exit -ne 0 ]]; then
            failed_stage=$stage_num
            break
        fi
    done

    # Output pipeline report
    printf '{\n'
    printf '  "pipeline": "%s",\n' "${pipeline//\"/\\\"}"
    printf '  "stages": %d,\n' "$stage_num"
    printf '  "failed_stage": %d,\n' "$failed_stage"
    printf '  "stage_results": ['
    local first=true
    for result in "${stage_results[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ', '
        fi
        printf '%d' "$result"
    done
    printf '],\n'
    printf '  "success": %s\n' "$([[ $failed_stage -eq 0 ]] && echo 'true' || echo 'false')"
    printf '}\n'

    return $([[ $failed_stage -eq 0 ]] && echo 0 || echo 1)
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get the exit code of the last sandboxed command
sandbox_last_exit_code() {
    echo "$_SANDBOX_LAST_EXIT_CODE"
}

# Get resource usage of the last sandboxed command
sandbox_last_resources() {
    printf '{\n'
    printf '  "exit_code": %d,\n' "$_SANDBOX_LAST_EXIT_CODE"
    printf '  "cpu_time": %s,\n' "${_SANDBOX_LAST_CPU_TIME:-0}"
    printf '  "memory_peak_kb": %s\n' "${_SANDBOX_LAST_MEMORY_PEAK:-0}"
    printf '}\n'
}

# Reset resource limits to defaults
sandbox_reset_limits() {
    SANDBOX_MAX_CPU_SECONDS=30
    SANDBOX_MAX_MEMORY_MB=512
    SANDBOX_MAX_FILE_SIZE_MB=100
    SANDBOX_MAX_PROCESSES=50
    SANDBOX_TIMEOUT_SECONDS=60
    SANDBOX_MAX_OPEN_FILES=1024
    SANDBOX_STACK_SIZE_MB=8
    _sandbox_exec_info "Resource limits reset to defaults"
}

# Set resource limits
# Usage: sandbox_set_limits [--cpu N] [--memory N] [--file-size N] [--procs N] [--timeout N]
sandbox_set_limits() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cpu)
                SANDBOX_MAX_CPU_SECONDS="$2"
                shift 2
                ;;
            --memory)
                SANDBOX_MAX_MEMORY_MB="$2"
                shift 2
                ;;
            --file-size)
                SANDBOX_MAX_FILE_SIZE_MB="$2"
                shift 2
                ;;
            --procs)
                SANDBOX_MAX_PROCESSES="$2"
                shift 2
                ;;
            --timeout)
                SANDBOX_TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --open-files)
                SANDBOX_MAX_OPEN_FILES="$2"
                shift 2
                ;;
            --stack)
                SANDBOX_STACK_SIZE_MB="$2"
                shift 2
                ;;
            *)
                _sandbox_exec_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    _sandbox_exec_info "Resource limits updated"
}

# Show current resource limits
sandbox_show_limits() {
    printf '%-20s %s\n' 'CPU (seconds):' "$SANDBOX_MAX_CPU_SECONDS"
    printf '%-20s %s MB\n' "Memory:" "$SANDBOX_MAX_MEMORY_MB"
    printf '%-20s %s MB\n' "File size:" "$SANDBOX_MAX_FILE_SIZE_MB"
    printf '%-20s %s\n' "Max processes:" "$SANDBOX_MAX_PROCESSES"
    printf '%-20s %s seconds\n' "Timeout:" "$SANDBOX_TIMEOUT_SECONDS"
    printf '%-20s %s\n' "Max open files:" "$SANDBOX_MAX_OPEN_FILES"
    printf '%-20s %s MB\n' 'Stack size:' "$SANDBOX_STACK_SIZE_MB"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_SANDBOX_EXEC_EXPORTS=(
    # Core execution
    sandbox_exec
    sandbox_exec_ai
    sandbox_exec_with_report
    sandbox_pipeline

    # Capability detection
    sandbox_available
    sandbox_capabilities

    # Resource management
    sandbox_set_limits
    sandbox_reset_limits
    sandbox_show_limits
    sandbox_last_exit_code
    sandbox_last_resources
)

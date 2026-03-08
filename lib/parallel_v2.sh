#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/parallel_v2.sh - Advanced Parallel Execution Engine V2
# =============================================================================
# Description: Enhanced parallel execution with map/reduce patterns, progress
#              tracking, and multiple execution backends (GNU parallel, 
#              background jobs, or sequential fallback).
#
# Dependencies: ansi.sh (for colors), json.sh (for output)
#
# Version: 2.0.0
# Requires: Bash 4.3+ (for namerefs and wait -n)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PARALLEL_V2_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PARALLEL_V2_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Auto-source dependencies if not loaded
if [[ -z "${_MAINFRAME_ANSI_LOADED:-}" ]]; then
    _pv2_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_pv2_lib_dir}/ansi.sh" ]]; then
        source "${_pv2_lib_dir}/ansi.sh"
    fi
fi

if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    _pv2_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_pv2_lib_dir}/json.sh" ]]; then
        source "${_pv2_lib_dir}/json.sh"
    fi
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default concurrency limit
PARALLEL_V2_DEFAULT_JOBS="${PARALLEL_V2_DEFAULT_JOBS:-4}"

# Backend: auto|gnu|bash|sequential
# Default to bash to avoid GNU parallel issues in some environments
PARALLEL_V2_BACKEND="${PARALLEL_V2_BACKEND:-bash}"

# State directory for coordination files
PARALLEL_V2_STATE_DIR="${PARALLEL_V2_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_parallel_v2}"

# Default timeout (seconds, 0 = no timeout)
PARALLEL_V2_DEFAULT_TIMEOUT="${PARALLEL_V2_DEFAULT_TIMEOUT:-0}"

# Progress bar width
PARALLEL_V2_PROGRESS_WIDTH="${PARALLEL_V2_PROGRESS_WIDTH:-40}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current time in milliseconds
_pv2_now_ms() {
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
            printf '%s000' "$(date +%s)"
        fi
    fi
}

# Format duration in human-readable form
_pv2_format_duration() {
    local ms="$1"
    
    if [[ $ms -lt 1000 ]]; then
        printf '%dms' "$ms"
    elif [[ $ms -lt 60000 ]]; then
        printf '%.1fs' "$(echo "scale=1; $ms / 1000" | bc 2>/dev/null || echo "$((ms / 1000)).0")"
    else
        local secs=$((ms / 1000))
        local mins=$((secs / 60))
        local rem_secs=$((secs % 60))
        printf '%dm %ds' "$mins" "$rem_secs"
    fi
}

# Detect available backend
_pv2_detect_backend() {
    case "$PARALLEL_V2_BACKEND" in
        gnu)
            if command -v parallel >/dev/null 2>&1; then
                printf 'gnu'
            else
                printf 'bash'
            fi
            ;;
        bash)
            printf 'bash'
            ;;
        sequential)
            printf 'sequential'
            ;;
        auto|*)
            if command -v parallel >/dev/null 2>&1; then
                printf 'gnu'
            elif ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
                printf 'bash'
            else
                printf 'sequential'
            fi
            ;;
    esac
}

# Check if wait -n is supported
_pv2_has_wait_n() {
    ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)))
}

# Create progress bar string
_pv2_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-$PARALLEL_V2_PROGRESS_WIDTH}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    printf '%s' "$bar"
}

# Calculate estimated time remaining
_pv2_eta() {
    local current="$1"
    local total="$2"
    local elapsed_ms="$3"
    
    if [[ $current -eq 0 ]]; then
        printf 'calculating...'
        return
    fi
    
    local rate=$(echo "scale=6; $elapsed_ms / $current" | bc 2>/dev/null || echo "$((elapsed_ms / current))")
    local remaining=$(echo "scale=0; $rate * ($total - $current) / 1" | bc 2>/dev/null || echo "$((rate * (total - current)))")
    
    _pv2_format_duration "$remaining"
}

# Log helper
_pv2_log() {
    local level="$1"
    shift
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[parallel_v2] %s: %s\n' "$level" "$*" >&2
    fi
}

# =============================================================================
# PROGRESS DISPLAY
# =============================================================================

# Show progress bar for running operation
# @pre: current <= total, elapsed_ms >= 0
# @post: progress bar printed to stderr
_pv2_show_progress() {
    local current="$1"
    local total="$2"
    local elapsed_ms="$3"
    local message="${4:-}"
    
    local percent=$((current * 100 / total))
    local bar
    bar=$(_pv2_progress_bar "$current" "$total")
    local eta
    eta=$(_pv2_eta "$current" "$total" "$elapsed_ms")
    
    # Clear line and print progress
    printf '\r\033[K' >&2
    printf '%b[%s]%b %3d%% %s/%s' "${CLR_CYAN}" "$bar" "$CLR_RESET" "$percent" "$current" "$total" >&2
    
    if [[ -n "$message" ]]; then
        printf ' | %s' "$message" >&2
    fi
    
    printf ' (ETA: %s)' "$eta" >&2
}

# Clear progress line
_pv2_clear_progress() {
    printf '\r\033[K' >&2
}

# =============================================================================
# CORE PARALLEL EXECUTION
# =============================================================================

# Execute commands in parallel using bash background jobs
# @pre: commands array, jobs > 0
# @post: all commands executed with concurrency limit
# @returns: JSON result array
_pv2_run_bash_parallel() {
    local -n _pv2_cmds=$1
    local max_jobs="$2"
    local timeout="${3:-0}"
    
    local total=${#_pv2_cmds[@]}
    local start_ms
    start_ms=$(_pv2_now_ms)
    
    mkdir -p "$PARALLEL_V2_STATE_DIR"
    
    # Arrays to track state
    local -a pids=()
    local -a pid_to_idx=()
    local -a tmpfiles=()
    local -a statuses=()
    local -a durations=()
    local -a outputs=()
    
    # Initialize result arrays
    local i
    for ((i=0; i<total; i++)); do
        statuses[$i]="pending"
        durations[$i]=0
        outputs[$i]=""
    done
    
    local running=0
    local next_idx=0
    local completed=0
    local failed=0
    
    # Launch and monitor jobs
    while [[ $completed -lt $total ]]; do
        # Start new jobs up to limit
        while [[ $running -lt $max_jobs && $next_idx -lt $total ]]; do
            local cmd="${_pv2_cmds[$next_idx]}"
            local tmpfile
            tmpfile=$(mktemp "$PARALLEL_V2_STATE_DIR/pv2_XXXXXX")
            tmpfiles[$next_idx]="$tmpfile"
            
            {
                local job_start
                job_start=$(_pv2_now_ms)
                local output
                local status
                
                # Handle timeout if specified
                if [[ $timeout -gt 0 ]]; then
                    output=$(timeout "$timeout" bash -c "$cmd" 2>&1) || true
                    status=$?
                    if [[ $status -eq 124 ]]; then
                        output="TIMEOUT: Command exceeded ${timeout}s"
                    fi
                else
                    output=$(eval "$cmd" 2>&1)
                    status=$?
                fi
                
                local job_end
                job_end=$(_pv2_now_ms)
                local job_duration=$((job_end - job_start))
                
                # Always write the result file
                printf '%d\n%d\n%s' "$status" "$job_duration" "$output" > "$tmpfile"
            } &
            
            local pid=$!
            pids+=($pid)
            pid_to_idx[$pid]=$next_idx
            statuses[$next_idx]="running"
            ((running++))
            ((next_idx++))
        done
        
        # Wait for any job to complete
        if [[ $running -gt 0 ]]; then
            sleep 0.05
            
            # Check which jobs finished
            local pid
            for pid in "${!pid_to_idx[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    local idx="${pid_to_idx[$pid]}"
                    local tmpfile="${tmpfiles[$idx]}"
                    
                    wait "$pid" 2>/dev/null || true
                    
                    # Read results
                    if [[ -f "$tmpfile" ]]; then
                        local content
                        content=$(<"$tmpfile")
                        local job_status job_duration job_output
                        job_status=$(printf '%s' "$content" | head -1)
                        job_duration=$(printf '%s' "$content" | sed -n '2p')
                        job_output=$(printf '%s' "$content" | tail -n +3)
                        
                        statuses[$idx]="done"
                        durations[$idx]="${job_duration:-0}"
                        outputs[$idx]="$job_output"
                        
                        if [[ "$job_status" -eq 0 ]]; then
                            statuses[$idx]="done"
                        else
                            statuses[$idx]="error"
                            ((failed++))
                        fi
                        ((completed++))
                        
                        rm -f "$tmpfile"
                    fi
                    
                    unset "pid_to_idx[$pid]"
                    
                    # Remove from pids array
                    local -a new_pids=()
                    local p
                    for p in "${pids[@]}"; do
                        if [[ "$p" != "$pid" ]]; then
                            new_pids+=("$p")
                        fi
                    done
                    pids=("${new_pids[@]}")
                    
                    ((running--))
                fi
            done
        fi
    done
    
    # Final wait for stragglers
    wait 2>/dev/null || true
    
    local end_ms
    end_ms=$(_pv2_now_ms)
    local total_duration=$((end_ms - start_ms))
    
    # Build JSON result
    local results_json="["
    local first=true
    for ((i=0; i<total; i++)); do
        $first || results_json+=","
        first=false
        
        local entry_status="done"
        local error=""
        if [[ "${statuses[$i]:-}" == "error" ]]; then
            entry_status="error"
            error="exit code 1"
        fi
        
        # Escape output for JSON (simple version)
        local escaped_output="${outputs[$i]}"
        escaped_output=${escaped_output//\\/\\\\}
        escaped_output=${escaped_output//\"/\\\"}
        escaped_output=${escaped_output//$'\n'/\\n}
        escaped_output=${escaped_output//$'\r'/\\r}
        escaped_output=${escaped_output//$'\t'/\\t}
        
        results_json+="{\"index\":$i,\"status\":\"$entry_status\",\"result\":\"${escaped_output}\",\"duration_ms\":${durations[$i]}}"
    done
    results_json+="]"
    
    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"
    
    printf '{"ok":%s,"data":{"results":%s,"total_duration_ms":%d,"succeeded":%d,"failed":%d}}' \
        "$ok" "$results_json" "$total_duration" "$completed" "$failed"
    
    [[ $failed -eq 0 ]]
}

# Execute commands using GNU parallel
# @pre: commands array, GNU parallel installed
# @post: all commands executed
# @returns: JSON result array
_pv2_run_gnu_parallel() {
    local -n _pv2_cmds_gnu=$1
    local max_jobs="$2"
    local timeout="${3:-0}"
    
    local total=${#_pv2_cmds_gnu[@]}
    local start_ms
    start_ms=$(_pv2_now_ms)
    
    mkdir -p "$PARALLEL_V2_STATE_DIR"
    
    # Create command file
    local cmdfile
    cmdfile=$(mktemp "$PARALLEL_V2_STATE_DIR/cmds_XXXXXX")
    
    local i
    for ((i=0; i<total; i++)); do
        printf '%s\t%s\n' "$i" "${_pv2_cmds_gnu[$i]}"
    done > "$cmdfile"
    
    # Build parallel command
    local parallel_opts="-j $max_jobs --colsep '\t' --results $PARALLEL_V2_STATE_DIR/parallel_results"
    
    if [[ $timeout -gt 0 ]]; then
        parallel_opts="$parallel_opts --timeout $timeout"
    fi
    
    # Execute with GNU parallel
    eval "parallel $parallel_opts 'echo {1}; {2}' :::: $cmdfile" 2>/dev/null || true
    
    # Parse results
    local -a results=()
    local -a durations=()
    local -a statuses=()
    
    for ((i=0; i<total; i++)); do
        results[$i]=""
        durations[$i]=0
        statuses[$i]=1
    done
    
    # Read parallel results
    for result_file in "$PARALLEL_V2_STATE_DIR/parallel_results"/*/stdout; do
        if [[ -f "$result_file" ]]; then
            local seq_dir
            seq_dir=$(dirname "$result_file")
            local seq=$(basename "$seq_dir")
            local exit_file="$seq_dir/exit"
            
            if [[ -f "$exit_file" ]]; then
                local exit_code
                exit_code=$(<"$exit_file")
                statuses[$seq]="$exit_code"
            fi
            
            results[$seq]=$(<"$result_file")
        fi
    done
    
    rm -f "$cmdfile"
    rm -rf "$PARALLEL_V2_STATE_DIR/parallel_results"
    
    local end_ms
    end_ms=$(_pv2_now_ms)
    local total_duration=$((end_ms - start_ms))
    
    # Count successes/failures
    local succeeded=0
    local failed=0
    for ((i=0; i<total; i++)); do
        if [[ "${statuses[$i]}" -eq 0 ]]; then
            ((succeeded++))
        else
            ((failed++))
        fi
    done
    
    # Build JSON result
    local results_json="["
    local first=true
    for ((i=0; i<total; i++)); do
        $first || results_json+=","
        first=false
        
        local entry_status="done"
        local error=""
        if [[ "${statuses[$i]}" -ne 0 ]]; then
            entry_status="error"
            error="exit code ${statuses[$i]}"
        fi
        
        local escaped_output
        escaped_output=$(printf '%s' "${results[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g')
        
        results_json+="{\"index\":$i,\"status\":\"$entry_status\",\"result\":\"${escaped_output}\",\"duration_ms\":${durations[$i]}}"
    done
    results_json+="]"
    
    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"
    
    printf '{"ok":%s,"data":{"results":%s,"total_duration_ms":%d,"succeeded":%d,"failed":%d}}' \
        "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
    
    [[ $failed -eq 0 ]]
}

# Execute commands sequentially (fallback)
# @pre: commands array
# @post: all commands executed sequentially
# @returns: JSON result array
_pv2_run_sequential() {
    local -n _pv2_cmds_seq=$1
    local timeout="${3:-0}"
    
    local total=${#_pv2_cmds_seq[@]}
    local start_ms
    start_ms=$(_pv2_now_ms)
    
    local -a results=()
    local -a durations=()
    local -a statuses=()
    
    local i
    for ((i=0; i<total; i++)); do
        local cmd="${_pv2_cmds_seq[$i]}"
        local job_start
        job_start=$(_pv2_now_ms)
        
        local output
        local status
        
        if [[ $timeout -gt 0 ]]; then
            output=$(timeout "$timeout" bash -c "$cmd" 2>&1)
            status=$?
        else
            output=$(eval "$cmd" 2>&1)
            status=$?
        fi
        
        local job_end
        job_end=$(_pv2_now_ms)
        
        results[$i]="$output"
        durations[$i]=$((job_end - job_start))
        statuses[$i]=$status
    done
    
    local end_ms
    end_ms=$(_pv2_now_ms)
    local total_duration=$((end_ms - start_ms))
    
    # Count successes/failures
    local succeeded=0
    local failed=0
    for ((i=0; i<total; i++)); do
        if [[ "${statuses[$i]}" -eq 0 ]]; then
            ((succeeded++))
        else
            ((failed++))
        fi
    done
    
    # Build JSON result
    local results_json="["
    local first=true
    for ((i=0; i<total; i++)); do
        $first || results_json+=","
        first=false
        
        local entry_status="done"
        local error=""
        if [[ "${statuses[$i]}" -ne 0 ]]; then
            entry_status="error"
            error="exit code ${statuses[$i]}"
        fi
        
        local escaped_output
        escaped_output=$(printf '%s' "${results[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g')
        
        results_json+="{\"index\":$i,\"status\":\"$entry_status\",\"result\":\"${escaped_output}\",\"duration_ms\":${durations[$i]}}"
    done
    results_json+="]"
    
    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"
    
    printf '{"ok":%s,"data":{"results":%s,"total_duration_ms":%d,"succeeded":%d,"failed":%d}}' \
        "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
    
    [[ $failed -eq 0 ]]
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: at least one command provided
# @post: commands executed in parallel
# @returns: 0 if all succeed, 1 otherwise. USOP JSON to stdout.
#
# Run multiple commands in parallel
#
# Usage: parallel_v2_run [options] "cmd1" "cmd2" ...
# Options:
#   -j, --jobs N      Max parallel jobs (default: PARALLEL_V2_DEFAULT_JOBS)
#   -t, --timeout S   Timeout per command in seconds (default: 0 = no timeout)
#   --backend TYPE    Execution backend: gnu|bash|sequential|auto
#   --progress        Show progress bar
#
# Example: parallel_v2_run --jobs 4 "sleep 1" "sleep 2" "sleep 1"
parallel_v2_run() {
    local jobs="$PARALLEL_V2_DEFAULT_JOBS"
    local timeout="$PARALLEL_V2_DEFAULT_TIMEOUT"
    local backend="$PARALLEL_V2_BACKEND"
    local show_progress=false
    local -a commands=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            --backend)
                backend="$2"
                shift 2
                ;;
            --progress)
                show_progress=true
                shift
                ;;
            --)
                shift
                commands+=("$@")
                break
                ;;
            -*)
                _pv2_log error "Unknown option: $1"
                return 1
                ;;
            *)
                commands+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ ${#commands[@]} -eq 0 ]]; then
        _pv2_log error "No commands provided"
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}\n'
        return 1
    fi
    
    local detected_backend
    detected_backend=$(_pv2_detect_backend)
    if [[ "$backend" != "auto" ]]; then
        detected_backend="$backend"
    fi
    
    _pv2_log info "Running ${#commands[@]} commands with $detected_backend backend (jobs=$jobs)"
    
    # Execute based on backend
    case "$detected_backend" in
        gnu)
            _pv2_run_gnu_parallel commands "$jobs" "$timeout"
            ;;
        bash)
            _pv2_run_bash_parallel commands "$jobs" "$timeout"
            ;;
        sequential|*)
            _pv2_run_sequential commands "$timeout"
            ;;
    esac
}

# @pre: command template provided, files/items provided
# @post: command executed for each file/item in parallel
# @returns: 0 if all succeed, 1 otherwise
#
# Map a command over a list of files/items
#
# Usage: parallel_v2_map [options] "command_template" "file1" "file2" ...
# The command template can use {} as placeholder for the item
#
# Example: parallel_v2_map "wc -l {}" file1.txt file2.txt file3.txt
parallel_v2_map() {
    local jobs="$PARALLEL_V2_DEFAULT_JOBS"
    local timeout="$PARALLEL_V2_DEFAULT_TIMEOUT"
    local backend="$PARALLEL_V2_BACKEND"
    local show_progress=false
    local -a items=()
    local template=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            --backend)
                backend="$2"
                shift 2
                ;;
            --progress)
                show_progress=true
                shift
                ;;
            --)
                shift
                items+=("$@")
                break
                ;;
            -*)
                _pv2_log error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$template" ]]; then
                    template="$1"
                else
                    items+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$template" ]]; then
        _pv2_log error "No command template provided"
        return 1
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        _pv2_log error "No items provided"
        printf '{"ok":false,"error":{"code":"E_NO_ITEMS","msg":"No items provided"}}\n'
        return 1
    fi
    
    # Build commands from template
    local -a commands=()
    local item
    for item in "${items[@]}"; do
        local cmd="${template//\{\}/$item}"
        commands+=("$cmd")
    done
    
    # Run using parallel_v2_run
    parallel_v2_run --jobs "$jobs" --timeout "$timeout" --backend "$backend" "${commands[@]}"
}

# @pre: reduce command provided, files/items provided
# @post: items reduced to single result
# @returns: 0 on success, 1 on failure
#
# Reduce a list of files/items using a binary operation
#
# Usage: parallel_v2_reduce [options] "reduce_cmd" "initial" "item1" "item2" ...
# The reduce command receives (acc, item) and should output new acc
# Use {} for accumulator placeholder and [] for item placeholder
#
# Example: parallel_v2_reduce "echo $(({} + []))" 0 1 2 3 4 5
parallel_v2_reduce() {
    local jobs="$PARALLEL_V2_DEFAULT_JOBS"
    local -a items=()
    local reduce_cmd=""
    local initial=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            --)
                shift
                items+=("$@")
                break
                ;;
            -*)
                _pv2_log error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$reduce_cmd" ]]; then
                    reduce_cmd="$1"
                elif [[ -z "$initial" ]]; then
                    initial="$1"
                else
                    items+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$reduce_cmd" || ${#items[@]} -eq 0 ]]; then
        _pv2_log error "Usage: parallel_v2_reduce <reduce_cmd> <initial> <item>..."
        return 1
    fi
    
    local accumulator="$initial"
    local item
    
    # Sequential reduce (parallel reduce is complex and tree-based)
    for item in "${items[@]}"; do
        local cmd="${reduce_cmd//\{\}/$accumulator}"
        cmd="${cmd//\[\]/$item}"
        accumulator=$(eval "$cmd" 2>&1) || {
            _pv2_log error "Reduce operation failed: $cmd"
            return 1
        }
    done
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local escaped_acc
        escaped_acc=$(printf '%s' "$accumulator" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
        printf '{"ok":true,"data":{"result":"%s","initial":"%s","count":%d}}\n' \
            "$escaped_acc" "$initial" "${#items[@]}"
    else
        printf '%s\n' "$accumulator"
    fi
    
    return 0
}

# @pre: total count known
# @post: progress bar displayed
# @returns: 0
#
# Show progress bar for any operation
#
# Usage: 
#   parallel_v2_progress_init 100 "Processing"
#   parallel_v2_progress_update 50 "Halfway"
#   parallel_v2_progress_finish "Done"
#
# Or use with subshell:
#   parallel_v2_progress_monitor 100 "Building" < <(commands...)

# Initialize progress tracking
parallel_v2_progress_init() {
    local total="$1"
    local message="${2:-Processing}"
    
    _PV2_PROGRESS_TOTAL="$total"
    _PV2_PROGRESS_CURRENT=0
    _PV2_PROGRESS_MESSAGE="$message"
    _PV2_PROGRESS_START=$(_pv2_now_ms)
    
    _pv2_show_progress 0 "$total" 0 "$message"
}

# Update progress
parallel_v2_progress_update() {
    local current="$1"
    local message="${2:-$_PV2_PROGRESS_MESSAGE}"
    
    _PV2_PROGRESS_CURRENT="$current"
    _PV2_PROGRESS_MESSAGE="$message"
    
    local now
    now=$(_pv2_now_ms)
    local elapsed=$((now - _PV2_PROGRESS_START))
    
    _pv2_show_progress "$current" "$_PV2_PROGRESS_TOTAL" "$elapsed" "$message"
}

# Increment progress
parallel_v2_progress_increment() {
    local amount="${1:-1}"
    local message="${2:-$_PV2_PROGRESS_MESSAGE}"
    
    (( _PV2_PROGRESS_CURRENT += amount ))
    parallel_v2_progress_update "$_PV2_PROGRESS_CURRENT" "$message"
}

# Finish progress
parallel_v2_progress_finish() {
    local message="${1:-Complete}"
    
    local now
    now=$(_pv2_now_ms)
    local elapsed=$((now - _PV2_PROGRESS_START))
    
    _pv2_clear_progress
    printf '%b✓%b %s (%s)\n' "$CLR_GREEN" "$CLR_RESET" "$message" "$(_pv2_format_duration "$elapsed")" >&2
}

# Monitor commands and show progress
# Usage: command_that_emits_lines | parallel_v2_progress_monitor 100 "Label"
parallel_v2_progress_monitor() {
    local total="$1"
    local message="${2:-Processing}"
    
    local current=0
    parallel_v2_progress_init "$total" "$message"
    
    while IFS= read -r line; do
        printf '%s\n' "$line"
        ((current++))
        if [[ $current -le $total ]]; then
            parallel_v2_progress_update "$current" "$message"
        fi
    done
    
    parallel_v2_progress_finish "Complete"
}

# =============================================================================
# ADVANCED PATTERNS
# =============================================================================

# Pipeline: run commands in sequence with parallel stages
# Usage: parallel_v2_pipeline "cmd1" "|" "cmd2" "|" "cmd3"
parallel_v2_pipeline() {
    local -a stages=()
    local -a commands=()
    
    # Parse pipeline
    local item
    for item in "$@"; do
        if [[ "$item" == "|" ]]; then
            stages+=("${commands[*]}")
            commands=()
        else
            commands+=("$item")
        fi
    done
    [[ ${#commands[@]} -gt 0 ]] && stages+=("${commands[*]}")
    
    if [[ ${#stages[@]} -eq 0 ]]; then
        _pv2_log error "No pipeline stages defined"
        return 1
    fi
    
    # Execute pipeline (sequential stages, but each stage can be parallel)
    local output=""
    local stage
    for stage in "${stages[@]}"; do
        if [[ -z "$output" ]]; then
            output=$(eval "$stage" 2>&1)
        else
            output=$(printf '%s' "$output" | eval "$stage" 2>&1)
        fi
    done
    
    printf '%s\n' "$output"
}

# Fan-out / Fan-in pattern
# Usage: parallel_v2_fanout "collector_cmd" "worker1" "worker2" ...
parallel_v2_fanout() {
    local collector="$1"
    shift
    local -a workers=("$@")
    
    if [[ -z "$collector" || ${#workers[@]} -eq 0 ]]; then
        _pv2_log error "Usage: parallel_v2_fanout <collector> <worker>..."
        return 1
    fi
    
    # Run workers in parallel
    local result
    result=$(parallel_v2_run "${workers[@]}")
    
    # Pass results to collector
    printf '%s' "$result" | eval "$collector"
}

# =============================================================================
# CLEANUP
# =============================================================================

parallel_v2_cleanup() {
    if [[ -d "$PARALLEL_V2_STATE_DIR" ]]; then
        # Only remove files older than 1 hour to avoid interfering with running jobs
        find "$PARALLEL_V2_STATE_DIR" -type f -mmin +60 -delete 2>/dev/null || true
    fi
}

# Register cleanup on exit (only cleans old files)
if [[ -z "${PARALLEL_V2_NO_CLEANUP:-}" ]]; then
    if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
        _mainframe_add_exit_trap "parallel_v2_cleanup"
    else
        trap parallel_v2_cleanup EXIT
    fi
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_PARALLEL_V2_EXPORTS=(
    parallel_v2_run
    parallel_v2_map
    parallel_v2_reduce
    parallel_v2_progress_init
    parallel_v2_progress_update
    parallel_v2_progress_increment
    parallel_v2_progress_finish
    parallel_v2_progress_monitor
    parallel_v2_pipeline
    parallel_v2_fanout
    parallel_v2_cleanup
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_PARALLEL_V2_EXPORTS[@]}" 2>/dev/null || true
fi

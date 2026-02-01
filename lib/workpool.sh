#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/workpool.sh - Lightweight Work Pool for Parallel Batch Processing
# =============================================================================
# Description: Simple parallel work pool without full orchestration overhead.
#              Uses background jobs with job control, temp files for IPC.
# Version: 1.0.0
# Requires: Bash 4.3+ (for wait -n support, falls back on older versions)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_WORKPOOL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_WORKPOOL_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# shellcheck source=./common.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/common.sh" 2>/dev/null || true
# shellcheck source=./json.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/json.sh" 2>/dev/null || true

# =============================================================================
# CONSTANTS & CONFIGURATION
# =============================================================================

# Default max workers (uses CPU count)
readonly POOL_DEFAULT_WORKERS="${POOL_DEFAULT_WORKERS:-0}"

# Pool state directory
readonly POOL_STATE_DIR="${POOL_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_pools}"

# Job status values
readonly POOL_STATUS_PENDING="pending"
readonly POOL_STATUS_RUNNING="running"
readonly POOL_STATUS_DONE="done"
readonly POOL_STATUS_FAILED="failed"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get CPU count for default workers
_pool_cpu_count() {
    if [[ -f /proc/cpuinfo ]]; then
        grep -c '^processor' /proc/cpuinfo 2>/dev/null
    elif command -v nproc &>/dev/null; then
        nproc 2>/dev/null
    elif command -v sysctl &>/dev/null; then
        sysctl -n hw.ncpu 2>/dev/null
    else
        echo 4  # Fallback default
    fi
}

# Validate pool name (alphanumeric, underscore, hyphen only)
_pool_validate_name() {
    local name="$1"
    [[ -n "$name" && "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]
}

# Get pool directory
_pool_dir() {
    local name="$1"
    printf '%s/%s' "$POOL_STATE_DIR" "$name"
}

# Check if pool exists
_pool_exists() {
    local name="$1"
    [[ -d "$(_pool_dir "$name")" ]]
}

# Generate unique job ID
_pool_job_id() {
    printf 'job_%s_%d' "$(date +%s%N 2>/dev/null || date +%s)" "$$"
}

# Internal logging
_pool_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "workpool" "$level" "$*"
    fi
}

# JSON escape for output
_pool_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Wait for any background job (version-gated)
_pool_wait_any() {
    if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
        wait -n 2>/dev/null || sleep 0.1
    else
        sleep 0.2
    fi
}

# Get number of running jobs for a pool
_pool_running_count() {
    local name="$1"
    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    local count=0
    local job_dir
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        local pid_file="$job_dir/pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                ((count++))
            fi
        fi
    done

    printf '%d' "$count"
}

# Update job status
_pool_update_status() {
    local job_dir="$1"
    local status="$2"
    printf '%s' "$status" > "$job_dir/status"
}

# =============================================================================
# POOL MANAGEMENT
# =============================================================================

# -----------------------------------------------------------------------------
# pool_create - Create a new work pool
# -----------------------------------------------------------------------------
# @description Create a pool with specified number of workers
# @param       $1 name - Pool name (alphanumeric, underscore, hyphen)
# @param       $2 max_workers - Maximum concurrent workers (default: CPU count)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_create "downloads" 4
#   pool_create "processors"  # Uses CPU count
# -----------------------------------------------------------------------------
pool_create() {
    local name="$1"
    local max_workers="${2:-0}"

    # Validate pool name
    if ! _pool_validate_name "$name"; then
        _pool_log "error" "Invalid pool name: $name"
        return 1
    fi

    # Check if pool already exists
    if _pool_exists "$name"; then
        _pool_log "warn" "Pool already exists: $name"
        return 0  # Idempotent
    fi

    # Determine worker count
    if [[ "$max_workers" -le 0 ]]; then
        max_workers=$(_pool_cpu_count)
    fi

    # Create pool directory structure
    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    mkdir -p "$pool_dir/jobs" || return 1
    mkdir -p "$pool_dir/results" || return 1

    # Store pool configuration
    printf '%d\n' "$max_workers" > "$pool_dir/max_workers"
    printf '0\n' > "$pool_dir/job_counter"
    printf '%d\n' "$$" > "$pool_dir/owner_pid"

    # Initialize rate limit (0 = unlimited)
    printf '0\n' > "$pool_dir/rate_limit"
    printf '0\n' > "$pool_dir/last_submit"

    # Initialize semaphore count (0 = unlimited)
    printf '0\n' > "$pool_dir/semaphore"

    _pool_log "info" "Created pool '$name' with $max_workers workers"
    return 0
}

# -----------------------------------------------------------------------------
# pool_destroy - Clean up pool resources
# -----------------------------------------------------------------------------
# @description Stop all jobs and remove pool state
# @param       $1 name - Pool name
# @return      0 on success, 1 on error
#
# Usage:
#   pool_destroy "downloads"
# -----------------------------------------------------------------------------
pool_destroy() {
    local name="$1"

    if ! _pool_exists "$name"; then
        return 0  # Idempotent
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    # Kill all running jobs
    local job_dir
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        local pid_file="$job_dir/pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        fi
    done

    # Remove pool directory
    rm -rf "$pool_dir"

    _pool_log "info" "Destroyed pool '$name'"
    return 0
}

# -----------------------------------------------------------------------------
# pool_resize - Adjust worker count
# -----------------------------------------------------------------------------
# @description Change maximum concurrent workers for a pool
# @param       $1 name - Pool name
# @param       $2 count - New worker count
# @return      0 on success, 1 on error
#
# Usage:
#   pool_resize "downloads" 8
# -----------------------------------------------------------------------------
pool_resize() {
    local name="$1"
    local count="$2"

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    if [[ ! "$count" =~ ^[1-9][0-9]*$ ]]; then
        _pool_log "error" "Invalid worker count: $count"
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"
    printf '%d\n' "$count" > "$pool_dir/max_workers"

    _pool_log "info" "Resized pool '$name' to $count workers"
    return 0
}

# =============================================================================
# JOB SUBMISSION
# =============================================================================

# -----------------------------------------------------------------------------
# pool_submit - Submit a job to the pool
# -----------------------------------------------------------------------------
# @description Submit a command for execution, returns job ID
# @param       $1 name - Pool name
# @param       $@ command - Command and arguments to execute
# @stdout      Job ID
# @return      0 on success, 1 on error
#
# Usage:
#   job_id=$(pool_submit "downloads" curl -sO "$url")
# -----------------------------------------------------------------------------
pool_submit() {
    local name="$1"
    shift
    local command=("$@")

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    if [[ ${#command[@]} -eq 0 ]]; then
        _pool_log "error" "No command provided"
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    # Apply rate limiting
    local rate_limit last_submit now
    rate_limit=$(cat "$pool_dir/rate_limit" 2>/dev/null || echo 0)
    if [[ "$rate_limit" -gt 0 ]]; then
        last_submit=$(cat "$pool_dir/last_submit" 2>/dev/null || echo 0)
        now=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
        local min_interval=$((1000000000 / rate_limit))  # nanoseconds
        local elapsed=$((now - last_submit))
        if [[ "$elapsed" -lt "$min_interval" ]]; then
            local sleep_ns=$((min_interval - elapsed))
            local sleep_s
            sleep_s=$(echo "scale=9; $sleep_ns / 1000000000" | bc 2>/dev/null || echo "0.1")
            sleep "$sleep_s" 2>/dev/null || sleep 0.1
        fi
        printf '%s\n' "$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")" > "$pool_dir/last_submit"
    fi

    # Generate job ID
    local job_counter job_id
    job_counter=$(cat "$pool_dir/job_counter" 2>/dev/null || echo 0)
    ((job_counter++))
    printf '%d\n' "$job_counter" > "$pool_dir/job_counter"
    job_id="job_$job_counter"

    # Create job directory
    local job_dir="$pool_dir/jobs/$job_id"
    mkdir -p "$job_dir"

    # Store command
    printf '%s\n' "${command[*]}" > "$job_dir/command"

    # Set initial status
    _pool_update_status "$job_dir" "$POOL_STATUS_PENDING"

    # Wait for slot if at capacity
    local max_workers running
    max_workers=$(cat "$pool_dir/max_workers" 2>/dev/null || echo 4)

    while true; do
        running=$(_pool_running_count "$name")
        if [[ "$running" -lt "$max_workers" ]]; then
            break
        fi
        _pool_wait_any
        # Clean up finished jobs
        _pool_cleanup_finished "$name"
    done

    # Check semaphore
    local semaphore semaphore_count
    semaphore=$(cat "$pool_dir/semaphore" 2>/dev/null || echo 0)
    if [[ "$semaphore" -gt 0 ]]; then
        while true; do
            semaphore_count=$(cat "$pool_dir/semaphore_count" 2>/dev/null || echo 0)
            if [[ "$semaphore_count" -lt "$semaphore" ]]; then
                ((semaphore_count++))
                printf '%d\n' "$semaphore_count" > "$pool_dir/semaphore_count"
                break
            fi
            sleep 0.1
        done
    fi

    # Launch job in background
    (
        _pool_update_status "$job_dir" "$POOL_STATUS_RUNNING"

        # Execute command and capture output
        local exit_code=0
        if "${command[@]}" > "$job_dir/stdout" 2> "$job_dir/stderr"; then
            exit_code=0
        else
            exit_code=$?
        fi

        # Store exit code
        printf '%d\n' "$exit_code" > "$job_dir/exit_code"

        # Update status based on exit code
        if [[ "$exit_code" -eq 0 ]]; then
            _pool_update_status "$job_dir" "$POOL_STATUS_DONE"
        else
            _pool_update_status "$job_dir" "$POOL_STATUS_FAILED"
        fi

        # Release semaphore if used
        if [[ "$semaphore" -gt 0 ]]; then
            local current
            current=$(cat "$pool_dir/semaphore_count" 2>/dev/null || echo 1)
            ((current--)) || current=0
            printf '%d\n' "$current" > "$pool_dir/semaphore_count"
        fi
    ) &

    # Store PID
    printf '%d\n' "$!" > "$job_dir/pid"

    # Output job ID
    printf '%s\n' "$job_id"
    return 0
}

# Clean up finished job tracking
_pool_cleanup_finished() {
    local name="$1"
    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    local job_dir
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        local pid_file="$job_dir/pid"
        local status_file="$job_dir/status"

        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                # Process finished, ensure status is updated
                local status
                status=$(cat "$status_file" 2>/dev/null)
                if [[ "$status" == "$POOL_STATUS_RUNNING" ]]; then
                    # Check exit code
                    local exit_code
                    exit_code=$(cat "$job_dir/exit_code" 2>/dev/null || echo 1)
                    if [[ "$exit_code" -eq 0 ]]; then
                        _pool_update_status "$job_dir" "$POOL_STATUS_DONE"
                    else
                        _pool_update_status "$job_dir" "$POOL_STATUS_FAILED"
                    fi
                fi
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# pool_submit_batch - Submit jobs from file
# -----------------------------------------------------------------------------
# @description Submit multiple jobs from a file (one command per line)
# @param       $1 name - Pool name
# @param       $2 file - File with commands (one per line)
# @stdout      Job IDs (one per line)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_submit_batch "downloads" commands.txt
# -----------------------------------------------------------------------------
pool_submit_batch() {
    local name="$1"
    local file="$2"

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _pool_log "error" "File not found: $file"
        return 1
    fi

    local line job_id
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Split line into command array (handles simple cases)
        local -a cmd
        read -ra cmd <<< "$line"

        job_id=$(pool_submit "$name" "${cmd[@]}")
        printf '%s\n' "$job_id"
    done < "$file"

    return 0
}

# -----------------------------------------------------------------------------
# pool_map - Map command over items
# -----------------------------------------------------------------------------
# @description Execute command with each item as argument
# @param       $1 name - Pool name
# @param       $2 command - Command to execute
# @param       $@ items - Items to process
# @stdout      Job IDs (one per line)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_map "processors" process_file file1.txt file2.txt file3.txt
# -----------------------------------------------------------------------------
# shellcheck disable=SC2178,SC2128  # command is a string, not array
pool_map() {
    local name="$1"
    local command="$2"
    shift 2
    local items=("$@")

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    local item job_id
    for item in "${items[@]}"; do
        job_id=$(pool_submit "$name" "$command" "$item")
        printf '%s\n' "$job_id"
    done

    return 0
}

# =============================================================================
# SYNCHRONIZATION
# =============================================================================

# -----------------------------------------------------------------------------
# pool_wait - Wait for job(s) to complete
# -----------------------------------------------------------------------------
# @description Wait for specific job or all jobs in pool
# @param       $1 name - Pool name
# @param       $2 job_id - Optional specific job ID (waits for all if omitted)
# @return      0 if all jobs succeeded, 1 if any failed
#
# Usage:
#   pool_wait "downloads"
#   pool_wait "downloads" "job_1"
# -----------------------------------------------------------------------------
pool_wait() {
    local name="$1"
    local job_id="${2:-}"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    local any_failed=0

    if [[ -n "$job_id" ]]; then
        # Wait for specific job
        local job_dir="$pool_dir/jobs/$job_id"
        if [[ ! -d "$job_dir" ]]; then
            _pool_log "error" "Job not found: $job_id"
            return 1
        fi

        local pid_file="$job_dir/pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                wait "$pid" 2>/dev/null || true
            fi
        fi

        # Check result
        local exit_code
        exit_code=$(cat "$job_dir/exit_code" 2>/dev/null || echo 1)
        [[ "$exit_code" -ne 0 ]] && any_failed=1
    else
        # Wait for all jobs
        local job_dir
        for job_dir in "$pool_dir/jobs"/*; do
            [[ -d "$job_dir" ]] || continue
            local pid_file="$job_dir/pid"
            if [[ -f "$pid_file" ]]; then
                local pid
                pid=$(cat "$pid_file" 2>/dev/null)
                if [[ -n "$pid" ]]; then
                    wait "$pid" 2>/dev/null || true
                fi
            fi

            # Check result
            local exit_code
            exit_code=$(cat "$job_dir/exit_code" 2>/dev/null || echo 1)
            [[ "$exit_code" -ne 0 ]] && any_failed=1
        done
    fi

    return "$any_failed"
}

# -----------------------------------------------------------------------------
# pool_wait_any - Wait for any job to complete
# -----------------------------------------------------------------------------
# @description Wait for the next job to complete, return its ID
# @param       $1 name - Pool name
# @stdout      Job ID of completed job
# @return      0 on success, 1 if no jobs pending
#
# Usage:
#   completed_job=$(pool_wait_any "downloads")
# -----------------------------------------------------------------------------
pool_wait_any() {
    local name="$1"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    # Find a running job and wait for it
    while true; do
        local job_dir job_id status
        for job_dir in "$pool_dir/jobs"/*; do
            [[ -d "$job_dir" ]] || continue
            job_id="${job_dir##*/}"
            status=$(cat "$job_dir/status" 2>/dev/null)

            # Check if just completed
            if [[ "$status" == "$POOL_STATUS_DONE" || "$status" == "$POOL_STATUS_FAILED" ]]; then
                # Check if we haven't reported this one yet
                if [[ ! -f "$job_dir/reported" ]]; then
                    touch "$job_dir/reported"
                    printf '%s\n' "$job_id"
                    return 0
                fi
            fi

            # Check if running
            if [[ "$status" == "$POOL_STATUS_RUNNING" ]]; then
                local pid_file="$job_dir/pid"
                if [[ -f "$pid_file" ]]; then
                    local pid
                    pid=$(cat "$pid_file" 2>/dev/null)
                    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                        # Job finished
                        _pool_cleanup_finished "$name"
                        if [[ ! -f "$job_dir/reported" ]]; then
                            touch "$job_dir/reported"
                            printf '%s\n' "$job_id"
                            return 0
                        fi
                    fi
                fi
            fi
        done

        # Check if any jobs are still pending or running
        local has_active=false
        for job_dir in "$pool_dir/jobs"/*; do
            [[ -d "$job_dir" ]] || continue
            status=$(cat "$job_dir/status" 2>/dev/null)
            if [[ "$status" == "$POOL_STATUS_PENDING" || "$status" == "$POOL_STATUS_RUNNING" ]]; then
                has_active=true
                break
            fi
            if [[ "$status" == "$POOL_STATUS_DONE" || "$status" == "$POOL_STATUS_FAILED" ]]; then
                if [[ ! -f "$job_dir/reported" ]]; then
                    has_active=true
                    break
                fi
            fi
        done

        if ! $has_active; then
            return 1
        fi

        _pool_wait_any
    done
}

# -----------------------------------------------------------------------------
# pool_barrier - Wait for all current jobs
# -----------------------------------------------------------------------------
# @description Block until all currently submitted jobs complete
# @param       $1 name - Pool name
# @return      0 if all succeeded, 1 if any failed
#
# Usage:
#   pool_barrier "downloads"
# -----------------------------------------------------------------------------
pool_barrier() {
    local name="$1"
    pool_wait "$name"
}

# =============================================================================
# RESULTS
# =============================================================================

# -----------------------------------------------------------------------------
# pool_result - Get job result (stdout)
# -----------------------------------------------------------------------------
# @description Retrieve stdout from completed job
# @param       $1 name - Pool name
# @param       $2 job_id - Job ID
# @stdout      Job stdout content
# @return      0 on success, 1 if job not found or still running
#
# Usage:
#   result=$(pool_result "downloads" "job_1")
# -----------------------------------------------------------------------------
pool_result() {
    local name="$1"
    local job_id="$2"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir job_dir
    pool_dir="$(_pool_dir "$name")"
    job_dir="$pool_dir/jobs/$job_id"

    if [[ ! -d "$job_dir" ]]; then
        _pool_log "error" "Job not found: $job_id"
        return 1
    fi

    local status
    status=$(cat "$job_dir/status" 2>/dev/null)

    if [[ "$status" != "$POOL_STATUS_DONE" && "$status" != "$POOL_STATUS_FAILED" ]]; then
        _pool_log "error" "Job still running: $job_id"
        return 1
    fi

    cat "$job_dir/stdout" 2>/dev/null
    return 0
}

# -----------------------------------------------------------------------------
# pool_status - Get job status
# -----------------------------------------------------------------------------
# @description Get current status of a job
# @param       $1 name - Pool name
# @param       $2 job_id - Job ID
# @stdout      Status: pending, running, done, failed
# @return      0 on success, 1 if job not found
#
# Usage:
#   status=$(pool_status "downloads" "job_1")
# -----------------------------------------------------------------------------
pool_status() {
    local name="$1"
    local job_id="$2"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir job_dir
    pool_dir="$(_pool_dir "$name")"
    job_dir="$pool_dir/jobs/$job_id"

    if [[ ! -d "$job_dir" ]]; then
        _pool_log "error" "Job not found: $job_id"
        return 1
    fi

    # Check if process is still running but status not updated
    _pool_cleanup_finished "$name"

    cat "$job_dir/status" 2>/dev/null
    return 0
}

# -----------------------------------------------------------------------------
# pool_results - Get all completed results as JSON
# -----------------------------------------------------------------------------
# @description Retrieve all job results as JSON array
# @param       $1 name - Pool name
# @stdout      JSON array of results
# @return      0 on success, 1 on error
#
# Usage:
#   results=$(pool_results "downloads")
# -----------------------------------------------------------------------------
pool_results() {
    local name="$1"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    # Clean up finished jobs first
    _pool_cleanup_finished "$name"

    local first=true
    printf '['

    local job_dir job_id status exit_code stdout
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        job_id="${job_dir##*/}"
        status=$(cat "$job_dir/status" 2>/dev/null)
        exit_code=$(cat "$job_dir/exit_code" 2>/dev/null || echo "null")

        $first || printf ','
        first=false

        # Escape stdout for JSON
        if [[ -f "$job_dir/stdout" ]]; then
            stdout=$(_pool_escape_json "$(cat "$job_dir/stdout" 2>/dev/null)")
        else
            stdout=""
        fi

        printf '{"id":"%s","status":"%s","exit_code":%s,"result":"%s"}' \
            "$job_id" "$status" "${exit_code:-null}" "$stdout"
    done

    printf ']'
    return 0
}

# =============================================================================
# RATE LIMITING
# =============================================================================

# -----------------------------------------------------------------------------
# pool_rate_limit - Set max jobs per second
# -----------------------------------------------------------------------------
# @description Limit job submission rate
# @param       $1 name - Pool name
# @param       $2 rate - Max jobs per second (0 = unlimited)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_rate_limit "api_calls" 10  # Max 10 jobs/second
# -----------------------------------------------------------------------------
pool_rate_limit() {
    local name="$1"
    local rate="$2"

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    if [[ ! "$rate" =~ ^[0-9]+$ ]]; then
        _pool_log "error" "Invalid rate: $rate"
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"
    printf '%d\n' "$rate" > "$pool_dir/rate_limit"

    _pool_log "info" "Set rate limit for '$name' to $rate jobs/second"
    return 0
}

# -----------------------------------------------------------------------------
# pool_semaphore - Set concurrent operation limit
# -----------------------------------------------------------------------------
# @description Limit concurrent operations (independent of workers)
# @param       $1 name - Pool name
# @param       $2 count - Max concurrent operations (0 = unlimited)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_semaphore "db_connections" 5  # Max 5 concurrent DB ops
# -----------------------------------------------------------------------------
pool_semaphore() {
    local name="$1"
    local count="$2"

    if ! _pool_exists "$name"; then
        _pool_log "error" "Pool does not exist: $name"
        return 1
    fi

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        _pool_log "error" "Invalid count: $count"
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"
    printf '%d\n' "$count" > "$pool_dir/semaphore"
    printf '0\n' > "$pool_dir/semaphore_count"

    _pool_log "info" "Set semaphore for '$name' to $count"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# pool_info - Get pool information as JSON
# -----------------------------------------------------------------------------
# @description Get pool configuration and status
# @param       $1 name - Pool name
# @stdout      JSON object with pool info
# @return      0 on success, 1 on error
#
# Usage:
#   info=$(pool_info "downloads")
# -----------------------------------------------------------------------------
pool_info() {
    local name="$1"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    local max_workers running pending completed failed
    max_workers=$(cat "$pool_dir/max_workers" 2>/dev/null || echo 0)
    running=$(_pool_running_count "$name")

    pending=0
    completed=0
    failed=0

    local job_dir status
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        status=$(cat "$job_dir/status" 2>/dev/null)
        case "$status" in
            "$POOL_STATUS_PENDING") ((pending++)) ;;
            "$POOL_STATUS_DONE") ((completed++)) ;;
            "$POOL_STATUS_FAILED") ((failed++)) ;;
        esac
    done

    local rate_limit semaphore
    rate_limit=$(cat "$pool_dir/rate_limit" 2>/dev/null || echo 0)
    semaphore=$(cat "$pool_dir/semaphore" 2>/dev/null || echo 0)

    printf '{"name":"%s","max_workers":%d,"running":%d,"pending":%d,"done":%d,"failed":%d,"rate_limit":%d,"semaphore":%d}' \
        "$name" "$max_workers" "$running" "$pending" "$completed" "$failed" "$rate_limit" "$semaphore"

    return 0
}

# -----------------------------------------------------------------------------
# pool_list_jobs - List all jobs in pool
# -----------------------------------------------------------------------------
# @description Get list of all job IDs
# @param       $1 name - Pool name
# @stdout      Job IDs (one per line)
# @return      0 on success, 1 on error
#
# Usage:
#   pool_list_jobs "downloads"
# -----------------------------------------------------------------------------
pool_list_jobs() {
    local name="$1"

    if ! _pool_exists "$name"; then
        return 1
    fi

    local pool_dir
    pool_dir="$(_pool_dir "$name")"

    local job_dir
    for job_dir in "$pool_dir/jobs"/*; do
        [[ -d "$job_dir" ]] || continue
        printf '%s\n' "${job_dir##*/}"
    done

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# shellcheck disable=SC2034  # Used by MAINFRAME lazy loading system
MAINFRAME_WORKPOOL_EXPORTS=(
    # Pool management
    pool_create
    pool_destroy
    pool_resize

    # Job submission
    pool_submit
    pool_submit_batch
    pool_map

    # Synchronization
    pool_wait
    pool_wait_any
    pool_barrier

    # Results
    pool_result
    pool_status
    pool_results

    # Rate limiting
    pool_rate_limit
    pool_semaphore

    # Utility
    pool_info
    pool_list_jobs
)

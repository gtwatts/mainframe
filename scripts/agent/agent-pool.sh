#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/agent/agent-pool.sh - Agent Worker Pool Manager
# =============================================================================
# Description: Manages a pool of background worker processes. Distributes tasks
#              across workers with configurable concurrency, retry logic, and
#              result collection. Supports FIFO-based task queuing.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
POOL_SIZE=4
TASK_QUEUE="/tmp/agent-pool-$$/queue"
RESULT_DIR="/tmp/agent-pool-$$/results"
MAX_RETRIES=2
TIMEOUT=60
WORKER_CMD=""
VERBOSE=false

# State
declare -A WORKER_PIDS
declare -A WORKER_STATUS
TASKS_TOTAL=0
TASKS_DONE=0
TASKS_FAILED=0

usage() {
    cat <<EOF
Usage: agent-pool.sh [options] --cmd <command> [task-file]

Manage a pool of worker processes for parallel task execution.

Task File Format (one task per line):
    Each line is passed as argument to the worker command.

Options:
    -w, --workers <n>      Pool size (default: 4)
    -c, --cmd <command>    Worker command (receives task as \$1)
    -r, --retries <n>      Max retries per task (default: 2)
    -t, --timeout <sec>    Per-task timeout (default: 60)
    --result-dir <path>    Results directory
    -v, --verbose          Verbose output
    -h, --help             Show this help

Examples:
    echo -e "url1\\nurl2\\nurl3" | agent-pool.sh -w 3 -c "curl -sO"
    agent-pool.sh -w 8 -c "./process.sh" tasks.txt
EOF
    exit 0
}

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--workers)    POOL_SIZE="$2"; shift 2 ;;
            -c|--cmd)        WORKER_CMD="$2"; shift 2 ;;
            -r|--retries)    MAX_RETRIES="$2"; shift 2 ;;
            -t|--timeout)    TIMEOUT="$2"; shift 2 ;;
            --result-dir)    RESULT_DIR="$2"; shift 2 ;;
            -v|--verbose)    VERBOSE=true; shift ;;
            -h|--help)       usage ;;
            -*)              log_error "Unknown option: $1"; usage ;;
            *)               positional+=("$1"); shift ;;
        esac
    done

    TASK_FILE="${positional[0]:-}"
}

# Initialize pool directories
init_pool() {
    mkdir -p "$(dirname "$TASK_QUEUE")"
    mkdir -p "$RESULT_DIR"
    mkfifo "$TASK_QUEUE" 2>/dev/null || true
}

# Run a single task with timeout and retries
run_task() {
    local task="$1"
    local task_id="$2"
    local attempt=0
    local success=false

    while [[ $attempt -le $MAX_RETRIES ]]; do
        ((attempt++))
        [[ "$VERBOSE" == true ]] && log_info "Worker $$: task $task_id attempt $attempt"

        local output_file="${RESULT_DIR}/${task_id}.out"
        local error_file="${RESULT_DIR}/${task_id}.err"

        if timeout "$TIMEOUT" bash -c "$WORKER_CMD \"\$1\"" -- "$task" \
            >"$output_file" 2>"$error_file"; then
            success=true
            break
        fi

        [[ $attempt -le $MAX_RETRIES ]] && sleep $((attempt * 2))
    done

    if [[ "$success" == true ]]; then
        echo "PASS $task_id" >> "${RESULT_DIR}/_status"
    else
        echo "FAIL $task_id $task" >> "${RESULT_DIR}/_status"
    fi
}

# Spawn worker processes
spawn_workers() {
    local tasks=()

    # Read tasks from file or stdin
    if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            tasks+=("$line")
        done < "$TASK_FILE"
    elif [[ ! -t 0 ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            tasks+=("$line")
        done
    else
        log_error "No tasks provided (use file argument or pipe)"
        exit 1
    fi

    TASKS_TOTAL=${#tasks[@]}
    log_info "Pool: $POOL_SIZE workers | Tasks: $TASKS_TOTAL | Retries: $MAX_RETRIES"

    # Initialize status file
    : > "${RESULT_DIR}/_status"

    # Distribute tasks across workers using round-robin
    local active_pids=()
    local task_idx=0

    while [[ $task_idx -lt $TASKS_TOTAL ]]; do
        # Wait if pool is full
        while [[ ${#active_pids[@]} -ge $POOL_SIZE ]]; do
            local new_pids=()
            for pid in "${active_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            active_pids=("${new_pids[@]}")
            [[ ${#active_pids[@]} -ge $POOL_SIZE ]] && sleep 0.1
        done

        # Launch task
        local task="${tasks[$task_idx]}"
        run_task "$task" "$task_idx" &
        active_pids+=($!)
        ((task_idx++))

        # Progress
        if [[ $((task_idx % 10)) -eq 0 || $task_idx -eq $TASKS_TOTAL ]]; then
            log_info "Dispatched: $task_idx / $TASKS_TOTAL"
        fi
    done

    # Wait for all workers to finish
    log_info "Waiting for workers to complete..."
    for pid in "${active_pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
}

# Collect and report results
report_results() {
    local status_file="${RESULT_DIR}/_status"
    [[ ! -f "$status_file" ]] && return

    TASKS_DONE=$(grep -c "^PASS" "$status_file" 2>/dev/null || echo 0)
    TASKS_FAILED=$(grep -c "^FAIL" "$status_file" 2>/dev/null || echo 0)

    echo ""
    log_info "=== Pool Results ==="
    log_info "Total:  $TASKS_TOTAL"
    log_info "Passed: $TASKS_DONE"
    log_info "Failed: $TASKS_FAILED"

    if [[ $TASKS_FAILED -gt 0 ]]; then
        echo ""
        log_warn "Failed tasks:"
        grep "^FAIL" "$status_file" | while IFS= read -r line; do
            local id task
            id=$(echo "$line" | awk '{print $2}')
            task=$(echo "$line" | cut -d' ' -f3-)
            echo "  [$id] $task"
            if [[ "$VERBOSE" == true && -f "${RESULT_DIR}/${id}.err" ]]; then
                echo "       $(head -1 "${RESULT_DIR}/${id}.err")"
            fi
        done
    fi

    log_info "Results: $RESULT_DIR"
}

# shellcheck disable=SC2329
cleanup() {
    # Kill remaining workers
    for pid in "${!WORKER_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    rm -f "$TASK_QUEUE"
    log_info "Pool terminated"
    exit 1
}

main() {
    parse_args "$@"

    if [[ -z "$WORKER_CMD" ]]; then
        log_error "Worker command required (--cmd)"
        usage
    fi

    trap cleanup INT TERM

    init_pool
    spawn_workers
    report_results

    [[ $TASKS_FAILED -gt 0 ]] && exit 1
    exit 0
}

main "$@"

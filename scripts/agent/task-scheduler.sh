#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/agent/task-scheduler.sh - DAG Task Scheduler
# =============================================================================
# Description: Executes tasks with dependency ordering (DAG). Supports parallel
#              execution of independent tasks, failure propagation, and retry.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
SCHEDULE_FILE=""
MAX_PARALLEL=4
MAX_RETRIES=1
VERBOSE=false
DRY_RUN=false

# State
declare -A TASK_CMDS
declare -A TASK_DEPS
declare -A TASK_STATUS  # pending|running|done|failed|skipped
declare -A TASK_PIDS
TASK_ORDER=()

usage() {
    cat <<EOF
Usage: task-scheduler.sh [options] <schedule-file>

Execute tasks with dependency ordering (DAG).

Schedule File Format:
    task_name: command to execute
    task_name [dep1, dep2]: command to execute

Example:
    build: make build
    test [build]: make test
    lint: make lint
    deploy [test, lint]: make deploy

Options:
    -j, --parallel <n>   Max parallel tasks (default: 4)
    -r, --retries <n>    Max retries (default: 1)
    -n, --dry-run        Show execution order without running
    -v, --verbose        Verbose output
    -h, --help           Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--parallel) MAX_PARALLEL="$2"; shift 2 ;;
            -r|--retries)  MAX_RETRIES="$2"; shift 2 ;;
            -n|--dry-run)  DRY_RUN=true; shift ;;
            -v|--verbose)  VERBOSE=true; shift ;;
            -h|--help)     usage ;;
            -*)            log_error "Unknown option: $1"; usage ;;
            *)             SCHEDULE_FILE="$1"; shift ;;
        esac
    done
}

# Parse schedule file
parse_schedule() {
    local file="$1"

    while IFS= read -r line; do
        # Skip comments and blanks
        [[ -z "$line" || "$line" == \#* ]] && continue

        local task_name="" deps="" cmd=""

        # Parse: name [dep1, dep2]: command
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*(\[([^\]]*)\])?[[:space:]]*:[[:space:]]*(.+)$ ]]; then
            task_name="${BASH_REMATCH[1]}"
            deps="${BASH_REMATCH[3]}"
            cmd="${BASH_REMATCH[4]}"
        else
            log_warn "Skipping malformed line: $line"
            continue
        fi

        TASK_CMDS["$task_name"]="$cmd"
        TASK_STATUS["$task_name"]="pending"

        # Parse dependencies
        if [[ -n "$deps" ]]; then
            # Remove spaces and split by comma
            deps="${deps// /}"
            TASK_DEPS["$task_name"]="$deps"
        else
            TASK_DEPS["$task_name"]=""
        fi

        TASK_ORDER+=("$task_name")
    done < "$file"
}

# Check if all dependencies are satisfied
deps_satisfied() {
    local task="$1"
    local deps="${TASK_DEPS[$task]}"

    [[ -z "$deps" ]] && return 0

    IFS=',' read -ra dep_list <<< "$deps"
    for dep in "${dep_list[@]}"; do
        local status="${TASK_STATUS[$dep]:-unknown}"
        case "$status" in
            done)    continue ;;
            failed)  return 2 ;;  # Dependency failed
            unknown) log_error "Unknown dependency: $dep"; return 2 ;;
            *)       return 1 ;;  # Not yet done
        esac
    done

    return 0
}

# Run a single task
run_task() {
    local task="$1"
    local cmd="${TASK_CMDS[$task]}"
    local attempt=0
    local success=false

    TASK_STATUS["$task"]="running"
    log_info "Running: $task"
    [[ "$VERBOSE" == true ]] && log_info "  Command: $cmd"

    while [[ $attempt -le $MAX_RETRIES ]]; do
        ((attempt++))

        if bash -c "$cmd" >/tmp/task-sched-$$-"$task".out 2>&1; then
            success=true
            break
        fi

        if [[ $attempt -le $MAX_RETRIES ]]; then
            log_warn "  Retrying $task (attempt $((attempt + 1)))"
            sleep 1
        fi
    done

    if [[ "$success" == true ]]; then
        TASK_STATUS["$task"]="done"
        log_info "  Done: $task"
    else
        TASK_STATUS["$task"]="failed"
        log_error "  Failed: $task"
        if [[ "$VERBOSE" == true ]]; then
            head -5 /tmp/task-sched-$$-"$task".out 2>/dev/null | sed 's/^/    /'
        fi
    fi

    rm -f /tmp/task-sched-$$-"$task".out
}

# Skip task and all dependents
skip_dependents() {
    local failed_task="$1"

    for task in "${TASK_ORDER[@]}"; do
        [[ "${TASK_STATUS[$task]}" != "pending" ]] && continue

        local deps="${TASK_DEPS[$task]}"
        if [[ "$deps" == *"$failed_task"* ]]; then
            TASK_STATUS["$task"]="skipped"
            log_warn "  Skipped: $task (depends on failed: $failed_task)"
            skip_dependents "$task"
        fi
    done
}

# Execute the DAG
execute_dag() {
    local all_done=false

    while [[ "$all_done" == false ]]; do
        all_done=true
        local launched=0
        local active_count=0

        # Count active tasks
        for task in "${TASK_ORDER[@]}"; do
            [[ "${TASK_STATUS[$task]}" == "running" ]] && ((active_count++))
        done

        for task in "${TASK_ORDER[@]}"; do
            local status="${TASK_STATUS[$task]}"

            [[ "$status" != "pending" ]] && continue
            all_done=false

            # Check if we can run more
            [[ $active_count -ge $MAX_PARALLEL ]] && break

            # Check dependencies
            deps_satisfied "$task"
            local dep_status=$?

            if [[ $dep_status -eq 0 ]]; then
                # Dependencies met - run task
                if [[ "$DRY_RUN" == true ]]; then
                    TASK_STATUS["$task"]="done"
                    echo "  Would run: $task -> ${TASK_CMDS[$task]}"
                else
                    run_task "$task"
                    ((launched++))
                    ((active_count++))

                    # If failed, skip dependents
                    if [[ "${TASK_STATUS[$task]}" == "failed" ]]; then
                        skip_dependents "$task"
                    fi
                fi
            elif [[ $dep_status -eq 2 ]]; then
                # Dependency failed
                TASK_STATUS["$task"]="skipped"
                log_warn "  Skipped: $task (dependency failed)"
            fi
        done

        # Check if anything is still pending
        local pending=0
        for task in "${TASK_ORDER[@]}"; do
            [[ "${TASK_STATUS[$task]}" == "pending" ]] && pending=1
        done
        [[ $pending -eq 0 ]] && all_done=true

        # Small sleep to prevent busy-waiting
        [[ "$all_done" == false && $launched -eq 0 ]] && sleep 0.1
    done
}

main() {
    parse_args "$@"

    if [[ -z "$SCHEDULE_FILE" ]]; then
        log_error "Schedule file required"
        usage
    fi

    if [[ ! -f "$SCHEDULE_FILE" ]]; then
        log_error "File not found: $SCHEDULE_FILE"
        exit 1
    fi

    parse_schedule "$SCHEDULE_FILE"

    local task_count=${#TASK_ORDER[@]}
    log_info "Task Scheduler: $task_count tasks, max parallel: $MAX_PARALLEL"
    [[ "$DRY_RUN" == true ]] && log_warn "DRY RUN MODE"
    echo ""

    execute_dag

    # Summary
    echo ""
    local done_count=0 failed_count=0 skipped_count=0
    for task in "${TASK_ORDER[@]}"; do
        case "${TASK_STATUS[$task]}" in
            done)    ((done_count++)) ;;
            failed)  ((failed_count++)) ;;
            skipped) ((skipped_count++)) ;;
        esac
    done

    log_info "=== Schedule Complete ==="
    log_info "Done:    $done_count"
    [[ $failed_count -gt 0 ]] && log_error "Failed:  $failed_count"
    [[ $skipped_count -gt 0 ]] && log_warn "Skipped: $skipped_count"

    [[ $failed_count -gt 0 ]] && exit 1
    exit 0
}

main "$@"

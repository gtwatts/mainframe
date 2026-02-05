#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/graph.sh - Graph-based Workflow Execution Engine
# =============================================================================
# Description: Dependency graph construction and execution with parallelization.
#              Provides topological sort (Kahn's algorithm), cycle detection,
#              visual flowcharts, and rollback capabilities.
#
# Dependencies: parallel_v2.sh (for parallel execution)
#
# Version: 1.0.0
# Requires: Bash 4.3+ (for namerefs and associative arrays)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GRAPH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GRAPH_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Auto-source dependencies if not loaded
if [[ -z "${_MAINFRAME_PARALLEL_V2_LOADED:-}" ]]; then
    _graph_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_graph_lib_dir}/parallel_v2.sh" ]]; then
        source "${_graph_lib_dir}/parallel_v2.sh"
    fi
fi

if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    _graph_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_graph_lib_dir}/json.sh" ]]; then
        source "${_graph_lib_dir}/json.sh"
    fi
fi

if [[ -z "${_MAINFRAME_ANSI_LOADED:-}" ]]; then
    _graph_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_graph_lib_dir}/ansi.sh" ]]; then
        source "${_graph_lib_dir}/ansi.sh"
    fi
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default parallelism limit
GRAPH_DEFAULT_PARALLEL="${GRAPH_DEFAULT_PARALLEL:-4}"

# State directory for workflow state files
GRAPH_STATE_DIR="${GRAPH_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_graph}"

# Continue on failure flag
GRAPH_CONTINUE_ON_FAIL="${GRAPH_CONTINUE_ON_FAIL:-false}"

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Workflow definitions (associative arrays keyed by "wf_name")
declare -gA _GRAPH_TASKS=()           # wf:task -> command
declare -gA _GRAPH_DEPS=()            # wf:task -> "dep1 dep2 ..."
declare -gA _GRAPH_STATUS=()          # wf:task -> pending|running|completed|failed|rolled_back
declare -gA _GRAPH_START_TIME=()      # wf:task -> epoch_ms
declare -gA _GRAPH_END_TIME=()        # wf:task -> epoch_ms
declare -gA _GRAPH_OUTPUT=()          # wf:task -> output
declare -gA _GRAPH_ERROR=()           # wf:task -> error message
declare -gA _GRAPH_ROLLBACK_CMD=()    # wf:task -> rollback command
declare -gA _GRAPH_WORKFLOWS=()       # wf_name -> 1 (exists)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current time in milliseconds
_graph_now_ms() {
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

# Log helper
_graph_log() {
    local level="$1"
    shift
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[graph] %s: %s\n' "$level" "$*" >&2
    fi
}

# Check if a workflow exists
_graph_wf_exists() {
    [[ -n "${_GRAPH_WORKFLOWS[$1]:-}" ]]
}

# Build key from workflow and task name
_graph_key() {
    printf '%s:%s' "$1" "$2"
}

# Get list of tasks for a workflow
_graph_get_tasks() {
    local wf="$1"
    local key
    for key in "${!_GRAPH_TASKS[@]}"; do
        if [[ "$key" == "$wf:"* ]]; then
            printf '%s\n' "${key#*:}"
        fi
    done
}

# Get dependencies for a task
_graph_get_deps() {
    local wf="$1"
    local task="$2"
    local key
    key=$(_graph_key "$wf" "$task")
    printf '%s' "${_GRAPH_DEPS[$key]:-}"
}

# Check if all dependencies are satisfied
_graph_deps_satisfied() {
    local wf="$1"
    local task="$2"
    local deps
    deps=$(_graph_get_deps "$wf" "$task")
    
    [[ -z "$deps" ]] && return 0
    
    local dep
    for dep in $deps; do
        local dep_key
        dep_key=$(_graph_key "$wf" "$dep")
        local status="${_GRAPH_STATUS[$dep_key]:-pending}"
        if [[ "$status" != "completed" ]]; then
            return 1
        fi
    done
    
    return 0
}

# Get tasks ready to run (all deps satisfied, still pending)
_graph_get_ready() {
    local wf="$1"
    local task
    for task in $(_graph_get_tasks "$wf"); do
        local key
        key=$(_graph_key "$wf" "$task")
        local status="${_GRAPH_STATUS[$key]:-pending}"
        if [[ "$status" == "pending" ]] && _graph_deps_satisfied "$wf" "$task"; then
            printf '%s\n' "$task"
        fi
    done
}

# Topological sort using Kahn's algorithm
_graph_topo_sort() {
    local wf="$1"
    
    # Build in-degree map
    declare -A in_degree
    local task
    for task in $(_graph_get_tasks "$wf"); do
        local deps
        deps=$(_graph_get_deps "$wf" "$task")
        local deg=0
        local dep
        for dep in $deps; do
            ((deg++))
        done
        in_degree["$task"]=$deg
    done
    
    # Queue for tasks with no dependencies
    local -a queue=()
    for task in $(_graph_get_tasks "$wf"); do
        if [[ ${in_degree[$task]:-0} -eq 0 ]]; then
            queue+=("$task")
        fi
    done
    
    # Process queue
    local -a result=()
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        result+=("$current")
        
        # Find tasks that depend on current
        local other
        for other in $(_graph_get_tasks "$wf"); do
            local deps
            deps=$(_graph_get_deps "$wf" "$other")
            if [[ " $deps " == *" $current "* ]]; then
                ((in_degree[$other]--))
                if [[ ${in_degree[$other]} -eq 0 ]]; then
                    queue+=("$other")
                fi
            fi
        done
    done
    
    # Check if all tasks were processed (no cycle)
    local total_tasks
    total_tasks=$(_graph_get_tasks "$wf" | wc -l)
    if [[ ${#result[@]} -ne $total_tasks ]]; then
        return 1  # Cycle detected
    fi
    
    printf '%s\n' "${result[@]}"
}

# Detect cycle in workflow
_graph_detect_cycle() {
    local wf="$1"
    ! _graph_topo_sort "$wf" >/dev/null 2>&1
}

# =============================================================================
# VISUALIZATION
# =============================================================================

# Get display width of a string (approximate)
_graph_display_width() {
    local str="$1"
    # Remove ANSI escape sequences
    str=$(printf '%s' "$str" | sed 's/\x1b\[[0-9;]*m//g')
    printf '%d' "${#str}"
}

# Build ASCII flowchart for workflow
_graph_build_flowchart() {
    local wf="$1"
    
    # Collect all tasks and their levels (topological depth)
    declare -A levels
    declare -A is_depended_by
    
    local task
    for task in $(_graph_get_tasks "$wf"); do
        levels["$task"]=0
        # Find what depends on this task
        local other
        for other in $(_graph_get_tasks "$wf"); do
            local deps
            deps=$(_graph_get_deps "$wf" "$other")
            if [[ " $deps " == *" $task "* ]]; then
                is_depended_by["$task"]+="$other "
            fi
        done
    done
    
    # Calculate levels (topological depth)
    local sorted
    sorted=$(_graph_topo_sort "$wf" 2>/dev/null) || {
        printf 'Error: Cannot visualize workflow with cycle\n'
        return 1
    }
    
    local current_level=0
    local -a tasks_at_level=()
    while IFS= read -r task; do
        local max_dep_level=-1
        local deps
        deps=$(_graph_get_deps "$wf" "$task")
        local dep
        for dep in $deps; do
            local dep_level=${levels[$dep]:-0}
            if [[ $dep_level -gt $max_dep_level ]]; then
                max_dep_level=$dep_level
            fi
        done
        levels["$task"]=$((max_dep_level + 1))
    done <<< "$sorted"
    
    # Find max level
    local max_level=0
    for task in $(_graph_get_tasks "$wf"); do
        if [[ ${levels[$task]:-0} -gt $max_level ]]; then
            max_level=${levels[$task]}
        fi
    done
    
    # Group tasks by level
    declare -a level_tasks
    for ((i=0; i<=max_level; i++)); do
        level_tasks[$i]=""
    done
    
    for task in $(_graph_get_tasks "$wf"); do
        local lvl=${levels[$task]:-0}
        level_tasks[$lvl]+="$task "
    done
    
    # Build visual representation
    printf '\n'
    printf '%bWorkflow: %s%b\n\n' "${CLR_BOLD}${CLR_CYAN}" "$wf" "$CLR_RESET"
    
    # Simple horizontal flowchart
    local first_level=true
    for ((lvl=0; lvl<=max_level; lvl++)); do
        local tasks="${level_tasks[$lvl]}"
        [[ -z "$tasks" ]] && continue
        
        if ! $first_level; then
            printf '\n'
            # Draw arrows from previous level
            local -a prev_tasks=(${level_tasks[$((lvl-1))]})
            local -a curr_tasks=($tasks)
            
            if [[ ${#curr_tasks[@]} -eq 1 && ${#prev_tasks[@]} -eq 1 ]]; then
                printf '      │\n'
                printf '      ▼\n'
            elif [[ ${#curr_tasks[@]} -eq 1 ]]; then
                # Multiple dependencies converging
                printf '      '
                for ((i=0; i<${#prev_tasks[@]}; i++)); do
                    if [[ $i -eq 0 ]]; then
                        printf '┌────┘ '
                    else
                        printf '└────┘ '
                    fi
                done
                printf '\n      ▼\n'
            else
                printf '      │\n'
                printf '      ▼\n'
            fi
        fi
        
        # Print tasks at this level
        local task_count=0
        for task in $tasks; do
            local key
            key=$(_graph_key "$wf" "$task")
            local status="${_GRAPH_STATUS[$key]:-pending}"
            local color="$CLR_RESET"
            local status_icon="○"
            
            case "$status" in
                pending)   color="$CLR_DIM"; status_icon="○" ;;
                running)   color="$CLR_YELLOW"; status_icon="◐" ;;
                completed) color="$CLR_GREEN"; status_icon="✓" ;;
                failed)    color="$CLR_RED"; status_icon="✗" ;;
                rolled_back) color="$CLR_MAGENTA"; status_icon="↺" ;;
            esac
            
            if [[ $task_count -gt 0 ]]; then
                printf '  '
            else
                printf '  '
            fi
            printf '%b[%s] %s%b' "$color" "$status_icon" "$task" "$CLR_RESET"
            ((task_count++))
        done
        printf '\n'
        
        first_level=false
    done
    
    printf '\n'
    
    # Legend
    printf '%bLegend:%b ○ pending  %b◐%b running  %b✓%b completed  %b✗%b failed  %b↺%b rolled_back\n' \
        "$CLR_DIM" "$CLR_RESET" "$CLR_YELLOW" "$CLR_RESET" "$CLR_GREEN" "$CLR_RESET" "$CLR_RED" "$CLR_RESET" "$CLR_MAGENTA" "$CLR_RESET"
    printf '\n'
}

# =============================================================================
# ROLLBACK
# =============================================================================

# Execute rollback for a single task
_graph_rollback_task() {
    local wf="$1"
    local task="$2"
    local key
    key=$(_graph_key "$wf" "$task")
    
    local rollback_cmd="${_GRAPH_ROLLBACK_CMD[$key]:-}"
    local current_status="${_GRAPH_STATUS[$key]:-pending}"
    
    # Only rollback if task was completed
    if [[ "$current_status" != "completed" ]]; then
        return 0
    fi
    
    _graph_log info "Rolling back task: $task"
    _GRAPH_STATUS[$key]="rolling_back"
    
    if [[ -n "$rollback_cmd" ]]; then
        if eval "$rollback_cmd" 2>/dev/null; then
            _GRAPH_STATUS[$key]="rolled_back"
            _graph_log info "Rolled back task: $task"
        else
            _GRAPH_STATUS[$key]="rollback_failed"
            _graph_log error "Failed to rollback task: $task"
            return 1
        fi
    else
        _GRAPH_STATUS[$key]="rolled_back"
        _graph_log info "No rollback command for task: $task"
    fi
    
    return 0
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: workflow_name is valid identifier
# @post: workflow is created in _GRAPH_WORKFLOWS
# @returns: 0 on success, 1 on invalid name
#
# Create a new workflow
#
# Usage: graph_define "workflow_name"
# Example: graph_define "deploy_pipeline"
graph_define() {
    local wf="$1"
    
    if [[ -z "$wf" ]]; then
        _graph_log error "Workflow name required"
        return 1
    fi
    
    if [[ ! "$wf" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        _graph_log error "Invalid workflow name: $wf (use alphanumeric, underscore, hyphen)"
        return 1
    fi
    
    _GRAPH_WORKFLOWS[$wf]=1
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":{"workflow":"%s","status":"defined"}}\n' "$(json_escape "$wf")"
    else
        _graph_log info "Defined workflow: $wf"
    fi
    
    return 0
}

# @pre: workflow exists, task_name is valid
# @post: task is added to workflow
# @returns: 0 on success, 1 on error
#
# Add a task to a workflow
#
# Usage: graph_add_task "wf" "name" "command" [--rollback "rollback_cmd"]
# Example: graph_add_task "deploy" "test" "npm test" --rollback "npm run clean"
graph_add_task() {
    local wf="$1"
    local task="$2"
    local cmd="$3"
    shift 3
    
    local rollback_cmd=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rollback)
                rollback_cmd="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if ! _graph_wf_exists "$wf"; then
        _graph_log error "Workflow not found: $wf"
        return 1
    fi
    
    if [[ -z "$task" ]]; then
        _graph_log error "Task name required"
        return 1
    fi
    
    if [[ -z "$cmd" ]]; then
        _graph_log error "Command required for task: $task"
        return 1
    fi
    
    local key
    key=$(_graph_key "$wf" "$task")
    
    _GRAPH_TASKS[$key]="$cmd"
    _GRAPH_STATUS[$key]="pending"
    
    if [[ -n "$rollback_cmd" ]]; then
        _GRAPH_ROLLBACK_CMD[$key]="$rollback_cmd"
    fi
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":{"workflow":"%s","task":"%s","status":"added"}}\n' \
            "$(json_escape "$wf")" "$(json_escape "$task")"
    else
        _graph_log info "Added task '$task' to workflow '$wf'"
    fi
    
    return 0
}

# @pre: workflow exists, both tasks exist
# @post: dependency edge is added
# @returns: 0 on success, 1 on error
#
# Add a dependency edge between tasks
#
# Usage: graph_add_dep "wf" "task" "dependency"
# Example: graph_add_dep "deploy" "build" "test"
graph_add_dep() {
    local wf="$1"
    local task="$2"
    local dep="$3"
    
    if ! _graph_wf_exists "$wf"; then
        _graph_log error "Workflow not found: $wf"
        return 1
    fi
    
    local task_key
    task_key=$(_graph_key "$wf" "$task")
    local dep_key
    dep_key=$(_graph_key "$wf" "$dep")
    
    if [[ -z "${_GRAPH_TASKS[$task_key]:-}" ]]; then
        _graph_log error "Task not found: $task"
        return 1
    fi
    
    if [[ -z "${_GRAPH_TASKS[$dep_key]:-}" ]]; then
        _graph_log error "Dependency task not found: $dep"
        return 1
    fi
    
    # Check for self-dependency
    if [[ "$task" == "$dep" ]]; then
        _graph_log error "Task cannot depend on itself: $task"
        return 1
    fi
    
    # Add dependency
    local current_deps="${_GRAPH_DEPS[$task_key]:-}"
    if [[ -n "$current_deps" ]]; then
        # Check if already depends
        if [[ " $current_deps " != *" $dep "* ]]; then
            _GRAPH_DEPS[$task_key]="$current_deps $dep"
        fi
    else
        _GRAPH_DEPS[$task_key]="$dep"
    fi
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":{"workflow":"%s","task":"%s","depends_on":"%s"}}\n' \
            "$(json_escape "$wf")" "$(json_escape "$task")" "$(json_escape "$dep")"
    else
        _graph_log info "Added dependency: $task -> $dep"
    fi
    
    return 0
}

# @pre: workflow exists
# @post: ASCII visualization is printed
# @returns: 0 on success, 1 on error
#
# Visualize workflow as ASCII flowchart
#
# Usage: graph_visualize "wf"
# Example: graph_visualize "deploy"
graph_visualize() {
    local wf="$1"
    
    if ! _graph_wf_exists "$wf"; then
        _graph_log error "Workflow not found: $wf"
        return 1
    fi
    
    _graph_build_flowchart "$wf"
    return 0
}

# @pre: workflow exists
# @post: status JSON/object is output
# @returns: 0 on success, 1 on error
#
# Get execution status of workflow
#
# Usage: graph_status "wf"
# Example: status=$(graph_status "deploy")
graph_status() {
    local wf="$1"
    
    if ! _graph_wf_exists "$wf"; then
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_WF_NOT_FOUND","msg":"Workflow not found"}}\n'
        else
            _graph_log error "Workflow not found: $wf"
        fi
        return 1
    fi
    
    local total=0
    local pending=0
    local running=0
    local completed=0
    local failed=0
    local rolled_back=0
    
    local task
    for task in $(_graph_get_tasks "$wf"); do
        local key
        key=$(_graph_key "$wf" "$task")
        local status="${_GRAPH_STATUS[$key]:-pending}"
        
        ((total++))
        case "$status" in
            pending)     ((pending++)) ;;
            running)     ((running++)) ;;
            completed)   ((completed++)) ;;
            failed)      ((failed++)) ;;
            rolled_back) ((rolled_back++)) ;;
        esac
    done
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":true,"data":{"workflow":"%s","total":%d,"pending":%d,"running":%d,"completed":%d,"failed":%d,"rolled_back":%d}}\n' \
            "$(json_escape "$wf")" "$total" "$pending" "$running" "$completed" "$failed" "$rolled_back"
    else
        printf 'Workflow: %s\n' "$wf"
        printf '  Total: %d\n' "$total"
        printf '  Pending: %d\n' "$pending"
        printf '  Running: %d\n' "$running"
        printf '  Completed: %d\n' "$completed"
        printf '  Failed: %d\n' "$failed"
        printf '  Rolled back: %d\n' "$rolled_back"
    fi
    
    return 0
}

# @pre: workflow exists with failed/completed tasks
# @post: rollback commands executed in reverse topological order
# @returns: 0 on success, 1 if rollback fails
#
# Rollback failed workflow
#
# Usage: graph_rollback "wf"
# Example: graph_rollback "deploy"
graph_rollback() {
    local wf="$1"
    
    if ! _graph_wf_exists "$wf"; then
        _graph_log error "Workflow not found: $wf"
        return 1
    fi
    
    _graph_log info "Starting rollback for workflow: $wf"
    
    # Get tasks in reverse topological order
    local sorted
    sorted=$(_graph_topo_sort "$wf" 2>/dev/null | tac) || {
        _graph_log error "Cannot rollback workflow with cycle"
        return 1
    }
    
    local failed=0
    local task
    while IFS= read -r task; do
        if ! _graph_rollback_task "$wf" "$task"; then
            ((failed++))
        fi
    done <<< "$sorted"
    
    if [[ $failed -gt 0 ]]; then
        _graph_log error "Rollback completed with $failed failures"
        return 1
    else
        _graph_log info "Rollback completed successfully"
    fi
    
    return 0
}

# @pre: workflow exists with tasks defined
# @post: tasks executed respecting dependencies and parallelism
# @returns: 0 on success, 1 on failure
#
# Execute workflow with auto-parallelization
#
# Usage: graph_execute "wf" [--parallel N] [--continue-on-fail]
# Example: graph_execute "deploy" --parallel 4
graph_execute() {
    local wf="$1"
    shift
    
    local parallel_limit="$GRAPH_DEFAULT_PARALLEL"
    local continue_on_fail=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parallel)
                parallel_limit="$2"
                shift 2
                ;;
            --continue-on-fail)
                continue_on_fail=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if ! _graph_wf_exists "$wf"; then
        _graph_log error "Workflow not found: $wf"
        return 1
    fi
    
    # Check for cycles
    if _graph_detect_cycle "$wf"; then
        _graph_log error "Cycle detected in workflow: $wf"
        if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CYCLE_DETECTED","msg":"Cycle detected in workflow"}}\n'
        fi
        return 1
    fi
    
    local total_tasks
    total_tasks=$(_graph_get_tasks "$wf" | wc -l)
    
    if [[ $total_tasks -eq 0 ]]; then
        _graph_log warn "No tasks in workflow: $wf"
        return 0
    fi
    
    _graph_log info "Executing workflow: $wf ($total_tasks tasks, parallelism=$parallel_limit)"

    # Create state directory
    mkdir -p "$GRAPH_STATE_DIR"

    # Track temp files for cleanup on signals
    declare -a _graph_exec_tmpfiles=()
    _graph_cleanup_tmpfiles() {
        local f
        for f in "${_graph_exec_tmpfiles[@]}"; do
            rm -f "$f" 2>/dev/null || true
        done
    }
    trap '_graph_cleanup_tmpfiles' EXIT INT TERM

    local start_ms
    start_ms=$(_graph_now_ms)

    # Track running jobs
    declare -A running_pids
    declare -A pid_to_task
    local completed=0
    local failed=0
    
    # Main execution loop
    while [[ $completed -lt $total_tasks ]]; do
        # Check for failed tasks (stop if not continuing)
        if [[ $failed -gt 0 ]] && ! $continue_on_fail; then
            _graph_log error "Stopping due to task failure (use --continue-on-fail to override)"
            # Kill running tasks
            local pid
            for pid in "${!running_pids[@]}"; do
                kill "$pid" 2>/dev/null || true
            done
            break
        fi
        
        # Start ready tasks up to parallel limit
        while [[ ${#running_pids[@]} -lt $parallel_limit ]]; do
            local ready_task
            ready_task=$(_graph_get_ready "$wf" | head -1)
            
            [[ -z "$ready_task" ]] && break
            
            local key
            key=$(_graph_key "$wf" "$ready_task")
            local cmd="${_GRAPH_TASKS[$key]}"
            
            _GRAPH_STATUS[$key]="running"
            _GRAPH_START_TIME[$key]=$(_graph_now_ms)
            
            # Create temp file for output
            local tmpfile
            tmpfile=$(mktemp "$GRAPH_STATE_DIR/${wf}_${ready_task}_XXXXXX")
            _graph_exec_tmpfiles+=("$tmpfile")

            # Validate command is non-empty before execution
            # Note: Commands are registered via graph_add_task() by the caller.
            # This eval is within a trust boundary -- only library users can
            # register tasks. External/untrusted input must be sanitized before
            # passing to graph_add_task().
            if [[ -z "${cmd:-}" ]]; then
                _graph_log error "Empty command for task: $ready_task"
                _GRAPH_STATUS[$key]="failed"
                _GRAPH_ERROR[$key]="Empty command"
                ((failed++))
                continue
            fi

            # Execute in background
            (
                local output
                local status
                output=$(eval "$cmd" 2>&1)
                status=$?
                printf '%d\n%s' "$status" "$output" > "$tmpfile"
            ) &
            
            local pid=$!
            running_pids[$pid]="$tmpfile"
            pid_to_task[$pid]="$ready_task"
            
            if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
                printf '[graph] %b→%b Running: %s\n' "$CLR_YELLOW" "$CLR_RESET" "$ready_task" >&2
            fi
        done
        
        # Check for completed tasks
        if [[ ${#running_pids[@]} -gt 0 ]]; then
            local -a completed_pids=()
            local pid
            for pid in "${!running_pids[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    completed_pids+=("$pid")
                fi
            done
            
            # Process completed tasks
            local cpid
            for cpid in "${completed_pids[@]}"; do
                local tmpfile="${running_pids[$cpid]}"
                local task="${pid_to_task[$cpid]}"
                local key
                key=$(_graph_key "$wf" "$task")
                
                wait "$cpid" 2>/dev/null || true
                
                # Read result
                local status output
                if [[ -f "$tmpfile" ]]; then
                    status=$(head -1 "$tmpfile")
                    output=$(tail -n +2 "$tmpfile")
                    rm -f "$tmpfile"
                else
                    status=1
                    output="Task output file not found"
                fi
                
                _GRAPH_END_TIME[$key]=$(_graph_now_ms)
                
                if [[ "$status" -eq 0 ]]; then
                    _GRAPH_STATUS[$key]="completed"
                    _GRAPH_OUTPUT[$key]="$output"
                    ((completed++))
                    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
                        printf '[graph] %b✓%b Completed: %s\n' "$CLR_GREEN" "$CLR_RESET" "$task" >&2
                    fi
                else
                    _GRAPH_STATUS[$key]="failed"
                    _GRAPH_ERROR[$key]="$output"
                    ((failed++))
                    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
                        printf '[graph] %b✗%b Failed: %s - %s\n' "$CLR_RED" "$CLR_RESET" "$task" "$output" >&2
                    fi
                fi
                
                unset "running_pids[$cpid]"
                unset "pid_to_task[$cpid]"
            done
        fi
        
        # Check for deadlock (no running, no ready, not done)
        if [[ ${#running_pids[@]} -eq 0 ]] && [[ $completed -lt $total_tasks ]]; then
            local ready_check
            ready_check=$(_graph_get_ready "$wf")
            if [[ -z "$ready_check" ]]; then
                _graph_log error "Deadlock detected - tasks with unsatisfied dependencies remain"
                break
            fi
        fi
        
        # Small delay to prevent CPU spinning
        if [[ ${#running_pids[@]} -gt 0 ]]; then
            sleep 0.1
        fi
    done
    
    local end_ms
    end_ms=$(_graph_now_ms)
    local duration=$((end_ms - start_ms))
    
    # Wait for any remaining tasks
    for pid in "${!running_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
        rm -f "${running_pids[$pid]}" 2>/dev/null || true
    done
    
    # Determine overall success
    local ok="true"
    if [[ $failed -gt 0 ]]; then
        ok="false"
    fi
    
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        printf '{"ok":%s,"data":{"workflow":"%s","completed":%d,"failed":%d,"duration_ms":%d}}\n' \
            "$ok" "$(json_escape "$wf")" "$completed" "$failed" "$duration"
    else
        printf '\n'
        printf '%bWorkflow Summary: %s%b\n' "$CLR_BOLD" "$wf" "$CLR_RESET"
        printf '  Duration: %d ms\n' "$duration"
        printf '  Completed: %d\n' "$completed"
        printf '  Failed: %d\n' "$failed"
        if [[ "$ok" == "true" ]]; then
            printf '%b[OK]%b Workflow completed successfully\n' "$CLR_GREEN$CLR_BOLD" "$CLR_RESET"
        else
            printf '%b[FAIL]%b Workflow completed with failures\n' "$CLR_RED$CLR_BOLD" "$CLR_RESET"
        fi
    fi
    
    # Clean up any remaining temp files and restore default trap
    _graph_cleanup_tmpfiles
    trap - EXIT INT TERM

    [[ "$ok" == "true" ]]
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Clear all data for a workflow
# Usage: graph_clear "wf"
graph_clear() {
    local wf="$1"
    
    if ! _graph_wf_exists "$wf"; then
        return 1
    fi
    
    local task
    for task in $(_graph_get_tasks "$wf"); do
        local key
        key=$(_graph_key "$wf" "$task")
        unset "_GRAPH_TASKS[$key]"
        unset "_GRAPH_DEPS[$key]"
        unset "_GRAPH_STATUS[$key]"
        unset "_GRAPH_START_TIME[$key]"
        unset "_GRAPH_END_TIME[$key]"
        unset "_GRAPH_OUTPUT[$key]"
        unset "_GRAPH_ERROR[$key]"
        unset "_GRAPH_ROLLBACK_CMD[$key]"
    done
    
    unset "_GRAPH_WORKFLOWS[$wf]"
    
    _graph_log info "Cleared workflow: $wf"
    return 0
}

# List all defined workflows
# Usage: graph_list
graph_list() {
    local wf
    for wf in "${_GRAPH_WORKFLOWS[@]}"; do
        printf '%s\n' "$wf"
    done
}

# Get task output
# Usage: output=$(graph_task_output "wf" "task")
graph_task_output() {
    local wf="$1"
    local task="$2"
    local key
    key=$(_graph_key "$wf" "$task")
    printf '%s' "${_GRAPH_OUTPUT[$key]:-}"
}

# Get task error
# Usage: error=$(graph_task_error "wf" "task")
graph_task_error() {
    local wf="$1"
    local task="$2"
    local key
    key=$(_graph_key "$wf" "$task")
    printf '%s' "${_GRAPH_ERROR[$key]:-}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_GRAPH_EXPORTS=(
    graph_define
    graph_add_task
    graph_add_dep
    graph_execute
    graph_visualize
    graph_status
    graph_rollback
    graph_clear
    graph_list
    graph_task_output
    graph_task_error
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_GRAPH_EXPORTS[@]}" 2>/dev/null || true
fi

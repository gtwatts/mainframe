#!/usr/bin/env bash
# =============================================================================
# taskgraph.sh - Declarative Task Graph / Workflow Orchestration
# =============================================================================
# Description: Provides a declarative API for defining tasks with dependencies,
#              inputs, outputs, and execution commands. Builds on workflow.sh.
# Version: 1.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TASKGRAPH_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_TASKGRAPH_LOADED=1

# =============================================================================
# Global State
# =============================================================================

declare -gA _TASK_DEFINITIONS=()     # task_name -> JSON definition
declare -gA _TASK_DEPENDENCIES=()    # task_name -> "dep1 dep2 ..."
declare -gA _TASK_STATUS=()          # task_name -> pending|running|completed|failed
declare -gA _TASK_OUTPUTS=()         # task_name -> output value/path
declare -g _TASK_GRAPH_NAME=""

# =============================================================================
# Internal Functions
# =============================================================================

# Parse task definition JSON (simple)
_task_get_field() {
    local json="$1"
    local field="$2"

    # Simple extraction for quoted strings
    local pattern="\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try array extraction
    pattern="\"$field\"[[:space:]]*:[[:space:]]*\[([^\]]*)\]"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Check if all dependencies are completed
_task_deps_satisfied() {
    local task_name="$1"
    local deps="${_TASK_DEPENDENCIES[$task_name]:-}"

    [[ -z "$deps" ]] && return 0

    local dep
    for dep in $deps; do
        local status="${_TASK_STATUS[$dep]:-}"
        if [[ "$status" != "completed" ]]; then
            return 1
        fi
    done

    return 0
}

# Get list of tasks ready to run
_task_get_ready() {
    local task_name
    for task_name in "${!_TASK_DEFINITIONS[@]}"; do
        local status="${_TASK_STATUS[$task_name]:-pending}"
        if [[ "$status" == "pending" ]] && _task_deps_satisfied "$task_name"; then
            echo "$task_name"
        fi
    done
}

# =============================================================================
# Public API
# =============================================================================

# task_define - Define a task with optional dependencies, inputs, outputs, and command
# Usage: task_define <name> [--inputs "path"] [--outputs "path"] [--depends "task1 task2"] --cmd "command"
task_define() {
    local name="$1"
    shift

    [[ -z "$name" ]] && {
        echo "Usage: task_define <name> [--inputs ...] [--outputs ...] [--depends ...] --cmd \"...\"" >&2
        return 1
    }

    local inputs="" outputs="" depends="" cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inputs)
                inputs="$2"
                shift 2
                ;;
            --outputs)
                outputs="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --cmd)
                cmd="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Store definition as JSON-like structure
    local def="{"
    def+="\"name\":\"$name\""
    [[ -n "$inputs" ]] && def+=",\"inputs\":\"$inputs\""
    [[ -n "$outputs" ]] && def+=",\"outputs\":\"$outputs\""
    [[ -n "$depends" ]] && def+=",\"depends\":\"$depends\""
    [[ -n "$cmd" ]] && def+=",\"cmd\":\"$cmd\""
    def+="}"

    _TASK_DEFINITIONS[$name]="$def"
    _TASK_DEPENDENCIES[$name]="$depends"
    _TASK_STATUS[$name]="pending"

    echo "Task defined: $name"
    [[ -n "$depends" ]] && echo "  Depends on: $depends"
    [[ -n "$cmd" ]] && echo "  Command: $cmd"
}

# task_run - Run a single task
# Usage: task_run <name>
task_run() {
    local name="$1"

    [[ -z "${_TASK_DEFINITIONS[$name]:-}" ]] && {
        echo "Error: Task '$name' not defined" >&2
        return 1
    }

    local def="${_TASK_DEFINITIONS[$name]}"
    local cmd
    cmd=$(_task_get_field "$def" "cmd")

    [[ -z "$cmd" ]] && {
        echo "Error: Task '$name' has no command" >&2
        return 1
    }

    # Check dependencies
    if ! _task_deps_satisfied "$name"; then
        echo "Error: Task '$name' has unsatisfied dependencies" >&2
        return 1
    fi

    echo "Running task: $name"
    _TASK_STATUS[$name]="running"

    # Execute command
    if eval "$cmd"; then
        _TASK_STATUS[$name]="completed"
        echo "Task completed: $name"

        # Store output path if defined
        local outputs
        outputs=$(_task_get_field "$def" "outputs")
        [[ -n "$outputs" ]] && _TASK_OUTPUTS[$name]="$outputs"

        return 0
    else
        _TASK_STATUS[$name]="failed"
        echo "Task failed: $name"
        return 1
    fi
}

# task_run_graph - Run all tasks resolving dependencies (topological sort)
# Usage: task_run_graph [target_task]
task_run_graph() {
    local target="${1:-}"

    if [[ ${#_TASK_DEFINITIONS[@]} -eq 0 ]]; then
        echo "Error: No tasks defined" >&2
        return 1
    fi

    echo "Running task graph..."

    # If target specified, only run tasks needed for that target
    local tasks_to_run=()
    if [[ -n "$target" ]]; then
        # Collect target and all its dependencies (recursive)
        local to_check=("$target")
        local checked=()

        while [[ ${#to_check[@]} -gt 0 ]]; do
            local current="${to_check[0]}"
            to_check=("${to_check[@]:1}")

            # Skip if already checked
            local skip=0
            for c in "${checked[@]}"; do
                [[ "$c" == "$current" ]] && { skip=1; break; }
            done
            [[ $skip -eq 1 ]] && continue

            checked+=("$current")
            tasks_to_run+=("$current")

            # Add dependencies
            local deps="${_TASK_DEPENDENCIES[$current]:-}"
            for dep in $deps; do
                to_check+=("$dep")
            done
        done
    else
        tasks_to_run=("${!_TASK_DEFINITIONS[@]}")
    fi

    # Run tasks in dependency order
    local completed=0
    local max_iterations=$((${#tasks_to_run[@]} * 2))
    local iteration=0

    while [[ $completed -lt ${#tasks_to_run[@]} && $iteration -lt $max_iterations ]]; do
        ((iteration++))

        local ran_something=0

        for task_name in "${tasks_to_run[@]}"; do
            local status="${_TASK_STATUS[$task_name]:-pending}"

            # Skip completed or failed
            [[ "$status" == "completed" || "$status" == "failed" ]] && continue

            # Check if ready to run
            if _task_deps_satisfied "$task_name"; then
                if task_run "$task_name"; then
                    ((completed++))
                    ran_something=1
                else
                    echo "Error: Task '$task_name' failed, stopping graph" >&2
                    return 1
                fi
            fi
        done

        # Detect deadlock
        if [[ $ran_something -eq 0 && $completed -lt ${#tasks_to_run[@]} ]]; then
            echo "Error: Circular dependency detected in task graph" >&2
            return 1
        fi
    done

    echo ""
    echo "Task graph completed: $completed tasks"
    return 0
}

# task_status - Show status of all tasks
task_status() {
    echo "Task Status"
    echo "==========="

    local task_name
    for task_name in "${!_TASK_DEFINITIONS[@]}"; do
        local status="${_TASK_STATUS[$task_name]:-pending}"
        local deps="${_TASK_DEPENDENCIES[$task_name]:-}"

        printf '%-20s %s' "$task_name" "$status"
        [[ -n "$deps" ]] && printf ' (depends: %s)' "$deps"
        echo
    done
}

# task_reset - Reset all tasks to pending
task_reset() {
    local task_name
    for task_name in "${!_TASK_STATUS[@]}"; do
        _TASK_STATUS[$task_name]="pending"
    done
    echo "All tasks reset to pending"
}

# task_clear - Clear all task definitions
task_clear() {
    _TASK_DEFINITIONS=()
    _TASK_DEPENDENCIES=()
    _TASK_STATUS=()
    _TASK_OUTPUTS=()
    _TASK_GRAPH_NAME=""
    echo "All tasks cleared"
}

# task_list - List defined tasks
task_list() {
    echo "Defined Tasks:"

    local task_name
    for task_name in "${!_TASK_DEFINITIONS[@]}"; do
        local def="${_TASK_DEFINITIONS[$task_name]}"
        local cmd
        cmd=$(_task_get_field "$def" "cmd")
        printf '  %-20s %s\n' "$task_name" "${cmd:0:50}"
    done
}

# task_output - Get output path/value for a completed task
# Usage: task_output <task_name>
task_output() {
    local name="$1"

    local output="${_TASK_OUTPUTS[$name]:-}"
    [[ -n "$output" ]] && echo "$output"
}

# task_graph - Set/get the current graph name
# Usage: task_graph [name]
task_graph() {
    local name="${1:-}"

    if [[ -n "$name" ]]; then
        _TASK_GRAPH_NAME="$name"
        echo "Task graph: $name"
    else
        echo "${_TASK_GRAPH_NAME:-unnamed}"
    fi
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _TASKGRAPH_EXPORTS=(
    task_define
    task_run
    task_run_graph
    task_status
    task_reset
    task_clear
    task_list
    task_output
    task_graph
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_TASKGRAPH_EXPORTS[@]}" 2>/dev/null || true
fi

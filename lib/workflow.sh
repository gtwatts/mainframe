#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/workflow.sh - DAG-Based Workflow Orchestration
# =============================================================================
# Description: Define, execute, and monitor multi-step workflows with
#              dependency-aware scheduling using Kahn's algorithm for
#              topological sort. Supports parallel execution of independent
#              steps, failure propagation, retry, and cancellation.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_WORKFLOW_LOADED:-}" ]] && return 0
_MAINFRAME_WORKFLOW_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for workflow state
MAINFRAME_WORKFLOW_DIR="${MAINFRAME_WORKFLOW_DIR:-${TMPDIR:-/tmp}/mainframe-${UID:-$(id -u)}/workflows}"

# Default parallelism (max concurrent background jobs)
_MAINFRAME_WF_DEFAULT_PARALLEL=4

# Step statuses
_MAINFRAME_WF_STATUS_PENDING="pending"
_MAINFRAME_WF_STATUS_RUNNING="running"
_MAINFRAME_WF_STATUS_SUCCESS="success"
_MAINFRAME_WF_STATUS_FAILED="failed"
_MAINFRAME_WF_STATUS_SKIPPED="skipped"
_MAINFRAME_WF_STATUS_CANCELLED="cancelled"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_wf_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "workflow" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[workflow] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

# JSON-escape a string (lightweight inline version)
_wf_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Extract a JSON string value for a known top-level key, honoring escaped quotes.
_wf_json_get_string() {
    local json="$1"
    local key="$2"
    local marker="\"${key}\":\""

    [[ "$json" == *"$marker"* ]] || return 1

    local rest="${json#*"$marker"}"
    local out=""
    local escaped="false"
    local i char hex

    for ((i=0; i<${#rest}; i++)); do
        char="${rest:i:1}"

        if [[ "$escaped" == "true" ]]; then
            case "$char" in
                '"') out+='"' ;;
                '\') out+='\' ;;
                /) out+='/' ;;
                b) out+=$'\b' ;;
                f) out+=$'\f' ;;
                n) out+=$'\n' ;;
                r) out+=$'\r' ;;
                t) out+=$'\t' ;;
                u)
                    hex="${rest:i+1:4}"
                    if [[ "$hex" =~ ^[0-9A-Fa-f]{4}$ ]]; then
                        if [[ "$hex" =~ ^00([0-7][0-9A-Fa-f])$ ]]; then
                            printf -v char "\\x%s" "${BASH_REMATCH[1]}"
                            out+="$char"
                        else
                            out+="\\u$hex"
                        fi
                        i=$(( i + 4 ))
                    else
                        out+='u'
                    fi
                    ;;
                *) out+="$char" ;;
            esac
            escaped="false"
            continue
        fi

        case "$char" in
            '\') escaped="true" ;;
            '"')
                printf '%s' "$out"
                return 0
                ;;
            *)
                out+="$char"
                ;;
        esac
    done

    return 1
}

# Get workflow directory for a named workflow
_wf_dir() {
    local name="$1"
    printf '%s/%s' "$MAINFRAME_WORKFLOW_DIR" "$name"
}

# Get steps directory for a workflow
_wf_steps_dir() {
    local name="$1"
    printf '%s/%s/steps' "$MAINFRAME_WORKFLOW_DIR" "$name"
}

# Get runs directory for history
_wf_runs_dir() {
    printf '%s/.runs' "$MAINFRAME_WORKFLOW_DIR"
}

# Read a step file and set variables: _step_command, _step_depends (array), _step_status
_wf_read_step() {
    local name="$1"
    local step="$2"
    local step_file
    step_file="$(_wf_steps_dir "$name")/${step}.json"

    if [[ ! -f "$step_file" ]]; then
        return 1
    fi

    local content
    content=$(<"$step_file")

    _step_command=""
    if ! _step_command=$(_wf_json_get_string "$content" "command"); then
        _step_command=""
    fi

    _step_status="$_MAINFRAME_WF_STATUS_PENDING"
    if ! _step_status=$(_wf_json_get_string "$content" "status"); then
        _step_status="$_MAINFRAME_WF_STATUS_PENDING"
    fi

    # Parse depends array
    _step_depends=()
    if [[ "$content" =~ \"depends\":\[([^\]]*)\] ]]; then
        local deps_str="${BASH_REMATCH[1]}"
        # Extract individual quoted strings
        while [[ "$deps_str" =~ \"([^\"]+)\" ]]; do
            _step_depends+=("${BASH_REMATCH[1]}")
            deps_str="${deps_str#*\"${BASH_REMATCH[1]}\"}"
        done
    fi

    return 0
}

# Write step file
_wf_write_step() {
    local name="$1"
    local step="$2"
    local command="$3"
    local status="$4"
    shift 4
    local -a depends=("$@")

    local steps_dir
    steps_dir="$(_wf_steps_dir "$name")"
    mkdir -p "$steps_dir"
    chmod 700 "$MAINFRAME_WORKFLOW_DIR" 2>/dev/null

    local deps_json="[]"
    if [[ ${#depends[@]} -gt 0 ]]; then
        deps_json="["
        local first=true
        for dep in "${depends[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                deps_json+=","
            fi
            deps_json+="\"$(_wf_json_escape "$dep")\""
        done
        deps_json+="]"
    fi

    local escaped_cmd
    escaped_cmd="$(_wf_json_escape "$command")"

    printf '{"command":"%s","depends":%s,"status":"%s"}' \
        "$escaped_cmd" "$deps_json" "$status" > "${steps_dir}/${step}.json"
}

# Update only the status field in a step file
_wf_update_status() {
    local name="$1"
    local step="$2"
    local new_status="$3"

    _wf_read_step "$name" "$step" || return 1
    _wf_write_step "$name" "$step" "$_step_command" "$new_status" "${_step_depends[@]}"
}

# Get list of all step names for a workflow
_wf_list_steps() {
    local name="$1"
    local steps_dir
    steps_dir="$(_wf_steps_dir "$name")"

    if [[ ! -d "$steps_dir" ]]; then
        return 0
    fi

    local f
    for f in "$steps_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local base="${f##*/}"
        printf '%s\n' "${base%.json}"
    done
}

# Get current epoch timestamp
_wf_timestamp() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# Record a workflow run in history
_wf_record_run() {
    local name="$1"
    local status="$2"
    local start_time="$3"
    local end_time="$4"

    local runs_dir
    runs_dir="$(_wf_runs_dir)"
    mkdir -p "$runs_dir"

    local duration
    duration=$(( end_time - start_time ))

    printf '{"workflow":"%s","status":"%s","start":%s,"end":%s,"duration":%s}\n' \
        "$(_wf_json_escape "$name")" "$status" "$start_time" "$end_time" "$duration" \
        >> "${runs_dir}/history.jsonl"
}

# =============================================================================
# WORKFLOW DEFINITION
# =============================================================================

# Create a new workflow
# Usage: workflow_define NAME
workflow_define() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_define: workflow name required"
        return 1
    fi

    # Validate name (alphanumeric, hyphens, underscores)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        _wf_log error "workflow_define: invalid name '$name' (use alphanumeric, hyphens, underscores)"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"

    mkdir -p "$wf_dir/steps"

    # Write workflow metadata
    printf '{"name":"%s","created":%s}' \
        "$(_wf_json_escape "$name")" "$(_wf_timestamp)" > "$wf_dir/meta.json"

    _wf_log info "Workflow '$name' defined"
    return 0
}

# Add a step to a workflow
# Usage: workflow_step NAME CMD [--depends DEP1,DEP2...]
workflow_step() {
    local name="${1:-}"
    local step="${2:-}"
    local command="${3:-}"
    shift 3 2>/dev/null || true

    if [[ -z "$name" || -z "$step" || -z "$command" ]]; then
        _wf_log error "workflow_step: requires NAME STEP COMMAND [--depends DEP1,DEP2]"
        return 1
    fi

    # Validate workflow exists
    local wf_dir
    wf_dir="$(_wf_dir "$name")"
    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_step: workflow '$name' not defined"
        return 1
    fi

    # Validate step name
    if [[ ! "$step" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        _wf_log error "workflow_step: invalid step name '$step'"
        return 1
    fi

    # Parse --depends flag
    local -a depends=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depends)
                shift
                if [[ -n "${1:-}" ]]; then
                    IFS=',' read -ra depends <<< "$1"
                fi
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate dependencies exist (if any)
    for dep in "${depends[@]}"; do
        if [[ ! -f "$(_wf_steps_dir "$name")/${dep}.json" ]]; then
            _wf_log error "workflow_step: dependency '$dep' not found in workflow '$name'"
            return 1
        fi
    done

    _wf_write_step "$name" "$step" "$command" "$_MAINFRAME_WF_STATUS_PENDING" "${depends[@]}"

    _wf_log debug "Step '$step' added to workflow '$name'"
    return 0
}

# Remove a step from a workflow
# Usage: workflow_remove_step NAME STEP
workflow_remove_step() {
    local name="${1:-}"
    local step="${2:-}"

    if [[ -z "$name" || -z "$step" ]]; then
        _wf_log error "workflow_remove_step: requires NAME STEP"
        return 1
    fi

    local step_file
    step_file="$(_wf_steps_dir "$name")/${step}.json"

    if [[ ! -f "$step_file" ]]; then
        _wf_log error "workflow_remove_step: step '$step' not found"
        return 1
    fi

    # Check if other steps depend on this one
    local other_step
    while IFS= read -r other_step; do
        [[ -z "$other_step" ]] && continue
        _wf_read_step "$name" "$other_step"
        for dep in "${_step_depends[@]}"; do
            if [[ "$dep" == "$step" ]]; then
                _wf_log error "workflow_remove_step: step '$other_step' depends on '$step'"
                return 1
            fi
        done
    done < <(_wf_list_steps "$name")

    rm -f "$step_file"
    _wf_log info "Step '$step' removed from workflow '$name'"
    return 0
}

# List all defined workflows
# Usage: workflow_list
workflow_list() {
    if [[ ! -d "$MAINFRAME_WORKFLOW_DIR" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '[]'
        fi
        return 0
    fi

    local -a workflows=()
    local d
    for d in "$MAINFRAME_WORKFLOW_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local base="${d%/}"
        base="${base##*/}"
        # Skip hidden directories (like .runs)
        [[ "$base" == .* ]] && continue
        if [[ -f "$d/meta.json" ]]; then
            workflows+=("$base")
        fi
    done

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '['
        local first=true
        for wf in "${workflows[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '"%s"' "$(_wf_json_escape "$wf")"
        done
        printf ']'
    else
        for wf in "${workflows[@]}"; do
            printf '%s\n' "$wf"
        done
    fi

    return 0
}

# =============================================================================
# DAG OPERATIONS - TOPOLOGICAL SORT (Kahn's Algorithm)
# =============================================================================

# Detect cycles in the dependency graph
# Returns 0 if no cycles, 1 if cycles detected
_wf_detect_cycle() {
    local name="$1"

    # Build in-degree map using Kahn's algorithm
    local -A in_degree
    local -A adjacency
    local -a all_steps=()

    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        all_steps+=("$step")
        in_degree["$step"]=0
        adjacency["$step"]=""
    done < <(_wf_list_steps "$name")

    # Count in-degrees
    for step in "${all_steps[@]}"; do
        _wf_read_step "$name" "$step"
        for dep in "${_step_depends[@]}"; do
            local current="${in_degree[$step]:-0}"
            in_degree["$step"]=$(( current + 1 ))
            adjacency["$dep"]="${adjacency[$dep]:+${adjacency[$dep]} }$step"
        done
    done

    # Find nodes with in-degree 0
    local -a queue=()
    for step in "${all_steps[@]}"; do
        if [[ "${in_degree[$step]}" -eq 0 ]]; then
            queue+=("$step")
        fi
    done

    local processed=0
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        processed=$(( processed + 1 ))

        # Reduce in-degree of neighbors
        local neighbors="${adjacency[$current]:-}"
        if [[ -n "$neighbors" ]]; then
            local neighbor
            for neighbor in $neighbors; do
                local deg="${in_degree[$neighbor]}"
                deg=$(( deg - 1 ))
                in_degree["$neighbor"]=$deg
                if [[ $deg -eq 0 ]]; then
                    queue+=("$neighbor")
                fi
            done
        fi
    done

    if [[ $processed -ne ${#all_steps[@]} ]]; then
        return 1  # Cycle detected
    fi
    return 0
}

# Get topological order of steps (returns newline-separated list)
_wf_topological_sort() {
    local name="$1"

    local -A in_degree
    local -A adjacency
    local -a all_steps=()

    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        all_steps+=("$step")
        in_degree["$step"]=0
        adjacency["$step"]=""
    done < <(_wf_list_steps "$name")

    # Build adjacency and in-degree
    for step in "${all_steps[@]}"; do
        _wf_read_step "$name" "$step"
        for dep in "${_step_depends[@]}"; do
            local current="${in_degree[$step]:-0}"
            in_degree["$step"]=$(( current + 1 ))
            adjacency["$dep"]="${adjacency[$dep]:+${adjacency[$dep]} }$step"
        done
    done

    # Kahn's algorithm
    local -a queue=()
    for step in "${all_steps[@]}"; do
        if [[ "${in_degree[$step]}" -eq 0 ]]; then
            queue+=("$step")
        fi
    done

    local -a sorted=()
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        sorted+=("$current")

        local neighbors="${adjacency[$current]:-}"
        if [[ -n "$neighbors" ]]; then
            local neighbor
            for neighbor in $neighbors; do
                local deg="${in_degree[$neighbor]}"
                deg=$(( deg - 1 ))
                in_degree["$neighbor"]=$deg
                if [[ $deg -eq 0 ]]; then
                    queue+=("$neighbor")
                fi
            done
        fi
    done

    for s in "${sorted[@]}"; do
        printf '%s\n' "$s"
    done
}

# Check if all dependencies of a step are satisfied (status=success)
_wf_deps_satisfied() {
    local name="$1"
    local step="$2"

    _wf_read_step "$name" "$step" || return 1
    local -a my_deps=("${_step_depends[@]}")

    for dep in "${my_deps[@]}"; do
        _wf_read_step "$name" "$dep" || return 1
        if [[ "$_step_status" != "$_MAINFRAME_WF_STATUS_SUCCESS" ]]; then
            return 1
        fi
    done
    return 0
}

# Check if any dependency of a step has failed
_wf_deps_failed() {
    local name="$1"
    local step="$2"

    _wf_read_step "$name" "$step" || return 1
    local -a my_deps=("${_step_depends[@]}")

    for dep in "${my_deps[@]}"; do
        _wf_read_step "$name" "$dep" || return 1
        if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_FAILED" || \
              "$_step_status" == "$_MAINFRAME_WF_STATUS_SKIPPED" || \
              "$_step_status" == "$_MAINFRAME_WF_STATUS_CANCELLED" ]]; then
            return 0  # Yes, a dep has failed
        fi
    done
    return 1  # No deps have failed
}

# =============================================================================
# EXECUTION
# =============================================================================

# Execute a workflow respecting DAG order
# Usage: workflow_run NAME [--parallel N] [--continue-on-error]
workflow_run() {
    local name="${1:-}"
    shift 2>/dev/null || true

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_run: workflow name required"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"
    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_run: workflow '$name' not defined"
        return 1
    fi

    # Parse options
    local max_parallel=$_MAINFRAME_WF_DEFAULT_PARALLEL
    local continue_on_error=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parallel)
                shift
                max_parallel="${1:-$_MAINFRAME_WF_DEFAULT_PARALLEL}"
                shift
                ;;
            --continue-on-error)
                continue_on_error=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check for empty workflow
    local -a all_steps=()
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        all_steps+=("$step")
    done < <(_wf_list_steps "$name")

    if [[ ${#all_steps[@]} -eq 0 ]]; then
        _wf_log warn "workflow_run: workflow '$name' has no steps"
        return 0
    fi

    # Detect cycles
    if ! _wf_detect_cycle "$name"; then
        _wf_log error "workflow_run: circular dependency detected in '$name'"
        return 1
    fi

    # Reset all steps to pending
    for step in "${all_steps[@]}"; do
        _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_PENDING"
    done

    # Mark workflow as running
    local start_time
    start_time="$(_wf_timestamp)"
    printf '%s' "$$" > "$wf_dir/pid"

    local workflow_failed=false

    # Track running PIDs: associative array step_name -> pid
    local -A running_pids=()
    local -A pid_to_step=()

    # Main execution loop
    while true; do
        # Check for cancellation
        if [[ -f "$wf_dir/cancel" ]]; then
            _wf_log info "Workflow '$name' cancelled"
            # Kill running jobs
            for pid in "${running_pids[@]}"; do
                kill "$pid" 2>/dev/null || true
            done
            # Mark remaining as cancelled
            for step in "${all_steps[@]}"; do
                _wf_read_step "$name" "$step"
                if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_PENDING" || \
                      "$_step_status" == "$_MAINFRAME_WF_STATUS_RUNNING" ]]; then
                    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_CANCELLED"
                fi
            done
            rm -f "$wf_dir/cancel" "$wf_dir/pid"
            _wf_record_run "$name" "cancelled" "$start_time" "$(_wf_timestamp)"
            return 1
        fi

        # Collect finished background jobs
        local -a finished_steps=()
        for step in "${!running_pids[@]}"; do
            local pid="${running_pids[$step]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                # Process exited, check result
                wait "$pid" 2>/dev/null
                local exit_code=$?
                finished_steps+=("$step")
                if [[ $exit_code -eq 0 ]]; then
                    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_SUCCESS"
                    _wf_log info "Step '$step' completed successfully"
                else
                    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_FAILED"
                    _wf_log error "Step '$step' failed (exit code $exit_code)"
                    workflow_failed=true
                fi
            fi
        done

        # Remove finished from running map
        for step in "${finished_steps[@]}"; do
            unset "running_pids[$step]"
        done

        # If a step failed and not continue-on-error, skip remaining pending deps
        if [[ "$workflow_failed" == "true" && "$continue_on_error" == "false" ]]; then
            # Skip steps whose deps have failed
            for step in "${all_steps[@]}"; do
                _wf_read_step "$name" "$step"
                if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_PENDING" ]]; then
                    if _wf_deps_failed "$name" "$step"; then
                        _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_SKIPPED"
                        _wf_log info "Step '$step' skipped (dependency failed)"
                    fi
                fi
            done
        fi

        # Count current running jobs
        local running_count=${#running_pids[@]}

        # Find steps ready to run (pending + deps satisfied)
        local launched=false
        for step in "${all_steps[@]}"; do
            # Check parallelism limit
            if [[ $running_count -ge $max_parallel ]]; then
                break
            fi

            _wf_read_step "$name" "$step"
            if [[ "$_step_status" != "$_MAINFRAME_WF_STATUS_PENDING" ]]; then
                continue
            fi

            # Check if deps are all satisfied
            if _wf_deps_satisfied "$name" "$step"; then
                # Launch this step
                _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_RUNNING"
                _wf_read_step "$name" "$step"
                local cmd="$_step_command"

                _wf_log info "Running step '$step': $cmd"

                # Run in background
                (eval "$cmd") &
                local bg_pid=$!
                running_pids["$step"]=$bg_pid
                pid_to_step[$bg_pid]="$step"
                running_count=$(( running_count + 1 ))
                launched=true
            fi
        done

        # Check if we're done
        local pending_count=0
        local done_count=0
        for step in "${all_steps[@]}"; do
            _wf_read_step "$name" "$step"
            case "$_step_status" in
                "$_MAINFRAME_WF_STATUS_PENDING") pending_count=$(( pending_count + 1 )) ;;
                "$_MAINFRAME_WF_STATUS_RUNNING") ;;
                *) done_count=$(( done_count + 1 )) ;;
            esac
        done

        # All done (nothing running, nothing pending)
        if [[ ${#running_pids[@]} -eq 0 && $pending_count -eq 0 ]]; then
            break
        fi

        # Deadlock detection: nothing running, nothing can launch, but pending remain
        if [[ ${#running_pids[@]} -eq 0 && "$launched" == "false" && $pending_count -gt 0 ]]; then
            _wf_log error "Deadlock detected: $pending_count steps pending but none can run"
            for step in "${all_steps[@]}"; do
                _wf_read_step "$name" "$step"
                if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_PENDING" ]]; then
                    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_SKIPPED"
                fi
            done
            workflow_failed=true
            break
        fi

        # Wait briefly before next check (avoid busy loop)
        if [[ ${#running_pids[@]} -gt 0 ]]; then
            # Wait for any child to finish
            sleep 0.1 2>/dev/null || sleep 1
        fi
    done

    # Cleanup
    rm -f "$wf_dir/pid" "$wf_dir/cancel"

    local end_time
    end_time="$(_wf_timestamp)"
    local final_status="success"
    [[ "$workflow_failed" == "true" ]] && final_status="failed"

    _wf_record_run "$name" "$final_status" "$start_time" "$end_time"

    if [[ "$workflow_failed" == "true" ]]; then
        _wf_log error "Workflow '$name' completed with failures"
        return 1
    fi

    _wf_log info "Workflow '$name' completed successfully"
    return 0
}

# Run a single step manually (ignoring dependencies)
# Usage: workflow_run_step NAME STEP
workflow_run_step() {
    local name="${1:-}"
    local step="${2:-}"

    if [[ -z "$name" || -z "$step" ]]; then
        _wf_log error "workflow_run_step: requires NAME STEP"
        return 1
    fi

    if ! _wf_read_step "$name" "$step"; then
        _wf_log error "workflow_run_step: step '$step' not found in '$name'"
        return 1
    fi

    local cmd="$_step_command"
    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_RUNNING"

    if eval "$cmd"; then
        _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_SUCCESS"
        return 0
    else
        _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_FAILED"
        return 1
    fi
}

# Retry a failed step (and reset its dependents to pending)
# Usage: workflow_retry NAME STEP
workflow_retry() {
    local name="${1:-}"
    local step="${2:-}"

    if [[ -z "$name" || -z "$step" ]]; then
        _wf_log error "workflow_retry: requires NAME STEP"
        return 1
    fi

    if ! _wf_read_step "$name" "$step"; then
        _wf_log error "workflow_retry: step '$step' not found"
        return 1
    fi

    if [[ "$_step_status" != "$_MAINFRAME_WF_STATUS_FAILED" && \
          "$_step_status" != "$_MAINFRAME_WF_STATUS_SKIPPED" ]]; then
        _wf_log error "workflow_retry: step '$step' is not failed/skipped (status: $_step_status)"
        return 1
    fi

    # Reset this step to pending
    _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_PENDING"

    # Reset all dependents (steps that depend on this step) to pending
    local other_step
    while IFS= read -r other_step; do
        [[ -z "$other_step" ]] && continue
        _wf_read_step "$name" "$other_step"
        for dep in "${_step_depends[@]}"; do
            if [[ "$dep" == "$step" ]]; then
                if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_SKIPPED" || \
                      "$_step_status" == "$_MAINFRAME_WF_STATUS_FAILED" ]]; then
                    _wf_update_status "$name" "$other_step" "$_MAINFRAME_WF_STATUS_PENDING"
                fi
                break
            fi
        done
    done < <(_wf_list_steps "$name")

    _wf_log info "Step '$step' reset for retry"
    return 0
}

# Cancel a running workflow
# Usage: workflow_cancel NAME
workflow_cancel() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_cancel: workflow name required"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"

    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_cancel: workflow '$name' not defined"
        return 1
    fi

    # Signal cancellation
    touch "$wf_dir/cancel"

    # If there's a PID file, signal the orchestrator
    if [[ -f "$wf_dir/pid" ]]; then
        local orchestrator_pid
        orchestrator_pid=$(<"$wf_dir/pid")
        if [[ -n "$orchestrator_pid" ]] && kill -0 "$orchestrator_pid" 2>/dev/null; then
            _wf_log info "Signalling workflow '$name' (PID $orchestrator_pid) for cancellation"
        fi
    fi

    # Mark pending/running steps as cancelled
    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        _wf_read_step "$name" "$step"
        if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_PENDING" || \
              "$_step_status" == "$_MAINFRAME_WF_STATUS_RUNNING" ]]; then
            _wf_update_status "$name" "$step" "$_MAINFRAME_WF_STATUS_CANCELLED"
        fi
    done < <(_wf_list_steps "$name")

    _wf_log info "Workflow '$name' cancelled"
    return 0
}

# =============================================================================
# STATUS & MONITORING
# =============================================================================

# Get JSON status of each step in a workflow
# Usage: workflow_status NAME
workflow_status() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_status: workflow name required"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"
    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_status: workflow '$name' not defined"
        return 1
    fi

    printf '{"workflow":"%s","steps":{' "$(_wf_json_escape "$name")"

    local first=true
    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        _wf_read_step "$name" "$step"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            printf ','
        fi

        # Build depends array
        local deps_json="[]"
        if [[ ${#_step_depends[@]} -gt 0 ]]; then
            deps_json="["
            local dfirst=true
            for dep in "${_step_depends[@]}"; do
                if [[ "$dfirst" == "true" ]]; then
                    dfirst=false
                else
                    deps_json+=","
                fi
                deps_json+="\"$(_wf_json_escape "$dep")\""
            done
            deps_json+="]"
        fi

        printf '"%s":{"status":"%s","command":"%s","depends":%s}' \
            "$(_wf_json_escape "$step")" \
            "$_step_status" \
            "$(_wf_json_escape "$_step_command")" \
            "$deps_json"
    done < <(_wf_list_steps "$name")

    printf '}}'
    return 0
}

# Check if a workflow is currently running
# Usage: workflow_is_running NAME
workflow_is_running() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"

    if [[ -f "$wf_dir/pid" ]]; then
        local pid
        pid=$(<"$wf_dir/pid")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi

    # Also check if any step is in running status
    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        _wf_read_step "$name" "$step"
        if [[ "$_step_status" == "$_MAINFRAME_WF_STATUS_RUNNING" ]]; then
            return 0
        fi
    done < <(_wf_list_steps "$name")

    return 1
}

# Show workflow run history
# Usage: workflow_history [--json] [--limit N]
workflow_history() {
    local format="text"
    local limit=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) format="json"; shift ;;
            --limit)
                shift
                limit="${1:-20}"
                shift
                ;;
            *) shift ;;
        esac
    done

    local runs_dir
    runs_dir="$(_wf_runs_dir)"
    local history_file="${runs_dir}/history.jsonl"

    if [[ ! -f "$history_file" ]]; then
        if [[ "$format" == "json" ]]; then
            printf '[]'
        else
            printf 'No workflow history\n'
        fi
        return 0
    fi

    # Read last N lines
    local -a lines=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        lines+=("$line")
    done < "$history_file"

    # Get last N entries
    local total=${#lines[@]}
    local start=0
    if [[ $total -gt $limit ]]; then
        start=$(( total - limit ))
    fi

    if [[ "$format" == "json" ]]; then
        printf '['
        local first=true
        local i=$start
        while [[ $i -lt $total ]]; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '%s' "${lines[$i]}"
            i=$(( i + 1 ))
        done
        printf ']'
    else
        printf '%-20s %-10s %-12s %s\n' "WORKFLOW" "STATUS" "DURATION" "STARTED"
        printf '%-20s %-10s %-12s %s\n' "--------" "------" "--------" "-------"
        local i=$start
        while [[ $i -lt $total ]]; do
            local entry="${lines[$i]}"
            local wf_name="" status="" duration=""
            if [[ "$entry" =~ \"workflow\":\"([^\"]+)\" ]]; then
                wf_name="${BASH_REMATCH[1]}"
            fi
            if [[ "$entry" =~ \"status\":\"([^\"]+)\" ]]; then
                status="${BASH_REMATCH[1]}"
            fi
            if [[ "$entry" =~ \"duration\":([0-9]+) ]]; then
                duration="${BASH_REMATCH[1]}s"
            fi
            printf '%-20s %-10s %-12s\n' "$wf_name" "$status" "$duration"
            i=$(( i + 1 ))
        done
    fi

    return 0
}

# =============================================================================
# VISUALIZATION & EXPORT
# =============================================================================

# Output Mermaid diagram definition for a workflow
# Usage: workflow_visualize NAME
workflow_visualize() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_visualize: workflow name required"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"
    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_visualize: workflow '$name' not defined"
        return 1
    fi

    printf 'graph TD\n'

    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        _wf_read_step "$name" "$step"

        # Node definition with status styling
        local style=""
        case "$_step_status" in
            "$_MAINFRAME_WF_STATUS_SUCCESS") style=":::success" ;;
            "$_MAINFRAME_WF_STATUS_FAILED") style=":::failed" ;;
            "$_MAINFRAME_WF_STATUS_RUNNING") style=":::running" ;;
            "$_MAINFRAME_WF_STATUS_SKIPPED") style=":::skipped" ;;
        esac

        printf '    %s["%s"]%s\n' "$step" "$step" "$style"

        # Edges from dependencies
        for dep in "${_step_depends[@]}"; do
            printf '    %s --> %s\n' "$dep" "$step"
        done
    done < <(_wf_list_steps "$name")

    # Style definitions
    printf '    classDef success fill:#90EE90\n'
    printf '    classDef failed fill:#FFB6C1\n'
    printf '    classDef running fill:#87CEEB\n'
    printf '    classDef skipped fill:#D3D3D3\n'

    return 0
}

# Export workflow definition as JSON
# Usage: workflow_export NAME FILE
workflow_export() {
    local name="${1:-}"
    local file="${2:-}"

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_export: workflow name required"
        return 1
    fi

    local wf_dir
    wf_dir="$(_wf_dir "$name")"
    if [[ ! -d "$wf_dir" ]]; then
        _wf_log error "workflow_export: workflow '$name' not defined"
        return 1
    fi

    local output=""
    output+='{"name":"'
    output+="$(_wf_json_escape "$name")"
    output+='","steps":['

    local first=true
    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        _wf_read_step "$name" "$step"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            output+=","
        fi

        # Build depends array
        local deps_json="[]"
        if [[ ${#_step_depends[@]} -gt 0 ]]; then
            deps_json="["
            local dfirst=true
            for dep in "${_step_depends[@]}"; do
                if [[ "$dfirst" == "true" ]]; then
                    dfirst=false
                else
                    deps_json+=","
                fi
                deps_json+="\"$(_wf_json_escape "$dep")\""
            done
            deps_json+="]"
        fi

        output+="{\"name\":\"$(_wf_json_escape "$step")\""
        output+=",\"command\":\"$(_wf_json_escape "$_step_command")\""
        output+=",\"depends\":$deps_json}"
    done < <(_wf_list_steps "$name")

    output+="]}"

    if [[ -n "$file" ]]; then
        printf '%s' "$output" > "$file"
        _wf_log info "Workflow '$name' exported to '$file'"
    else
        printf '%s' "$output"
    fi

    return 0
}

# Import workflow definition from JSON file
# Usage: workflow_import FILE
workflow_import() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        _wf_log error "workflow_import: file path required"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _wf_log error "workflow_import: file '$file' not found"
        return 1
    fi

    local content
    content=$(<"$file")

    # Parse workflow name
    local name=""
    if [[ "$content" =~ \"name\":\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$name" ]]; then
        _wf_log error "workflow_import: could not parse workflow name from file"
        return 1
    fi

    # Define the workflow
    workflow_define "$name" || return 1

    # Parse steps array - extract individual step objects
    # Match steps array content
    local steps_content=""
    if [[ "$content" =~ \"steps\":\[(.+)\]$ ]]; then
        steps_content="${BASH_REMATCH[1]}"
    elif [[ "$content" =~ \"steps\":\[(.+)\]\} ]]; then
        steps_content="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$steps_content" ]]; then
        _wf_log warn "workflow_import: no steps found in file"
        return 0
    fi

    # Parse each step object - simple state machine
    # We process steps in order, handling the {"name":"...","command":"...","depends":[...]} pattern
    local -a step_names=()
    local -a step_commands=()
    local -a step_deps=()

    # Extract step objects by finding balanced braces
    local remaining="$steps_content"
    while [[ -n "$remaining" ]]; do
        # Find next object start
        if [[ ! "$remaining" =~ \{(.*) ]]; then
            break
        fi
        remaining="${BASH_REMATCH[1]}"

        # Find matching close brace (simple: no nested objects expected)
        local obj_content=""
        if [[ "$remaining" =~ ^([^}]*)\}(.*) ]]; then
            obj_content="${BASH_REMATCH[1]}"
            remaining="${BASH_REMATCH[2]}"
        else
            break
        fi

        # Parse fields from obj_content
        local sname="" scmd="" sdeps=""
        if [[ "$obj_content" =~ \"name\":\"([^\"]+)\" ]]; then
            sname="${BASH_REMATCH[1]}"
        fi
        if [[ "$obj_content" =~ \"command\":\"([^\"]+)\" ]]; then
            scmd="${BASH_REMATCH[1]}"
        fi
        if [[ "$obj_content" =~ \"depends\":\[([^\]]*)\] ]]; then
            sdeps="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$sname" && -n "$scmd" ]]; then
            step_names+=("$sname")
            step_commands+=("$scmd")
            step_deps+=("$sdeps")
        fi
    done

    # Add steps in order (deps must be added before dependents)
    local i=0
    while [[ $i -lt ${#step_names[@]} ]]; do
        local sname="${step_names[$i]}"
        local scmd="${step_commands[$i]}"
        local sdeps="${step_deps[$i]}"

        # Parse dependency strings
        local -a dep_array=()
        if [[ -n "$sdeps" ]]; then
            while [[ "$sdeps" =~ \"([^\"]+)\" ]]; do
                dep_array+=("${BASH_REMATCH[1]}")
                sdeps="${sdeps#*\"${BASH_REMATCH[1]}\"}"
            done
        fi

        # Write step directly (bypassing workflow_step validation since we import in order)
        _wf_write_step "$name" "$sname" "$scmd" "$_MAINFRAME_WF_STATUS_PENDING" "${dep_array[@]}"

        i=$(( i + 1 ))
    done

    _wf_log info "Workflow '$name' imported from '$file' (${#step_names[@]} steps)"
    return 0
}

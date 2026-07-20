#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/taskstate.sh - Resumable Task State Machines
# =============================================================================
# Description: Persistent checkpointing and resumable multi-step task execution
#              for AI agents that get interrupted. Tasks survive process death,
#              session loss, and system restarts. Completed steps are skipped
#              on resume, enabling reliable long-running workflows.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TASKSTATE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TASKSTATE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Root directory for all task state storage
MAINFRAME_TASK_DIR="${MAINFRAME_TASK_DIR:-${HOME}/.mainframe/tasks}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Currently active task ID (set by task_create or task_resume)
_TASKSTATE_CURRENT_ID=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_task_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "taskstate" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[taskstate] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

# Generate 8-character random hex ID
_task_gen_id() {
    local id
    id=$(od -An -tx1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 8 ]]; then
        # Fallback: use RANDOM + PID + date
        printf '%04x%04x' "$$" "$RANDOM"
        return
    fi
    printf '%s' "${id:0:8}"
}

# Get epoch seconds
_task_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# ISO 8601 timestamp
_task_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
}

# Get the state directory for a task
_task_dir() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"
    printf '%s/%s' "$MAINFRAME_TASK_DIR" "$id"
}

# Escape a string for safe JSON embedding
_task_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)    result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

# Read a JSON field from a file (simple top-level string extraction)
_task_json_get() {
    local file="$1"
    local key="$2"

    [[ -f "$file" ]] || return 1
    local content
    content=$(<"$file")

    # String values
    if [[ "$content" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Numeric values
    if [[ "$content" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Boolean/null
    if [[ "$content" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false|null) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Write the manifest file atomically
_task_write_manifest() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local manifest="${dir}/manifest.json"
    local name description status created_at updated_at

    name=$(_task_json_get "$manifest" "name") || name=""
    description=$(_task_json_get "$manifest" "description") || description=""
    status=$(_task_json_get "$manifest" "status") || status="pending"
    created_at=$(_task_json_get "$manifest" "created_at") || created_at=""
    updated_at=$(_task_timestamp)

    # Apply overrides from args
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            name=*) name="${1#name=}" ;;
            description=*) description="${1#description=}" ;;
            status=*) status="${1#status=}" ;;
            created_at=*) created_at="${1#created_at=}" ;;
        esac
        shift
    done

    local escaped_name escaped_desc
    escaped_name=$(_task_json_escape "$name")
    escaped_desc=$(_task_json_escape "$description")

    local content
    content=$(printf '{"id":"%s","name":"%s","description":"%s","status":"%s","created_at":"%s","updated_at":"%s"}' \
        "$id" "$escaped_name" "$escaped_desc" "$status" "$created_at" "$updated_at")

    _task_atomic_write "$manifest" "$content"
}

# Atomic write using temp file + rename (same filesystem guarantees atomicity)
# Usage: _task_atomic_write "path" "content" [--no-newline]
_task_atomic_write() {
    local target="$1"
    local content="$2"
    local no_newline="${3:-}"
    local tmpfile="${target}.tmp.$$"

    if [[ "$no_newline" == "--no-newline" ]]; then
        printf '%s' "$content" > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    else
        printf '%s\n' "$content" > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    fi
    mv -f "$tmpfile" "$target" || { rm -f "$tmpfile"; return 1; }
}

# Read steps.json and extract step info
# Sets: _TASK_STEPS_RAW (raw file content)
_task_read_steps() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local steps_file="${dir}/steps.json"

    if [[ -f "$steps_file" ]]; then
        _TASK_STEPS_RAW=$(<"$steps_file")
    else
        _TASK_STEPS_RAW="[]"
    fi
}

# Get step status from steps.json
# Usage: _task_get_step_field "step_name" "field"
_task_get_step_field() {
    local step_name="$1"
    local field="$2"
    local id="${3:-$_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local steps_file="${dir}/steps.json"

    [[ -f "$steps_file" ]] || return 1
    local content
    content=$(<"$steps_file")

    # Find the step entry and extract the field
    # Steps are stored as: {"name":"X","field":"val",...}
    # We extract by finding the step block first
    local step_block=""
    local in_step=false
    local depth=0
    local i char
    local current_block=""

    for ((i=0; i<${#content}; i++)); do
        char="${content:i:1}"

        if [[ "$char" == "{" ]]; then
            depth=$(( depth + 1 ))
            if [[ $depth -eq 1 ]]; then
                current_block="{"
                continue
            fi
        elif [[ "$char" == "}" ]]; then
            if [[ $depth -eq 1 ]]; then
                current_block+="}"
                # Check if this block matches our step name
                if [[ "$current_block" =~ \"name\"[[:space:]]*:[[:space:]]*\"$step_name\" ]]; then
                    step_block="$current_block"
                    break
                fi
                current_block=""
            fi
            depth=$(( depth - 1 ))
            continue
        fi

        if [[ $depth -ge 1 ]]; then
            current_block+="$char"
        fi
    done

    [[ -z "$step_block" ]] && return 1

    # Extract the requested field from the step block
    if [[ "$step_block" =~ \"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try numeric
    if [[ "$step_block" =~ \"$field\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try boolean/null
    if [[ "$step_block" =~ \"$field\"[[:space:]]*:[[:space:]]*(true|false|null) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Update or add a step in steps.json
_task_update_step() {
    local step_name="$1"
    shift
    local id="${_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local steps_file="${dir}/steps.json"

    # Parse update fields
    local -A updates=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            *=*) updates["${1%%=*}"]="${1#*=}" ;;
        esac
        shift
    done

    # Read existing steps or initialize empty
    local content="[]"
    [[ -f "$steps_file" ]] && content=$(<"$steps_file")

    # Check if step already exists
    local step_exists=false
    if [[ "$content" =~ \"name\"[[:space:]]*:[[:space:]]*\"$step_name\" ]]; then
        step_exists=true
    fi

    if $step_exists; then
        # Rebuild the steps array with the updated step
        local new_content="["
        local first=true
        local in_step=false
        local depth=0
        local i char
        local current_block=""

        for ((i=0; i<${#content}; i++)); do
            char="${content:i:1}"

            if [[ "$char" == "{" ]]; then
                depth=$(( depth + 1 ))
                if [[ $depth -eq 1 ]]; then
                    current_block="{"
                    continue
                fi
            elif [[ "$char" == "}" ]]; then
                if [[ $depth -eq 1 ]]; then
                    current_block+="}"
                    # Output this step (modified or not)
                    $first || new_content+=","
                    first=false

                    if [[ "$current_block" =~ \"name\"[[:space:]]*:[[:space:]]*\"$step_name\" ]]; then
                        # Rebuild this step with updates
                        local step_json
                        step_json=$(_task_rebuild_step "$current_block" updates)
                        new_content+="$step_json"
                    else
                        new_content+="$current_block"
                    fi
                    current_block=""
                fi
                depth=$(( depth - 1 ))
                continue
            fi

            if [[ $depth -ge 1 ]]; then
                current_block+="$char"
            fi
        done

        new_content+="]"
        _task_locked_write "$steps_file" "$new_content"
    else
        # Add new step entry
        local desc="${updates[description]:-}"
        local status="${updates[status]:-pending}"
        local started_at="${updates[started_at]:-}"
        local completed_at="${updates[completed_at]:-}"
        local result_data="${updates[result]:-}"

        local escaped_name escaped_desc escaped_result
        escaped_name=$(_task_json_escape "$step_name")
        escaped_desc=$(_task_json_escape "$desc")
        escaped_result=$(_task_json_escape "$result_data")

        local step_json
        step_json=$(printf '{"name":"%s","description":"%s","status":"%s","started_at":"%s","completed_at":"%s","result":"%s"}' \
            "$escaped_name" "$escaped_desc" "$status" "$started_at" "$completed_at" "$escaped_result")

        # Append to existing array
        local new_content
        if [[ "$content" == "[]" ]]; then
            new_content="[${step_json}]"
        else
            # Remove trailing ] and append
            new_content="${content%]},${step_json}]"
        fi
        _task_locked_write "$steps_file" "$new_content"
    fi
}

# Rebuild a step JSON block with updated fields
_task_rebuild_step() {
    local block="$1"
    local -n _updates_ref=$2

    # Extract existing fields
    local name desc status started_at completed_at result
    [[ "$block" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && name="${BASH_REMATCH[1]}" || name=""
    [[ "$block" =~ \"description\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && desc="${BASH_REMATCH[1]}" || desc=""
    [[ "$block" =~ \"status\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && status="${BASH_REMATCH[1]}" || status="pending"
    [[ "$block" =~ \"started_at\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && started_at="${BASH_REMATCH[1]}" || started_at=""
    [[ "$block" =~ \"completed_at\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && completed_at="${BASH_REMATCH[1]}" || completed_at=""
    [[ "$block" =~ \"result\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && result="${BASH_REMATCH[1]}" || result=""

    # Apply updates
    [[ -n "${_updates_ref[description]+x}" ]] && desc="${_updates_ref[description]}"
    [[ -n "${_updates_ref[status]+x}" ]] && status="${_updates_ref[status]}"
    [[ -n "${_updates_ref[started_at]+x}" ]] && started_at="${_updates_ref[started_at]}"
    [[ -n "${_updates_ref[completed_at]+x}" ]] && completed_at="${_updates_ref[completed_at]}"
    [[ -n "${_updates_ref[result]+x}" ]] && result="${_updates_ref[result]}"

    local escaped_name escaped_desc escaped_result
    escaped_name=$(_task_json_escape "$name")
    escaped_desc=$(_task_json_escape "$desc")
    escaped_result=$(_task_json_escape "$result")

    printf '{"name":"%s","description":"%s","status":"%s","started_at":"%s","completed_at":"%s","result":"%s"}' \
        "$escaped_name" "$escaped_desc" "$status" "$started_at" "$completed_at" "$escaped_result"
}

# Write with flock for concurrent safety
# Usage: _task_locked_write "path" "content" [--no-newline]
_task_locked_write() {
    local target="$1"
    local content="$2"
    local flags="${3:-}"

    if command -v flock &>/dev/null; then
        (
            flock -x 200
            _task_atomic_write "$target" "$content" "$flags"
        ) 200>"${target}.lock"
        rm -f "${target}.lock" 2>/dev/null
    else
        _task_atomic_write "$target" "$content" "$flags"
    fi
}

# Count steps by status
_task_count_steps() {
    local status="$1"
    local id="${2:-$_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local steps_file="${dir}/steps.json"

    [[ -f "$steps_file" ]] || { printf '0'; return; }

    local content count
    content=$(<"$steps_file")

    if [[ "$status" == "total" ]]; then
        # Count all step entries
        count=0
        local tmp="$content"
        while [[ "$tmp" =~ \"name\"[[:space:]]*: ]]; do
            count=$(( count + 1 ))
            tmp="${tmp#*\"name\"*:}"
        done
        printf '%d' "$count"
    else
        count=0
        local tmp="$content"
        while [[ "$tmp" =~ \"status\"[[:space:]]*:[[:space:]]*\"$status\" ]]; do
            count=$(( count + 1 ))
            tmp="${tmp#*\"status\"*:*\"$status\"}"
        done
        printf '%d' "$count"
    fi
}

# Get list of step names
_task_step_names() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"
    local dir
    dir=$(_task_dir "$id")
    local steps_file="${dir}/steps.json"

    [[ -f "$steps_file" ]] || return

    local content
    content=$(<"$steps_file")

    # Extract all step names
    local tmp="$content"
    while [[ "$tmp" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; do
        printf '%s\n' "${BASH_REMATCH[1]}"
        tmp="${tmp#*\"name\"*:*\"${BASH_REMATCH[1]}\"}"
    done
}

# Update task status based on step states
_task_recalculate_status() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"
    local total completed failed running

    total=$(_task_count_steps "total" "$id")
    completed=$(_task_count_steps "completed" "$id")
    failed=$(_task_count_steps "failed" "$id")
    running=$(_task_count_steps "running" "$id")

    local skipped
    skipped=$(_task_count_steps "skipped" "$id")

    local done_count=$((completed + skipped))

    local new_status
    if [[ $failed -gt 0 ]]; then
        new_status="failed"
    elif [[ $running -gt 0 ]]; then
        new_status="running"
    elif [[ $total -gt 0 && $done_count -eq $total ]]; then
        new_status="completed"
    elif [[ $done_count -gt 0 ]]; then
        new_status="running"
    else
        new_status="pending"
    fi

    _task_write_manifest "$id" "status=$new_status"
}

# Find task ID by name
_task_find_by_name() {
    local name="$1"

    [[ -d "$MAINFRAME_TASK_DIR" ]] || return 1

    local dir_entry manifest task_name
    for dir_entry in "$MAINFRAME_TASK_DIR"/*/; do
        [[ -d "$dir_entry" ]] || continue
        manifest="${dir_entry}manifest.json"
        [[ -f "$manifest" ]] || continue

        task_name=$(_task_json_get "$manifest" "name") || continue
        if [[ "$task_name" == "$name" ]]; then
            local id="${dir_entry%/}"
            id="${id##*/}"
            printf '%s' "$id"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# TASK LIFECYCLE
# =============================================================================

# Create a new task (or resume existing by name)
# Usage: task_create "task_name" ["description"]
# Returns: task ID on stdout, sets _TASKSTATE_CURRENT_ID
# Note: If capturing output with $(), set _TASKSTATE_CURRENT_ID="$id" after,
#       since subshell variable assignments do not propagate to parent.
task_create() {
    local name="$1"
    local description="${2:-}"

    if [[ -z "$name" ]]; then
        _task_log error "task_create: task name required"
        return 1
    fi

    # Check if task with this name already exists
    local existing_id
    if existing_id=$(_task_find_by_name "$name"); then
        _task_log info "task already exists with name '$name', resuming: $existing_id"
        _TASKSTATE_CURRENT_ID="$existing_id"
        printf '%s' "$existing_id"
        return 0
    fi

    # Generate new ID and create state directory
    local id
    id=$(_task_gen_id)

    local dir="${MAINFRAME_TASK_DIR}/${id}"
    mkdir -p "${dir}/data" "${dir}/files" "${dir}/checkpoints" "${dir}/steps" || {
        _task_log error "task_create: failed to create state directory"
        return 1
    }

    # Initialize steps file
    _task_atomic_write "${dir}/steps.json" "[]"

    # Set current task
    _TASKSTATE_CURRENT_ID="$id"

    # Write manifest
    local created_at
    created_at=$(_task_timestamp)
    _task_write_manifest "$id" "name=$name" "description=$description" "status=pending" "created_at=$created_at"

    _task_log info "created task '$name' with id: $id"
    printf '%s' "$id"
}

# Resume an existing task by ID or name
# Usage: task_resume "task_id_or_name"
# Returns: 0 if found, 1 if not
task_resume() {
    local identifier="$1"

    if [[ -z "$identifier" ]]; then
        _task_log error "task_resume: task ID or name required"
        return 1
    fi

    # Try as ID first
    local dir="${MAINFRAME_TASK_DIR}/${identifier}"
    if [[ -d "$dir" && -f "${dir}/manifest.json" ]]; then
        _TASKSTATE_CURRENT_ID="$identifier"
        _task_log info "resumed task: $identifier"
        return 0
    fi

    # Try as name
    local id
    if id=$(_task_find_by_name "$identifier"); then
        _TASKSTATE_CURRENT_ID="$id"
        _task_log info "resumed task '$identifier': $id"
        return 0
    fi

    _task_log error "task_resume: task not found: $identifier"
    return 1
}

# List all tasks
# Usage: task_list [--status pending|running|completed|failed]
# Output: id name status created_at step_progress
task_list() {
    local filter_status=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) filter_status="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -d "$MAINFRAME_TASK_DIR" ]] || return 0

    local dir_entry manifest
    for dir_entry in "$MAINFRAME_TASK_DIR"/*/; do
        [[ -d "$dir_entry" ]] || continue
        manifest="${dir_entry}manifest.json"
        [[ -f "$manifest" ]] || continue

        local id="${dir_entry%/}"
        id="${id##*/}"

        local name status created_at
        name=$(_task_json_get "$manifest" "name") || name=""
        status=$(_task_json_get "$manifest" "status") || status="unknown"
        created_at=$(_task_json_get "$manifest" "created_at") || created_at=""

        # Apply filter
        if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
            continue
        fi

        local total completed
        total=$(_task_count_steps "total" "$id")
        completed=$(_task_count_steps "completed" "$id")
        local skipped
        skipped=$(_task_count_steps "skipped" "$id")
        local done_count=$((completed + skipped))

        printf '%s\t%s\t%s\t%s\t%d/%d\n' "$id" "$name" "$status" "$created_at" "$done_count" "$total"
    done
}

# Get current task info as JSON
# Usage: task_info ["task_id"]
task_info() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"

    if [[ -z "$id" ]]; then
        _task_log error "task_info: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir "$id")
    local manifest="${dir}/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        _task_log error "task_info: task not found: $id"
        return 1
    fi

    cat "$manifest"
}

# Delete a task and its state
# Usage: task_delete "task_id"
task_delete() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"

    if [[ -z "$id" ]]; then
        _task_log error "task_delete: task ID required"
        return 1
    fi

    local dir
    dir=$(_task_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _task_log error "task_delete: task not found: $id"
        return 1
    fi

    rm -rf "$dir"
    _task_log info "deleted task: $id"

    # Clear current if this was active
    if [[ "$_TASKSTATE_CURRENT_ID" == "$id" ]]; then
        _TASKSTATE_CURRENT_ID=""
    fi
}

# Clean up old completed tasks (older than N days)
# Usage: task_cleanup [days]  # default: 7
task_cleanup() {
    local max_days="${1:-7}"
    local now
    now=$(_task_epoch)
    local max_seconds=$((max_days * 86400))
    local cleaned=0

    [[ -d "$MAINFRAME_TASK_DIR" ]] || return 0

    local dir_entry manifest
    for dir_entry in "$MAINFRAME_TASK_DIR"/*/; do
        [[ -d "$dir_entry" ]] || continue
        manifest="${dir_entry}manifest.json"
        [[ -f "$manifest" ]] || continue

        local status
        status=$(_task_json_get "$manifest" "status") || continue

        # Only clean completed or failed tasks
        [[ "$status" == "completed" || "$status" == "failed" ]] || continue

        # Check age using file modification time
        local mtime
        if [[ "$OSTYPE" == darwin* ]]; then
            mtime=$(stat -f '%m' "$manifest" 2>/dev/null) || continue
        else
            mtime=$(stat -c '%Y' "$manifest" 2>/dev/null) || continue
        fi

        local age=$((now - mtime))
        if [[ $age -gt $max_seconds ]]; then
            local id="${dir_entry%/}"
            id="${id##*/}"
            rm -rf "$dir_entry"
            cleaned=$(( cleaned + 1 ))
            _task_log debug "cleaned up task: $id (age: $((age / 86400))d)"
        fi
    done

    _task_log info "cleaned up $cleaned tasks older than ${max_days} days"
    printf '%d' "$cleaned"
}

# =============================================================================
# STEP MANAGEMENT
# =============================================================================

# Define/add a step for the current task
# Usage: task_add_step "step_name" ["description"]
task_add_step() {
    local step_name="$1"
    local description="${2:-}"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_add_step: no active task"
        return 1
    fi

    if [[ -z "$step_name" ]]; then
        _task_log error "task_add_step: step name required"
        return 1
    fi

    # Check if step already exists
    local existing_status
    if existing_status=$(_task_get_step_field "$step_name" "status"); then
        _task_log debug "step '$step_name' already exists with status: $existing_status"
        return 0
    fi

    _task_update_step "$step_name" "description=$description" "status=pending"
    _task_log debug "added step: $step_name"
}

# Execute a step (skips if already completed)
# Usage: task_step "step_name" command [args...]
# Returns: 0=success (or already done), 1=failed
task_step() {
    local step_name="$1"
    shift

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step: no active task"
        return 1
    fi

    if [[ -z "$step_name" ]]; then
        _task_log error "task_step: step name required"
        return 1
    fi

    # Check if already done
    local current_status
    current_status=$(_task_get_step_field "$step_name" "status" 2>/dev/null) || current_status=""

    if [[ "$current_status" == "completed" || "$current_status" == "skipped" ]]; then
        _task_log info "step '$step_name' already done, skipping"
        return 0
    fi

    # Ensure step exists
    if [[ -z "$current_status" ]]; then
        _task_update_step "$step_name" "status=pending"
    fi

    # Mark as running
    local started_at
    started_at=$(_task_timestamp)
    _task_update_step "$step_name" "status=running" "started_at=$started_at"
    _task_recalculate_status

    # Create output capture file
    local dir
    dir=$(_task_dir)
    local output_file="${dir}/steps/${step_name}.out"
    mkdir -p "${dir}/steps"

    # Execute the command, capturing stdout
    local rc=0
    "$@" > "$output_file" 2>&1 || rc=$?

    local completed_at
    completed_at=$(_task_timestamp)

    if [[ $rc -eq 0 ]]; then
        # Read captured output for result field (truncated)
        local result_data=""
        if [[ -f "$output_file" ]]; then
            result_data=$(head -c 1024 "$output_file" | tr '\n' ' ')
        fi
        _task_update_step "$step_name" "status=completed" "completed_at=$completed_at" "result=$result_data"
        _task_log info "step '$step_name' completed"
    else
        local error_data=""
        if [[ -f "$output_file" ]]; then
            error_data=$(tail -c 512 "$output_file" | tr '\n' ' ')
        fi
        _task_update_step "$step_name" "status=failed" "completed_at=$completed_at" "result=$error_data"
        _task_log error "step '$step_name' failed (exit code: $rc)"
    fi

    _task_recalculate_status
    return $rc
}

# Mark step as completed manually
# Usage: task_step_complete "step_name" ["result_data"]
task_step_complete() {
    local step_name="$1"
    local result_data="${2:-}"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step_complete: no active task"
        return 1
    fi

    local completed_at
    completed_at=$(_task_timestamp)
    _task_update_step "$step_name" "status=completed" "completed_at=$completed_at" "result=$result_data"
    _task_recalculate_status
    _task_log info "step '$step_name' marked completed"
}

# Mark step as failed manually
# Usage: task_step_fail "step_name" ["error_message"]
task_step_fail() {
    local step_name="$1"
    local error_msg="${2:-}"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step_fail: no active task"
        return 1
    fi

    local completed_at
    completed_at=$(_task_timestamp)
    _task_update_step "$step_name" "status=failed" "completed_at=$completed_at" "result=$error_msg"
    _task_recalculate_status
    _task_log error "step '$step_name' marked failed"
}

# Mark step as skipped
# Usage: task_step_skip "step_name" ["reason"]
task_step_skip() {
    local step_name="$1"
    local reason="${2:-}"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step_skip: no active task"
        return 1
    fi

    local completed_at
    completed_at=$(_task_timestamp)
    _task_update_step "$step_name" "status=skipped" "completed_at=$completed_at" "result=$reason"
    _task_recalculate_status
    _task_log debug "step '$step_name' skipped: $reason"
}

# Check step status
# Usage: task_step_status "step_name"
# Output: pending|running|completed|failed|skipped
task_step_status() {
    local step_name="$1"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step_status: no active task"
        return 1
    fi

    local status
    status=$(_task_get_step_field "$step_name" "status") || {
        printf 'unknown'
        return 1
    }
    printf '%s' "$status"
}

# Check if step is done (completed or skipped)
# Usage: task_step_is_done "step_name"
# Returns: 0 if completed or skipped, 1 otherwise
task_step_is_done() {
    local step_name="$1"
    local status
    status=$(task_step_status "$step_name") || return 1

    [[ "$status" == "completed" || "$status" == "skipped" ]]
}

# Get step result (stored output from when it ran)
# Usage: task_step_result "step_name"
task_step_result() {
    local step_name="$1"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_step_result: no active task"
        return 1
    fi

    # First try the output file
    local dir
    dir=$(_task_dir)
    local output_file="${dir}/steps/${step_name}.out"

    if [[ -f "$output_file" ]]; then
        cat "$output_file"
        return 0
    fi

    # Fall back to result field in steps.json
    local result
    result=$(_task_get_step_field "$step_name" "result") || return 1
    printf '%s' "$result"
}

# =============================================================================
# STATE/DATA STORAGE
# =============================================================================

# Store arbitrary key-value data with the task
# Usage: task_set "key" "value"
task_set() {
    local key="$1"
    local value="$2"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_set: no active task"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _task_log error "task_set: key required"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local data_file="${dir}/data/${key}"

    mkdir -p "${dir}/data"
    _task_locked_write "$data_file" "$value" "--no-newline"
}

# Get a stored value
# Usage: task_get "key" ["default"]
task_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_get: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local data_file="${dir}/data/${key}"

    if [[ -f "$data_file" ]]; then
        cat "$data_file"
    else
        printf '%s' "$default"
    fi
}

# Check if key exists
# Usage: task_has "key"
# Returns: 0 if exists, 1 if not
task_has() {
    local key="$1"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        return 1
    fi

    local dir
    dir=$(_task_dir)
    [[ -f "${dir}/data/${key}" ]]
}

# List all stored keys
# Usage: task_keys
task_keys() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_keys: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local data_dir="${dir}/data"

    [[ -d "$data_dir" ]] || return 0

    local entry
    for entry in "$data_dir"/*; do
        [[ -f "$entry" ]] || continue
        printf '%s\n' "${entry##*/}"
    done
}

# Store a file with the task
# Usage: task_store_file "key" "/path/to/file"
task_store_file() {
    local key="$1"
    local source_path="$2"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_store_file: no active task"
        return 1
    fi

    if [[ ! -f "$source_path" ]]; then
        _task_log error "task_store_file: source file not found: $source_path"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    mkdir -p "${dir}/files"
    cp -f "$source_path" "${dir}/files/${key}"
}

# Retrieve a stored file
# Usage: task_retrieve_file "key" "/output/path"
task_retrieve_file() {
    local key="$1"
    local output_path="$2"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_retrieve_file: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local stored="${dir}/files/${key}"

    if [[ ! -f "$stored" ]]; then
        _task_log error "task_retrieve_file: file not found for key: $key"
        return 1
    fi

    cp -f "$stored" "$output_path"
}

# =============================================================================
# PROGRESS & REPORTING
# =============================================================================

# Get progress as fraction
# Usage: task_progress
# Output: "3/10" (completed_and_skipped / total steps)
task_progress() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        printf '0/0'
        return 1
    fi

    local total completed skipped
    total=$(_task_count_steps "total")
    completed=$(_task_count_steps "completed")
    skipped=$(_task_count_steps "skipped")
    local done_count=$((completed + skipped))

    printf '%d/%d' "$done_count" "$total"
}

# Get progress as percentage
# Usage: task_progress_pct
# Output: "30" (integer percentage)
task_progress_pct() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        printf '0'
        return 1
    fi

    local total completed skipped
    total=$(_task_count_steps "total")
    completed=$(_task_count_steps "completed")
    skipped=$(_task_count_steps "skipped")
    local done_count=$((completed + skipped))

    if [[ $total -eq 0 ]]; then
        printf '0'
    else
        printf '%d' $(( (done_count * 100) / total ))
    fi
}

# Get summary as JSON
# Usage: task_summary ["task_id"]
task_summary() {
    local id="${1:-$_TASKSTATE_CURRENT_ID}"

    if [[ -z "$id" ]]; then
        _task_log error "task_summary: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir "$id")
    local manifest="${dir}/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        _task_log error "task_summary: task not found: $id"
        return 1
    fi

    local name status
    name=$(_task_json_get "$manifest" "name") || name=""
    status=$(_task_json_get "$manifest" "status") || status="unknown"

    local total completed failed skipped pending running
    total=$(_task_count_steps "total" "$id")
    completed=$(_task_count_steps "completed" "$id")
    failed=$(_task_count_steps "failed" "$id")
    skipped=$(_task_count_steps "skipped" "$id")
    pending=$(_task_count_steps "pending" "$id")
    running=$(_task_count_steps "running" "$id")

    # Build data section from key-value store
    local data_json="{"
    local data_first=true
    local data_dir="${dir}/data"
    if [[ -d "$data_dir" ]]; then
        local entry
        for entry in "$data_dir"/*; do
            [[ -f "$entry" ]] || continue
            local k="${entry##*/}"
            local v
            v=$(<"$entry")
            local ek ev
            ek=$(_task_json_escape "$k")
            ev=$(_task_json_escape "$v")
            $data_first || data_json+=","
            data_first=false
            data_json+="\"${ek}\":\"${ev}\""
        done
    fi
    data_json+="}"

    local escaped_name
    escaped_name=$(_task_json_escape "$name")

    printf '{"id":"%s","name":"%s","status":"%s","steps":{"total":%d,"completed":%d,"failed":%d,"skipped":%d,"pending":%d,"running":%d},"data":%s}' \
        "$id" "$escaped_name" "$status" \
        "$total" "$completed" "$failed" "$skipped" "$pending" "$running" \
        "$data_json"
}

# Get a list of remaining (not-yet-done) steps
# Usage: task_remaining
# Output: One step name per line
task_remaining() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_remaining: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local steps_file="${dir}/steps.json"
    [[ -f "$steps_file" ]] || return 0

    local content
    content=$(<"$steps_file")

    # Parse each step and check status
    local depth=0
    local current_block=""
    local i char

    for ((i=0; i<${#content}; i++)); do
        char="${content:i:1}"

        if [[ "$char" == "{" ]]; then
            depth=$(( depth + 1 ))
            if [[ $depth -eq 1 ]]; then
                current_block="{"
                continue
            fi
        elif [[ "$char" == "}" ]]; then
            if [[ $depth -eq 1 ]]; then
                current_block+="}"
                # Check if this step is not done
                local step_status=""
                [[ "$current_block" =~ \"status\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && step_status="${BASH_REMATCH[1]}"
                if [[ "$step_status" != "completed" && "$step_status" != "skipped" ]]; then
                    [[ "$current_block" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && printf '%s\n' "${BASH_REMATCH[1]}"
                fi
                current_block=""
            fi
            depth=$(( depth - 1 ))
            continue
        fi

        if [[ $depth -ge 1 ]]; then
            current_block+="$char"
        fi
    done
}

# Get elapsed time for current task (seconds since creation)
# Usage: task_elapsed
task_elapsed() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        printf '0'
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local manifest="${dir}/manifest.json"

    # Use file creation time as approximation
    local mtime now
    if [[ "$OSTYPE" == darwin* ]]; then
        mtime=$(stat -f '%m' "$manifest" 2>/dev/null) || mtime=0
    else
        mtime=$(stat -c '%Y' "$manifest" 2>/dev/null) || mtime=0
    fi

    # Use birth time (creation) if available, otherwise use mtime of the directory
    local dir_time
    dir=$(_task_dir)
    if [[ "$OSTYPE" == darwin* ]]; then
        dir_time=$(stat -f '%B' "$dir" 2>/dev/null) || dir_time=$mtime
    else
        dir_time=$(stat -c '%W' "$dir" 2>/dev/null) || dir_time=0
        # %W returns 0 if birth time is not available, use dir mtime
        [[ "$dir_time" == "0" ]] && dir_time=$(stat -c '%Y' "$dir" 2>/dev/null)
    fi

    now=$(_task_epoch)
    local elapsed=$((now - dir_time))
    [[ $elapsed -lt 0 ]] && elapsed=0
    printf '%d' "$elapsed"
}

# =============================================================================
# CHECKPOINTING
# =============================================================================

# Save a checkpoint (snapshot of current state with label)
# Usage: task_checkpoint "label"
task_checkpoint() {
    local label="$1"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_checkpoint: no active task"
        return 1
    fi

    if [[ -z "$label" ]]; then
        _task_log error "task_checkpoint: label required"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local cp_dir="${dir}/checkpoints/${label}"

    mkdir -p "$cp_dir"

    # Copy manifest and steps
    [[ -f "${dir}/manifest.json" ]] && cp -f "${dir}/manifest.json" "${cp_dir}/manifest.json"
    [[ -f "${dir}/steps.json" ]] && cp -f "${dir}/steps.json" "${cp_dir}/steps.json"

    # Copy data directory
    if [[ -d "${dir}/data" ]]; then
        mkdir -p "${cp_dir}/data"
        cp -rf "${dir}/data/." "${cp_dir}/data/"
    fi

    _task_log info "checkpoint saved: $label"
}

# Restore to a previous checkpoint
# Usage: task_restore_checkpoint "label"
task_restore_checkpoint() {
    local label="$1"

    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_restore_checkpoint: no active task"
        return 1
    fi

    if [[ -z "$label" ]]; then
        _task_log error "task_restore_checkpoint: label required"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local cp_dir="${dir}/checkpoints/${label}"

    if [[ ! -d "$cp_dir" ]]; then
        _task_log error "task_restore_checkpoint: checkpoint not found: $label"
        return 1
    fi

    # Restore manifest and steps
    [[ -f "${cp_dir}/manifest.json" ]] && cp -f "${cp_dir}/manifest.json" "${dir}/manifest.json"
    [[ -f "${cp_dir}/steps.json" ]] && cp -f "${cp_dir}/steps.json" "${dir}/steps.json"

    # Restore data directory
    if [[ -d "${cp_dir}/data" ]]; then
        rm -rf "${dir}/data"
        mkdir -p "${dir}/data"
        cp -rf "${cp_dir}/data/." "${dir}/data/"
    fi

    _task_log info "checkpoint restored: $label"
}

# List checkpoints
# Usage: task_checkpoints
task_checkpoints() {
    if [[ -z "$_TASKSTATE_CURRENT_ID" ]]; then
        _task_log error "task_checkpoints: no active task"
        return 1
    fi

    local dir
    dir=$(_task_dir)
    local cp_dir="${dir}/checkpoints"

    [[ -d "$cp_dir" ]] || return 0

    local entry
    for entry in "$cp_dir"/*/; do
        [[ -d "$entry" ]] || continue
        local label="${entry%/}"
        label="${label##*/}"
        printf '%s\n' "$label"
    done
}

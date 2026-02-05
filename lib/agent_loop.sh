#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_loop.sh - Persistent Goal-Oriented Agent Loop System
# =============================================================================
# Description: Manages persistent, background AI agent execution with goal
#              tracking, multi-agent coordination, and human-in-the-loop.
# Version: 1.0.0
# Requires: Bash 4.0+, lib/json.sh, lib/proc.sh, lib/uap.sh, lib/state.sh
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_LOOP_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_LOOP_LOADED=1

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/json.sh"
fi
if [[ -z "${_MAINFRAME_PROC_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/proc.sh"
fi
if [[ -z "${_MAINFRAME_UAP_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/uap.sh"
fi
if [[ -z "${_MAINFRAME_STATE_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/state.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for agent loop state
AGENT_LOOP_DIR="${MAINFRAME_AGENT_LOOP_DIR:-${HOME}/.mainframe/agent_loops}"

# Default checkpoint interval (seconds)
AGENT_LOOP_CHECKPOINT_INTERVAL="${AGENT_LOOP_CHECKPOINT_INTERVAL:-60}"

# Default priority levels
declare -gA AGENT_LOOP_PRIORITIES=(
    [low]=10
    [normal]=5
    [high]=1
    [critical]=0
)

# Signal definitions
readonly AGENT_LOOP_SIGNAL_PAUSE=USR1
readonly AGENT_LOOP_SIGNAL_RESUME=USR2
readonly AGENT_LOOP_SIGNAL_CHECKPOINT=HUP

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Logging function
_agent_loop_log() {
    local level="$1"
    shift
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[agent_loop][%s] %s: %s\n' "$(date -Iseconds)" "$level" "$*" >&2
    fi
}

# Validate agent name (alphanumeric, dash, underscore only)
_agent_loop_validate_name() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [[ ${#name} -le 64 ]] || return 1
    return 0
}

# Get agent state directory
_agent_loop_state_dir() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name"
}

# Get agent PID file path
_agent_loop_pidfile() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name/agent.pid"
}

# Get agent state file path
_agent_loop_state_file() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name/state.json"
}

# Get agent checkpoint file path
_agent_loop_checkpoint_file() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name/checkpoint.json"
}

# Get agent log file path
_agent_loop_log_file() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name/log.jsonl"
}

# Get subtasks directory
_agent_loop_subtasks_dir() {
    local name="$1"
    printf '%s' "$AGENT_LOOP_DIR/$name/subtasks"
}

# Ensure agent directory structure exists
_agent_loop_ensure_dirs() {
    local name="$1"
    local state_dir
    state_dir=$(_agent_loop_state_dir "$name")
    mkdir -p "$state_dir/subtasks" || return 1
    chmod 700 "$state_dir"
}

# Generate timestamp
_agent_loop_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s
}

# Atomic write
_agent_loop_atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s' "$content" > "$tmp" && mv "$tmp" "$file"
}

# Read agent state
_agent_loop_read_state() {
    local name="$1"
    local state_file
    state_file=$(_agent_loop_state_file "$name")
    [[ -f "$state_file" ]] && cat "$state_file"
}

# Write agent state
_agent_loop_write_state() {
    local name="$1"
    local state="$2"
    local state_file
    state_file=$(_agent_loop_state_file "$name")
    _agent_loop_atomic_write "$state_file" "$state"
}

# Log activity to JSONL
_agent_loop_log_activity() {
    local name="$1"
    local event="$2"
    local data="${3:-{}}"
    local log_file
    log_file=$(_agent_loop_log_file "$name")
    
    local entry
    entry=$(json_object \
        "timestamp=$(_agent_loop_timestamp)" \
        "event=$event" \
        "data:raw=$data")
    
    printf '%s\n' "$entry" >> "$log_file"
}

# Get agent PID
_agent_loop_get_pid() {
    local name="$1"
    local pidfile
    pidfile=$(_agent_loop_pidfile "$name")
    [[ -f "$pidfile" ]] && cat "$pidfile" 2>/dev/null
}

# Check if agent is running
_agent_loop_is_running() {
    local name="$1"
    local pid
    pid=$(_agent_loop_get_pid "$name")
    [[ -n "$pid" ]] && proc_exists "$pid"
}

# Generate unique agent ID
_agent_loop_gen_id() {
    local name="$1"
    local timestamp
    timestamp=$(date +%s)
    local rand
    rand=$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 8)
    printf '%s_%s_%s' "$name" "$timestamp" "$rand"
}

# Calculate elapsed time
_agent_loop_elapsed() {
    local start_time="$1"
    local now
    now=$(date +%s)
    local elapsed=$((now - start_time))
    
    local hours=$((elapsed / 3600))
    local mins=$(((elapsed % 3600) / 60))
    local secs=$((elapsed % 60))
    
    if [[ $hours -gt 0 ]]; then
        printf '%dh%02dm' "$hours" "$mins"
    elif [[ $mins -gt 0 ]]; then
        printf '%dm%02ds' "$mins" "$secs"
    else
        printf '%ds' "$secs"
    fi
}

# =============================================================================
# AGENT PROCESS (INTERNAL)
# =============================================================================

# The actual agent process that runs in background
_agent_loop_process() {
    local name="$1"
    local goal="$2"
    local priority="${3:-normal}"
    local parent="${4:-}"
    
    local state_dir
    state_dir=$(_agent_loop_state_dir "$name")
    local start_time
    start_time=$(date +%s)
    
    # Set up signal handlers
    _agent_loop_paused=false
    _agent_loop_shutdown=false
    
    trap '_agent_loop_paused=true' "$AGENT_LOOP_SIGNAL_PAUSE"
    trap '_agent_loop_paused=false' "$AGENT_LOOP_SIGNAL_RESUME"
    trap '_agent_loop_checkpoint "$name"' "$AGENT_LOOP_SIGNAL_CHECKPOINT"
    trap '_agent_loop_shutdown=true' TERM INT
    
    # Initialize state
    local state
    state=$(json_object \
        "name=$name" \
        "agent_id=$(_agent_loop_gen_id "$name")" \
        "status=running" \
        "goal=$goal" \
        "priority=$priority" \
        "started=$(_agent_loop_timestamp)" \
        "start_time:number=$start_time" \
        "current_task=Initializing" \
        "progress:number=0" \
        "files_modified:raw=[]" \
        "subtasks_completed:number=0" \
        "subtasks_total:number=0" \
        "errors_encountered:number=0" \
        "parent=$parent" \
        "children:raw=[]")
    
    _agent_loop_write_state "$name" "$state"
    _agent_loop_log_activity "$name" "started" "{\"goal\":\"$goal\"}"
    
    # Main execution loop
    local iteration=0
    while ! $_agent_loop_shutdown; do
        # Check if paused
        if $_agent_loop_paused; then
            sleep 1
            continue
        fi
        
        # Simulate work (in real implementation, this would be actual agent work)
        ((iteration++))
        
        # Update progress periodically
        if ((iteration % 10 == 0)); then
            local progress=$((iteration % 100))
            local current_state
            current_state=$(_agent_loop_read_state "$name")
            
            # Update state with new progress
            if [[ -n "$current_state" ]]; then
                # Extract and update fields
                local new_state
                new_state=$(echo "$current_state" | sed "s/\"progress\":[0-9]*/\"progress\":$progress/")
                new_state=$(echo "$new_state" | sed "s/\"current_task\":\"[^\"]*\"/\"current_task\":\"Working on subtask $iteration\"/")
                _agent_loop_write_state "$name" "$new_state"
            fi
        fi
        
        # Periodic checkpoint
        if ((iteration % AGENT_LOOP_CHECKPOINT_INTERVAL == 0)); then
            _agent_loop_checkpoint "$name"
        fi
        
        # Simulate work cycle
        sleep 1
    done
    
    # Final checkpoint before exit
    _agent_loop_checkpoint "$name"
    
    # Update state to stopped
    local final_state
    final_state=$(_agent_loop_read_state "$name")
    if [[ -n "$final_state" ]]; then
        final_state=$(echo "$final_state" | sed 's/"status":"[^"]*"/"status":"stopped"/')
        final_state=$(echo "$final_state" | sed "s/\"stopped_at\":\"[^\"]*\"/\"stopped_at\":\"$(_agent_loop_timestamp)\"/")
        _agent_loop_write_state "$name" "$final_state"
    fi
    
    _agent_loop_log_activity "$name" "stopped" "{}"
    
    # Clean up PID file
    rm -f "$(_agent_loop_pidfile "$name")"
}

# Create checkpoint
_agent_loop_checkpoint() {
    local name="$1"
    local state
    state=$(_agent_loop_read_state "$name")
    [[ -z "$state" ]] && return 1
    
    local checkpoint_file
    checkpoint_file=$(_agent_loop_checkpoint_file "$name")
    
    # Add checkpoint metadata
    local checkpoint
    checkpoint=$(json_object \
        "checkpoint_time=$(_agent_loop_timestamp)" \
        "state:raw=$state")
    
    _agent_loop_atomic_write "$checkpoint_file" "$checkpoint"
    _agent_loop_log_activity "$name" "checkpoint" "{}"
}

# =============================================================================
# PUBLIC API - AGENT LIFECYCLE
# =============================================================================

# @desc Start a new agent loop
# @usage agent_loop_start "name" --goal "description" [--priority N]
# @returns JSON with agent info on success
agent_loop_start() {
    local name="$1"
    shift
    
    local goal=""
    local priority="normal"
    local parent=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --goal)
                goal="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            --parent)
                parent="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate name
    if ! _agent_loop_validate_name "$name"; then
        json_object \
            "success:bool=false" \
            "error=Invalid agent name (alphanumeric, dash, underscore, max 64 chars)"
        return 1
    fi
    
    # Validate goal
    if [[ -z "$goal" ]]; then
        json_object \
            "success:bool=false" \
            "error=Goal is required (use --goal)"
        return 1
    fi
    
    # Check if already running
    if _agent_loop_is_running "$name"; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' is already running" \
            "pid=$(_agent_loop_get_pid "$name")"
        return 1
    fi
    
    # Ensure directories
    _agent_loop_ensure_dirs "$name" || {
        json_object \
            "success:bool=false" \
            "error=Failed to create agent directories"
        return 1
    }
    
    # Start the agent process with nohup-style persistence
    (
        # Close stdin, redirect stdout/stderr to log
        exec 0<&- 1>>"$AGENT_LOOP_DIR/$name/output.log" 2>&1
        # Run agent process
        _agent_loop_process "$name" "$goal" "$priority" "$parent"
    ) &
    
    local pid=$!
    
    # Write PID file
    pidfile_create "$(_agent_loop_pidfile "$name")" "$pid"
    
    # Wait a moment to verify it started
    sleep 0.5
    if ! proc_exists "$pid"; then
        json_object \
            "success:bool=false" \
            "error=Agent process failed to start"
        return 1
    fi
    
    # If we have a parent, add this child to parent's state
    if [[ -n "$parent" ]] && _agent_loop_is_running "$parent"; then
        local parent_state
        parent_state=$(_agent_loop_read_state "$parent")
        if [[ -n "$parent_state" ]]; then
            # Extract current children and add new one
            local children
            children=$(json_get "$parent_state" "children" 2>/dev/null || echo "[]")
            # Simple array append (naive JSON manipulation)
            children="${children%]}, \"$name\"]"
            [[ "$children" == "[]" ]] && children="[\"$name\"]"
            parent_state=$(echo "$parent_state" | sed "s/\"children\":\[[^]]*\]/\"children\":$children/")
            _agent_loop_write_state "$parent" "$parent_state"
        fi
    fi
    
    _agent_loop_log info "Started agent: $name (PID: $pid)"
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "pid:number=$pid" \
        "goal=$goal" \
        "priority=$priority" \
        "state_dir=$(_agent_loop_state_dir "$name")"
}

# @desc Get agent status
# @usage agent_loop_status "name"
# @returns JSON with current agent status
agent_loop_status() {
    local name="$1"
    
    if ! _agent_loop_validate_name "$name"; then
        json_object \
            "success:bool=false" \
            "error=Invalid agent name"
        return 1
    fi
    
    local state
    state=$(_agent_loop_read_state "$name")
    
    if [[ -z "$state" ]]; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' not found"
        return 1
    fi
    
    local pid
    pid=$(_agent_loop_get_pid "$name")
    
    local running="false"
    [[ -n "$pid" ]] && proc_exists "$pid" && running="true"
    
    # Calculate elapsed time
    local start_time
    start_time=$(json_get "$state" "start_time" 2>/dev/null || echo "0")
    local elapsed=""
    [[ -n "$start_time" && "$start_time" != "0" ]] && elapsed=$(_agent_loop_elapsed "$start_time")
    
    # Build status response
    json_object \
        "name=$name" \
        "running:bool=$running" \
        "pid:number=${pid:-0}" \
        "elapsed=$elapsed" \
        "state:raw=$state"
}

# @desc Pause agent execution
# @usage agent_loop_pause "name"
# @returns JSON with status
agent_loop_pause() {
    local name="$1"
    
    if ! _agent_loop_is_running "$name"; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' is not running"
        return 1
    fi
    
    local pid
    pid=$(_agent_loop_get_pid "$name")
    
    if proc_signal "$pid" "$AGENT_LOOP_SIGNAL_PAUSE"; then
        # Update state
        local state
        state=$(_agent_loop_read_state "$name")
        if [[ -n "$state" ]]; then
            state=$(echo "$state" | sed 's/"status":"[^"]*"/"status":"paused"/')
            _agent_loop_write_state "$name" "$state"
        fi
        
        _agent_loop_log_activity "$name" "paused" "{}"
        _agent_loop_log info "Paused agent: $name"
        
        json_object \
            "success:bool=true" \
            "name=$name" \
            "status=paused"
    else
        json_object \
            "success:bool=false" \
            "error=Failed to send pause signal"
    fi
}

# @desc Resume agent execution
# @usage agent_loop_resume "name" [--context "focus"]
# @returns JSON with status
agent_loop_resume() {
    local name="$1"
    shift
    
    local context=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --context)
                context="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local pid
    pid=$(_agent_loop_get_pid "$name")
    
    if [[ -z "$pid" ]] || ! proc_exists "$pid"; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' is not running"
        return 1
    fi
    
    if proc_signal "$pid" "$AGENT_LOOP_SIGNAL_RESUME"; then
        # Update state
        local state
        state=$(_agent_loop_read_state "$name")
        if [[ -n "$state" ]]; then
            state=$(echo "$state" | sed 's/"status":"[^"]*"/"status":"running"/')
            if [[ -n "$context" ]]; then
                # Add context to state
                local new_context
                new_context=$(json_object \
                    "resume_time=$(_agent_loop_timestamp)" \
                    "focus=$context")
                state=$(echo "$state" | sed "s/\"context\":{[^}]*}/\"context\":$new_context/")
            fi
            _agent_loop_write_state "$name" "$state"
        fi
        
        local activity_data="{}"
        [[ -n "$context" ]] && activity_data="{\"focus\":\"$context\"}"
        _agent_loop_log_activity "$name" "resumed" "$activity_data"
        _agent_loop_log info "Resumed agent: $name"
        
        json_object \
            "success:bool=true" \
            "name=$name" \
            "status=running" \
            "context=$context"
    else
        json_object \
            "success:bool=false" \
            "error=Failed to send resume signal"
    fi
}

# @desc Stop agent execution
# @usage agent_loop_stop "name"
# @returns JSON with status
agent_loop_stop() {
    local name="$1"
    
    local pid
    pid=$(_agent_loop_get_pid "$name")
    
    if [[ -z "$pid" ]]; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' not found"
        return 1
    fi
    
    if ! proc_exists "$pid"; then
        # Clean up stale state
        rm -f "$(_agent_loop_pidfile "$name")"
        json_object \
            "success:bool=true" \
            "name=$name" \
            "status=already_stopped"
        return 0
    fi
    
    # Send TERM signal
    if proc_kill "$pid"; then
        # Wait for process to exit
        proc_wait_timeout "$pid" 5 || proc_kill_force "$pid"
        
        _agent_loop_log info "Stopped agent: $name"
        
        json_object \
            "success:bool=true" \
            "name=$name" \
            "status=stopped"
    else
        json_object \
            "success:bool=false" \
            "error=Failed to stop agent"
    fi
}

# @desc List all agents
# @usage agent_loop_list [--running] [--json]
# @returns List of agents
agent_loop_list() {
    local running_only=false
    local json_output=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --running)
                running_only=true
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -d "$AGENT_LOOP_DIR" ]] || {
        $json_output && echo '[]' || echo "No agents found"
        return 0
    }
    
    local -a agents=()
    
    for state_file in "$AGENT_LOOP_DIR"/*/state.json; do
        [[ -f "$state_file" ]] || continue
        
        local dir="${state_file%/state.json}"
        local name="${dir##*/}"
        
        local running="false"
        _agent_loop_is_running "$name" && running="true"
        
        $running_only && [[ "$running" == "false" ]] && continue
        
        if $json_output; then
            local state
            state=$(cat "$state_file")
            agents+=("$state")
        else
            local pid
            pid=$(_agent_loop_get_pid "$name")
            local status
            status=$(json_get "$(cat "$state_file")" "status" 2>/dev/null || echo "unknown")
            printf '%-30s %-10s %-10s %s\n' "$name" "$status" "${pid:--}" "$( [[ "$running" == "true" ]] && echo "running" || echo "stopped" )"
        fi
    done
    
    if $json_output; then
        printf '['
        local first=true
        for agent in "${agents[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$agent"
        done
        printf ']\n'
    fi
}

# =============================================================================
# PUBLIC API - MULTI-AGENT COORDINATION
# =============================================================================

# @desc Spawn a child agent for a subtask
# @usage agent_loop_spawn --parent "name" --child "subtask_name" --goal "..."
# @returns JSON with child agent info
agent_loop_spawn() {
    local parent=""
    local child=""
    local goal=""
    local priority="normal"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parent)
                parent="$2"
                shift 2
                ;;
            --child)
                child="$2"
                shift 2
                ;;
            --goal)
                goal="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate
    [[ -z "$parent" ]] && {
        json_object "success:bool=false" "error=Parent agent required"
        return 1
    }
    [[ -z "$child" ]] && {
        json_object "success:bool=false" "error=Child agent name required"
        return 1
    }
    [[ -z "$goal" ]] && {
        json_object "success:bool=false" "error=Goal required"
        return 1
    }
    
    # Check parent exists
    if ! _agent_loop_is_running "$parent"; then
        json_object \
            "success:bool=false" \
            "error=Parent agent '$parent' is not running"
        return 1
    fi
    
    # Start child agent
    agent_loop_start "$child" --goal "$goal" --priority "$priority" --parent "$parent"
}

# @desc Delegate task to another agent via UAP
# @usage agent_loop_delegate "name" --to "other_agent" --task "..." [--timeout N]
# @returns JSON with delegation status
agent_loop_delegate() {
    local name="$1"
    shift
    
    local to_agent=""
    local task=""
    local timeout=1800
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to)
                to_agent="$2"
                shift 2
                ;;
            --task)
                task="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate
    [[ -z "$to_agent" ]] && {
        json_object "success:bool=false" "error=Target agent required (use --to)"
        return 1
    }
    [[ -z "$task" ]] && {
        json_object "success:bool=false" "error=Task description required (use --task)"
        return 1
    }
    
    # Build delegation message
    local payload
    payload=$(json_object \
        "from=$name" \
        "task=$task" \
        "timeout:number=$timeout" \
        "delegated_at=$(_agent_loop_timestamp)")
    
    local message
    message=$(uap_encode_message \
        --type "$UAP_TYPE_TASK_REQUEST" \
        --payload "$payload" \
        --to "$to_agent")
    
    # Send via UAP
    local result
    result=$(uap_send --to "$to_agent" --message "$message" --timeout "$timeout")
    
    # Log delegation
    _agent_loop_log_activity "$name" "delegated" "$payload"
    
    json_object \
        "success:bool=true" \
        "from=$name" \
        "to=$to_agent" \
        "task=$task" \
        "send_result:raw=$result"
}

# @desc Join/wait for another agent
# @usage agent_loop_join "name" --wait_for "other_agent" [--timeout N]
# @returns JSON with join result
agent_loop_join() {
    local name="$1"
    shift
    
    local wait_for=""
    local timeout=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wait_for)
                wait_for="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$wait_for" ]] && {
        json_object "success:bool=false" "error=Agent to wait for required (use --wait_for)"
        return 1
    }
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        # Check if target agent is still running
        if ! _agent_loop_is_running "$wait_for"; then
            # Agent stopped, check its final status
            local final_state
            final_state=$(_agent_loop_read_state "$wait_for")
            
            _agent_loop_log_activity "$name" "joined" "{\"agent\":\"$wait_for\"}"
            
            json_object \
                "success:bool=true" \
                "joined=$wait_for" \
                "final_state:raw=${final_state:-{}}"
            return 0
        fi
        
        # Check timeout
        if [[ $timeout -gt 0 ]]; then
            local elapsed
            elapsed=$(($(date +%s) - start_time))
            if [[ $elapsed -ge $timeout ]]; then
                json_object \
                    "success:bool=false" \
                    "error=Timeout waiting for $wait_for" \
                    "elapsed:number=$elapsed"
                return 124
            fi
        fi
        
        sleep 1
    done
}

# =============================================================================
# PUBLIC API - HUMAN INTERACTION
# =============================================================================

# @desc Request input from human operator
# @usage agent_loop_request_input "name" --prompt "..."
# @returns JSON with request status
agent_loop_request_input() {
    local name="$1"
    shift
    
    local prompt=""
    local timeout=3600
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prompt)
                prompt="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$prompt" ]] && {
        json_object "success:bool=false" "error=Prompt required (use --prompt)"
        return 1
    }
    
    if ! _agent_loop_is_running "$name"; then
        json_object \
            "success:bool=false" \
            "error=Agent '$name' is not running"
        return 1
    fi
    
    # Create input request file
    local request_file="$AGENT_LOOP_DIR/$name/input_request.json"
    local request_id
    request_id=$(_agent_loop_gen_id "req")
    
    local request_data
    request_data=$(json_object \
        "request_id=$request_id" \
        "prompt=$prompt" \
        "requested_at=$(_agent_loop_timestamp)" \
        "timeout:number=$timeout" \
        "status=pending")
    
    _agent_loop_atomic_write "$request_file" "$request_data"
    
    # Update agent state
    local state
    state=$(_agent_loop_read_state "$name")
    if [[ -n "$state" ]]; then
        state=$(echo "$state" | sed 's/"status":"[^"]*"/"status":"waiting_for_input"/')
        _agent_loop_write_state "$name" "$state"
    fi
    
    # Pause agent until input received
    agent_loop_pause "$name" > /dev/null
    
    _agent_loop_log_activity "$name" "input_requested" "$request_data"
    _agent_loop_log info "Agent $name requested input: $prompt"
    
    json_object \
        "success:bool=true" \
        "request_id=$request_id" \
        "prompt=$prompt" \
        "response_file=$request_file"
}

# @desc Provide input to waiting agent
# @usage agent_loop_provide_input "name" --request_id "..." --response "..."
# @returns JSON with status
agent_loop_provide_input() {
    local name="$1"
    shift
    
    local request_id=""
    local response=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --request_id)
                request_id="$2"
                shift 2
                ;;
            --response)
                response="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local request_file="$AGENT_LOOP_DIR/$name/input_request.json"
    
    if [[ ! -f "$request_file" ]]; then
        json_object \
            "success:bool=false" \
            "error=No pending input request for agent '$name'"
        return 1
    fi
    
    # Update request file with response
    local updated
    updated=$(json_object \
        "request_id=${request_id:-unknown}" \
        "response=$response" \
        "responded_at=$(_agent_loop_timestamp)" \
        "status=completed")
    
    _agent_loop_atomic_write "$request_file" "$updated"
    
    # Resume agent
    agent_loop_resume "$name" --context "Input received: $response"
    
    _agent_loop_log_activity "$name" "input_received" "{\"response\":\"$response\"}"
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "status=resumed"
}

# @desc Notify human operator of milestone
# @usage agent_loop_notify "name" --message "..." [--level info|warn|error]
# @returns JSON with notification status
agent_loop_notify() {
    local name="$1"
    shift
    
    local message=""
    local level="info"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message)
                message="$2"
                shift 2
                ;;
            --level)
                level="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$message" ]] && {
        json_object "success:bool=false" "error=Message required (use --message)"
        return 1
    }
    
    # Log notification
    _agent_loop_log_activity "$name" "notification" "{\"level\":\"$level\",\"message\":\"$message\"}"
    
    # Output to stderr for immediate visibility
    printf '[agent_loop][%s][%s][%s] %s\n' "$(date -Iseconds)" "$level" "$name" "$message" >&2
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "level=$level" \
        "message=$message"
}

# =============================================================================
# PUBLIC API - CHECKPOINT/RECOVERY
# =============================================================================

# @desc Restore agent from checkpoint
# @usage agent_loop_restore "name"
# @returns JSON with restore status
agent_loop_restore() {
    local name="$1"
    
    local checkpoint_file
    checkpoint_file=$(_agent_loop_checkpoint_file "$name")
    
    if [[ ! -f "$checkpoint_file" ]]; then
        json_object \
            "success:bool=false" \
            "error=No checkpoint found for agent '$name'"
        return 1
    fi
    
    local checkpoint
    checkpoint=$(cat "$checkpoint_file")
    
    # Extract state from checkpoint
    local saved_state
    saved_state=$(json_get "$checkpoint" "state" 2>/dev/null || echo "")
    
    if [[ -z "$saved_state" ]]; then
        json_object \
            "success:bool=false" \
            "error=Invalid checkpoint format"
        return 1
    fi
    
    # Restore state
    _agent_loop_write_state "$name" "$saved_state"
    
    _agent_loop_log info "Restored agent '$name' from checkpoint"
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "restored_from=$checkpoint_file"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _AGENT_LOOP_EXPORTS=(
    agent_loop_start
    agent_loop_status
    agent_loop_pause
    agent_loop_resume
    agent_loop_stop
    agent_loop_list
    agent_loop_spawn
    agent_loop_delegate
    agent_loop_join
    agent_loop_request_input
    agent_loop_provide_input
    agent_loop_notify
    agent_loop_restore
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_AGENT_LOOP_EXPORTS[@]}" 2>/dev/null || true
fi

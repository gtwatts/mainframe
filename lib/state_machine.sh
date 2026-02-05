#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/state_machine.sh - Visual State Machine for Workflows
# =============================================================================
# Description: Event-driven state machine with visual workflow definition,
#              checkpoint/resume, timeout handling, and retry logic.
# Version: 1.0.0
# Requires: Bash 4.0+, lib/json.sh, lib/state.sh
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_STATE_MACHINE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_STATE_MACHINE_LOADED=1

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/json.sh"
fi
if [[ -z "${_MAINFRAME_STATE_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/state.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for state machine storage
STATE_MACHINE_DIR="${MAINFRAME_STATE_MACHINE_DIR:-${HOME}/.mainframe/state_machines}"

# Default timeout for state transitions (seconds)
STATE_MACHINE_DEFAULT_TIMEOUT="${STATE_MACHINE_DEFAULT_TIMEOUT:-300}"

# Default retry count
STATE_MACHINE_DEFAULT_RETRIES="${STATE_MACHINE_DEFAULT_RETRIES:-3}"

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Associative array for machine definitions
declare -gA _STATE_MACHINE_DEFINITIONS=()
declare -gA _STATE_MACHINE_STATES=()
declare -gA _STATE_MACHINE_TRANSITIONS=()
declare -gA _STATE_MACHINE_CALLBACKS=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Logging function
_state_machine_log() {
    local level="$1"
    shift
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[state_machine][%s] %s: %s\n' "$(date -Iseconds)" "$level" "$*" >&2
    fi
}

# Validate machine name
_state_machine_validate_name() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [[ ${#name} -le 64 ]] || return 1
    return 0
}

# Validate state name
_state_machine_validate_state_name() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    return 0
}

# Get machine directory
_state_machine_dir() {
    local name="$1"
    printf '%s' "$STATE_MACHINE_DIR/$name"
}

# Get machine state file
_state_machine_state_file() {
    local name="$1"
    printf '%s' "$STATE_MACHINE_DIR/$name/machine_state.json"
}

# Get machine definition file
_state_machine_def_file() {
    local name="$1"
    printf '%s' "$STATE_MACHINE_DIR/$name/definition.json"
}

# Get checkpoint file
_state_machine_checkpoint_file() {
    local name="$1"
    printf '%s' "$STATE_MACHINE_DIR/$name/checkpoint.json"
}

# Ensure directories exist
_state_machine_ensure_dirs() {
    local name="$1"
    local dir
    dir=$(_state_machine_dir "$name")
    mkdir -p "$dir" || return 1
    chmod 700 "$dir"
}

# Atomic write
_state_machine_atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s' "$content" > "$tmp" && mv "$tmp" "$file"
}

# Generate timestamp
_state_machine_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s
}

# Generate unique run ID
_state_machine_gen_run_id() {
    local name="$1"
    local timestamp
    timestamp=$(date +%s)
    local rand
    rand=$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 6)
    printf '%s_%s_%s' "$name" "$timestamp" "$rand"
}

# =============================================================================
# PUBLIC API - DEFINITION
# =============================================================================

# @desc Define a new state machine
# @usage state_machine_define "name"
# @returns JSON with machine definition
state_machine_define() {
    local name="$1"
    
    if ! _state_machine_validate_name "$name"; then
        json_object \
            "success:bool=false" \
            "error=Invalid machine name (alphanumeric, dash, underscore, max 64 chars)"
        return 1
    fi
    
    # Ensure directories
    _state_machine_ensure_dirs "$name"
    
    # Initialize machine definition
    local definition
    definition=$(json_object \
        "name=$name" \
        "created=$(_state_machine_timestamp)" \
        "states:raw=[]" \
        "initial=" \
        "final_states:raw=[]")
    
    _STATE_MACHINE_DEFINITIONS[$name]="$definition"
    
    # Initialize states array
    _STATE_MACHINE_STATES[$name]=""
    _STATE_MACHINE_TRANSITIONS[$name]=""
    _STATE_MACHINE_CALLBACKS[$name]=""
    
    _state_machine_log info "Defined state machine: $name"
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "definition:raw=$definition"
}

# @desc Add a state to the machine
# @usage state_machine_add_state "machine" "state_name" \
#           [--on_enter "callback"] \
#           [--on_exit "callback"] \
#           [--transitions '{"event": "next_state"}'] \
#           [--final] \
#           [--timeout N] \
#           [--retries N]
# @returns JSON with updated state
state_machine_add_state() {
    local machine="$1"
    local state_name="$2"
    shift 2
    
    local on_enter=""
    local on_exit=""
    local transitions="{}"
    local is_final="false"
    local timeout=$STATE_MACHINE_DEFAULT_TIMEOUT
    local retries=$STATE_MACHINE_DEFAULT_RETRIES
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --on_enter)
                on_enter="$2"
                shift 2
                ;;
            --on_exit)
                on_exit="$2"
                shift 2
                ;;
            --transitions)
                transitions="$2"
                shift 2
                ;;
            --final)
                is_final="true"
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --retries)
                retries="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate
    if ! _state_machine_validate_name "$machine"; then
        json_object "success:bool=false" "error=Invalid machine name"
        return 1
    fi
    if ! _state_machine_validate_state_name "$state_name"; then
        json_object "success:bool=false" "error=Invalid state name"
        return 1
    fi
    
    # Build state definition
    local state_def
    state_def=$(json_object \
        "name=$state_name" \
        "on_enter=$on_enter" \
        "on_exit=$on_exit" \
        "transitions:raw=$transitions" \
        "final:bool=$is_final" \
        "timeout:number=$timeout" \
        "retries:number=$retries")
    
    # Store state
    local current_states="${_STATE_MACHINE_STATES[$machine]:-}"
    if [[ -n "$current_states" ]]; then
        current_states="$current_states $state_name"
    else
        current_states="$state_name"
    fi
    _STATE_MACHINE_STATES[$machine]="$current_states"
    _STATE_MACHINE_TRANSITIONS["$machine:$state_name"]="$transitions"
    
    # Store callbacks
    if [[ -n "$on_enter" || -n "$on_exit" ]]; then
        local callbacks
        callbacks=$(json_object \
            "on_enter=$on_enter" \
            "on_exit=$on_exit")
        _STATE_MACHINE_CALLBACKS["$machine:$state_name"]="$callbacks"
    fi
    
    _state_machine_log debug "Added state '$state_name' to machine '$machine'"
    
    json_object \
        "success:bool=true" \
        "machine=$machine" \
        "state=$state_name" \
        "definition:raw=$state_def"
}

# @desc Set initial state for machine
# @usage state_machine_set_initial "machine" "state_name"
# @returns JSON with status
state_machine_set_initial() {
    local machine="$1"
    local state_name="$2"
    
    if ! _state_machine_validate_name "$machine"; then
        json_object "success:bool=false" "error=Invalid machine name"
        return 1
    fi
    
    # Verify state exists
    local states="${_STATE_MACHINE_STATES[$machine]:-}"
    if [[ ! " $states " =~ " $state_name " ]]; then
        json_object "success:bool=false" "error=State '$state_name' not defined"
        return 1
    fi
    
    # Update definition
    local def="${_STATE_MACHINE_DEFINITIONS[$machine]:-}"
    if [[ -n "$def" ]]; then
        def=$(echo "$def" | sed "s/\"initial\":\"[^\"]*\"/\"initial\":\"$state_name\"/")
        def=$(echo "$def" | sed "s/\"initial\":\s*null/\"initial\":\"$state_name\"/")
        _STATE_MACHINE_DEFINITIONS[$machine]="$def"
    fi
    
    json_object \
        "success:bool=true" \
        "machine=$machine" \
        "initial=$state_name"
}

# =============================================================================
# PUBLIC API - EXECUTION
# =============================================================================

# @desc Run the state machine
# @usage state_machine_run "name" \
#           [--initial "start_state"] \
#           [--visualize] \
#           [--on_state_change "callback"] \
#           [--event_timeout N]
# @returns JSON with execution result
state_machine_run() {
    local name="$1"
    shift
    
    local initial=""
    local visualize="false"
    local on_state_change=""
    local event_timeout=$STATE_MACHINE_DEFAULT_TIMEOUT
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --initial)
                initial="$2"
                shift 2
                ;;
            --visualize)
                visualize="true"
                shift
                ;;
            --on_state_change)
                on_state_change="$2"
                shift 2
                ;;
            --event_timeout)
                event_timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if ! _state_machine_validate_name "$name"; then
        json_object "success:bool=false" "error=Invalid machine name"
        return 1
    fi
    
    # Get states
    local states="${_STATE_MACHINE_STATES[$name]:-}"
    if [[ -z "$states" ]]; then
        json_object "success:bool=false" "error=No states defined for machine '$name'"
        return 1
    fi
    
    # Determine initial state
    if [[ -z "$initial" ]]; then
        # Use first state as default
        initial="${states%% *}"
    fi
    
    # Initialize machine state
    local run_id
    run_id=$(_state_machine_gen_run_id "$name")
    local started_at
    started_at=$(_state_machine_timestamp)
    
    local machine_state
    machine_state=$(json_object \
        "machine=$name" \
        "run_id=$run_id" \
        "current_state=$initial" \
        "previous_state=" \
        "started_at=$started_at" \
        "status=running" \
        "state_history:raw=[\"$initial\"]" \
        "event_count:number=0" \
        "retry_count:number=0")
    
    _state_machine_ensure_dirs "$name"
    _state_machine_atomic_write "$(_state_machine_state_file "$name")" "$machine_state"
    
    _state_machine_log info "Started state machine: $name (run_id: $run_id)"
    
    # Visualize if requested
    if [[ "$visualize" == "true" ]]; then
        state_machine_visualize "$name"
    fi
    
    # Execute state machine
    local current_state="$initial"
    local final_states=""
    local iteration=0
    local max_iterations=1000  # Safety limit
    
    while [[ $iteration -lt $max_iterations ]]; do
        ((iteration++))
        
        # Check if current state is final
        local state_def
        state_def="${_STATE_MACHINE_TRANSITIONS["$name:$current_state"]:-{}}"
        
        # Check if final state
        local is_final="false"
        if [[ "$state_def" == *'"final":true'* ]]; then
            is_final="true"
        fi
        
        # Execute on_enter callback
        local callbacks="${_STATE_MACHINE_CALLBACKS["$name:$current_state"]:-{}}"
        local on_enter
        on_enter=$(json_get "$callbacks" "on_enter" 2>/dev/null || echo "")
        
        if [[ -n "$on_enter" ]]; then
            _state_machine_log debug "Executing on_enter for state: $current_state"
            # Execute callback (in real implementation, this would be a function call)
            if declare -f "$on_enter" &>/dev/null; then
                "$on_enter" "$name" "$current_state" || {
                    _state_machine_log warn "on_enter callback failed for state: $current_state"
                }
            fi
        fi
        
        # Call state change callback if provided
        if [[ -n "$on_state_change" ]]; then
            if declare -f "$on_state_change" &>/dev/null; then
                "$on_state_change" "$name" "$current_state" "${previous_state:-}"
            fi
        fi
        
        # Check if final state
        if [[ "$is_final" == "true" ]]; then
            _state_machine_log info "Reached final state: $current_state"
            break
        fi
        
        # Wait for event or timeout
        local event=""
        local event_data="{}"
        local wait_start
        wait_start=$(date +%s)
        
        while true; do
            # Check for pending events
            local event_file="$STATE_MACHINE_DIR/$name/pending_event.json"
            if [[ -f "$event_file" ]]; then
                local event_content
                event_content=$(cat "$event_file")
                event=$(json_get "$event_content" "event" 2>/dev/null || echo "")
                event_data=$(json_get "$event_content" "data" 2>/dev/null || echo "{}")
                rm -f "$event_file"
                break
            fi
            
            # Check timeout
            local elapsed
            elapsed=$(($(date +%s) - wait_start))
            if [[ $elapsed -ge $event_timeout ]]; then
                event="timeout"
                event_data="{\"elapsed\":$elapsed}"
                break
            fi
            
            sleep 0.1
        done
        
        _state_machine_log debug "Received event: $event"
        
        # Get transitions for current state
        local transitions
        transitions="${_STATE_MACHINE_TRANSITIONS["$name:$current_state"]:-{}}"
        
        # Determine next state
        local next_state
        next_state=$(json_get "$transitions" "$event" 2>/dev/null || echo "")
        
        # If no transition for this event, check for "*" wildcard
        if [[ -z "$next_state" ]]; then
            next_state=$(json_get "$transitions" "*" 2>/dev/null || echo "")
        fi
        
        # If still no transition, stay in current state
        if [[ -z "$next_state" ]]; then
            _state_machine_log debug "No transition for event '$event' in state '$current_state'"
            continue
        fi
        
        # Execute on_exit callback
        local on_exit
        on_exit=$(json_get "$callbacks" "on_exit" 2>/dev/null || echo "")
        
        if [[ -n "$on_exit" ]]; then
            _state_machine_log debug "Executing on_exit for state: $current_state"
            if declare -f "$on_exit" &>/dev/null; then
                "$on_exit" "$name" "$current_state" || {
                    _state_machine_log warn "on_exit callback failed for state: $current_state"
                }
            fi
        fi
        
        # Update state
        local previous_state="$current_state"
        current_state="$next_state"
        
        # Update machine state
        local current_machine_state
        current_machine_state=$(_state_machine_state_file "$name")
        if [[ -f "$current_machine_state" ]]; then
            local updated_state
            updated_state=$(cat "$current_machine_state")
            updated_state=$(echo "$updated_state" | sed "s/\"current_state\":\"[^\"]*\"/\"current_state\":\"$current_state\"/")
            updated_state=$(echo "$updated_state" | sed "s/\"previous_state\":\"[^\"]*\"/\"previous_state\":\"$previous_state\"/")
            
            # Update history
            local history
            history=$(json_get "$updated_state" "state_history" 2>/dev/null || echo "[]")
            history="${history%]}, \"$current_state\"]"
            [[ "$history" == "[]" ]] && history="[\"$current_state\"]"
            updated_state=$(echo "$updated_state" | sed "s/\"state_history\":\[[^]]*\]/\"state_history\":$history/")
            
            # Update event count
            local event_count
            event_count=$(json_get "$updated_state" "event_count" 2>/dev/null || echo "0")
            event_count=$((event_count + 1))
            updated_state=$(echo "$updated_state" | sed "s/\"event_count\":[0-9]*/\"event_count\":$event_count/")
            
            _state_machine_atomic_write "$current_machine_state" "$updated_state"
        fi
        
        _state_machine_log info "Transition: $previous_state -> $current_state (event: $event)"
    done
    
    # Mark as completed
    local final_state_file
    final_state_file=$(_state_machine_state_file "$name")
    if [[ -f "$final_state_file" ]]; then
        local final_state
        final_state=$(cat "$final_state_file")
        final_state=$(echo "$final_state" | sed 's/"status":"[^"]*"/"status":"completed"/')
        final_state=$(echo "$final_state" | sed "s/\"completed_at\":\"[^\"]*\"/\"completed_at\":\"$(_state_machine_timestamp)\"/")
        _state_machine_atomic_write "$final_state_file" "$final_state"
    fi
    
    _state_machine_log info "Completed state machine: $name"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "run_id=$run_id" \
        "final_state=$current_state" \
        "iterations:number=$iteration"
}

# @desc Send event to running state machine
# @usage state_machine_send_event "name" --event "event_name" [--data '{...}']
# @returns JSON with status
state_machine_send_event() {
    local name="$1"
    shift
    
    local event=""
    local data="{}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --event)
                event="$2"
                shift 2
                ;;
            --data)
                data="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$event" ]] && {
        json_object "success:bool=false" "error=Event name required (use --event)"
        return 1
    }
    
    local event_file="$STATE_MACHINE_DIR/$name/pending_event.json"
    
    local event_content
    event_content=$(json_object \
        "event=$event" \
        "data:raw=$data" \
        "sent_at=$(_state_machine_timestamp)")
    
    _state_machine_atomic_write "$event_file" "$event_content"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "event=$event"
}

# =============================================================================
# PUBLIC API - STATUS & CONTROL
# =============================================================================

# @desc Get current state machine status
# @usage state_machine_status "name"
# @returns JSON with current status
state_machine_status() {
    local name="$1"
    
    if ! _state_machine_validate_name "$name"; then
        json_object "success:bool=false" "error=Invalid machine name"
        return 1
    fi
    
    local state_file
    state_file=$(_state_machine_state_file "$name")
    
    if [[ ! -f "$state_file" ]]; then
        json_object \
            "success:bool=false" \
            "error=State machine '$name' not found or not running"
        return 1
    fi
    
    local state
    state=$(cat "$state_file")
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "state:raw=$state"
}

# @desc Pause state machine execution
# @usage state_machine_pause "name"
# @returns JSON with status
state_machine_pause() {
    local name="$1"
    
    local state_file
    state_file=$(_state_machine_state_file "$name")
    
    if [[ ! -f "$state_file" ]]; then
        json_object "success:bool=false" "error=State machine not found"
        return 1
    fi
    
    local state
    state=$(cat "$state_file")
    state=$(echo "$state" | sed 's/"status":"[^"]*"/"status":"paused"/')
    _state_machine_atomic_write "$state_file" "$state"
    
    # Create pause signal file
    touch "$STATE_MACHINE_DIR/$name/.paused"
    
    _state_machine_log info "Paused state machine: $name"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "status=paused"
}

# @desc Resume state machine execution
# @usage state_machine_resume "name"
# @returns JSON with status
state_machine_resume() {
    local name="$1"
    
    local state_file
    state_file=$(_state_machine_state_file "$name")
    
    if [[ ! -f "$state_file" ]]; then
        json_object "success:bool=false" "error=State machine not found"
        return 1
    fi
    
    local state
    state=$(cat "$state_file")
    state=$(echo "$state" | sed 's/"status":"[^"]*"/"status":"running"/')
    _state_machine_atomic_write "$state_file" "$state"
    
    # Remove pause signal file
    rm -f "$STATE_MACHINE_DIR/$name/.paused"
    
    _state_machine_log info "Resumed state machine: $name"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "status=running"
}

# =============================================================================
# PUBLIC API - CHECKPOINT/RECOVERY
# =============================================================================

# @desc Create checkpoint of current state
# @usage state_machine_checkpoint "name"
# @returns JSON with checkpoint info
state_machine_checkpoint() {
    local name="$1"
    
    local state_file
    state_file=$(_state_machine_state_file "$name")
    
    if [[ ! -f "$state_file" ]]; then
        json_object "success:bool=false" "error=State machine not running"
        return 1
    fi
    
    local checkpoint_file
    checkpoint_file=$(_state_machine_checkpoint_file "$name")
    
    local state
    state=$(cat "$state_file")
    
    local checkpoint
    checkpoint=$(json_object \
        "checkpoint_time=$(_state_machine_timestamp)" \
        "state:raw=$state")
    
    _state_machine_atomic_write "$checkpoint_file" "$checkpoint"
    
    _state_machine_log info "Created checkpoint for: $name"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "checkpoint_file=$checkpoint_file"
}

# @desc Resume from checkpoint
# @usage state_machine_resume_from_checkpoint "name"
# @returns JSON with resume status
state_machine_resume_from_checkpoint() {
    local name="$1"
    
    local checkpoint_file
    checkpoint_file=$(_state_machine_checkpoint_file "$name")
    
    if [[ ! -f "$checkpoint_file" ]]; then
        json_object \
            "success:bool=false" \
            "error=No checkpoint found for machine '$name'"
        return 1
    fi
    
    local checkpoint
    checkpoint=$(cat "$checkpoint_file")
    
    local saved_state
    saved_state=$(json_get "$checkpoint" "state" 2>/dev/null || echo "")
    
    if [[ -z "$saved_state" ]]; then
        json_object \
            "success:bool=false" \
            "error=Invalid checkpoint format"
        return 1
    fi
    
    # Restore state
    local state_file
    state_file=$(_state_machine_state_file "$name")
    _state_machine_atomic_write "$state_file" "$saved_state"
    
    _state_machine_log info "Resumed '$name' from checkpoint"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "restored:raw=$saved_state"
}

# @desc Replay state machine from beginning
# @usage state_machine_replay "name" [--from "start_state"]
# @returns JSON with replay result
state_machine_replay() {
    local name="$1"
    shift
    
    local from_state=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from_state="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Reset state to initial
    local def_file
    def_file=$(_state_machine_def_file "$name")
    
    local initial
    if [[ -n "$from_state" ]]; then
        initial="$from_state"
    else
        initial="${_STATE_MACHINE_STATES[$name]%% *}"
    fi
    
    # Reset machine state
    local state_file
    state_file=$(_state_machine_state_file "$name")
    
    local run_id
    run_id=$(_state_machine_gen_run_id "$name")
    
    local reset_state
    reset_state=$(json_object \
        "machine=$name" \
        "run_id=$run_id" \
        "current_state=$initial" \
        "previous_state=" \
        "started_at=$(_state_machine_timestamp)" \
        "status=running" \
        "state_history:raw=[\"$initial\"]" \
        "event_count:number=0" \
        "retry_count:number=0" \
        "replayed:bool=true")
    
    _state_machine_atomic_write "$state_file" "$reset_state"
    
    _state_machine_log info "Replayed state machine: $name from state: $initial"
    
    json_object \
        "success:bool=true" \
        "machine=$name" \
        "run_id=$run_id" \
        "starting_state=$initial"
}

# =============================================================================
# PUBLIC API - VISUALIZATION
# =============================================================================

# @desc Visualize state machine as ASCII diagram
# @usage state_machine_visualize "name"
# @returns ASCII visualization
state_machine_visualize() {
    local name="$1"
    
    if ! _state_machine_validate_name "$name"; then
        echo "Error: Invalid machine name"
        return 1
    fi
    
    local states="${_STATE_MACHINE_STATES[$name]:-}"
    if [[ -z "$states" ]]; then
        echo "Error: No states defined"
        return 1
    fi
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  State Machine: $name"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo ""
    
    # Draw states and transitions
    local first=true
    for state in $states; do
        local transitions
        transitions="${_STATE_MACHINE_TRANSITIONS["$name:$state"]:-{}}"
        
        # Check if final state
        local is_final="false"
        if [[ "$transitions" == *'"final":true'* ]]; then
            is_final="true"
        fi
        
        if $first; then
            echo "    [START]"
            echo "       │"
            echo "       ▼"
            first=false
        fi
        
        if [[ "$is_final" == "true" ]]; then
            echo "   ┌─────────┐"
            echo "   │  $state │ ◄── [FINAL]"
            echo "   └─────────┘"
        else
            echo "   ┌─────────┐"
            echo "   │  $state │"
            echo "   └────┬────┘"
            
            # Show transitions
            local event next_state
            # Parse transitions JSON (simple approach)
            if [[ "$transitions" != "{}" ]]; then
                echo "        │"
                # Extract events and targets
                local trans_clean
                trans_clean=$(echo "$transitions" | tr -d '{}"' | tr ',' '\n')
                while IFS=: read -r event next_state; do
                    [[ -n "$event" ]] || continue
                    echo "        ├── $event ──► $next_state"
                done <<< "$trans_clean"
            fi
        fi
        echo ""
    done
    
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

# @desc Export state machine to DOT format for GraphViz
# @usage state_machine_to_dot "name" [--output file.dot]
# @returns DOT format graph
state_machine_to_dot() {
    local name="$1"
    shift
    
    local output=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                output="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local states="${_STATE_MACHINE_STATES[$name]:-}"
    if [[ -z "$states" ]]; then
        echo "Error: No states defined"
        return 1
    fi
    
    local dot="digraph $name {"
    dot+=$'\n  rankdir=TB;'
    dot+=$'\n  node [shape=box, style=rounded];'
    dot+=$'\n'
    
    # Add states
    for state in $states; do
        local transitions
        transitions="${_STATE_MACHINE_TRANSITIONS["$name:$state"]:-{}}"
        
        # Check if final state
        if [[ "$transitions" == *'"final":true'* ]]; then
            dot+=$"\n  \"$state\" [shape=doublecircle, style=filled, fillcolor=lightgreen];"
        else
            dot+=$"\n  \"$state\";"
        fi
        
        # Add edges
        if [[ "$transitions" != "{}" ]]; then
            local trans_clean
            trans_clean=$(echo "$transitions" | tr -d '{}"' | tr ',' '\n')
            while IFS=: read -r event next_state; do
                [[ -n "$event" ]] || continue
                [[ "$event" == "final" ]] && continue  # Skip final marker
                dot+=$"\n  \"$state\" -> \"$next_state\" [label=\"$event\"];"
            done <<< "$trans_clean"
        fi
    done
    
    dot+=$'\n}'
    
    if [[ -n "$output" ]]; then
        printf '%s\n' "$dot" > "$output"
        echo "DOT graph written to: $output"
    else
        printf '%s\n' "$dot"
    fi
}

# =============================================================================
# PUBLIC API - LISTING & CLEANUP
# =============================================================================

# @desc List all state machines
# @usage state_machine_list [--json]
# @returns List of machines
state_machine_list() {
    local json_output=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -d "$STATE_MACHINE_DIR" ]] || {
        $json_output && echo '[]' || echo "No state machines found"
        return 0
    }
    
    local -a machines=()
    
    for def_file in "$STATE_MACHINE_DIR"/*/definition.json; do
        [[ -f "$def_file" ]] || continue
        
        local dir="${def_file%/definition.json}"
        local name="${dir##*/}"
        
        # Check if currently running
        local status="defined"
        local state_file="$dir/machine_state.json"
        if [[ -f "$state_file" ]]; then
            status=$(json_get "$(cat "$state_file")" "status" 2>/dev/null || echo "unknown")
        fi
        
        if $json_output; then
            local def
            def=$(cat "$def_file" 2>/dev/null || echo "{}")
            machines+=("$(json_object \
                "name=$name" \
                "status=$status" \
                "definition:raw=$def")")
        else
            printf '%-30s %s\n' "$name" "$status"
        fi
    done
    
    if $json_output; then
        printf '['
        local first=true
        for machine in "${machines[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$machine"
        done
        printf ']\n'
    fi
}

# @desc Remove state machine
# @usage state_machine_destroy "name"
# @returns JSON with status
state_machine_destroy() {
    local name="$1"
    
    local dir
    dir=$(_state_machine_dir "$name")
    
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        
        # Clean up from memory
        unset "_STATE_MACHINE_DEFINITIONS[$name]"
        unset "_STATE_MACHINE_STATES[$name]"
        
        # Clean up transitions and callbacks
        local key
        for key in "${!_STATE_MACHINE_TRANSITIONS[@]}"; do
            [[ "$key" == "$name:"* ]] && unset "_STATE_MACHINE_TRANSITIONS[$key]"
        done
        for key in "${!_STATE_MACHINE_CALLBACKS[@]}"; do
            [[ "$key" == "$name:"* ]] && unset "_STATE_MACHINE_CALLBACKS[$key]"
        done
        
        _state_machine_log info "Destroyed state machine: $name"
        
        json_object \
            "success:bool=true" \
            "destroyed=$name"
    else
        json_object \
            "success:bool=false" \
            "error=State machine not found"
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _STATE_MACHINE_EXPORTS=(
    state_machine_define
    state_machine_add_state
    state_machine_set_initial
    state_machine_run
    state_machine_send_event
    state_machine_status
    state_machine_pause
    state_machine_resume
    state_machine_checkpoint
    state_machine_resume_from_checkpoint
    state_machine_replay
    state_machine_visualize
    state_machine_to_dot
    state_machine_list
    state_machine_destroy
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_STATE_MACHINE_EXPORTS[@]}" 2>/dev/null || true
fi

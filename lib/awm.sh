#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/awm.sh - Agent Working Memory (AWM)
# =============================================================================
# Description: Persistent external memory for AI agents with finite context.
#              Enables agents to write state/discoveries OUTSIDE their context,
#              read back relevant portions, support sub-agent inheritance,
#              and resume sessions after interruption.
#
# Design Goals:
#   - Minimize context cost when reading memory back
#   - Support concurrent sub-agents safely
#   - Enable session resumption after crashes/timeouts
#   - Auto-compress old entries to prevent memory bloat
#   - Provide inheritance mechanism for sub-agent spawning
#
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AWM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AWM_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Root directory for all AWM storage
AWM_ROOT="${AWM_ROOT:-${HOME}/.mainframe/awm}"

# Maximum size of a single memory file before compression (bytes)
AWM_MAX_FILE_SIZE="${AWM_MAX_FILE_SIZE:-65536}"  # 64KB default

# Maximum entries in a category log before auto-compression
AWM_MAX_LOG_ENTRIES="${AWM_MAX_LOG_ENTRIES:-100}"

# Default compression threshold (entries older than N seconds are compressed)
AWM_COMPRESS_AGE="${AWM_COMPRESS_AGE:-3600}"  # 1 hour

# Token estimation ratio (chars per token, approximate)
AWM_CHARS_PER_TOKEN="${AWM_CHARS_PER_TOKEN:-4}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Currently active session ID
_AWM_SESSION_ID=""

# Namespace for isolation (sub-agents can have their own namespace)
_AWM_NAMESPACE=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_awm_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[awm] $*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[awm] %s: %s\n' "${level}" "$*" >&2
    fi
}

# Get epoch seconds
_awm_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# Get high-resolution timestamp for ordering
_awm_timestamp() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    else
        date '+%s.%N' 2>/dev/null || date +%s
    fi
}

# ISO 8601 timestamp for human readability
_awm_iso_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
}

# Generate 12-character hex session ID
_awm_gen_session_id() {
    local id
    id=$(od -An -tx1 -N6 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 12 ]]; then
        # Fallback: use RANDOM + PID + date
        printf '%04x%04x%04x' "$$" "$RANDOM" "$(date +%s | cut -c6-10)"
        return
    fi
    printf '%s' "${id:0:12}"
}

# Get the session directory
_awm_session_dir() {
    local sid="${1:-$_AWM_SESSION_ID}"
    if [[ -n "$_AWM_NAMESPACE" ]]; then
        printf '%s/sessions/%s/%s' "$AWM_ROOT" "$_AWM_NAMESPACE" "$sid"
    else
        printf '%s/sessions/%s' "$AWM_ROOT" "$sid"
    fi
}

# JSON-escape a string
_awm_json_escape() {
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

# Atomic write using temp file + rename
_awm_atomic_write() {
    local target="$1"
    local content="$2"
    local tmpfile="${target}.tmp.$$"
    local dir="${target%/*}"

    [[ "$dir" != "$target" ]] && mkdir -p "$dir" 2>/dev/null

    if printf '%s' "$content" > "$tmpfile" 2>/dev/null; then
        mv -f "$tmpfile" "$target" 2>/dev/null && return 0
    fi
    rm -f "$tmpfile" 2>/dev/null
    return 1
}

# Append with flock for concurrent safety
_awm_locked_append() {
    local target="$1"
    local content="$2"
    local dir="${target%/*}"

    [[ "$dir" != "$target" ]] && mkdir -p "$dir" 2>/dev/null

    if command -v flock &>/dev/null; then
        (
            flock -x 200
            printf '%s\n' "$content" >> "$target"
        ) 200>"${target}.lock"
        rm -f "${target}.lock" 2>/dev/null
    else
        printf '%s\n' "$content" >> "$target"
    fi
}

# Count lines in a file (safely)
_awm_line_count() {
    local file="$1"
    [[ -f "$file" ]] || { printf '0'; return; }
    wc -l < "$file" 2>/dev/null | tr -d ' '
}

# Get file size in bytes
_awm_file_size() {
    local file="$1"
    [[ -f "$file" ]] || { printf '0'; return; }
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%z "$file" 2>/dev/null || echo 0
    else
        stat -c%s "$file" 2>/dev/null || echo 0
    fi
}

# =============================================================================
# SESSION LIFECYCLE
# =============================================================================

# @pre: none
# @post: new session initialized, _AWM_SESSION_ID set
# @idempotent: no - creates new session each time (use awm_resume for existing)
# @returns: 0, prints session_id to stdout
#
# Initialize a new AWM session. Creates the storage directory and manifest.
# Optionally inherits from a parent session.
#
# Usage: session_id=$(awm_init ["session_name"] ["parent_session_id"])
# Example: sid=$(awm_init "deploy-config")
# Example: sid=$(awm_init "subtask" "$parent_sid")
awm_init() {
    local name="${1:-}"
    local parent_session="${2:-}"

    local session_id
    session_id=$(_awm_gen_session_id)

    _AWM_SESSION_ID="$session_id"

    local dir
    dir=$(_awm_session_dir "$session_id")
    mkdir -p "${dir}/logs" "${dir}/data" "${dir}/checkpoints" || {
        _awm_log error "awm_init: failed to create session directory"
        return 1
    }

    # Create manifest
    local now
    now=$(_awm_iso_timestamp)
    local epoch
    epoch=$(_awm_epoch)

    local escaped_name
    escaped_name=$(_awm_json_escape "${name:-unnamed}")

    local manifest
    manifest=$(printf '{"session_id":"%s","name":"%s","created_at":"%s","created_epoch":%s,"parent_session":"%s","status":"active","namespace":"%s"}' \
        "$session_id" "$escaped_name" "$now" "$epoch" "${parent_session:-}" "${_AWM_NAMESPACE:-}")

    _awm_atomic_write "${dir}/manifest.json" "$manifest"

    # Initialize empty logs index
    _awm_atomic_write "${dir}/logs/index.json" '{"categories":[]}'

    # If parent session provided, inherit its discoveries and checkpoints
    if [[ -n "$parent_session" ]]; then
        _awm_inherit "$parent_session" "$session_id"
    fi

    _awm_log info "initialized session: $session_id"
    printf '%s' "$session_id"
}

# @pre: session_id exists
# @post: _AWM_SESSION_ID set to existing session
# @returns: 0 if found, 1 if not
#
# Resume an existing AWM session by ID.
#
# Usage: awm_resume "session_id"
# Example: awm_resume "a1b2c3d4e5f6"
awm_resume() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        _awm_log error "awm_resume: session_id required"
        return 1
    fi

    local dir
    dir=$(_awm_session_dir "$session_id")

    if [[ ! -d "$dir" || ! -f "${dir}/manifest.json" ]]; then
        _awm_log error "awm_resume: session not found: $session_id"
        return 1
    fi

    _AWM_SESSION_ID="$session_id"
    _awm_log info "resumed session: $session_id"
    return 0
}

# @pre: active session exists
# @post: session marked as complete
# @returns: 0
#
# Close the current AWM session (marks as complete but doesn't delete).
#
# Usage: awm_close
awm_close() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log warn "awm_close: no active session"
        return 0
    fi

    local dir
    dir=$(_awm_session_dir)
    local manifest="${dir}/manifest.json"

    if [[ -f "$manifest" ]]; then
        local content
        content=$(<"$manifest")
        # Update status to completed
        content="${content/\"status\":\"active\"/\"status\":\"completed\"}"
        _awm_atomic_write "$manifest" "$content"
    fi

    _awm_log info "closed session: $_AWM_SESSION_ID"
    _AWM_SESSION_ID=""
}

# Internal: inherit from parent session
_awm_inherit() {
    local parent_id="$1"
    local child_id="$2"

    local parent_dir child_dir
    parent_dir=$(_awm_session_dir "$parent_id")
    child_dir=$(_awm_session_dir "$child_id")

    if [[ ! -d "$parent_dir" ]]; then
        _awm_log warn "_awm_inherit: parent session not found: $parent_id"
        return 1
    fi

    # Copy discoveries (key learnings to inherit)
    if [[ -f "${parent_dir}/logs/discoveries.jsonl" ]]; then
        cp -f "${parent_dir}/logs/discoveries.jsonl" "${child_dir}/logs/inherited_discoveries.jsonl" 2>/dev/null
    fi

    # Copy key-value data
    if [[ -d "${parent_dir}/data" ]]; then
        for file in "${parent_dir}/data"/*; do
            [[ -f "$file" ]] || continue
            local key="${file##*/}"
            [[ ! -f "${child_dir}/data/${key}" ]] && cp -f "$file" "${child_dir}/data/${key}" 2>/dev/null
        done
    fi

    _awm_log debug "_awm_inherit: inherited from $parent_id to $child_id"
}

# =============================================================================
# NAMESPACE MANAGEMENT (Sub-Agent Isolation)
# =============================================================================

# @pre: none
# @post: _AWM_NAMESPACE set
# @returns: 0
#
# Set a namespace for sub-agent isolation.
# Namespaced sessions are stored in separate directories.
#
# Usage: awm_namespace "agent-name"
# Example: awm_namespace "code-reviewer"
awm_namespace() {
    local ns="$1"

    if [[ -z "$ns" ]]; then
        _AWM_NAMESPACE=""
        _awm_log debug "awm_namespace: cleared namespace"
    else
        # Sanitize namespace name
        ns="${ns//[^a-zA-Z0-9_-]/_}"
        _AWM_NAMESPACE="$ns"
        _awm_log debug "awm_namespace: set to $ns"
    fi
}

# =============================================================================
# CORE WRITE FUNCTIONS
# =============================================================================

# @pre: active session
# @post: key-value pair stored atomically
# @idempotent: yes - overwrites existing key
# @returns: 0 on success, 1 on failure
#
# Save a key-value pair to persistent memory.
# Keys are stored as individual files for atomic access.
#
# Usage: awm_checkpoint "key" "value"
# Example: awm_checkpoint "current_step" "3"
# Example: awm_checkpoint "api_response" "$json_response"
awm_checkpoint() {
    local key="$1"
    local value="$2"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_checkpoint: no active session"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _awm_log error "awm_checkpoint: key required"
        return 1
    fi

    # Sanitize key for filename
    local safe_key="${key//[^a-zA-Z0-9_.-]/_}"

    local dir
    dir=$(_awm_session_dir)
    local file="${dir}/data/${safe_key}"

    _awm_atomic_write "$file" "$value"

    # Also log the checkpoint event
    local ts
    ts=$(_awm_timestamp)
    local escaped_key escaped_val
    escaped_key=$(_awm_json_escape "$key")
    escaped_val=$(_awm_json_escape "${value:0:256}")  # Truncate for log

    local entry
    entry=$(printf '{"ts":%s,"key":"%s","preview":"%s"}' "$ts" "$escaped_key" "$escaped_val")
    _awm_locked_append "${dir}/logs/checkpoints.jsonl" "$entry"

    _awm_log debug "awm_checkpoint: saved $key"
}

# @pre: active session
# @post: message appended to category log
# @idempotent: no - appends each time
# @returns: 0 on success, 1 on failure
#
# Append a structured message to a categorized log.
# Categories enable selective retrieval of related entries.
#
# Usage: awm_log "category" "message"
# Example: awm_log "errors" "Failed to connect to API"
# Example: awm_log "decisions" "Chose PostgreSQL over MySQL for transactions"
awm_log() {
    local category="$1"
    local message="$2"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_log: no active session"
        return 1
    fi

    if [[ -z "$category" || -z "$message" ]]; then
        _awm_log error "awm_log: category and message required"
        return 1
    fi

    # Sanitize category
    local safe_cat="${category//[^a-zA-Z0-9_-]/_}"

    local dir
    dir=$(_awm_session_dir)
    local log_file="${dir}/logs/${safe_cat}.jsonl"

    local ts iso
    ts=$(_awm_timestamp)
    iso=$(_awm_iso_timestamp)
    local escaped_msg
    escaped_msg=$(_awm_json_escape "$message")

    local entry
    entry=$(printf '{"ts":%s,"iso":"%s","msg":"%s"}' "$ts" "$iso" "$escaped_msg")
    _awm_locked_append "$log_file" "$entry"

    # Update category index
    _awm_update_category_index "$safe_cat"

    # Check if compression needed
    local count
    count=$(_awm_line_count "$log_file")
    if [[ $count -gt $AWM_MAX_LOG_ENTRIES ]]; then
        _awm_compress_log "$safe_cat"
    fi

    _awm_log debug "awm_log: [$category] $message"
}

# Internal: update category index
_awm_update_category_index() {
    local category="$1"
    local dir
    dir=$(_awm_session_dir)
    local index="${dir}/logs/index.json"

    if [[ -f "$index" ]]; then
        local content
        content=$(<"$index")
        if [[ "$content" != *"\"$category\""* ]]; then
            # Add category to index
            content="${content/\"categories\":\[/\"categories\":[\"$category\",}"
            content="${content/\[\",/[}"  # Fix if first entry
            _awm_atomic_write "$index" "$content"
        fi
    fi
}

# @pre: active session
# @post: progress entry recorded
# @idempotent: no - appends each time
# @returns: 0
#
# Track task progress with a structured format.
# Progress entries include current/total for progress bar calculation.
#
# Usage: awm_progress "task_id" "current/total" ["status_message"]
# Example: awm_progress "file-processing" "47/200" "Processing batch 47"
awm_progress() {
    local task_id="$1"
    local progress="$2"
    local status_msg="${3:-}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_progress: no active session"
        return 1
    fi

    local current total
    current="${progress%/*}"
    total="${progress#*/}"

    local dir
    dir=$(_awm_session_dir)

    local ts
    ts=$(_awm_timestamp)
    local escaped_task escaped_status
    escaped_task=$(_awm_json_escape "$task_id")
    escaped_status=$(_awm_json_escape "$status_msg")

    local entry
    entry=$(printf '{"ts":%s,"task":"%s","current":%s,"total":%s,"status":"%s"}' \
        "$ts" "$escaped_task" "${current:-0}" "${total:-0}" "$escaped_status")

    _awm_locked_append "${dir}/logs/progress.jsonl" "$entry"

    # Also update latest progress as checkpoint for quick access
    awm_checkpoint "progress:${task_id}" "$progress"
}

# @pre: active session
# @post: discovery recorded in special high-priority log
# @idempotent: no - appends each time
# @returns: 0
#
# Record a key insight or discovery that should be preserved.
# Discoveries are prioritized during inheritance and summarization.
#
# Usage: awm_discovery "insight text"
# Example: awm_discovery "User prefers PostgreSQL for all new projects"
# Example: awm_discovery "API rate limit is 100 req/min, not 1000"
awm_discovery() {
    local insight="$1"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_discovery: no active session"
        return 1
    fi

    if [[ -z "$insight" ]]; then
        _awm_log error "awm_discovery: insight text required"
        return 1
    fi

    local dir
    dir=$(_awm_session_dir)

    local ts iso
    ts=$(_awm_timestamp)
    iso=$(_awm_iso_timestamp)
    local escaped
    escaped=$(_awm_json_escape "$insight")

    local entry
    entry=$(printf '{"ts":%s,"iso":"%s","discovery":"%s","importance":"high"}' \
        "$ts" "$iso" "$escaped")

    _awm_locked_append "${dir}/logs/discoveries.jsonl" "$entry"

    _awm_log info "awm_discovery: $insight"
}

# =============================================================================
# CORE READ FUNCTIONS
# =============================================================================

# @pre: active session, key exists
# @post: none (read-only)
# @returns: 0 if found, 1 if not found
#
# Retrieve a checkpointed value by key.
#
# Usage: value=$(awm_get "key")
# Example: step=$(awm_get "current_step")
awm_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        printf '%s' "$default"
        return 1
    fi

    # Sanitize key for filename
    local safe_key="${key//[^a-zA-Z0-9_.-]/_}"

    local dir
    dir=$(_awm_session_dir)
    local file="${dir}/data/${safe_key}"

    if [[ -f "$file" ]]; then
        cat "$file"
        return 0
    fi

    printf '%s' "$default"
    return 1
}

# @pre: active session, category exists
# @post: none (read-only)
# @returns: last N entries as JSON array
#
# Retrieve the last N entries from a category log.
# Returns newest entries first (reverse chronological).
#
# Usage: entries=$(awm_recent "category" [count])
# Example: errors=$(awm_recent "errors" 10)
awm_recent() {
    local category="$1"
    local count="${2:-10}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        printf '[]'
        return 1
    fi

    # Sanitize category
    local safe_cat="${category//[^a-zA-Z0-9_-]/_}"

    local dir
    dir=$(_awm_session_dir)
    local log_file="${dir}/logs/${safe_cat}.jsonl"

    if [[ ! -f "$log_file" ]]; then
        printf '[]'
        return 0
    fi

    # Get last N lines and format as JSON array
    printf '['
    local first=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        $first || printf ','
        first=false
        printf '%s' "$line"
    done < <(tail -n "$count" "$log_file" | tac 2>/dev/null || tail -r -n "$count" "$log_file" 2>/dev/null || tail -n "$count" "$log_file")
    printf ']'
}

# @pre: active session
# @post: none (read-only)
# @returns: compressed summary as JSON
#
# Generate a compressed summary of the session for context injection.
# Includes: discoveries, recent progress, key checkpoints.
#
# Usage: summary=$(awm_summary)
# Example: context=$(awm_summary)
awm_summary() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        printf '{"error":"no active session"}'
        return 1
    fi

    local dir
    dir=$(_awm_session_dir)

    # Collect discoveries
    local discoveries="[]"
    if [[ -f "${dir}/logs/discoveries.jsonl" ]]; then
        discoveries="["
        local first=true
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            $first || discoveries+=","
            first=false
            discoveries+="$line"
        done < "${dir}/logs/discoveries.jsonl"
        discoveries+="]"
    fi

    # Get latest progress entries (one per task)
    local progress="{}"
    if [[ -f "${dir}/logs/progress.jsonl" ]]; then
        # Extract unique tasks with latest progress
        progress="{"
        local first=true
        local -A seen_tasks=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # Extract task name from JSON
            if [[ "$line" =~ \"task\":\"([^\"]+)\" ]]; then
                local task="${BASH_REMATCH[1]}"
                if [[ -z "${seen_tasks[$task]:-}" ]]; then
                    $first || progress+=","
                    first=false
                    # Extract current/total
                    local current=0 total=0
                    [[ "$line" =~ \"current\":([0-9]+) ]] && current="${BASH_REMATCH[1]}"
                    [[ "$line" =~ \"total\":([0-9]+) ]] && total="${BASH_REMATCH[1]}"
                    progress+="\"$task\":\"$current/$total\""
                    seen_tasks[$task]=1
                fi
            fi
        done < <(tac "${dir}/logs/progress.jsonl" 2>/dev/null || tail -r "${dir}/logs/progress.jsonl" 2>/dev/null || cat "${dir}/logs/progress.jsonl")
        progress+="}"
    fi

    # Get key checkpoints (files in data/)
    local checkpoints="{"
    local first=true
    if [[ -d "${dir}/data" ]]; then
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            local key="${file##*/}"
            local value
            value=$(head -c 256 "$file")  # Truncate large values
            local escaped_key escaped_val
            escaped_key=$(_awm_json_escape "$key")
            escaped_val=$(_awm_json_escape "$value")
            $first || checkpoints+=","
            first=false
            checkpoints+="\"${escaped_key}\":\"${escaped_val}\""
        done
    fi
    checkpoints+="}"

    # Get list of log categories
    local categories="[]"
    if [[ -f "${dir}/logs/index.json" ]]; then
        # Extract categories array
        local index
        index=$(<"${dir}/logs/index.json")
        if [[ "$index" =~ \"categories\":\[([^\]]*)\] ]]; then
            categories="[${BASH_REMATCH[1]}]"
        fi
    fi

    # Build summary
    printf '{"session_id":"%s","discoveries":%s,"progress":%s,"checkpoints":%s,"categories":%s}' \
        "$_AWM_SESSION_ID" "$discoveries" "$progress" "$checkpoints" "$categories"
}

# @pre: active session
# @post: none (read-only)
# @returns: context optimized for sub-agent
#
# Generate a context package for spawning a sub-agent.
# Includes essential state without full history.
#
# Usage: ctx=$(awm_context_for "subtask_name")
# Example: ctx=$(awm_context_for "validate-config")
awm_context_for() {
    local subtask="${1:-subtask}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        printf '{"error":"no active session"}'
        return 1
    fi

    local dir
    dir=$(_awm_session_dir)

    # Include: discoveries, relevant checkpoints, parent session info
    local discoveries="[]"
    if [[ -f "${dir}/logs/discoveries.jsonl" ]]; then
        discoveries=$(awm_recent "discoveries" 20)
    fi

    # Include inherited discoveries if present
    local inherited="[]"
    if [[ -f "${dir}/logs/inherited_discoveries.jsonl" ]]; then
        inherited="["
        local first=true
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            $first || inherited+=","
            first=false
            inherited+="$line"
        done < "${dir}/logs/inherited_discoveries.jsonl"
        inherited+="]"
    fi

    # Key checkpoints only
    local checkpoints="{}"
    if [[ -d "${dir}/data" ]]; then
        checkpoints="{"
        local first=true
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            local key="${file##*/}"
            # Skip progress keys and large files
            [[ "$key" == progress:* ]] && continue
            local size
            size=$(_awm_file_size "$file")
            [[ $size -gt 1024 ]] && continue

            local value
            value=$(<"$file")
            local escaped_key escaped_val
            escaped_key=$(_awm_json_escape "$key")
            escaped_val=$(_awm_json_escape "$value")
            $first || checkpoints+=","
            first=false
            checkpoints+="\"${escaped_key}\":\"${escaped_val}\""
        done
        checkpoints+="}"
    fi

    local escaped_subtask
    escaped_subtask=$(_awm_json_escape "$subtask")

    printf '{"parent_session":"%s","subtask":"%s","discoveries":%s,"inherited":%s,"checkpoints":%s}' \
        "$_AWM_SESSION_ID" "$escaped_subtask" "$discoveries" "$inherited" "$checkpoints"
}

# =============================================================================
# MEMORY MANAGEMENT
# =============================================================================

# @pre: none (can be called without active session to compress all)
# @post: old entries archived, logs compressed
# @returns: 0
#
# Compress old memory entries to reduce storage and context cost.
# Entries older than AWM_COMPRESS_AGE are summarized and archived.
#
# Usage: awm_compress
awm_compress() {
    local session_id="${1:-$_AWM_SESSION_ID}"

    if [[ -z "$session_id" ]]; then
        _awm_log error "awm_compress: no session specified"
        return 1
    fi

    local dir
    dir=$(_awm_session_dir "$session_id")

    if [[ ! -d "${dir}/logs" ]]; then
        return 0
    fi

    local now
    now=$(_awm_epoch)
    local cutoff=$((now - AWM_COMPRESS_AGE))

    # Compress each log file
    for log_file in "${dir}/logs"/*.jsonl; do
        [[ -f "$log_file" ]] || continue
        [[ "$log_file" == *discoveries.jsonl ]] && continue  # Never compress discoveries

        local category="${log_file##*/}"
        category="${category%.jsonl}"

        _awm_compress_log "$category" "$session_id"
    done

    _awm_log info "awm_compress: compressed session $session_id"
}

# Internal: compress a single log category
_awm_compress_log() {
    local category="$1"
    local session_id="${2:-$_AWM_SESSION_ID}"

    local dir
    dir=$(_awm_session_dir "$session_id")
    local log_file="${dir}/logs/${category}.jsonl"

    [[ -f "$log_file" ]] || return 0

    local line_count
    line_count=$(_awm_line_count "$log_file")

    if [[ $line_count -le $AWM_MAX_LOG_ENTRIES ]]; then
        return 0
    fi

    local keep=$((AWM_MAX_LOG_ENTRIES / 2))
    local archive_count=$((line_count - keep))

    # Archive old entries
    local archive_file="${dir}/logs/${category}.archive.jsonl"
    head -n "$archive_count" "$log_file" >> "$archive_file"

    # Keep only recent entries
    local tmpfile="${log_file}.tmp.$$"
    tail -n "$keep" "$log_file" > "$tmpfile"
    mv -f "$tmpfile" "$log_file"

    _awm_log debug "_awm_compress_log: archived $archive_count entries from $category"
}

# @pre: active session
# @post: memory exported to markdown file
# @returns: 0, prints file path
#
# Export session memory to a human-readable markdown file.
# Useful for handoff to humans or documentation.
#
# Usage: awm_export "/path/to/output.md"
# Example: awm_export "session-report.md"
awm_export() {
    local output_file="${1:-}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_export: no active session"
        return 1
    fi

    local dir
    dir=$(_awm_session_dir)

    if [[ -z "$output_file" ]]; then
        output_file="${dir}/export.md"
    fi

    {
        printf '# AWM Session Export\n\n'
        printf '**Session ID:** %s\n' "$_AWM_SESSION_ID"
        printf '**Exported:** %s\n\n' "$(_awm_iso_timestamp)"

        # Manifest info
        if [[ -f "${dir}/manifest.json" ]]; then
            printf '## Session Info\n\n'
            printf '```json\n'
            cat "${dir}/manifest.json"
            printf '\n```\n\n'
        fi

        # Discoveries
        if [[ -f "${dir}/logs/discoveries.jsonl" ]]; then
            printf '## Discoveries\n\n'
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # Extract discovery text
                if [[ "$line" =~ \"discovery\":\"([^\"]+)\" ]]; then
                    printf '- %s\n' "${BASH_REMATCH[1]}"
                fi
            done < "${dir}/logs/discoveries.jsonl"
            printf '\n'
        fi

        # Checkpoints
        if [[ -d "${dir}/data" ]]; then
            printf '## Checkpoints\n\n'
            printf '| Key | Value |\n'
            printf '|-----|-------|\n'
            for file in "${dir}/data"/*; do
                [[ -f "$file" ]] || continue
                local key="${file##*/}"
                local value
                value=$(head -c 100 "$file" | tr '\n' ' ')
                printf '| %s | %s |\n' "$key" "$value"
            done
            printf '\n'
        fi

        # Log summaries
        printf '## Logs\n\n'
        for log_file in "${dir}/logs"/*.jsonl; do
            [[ -f "$log_file" ]] || continue
            local category="${log_file##*/}"
            category="${category%.jsonl}"
            local count
            count=$(_awm_line_count "$log_file")
            printf '- **%s**: %d entries\n' "$category" "$count"
        done

    } > "$output_file"

    printf '%s' "$output_file"
}

# @pre: parent_session exists
# @post: child session created with inherited state
# @returns: child session ID
#
# Create a sub-agent session that inherits from a parent.
# Equivalent to awm_init with parent parameter.
#
# Usage: child_id=$(awm_inherit "parent_session_id")
# Example: sub_id=$(awm_inherit "$main_session")
awm_inherit() {
    local parent_session="$1"
    local name="${2:-child}"

    awm_init "$name" "$parent_session"
}

# =============================================================================
# TOKEN BUDGET ESTIMATION
# =============================================================================

# @pre: active session
# @post: none (read-only)
# @returns: estimated token count for full memory read
#
# Estimate the token cost of reading back all memory.
# Helps agents decide when to compress or summarize.
#
# Usage: tokens=$(awm_token_estimate)
awm_token_estimate() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        printf '0'
        return 1
    fi

    local dir
    dir=$(_awm_session_dir)
    local total_bytes=0

    # Count all data files
    if [[ -d "${dir}/data" ]]; then
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            local size
            size=$(_awm_file_size "$file")
            total_bytes=$((total_bytes + size))
        done
    fi

    # Count all log files
    if [[ -d "${dir}/logs" ]]; then
        for file in "${dir}/logs"/*.jsonl; do
            [[ -f "$file" ]] || continue
            local size
            size=$(_awm_file_size "$file")
            total_bytes=$((total_bytes + size))
        done
    fi

    # Estimate tokens (chars / chars_per_token)
    local tokens=$((total_bytes / AWM_CHARS_PER_TOKEN))
    printf '%d' "$tokens"
}

# @pre: active session
# @post: none (read-only)
# @returns: token estimate for specific read operation
#
# Estimate tokens for a specific memory read.
#
# Usage: tokens=$(awm_estimate_read "summary")
# Usage: tokens=$(awm_estimate_read "recent" "errors" 10)
awm_estimate_read() {
    local operation="$1"
    shift

    local bytes=0
    local dir
    dir=$(_awm_session_dir)

    case "$operation" in
        summary)
            # Estimate summary size based on discoveries + checkpoints
            if [[ -f "${dir}/logs/discoveries.jsonl" ]]; then
                bytes=$(_awm_file_size "${dir}/logs/discoveries.jsonl")
            fi
            if [[ -d "${dir}/data" ]]; then
                for file in "${dir}/data"/*; do
                    [[ -f "$file" ]] || continue
                    local size
                    size=$(_awm_file_size "$file")
                    [[ $size -gt 256 ]] && size=256  # Truncated
                    bytes=$((bytes + size + 50))  # +50 for JSON overhead
                done
            fi
            ;;
        recent)
            local category="$1"
            local count="${2:-10}"
            local safe_cat="${category//[^a-zA-Z0-9_-]/_}"
            local log_file="${dir}/logs/${safe_cat}.jsonl"
            if [[ -f "$log_file" ]]; then
                # Estimate: avg line length * count
                local total_size line_count avg_line
                total_size=$(_awm_file_size "$log_file")
                line_count=$(_awm_line_count "$log_file")
                [[ $line_count -eq 0 ]] && line_count=1
                avg_line=$((total_size / line_count))
                bytes=$((avg_line * count + 20))  # +20 for array brackets
            fi
            ;;
        get)
            local key="$1"
            local safe_key="${key//[^a-zA-Z0-9_.-]/_}"
            local file="${dir}/data/${safe_key}"
            if [[ -f "$file" ]]; then
                bytes=$(_awm_file_size "$file")
            fi
            ;;
        context_for)
            # Similar to summary but includes inherited
            bytes=500  # Base overhead
            if [[ -f "${dir}/logs/discoveries.jsonl" ]]; then
                bytes=$((bytes + $(_awm_file_size "${dir}/logs/discoveries.jsonl")))
            fi
            if [[ -f "${dir}/logs/inherited_discoveries.jsonl" ]]; then
                bytes=$((bytes + $(_awm_file_size "${dir}/logs/inherited_discoveries.jsonl")))
            fi
            ;;
    esac

    local tokens=$((bytes / AWM_CHARS_PER_TOKEN))
    printf '%d' "$tokens"
}

# =============================================================================
# SESSION LISTING & CLEANUP
# =============================================================================

# @pre: none
# @post: none (read-only)
# @returns: list of sessions (tab-separated: id, name, status, created_at)
#
# List all AWM sessions, optionally filtered by status.
#
# Usage: awm_list [--status active|completed]
awm_list() {
    local filter_status=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) filter_status="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local sessions_dir="${AWM_ROOT}/sessions"
    [[ -d "$sessions_dir" ]] || return 0

    # Check both root and namespace directories
    local dirs=("$sessions_dir")
    for ns_dir in "$sessions_dir"/*/; do
        [[ -d "$ns_dir" ]] && dirs+=("$ns_dir")
    done

    for base_dir in "${dirs[@]}"; do
        for session_dir in "$base_dir"/*/; do
            [[ -d "$session_dir" ]] || continue
            local manifest="${session_dir}manifest.json"
            [[ -f "$manifest" ]] || continue

            local id="${session_dir%/}"
            id="${id##*/}"

            # Skip namespace directories
            [[ -d "${session_dir}sessions" ]] && continue

            local content
            content=$(<"$manifest")

            local name status created_at
            [[ "$content" =~ \"name\":\"([^\"]+)\" ]] && name="${BASH_REMATCH[1]}" || name=""
            [[ "$content" =~ \"status\":\"([^\"]+)\" ]] && status="${BASH_REMATCH[1]}" || status="unknown"
            [[ "$content" =~ \"created_at\":\"([^\"]+)\" ]] && created_at="${BASH_REMATCH[1]}" || created_at=""

            # Apply filter
            if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
                continue
            fi

            printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$status" "$created_at"
        done
    done
}

# @pre: none
# @post: old completed sessions deleted
# @returns: count of deleted sessions
#
# Clean up old completed sessions (default: older than 7 days).
#
# Usage: awm_cleanup [days]
awm_cleanup() {
    local max_days="${1:-7}"
    local now
    now=$(_awm_epoch)
    local max_seconds=$((max_days * 86400))
    local cleaned=0

    local sessions_dir="${AWM_ROOT}/sessions"
    [[ -d "$sessions_dir" ]] || { printf '0'; return 0; }

    for session_dir in "$sessions_dir"/*/; do
        [[ -d "$session_dir" ]] || continue
        local manifest="${session_dir}manifest.json"
        [[ -f "$manifest" ]] || continue

        local content
        content=$(<"$manifest")

        # Only clean completed sessions
        [[ "$content" =~ \"status\":\"completed\" ]] || continue

        # Check age
        local created_epoch=0
        [[ "$content" =~ \"created_epoch\":([0-9]+) ]] && created_epoch="${BASH_REMATCH[1]}"

        local age=$((now - created_epoch))
        if [[ $age -gt $max_seconds ]]; then
            rm -rf "$session_dir"
            ((cleaned++))
        fi
    done

    printf '%d' "$cleaned"
}

# =============================================================================
# SAFETY FEATURES
# =============================================================================

# @pre: active session
# @post: none (read-only)
# @returns: 0 if within limits, 1 if at risk
#
# Check if memory usage is approaching configured limits.
#
# Usage: awm_check_limits && echo "OK" || echo "At limit"
awm_check_limits() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        return 0
    fi

    local dir
    dir=$(_awm_session_dir)

    # Check total size
    local total_size=0
    for file in "${dir}"/{data,logs}/*; do
        [[ -f "$file" ]] || continue
        local size
        size=$(_awm_file_size "$file")
        total_size=$((total_size + size))
    done

    # Max session size: 10MB
    local max_size=$((10 * 1024 * 1024))
    if [[ $total_size -gt $max_size ]]; then
        _awm_log warn "awm_check_limits: session exceeds 10MB ($total_size bytes)"
        return 1
    fi

    # Check token estimate
    local tokens
    tokens=$(awm_token_estimate)
    local max_tokens=50000
    if [[ $tokens -gt $max_tokens ]]; then
        _awm_log warn "awm_check_limits: estimated tokens exceed 50K ($tokens)"
        return 1
    fi

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_AWM_EXPORTS=(
    # Session Lifecycle
    awm_init
    awm_resume
    awm_close
    awm_namespace
    # Core Write
    awm_checkpoint
    awm_log
    awm_progress
    awm_discovery
    # Core Read
    awm_get
    awm_recent
    awm_summary
    awm_context_for
    # Memory Management
    awm_compress
    awm_export
    awm_inherit
    # Token Estimation
    awm_token_estimate
    awm_estimate_read
    # Session Management
    awm_list
    awm_cleanup
    # Safety
    awm_check_limits
)

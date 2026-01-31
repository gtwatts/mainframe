#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_ai.sh - AI Agent Infrastructure Library
# =============================================================================
# Description: Agent-optimized primitives for agentic coding CLIs.
#              Synthesizes patterns from: Claude Code, Aider, OpenCode,
#              Copilot CLI, and Codex for context management, tool registry,
#              edit format abstraction, session management, and orchestration.
# Version: 6.0.0
# Requires: Bash 4.0+
# =============================================================================
# DESIGN SOURCES:
#   - Claude Code: Context budget, subagents, hooks, Tool Search
#   - Aider: Pluggable edit formats, reflection loops, RepoMap
#   - OpenCode: Tool registry, permission cascade, spillover-to-disk
#   - Copilot CLI: Auto-compress, file references, session persistence
#   - Codex: Hierarchical AGENTS.md, gated handoffs, transcript logging
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_AI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_AI_LOADED=1

# =============================================================================
# CONSTANTS & CONFIGURATION
# =============================================================================

# Context thresholds (from Claude Code + Copilot patterns)
readonly AGENT_AI_CONTEXT_WARN_THRESHOLD=80       # Warn at 80% usage
readonly AGENT_AI_CONTEXT_COMPRESS_THRESHOLD=95   # Auto-compress at 95%
readonly AGENT_AI_CONTEXT_RESERVE_PERCENT=20      # Reserve 20% for final ops

# Tool permission modes (from Copilot CLI)
readonly AGENT_AI_PERMISSION_ALLOW="allow"
readonly AGENT_AI_PERMISSION_DENY="deny"
readonly AGENT_AI_PERMISSION_ASK="ask"

# Edit format strategies (from Aider)
readonly AGENT_AI_EDIT_DIFF="diff"           # SEARCH/REPLACE blocks
readonly AGENT_AI_EDIT_UDIFF="udiff"         # Unified diff
readonly AGENT_AI_EDIT_WHOLE="whole"         # Full file replacement
readonly AGENT_AI_EDIT_PATCH="patch"         # Patch format

# Session states
readonly AGENT_AI_SESSION_ACTIVE="active"
readonly AGENT_AI_SESSION_PAUSED="paused"
readonly AGENT_AI_SESSION_COMPLETED="completed"

# Default paths
: "${AGENT_AI_STATE_DIR:=${MAINFRAME_ROOT:-$HOME/.mainframe}/state/agent_ai}"
: "${AGENT_AI_TRANSCRIPT_DIR:=${AGENT_AI_STATE_DIR}/transcripts}"
: "${AGENT_AI_SESSION_FILE:=${AGENT_AI_STATE_DIR}/session_$$}"

# Output limits (from OpenCode spillover pattern)
readonly AGENT_AI_MAX_OUTPUT_LINES=2000
readonly AGENT_AI_MAX_OUTPUT_BYTES=51200  # 50KB
readonly AGENT_AI_SPILLOVER_TTL_DAYS=7

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_agent_ai_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[agent_ai] %s: %s\n' "${level}" "$*" >&2
    fi
}

_agent_ai_ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null
}

_agent_ai_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

_agent_ai_uuid() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        printf '%s-%s-%s-%s-%s' \
            "$(printf '%04x%04x' $RANDOM $RANDOM)" \
            "$(printf '%04x' $RANDOM)" \
            "$(printf '%04x' $((RANDOM & 0x0fff | 0x4000)))" \
            "$(printf '%04x' $((RANDOM & 0x3fff | 0x8000)))" \
            "$(printf '%04x%04x%04x' $RANDOM $RANDOM $RANDOM)"
    fi
}

# =============================================================================
# CONTEXT BUDGET EXTENSIONS (Claude Code + Copilot patterns)
# =============================================================================

# Initialize agent context budget with auto-compress support
# Usage: agent_ai_context_init [max_tokens] [reserve_percent]
agent_ai_context_init() {
    local max_tokens="${1:-200000}"
    local reserve_pct="${2:-$AGENT_AI_CONTEXT_RESERVE_PERCENT}"

    _agent_ai_ensure_dir "$AGENT_AI_STATE_DIR"

    local reserve=$(( max_tokens * reserve_pct / 100 ))

    cat > "${AGENT_AI_SESSION_FILE}.context" << EOF
AGENT_AI_CTX_MAX=$max_tokens
AGENT_AI_CTX_USED=0
AGENT_AI_CTX_RESERVE=$reserve
AGENT_AI_CTX_COMPRESSED=0
AGENT_AI_CTX_WARNS=0
AGENT_AI_CTX_INIT_TIME=$(_agent_ai_timestamp)
EOF

    export AGENT_AI_CTX_MAX="$max_tokens"
    export AGENT_AI_CTX_USED=0
    export AGENT_AI_CTX_RESERVE="$reserve"
}

# Record context usage and check thresholds
# Usage: agent_ai_context_use tokens [label]
# Returns: 0=ok, 1=warning, 2=compress_triggered
agent_ai_context_use() {
    local tokens="$1"
    local label="${2:-anonymous}"

    [[ -f "${AGENT_AI_SESSION_FILE}.context" ]] && source "${AGENT_AI_SESSION_FILE}.context"

    AGENT_AI_CTX_USED=$(( ${AGENT_AI_CTX_USED:-0} + tokens ))

    local available=$(( ${AGENT_AI_CTX_MAX:-200000} - ${AGENT_AI_CTX_RESERVE:-40000} ))
    local usage_pct=$(( AGENT_AI_CTX_USED * 100 / available ))

    # Log to transcript
    agent_ai_transcript_append "context_use" "{\"tokens\":$tokens,\"label\":\"$label\",\"total\":$AGENT_AI_CTX_USED,\"percent\":$usage_pct}"

    local rc=0

    # Check compress threshold (95%)
    if (( usage_pct >= AGENT_AI_CONTEXT_COMPRESS_THRESHOLD )); then
        _agent_ai_log warn "Context at ${usage_pct}% - auto-compress triggered"
        AGENT_AI_CTX_COMPRESSED=$(( ${AGENT_AI_CTX_COMPRESSED:-0} + 1 ))
        rc=2
    # Check warning threshold (80%)
    elif (( usage_pct >= AGENT_AI_CONTEXT_WARN_THRESHOLD )); then
        _agent_ai_log warn "Context at ${usage_pct}% - approaching limit"
        AGENT_AI_CTX_WARNS=$(( ${AGENT_AI_CTX_WARNS:-0} + 1 ))
        rc=1
    fi

    # Persist state
    cat > "${AGENT_AI_SESSION_FILE}.context" << EOF
AGENT_AI_CTX_MAX=${AGENT_AI_CTX_MAX:-200000}
AGENT_AI_CTX_USED=$AGENT_AI_CTX_USED
AGENT_AI_CTX_RESERVE=${AGENT_AI_CTX_RESERVE:-40000}
AGENT_AI_CTX_COMPRESSED=${AGENT_AI_CTX_COMPRESSED:-0}
AGENT_AI_CTX_WARNS=${AGENT_AI_CTX_WARNS:-0}
AGENT_AI_CTX_INIT_TIME=${AGENT_AI_CTX_INIT_TIME:-$(_agent_ai_timestamp)}
EOF

    return $rc
}

# Get context status as JSON
# Usage: agent_ai_context_status
agent_ai_context_status() {
    [[ -f "${AGENT_AI_SESSION_FILE}.context" ]] && source "${AGENT_AI_SESSION_FILE}.context"

    local available=$(( ${AGENT_AI_CTX_MAX:-200000} - ${AGENT_AI_CTX_RESERVE:-40000} ))
    local remaining=$(( available - ${AGENT_AI_CTX_USED:-0} ))
    local usage_pct=$(( ${AGENT_AI_CTX_USED:-0} * 100 / available ))

    local status="ok"
    (( usage_pct >= AGENT_AI_CONTEXT_COMPRESS_THRESHOLD )) && status="critical"
    (( usage_pct >= AGENT_AI_CONTEXT_WARN_THRESHOLD && usage_pct < AGENT_AI_CONTEXT_COMPRESS_THRESHOLD )) && status="warning"

    printf '{"max":%d,"used":%d,"remaining":%d,"reserve":%d,"percent":%d,"status":"%s","compresses":%d,"warns":%d}\n' \
        "${AGENT_AI_CTX_MAX:-200000}" "${AGENT_AI_CTX_USED:-0}" "$remaining" "${AGENT_AI_CTX_RESERVE:-40000}" \
        "$usage_pct" "$status" "${AGENT_AI_CTX_COMPRESSED:-0}" "${AGENT_AI_CTX_WARNS:-0}"
}

# Check if tokens fit within remaining budget
# Usage: agent_ai_context_fits tokens
agent_ai_context_fits() {
    local tokens="$1"
    [[ -f "${AGENT_AI_SESSION_FILE}.context" ]] && source "${AGENT_AI_SESSION_FILE}.context"

    local available=$(( ${AGENT_AI_CTX_MAX:-200000} - ${AGENT_AI_CTX_RESERVE:-40000} ))
    local remaining=$(( available - ${AGENT_AI_CTX_USED:-0} ))

    [[ "$tokens" -le "$remaining" ]]
}

# Reset context budget
# Usage: agent_ai_context_reset
agent_ai_context_reset() {
    rm -f "${AGENT_AI_SESSION_FILE}.context"
    unset AGENT_AI_CTX_MAX AGENT_AI_CTX_USED AGENT_AI_CTX_RESERVE
}

# =============================================================================
# HIERARCHICAL CONTEXT LOADING (Codex AGENTS.md pattern)
# =============================================================================

# Load context files in precedence order: global -> project -> local
# Concatenates with 32KB limit (like Codex)
# Usage: agent_ai_context_hierarchy [start_dir]
# Output: Concatenated context content
agent_ai_context_hierarchy() {
    local start_dir="${1:-.}"
    local max_bytes=32768
    local total_bytes=0
    local result=""

    # Collect context files from root to current
    local -a context_files=()

    # Global first (lowest priority)
    [[ -f "$HOME/.claude/CLAUDE.md" ]] && context_files+=("$HOME/.claude/CLAUDE.md")
    [[ -f "$HOME/.mainframe/AGENTS.md" ]] && context_files+=("$HOME/.mainframe/AGENTS.md")

    # Walk up to find project-level contexts
    local -a project_contexts=()
    local dir
    dir=$(cd "$start_dir" 2>/dev/null && pwd)
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -f "$dir/CLAUDE.md" ]]; then
            project_contexts=("$dir/CLAUDE.md" "${project_contexts[@]}")
        fi
        if [[ -f "$dir/AGENTS.md" ]]; then
            project_contexts=("$dir/AGENTS.md" "${project_contexts[@]}")
        fi
        dir=$(dirname "$dir")
    done

    context_files+=("${project_contexts[@]}")

    # Local (highest priority) - closest to cwd wins
    local abs_start
    abs_start=$(cd "$start_dir" 2>/dev/null && pwd)
    [[ -f "$abs_start/.claude-instructions" ]] && context_files+=("$abs_start/.claude-instructions")

    # Concatenate with size limit
    local file
    for file in "${context_files[@]}"; do
        [[ -f "$file" ]] || continue
        local file_size
        file_size=$(wc -c < "$file" 2>/dev/null)
        file_size="${file_size// /}"

        if (( total_bytes + file_size <= max_bytes )); then
            result+="# From: $file"$'\n'
            result+=$(cat "$file")
            result+=$'\n\n'
            total_bytes=$(( total_bytes + file_size ))
        else
            _agent_ai_log warn "Context hierarchy truncated at $total_bytes bytes (limit: $max_bytes)"
            break
        fi
    done

    printf '%s' "$result"
}

# =============================================================================
# TOOL REGISTRY (OpenCode + Copilot patterns)
# =============================================================================

# Global tool registry (associative arrays)
declare -gA _AGENT_AI_TOOLS=()          # name -> definition JSON
declare -gA _AGENT_AI_TOOL_PERMS=()     # name -> permission (allow/deny/ask)
declare -gA _AGENT_AI_TOOL_LOADED=()    # name -> 1 if initialized

# Register a tool with lazy initialization
# Usage: agent_ai_tool_register "name" "description" "handler_function" [permission]
agent_ai_tool_register() {
    local name="$1"
    local description="$2"
    local handler="$3"
    local permission="${4:-$AGENT_AI_PERMISSION_ASK}"

    _AGENT_AI_TOOLS["$name"]="{\"name\":\"$name\",\"description\":\"$description\",\"handler\":\"$handler\"}"
    _AGENT_AI_TOOL_PERMS["$name"]="$permission"
    _AGENT_AI_TOOL_LOADED["$name"]=0

    agent_ai_transcript_append "tool_register" "{\"name\":\"$name\",\"permission\":\"$permission\"}"
}

# Check if tool use is permitted
# Usage: agent_ai_tool_permitted "name"
# Returns: 0=allowed, 1=denied, 2=needs_ask
agent_ai_tool_permitted() {
    local name="$1"
    local perm="${_AGENT_AI_TOOL_PERMS[$name]:-$AGENT_AI_PERMISSION_ASK}"

    case "$perm" in
        "$AGENT_AI_PERMISSION_ALLOW") return 0 ;;
        "$AGENT_AI_PERMISSION_DENY")  return 1 ;;
        "$AGENT_AI_PERMISSION_ASK")   return 2 ;;
        *) return 2 ;;
    esac
}

# Set tool permission (session or permanent)
# Usage: agent_ai_tool_approve "name" [--session|--permanent]
agent_ai_tool_approve() {
    local name="$1"
    local scope="${2:---session}"

    _AGENT_AI_TOOL_PERMS["$name"]="$AGENT_AI_PERMISSION_ALLOW"

    if [[ "$scope" == "--permanent" ]]; then
        _agent_ai_ensure_dir "$AGENT_AI_STATE_DIR"
        echo "$name=$AGENT_AI_PERMISSION_ALLOW" >> "${AGENT_AI_STATE_DIR}/tool_permissions"
    fi

    agent_ai_transcript_append "tool_approve" "{\"name\":\"$name\",\"scope\":\"${scope#--}\"}"
}

# Deny a tool
# Usage: agent_ai_tool_deny "name"
agent_ai_tool_deny() {
    local name="$1"
    _AGENT_AI_TOOL_PERMS["$name"]="$AGENT_AI_PERMISSION_DENY"
    agent_ai_transcript_append "tool_deny" "{\"name\":\"$name\"}"
}

# Invoke a tool with permission check
# Usage: agent_ai_tool_invoke "name" [args...]
# Returns: tool exit code or 126 if denied
agent_ai_tool_invoke() {
    local name="$1"
    shift

    local perm_check
    agent_ai_tool_permitted "$name"
    perm_check=$?

    if [[ $perm_check -eq 1 ]]; then
        _agent_ai_log error "Tool '$name' is denied"
        return 126
    fi

    if [[ $perm_check -eq 2 ]]; then
        _agent_ai_log warn "Tool '$name' requires approval"
        return 126
    fi

    # Lazy initialization
    if [[ "${_AGENT_AI_TOOL_LOADED[$name]:-0}" -eq 0 ]]; then
        _AGENT_AI_TOOL_LOADED["$name"]=1
    fi

    # Get handler and invoke
    local def="${_AGENT_AI_TOOLS[$name]:-}"
    if [[ -z "$def" ]]; then
        _agent_ai_log error "Tool '$name' not registered"
        return 127
    fi

    # Extract handler (simple JSON parse)
    local handler
    handler=$(printf '%s' "$def" | grep -oP '"handler":"\K[^"]+' 2>/dev/null || echo "")

    if [[ -z "$handler" ]]; then
        # Fallback extraction
        handler="${def#*\"handler\":\"}"
        handler="${handler%%\"*}"
    fi

    if declare -F "$handler" &>/dev/null; then
        agent_ai_transcript_append "tool_invoke" "{\"name\":\"$name\",\"args\":\"$*\"}"
        "$handler" "$@"
        local rc=$?
        agent_ai_transcript_append "tool_result" "{\"name\":\"$name\",\"exit_code\":$rc}"
        return $rc
    else
        _agent_ai_log error "Handler '$handler' not found for tool '$name'"
        return 127
    fi
}

# List registered tools as JSON
# Usage: agent_ai_tool_list
agent_ai_tool_list() {
    printf '['
    local first=1
    local name
    for name in "${!_AGENT_AI_TOOLS[@]}"; do
        [[ $first -eq 0 ]] && printf ','
        first=0
        local perm="${_AGENT_AI_TOOL_PERMS[$name]:-ask}"
        printf '{"name":"%s","permission":"%s"}' "$name" "$perm"
    done
    printf ']\n'
}

# Load permanent tool permissions from file
# Usage: agent_ai_tool_load_permissions
agent_ai_tool_load_permissions() {
    local perm_file="${AGENT_AI_STATE_DIR}/tool_permissions"
    [[ -f "$perm_file" ]] || return 0

    local line
    while IFS='=' read -r name perm; do
        [[ -z "$name" ]] && continue
        _AGENT_AI_TOOL_PERMS["$name"]="$perm"
    done < "$perm_file"
}

# =============================================================================
# OUTPUT SPILLOVER (OpenCode pattern)
# =============================================================================

# Truncate output with spillover to disk
# Usage: echo "content" | agent_ai_output_truncate [--direction head|tail]
# Returns: truncated content with spillover path if applicable
agent_ai_output_truncate() {
    local direction="tail"
    [[ "$1" == "--direction" ]] && direction="$2"

    local content
    content=$(cat)

    local line_count
    line_count=$(printf '%s' "$content" | wc -l)
    line_count="${line_count// /}"

    local byte_count=${#content}

    # Check if truncation needed
    if (( line_count <= AGENT_AI_MAX_OUTPUT_LINES && byte_count <= AGENT_AI_MAX_OUTPUT_BYTES )); then
        printf '%s' "$content"
        return 0
    fi

    # Spillover to disk
    _agent_ai_ensure_dir "${AGENT_AI_STATE_DIR}/spillover"
    local spillover_file="${AGENT_AI_STATE_DIR}/spillover/output_$(date +%Y%m%d_%H%M%S)_$$.txt"
    printf '%s' "$content" > "$spillover_file"

    # Truncate
    local truncated
    if [[ "$direction" == "head" ]]; then
        truncated=$(printf '%s' "$content" | head -n "$AGENT_AI_MAX_OUTPUT_LINES")
    else
        truncated=$(printf '%s' "$content" | tail -n "$AGENT_AI_MAX_OUTPUT_LINES")
    fi

    local truncated_lines=$(( line_count - AGENT_AI_MAX_OUTPUT_LINES ))

    printf '%s\n\n[Truncated %d lines. Full output: %s]\n' "$truncated" "$truncated_lines" "$spillover_file"
    printf '[Hint: Use grep/read with offset to access specific sections]\n'

    agent_ai_transcript_append "output_spillover" "{\"file\":\"$spillover_file\",\"lines\":$line_count,\"bytes\":$byte_count}"
}

# Clean old spillover files
# Usage: agent_ai_spillover_gc [days]
agent_ai_spillover_gc() {
    local days="${1:-$AGENT_AI_SPILLOVER_TTL_DAYS}"
    find "${AGENT_AI_STATE_DIR}/spillover" -type f -mtime "+$days" -delete 2>/dev/null
}

# =============================================================================
# EDIT FORMAT ABSTRACTION (Aider pattern)
# =============================================================================

# Apply edit using specified format strategy
# Usage: agent_ai_edit_apply "file" "edit_content" [--format diff|udiff|whole|patch]
agent_ai_edit_apply() {
    local file="$1"
    local edit_content="$2"
    shift 2

    local format="$AGENT_AI_EDIT_DIFF"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    agent_ai_transcript_append "edit_start" "{\"file\":\"$file\",\"format\":\"$format\"}"

    local rc=0
    case "$format" in
        "$AGENT_AI_EDIT_DIFF")
            _agent_ai_edit_search_replace "$file" "$edit_content"
            rc=$?
            ;;
        "$AGENT_AI_EDIT_UDIFF")
            _agent_ai_edit_unified_diff "$file" "$edit_content"
            rc=$?
            ;;
        "$AGENT_AI_EDIT_WHOLE")
            _agent_ai_edit_whole_file "$file" "$edit_content"
            rc=$?
            ;;
        "$AGENT_AI_EDIT_PATCH")
            _agent_ai_edit_patch "$file" "$edit_content"
            rc=$?
            ;;
        *)
            _agent_ai_log error "Unknown edit format: $format"
            rc=1
            ;;
    esac

    agent_ai_transcript_append "edit_result" "{\"file\":\"$file\",\"success\":$([[ $rc -eq 0 ]] && echo true || echo false)}"
    return $rc
}

# Internal: SEARCH/REPLACE block format (like Aider's EditBlock)
_agent_ai_edit_search_replace() {
    local file="$1"
    local content="$2"

    # Parse SEARCH/REPLACE blocks
    # Format:
    # <<<<<<< SEARCH
    # old text
    # =======
    # new text
    # >>>>>>> REPLACE
    # OR
    # <ORIGINAL>
    # old text
    # </ORIGINAL>
    # <UPDATED>
    # new text
    # </UPDATED>

    local in_search=0 in_replace=0
    local search_text="" replace_text=""
    local success=0

    while IFS= read -r line; do
        if [[ "$line" == "<<<<<<< SEARCH" ]] || [[ "$line" == "<ORIGINAL>" ]]; then
            in_search=1
            search_text=""
            continue
        elif [[ "$line" == "=======" ]]; then
            # Git-style format: ======= transitions from search to replace
            in_search=0
            in_replace=1
            replace_text=""
            continue
        elif [[ "$line" == "</ORIGINAL>" ]]; then
            in_search=0
            continue
        elif [[ "$line" == "<UPDATED>" ]]; then
            in_replace=1
            replace_text=""
            continue
        elif [[ "$line" == ">>>>>>> REPLACE" ]] || [[ "$line" == "</UPDATED>" ]]; then
            in_replace=0
            # Apply replacement
            if [[ -n "$search_text" ]]; then
                if declare -F diff_replace &>/dev/null; then
                    if diff_replace "$file" "$search_text" "$replace_text" --no-backup 2>/dev/null; then
                        success=1
                    else
                        _agent_ai_log warn "Search text not found or ambiguous"
                        return 1
                    fi
                else
                    # Fallback: simple replacement
                    local file_content
                    file_content=$(cat "$file")
                    if [[ "$file_content" == *"$search_text"* ]]; then
                        local new_content="${file_content/"$search_text"/"$replace_text"}"
                        printf '%s' "$new_content" > "$file"
                        success=1
                    else
                        _agent_ai_log warn "Search text not found"
                        return 1
                    fi
                fi
            fi
            search_text=""
            replace_text=""
            continue
        fi

        if [[ $in_search -eq 1 ]]; then
            [[ -n "$search_text" ]] && search_text+=$'\n'
            search_text+="$line"
        elif [[ $in_replace -eq 1 ]]; then
            [[ -n "$replace_text" ]] && replace_text+=$'\n'
            replace_text+="$line"
        fi
    done <<< "$content"

    [[ $success -eq 1 ]]
}

# Internal: Unified diff format
_agent_ai_edit_unified_diff() {
    local file="$1"
    local diff_content="$2"

    if declare -F diff_apply &>/dev/null; then
        diff_apply "$file" "$diff_content" --no-backup
    else
        # Fallback to patch command
        printf '%s' "$diff_content" | patch -p0 "$file" 2>/dev/null
    fi
}

# Internal: Whole file replacement
_agent_ai_edit_whole_file() {
    local file="$1"
    local content="$2"

    # Atomic write
    local tmpfile="${file}.tmp.$$"
    printf '%s' "$content" > "$tmpfile" && mv -f "$tmpfile" "$file"
}

# Internal: Patch format
_agent_ai_edit_patch() {
    local file="$1"
    local patch_content="$2"

    printf '%s' "$patch_content" | patch -p0 "$file" 2>/dev/null
}

# Get model-specific edit format default (Aider pattern)
# Usage: agent_ai_model_edit_format "model_name"
agent_ai_model_edit_format() {
    local model="$1"

    case "$model" in
        *claude*opus*|*claude-opus*) echo "$AGENT_AI_EDIT_WHOLE" ;;
        *claude*sonnet*|*claude-sonnet*) echo "$AGENT_AI_EDIT_DIFF" ;;
        *gpt-4*|*gpt-4o*) echo "$AGENT_AI_EDIT_UDIFF" ;;
        *deepseek*) echo "$AGENT_AI_EDIT_DIFF" ;;
        *gemini*) echo "$AGENT_AI_EDIT_WHOLE" ;;
        *glm*) echo "$AGENT_AI_EDIT_DIFF" ;;
        *) echo "$AGENT_AI_EDIT_DIFF" ;;
    esac
}

# =============================================================================
# REFLECTION LOOP (Aider pattern)
# =============================================================================

# Run a reflection loop with max iterations
# Calls validator_fn, if fails calls reflector_fn for adjustment
# Usage: agent_ai_reflect "task" validator_fn reflector_fn [max_iterations]
agent_ai_reflect() {
    local task="$1"
    local validator_fn="$2"
    local reflector_fn="$3"
    local max_iter="${4:-3}"

    local iteration=0

    while (( iteration < max_iter )); do
        ((iteration++))

        agent_ai_transcript_append "reflect_iter" "{\"iteration\":$iteration,\"task\":\"$task\"}"

        # Validate current state
        if "$validator_fn" "$task"; then
            agent_ai_transcript_append "reflect_success" "{\"iterations\":$iteration}"
            return 0
        fi

        # Reflect and adjust
        if ! "$reflector_fn" "$task" "$iteration"; then
            _agent_ai_log warn "Reflection failed at iteration $iteration"
        fi
    done

    _agent_ai_log error "Reflection loop exhausted after $max_iter iterations"
    agent_ai_transcript_append "reflect_exhausted" "{\"max_iterations\":$max_iter}"
    return 1
}

# =============================================================================
# SESSION MANAGEMENT (Codex + Copilot patterns)
# =============================================================================

# Start a new agent session
# Usage: agent_ai_session_start [session_name]
agent_ai_session_start() {
    local name="${1:-session_$(_agent_ai_uuid | cut -c1-8)}"

    _agent_ai_ensure_dir "$AGENT_AI_STATE_DIR"
    _agent_ai_ensure_dir "$AGENT_AI_TRANSCRIPT_DIR"

    export AGENT_AI_SESSION_ID="$name"
    export AGENT_AI_SESSION_START="$(_agent_ai_timestamp)"
    export AGENT_AI_SESSION_STATUS="$AGENT_AI_SESSION_ACTIVE"

    cat > "${AGENT_AI_STATE_DIR}/${name}.session" << EOF
AGENT_AI_SESSION_ID=$name
AGENT_AI_SESSION_START=$AGENT_AI_SESSION_START
AGENT_AI_SESSION_STATUS=$AGENT_AI_SESSION_STATUS
AGENT_AI_SESSION_CWD=$(pwd)
AGENT_AI_SESSION_USER=${USER:-$(whoami)}
EOF

    # Initialize transcript
    printf '{"session":"%s","started":"%s","events":[\n' "$name" "$AGENT_AI_SESSION_START" \
        > "${AGENT_AI_TRANSCRIPT_DIR}/${name}.jsonl"

    agent_ai_context_init

    _agent_ai_log info "Session started: $name"
    printf '%s' "$name"
}

# Resume an existing session
# Usage: agent_ai_session_resume session_id
agent_ai_session_resume() {
    local session_id="$1"
    local session_file="${AGENT_AI_STATE_DIR}/${session_id}.session"

    if [[ ! -f "$session_file" ]]; then
        _agent_ai_log error "Session not found: $session_id"
        return 1
    fi

    source "$session_file"
    export AGENT_AI_SESSION_ID AGENT_AI_SESSION_START AGENT_AI_SESSION_STATUS

    # Restore context state if exists
    local context_file="${AGENT_AI_STATE_DIR}/${session_id}.context"
    [[ -f "$context_file" ]] && source "$context_file"

    agent_ai_transcript_append "session_resume" "{\"session\":\"$session_id\"}"

    _agent_ai_log info "Session resumed: $session_id"
}

# Fork current session (for safe parallel exploration)
# Usage: agent_ai_session_fork [new_name]
agent_ai_session_fork() {
    local parent_id="${AGENT_AI_SESSION_ID:-}"
    local new_name="${1:-fork_$(_agent_ai_uuid | cut -c1-8)}"

    if [[ -z "$parent_id" ]]; then
        _agent_ai_log error "No active session to fork"
        return 1
    fi

    # Copy session state
    cp "${AGENT_AI_STATE_DIR}/${parent_id}.session" "${AGENT_AI_STATE_DIR}/${new_name}.session"
    cp "${AGENT_AI_STATE_DIR}/${parent_id}.context" "${AGENT_AI_STATE_DIR}/${new_name}.context" 2>/dev/null

    # Update fork metadata
    sed -i "s/AGENT_AI_SESSION_ID=.*/AGENT_AI_SESSION_ID=$new_name/" "${AGENT_AI_STATE_DIR}/${new_name}.session"
    echo "AGENT_AI_SESSION_PARENT=$parent_id" >> "${AGENT_AI_STATE_DIR}/${new_name}.session"

    # Start new transcript
    printf '{"session":"%s","forked_from":"%s","started":"%s","events":[\n' \
        "$new_name" "$parent_id" "$(_agent_ai_timestamp)" \
        > "${AGENT_AI_TRANSCRIPT_DIR}/${new_name}.jsonl"

    agent_ai_transcript_append "session_fork" "{\"parent\":\"$parent_id\",\"child\":\"$new_name\"}"

    _agent_ai_log info "Session forked: $parent_id -> $new_name"
    printf '%s' "$new_name"
}

# End current session
# Usage: agent_ai_session_end [status]
agent_ai_session_end() {
    local status="${1:-$AGENT_AI_SESSION_COMPLETED}"
    local session_id="${AGENT_AI_SESSION_ID:-}"

    if [[ -z "$session_id" ]]; then
        return 0
    fi

    AGENT_AI_SESSION_STATUS="$status"
    AGENT_AI_SESSION_END="$(_agent_ai_timestamp)"

    # Update session file
    cat >> "${AGENT_AI_STATE_DIR}/${session_id}.session" << EOF
AGENT_AI_SESSION_STATUS=$status
AGENT_AI_SESSION_END=$AGENT_AI_SESSION_END
EOF

    # Close transcript
    agent_ai_transcript_append "session_end" "{\"status\":\"$status\"}"
    printf ']}\n' >> "${AGENT_AI_TRANSCRIPT_DIR}/${session_id}.jsonl"

    _agent_ai_log info "Session ended: $session_id ($status)"

    unset AGENT_AI_SESSION_ID AGENT_AI_SESSION_START AGENT_AI_SESSION_STATUS
}

# List recent sessions
# Usage: agent_ai_session_list [--limit N]
agent_ai_session_list() {
    local limit=10
    [[ "$1" == "--limit" ]] && limit="$2"

    printf '['
    local first=1
    local f
    for f in $(ls -t "${AGENT_AI_STATE_DIR}"/*.session 2>/dev/null | head -n "$limit"); do
        source "$f"
        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"id":"%s","started":"%s","status":"%s"}' \
            "$AGENT_AI_SESSION_ID" "$AGENT_AI_SESSION_START" "$AGENT_AI_SESSION_STATUS"
    done
    printf ']\n'
}

# =============================================================================
# TRANSCRIPT LOGGING (Codex pattern)
# =============================================================================

# Append event to transcript (immutable log)
# Usage: agent_ai_transcript_append "event_type" "data_json"
agent_ai_transcript_append() {
    local event_type="$1"
    local data="$2"
    local session_id="${AGENT_AI_SESSION_ID:-default}"

    _agent_ai_ensure_dir "$AGENT_AI_TRANSCRIPT_DIR"

    local transcript="${AGENT_AI_TRANSCRIPT_DIR}/${session_id}.jsonl"

    printf '{"time":"%s","type":"%s","data":%s}\n' \
        "$(_agent_ai_timestamp)" "$event_type" "${data:-null}" >> "$transcript"
}

# Search transcript for events
# Usage: agent_ai_transcript_search "pattern" [session_id]
agent_ai_transcript_search() {
    local pattern="$1"
    local session_id="${2:-${AGENT_AI_SESSION_ID:-}}"

    if [[ -n "$session_id" ]]; then
        grep -E "$pattern" "${AGENT_AI_TRANSCRIPT_DIR}/${session_id}.jsonl" 2>/dev/null
    else
        grep -rE "$pattern" "${AGENT_AI_TRANSCRIPT_DIR}" 2>/dev/null
    fi
}

# Get transcript as JSON array
# Usage: agent_ai_transcript_get [session_id]
agent_ai_transcript_get() {
    local session_id="${1:-${AGENT_AI_SESSION_ID:-}}"
    local transcript="${AGENT_AI_TRANSCRIPT_DIR}/${session_id}.jsonl"

    [[ -f "$transcript" ]] || { echo '[]'; return 1; }

    printf '['
    local first=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "{"* ]] || continue
        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '%s' "$line"
    done < "$transcript"
    printf ']\n'
}

# =============================================================================
# GATED HANDOFFS (Codex pattern)
# =============================================================================

# Define a phase gate with validation
# Usage: agent_ai_gate_define "gate_name" validator_fn
declare -gA _AGENT_AI_GATES=()

agent_ai_gate_define() {
    local name="$1"
    local validator="$2"
    _AGENT_AI_GATES["$name"]="$validator"
}

# Check if ready to pass through gate
# Usage: agent_ai_gate_check "gate_name"
agent_ai_gate_check() {
    local name="$1"
    local validator="${_AGENT_AI_GATES[$name]:-}"

    if [[ -z "$validator" ]]; then
        _agent_ai_log error "Gate not defined: $name"
        return 1
    fi

    agent_ai_transcript_append "gate_check" "{\"gate\":\"$name\"}"

    if "$validator"; then
        agent_ai_transcript_append "gate_passed" "{\"gate\":\"$name\"}"
        return 0
    else
        agent_ai_transcript_append "gate_failed" "{\"gate\":\"$name\"}"
        return 1
    fi
}

# Wait for gate with timeout
# Usage: agent_ai_gate_wait "gate_name" [timeout_seconds] [poll_interval]
agent_ai_gate_wait() {
    local name="$1"
    local timeout="${2:-3600}"  # 1 hour default
    local interval="${3:-30}"   # 30 seconds

    local elapsed=0
    while (( elapsed < timeout )); do
        if agent_ai_gate_check "$name"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    _agent_ai_log error "Gate timeout: $name (waited ${elapsed}s)"
    return 1
}

# =============================================================================
# SUBAGENT ORCHESTRATION (Claude Code pattern)
# =============================================================================

# Spawn a subagent (simulated in bash via backgrounded process)
# Usage: agent_ai_spawn "task_description" handler_fn [--parallel]
agent_ai_spawn() {
    local task="$1"
    local handler="$2"
    local parallel=0
    [[ "${3:-}" == "--parallel" ]] && parallel=1

    local subagent_id="sub_$(_agent_ai_uuid | cut -c1-8)"

    agent_ai_transcript_append "subagent_spawn" "{\"id\":\"$subagent_id\",\"task\":\"$task\",\"parallel\":$parallel}"

    if [[ $parallel -eq 1 ]]; then
        (
            export AGENT_AI_SUBAGENT_ID="$subagent_id"
            export AGENT_AI_PARENT_SESSION="${AGENT_AI_SESSION_ID:-}"
            "$handler" "$task"
        ) &
        printf '%s:%d' "$subagent_id" "$!"
    else
        export AGENT_AI_SUBAGENT_ID="$subagent_id"
        "$handler" "$task"
        local rc=$?
        unset AGENT_AI_SUBAGENT_ID
        return $rc
    fi
}

# Wait for parallel subagents to complete
# Usage: agent_ai_await pid1 pid2 ...
agent_ai_await() {
    local -a pids=("$@")
    local -a failed=()

    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || failed+=("$pid")
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        _agent_ai_log warn "Some subagents failed: ${failed[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# FILE REFERENCE SYSTEM (Copilot @ pattern)
# =============================================================================

# Track referenced files in session
declare -ga _AGENT_AI_REF_FILES=()

# Add file to context references
# Usage: agent_ai_ref_add "path"
agent_ai_ref_add() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        _agent_ai_log warn "Referenced file not found: $path"
        return 1
    fi

    local abs_path
    abs_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")

    # Avoid duplicates
    local f
    for f in "${_AGENT_AI_REF_FILES[@]}"; do
        [[ "$f" == "$abs_path" ]] && return 0
    done

    _AGENT_AI_REF_FILES+=("$abs_path")
    agent_ai_transcript_append "file_ref" "{\"path\":\"$abs_path\"}"
}

# List referenced files
# Usage: agent_ai_ref_list
agent_ai_ref_list() {
    printf '%s\n' "${_AGENT_AI_REF_FILES[@]}"
}

# Clear file references
# Usage: agent_ai_ref_clear
agent_ai_ref_clear() {
    _AGENT_AI_REF_FILES=()
}

# Estimate tokens for all referenced files
# Usage: agent_ai_ref_tokens
agent_ai_ref_tokens() {
    local total=0
    local f
    for f in "${_AGENT_AI_REF_FILES[@]}"; do
        if declare -F context_file_tokens &>/dev/null; then
            local ft
            ft=$(context_file_tokens "$f")
            total=$(( total + ft ))
        else
            # Fallback: estimate ~4 chars per token
            local chars
            chars=$(wc -c < "$f" 2>/dev/null)
            chars="${chars// /}"
            total=$(( total + chars / 4 ))
        fi
    done
    echo "$total"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if running in agent context
# Usage: agent_ai_is_active
agent_ai_is_active() {
    [[ -n "${AGENT_AI_SESSION_ID:-}" ]]
}

# Get agent status summary
# Usage: agent_ai_status
agent_ai_status() {
    local session="${AGENT_AI_SESSION_ID:-none}"
    local ctx_status
    ctx_status=$(agent_ai_context_status 2>/dev/null || echo '{"status":"uninitialized"}')
    local tool_count="${#_AGENT_AI_TOOLS[@]}"
    local ref_count="${#_AGENT_AI_REF_FILES[@]}"

    printf '{"session":"%s","context":%s,"tools":%d,"file_refs":%d}\n' \
        "$session" "$ctx_status" "$tool_count" "$ref_count"
}

# Initialize agent AI subsystem
# Usage: agent_ai_init
agent_ai_init() {
    _agent_ai_ensure_dir "$AGENT_AI_STATE_DIR"
    _agent_ai_ensure_dir "$AGENT_AI_TRANSCRIPT_DIR"
    _agent_ai_ensure_dir "${AGENT_AI_STATE_DIR}/spillover"
    agent_ai_tool_load_permissions
    return 0
}

# Cleanup old state files
# Usage: agent_ai_cleanup [--older-than days]
agent_ai_cleanup() {
    local days=7
    [[ "$1" == "--older-than" ]] && days="$2"

    find "$AGENT_AI_STATE_DIR" -type f -mtime "+$days" -delete 2>/dev/null
    find "$AGENT_AI_TRANSCRIPT_DIR" -type f -mtime "+$days" -delete 2>/dev/null
    agent_ai_spillover_gc "$days"

    _agent_ai_log info "Cleaned up files older than $days days"
}

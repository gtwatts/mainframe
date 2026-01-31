#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/capability.sh - Capability-Based Security Model
# =============================================================================
# Description: Fine-grained permission system for AI agents using capability
#              tokens. Provides least-privilege access control with auditing.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Security is not a product, but a process." - Bruce Schneier
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CAPABILITY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CAPABILITY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable audit logging (1=enabled, 0=disabled)
MAINFRAME_CAP_AUDIT="${MAINFRAME_CAP_AUDIT:-0}"

# Capability log file (if set, logs to file)
MAINFRAME_CAP_LOG_FILE="${MAINFRAME_CAP_LOG_FILE:-}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Agent capabilities: key="agent_id:capability", value=1
declare -gA _CAP_GRANTS=()

# Audit log (in-memory)
declare -ga _CAP_AUDIT_LOG=()

# Capability token regex: cap://<domain>/<action>/<resource>
readonly _CAP_TOKEN_REGEX='^cap://[a-z]+/[a-z]+/.+'

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Log capability event
# Usage: _cap_log "GRANT|REVOKE|USE|DENIED" "agent_id" "capability"
_cap_log() {
    local action="$1"
    local agent_id="$2"
    local capability="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)

    local entry="${timestamp} ${action} ${agent_id} ${capability}"
    _CAP_AUDIT_LOG+=("$entry")

    # Console logging if enabled
    if [[ "${MAINFRAME_CAP_AUDIT}" == "1" ]]; then
        printf '[capability] %s\n' "$entry" >&2
    fi

    # File logging if configured
    if [[ -n "${MAINFRAME_CAP_LOG_FILE}" ]]; then
        printf '%s\n' "$entry" >> "${MAINFRAME_CAP_LOG_FILE}" 2>/dev/null
    fi
}

# Check if capability matches pattern (supports wildcards)
# Usage: _cap_matches "cap://fs/read/home/user/file" "cap://fs/read/home/*"
_cap_matches() {
    local capability="$1"
    local pattern="$2"

    # Exact match
    [[ "$capability" == "$pattern" ]] && return 0

    # Extract parts
    local cap_domain cap_action cap_resource
    cap_domain="${capability#cap://}"
    cap_domain="${cap_domain%%/*}"
    cap_action="${capability#cap://${cap_domain}/}"
    cap_action="${cap_action%%/*}"
    cap_resource="${capability#cap://${cap_domain}/${cap_action}/}"

    local pat_domain pat_action pat_resource
    pat_domain="${pattern#cap://}"
    pat_domain="${pat_domain%%/*}"
    pat_action="${pattern#cap://${pat_domain}/}"
    pat_action="${pat_action%%/*}"
    pat_resource="${pattern#cap://${pat_domain}/${pat_action}/}"

    # Domain must match exactly
    [[ "$cap_domain" != "$pat_domain" ]] && return 1

    # Action must match exactly
    [[ "$cap_action" != "$pat_action" ]] && return 1

    # Resource can use wildcards
    if [[ "$pat_resource" == "*" ]]; then
        return 0
    fi

    # Check wildcard suffix (e.g., "home/*" matches "home/user/file")
    if [[ "$pat_resource" == *'*' ]]; then
        local prefix="${pat_resource%\*}"
        [[ "$cap_resource" == "$prefix"* ]] && return 0
    fi

    # Check exact resource match
    [[ "$cap_resource" == "$pat_resource" ]]
}

# Validate capability token format
# Usage: _cap_validate "cap://fs/read/home/*"
_cap_validate() {
    local capability="$1"
    [[ "$capability" =~ $_CAP_TOKEN_REGEX ]]
}

# =============================================================================
# CAPABILITY MANAGEMENT
# =============================================================================

# Grant a capability to an agent
# @param agent_id - Agent identifier
# @param capability - Capability token (cap://domain/action/resource)
# @returns 0 on success, 1 on invalid input
#
# Usage: cap_grant "search_agent" "cap://fs/read/home/*"
cap_grant() {
    local agent_id="$1"
    local capability="$2"

    # Validate inputs
    if [[ -z "$agent_id" ]]; then
        printf 'cap_grant: agent_id required\n' >&2
        return 1
    fi

    if [[ -z "$capability" ]]; then
        printf 'cap_grant: capability required\n' >&2
        return 1
    fi

    if ! _cap_validate "$capability"; then
        printf 'cap_grant: invalid capability format: %s\n' "$capability" >&2
        return 1
    fi

    # Store grant
    local key="${agent_id}:${capability}"
    _CAP_GRANTS[$key]=1

    _cap_log "GRANT" "$agent_id" "$capability"
    return 0
}

# Revoke a capability from an agent
# @param agent_id - Agent identifier
# @param capability - Capability token to revoke
# @returns 0 on success
#
# Usage: cap_revoke "agent_id" "cap://fs/write/*"
cap_revoke() {
    local agent_id="$1"
    local capability="$2"

    if [[ -z "$agent_id" || -z "$capability" ]]; then
        return 1
    fi

    local key="${agent_id}:${capability}"
    unset "_CAP_GRANTS[$key]"

    _cap_log "REVOKE" "$agent_id" "$capability"
    return 0
}

# Revoke all capabilities from an agent
# @param agent_id - Agent identifier
# @returns 0 on success
#
# Usage: cap_revoke_all "agent_id"
cap_revoke_all() {
    local agent_id="$1"

    [[ -z "$agent_id" ]] && return 1

    local key
    for key in "${!_CAP_GRANTS[@]}"; do
        if [[ "$key" == "${agent_id}:"* ]]; then
            unset "_CAP_GRANTS[$key]"
        fi
    done

    _cap_log "REVOKE_ALL" "$agent_id" "*"
    return 0
}

# Check if agent has a capability (without logging usage)
# @param agent_id - Agent identifier
# @param capability - Capability to check
# @returns 0 if granted, 1 if not
#
# Usage: cap_has "agent_id" "cap://fs/read/etc/passwd" && cat /etc/passwd
cap_has() {
    local agent_id="$1"
    local capability="$2"

    [[ -z "$agent_id" || -z "$capability" ]] && return 1

    # Check exact match first
    local key="${agent_id}:${capability}"
    [[ -n "${_CAP_GRANTS[$key]:-}" ]] && return 0

    # Check pattern matches
    local pattern
    for pattern in "${!_CAP_GRANTS[@]}"; do
        [[ "$pattern" != "${agent_id}:"* ]] && continue
        local cap_pattern="${pattern#${agent_id}:}"
        if _cap_matches "$capability" "$cap_pattern"; then
            return 0
        fi
    done

    return 1
}

# Use a capability (check + log usage)
# @param agent_id - Agent identifier
# @param capability - Capability to use
# @returns 0 if granted, 1 if denied
#
# Usage: cap_use "agent_id" "cap://fs/read/etc/passwd" || return 1
cap_use() {
    local agent_id="$1"
    local capability="$2"

    if cap_has "$agent_id" "$capability"; then
        _cap_log "USE" "$agent_id" "$capability"
        return 0
    else
        _cap_log "DENIED" "$agent_id" "$capability"
        return 1
    fi
}

# List all capabilities for an agent
# @param agent_id - Agent identifier
# @returns List of capability tokens, one per line
#
# Usage: cap_list "agent_id"
cap_list() {
    local agent_id="$1"

    [[ -z "$agent_id" ]] && return 1

    local key
    for key in "${!_CAP_GRANTS[@]}"; do
        [[ "$key" == "${agent_id}:"* ]] && printf '%s\n' "${key#${agent_id}:}"
    done
}

# List all agents with capabilities
# @returns List of agent IDs, one per line
#
# Usage: cap_list_agents
cap_list_agents() {
    local key
    local -A agents=()

    for key in "${!_CAP_GRANTS[@]}"; do
        local agent="${key%%:*}"
        agents[$agent]=1
    done

    printf '%s\n' "${!agents[@]}"
}

# =============================================================================
# CAPABILITY PROFILES (Preset Permission Sets)
# =============================================================================

# Grant a preset profile to an agent
# @param agent_id - Agent identifier
# @param profile - Profile name: minimal, readonly, developer, network, admin
# @returns 0 on success
#
# Usage: cap_grant_profile "agent_id" "developer"
cap_grant_profile() {
    local agent_id="$1"
    local profile="$2"

    [[ -z "$agent_id" || -z "$profile" ]] && return 1

    case "$profile" in
        minimal)
            # Absolute minimum - only temp files and echo
            cap_grant "$agent_id" "cap://fs/read/tmp/*"
            cap_grant "$agent_id" "cap://fs/write/tmp/*"
            cap_grant "$agent_id" "cap://exec/run/echo"
            ;;

        readonly)
            # Read-only access, safe commands
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://exec/run/ls"
            cap_grant "$agent_id" "cap://exec/run/cat"
            cap_grant "$agent_id" "cap://exec/run/grep"
            cap_grant "$agent_id" "cap://exec/run/find"
            cap_grant "$agent_id" "cap://exec/run/wc"
            cap_grant "$agent_id" "cap://exec/run/head"
            cap_grant "$agent_id" "cap://exec/run/tail"
            cap_grant "$agent_id" "cap://exec/run/file"
            ;;

        developer)
            # Standard development workflow
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://fs/write/home/*"
            cap_grant "$agent_id" "cap://fs/write/tmp/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://exec/run/git"
            cap_grant "$agent_id" "cap://exec/run/npm"
            cap_grant "$agent_id" "cap://exec/run/node"
            cap_grant "$agent_id" "cap://exec/run/python"
            cap_grant "$agent_id" "cap://exec/run/python3"
            cap_grant "$agent_id" "cap://exec/run/pip"
            cap_grant "$agent_id" "cap://exec/run/pip3"
            cap_grant "$agent_id" "cap://exec/run/make"
            cap_grant "$agent_id" "cap://exec/run/bash"
            cap_grant "$agent_id" "cap://exec/run/ls"
            cap_grant "$agent_id" "cap://exec/run/cat"
            cap_grant "$agent_id" "cap://exec/run/grep"
            cap_grant "$agent_id" "cap://exec/run/find"
            cap_grant "$agent_id" "cap://exec/run/mkdir"
            cap_grant "$agent_id" "cap://exec/run/cp"
            cap_grant "$agent_id" "cap://exec/run/mv"
            cap_grant "$agent_id" "cap://exec/run/rm"
            cap_grant "$agent_id" "cap://exec/run/touch"
            ;;

        network)
            # Network operations only
            cap_grant "$agent_id" "cap://net/http/*"
            cap_grant "$agent_id" "cap://net/tcp/*"
            cap_grant "$agent_id" "cap://exec/run/curl"
            cap_grant "$agent_id" "cap://exec/run/wget"
            ;;

        admin)
            # Full access (use sparingly)
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://fs/write/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://env/write/*"
            cap_grant "$agent_id" "cap://exec/run/*"
            cap_grant "$agent_id" "cap://net/http/*"
            cap_grant "$agent_id" "cap://net/tcp/*"
            ;;

        *)
            printf 'cap_grant_profile: unknown profile: %s\n' "$profile" >&2
            return 1
            ;;
    esac

    _cap_log "PROFILE" "$agent_id" "$profile"
    return 0
}

# =============================================================================
# CAPABILITY-GUARDED OPERATIONS
# =============================================================================

# Read a file with capability check
# @param agent_id - Agent identifier
# @param path - File path to read
# @returns File contents on success, 1 on permission denied
#
# Usage: content=$(cap_read_file "agent" "/etc/hosts")
cap_read_file() {
    local agent_id="$1"
    local path="$2"

    [[ -z "$agent_id" || -z "$path" ]] && return 1

    # Normalize path (remove leading slash for capability)
    local resource="${path#/}"
    local cap="cap://fs/read/${resource}"

    if ! cap_use "$agent_id" "$cap"; then
        printf 'Permission denied: %s\n' "$cap" >&2
        return 1
    fi

    if [[ ! -f "$path" ]]; then
        printf 'File not found: %s\n' "$path" >&2
        return 1
    fi

    cat "$path"
}

# Write a file with capability check
# @param agent_id - Agent identifier
# @param path - File path to write
# @param content - Content to write
# @returns 0 on success, 1 on failure
#
# Usage: cap_write_file "agent" "/tmp/out.txt" "content"
cap_write_file() {
    local agent_id="$1"
    local path="$2"
    local content="$3"

    [[ -z "$agent_id" || -z "$path" ]] && return 1

    local resource="${path#/}"
    local cap="cap://fs/write/${resource}"

    if ! cap_use "$agent_id" "$cap"; then
        printf 'Permission denied: %s\n' "$cap" >&2
        return 1
    fi

    # Use atomic_write if available
    if declare -F atomic_write &>/dev/null; then
        atomic_write "$path" "$content"
    else
        printf '%s' "$content" > "$path"
    fi
}

# Execute a command with capability check
# @param agent_id - Agent identifier
# @param cmd - Command to execute (can include args)
# @returns Command output on success, 1 on permission denied
#
# Usage: cap_exec "agent" "git status"
cap_exec() {
    local agent_id="$1"
    local cmd="$2"

    [[ -z "$agent_id" || -z "$cmd" ]] && return 1

    # Extract base command
    local base_cmd="${cmd%% *}"
    base_cmd="${base_cmd##*/}"  # Remove path

    local cap="cap://exec/run/${base_cmd}"

    if ! cap_use "$agent_id" "$cap"; then
        printf 'Permission denied: %s\n' "$cap" >&2
        return 1
    fi

    # Execute in subprocess for isolation
    bash -c "$cmd"
}

# Read environment variable with capability check
# @param agent_id - Agent identifier
# @param var_name - Variable name to read
# @returns Variable value on success, 1 on permission denied
#
# Usage: home=$(cap_env_get "agent" "HOME")
cap_env_get() {
    local agent_id="$1"
    local var_name="$2"

    [[ -z "$agent_id" || -z "$var_name" ]] && return 1

    local cap="cap://env/read/${var_name}"

    if ! cap_use "$agent_id" "$cap"; then
        printf 'Permission denied: %s\n' "$cap" >&2
        return 1
    fi

    printf '%s' "${!var_name}"
}

# Set environment variable with capability check
# @param agent_id - Agent identifier
# @param var_name - Variable name to set
# @param value - Value to set
# @returns 0 on success, 1 on permission denied
#
# Usage: cap_env_set "agent" "MY_VAR" "value"
cap_env_set() {
    local agent_id="$1"
    local var_name="$2"
    local value="$3"

    [[ -z "$agent_id" || -z "$var_name" ]] && return 1

    local cap="cap://env/write/${var_name}"

    if ! cap_use "$agent_id" "$cap"; then
        printf 'Permission denied: %s\n' "$cap" >&2
        return 1
    fi

    export "${var_name}=${value}"
}

# =============================================================================
# AUDIT LOG ACCESS
# =============================================================================

# Get audit log entries
# @param limit - Optional maximum number of entries (default: all)
# @returns Log entries, one per line
#
# Usage: cap_audit_log 100
cap_audit_log() {
    local limit="${1:-0}"
    local count=0
    local entry

    if [[ "$limit" -gt 0 ]]; then
        # Return last N entries
        local start=$((${#_CAP_AUDIT_LOG[@]} - limit))
        [[ "$start" -lt 0 ]] && start=0

        for ((i = start; i < ${#_CAP_AUDIT_LOG[@]}; i++)); do
            printf '%s\n' "${_CAP_AUDIT_LOG[i]}"
        done
    else
        # Return all entries
        for entry in "${_CAP_AUDIT_LOG[@]}"; do
            printf '%s\n' "$entry"
        done
    fi
}

# Get audit log as JSON
# @returns JSON array of log entries
#
# Usage: cap_audit_log_json
cap_audit_log_json() {
    local first=1
    printf '['

    for entry in "${_CAP_AUDIT_LOG[@]}"; do
        [[ "$first" -eq 0 ]] && printf ','
        first=0

        # Parse entry: timestamp action agent capability
        local ts action agent cap
        read -r ts action agent cap <<< "$entry"

        printf '{"timestamp":"%s","action":"%s","agent":"%s","capability":"%s"}' \
            "$ts" "$action" "$agent" "$cap"
    done

    printf ']\n'
}

# Count denied operations for an agent
# @param agent_id - Agent identifier
# @returns Count of DENIED entries
#
# Usage: denied=$(cap_denied_count "agent")
cap_denied_count() {
    local agent_id="$1"
    local count=0

    for entry in "${_CAP_AUDIT_LOG[@]}"; do
        if [[ "$entry" == *" DENIED $agent_id "* ]]; then
            ((count++))
        fi
    done

    printf '%d' "$count"
}

# =============================================================================
# MANAGEMENT
# =============================================================================

# Reset all capabilities and audit log (for testing)
# Usage: cap_reset
cap_reset() {
    _CAP_GRANTS=()
    _CAP_AUDIT_LOG=()
}

# Get capability statistics
# @returns JSON with stats
#
# Usage: cap_stats
cap_stats() {
    local total_grants=${#_CAP_GRANTS[@]}
    local total_log=${#_CAP_AUDIT_LOG[@]}
    local agents
    agents=$(cap_list_agents | wc -l)

    local grants=0 revokes=0 uses=0 denials=0
    for entry in "${_CAP_AUDIT_LOG[@]}"; do
        case "$entry" in
            *" GRANT "*) ((grants++)) ;;
            *" REVOKE "*) ((revokes++)) ;;
            *" USE "*) ((uses++)) ;;
            *" DENIED "*) ((denials++)) ;;
        esac
    done

    printf '{"active_grants":%d,"unique_agents":%d,"audit_entries":%d,"grants":%d,"revokes":%d,"uses":%d,"denials":%d}\n' \
        "$total_grants" "$agents" "$total_log" "$grants" "$revokes" "$uses" "$denials"
}

# =============================================================================
# CAPABILITY TRANSFER (For Agent Handoff)
# =============================================================================

# Export agent's capabilities as JSON
# @param agent_id - Source agent
# @returns JSON array of capabilities
#
# Usage: caps=$(cap_export "parent_agent")
cap_export() {
    local agent_id="$1"

    [[ -z "$agent_id" ]] && return 1

    local first=1
    printf '['

    local key
    for key in "${!_CAP_GRANTS[@]}"; do
        [[ "$key" != "${agent_id}:"* ]] && continue

        [[ "$first" -eq 0 ]] && printf ','
        first=0

        printf '"%s"' "${key#${agent_id}:}"
    done

    printf ']\n'
}

# Import capabilities from JSON to an agent
# @param agent_id - Target agent
# @param json_caps - JSON array of capability strings
# @returns 0 on success
#
# Usage: cap_import "child_agent" "$caps"
cap_import() {
    local agent_id="$1"
    local json_caps="$2"

    [[ -z "$agent_id" || -z "$json_caps" ]] && return 1

    # Parse JSON array and grant each capability
    # Simple parsing for array of strings
    local cap
    while IFS= read -r cap; do
        [[ -z "$cap" ]] && continue
        # Remove quotes
        cap="${cap#\"}"
        cap="${cap%\"}"
        cap_grant "$agent_id" "$cap"
    done < <(echo "$json_caps" | tr -d '[]' | tr ',' '\n')
}

# Delegate subset of capabilities to child agent
# @param parent_id - Parent agent
# @param child_id - Child agent
# @param filter - Optional pattern to filter capabilities (e.g., "cap://fs/*")
# @returns 0 on success
#
# Usage: cap_delegate "parent" "child" "cap://fs/*"
cap_delegate() {
    local parent_id="$1"
    local child_id="$2"
    local filter="${3:-*}"

    [[ -z "$parent_id" || -z "$child_id" ]] && return 1

    local key
    for key in "${!_CAP_GRANTS[@]}"; do
        [[ "$key" != "${parent_id}:"* ]] && continue

        local cap="${key#${parent_id}:}"

        # Apply filter (simple prefix matching with wildcard support)
        if [[ "$filter" != "*" ]]; then
            # Convert filter to prefix for matching
            local prefix="${filter%\*}"
            if [[ "$filter" == *'*' ]]; then
                # Wildcard filter - check prefix
                [[ "$cap" != "$prefix"* ]] && continue
            else
                # Exact match required
                [[ "$cap" != "$filter" ]] && continue
            fi
        fi

        cap_grant "$child_id" "$cap"
    done

    _cap_log "DELEGATE" "$parent_id" "${child_id}:${filter}"
}

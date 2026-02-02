#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/policy.sh - Policy-as-Code Guardrails for AI Agents
# =============================================================================
# Description: Declarative policy enforcement for AI agent operations.
#              Supports allow/deny/require_approval effects with glob patterns,
#              audit logging in JSONL format, and human-in-the-loop approval.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_POLICY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_POLICY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Policy storage directory
declare -g POLICY_DIR="${POLICY_DIR:-${TMPDIR:-/tmp}/mainframe_policy_$$}"

# Audit log file (JSONL format)
declare -g POLICY_AUDIT_LOG="${POLICY_AUDIT_LOG:-${POLICY_DIR}/audit.jsonl}"

# Pending approvals file
declare -g POLICY_PENDING_FILE="${POLICY_PENDING_FILE:-${POLICY_DIR}/pending.jsonl}"

# Approved actions file
declare -g POLICY_APPROVED_FILE="${POLICY_APPROVED_FILE:-${POLICY_DIR}/approved.jsonl}"

# Denied actions file
declare -g POLICY_DENIED_FILE="${POLICY_DENIED_FILE:-${POLICY_DIR}/denied.jsonl}"

# Policy definitions file (for loaded/defined policies)
declare -g POLICY_DEFS_FILE="${POLICY_DEFS_FILE:-${POLICY_DIR}/policies.jsonl}"

# Counter for generating unique action IDs
declare -g _POLICY_ACTION_COUNTER=0

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Associative arrays for in-memory policy storage
# Format: _POLICY_RULES[policy_name:rule_index]="action|resources|effect"
declare -gA _POLICY_RULES=()
declare -gA _POLICY_NAMES=()
declare -gA _POLICY_DESCRIPTIONS=()

# Counters for rules per policy
declare -gA _POLICY_RULE_COUNTS=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_policy_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "policy" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[policy] %s: %s\n' "$level" "$*" >&2
        :
    fi
}

# JSON-escape a string
_policy_json_escape() {
    local str="$1"
    if declare -F json_escape &>/dev/null; then
        json_escape "$str"
        return
    fi
    # Manual escaping fallback
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Generate ISO timestamp
_policy_timestamp() {
    date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# Generate unique action ID
_policy_generate_action_id() {
    _POLICY_ACTION_COUNTER=$((_POLICY_ACTION_COUNTER + 1))
    local ts rand
    ts=$(date +%s%N 2>/dev/null || printf '%d' "$EPOCHSECONDS")
    rand=$((RANDOM * RANDOM))  # More randomness since counter fails in subshells
    printf 'action_%s_%s_%d_%d' "$$" "$ts" "$rand" "$_POLICY_ACTION_COUNTER"
}

# Initialize policy directory structure
_policy_init_dir() {
    if [[ ! -d "$POLICY_DIR" ]]; then
        mkdir -p "$POLICY_DIR" 2>/dev/null || return 1
    fi
    # Ensure files exist
    touch "$POLICY_AUDIT_LOG" "$POLICY_PENDING_FILE" "$POLICY_APPROVED_FILE" \
          "$POLICY_DENIED_FILE" "$POLICY_DEFS_FILE" 2>/dev/null || return 1
    return 0
}

# Match a resource against a glob pattern
# Supports * for any characters and ? for single character
_policy_glob_match() {
    local pattern="$1"
    local resource="$2"

    # Fast path: exact match (no wildcards)
    if [[ "$pattern" != *'*'* && "$pattern" != *'?'* ]]; then
        [[ "$resource" == "$pattern" ]]
        return
    fi

    # Convert glob to regex using string substitution (O(1) vs O(n) char loop)
    local regex="$pattern"

    # Use control characters as placeholders for glob wildcards
    local star_ph=$'\x01'
    local qmark_ph=$'\x02'

    # Save wildcards with placeholders before escaping
    regex="${regex//\*/$star_ph}"
    regex="${regex//\?/$qmark_ph}"

    # Escape backslash first (before other escaping)
    regex="${regex//\\/\\\\}"

    # Escape regex metacharacters
    regex="${regex//./\\.}"
    regex="${regex//[/\\[}"
    regex="${regex//]/\\]}"
    regex="${regex//^/\\^}"
    regex="${regex//\$/\\\$}"

    # Restore wildcards as regex equivalents
    regex="${regex//$star_ph/.*}"
    regex="${regex//$qmark_ph/.}"

    # Anchor the pattern
    regex="^${regex}\$"

    [[ "$resource" =~ $regex ]]
}

# =============================================================================
# YAML PARSING (Simple subset for policy files)
# =============================================================================

# Parse policy YAML file into internal structures
# Supports basic key: value, arrays with -, and nested indentation
_policy_parse_yaml() {
    local file="$1"

    [[ -f "$file" ]] || return 1

    local line key value
    local current_policy=""
    local in_policies=0
    local in_rules=0
    local rule_action="" rule_effect=""
    local -a rule_resources=()
    local rule_idx=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Remove inline comments (not in quotes)
        local clean_line="${line%%#*}"

        # Detect top-level keys
        if [[ "$clean_line" =~ ^version:[[:space:]]*(.+)$ ]]; then
            # version: "1.0"
            continue
        elif [[ "$clean_line" =~ ^policies:[[:space:]]*$ ]]; then
            in_policies=1
            continue
        fi

        # Inside policies array
        if [[ $in_policies -eq 1 ]]; then
            # New policy item: - name: "..."
            if [[ "$clean_line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
                # Save previous policy's last rule
                if [[ -n "$current_policy" && -n "$rule_action" ]]; then
                    local resources_str
                    resources_str=$(IFS='|'; echo "${rule_resources[*]}")
                    _POLICY_RULES["${current_policy}:${rule_idx}"]="${rule_action}|${resources_str}|${rule_effect}"
                    rule_idx=$((rule_idx + 1))
                    _POLICY_RULE_COUNTS["$current_policy"]=$rule_idx
                fi

                current_policy="${BASH_REMATCH[1]}"
                _POLICY_NAMES["$current_policy"]=1
                rule_idx=0
                in_rules=0
                rule_action=""
                rule_effect=""
                rule_resources=()
                continue
            fi

            # Description
            if [[ "$clean_line" =~ ^[[:space:]]+description:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
                [[ -n "$current_policy" ]] && _POLICY_DESCRIPTIONS["$current_policy"]="${BASH_REMATCH[1]}"
                continue
            fi

            # Rules section start
            if [[ "$clean_line" =~ ^[[:space:]]+rules:[[:space:]]*$ ]]; then
                in_rules=1
                continue
            fi

            # Inside rules
            if [[ $in_rules -eq 1 && -n "$current_policy" ]]; then
                # New rule: - action: "..."
                if [[ "$clean_line" =~ ^[[:space:]]+-[[:space:]]*action:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
                    # Save previous rule
                    if [[ -n "$rule_action" ]]; then
                        local resources_str
                        resources_str=$(IFS='|'; echo "${rule_resources[*]}")
                        _POLICY_RULES["${current_policy}:${rule_idx}"]="${rule_action}|${resources_str}|${rule_effect}"
                        rule_idx=$((rule_idx + 1))
                    fi
                    rule_action="${BASH_REMATCH[1]}"
                    rule_effect=""
                    rule_resources=()
                    continue
                fi

                # Resources array start
                if [[ "$clean_line" =~ ^[[:space:]]+resources:[[:space:]]*$ ]]; then
                    continue
                fi

                # Resources array item
                if [[ "$clean_line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]*)\"?$ ]]; then
                    rule_resources+=("${BASH_REMATCH[1]}")
                    continue
                fi

                # Inline resources: resources: ["...", "..."]
                if [[ "$clean_line" =~ ^[[:space:]]+resources:[[:space:]]*\[(.+)\]$ ]]; then
                    local res_str="${BASH_REMATCH[1]}"
                    # Parse comma-separated quoted strings
                    while [[ "$res_str" =~ \"([^\"]+)\" ]]; do
                        rule_resources+=("${BASH_REMATCH[1]}")
                        res_str="${res_str#*\"${BASH_REMATCH[1]}\"}"
                    done
                    continue
                fi

                # Effect
                if [[ "$clean_line" =~ ^[[:space:]]+effect:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
                    rule_effect="${BASH_REMATCH[1]}"
                    continue
                fi
            fi
        fi
    done < "$file"

    # Save last rule
    if [[ -n "$current_policy" && -n "$rule_action" ]]; then
        local resources_str
        resources_str=$(IFS='|'; echo "${rule_resources[*]}")
        _POLICY_RULES["${current_policy}:${rule_idx}"]="${rule_action}|${resources_str}|${rule_effect}"
        rule_idx=$((rule_idx + 1))
        _POLICY_RULE_COUNTS["$current_policy"]=$rule_idx
    fi

    return 0
}

# =============================================================================
# PUBLIC API - POLICY MANAGEMENT
# =============================================================================

# Load policy from a YAML file
# @pre: file_path points to a valid policy YAML file
# @post: policies loaded into memory
# @idempotent: yes - re-loads policies from file
# @returns: 0 on success, 1 on failure
#
# Usage: policy_load "policy.yaml"
# Example: policy_load "/etc/myapp/policies.yaml"
policy_load() {
    local file="$1"

    if [[ -z "$file" ]]; then
        _policy_log error "policy_load: file path required"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _policy_log error "policy_load: file not found: $file"
        return 1
    fi

    _policy_init_dir || return 1

    if _policy_parse_yaml "$file"; then
        _policy_log debug "policy_load: loaded policies from $file"
        policy_audit "policy_loaded" "system" "$file" "success"
        return 0
    else
        _policy_log error "policy_load: failed to parse $file"
        return 1
    fi
}

# Define an inline policy rule
# @pre: name and rule_json provided
# @post: policy rule added to memory
# @idempotent: no - adds additional rules
# @returns: 0 on success, 1 on failure
#
# Usage: policy_define "my_policy" '{"action":"write","resources":["/tmp/*"],"effect":"allow"}'
# Example: policy_define "network_deny" '{"action":"http_request","resources":["*.internal"],"effect":"deny"}'
policy_define() {
    local name="$1"
    local rule_json="$2"

    if [[ -z "$name" || -z "$rule_json" ]]; then
        _policy_log error "policy_define: name and rule_json required"
        return 1
    fi

    _policy_init_dir || return 1

    # Parse JSON (simple extraction)
    local action="" effect=""
    local -a resources=()

    # Extract action
    if [[ "$rule_json" =~ \"action\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        action="${BASH_REMATCH[1]}"
    fi

    # Extract effect
    if [[ "$rule_json" =~ \"effect\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        effect="${BASH_REMATCH[1]}"
    fi

    # Extract resources array
    if [[ "$rule_json" =~ \"resources\"[[:space:]]*:[[:space:]]*\[([^\]]+)\] ]]; then
        local res_str="${BASH_REMATCH[1]}"
        while [[ "$res_str" =~ \"([^\"]+)\" ]]; do
            resources+=("${BASH_REMATCH[1]}")
            res_str="${res_str#*\"${BASH_REMATCH[1]}\"}"
        done
    fi

    if [[ -z "$action" || -z "$effect" ]]; then
        _policy_log error "policy_define: action and effect required in rule_json"
        return 1
    fi

    # Add policy
    _POLICY_NAMES["$name"]=1
    local rule_idx="${_POLICY_RULE_COUNTS[$name]:-0}"
    local resources_str
    resources_str=$(IFS='|'; echo "${resources[*]}")
    _POLICY_RULES["${name}:${rule_idx}"]="${action}|${resources_str}|${effect}"
    _POLICY_RULE_COUNTS["$name"]=$((rule_idx + 1))

    _policy_log debug "policy_define: added rule to policy '$name'"
    policy_audit "policy_defined" "system" "$name" "success"
    return 0
}

# List all loaded policies
# @post: prints policy names and descriptions
# @idempotent: yes
# @returns: 0
#
# Usage: policy_list
policy_list() {
    _policy_init_dir || return 1

    local name
    for name in "${!_POLICY_NAMES[@]}"; do
        local desc="${_POLICY_DESCRIPTIONS[$name]:-No description}"
        local count="${_POLICY_RULE_COUNTS[$name]:-0}"
        printf '{"name":"%s","description":"%s","rule_count":%d}\n' \
            "$(_policy_json_escape "$name")" \
            "$(_policy_json_escape "$desc")" \
            "$count"
    done
}

# Validate a policy YAML file
# @pre: file_path points to a file
# @post: validates file structure
# @idempotent: yes
# @returns: 0 if valid, 1 if invalid
#
# Usage: policy_validate "policy.yaml"
policy_validate() {
    local file="$1"

    if [[ -z "$file" ]]; then
        printf '{"valid":false,"error":"file path required"}\n'
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        printf '{"valid":false,"error":"file not found: %s"}\n' "$(_policy_json_escape "$file")"
        return 1
    fi

    # Check for required structure
    local has_version=0 has_policies=0
    local line_num=0
    local -a errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        [[ "$line" =~ ^version: ]] && has_version=1
        [[ "$line" =~ ^policies: ]] && has_policies=1

        # Check for tabs (YAML doesn't allow tabs for indentation)
        if [[ "$line" == *$'\t'* ]]; then
            errors+=("line $line_num: tabs not allowed in YAML")
        fi
    done < "$file"

    if [[ $has_version -eq 0 ]]; then
        errors+=("missing required field: version")
    fi

    if [[ $has_policies -eq 0 ]]; then
        errors+=("missing required field: policies")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        local err_json="["
        local first=true
        for err in "${errors[@]}"; do
            $first || err_json+=","
            first=false
            err_json+="\"$(_policy_json_escape "$err")\""
        done
        err_json+="]"
        printf '{"valid":false,"errors":%s}\n' "$err_json"
        return 1
    fi

    printf '{"valid":true,"file":"%s"}\n' "$(_policy_json_escape "$file")"
    return 0
}

# =============================================================================
# PUBLIC API - POLICY CHECKING
# =============================================================================

# Check if an action is allowed by loaded policies
# @pre: action and optional agent_id provided
# @post: checks action against all policies
# @idempotent: yes
# @returns: 0 if allowed, 1 if denied, 2 if requires approval
#
# Usage: policy_check "write" "agent-123" "/tmp/file.txt"
# Example: policy_check "http_request" "" "api.openai.com"
policy_check() {
    local action="$1"
    local agent_id="${2:-anonymous}"
    local resource="${3:-*}"

    if [[ -z "$action" ]]; then
        _policy_log error "policy_check: action required"
        return 1
    fi

    _policy_init_dir || return 1

    # If no policies loaded, allow by default
    if [[ ${#_POLICY_NAMES[@]} -eq 0 ]]; then
        printf '{"allowed":true,"reason":"no_policies_loaded"}\n'
        return 0
    fi

    local matched_policy=""
    local matched_effect=""
    local most_specific_match=""

    # Check all policies
    local name
    for name in "${!_POLICY_NAMES[@]}"; do
        local count="${_POLICY_RULE_COUNTS[$name]:-0}"
        local i
        for ((i=0; i<count; i++)); do
            local rule="${_POLICY_RULES[${name}:${i}]:-}"
            [[ -z "$rule" ]] && continue

            # Parse rule: action|resources|effect
            local rule_action="${rule%%|*}"
            local rest="${rule#*|}"
            local rule_resources="${rest%|*}"
            local rule_effect="${rest##*|}"

            # Check action match
            if [[ "$action" != "$rule_action" && "$rule_action" != "*" ]]; then
                continue
            fi

            # Check resource match
            local resource_matched=0
            if [[ -z "$rule_resources" || "$rule_resources" == "*" ]]; then
                resource_matched=1
            else
                # Parse resources (pipe-separated)
                # IMPORTANT: Disable glob expansion to prevent /tmp/* from expanding
                local old_glob_state
                old_glob_state=$(shopt -p nullglob globstar 2>/dev/null || true)
                set -f  # Disable glob expansion
                local IFS='|'
                local pattern
                for pattern in $rule_resources; do
                    if _policy_glob_match "$pattern" "$resource"; then
                        resource_matched=1
                        # Track most specific match (longest pattern)
                        if [[ ${#pattern} -gt ${#most_specific_match} ]]; then
                            most_specific_match="$pattern"
                            matched_policy="$name"
                            matched_effect="$rule_effect"
                        fi
                        break
                    fi
                done
                set +f  # Re-enable glob expansion
            fi

            # If matched and no more specific match found yet
            if [[ $resource_matched -eq 1 && -z "$matched_effect" ]]; then
                matched_policy="$name"
                matched_effect="$rule_effect"
            fi
        done
    done

    # Determine result
    case "$matched_effect" in
        allow)
            printf '{"allowed":true,"policy":"%s","effect":"allow","resource":"%s"}\n' \
                "$(_policy_json_escape "$matched_policy")" \
                "$(_policy_json_escape "$resource")"
            policy_audit "$action" "$agent_id" "$resource" "allowed" "$matched_policy"
            return 0
            ;;
        deny)
            printf '{"allowed":false,"policy":"%s","effect":"deny","resource":"%s"}\n' \
                "$(_policy_json_escape "$matched_policy")" \
                "$(_policy_json_escape "$resource")"
            policy_audit "$action" "$agent_id" "$resource" "denied" "$matched_policy"
            return 1
            ;;
        require_approval)
            local action_id
            action_id=$(_policy_generate_action_id)
            printf '{"allowed":false,"requires_approval":true,"action_id":"%s","policy":"%s","resource":"%s"}\n' \
                "$(_policy_json_escape "$action_id")" \
                "$(_policy_json_escape "$matched_policy")" \
                "$(_policy_json_escape "$resource")"

            # Add to pending
            local ts
            ts=$(_policy_timestamp)
            printf '{"action_id":"%s","action":"%s","agent":"%s","resource":"%s","policy":"%s","timestamp":"%s"}\n' \
                "$(_policy_json_escape "$action_id")" \
                "$(_policy_json_escape "$action")" \
                "$(_policy_json_escape "$agent_id")" \
                "$(_policy_json_escape "$resource")" \
                "$(_policy_json_escape "$matched_policy")" \
                "$ts" >> "$POLICY_PENDING_FILE"

            policy_audit "$action" "$agent_id" "$resource" "pending_approval" "$matched_policy"
            return 2
            ;;
        *)
            # No matching rule - allow by default
            printf '{"allowed":true,"reason":"no_matching_rule"}\n'
            return 0
            ;;
    esac
}

# Mark an action as requiring approval
# @pre: action provided
# @post: creates pending approval record
# @idempotent: no - creates new record each time
# @returns: 0 on success, 1 on failure
#
# Usage: policy_require_approval "delete_all_files"
# Example: policy_require_approval "deploy_production" "agent-42" "/prod/app"
policy_require_approval() {
    local action="$1"
    local agent_id="${2:-anonymous}"
    local resource="${3:-*}"

    if [[ -z "$action" ]]; then
        _policy_log error "policy_require_approval: action required"
        return 1
    fi

    _policy_init_dir || return 1

    local action_id
    action_id=$(_policy_generate_action_id)
    local ts
    ts=$(_policy_timestamp)

    printf '{"action_id":"%s","action":"%s","agent":"%s","resource":"%s","policy":"manual","timestamp":"%s"}\n' \
        "$(_policy_json_escape "$action_id")" \
        "$(_policy_json_escape "$action")" \
        "$(_policy_json_escape "$agent_id")" \
        "$(_policy_json_escape "$resource")" \
        "$ts" >> "$POLICY_PENDING_FILE"

    printf '{"action_id":"%s","status":"pending"}\n' "$(_policy_json_escape "$action_id")"
    policy_audit "$action" "$agent_id" "$resource" "pending_approval" "manual"
    return 0
}

# =============================================================================
# PUBLIC API - APPROVAL WORKFLOW
# =============================================================================

# Approve a pending action
# @pre: action_id exists in pending file
# @post: action moved to approved file
# @idempotent: yes - approving already approved action is no-op
# @returns: 0 on success, 1 if not found
#
# Usage: policy_approve "action_12345_1706800000_1"
policy_approve() {
    local action_id="$1"

    if [[ -z "$action_id" ]]; then
        _policy_log error "policy_approve: action_id required"
        return 1
    fi

    _policy_init_dir || return 1

    # Check if already approved
    if grep -q "\"action_id\":\"$action_id\"" "$POLICY_APPROVED_FILE" 2>/dev/null; then
        printf '{"action_id":"%s","status":"already_approved"}\n' "$(_policy_json_escape "$action_id")"
        return 0
    fi

    # Find in pending
    local pending_line
    pending_line=$(grep "\"action_id\":\"$action_id\"" "$POLICY_PENDING_FILE" 2>/dev/null | head -1)

    if [[ -z "$pending_line" ]]; then
        printf '{"action_id":"%s","error":"not_found"}\n' "$(_policy_json_escape "$action_id")"
        return 1
    fi

    # Move to approved with timestamp
    local ts
    ts=$(_policy_timestamp)

    # Add approved_at to the record
    local approved_line
    approved_line="${pending_line%\}},\"approved_at\":\"$ts\"}"
    printf '%s\n' "$approved_line" >> "$POLICY_APPROVED_FILE"

    # Remove from pending (create temp file, filter, replace)
    local tmp_pending
    tmp_pending=$(mktemp)
    grep -v "\"action_id\":\"$action_id\"" "$POLICY_PENDING_FILE" > "$tmp_pending" 2>/dev/null || true
    mv -f "$tmp_pending" "$POLICY_PENDING_FILE"

    printf '{"action_id":"%s","status":"approved","approved_at":"%s"}\n' \
        "$(_policy_json_escape "$action_id")" "$ts"

    # Extract action from pending line for audit
    local action=""
    if [[ "$pending_line" =~ \"action\":\"([^\"]+)\" ]]; then
        action="${BASH_REMATCH[1]}"
    fi
    policy_audit "${action:-unknown}" "approver" "$action_id" "approved" ""

    return 0
}

# Deny a pending action
# @pre: action_id exists in pending file
# @post: action moved to denied file with reason
# @idempotent: yes - denying already denied action is no-op
# @returns: 0 on success, 1 if not found
#
# Usage: policy_deny "action_12345_1706800000_1" "too risky"
policy_deny() {
    local action_id="$1"
    local reason="${2:-no reason provided}"

    if [[ -z "$action_id" ]]; then
        _policy_log error "policy_deny: action_id required"
        return 1
    fi

    _policy_init_dir || return 1

    # Check if already denied
    if grep -q "\"action_id\":\"$action_id\"" "$POLICY_DENIED_FILE" 2>/dev/null; then
        printf '{"action_id":"%s","status":"already_denied"}\n' "$(_policy_json_escape "$action_id")"
        return 0
    fi

    # Find in pending
    local pending_line
    pending_line=$(grep "\"action_id\":\"$action_id\"" "$POLICY_PENDING_FILE" 2>/dev/null | head -1)

    if [[ -z "$pending_line" ]]; then
        printf '{"action_id":"%s","error":"not_found"}\n' "$(_policy_json_escape "$action_id")"
        return 1
    fi

    # Move to denied with reason and timestamp
    local ts
    ts=$(_policy_timestamp)

    local denied_line
    denied_line="${pending_line%\}},\"denied_at\":\"$ts\",\"reason\":\"$(_policy_json_escape "$reason")\"}"
    printf '%s\n' "$denied_line" >> "$POLICY_DENIED_FILE"

    # Remove from pending
    local tmp_pending
    tmp_pending=$(mktemp)
    grep -v "\"action_id\":\"$action_id\"" "$POLICY_PENDING_FILE" > "$tmp_pending" 2>/dev/null || true
    mv -f "$tmp_pending" "$POLICY_PENDING_FILE"

    printf '{"action_id":"%s","status":"denied","reason":"%s","denied_at":"%s"}\n' \
        "$(_policy_json_escape "$action_id")" \
        "$(_policy_json_escape "$reason")" \
        "$ts"

    # Extract action from pending line for audit
    local action=""
    if [[ "$pending_line" =~ \"action\":\"([^\"]+)\" ]]; then
        action="${BASH_REMATCH[1]}"
    fi
    policy_audit "${action:-unknown}" "approver" "$action_id" "denied" "$reason"

    return 0
}

# List pending approval actions
# @post: prints all pending actions as JSONL
# @idempotent: yes
# @returns: 0
#
# Usage: policy_pending
policy_pending() {
    _policy_init_dir || return 1

    if [[ -s "$POLICY_PENDING_FILE" ]]; then
        cat "$POLICY_PENDING_FILE"
    fi
    return 0
}

# Check if an action has been approved
# @pre: action_id provided
# @post: checks approval status
# @idempotent: yes
# @returns: 0 if approved, 1 if not approved
#
# Usage: policy_is_approved "action_12345_1706800000_1" && echo "Go ahead"
policy_is_approved() {
    local action_id="$1"

    [[ -z "$action_id" ]] && return 1
    _policy_init_dir || return 1

    grep -q "\"action_id\":\"$action_id\"" "$POLICY_APPROVED_FILE" 2>/dev/null
}

# =============================================================================
# PUBLIC API - AUDIT LOGGING
# =============================================================================

# Write an audit log entry
# @pre: action, actor, resource, result provided
# @post: JSONL entry appended to audit log
# @idempotent: no - always appends new entry
# @returns: 0
#
# Usage: policy_audit "write" "agent-123" "/tmp/file.txt" "allowed" "file_operations"
policy_audit() {
    local action="$1"
    local actor="${2:-anonymous}"
    local resource="${3:-unknown}"
    local result="${4:-unknown}"
    local policy="${5:-}"

    _policy_init_dir || return 1

    local ts
    ts=$(_policy_timestamp)

    printf '{"timestamp":"%s","action":"%s","actor":"%s","resource":"%s","policy":"%s","effect":"%s","result":"%s"}\n' \
        "$ts" \
        "$(_policy_json_escape "$action")" \
        "$(_policy_json_escape "$actor")" \
        "$(_policy_json_escape "$resource")" \
        "$(_policy_json_escape "$policy")" \
        "$(_policy_json_escape "$result")" \
        "$(_policy_json_escape "$result")" >> "$POLICY_AUDIT_LOG"

    return 0
}

# Query the audit log with filters
# @post: prints matching audit entries
# @idempotent: yes
# @returns: 0
#
# Usage: policy_audit_query --actor "agent-123" --since "2026-01-01"
# Example: policy_audit_query --action "write" --result "denied"
policy_audit_query() {
    _policy_init_dir || return 1

    local filter_actor="" filter_action="" filter_since="" filter_result="" filter_resource=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --actor)
                filter_actor="$2"
                shift 2
                ;;
            --action)
                filter_action="$2"
                shift 2
                ;;
            --since)
                filter_since="$2"
                shift 2
                ;;
            --result)
                filter_result="$2"
                shift 2
                ;;
            --resource)
                filter_resource="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ ! -f "$POLICY_AUDIT_LOG" ]] && return 0

    # Read and filter audit log
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        local match=1

        # Filter by actor
        if [[ -n "$filter_actor" ]]; then
            if ! [[ "$line" =~ \"actor\":\"$filter_actor\" ]]; then
                match=0
            fi
        fi

        # Filter by action
        if [[ -n "$filter_action" && $match -eq 1 ]]; then
            if ! [[ "$line" =~ \"action\":\"$filter_action\" ]]; then
                match=0
            fi
        fi

        # Filter by result
        if [[ -n "$filter_result" && $match -eq 1 ]]; then
            if ! [[ "$line" =~ \"result\":\"$filter_result\" ]]; then
                match=0
            fi
        fi

        # Filter by resource
        if [[ -n "$filter_resource" && $match -eq 1 ]]; then
            if ! [[ "$line" =~ \"resource\":\"[^\"]*$filter_resource ]]; then
                match=0
            fi
        fi

        # Filter by timestamp (since)
        if [[ -n "$filter_since" && $match -eq 1 ]]; then
            local entry_ts=""
            if [[ "$line" =~ \"timestamp\":\"([^\"]+)\" ]]; then
                entry_ts="${BASH_REMATCH[1]}"
                # Compare ISO timestamps lexicographically
                if [[ "$entry_ts" < "$filter_since" ]]; then
                    match=0
                fi
            fi
        fi

        if [[ $match -eq 1 ]]; then
            printf '%s\n' "$line"
        fi
    done < "$POLICY_AUDIT_LOG"

    return 0
}

# Clear the audit log (for testing/maintenance)
# @post: audit log file emptied
# @idempotent: yes
# @returns: 0
#
# Usage: policy_audit_clear
policy_audit_clear() {
    _policy_init_dir || return 1
    : > "$POLICY_AUDIT_LOG"
    return 0
}

# =============================================================================
# PUBLIC API - UTILITY FUNCTIONS
# =============================================================================

# Clear all loaded policies and reset state
# @post: all policies and state cleared
# @idempotent: yes
# @returns: 0
#
# Usage: policy_clear
policy_clear() {
    _POLICY_RULES=()
    _POLICY_NAMES=()
    _POLICY_DESCRIPTIONS=()
    _POLICY_RULE_COUNTS=()

    _policy_init_dir || return 1

    : > "$POLICY_PENDING_FILE"
    : > "$POLICY_APPROVED_FILE"
    : > "$POLICY_DENIED_FILE"

    _policy_log debug "policy_clear: all policies cleared"
    return 0
}

# Get policy status summary
# @post: prints status JSON
# @idempotent: yes
# @returns: 0
#
# Usage: policy_status
policy_status() {
    _policy_init_dir || return 1

    local policy_count="${#_POLICY_NAMES[@]}"
    local pending_count=0
    local approved_count=0
    local denied_count=0

    [[ -f "$POLICY_PENDING_FILE" ]] && pending_count=$(wc -l < "$POLICY_PENDING_FILE" | tr -d ' ')
    [[ -f "$POLICY_APPROVED_FILE" ]] && approved_count=$(wc -l < "$POLICY_APPROVED_FILE" | tr -d ' ')
    [[ -f "$POLICY_DENIED_FILE" ]] && denied_count=$(wc -l < "$POLICY_DENIED_FILE" | tr -d ' ')

    printf '{"policies_loaded":%d,"pending_approvals":%d,"approved_actions":%d,"denied_actions":%d}\n' \
        "$policy_count" "$pending_count" "$approved_count" "$denied_count"

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_POLICY_EXPORTS=(
    # Policy Management
    policy_load
    policy_define
    policy_list
    policy_validate
    policy_clear
    policy_status
    # Policy Checking
    policy_check
    policy_require_approval
    # Approval Workflow
    policy_approve
    policy_deny
    policy_pending
    policy_is_approved
    # Audit Logging
    policy_audit
    policy_audit_query
    policy_audit_clear
)

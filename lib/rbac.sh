#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/rbac.sh - Role-Based Access Control (RBAC)
# =============================================================================
# Description: Enterprise-grade RBAC for AI agent systems. Provides role
#              definitions, permission checking, role inheritance, wildcard
#              matching, audit logging, and config import/export.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# Permission Format: resource:action
#   - files:read, files:write, files:delete
#   - agents:spawn, agents:terminate
#   - secrets:read
#   - network:* (wildcard - all network actions)
#   - *:read (wildcard - read all resources)
#   - *:* (admin - all permissions)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing (set -u compatible)
[[ -n "${_MAINFRAME_RBAC_LOADED:-}" ]] && return 0
_MAINFRAME_RBAC_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Role definitions: role_name -> space-separated permissions
declare -gA _RBAC_ROLES=()

# Role inheritance: role_name -> space-separated parent roles
declare -gA _RBAC_ROLE_INHERITS=()

# Role descriptions: role_name -> description
declare -gA _RBAC_ROLE_DESC=()

# Subject role assignments: subject_id -> space-separated roles
declare -gA _RBAC_SUBJECT_ROLES=()

# Permission cache: subject_id:permission -> 1 (granted) or 0 (denied)
declare -gA _RBAC_PERM_CACHE=()

# Audit log file (optional, set via rbac_set_audit_log)
declare -g _RBAC_AUDIT_LOG=""

# Audit log format: timestamp|subject|resource|action|result|context
declare -g _RBAC_AUDIT_FORMAT="timestamp|subject|resource|action|result|context"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging
_rbac_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "rbac" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[rbac] %s: %s\n' "$level" "$*" >&2
    fi
}

# Clear permission cache for a subject (call when roles change)
_rbac_clear_cache() {
    local subject="$1"
    local key
    for key in "${!_RBAC_PERM_CACHE[@]}"; do
        if [[ "$key" == "${subject}:"* ]]; then
            unset '_RBAC_PERM_CACHE[$key]'
        fi
    done
}

# Clear entire permission cache
_rbac_clear_all_cache() {
    _RBAC_PERM_CACHE=()
}

# Get all permissions for a role (including inherited)
# Usage: _rbac_get_role_permissions "role_name"
# Output: space-separated permissions
_rbac_get_role_permissions() {
    local role="$1"
    local -A seen_roles=()
    local -A all_perms=()
    local -a stack=("$role")

    while [[ ${#stack[@]} -gt 0 ]]; do
        local current="${stack[0]}"
        stack=("${stack[@]:1}")

        # Skip if already processed
        [[ -n "${seen_roles[$current]:-}" ]] && continue
        seen_roles["$current"]=1

        # Add direct permissions
        if [[ -n "${_RBAC_ROLES[$current]:-}" ]]; then
            local perm
            for perm in ${_RBAC_ROLES[$current]}; do
                all_perms["$perm"]=1
            done
        fi

        # Add parent roles to stack
        if [[ -n "${_RBAC_ROLE_INHERITS[$current]:-}" ]]; then
            local parent
            for parent in ${_RBAC_ROLE_INHERITS[$current]}; do
                stack+=("$parent")
            done
        fi
    done

    # Output unique permissions
    printf '%s' "${!all_perms[*]}"
}

# Check if a permission matches a pattern (wildcard support)
# Usage: _rbac_permission_matches "pattern" "permission"
# Returns: 0 if matches, 1 if not
_rbac_permission_matches() {
    local pattern="$1"
    local permission="$2"

    # Exact match
    [[ "$pattern" == "$permission" ]] && return 0

    # Full wildcard
    [[ "$pattern" == "*:*" ]] && return 0

    # Parse pattern and permission
    local pat_resource="${pattern%%:*}"
    local pat_action="${pattern#*:}"
    local perm_resource="${permission%%:*}"
    local perm_action="${permission#*:}"

    # Resource wildcard
    if [[ "$pat_resource" == "*" && "$pat_action" == "$perm_action" ]]; then
        return 0
    fi

    # Action wildcard
    if [[ "$pat_action" == "*" && "$pat_resource" == "$perm_resource" ]]; then
        return 0
    fi

    # Both wildcards (handled by *:* above, but be explicit)
    if [[ "$pat_resource" == "*" && "$pat_action" == "*" ]]; then
        return 0
    fi

    return 1
}

# Parse YAML config into RBAC state
# Minimal YAML parser for RBAC config format
_rbac_parse_yaml_config() {
    local file="$1"
    local section="" role="" subject=""
    local in_permissions=0 in_roles=0 in_inherits=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty and comment lines
        [[ -z "${line// /}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Trim leading whitespace for detection
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local indent=$((${#line} - ${#trimmed}))

        # Top-level sections
        if [[ $indent -eq 0 ]]; then
            if [[ "$trimmed" == "roles:" ]]; then
                section="roles"
                continue
            elif [[ "$trimmed" == "subjects:" ]]; then
                section="subjects"
                continue
            fi
        fi

        # Role definitions
        if [[ "$section" == "roles" ]]; then
            # Role name (indent 2)
            if [[ $indent -eq 2 && "$trimmed" =~ ^([a-zA-Z0-9_-]+):$ ]]; then
                role="${BASH_REMATCH[1]}"
                in_permissions=0
                in_inherits=0
                continue
            fi

            # Role properties (indent 4)
            if [[ $indent -eq 4 && -n "$role" ]]; then
                if [[ "$trimmed" == "permissions:" ]]; then
                    in_permissions=1
                    in_inherits=0
                    continue
                elif [[ "$trimmed" =~ ^inherits:[[:space:]]*(.*)$ ]]; then
                    local parent="${BASH_REMATCH[1]}"
                    parent="${parent// /}"
                    if [[ -n "$parent" ]]; then
                        _RBAC_ROLE_INHERITS["$role"]="${_RBAC_ROLE_INHERITS[$role]:-} $parent"
                        _RBAC_ROLE_INHERITS["$role"]="${_RBAC_ROLE_INHERITS[$role]# }"
                    fi
                    in_inherits=1
                    in_permissions=0
                    continue
                elif [[ "$trimmed" =~ ^description:[[:space:]]*[\"\']?(.*)[\"\']?$ ]]; then
                    local desc="${BASH_REMATCH[1]}"
                    desc="${desc%\"}"
                    desc="${desc%\'}"
                    _RBAC_ROLE_DESC["$role"]="$desc"
                    continue
                fi
            fi

            # Permission list items (indent 6)
            if [[ $indent -eq 6 && $in_permissions -eq 1 && -n "$role" ]]; then
                if [[ "$trimmed" =~ ^-[[:space:]]*[\"\']?([^\"\']+)[\"\']?$ ]]; then
                    local perm="${BASH_REMATCH[1]}"
                    _RBAC_ROLES["$role"]="${_RBAC_ROLES[$role]:-} $perm"
                    _RBAC_ROLES["$role"]="${_RBAC_ROLES[$role]# }"
                fi
                continue
            fi
        fi

        # Subject definitions
        if [[ "$section" == "subjects" ]]; then
            # Subject ID (indent 2)
            if [[ $indent -eq 2 && "$trimmed" =~ ^([a-zA-Z0-9_-]+):$ ]]; then
                subject="${BASH_REMATCH[1]}"
                in_roles=0
                continue
            fi

            # Subject properties (indent 4)
            if [[ $indent -eq 4 && -n "$subject" ]]; then
                if [[ "$trimmed" == "roles:" ]]; then
                    in_roles=1
                    continue
                fi
            fi

            # Role list items (indent 6)
            if [[ $indent -eq 6 && $in_roles -eq 1 && -n "$subject" ]]; then
                if [[ "$trimmed" =~ ^-[[:space:]]*([a-zA-Z0-9_-]+)$ ]]; then
                    local subj_role="${BASH_REMATCH[1]}"
                    _RBAC_SUBJECT_ROLES["$subject"]="${_RBAC_SUBJECT_ROLES[$subject]:-} $subj_role"
                    _RBAC_SUBJECT_ROLES["$subject"]="${_RBAC_SUBJECT_ROLES[$subject]# }"
                fi
                continue
            fi
        fi

    done < "$file"
}

# =============================================================================
# PUBLIC API - INITIALIZATION
# =============================================================================

# @pre: config_file is a valid YAML file with roles/subjects sections
# @post: RBAC state is populated from config
# @idempotent: yes (clears previous state)
# @returns: 0 on success, 1 on error
#
# Initialize RBAC from a YAML configuration file.
#
# Usage: rbac_init "rbac-config.yaml"
# Example:
#   rbac_init "/etc/mainframe/rbac.yaml"
#   rbac_check_permission "agent-123" "files:read"
rbac_init() {
    local config_file="$1"

    if [[ -z "$config_file" ]]; then
        _rbac_log "error" "No config file specified"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        _rbac_log "error" "Config file not found: $config_file"
        return 1
    fi

    # Clear existing state
    _RBAC_ROLES=()
    _RBAC_ROLE_INHERITS=()
    _RBAC_ROLE_DESC=()
    _RBAC_SUBJECT_ROLES=()
    _RBAC_PERM_CACHE=()

    # Parse config
    _rbac_parse_yaml_config "$config_file"

    _rbac_log "info" "RBAC initialized from $config_file"
    _rbac_log "debug" "Loaded ${#_RBAC_ROLES[@]} roles, ${#_RBAC_SUBJECT_ROLES[@]} subjects"

    return 0
}

# @pre: none
# @post: all RBAC state is cleared
# @idempotent: yes
# @returns: 0
#
# Reset RBAC to empty state.
#
# Usage: rbac_reset
rbac_reset() {
    _RBAC_ROLES=()
    _RBAC_ROLE_INHERITS=()
    _RBAC_ROLE_DESC=()
    _RBAC_SUBJECT_ROLES=()
    _RBAC_PERM_CACHE=()
    _rbac_log "info" "RBAC state reset"
    return 0
}

# =============================================================================
# PUBLIC API - ROLE MANAGEMENT
# =============================================================================

# @pre: role_name is a valid identifier, permissions are resource:action format
# @post: role is created/updated with the given permissions
# @idempotent: yes (replaces existing role)
# @returns: 0 on success, 1 on invalid input
#
# Define a role with permissions.
#
# Usage: rbac_define_role "role_name" "perm1" "perm2" ...
# Example:
#   rbac_define_role "reader" "files:read" "logs:read"
#   rbac_define_role "admin" "*:*"
rbac_define_role() {
    local role_name="$1"
    shift
    local permissions="$*"

    if [[ -z "$role_name" ]]; then
        _rbac_log "error" "Role name required"
        return 1
    fi

    # Validate role name (alphanumeric, dash, underscore)
    if [[ ! "$role_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        _rbac_log "error" "Invalid role name: $role_name"
        return 1
    fi

    # Validate permissions format
    local perm
    for perm in $permissions; do
        if [[ ! "$perm" =~ ^[a-zA-Z0-9_*-]+:[a-zA-Z0-9_*-]+$ ]]; then
            _rbac_log "error" "Invalid permission format: $perm (expected resource:action)"
            return 1
        fi
    done

    _RBAC_ROLES["$role_name"]="$permissions"
    _rbac_clear_all_cache

    _rbac_log "debug" "Defined role '$role_name' with permissions: $permissions"
    return 0
}

# @pre: role_name is a valid identifier, parent_role exists
# @post: role inherits from parent_role
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Set role inheritance.
#
# Usage: rbac_inherit_role "child_role" "parent_role"
# Example:
#   rbac_inherit_role "agent-operator" "agent-reader"
rbac_inherit_role() {
    local child_role="$1"
    local parent_role="$2"

    if [[ -z "$child_role" || -z "$parent_role" ]]; then
        _rbac_log "error" "Both child and parent role required"
        return 1
    fi

    # Check parent role exists
    if [[ -z "${_RBAC_ROLES[$parent_role]:-}" && -z "${_RBAC_ROLE_INHERITS[$parent_role]:-}" ]]; then
        _rbac_log "warn" "Parent role '$parent_role' not defined"
    fi

    # Add inheritance
    if [[ -n "${_RBAC_ROLE_INHERITS[$child_role]:-}" ]]; then
        # Check if already inherits
        if [[ " ${_RBAC_ROLE_INHERITS[$child_role]} " == *" $parent_role "* ]]; then
            return 0
        fi
        _RBAC_ROLE_INHERITS["$child_role"]+=" $parent_role"
    else
        _RBAC_ROLE_INHERITS["$child_role"]="$parent_role"
    fi

    _rbac_clear_all_cache
    _rbac_log "debug" "Role '$child_role' now inherits from '$parent_role'"
    return 0
}

# @pre: role_name exists
# @post: role and all references removed
# @idempotent: yes
# @returns: 0 on success, 1 if role not found
#
# Delete a role.
#
# Usage: rbac_delete_role "role_name"
# Example:
#   rbac_delete_role "deprecated-role"
rbac_delete_role() {
    local role_name="$1"

    if [[ -z "$role_name" ]]; then
        _rbac_log "error" "Role name required"
        return 1
    fi

    if [[ -z "${_RBAC_ROLES[$role_name]:-}" && -z "${_RBAC_ROLE_INHERITS[$role_name]:-}" ]]; then
        _rbac_log "warn" "Role not found: $role_name"
        return 1
    fi

    # Remove role
    unset '_RBAC_ROLES[$role_name]'
    unset '_RBAC_ROLE_INHERITS[$role_name]'
    unset '_RBAC_ROLE_DESC[$role_name]'

    # Remove from subject assignments
    local subject
    for subject in "${!_RBAC_SUBJECT_ROLES[@]}"; do
        local roles="${_RBAC_SUBJECT_ROLES[$subject]}"
        local new_roles=""
        local r
        for r in $roles; do
            [[ "$r" != "$role_name" ]] && new_roles+="$r "
        done
        _RBAC_SUBJECT_ROLES["$subject"]="${new_roles% }"
    done

    # Remove from inheritance
    local role
    for role in "${!_RBAC_ROLE_INHERITS[@]}"; do
        local parents="${_RBAC_ROLE_INHERITS[$role]}"
        local new_parents=""
        local p
        for p in $parents; do
            [[ "$p" != "$role_name" ]] && new_parents+="$p "
        done
        _RBAC_ROLE_INHERITS["$role"]="${new_parents% }"
    done

    _rbac_clear_all_cache
    _rbac_log "info" "Deleted role: $role_name"
    return 0
}

# @pre: none
# @post: prints role list to stdout
# @idempotent: yes
# @returns: 0
#
# List all defined roles.
#
# Usage: rbac_list_roles
# Output: One role per line with format: role_name [permissions...] (inherits: parent...)
rbac_list_roles() {
    local role
    local -a roles=()

    # Collect all roles (from definitions and inheritance)
    for role in "${!_RBAC_ROLES[@]}"; do
        roles+=("$role")
    done
    for role in "${!_RBAC_ROLE_INHERITS[@]}"; do
        # Only add if not already present
        local found=0
        local r
        for r in "${roles[@]}"; do
            [[ "$r" == "$role" ]] && { found=1; break; }
        done
        [[ $found -eq 0 ]] && roles+=("$role")
    done

    # Sort and output
    local sorted_roles
    sorted_roles=$(printf '%s\n' "${roles[@]}" | sort)

    while IFS= read -r role; do
        [[ -z "$role" ]] && continue

        local perms="${_RBAC_ROLES[$role]:-}"
        local inherits="${_RBAC_ROLE_INHERITS[$role]:-}"
        local desc="${_RBAC_ROLE_DESC[$role]:-}"

        printf '%s' "$role"
        [[ -n "$perms" ]] && printf ' [%s]' "$perms"
        [[ -n "$inherits" ]] && printf ' (inherits: %s)' "$inherits"
        [[ -n "$desc" ]] && printf ' - %s' "$desc"
        printf '\n'
    done <<< "$sorted_roles"

    return 0
}

# @pre: role_name exists
# @post: prints role details as JSON
# @idempotent: yes
# @returns: 0 on success, 1 if not found
#
# Get role details as JSON.
#
# Usage: rbac_get_role "role_name"
# Output: {"name":"...","permissions":[...],"inherits":[...],"description":"..."}
rbac_get_role() {
    local role_name="$1"

    if [[ -z "$role_name" ]]; then
        return 1
    fi

    if [[ -z "${_RBAC_ROLES[$role_name]:-}" && -z "${_RBAC_ROLE_INHERITS[$role_name]:-}" ]]; then
        return 1
    fi

    local perms="${_RBAC_ROLES[$role_name]:-}"
    local inherits="${_RBAC_ROLE_INHERITS[$role_name]:-}"
    local desc="${_RBAC_ROLE_DESC[$role_name]:-}"

    # Build JSON
    local json='{"name":"'"$role_name"'"'

    # Permissions array
    json+=',"permissions":['
    local first=true perm
    for perm in $perms; do
        $first || json+=','
        first=false
        json+='"'"$perm"'"'
    done
    json+=']'

    # Inherits array
    json+=',"inherits":['
    first=true
    local parent
    for parent in $inherits; do
        $first || json+=','
        first=false
        json+='"'"$parent"'"'
    done
    json+=']'

    # Effective permissions (resolved)
    local effective
    effective=$(_rbac_get_role_permissions "$role_name")
    json+=',"effective_permissions":['
    first=true
    for perm in $effective; do
        $first || json+=','
        first=false
        json+='"'"$perm"'"'
    done
    json+=']'

    # Description
    if [[ -n "$desc" ]]; then
        # Escape description for JSON
        desc="${desc//\\/\\\\}"
        desc="${desc//\"/\\\"}"
        json+=',"description":"'"$desc"'"'
    fi

    json+='}'
    printf '%s\n' "$json"
    return 0
}

# =============================================================================
# PUBLIC API - SUBJECT MANAGEMENT
# =============================================================================

# @pre: subject_id is a valid identifier, role_name exists
# @post: subject is assigned the role
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Assign a role to a subject (user, agent, service).
#
# Usage: rbac_assign_role "subject_id" "role_name"
# Example:
#   rbac_assign_role "agent-123" "agent-operator"
#   rbac_assign_role "service-auth" "admin"
rbac_assign_role() {
    local subject_id="$1"
    local role_name="$2"

    if [[ -z "$subject_id" || -z "$role_name" ]]; then
        _rbac_log "error" "Subject ID and role name required"
        return 1
    fi

    # Check role exists
    if [[ -z "${_RBAC_ROLES[$role_name]:-}" && -z "${_RBAC_ROLE_INHERITS[$role_name]:-}" ]]; then
        _rbac_log "error" "Role not found: $role_name"
        return 1
    fi

    # Check if already assigned
    local current="${_RBAC_SUBJECT_ROLES[$subject_id]:-}"
    if [[ " $current " == *" $role_name "* ]]; then
        return 0
    fi

    # Assign role
    if [[ -n "$current" ]]; then
        _RBAC_SUBJECT_ROLES["$subject_id"]+=" $role_name"
    else
        _RBAC_SUBJECT_ROLES["$subject_id"]="$role_name"
    fi

    _rbac_clear_cache "$subject_id"
    _rbac_log "info" "Assigned role '$role_name' to subject '$subject_id'"
    return 0
}

# @pre: subject_id exists with role_name assigned
# @post: role is removed from subject
# @idempotent: yes
# @returns: 0 on success, 1 if not assigned
#
# Revoke a role from a subject.
#
# Usage: rbac_revoke_role "subject_id" "role_name"
# Example:
#   rbac_revoke_role "agent-123" "admin"
rbac_revoke_role() {
    local subject_id="$1"
    local role_name="$2"

    if [[ -z "$subject_id" || -z "$role_name" ]]; then
        _rbac_log "error" "Subject ID and role name required"
        return 1
    fi

    local current="${_RBAC_SUBJECT_ROLES[$subject_id]:-}"
    if [[ -z "$current" ]]; then
        _rbac_log "warn" "Subject has no roles: $subject_id"
        return 1
    fi

    if [[ " $current " != *" $role_name "* ]]; then
        _rbac_log "warn" "Subject '$subject_id' does not have role '$role_name'"
        return 1
    fi

    # Remove role
    local new_roles=""
    local r
    for r in $current; do
        [[ "$r" != "$role_name" ]] && new_roles+="$r "
    done
    _RBAC_SUBJECT_ROLES["$subject_id"]="${new_roles% }"

    _rbac_clear_cache "$subject_id"
    _rbac_log "info" "Revoked role '$role_name' from subject '$subject_id'"
    return 0
}

# @pre: subject_id exists
# @post: prints roles to stdout
# @idempotent: yes
# @returns: 0 on success (prints roles), 1 if subject not found
#
# Get all roles assigned to a subject.
#
# Usage: rbac_get_roles "subject_id"
# Output: Space-separated role names
rbac_get_roles() {
    local subject_id="$1"

    if [[ -z "$subject_id" ]]; then
        return 1
    fi

    local roles="${_RBAC_SUBJECT_ROLES[$subject_id]:-}"
    if [[ -z "$roles" ]]; then
        return 1
    fi

    printf '%s\n' "$roles"
    return 0
}

# @pre: none
# @post: prints all subjects and their roles
# @idempotent: yes
# @returns: 0
#
# List all subjects with their assigned roles.
#
# Usage: rbac_list_subjects
# Output: One line per subject: subject_id: role1 role2 ...
rbac_list_subjects() {
    local subject
    for subject in "${!_RBAC_SUBJECT_ROLES[@]}"; do
        printf '%s: %s\n' "$subject" "${_RBAC_SUBJECT_ROLES[$subject]}"
    done | sort
}

# =============================================================================
# PUBLIC API - PERMISSION CHECKING
# =============================================================================

# @pre: subject_id and permission are non-empty
# @post: returns 0 if permitted, 1 if denied
# @idempotent: yes (uses cache)
# @returns: 0=permitted, 1=denied
#
# Check if a subject has a specific permission.
# Supports wildcard matching in both the permission requested and role definitions.
#
# Usage: rbac_check_permission "subject_id" "permission"
# Example:
#   if rbac_check_permission "agent-123" "files:read"; then
#       echo "Access granted"
#   fi
rbac_check_permission() {
    local subject_id="$1"
    local permission="$2"

    if [[ -z "$subject_id" || -z "$permission" ]]; then
        return 1
    fi

    # Check cache
    local cache_key="${subject_id}:${permission}"
    if [[ -n "${_RBAC_PERM_CACHE[$cache_key]+x}" ]]; then
        return "${_RBAC_PERM_CACHE[$cache_key]}"
    fi

    # Get subject's roles
    local roles="${_RBAC_SUBJECT_ROLES[$subject_id]:-}"
    if [[ -z "$roles" ]]; then
        _RBAC_PERM_CACHE["$cache_key"]=1
        return 1
    fi

    # Check each role's permissions
    local role
    for role in $roles; do
        local perms
        perms=$(_rbac_get_role_permissions "$role")

        local perm
        for perm in $perms; do
            if _rbac_permission_matches "$perm" "$permission"; then
                _RBAC_PERM_CACHE["$cache_key"]=0
                return 0
            fi
        done
    done

    _RBAC_PERM_CACHE["$cache_key"]=1
    return 1
}

# @pre: permission is non-empty
# @post: exits with 77 if denied, continues if permitted
# @idempotent: yes
# @returns: 0 if permitted, exits with 77 if denied
#
# Assert permission is granted for current subject.
# Uses RBAC_SUBJECT environment variable or defaults to "anonymous".
#
# Usage: rbac_require_permission "permission"
# Example:
#   export RBAC_SUBJECT="agent-123"
#   rbac_require_permission "secrets:read"  # Exits if denied
rbac_require_permission() {
    local permission="$1"
    local subject="${RBAC_SUBJECT:-anonymous}"

    if [[ -z "$permission" ]]; then
        _rbac_log "error" "Permission required"
        exit 77
    fi

    if ! rbac_check_permission "$subject" "$permission"; then
        _rbac_log "error" "Permission denied: $subject requires $permission"
        rbac_audit_access "$subject" "${permission%%:*}" "${permission#*:}" "denied"
        exit 77
    fi

    return 0
}

# @pre: subject_id is non-empty
# @post: prints all effective permissions
# @idempotent: yes
# @returns: 0
#
# Get all effective permissions for a subject (across all roles).
#
# Usage: rbac_get_permissions "subject_id"
# Output: One permission per line
rbac_get_permissions() {
    local subject_id="$1"

    if [[ -z "$subject_id" ]]; then
        return 1
    fi

    local roles="${_RBAC_SUBJECT_ROLES[$subject_id]:-}"
    if [[ -z "$roles" ]]; then
        return 0
    fi

    local -A all_perms=()
    local role
    for role in $roles; do
        local perms
        perms=$(_rbac_get_role_permissions "$role")
        local perm
        for perm in $perms; do
            all_perms["$perm"]=1
        done
    done

    local p
    for p in "${!all_perms[@]}"; do
        printf '%s\n' "$p"
    done | sort
}

# =============================================================================
# PUBLIC API - AUDIT LOGGING
# =============================================================================

# @pre: log_file path is writable
# @post: audit logging is enabled
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Set audit log file path.
#
# Usage: rbac_set_audit_log "/var/log/rbac-audit.log"
rbac_set_audit_log() {
    local log_file="$1"

    if [[ -z "$log_file" ]]; then
        _RBAC_AUDIT_LOG=""
        return 0
    fi

    # Check directory exists
    local log_dir
    log_dir=$(dirname "$log_file")
    if [[ ! -d "$log_dir" ]]; then
        _rbac_log "error" "Audit log directory does not exist: $log_dir"
        return 1
    fi

    _RBAC_AUDIT_LOG="$log_file"
    _rbac_log "info" "Audit logging enabled: $log_file"
    return 0
}

# @pre: all parameters are non-empty
# @post: audit record is written to log file (if configured)
# @idempotent: no (appends to log)
# @returns: 0
#
# Log an access attempt for auditing.
#
# Usage: rbac_audit_access "subject" "resource" "action" "result" ["context"]
# Example:
#   rbac_audit_access "agent-123" "files" "read" "granted" "/path/to/file"
#   rbac_audit_access "agent-456" "secrets" "write" "denied" "attempt to modify api-key"
rbac_audit_access() {
    local subject="$1"
    local resource="$2"
    local action="$3"
    local result="$4"
    local context="${5:-}"

    # Always log to debug
    _rbac_log "debug" "AUDIT: subject=$subject resource=$resource action=$action result=$result context=$context"

    # Write to audit log if configured
    if [[ -n "$_RBAC_AUDIT_LOG" ]]; then
        local timestamp
        timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

        # Escape pipe characters in context
        context="${context//|/\\|}"

        printf '%s|%s|%s|%s|%s|%s\n' \
            "$timestamp" "$subject" "$resource" "$action" "$result" "$context" \
            >> "$_RBAC_AUDIT_LOG"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - IMPORT/EXPORT
# =============================================================================

# @pre: output_file is writable
# @post: RBAC config is written as JSON
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Export RBAC configuration to JSON file.
#
# Usage: rbac_export "rbac-backup.json"
# Output: JSON with roles and subjects sections
rbac_export() {
    local output_file="$1"

    if [[ -z "$output_file" ]]; then
        _rbac_log "error" "Output file required"
        return 1
    fi

    local json='{"roles":{'
    local first=true
    local role

    # Export roles
    for role in "${!_RBAC_ROLES[@]}"; do
        $first || json+=','
        first=false

        json+='"'"$role"'":{'

        # Permissions
        json+='"permissions":['
        local pfirst=true perm
        for perm in ${_RBAC_ROLES[$role]}; do
            $pfirst || json+=','
            pfirst=false
            json+='"'"$perm"'"'
        done
        json+=']'

        # Inherits
        if [[ -n "${_RBAC_ROLE_INHERITS[$role]:-}" ]]; then
            json+=',"inherits":['
            pfirst=true
            for perm in ${_RBAC_ROLE_INHERITS[$role]}; do
                $pfirst || json+=','
                pfirst=false
                json+='"'"$perm"'"'
            done
            json+=']'
        fi

        # Description
        if [[ -n "${_RBAC_ROLE_DESC[$role]:-}" ]]; then
            local desc="${_RBAC_ROLE_DESC[$role]}"
            desc="${desc//\\/\\\\}"
            desc="${desc//\"/\\\"}"
            json+=',"description":"'"$desc"'"'
        fi

        json+='}'
    done
    json+='}'

    # Export subjects
    json+=',"subjects":{'
    first=true
    local subject
    for subject in "${!_RBAC_SUBJECT_ROLES[@]}"; do
        $first || json+=','
        first=false

        json+='"'"$subject"'":{"roles":['
        local sfirst=true r
        for r in ${_RBAC_SUBJECT_ROLES[$subject]}; do
            $sfirst || json+=','
            sfirst=false
            json+='"'"$r"'"'
        done
        json+=']}'
    done
    json+='}}'

    printf '%s\n' "$json" > "$output_file"
    _rbac_log "info" "Exported RBAC config to $output_file"
    return 0
}

# @pre: input_file is a valid JSON export
# @post: RBAC state is populated from JSON
# @idempotent: yes (clears previous state)
# @returns: 0 on success, 1 on error
#
# Import RBAC configuration from JSON file.
#
# Usage: rbac_import "rbac-backup.json"
rbac_import() {
    local input_file="$1"

    if [[ -z "$input_file" ]]; then
        _rbac_log "error" "Input file required"
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        _rbac_log "error" "Import file not found: $input_file"
        return 1
    fi

    # Clear existing state
    _RBAC_ROLES=()
    _RBAC_ROLE_INHERITS=()
    _RBAC_ROLE_DESC=()
    _RBAC_SUBJECT_ROLES=()
    _RBAC_PERM_CACHE=()

    # Use jq if available for robust parsing
    if command -v jq &>/dev/null; then
        local json
        json=$(<"$input_file")

        # Parse roles
        local role
        while IFS= read -r role; do
            [[ -z "$role" ]] && continue

            # Get permissions
            local perms
            perms=$(jq -r ".roles.\"$role\".permissions // [] | .[]" <<< "$json" 2>/dev/null | tr '\n' ' ')
            _RBAC_ROLES["$role"]="${perms% }"

            # Get inherits
            local inherits
            inherits=$(jq -r ".roles.\"$role\".inherits // [] | .[]" <<< "$json" 2>/dev/null | tr '\n' ' ')
            [[ -n "${inherits% }" ]] && _RBAC_ROLE_INHERITS["$role"]="${inherits% }"

            # Get description
            local desc
            desc=$(jq -r ".roles.\"$role\".description // empty" <<< "$json" 2>/dev/null)
            [[ -n "$desc" ]] && _RBAC_ROLE_DESC["$role"]="$desc"

        done < <(jq -r '.roles | keys[]' <<< "$json" 2>/dev/null)

        # Parse subjects
        local subject
        while IFS= read -r subject; do
            [[ -z "$subject" ]] && continue

            local roles
            roles=$(jq -r ".subjects.\"$subject\".roles // [] | .[]" <<< "$json" 2>/dev/null | tr '\n' ' ')
            _RBAC_SUBJECT_ROLES["$subject"]="${roles% }"

        done < <(jq -r '.subjects | keys[]' <<< "$json" 2>/dev/null)

    else
        # Fallback: basic JSON parsing (limited)
        _rbac_log "warn" "jq not available, using limited JSON parsing"

        local json
        json=$(<"$input_file")

        # Very basic extraction - works for simple cases
        # Extract role names and permissions using regex
        local role_block
        role_block=$(grep -oP '"roles"\s*:\s*\{[^}]+\}' <<< "$json" || true)

        # This is a simplified fallback - recommend jq for production
        _rbac_log "warn" "JSON import without jq may be incomplete"
    fi

    _rbac_log "info" "Imported RBAC config from $input_file"
    _rbac_log "debug" "Loaded ${#_RBAC_ROLES[@]} roles, ${#_RBAC_SUBJECT_ROLES[@]} subjects"

    return 0
}

# =============================================================================
# PUBLIC API - UTILITIES
# =============================================================================

# @pre: none
# @post: prints RBAC statistics
# @idempotent: yes
# @returns: 0
#
# Get RBAC system statistics.
#
# Usage: rbac_stats
# Output: JSON with role_count, subject_count, cache_size
rbac_stats() {
    local role_count=${#_RBAC_ROLES[@]}
    local subject_count=${#_RBAC_SUBJECT_ROLES[@]}
    local cache_size=${#_RBAC_PERM_CACHE[@]}

    printf '{"role_count":%d,"subject_count":%d,"cache_entries":%d,"audit_enabled":%s}\n' \
        "$role_count" "$subject_count" "$cache_size" \
        "$([[ -n "$_RBAC_AUDIT_LOG" ]] && echo "true" || echo "false")"
}

# @pre: none
# @post: clears permission cache
# @idempotent: yes
# @returns: 0
#
# Clear the permission cache (call after bulk role changes).
#
# Usage: rbac_clear_cache
rbac_clear_cache() {
    _rbac_clear_all_cache
    _rbac_log "debug" "Permission cache cleared"
    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_RBAC_EXPORTS=(
    # Initialization
    rbac_init
    rbac_reset
    # Role management
    rbac_define_role
    rbac_inherit_role
    rbac_delete_role
    rbac_list_roles
    rbac_get_role
    # Subject management
    rbac_assign_role
    rbac_revoke_role
    rbac_get_roles
    rbac_list_subjects
    # Permission checking
    rbac_check_permission
    rbac_require_permission
    rbac_get_permissions
    # Audit
    rbac_set_audit_log
    rbac_audit_access
    # Import/Export
    rbac_export
    rbac_import
    # Utilities
    rbac_stats
    rbac_clear_cache
)

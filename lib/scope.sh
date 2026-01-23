#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/scope.sh - Scope Boundary Enforcement for AI Agent Safety
# =============================================================================
# Description: Manages filesystem, network, and command execution scopes to
#              constrain AI agent operations. Provides structured JSON violation
#              reporting and persistence for cross-process boundary enforcement.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SCOPE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SCOPE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Directory for persisted scope state (cross-process visibility)
MAINFRAME_SCOPE_DIR="${MAINFRAME_SCOPE_DIR:-/tmp/mainframe_scope_$$}"

# Enable/disable scope enforcement (disable for trusted environments)
MAINFRAME_SCOPE_ENABLED="${MAINFRAME_SCOPE_ENABLED:-1}"

# Emit violations as JSON (1) or plain text (0)
MAINFRAME_SCOPE_JSON="${MAINFRAME_SCOPE_JSON:-1}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Associative arrays for in-memory scope storage
declare -gA _MAINFRAME_SCOPE_FS=()
declare -gA _MAINFRAME_SCOPE_NET=()
declare -gA _MAINFRAME_SCOPE_CMD=()

# Counter for scope entries (used as keys in associative arrays)
declare -g _MAINFRAME_SCOPE_FS_COUNT=0
declare -g _MAINFRAME_SCOPE_NET_COUNT=0
declare -g _MAINFRAME_SCOPE_CMD_COUNT=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string (use json_escape if available, otherwise inline)
_scope_escape() {
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

# Emit a scope violation to stderr
_scope_violation() {
    local operation="$1"
    local target="$2"
    local scope_type="$3"
    shift 3
    # Remaining args are allowed scope entries
    local -a allowed=("$@")

    local ts
    ts=$(date +%s)

    if [[ "$MAINFRAME_SCOPE_JSON" == "1" ]]; then
        local escaped_op escaped_target escaped_type
        escaped_op=$(_scope_escape "$operation")
        escaped_target=$(_scope_escape "$target")
        escaped_type=$(_scope_escape "$scope_type")

        # Build allowed_scope JSON array
        local allowed_json="["
        local first=true
        local entry
        for entry in "${allowed[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                allowed_json+=","
            fi
            allowed_json+="\"$(_scope_escape "$entry")\""
        done
        allowed_json+="]"

        printf '{"error":true,"type":"scope_violation","severity":"high","scope_kind":"%s","operation":"%s","target":"%s","allowed_scope":%s,"action":"blocked","timestamp":%d}\n' \
            "$escaped_type" "$escaped_op" "$escaped_target" "$allowed_json" "$ts" >&2
    else
        local allowed_str=""
        local i
        for ((i=0; i<${#allowed[@]}; i++)); do
            if ((i > 0)); then
                allowed_str+=","
            fi
            allowed_str+="${allowed[$i]}"
        done
        printf '[scope] VIOLATION (%s): operation=%s target=%s allowed=[%s] action=blocked\n' \
            "$scope_type" "$operation" "$target" "$allowed_str" >&2
    fi
}

# Normalize a path for consistent prefix matching
_scope_normalize_path() {
    local path="$1"

    # Use path_normalize if available
    if declare -F path_normalize &>/dev/null; then
        path_normalize "$path"
        return
    fi

    # Inline normalization fallback: resolve . and .. and collapse slashes
    local result=""
    local -a parts=()
    local prefix=""
    [[ "$path" == /* ]] && prefix="/"

    # Remove trailing slashes
    path="${path%"${path##*[!/]}"}"
    [[ -z "$path" ]] && path="/"

    local IFS='/'
    read -ra parts <<< "$path"

    local -a stack=()
    local part
    for part in "${parts[@]}"; do
        [[ -z "$part" || "$part" == "." ]] && continue
        if [[ "$part" == ".." ]]; then
            if [[ ${#stack[@]} -gt 0 && "${stack[-1]}" != ".." ]]; then
                unset 'stack[-1]'
            elif [[ -z "$prefix" ]]; then
                stack+=("$part")
            fi
        else
            stack+=("$part")
        fi
    done

    if [[ ${#stack[@]} -eq 0 ]]; then
        result="${prefix:-.}"
    else
        local IFS='/'
        result="${prefix}${stack[*]}"
    fi

    printf '%s' "$result"
}

# Ensure trailing slash for directory prefix matching
_scope_ensure_trailing_slash() {
    local path="$1"
    if [[ "$path" != */ ]]; then
        printf '%s/' "$path"
    else
        printf '%s' "$path"
    fi
}

# Persist scope state to disk for cross-process visibility
_scope_persist() {
    local scope_type="$1"

    mkdir -p "$MAINFRAME_SCOPE_DIR" 2>/dev/null || return 1

    local file="${MAINFRAME_SCOPE_DIR}/${scope_type}"

    case "$scope_type" in
        filesystem)
            local key
            : > "$file"
            for key in "${!_MAINFRAME_SCOPE_FS[@]}"; do
                printf '%s\n' "${_MAINFRAME_SCOPE_FS[$key]}" >> "$file"
            done
            ;;
        network)
            local key
            : > "$file"
            for key in "${!_MAINFRAME_SCOPE_NET[@]}"; do
                printf '%s\n' "${_MAINFRAME_SCOPE_NET[$key]}" >> "$file"
            done
            ;;
        commands)
            local key
            : > "$file"
            for key in "${!_MAINFRAME_SCOPE_CMD[@]}"; do
                printf '%s\n' "${_MAINFRAME_SCOPE_CMD[$key]}" >> "$file"
            done
            ;;
    esac
}

# Load scope state from disk
_scope_load() {
    local scope_type="$1"
    local file="${MAINFRAME_SCOPE_DIR}/${scope_type}"

    [[ -f "$file" ]] || return 1

    case "$scope_type" in
        filesystem)
            _MAINFRAME_SCOPE_FS=()
            _MAINFRAME_SCOPE_FS_COUNT=0
            local line
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                _MAINFRAME_SCOPE_FS[$_MAINFRAME_SCOPE_FS_COUNT]="$line"
                _MAINFRAME_SCOPE_FS_COUNT=$((_MAINFRAME_SCOPE_FS_COUNT + 1))
            done < "$file"
            ;;
        network)
            _MAINFRAME_SCOPE_NET=()
            _MAINFRAME_SCOPE_NET_COUNT=0
            local line
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                _MAINFRAME_SCOPE_NET[$_MAINFRAME_SCOPE_NET_COUNT]="$line"
                _MAINFRAME_SCOPE_NET_COUNT=$((_MAINFRAME_SCOPE_NET_COUNT + 1))
            done < "$file"
            ;;
        commands)
            _MAINFRAME_SCOPE_CMD=()
            _MAINFRAME_SCOPE_CMD_COUNT=0
            local line
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                _MAINFRAME_SCOPE_CMD[$_MAINFRAME_SCOPE_CMD_COUNT]="$line"
                _MAINFRAME_SCOPE_CMD_COUNT=$((_MAINFRAME_SCOPE_CMD_COUNT + 1))
            done < "$file"
            ;;
    esac
}

# Convert IP to integer for CIDR comparison
_scope_ip_to_int() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"

    # Validate octets
    [[ "$a" =~ ^[0-9]+$ ]] || return 1
    [[ "$b" =~ ^[0-9]+$ ]] || return 1
    [[ "$c" =~ ^[0-9]+$ ]] || return 1
    [[ "$d" =~ ^[0-9]+$ ]] || return 1

    printf '%d' $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# Check if IP is within a CIDR range
_scope_ip_in_cidr() {
    local ip="$1"
    local cidr="$2"

    local network="${cidr%%/*}"
    local prefix="${cidr##*/}"

    # Validate prefix length
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1

    local ip_int network_int mask
    ip_int=$(_scope_ip_to_int "$ip") || return 1
    network_int=$(_scope_ip_to_int "$network") || return 1

    # Calculate mask
    if (( prefix == 0 )); then
        mask=0
    else
        mask=$(( 0xFFFFFFFF << (32 - prefix) ))
        # Handle bash arithmetic for large numbers
        mask=$(( mask & 0xFFFFFFFF ))
    fi

    # Check if IP is in network range
    (( (ip_int & mask) == (network_int & mask) ))
}

# Check if a string is a valid IPv4 address
_scope_is_ipv4() {
    local str="$1"
    [[ "$str" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local a b c d
    IFS='.' read -r a b c d <<< "$str"
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

# =============================================================================
# PUBLIC API: SCOPE MANAGEMENT
# =============================================================================

# @pre: type is one of: filesystem, network, commands
# @post: scope entries stored in memory and persisted to disk
# @idempotent: no - replaces existing scope of given type
# @returns: 0 on success, 1 on invalid type
#
# Set scope boundaries for a given type.
#   filesystem: colon-separated list of allowed directories
#   network: comma-separated list of allowed hosts/CIDRs
#   commands: comma-separated list of allowed commands
#
# Usage: mainframe_scope_set filesystem "/home/user/project:/tmp"
# Usage: mainframe_scope_set network "localhost,10.0.0.0/8,github.com"
# Usage: mainframe_scope_set commands "git,npm,docker,python"
mainframe_scope_set() {
    local type="$1"
    local value="$2"

    if [[ -z "$type" ]] || [[ -z "$value" ]]; then
        if declare -F mainframe_error &>/dev/null; then
            mainframe_error 1 "mainframe_scope_set: type and value required"
        fi
        return 1
    fi

    case "$type" in
        filesystem)
            _MAINFRAME_SCOPE_FS=()
            _MAINFRAME_SCOPE_FS_COUNT=0
            local IFS=':'
            local entry
            for entry in $value; do
                [[ -z "$entry" ]] && continue
                # Normalize the path
                local normalized
                normalized=$(_scope_normalize_path "$entry")
                _MAINFRAME_SCOPE_FS[$_MAINFRAME_SCOPE_FS_COUNT]="$normalized"
                _MAINFRAME_SCOPE_FS_COUNT=$((_MAINFRAME_SCOPE_FS_COUNT + 1))
            done
            _scope_persist "filesystem"
            ;;
        network)
            _MAINFRAME_SCOPE_NET=()
            _MAINFRAME_SCOPE_NET_COUNT=0
            local IFS=','
            local entry
            for entry in $value; do
                # Trim whitespace
                entry="${entry#"${entry%%[![:space:]]*}"}"
                entry="${entry%"${entry##*[![:space:]]}"}"
                [[ -z "$entry" ]] && continue
                _MAINFRAME_SCOPE_NET[$_MAINFRAME_SCOPE_NET_COUNT]="$entry"
                _MAINFRAME_SCOPE_NET_COUNT=$((_MAINFRAME_SCOPE_NET_COUNT + 1))
            done
            _scope_persist "network"
            ;;
        commands)
            _MAINFRAME_SCOPE_CMD=()
            _MAINFRAME_SCOPE_CMD_COUNT=0
            local IFS=','
            local entry
            for entry in $value; do
                # Trim whitespace
                entry="${entry#"${entry%%[![:space:]]*}"}"
                entry="${entry%"${entry##*[![:space:]]}"}"
                [[ -z "$entry" ]] && continue
                _MAINFRAME_SCOPE_CMD[$_MAINFRAME_SCOPE_CMD_COUNT]="$entry"
                _MAINFRAME_SCOPE_CMD_COUNT=$((_MAINFRAME_SCOPE_CMD_COUNT + 1))
            done
            _scope_persist "commands"
            ;;
        *)
            if declare -F mainframe_error &>/dev/null; then
                mainframe_error 1 "mainframe_scope_set: invalid type '$type' (use: filesystem, network, commands)"
            else
                printf '{"error":true,"type":"invalid_scope_type","msg":"invalid type: %s","valid":["filesystem","network","commands"]}\n' \
                    "$(_scope_escape "$type")" >&2
            fi
            return 1
            ;;
    esac
    return 0
}

# @pre: type is one of: filesystem, network, commands; target is non-empty
# @post: returns 0 if target is within scope, 1 if blocked (with violation emitted)
# @idempotent: yes
# @returns: 0 if allowed, 1 if blocked (violation emitted to stderr)
#
# Check if a target is within the defined scope for a given type.
# If no scope is set for the type, all operations are allowed (open scope).
#
# Usage: mainframe_scope_check filesystem "/home/user/project/file.txt"
# Usage: mainframe_scope_check network "github.com"
# Usage: mainframe_scope_check commands "git"
mainframe_scope_check() {
    local type="$1"
    local target="$2"

    # If scope enforcement is disabled, allow everything
    [[ "$MAINFRAME_SCOPE_ENABLED" != "1" ]] && return 0

    if [[ -z "$type" ]] || [[ -z "$target" ]]; then
        if declare -F mainframe_error &>/dev/null; then
            mainframe_error 1 "mainframe_scope_check: type and target required"
        fi
        return 1
    fi

    case "$type" in
        filesystem)
            _scope_check_filesystem "$target"
            ;;
        network)
            _scope_check_network "$target"
            ;;
        commands)
            _scope_check_commands "$target"
            ;;
        *)
            if declare -F mainframe_error &>/dev/null; then
                mainframe_error 1 "mainframe_scope_check: invalid type '$type'"
            fi
            return 1
            ;;
    esac
}

# @pre: optional type argument
# @post: scope entries cleared from memory and disk
# @idempotent: yes
# @returns: 0
#
# Clear scope boundaries. If type is provided, clear only that type.
# If no type is provided, clear all scopes.
#
# Usage: mainframe_scope_clear           # Clear all scopes
# Usage: mainframe_scope_clear filesystem  # Clear only filesystem scope
mainframe_scope_clear() {
    local type="${1:-}"

    if [[ -z "$type" ]]; then
        # Clear all
        _MAINFRAME_SCOPE_FS=()
        _MAINFRAME_SCOPE_FS_COUNT=0
        _MAINFRAME_SCOPE_NET=()
        _MAINFRAME_SCOPE_NET_COUNT=0
        _MAINFRAME_SCOPE_CMD=()
        _MAINFRAME_SCOPE_CMD_COUNT=0
        rm -f "${MAINFRAME_SCOPE_DIR}/filesystem" 2>/dev/null
        rm -f "${MAINFRAME_SCOPE_DIR}/network" 2>/dev/null
        rm -f "${MAINFRAME_SCOPE_DIR}/commands" 2>/dev/null
    else
        case "$type" in
            filesystem)
                _MAINFRAME_SCOPE_FS=()
                _MAINFRAME_SCOPE_FS_COUNT=0
                rm -f "${MAINFRAME_SCOPE_DIR}/filesystem" 2>/dev/null
                ;;
            network)
                _MAINFRAME_SCOPE_NET=()
                _MAINFRAME_SCOPE_NET_COUNT=0
                rm -f "${MAINFRAME_SCOPE_DIR}/network" 2>/dev/null
                ;;
            commands)
                _MAINFRAME_SCOPE_CMD=()
                _MAINFRAME_SCOPE_CMD_COUNT=0
                rm -f "${MAINFRAME_SCOPE_DIR}/commands" 2>/dev/null
                ;;
            *)
                return 1
                ;;
        esac
    fi
    return 0
}

# @pre: none
# @post: JSON status emitted to stdout
# @idempotent: yes
# @returns: 0
#
# Show active scopes as JSON. Reports all three scope types with their entries.
#
# Usage: mainframe_scope_status
# Output: {"enabled":true,"filesystem":["/home/user","/tmp"],"network":["localhost"],"commands":["git","npm"]}
mainframe_scope_status() {
    local enabled="true"
    [[ "$MAINFRAME_SCOPE_ENABLED" != "1" ]] && enabled="false"

    local json="{\"enabled\":${enabled}"

    # Filesystem scope
    json+=",\"filesystem\":["
    local first=true key
    for key in "${!_MAINFRAME_SCOPE_FS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$(_scope_escape "${_MAINFRAME_SCOPE_FS[$key]}")\""
    done
    json+="]"

    # Network scope
    json+=",\"network\":["
    first=true
    for key in "${!_MAINFRAME_SCOPE_NET[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$(_scope_escape "${_MAINFRAME_SCOPE_NET[$key]}")\""
    done
    json+="]"

    # Commands scope
    json+=",\"commands\":["
    first=true
    for key in "${!_MAINFRAME_SCOPE_CMD[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$(_scope_escape "${_MAINFRAME_SCOPE_CMD[$key]}")\""
    done
    json+="]"

    json+="}"
    printf '%s\n' "$json"
}

# =============================================================================
# SCOPE CHECK IMPLEMENTATIONS
# =============================================================================

# Check filesystem scope: path prefix matching after normalization
_scope_check_filesystem() {
    local target="$1"

    # If no filesystem scope is set, allow (open scope)
    [[ ${#_MAINFRAME_SCOPE_FS[@]} -eq 0 ]] && return 0

    # Normalize the target path
    local normalized_target
    normalized_target=$(_scope_normalize_path "$target")

    # Check each allowed directory
    local key allowed_dir
    for key in "${!_MAINFRAME_SCOPE_FS[@]}"; do
        allowed_dir="${_MAINFRAME_SCOPE_FS[$key]}"

        # Exact match
        if [[ "$normalized_target" == "$allowed_dir" ]]; then
            return 0
        fi

        # Prefix match: target is within allowed directory
        local allowed_prefix
        allowed_prefix=$(_scope_ensure_trailing_slash "$allowed_dir")
        if [[ "$normalized_target" == "${allowed_prefix}"* ]]; then
            return 0
        fi
    done

    # Violation: target is outside all allowed scopes
    local -a allowed_list=()
    for key in "${!_MAINFRAME_SCOPE_FS[@]}"; do
        allowed_list+=("${_MAINFRAME_SCOPE_FS[$key]}")
    done
    _scope_violation "filesystem_access" "$normalized_target" "filesystem" "${allowed_list[@]}"
    return 1
}

# Check network scope: hostname and CIDR matching
_scope_check_network() {
    local target="$1"

    # If no network scope is set, allow (open scope)
    [[ ${#_MAINFRAME_SCOPE_NET[@]} -eq 0 ]] && return 0

    # Strip port if present (host:port format)
    local host="$target"
    if [[ "$host" == *:* ]] && [[ "$host" != */* ]]; then
        host="${host%%:*}"
    fi

    # Check each allowed entry
    local key entry
    for key in "${!_MAINFRAME_SCOPE_NET[@]}"; do
        entry="${_MAINFRAME_SCOPE_NET[$key]}"

        # Direct hostname match (case-insensitive)
        if [[ "${host,,}" == "${entry,,}" ]]; then
            return 0
        fi

        # CIDR match: if entry contains / and target is an IP
        if [[ "$entry" == */* ]] && _scope_is_ipv4 "$host"; then
            if _scope_ip_in_cidr "$host" "$entry"; then
                return 0
            fi
        fi

        # Wildcard domain match: *.example.com
        if [[ "$entry" == \*.* ]]; then
            local domain="${entry#\*.}"
            if [[ "${host,,}" == *.${domain,,} ]] || [[ "${host,,}" == "${domain,,}" ]]; then
                return 0
            fi
        fi

        # localhost aliases
        if [[ "${entry,,}" == "localhost" ]]; then
            if [[ "$host" == "127.0.0.1" ]] || [[ "$host" == "::1" ]]; then
                return 0
            fi
        fi
        if [[ "$host" == "localhost" ]]; then
            if [[ "$entry" == "127.0.0.1" ]] || [[ "$entry" == "::1" ]]; then
                return 0
            fi
        fi
    done

    # Violation: target host not in allowed scope
    local -a allowed_list=()
    for key in "${!_MAINFRAME_SCOPE_NET[@]}"; do
        allowed_list+=("${_MAINFRAME_SCOPE_NET[$key]}")
    done
    _scope_violation "network_access" "$target" "network" "${allowed_list[@]}"
    return 1
}

# Check command scope: exact command name matching
_scope_check_commands() {
    local target="$1"

    # If no command scope is set, allow (open scope)
    [[ ${#_MAINFRAME_SCOPE_CMD[@]} -eq 0 ]] && return 0

    # Extract base command name (strip path and arguments)
    local cmd_name="$target"
    # If target contains spaces, take first word (command name)
    cmd_name="${cmd_name%% *}"
    # Strip path to get just the binary name
    cmd_name="${cmd_name##*/}"

    # Check each allowed command
    local key entry
    for key in "${!_MAINFRAME_SCOPE_CMD[@]}"; do
        entry="${_MAINFRAME_SCOPE_CMD[$key]}"
        if [[ "$cmd_name" == "$entry" ]]; then
            return 0
        fi
    done

    # Violation: command not in allowed scope
    local -a allowed_list=()
    for key in "${!_MAINFRAME_SCOPE_CMD[@]}"; do
        allowed_list+=("${_MAINFRAME_SCOPE_CMD[$key]}")
    done
    _scope_violation "$cmd_name" "$target" "commands" "${allowed_list[@]}"
    return 1
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# @pre: scope set via mainframe_scope_set
# @post: returns 0 if path allowed, 1 if blocked
# @idempotent: yes
# @returns: 0 if allowed, 1 if blocked
#
# Convenience wrapper to check filesystem scope for a path.
#
# Usage: mainframe_scope_check_path "/path/to/file"
mainframe_scope_check_path() {
    mainframe_scope_check "filesystem" "$1"
}

# @pre: scope set via mainframe_scope_set
# @post: returns 0 if host allowed, 1 if blocked
# @idempotent: yes
# @returns: 0 if allowed, 1 if blocked
#
# Convenience wrapper to check network scope for a host.
#
# Usage: mainframe_scope_check_host "github.com"
mainframe_scope_check_host() {
    mainframe_scope_check "network" "$1"
}

# @pre: scope set via mainframe_scope_set
# @post: returns 0 if command allowed, 1 if blocked
# @idempotent: yes
# @returns: 0 if allowed, 1 if blocked
#
# Convenience wrapper to check command scope.
#
# Usage: mainframe_scope_check_cmd "git"
mainframe_scope_check_cmd() {
    mainframe_scope_check "commands" "$1"
}

# @pre: scope set, command is non-empty
# @post: runs command if allowed, blocks with violation if not
# @returns: command exit code if allowed, 1 if blocked
#
# Execute a command only if it passes scope checks.
# Checks both command scope (if set) and filesystem scope for path arguments.
#
# Usage: mainframe_scope_exec git commit -m "update"
mainframe_scope_exec() {
    local cmd="$1"
    shift

    # Check command scope
    if ! mainframe_scope_check "commands" "$cmd"; then
        return 1
    fi

    # Execute the command
    "$cmd" "$@"
}

# @pre: none
# @post: loads scope state from persisted files
# @idempotent: yes
# @returns: 0
#
# Reload scope state from disk. Useful for cross-process coordination
# where another process may have updated the scope.
#
# Usage: mainframe_scope_reload
mainframe_scope_reload() {
    _scope_load "filesystem" 2>/dev/null || true
    _scope_load "network" 2>/dev/null || true
    _scope_load "commands" 2>/dev/null || true
    return 0
}

# @pre: none
# @post: scope dir removed, state cleared
# @idempotent: yes
# @returns: 0
#
# Destroy all scope state including persisted files.
# Use when an agent session ends.
#
# Usage: mainframe_scope_destroy
mainframe_scope_destroy() {
    mainframe_scope_clear
    rm -rf "$MAINFRAME_SCOPE_DIR" 2>/dev/null
    return 0
}

# @pre: filesystem scope set
# @post: adds additional path to existing filesystem scope
# @returns: 0
#
# Add a single directory to the filesystem scope without replacing existing entries.
#
# Usage: mainframe_scope_add_path "/additional/allowed/dir"
mainframe_scope_add_path() {
    local path="$1"
    [[ -z "$path" ]] && return 1

    local normalized
    normalized=$(_scope_normalize_path "$path")
    _MAINFRAME_SCOPE_FS[$_MAINFRAME_SCOPE_FS_COUNT]="$normalized"
    _MAINFRAME_SCOPE_FS_COUNT=$((_MAINFRAME_SCOPE_FS_COUNT + 1))
    _scope_persist "filesystem"
    return 0
}

# @pre: network scope set
# @post: adds additional host to existing network scope
# @returns: 0
#
# Add a single host/CIDR to the network scope without replacing existing entries.
#
# Usage: mainframe_scope_add_host "api.example.com"
mainframe_scope_add_host() {
    local host="$1"
    [[ -z "$host" ]] && return 1

    # Trim whitespace
    host="${host#"${host%%[![:space:]]*}"}"
    host="${host%"${host##*[![:space:]]}"}"

    _MAINFRAME_SCOPE_NET[$_MAINFRAME_SCOPE_NET_COUNT]="$host"
    _MAINFRAME_SCOPE_NET_COUNT=$((_MAINFRAME_SCOPE_NET_COUNT + 1))
    _scope_persist "network"
    return 0
}

# @pre: commands scope set
# @post: adds additional command to existing commands scope
# @returns: 0
#
# Add a single command to the commands scope without replacing existing entries.
#
# Usage: mainframe_scope_add_cmd "curl"
mainframe_scope_add_cmd() {
    local cmd="$1"
    [[ -z "$cmd" ]] && return 1

    # Trim whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"

    _MAINFRAME_SCOPE_CMD[$_MAINFRAME_SCOPE_CMD_COUNT]="$cmd"
    _MAINFRAME_SCOPE_CMD_COUNT=$((_MAINFRAME_SCOPE_CMD_COUNT + 1))
    _scope_persist "commands"
    return 0
}

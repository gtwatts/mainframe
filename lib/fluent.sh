#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/fluent.sh - Fluent Validation DSL
# =============================================================================
# Description: Chainable validation primitives using is::, when::, assert::
#              namespaced functions for expressive file and value checks.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FLUENT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FLUENT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Exit on assertion failure (set to 0 for soft assertions)
FLUENT_EXIT_ON_FAILURE="${FLUENT_EXIT_ON_FAILURE:-1}"

# Output format: plain or json (USOP)
FLUENT_OUTPUT_FORMAT="${FLUENT_OUTPUT_FORMAT:-plain}"

# Verbose mode for debugging
FLUENT_VERBOSE="${FLUENT_VERBOSE:-0}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_fluent_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Debug output
_fluent_debug() {
    [[ "$FLUENT_VERBOSE" == "1" ]] && printf '[fluent] DEBUG: %s\n' "$*" >&2
}

# Parse duration string to seconds
# Supports: 1s, 5m, 2h, 7d, 1w, 30s, 2h30m, etc.
_fluent_duration_to_seconds() {
    local duration="$1"
    local total=0
    local remaining="$duration"

    # Parse weeks
    if [[ "$remaining" =~ ([0-9]+)w ]]; then
        total=$(( total + BASH_REMATCH[1] * 604800 ))
        remaining="${remaining//${BASH_REMATCH[0]}/}"
    fi

    # Parse days
    if [[ "$remaining" =~ ([0-9]+)d ]]; then
        total=$(( total + BASH_REMATCH[1] * 86400 ))
        remaining="${remaining//${BASH_REMATCH[0]}/}"
    fi

    # Parse hours
    if [[ "$remaining" =~ ([0-9]+)h ]]; then
        total=$(( total + BASH_REMATCH[1] * 3600 ))
        remaining="${remaining//${BASH_REMATCH[0]}/}"
    fi

    # Parse minutes
    if [[ "$remaining" =~ ([0-9]+)m ]]; then
        total=$(( total + BASH_REMATCH[1] * 60 ))
        remaining="${remaining//${BASH_REMATCH[0]}/}"
    fi

    # Parse seconds
    if [[ "$remaining" =~ ([0-9]+)s? ]]; then
        total=$(( total + BASH_REMATCH[1] ))
    fi

    printf '%d' "$total"
}

# Get file modification time in epoch seconds
_fluent_file_mtime() {
    local path="$1"
    if [[ -e "$path" ]]; then
        stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null
    else
        printf '0'
    fi
}

# Get file access time in epoch seconds
_fluent_file_atime() {
    local path="$1"
    if [[ -e "$path" ]]; then
        stat -c %X "$path" 2>/dev/null || stat -f %a "$path" 2>/dev/null
    else
        printf '0'
    fi
}

# Get current timestamp
_fluent_now() {
    printf '%(%s)T' -1
}

# =============================================================================
# ERROR REPORTING (USOP)
# =============================================================================

# Emit structured error in JSON format
# @pre: check_type is non-empty
# @post: JSON error emitted to stderr
# Usage: fluent_error_json "/path" "file" "not_found"
fluent_error_json() {
    local path="$1"
    local check_type="$2"
    local message="$3"
    local func="${FUNCNAME[1]:-main}"
    local line="${BASH_LINENO[0]:-0}"

    local escaped_path escaped_msg escaped_func
    escaped_path=$(_fluent_escape_json "$path")
    escaped_msg=$(_fluent_escape_json "$message")
    escaped_func=$(_fluent_escape_json "$func")

    printf '{"success":false,"error":{"type":"assertion","check":"%s","path":"%s","message":"%s","func":"%s","line":%d}}\n' \
        "$check_type" "$escaped_path" "$escaped_msg" "$escaped_func" "$line" >&2
}

# Emit plain text error
# Usage: fluent_error_plain "/path" "file" "not_found"
fluent_error_plain() {
    local path="$1"
    local check_type="$2"
    local message="$3"
    local func="${FUNCNAME[1]:-main}"

    printf 'ASSERTION FAILED: %s (check=%s, path=%s, func=%s)\n' \
        "$message" "$check_type" "$path" "$func" >&2
}

# Emit error in configured format
# Usage: _fluent_emit_error "/path" "file" "not_found"
_fluent_emit_error() {
    local path="$1"
    local check_type="$2"
    local message="$3"

    if [[ "$FLUENT_OUTPUT_FORMAT" == "json" ]]; then
        fluent_error_json "$path" "$check_type" "$message"
    else
        fluent_error_plain "$path" "$check_type" "$message"
    fi
}

# =============================================================================
# FILE TYPE CHECKS (is::*)
# =============================================================================

# Check if path is a regular file
# @pre: path is non-empty string
# @post: returns 0 if regular file, 1 otherwise
# Usage: is::file "/path/to/file"
is::file() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -f "$path" ]]
}

# Check if path is a directory
# @pre: path is non-empty string
# @post: returns 0 if directory, 1 otherwise
# Usage: is::dir "/path/to/dir"
is::dir() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -d "$path" ]]
}

# Check if path is a symbolic link
# @pre: path is non-empty string
# @post: returns 0 if symlink, 1 otherwise
# Usage: is::link "/path"
is::link() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -L "$path" ]]
}

# Check if path exists (any type)
# @pre: path is non-empty string
# @post: returns 0 if exists, 1 otherwise
# Usage: is::exists "/path"
is::exists() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -e "$path" ]]
}

# Check if path is readable
# @pre: path is non-empty string
# @post: returns 0 if readable, 1 otherwise
# Usage: is::readable "/path"
is::readable() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -r "$path" ]]
}

# Check if path is writable
# @pre: path is non-empty string
# @post: returns 0 if writable, 1 otherwise
# Usage: is::writable "/path"
is::writable() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -w "$path" ]]
}

# Check if path is executable
# @pre: path is non-empty string
# @post: returns 0 if executable, 1 otherwise
# Usage: is::executable "/path"
is::executable() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -x "$path" ]]
}

# Check if file/directory is empty
# @pre: path is non-empty string
# @post: returns 0 if empty, 1 otherwise
# Usage: is::empty "/path"
is::empty() {
    local path="$1"
    [[ -z "$path" ]] && return 1

    if [[ -f "$path" ]]; then
        # File: check size is 0
        [[ ! -s "$path" ]]
    elif [[ -d "$path" ]]; then
        # Directory: check if empty
        local count
        count=$(find "$path" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
        [[ "$count" -eq 0 ]]
    else
        return 1
    fi
}

# Check if file/directory is non-empty
# @pre: path is non-empty string
# @post: returns 0 if non-empty, 1 otherwise
# Usage: is::nonempty "/path"
is::nonempty() {
    local path="$1"
    [[ -z "$path" ]] && return 1

    if [[ -f "$path" ]]; then
        # File: check size > 0
        [[ -s "$path" ]]
    elif [[ -d "$path" ]]; then
        # Directory: check if has contents
        local count
        count=$(find "$path" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
        [[ "$count" -gt 0 ]]
    else
        return 1
    fi
}

# Check if file is owned by user
# @pre: path and user are non-empty strings
# @post: returns 0 if owned by user, 1 otherwise
# Usage: is::owned_by "/path" "user"
is::owned_by() {
    local path="$1"
    local user="$2"
    [[ -z "$path" || -z "$user" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local owner
    owner=$(stat -c %U "$path" 2>/dev/null || stat -f %Su "$path" 2>/dev/null)
    [[ "$owner" == "$user" ]]
}

# Check if file is group owned
# @pre: path and group are non-empty strings
# @post: returns 0 if group owned, 1 otherwise
# Usage: is::group_owned "/path" "grp"
is::group_owned() {
    local path="$1"
    local group="$2"
    [[ -z "$path" || -z "$group" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local file_group
    file_group=$(stat -c %G "$path" 2>/dev/null || stat -f %Sg "$path" 2>/dev/null)
    [[ "$file_group" == "$group" ]]
}

# Check if path is a block device
# @pre: path is non-empty string
# @post: returns 0 if block device, 1 otherwise
# Usage: is::block_device "/dev/sda"
is::block_device() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -b "$path" ]]
}

# Check if path is a character device
# @pre: path is non-empty string
# @post: returns 0 if character device, 1 otherwise
# Usage: is::char_device "/dev/tty"
is::char_device() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -c "$path" ]]
}

# Check if path is a named pipe (FIFO)
# @pre: path is non-empty string
# @post: returns 0 if pipe, 1 otherwise
# Usage: is::pipe "/tmp/mypipe"
is::pipe() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -p "$path" ]]
}

# Check if path is a socket
# @pre: path is non-empty string
# @post: returns 0 if socket, 1 otherwise
# Usage: is::socket "/var/run/docker.sock"
is::socket() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -S "$path" ]]
}

# =============================================================================
# TIME CHECKS (is::*)
# =============================================================================

# Check if file is newer than duration
# @pre: path is non-empty, duration is valid (e.g., "1h", "7d")
# @post: returns 0 if newer than duration, 1 otherwise
# Usage: is::newer_than "/path" "1h"
is::newer_than() {
    local path="$1"
    local duration="$2"
    [[ -z "$path" || -z "$duration" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local seconds now mtime threshold
    seconds=$(_fluent_duration_to_seconds "$duration")
    now=$(_fluent_now)
    mtime=$(_fluent_file_mtime "$path")
    threshold=$(( now - seconds ))

    _fluent_debug "newer_than: mtime=$mtime threshold=$threshold (now=$now - $seconds)"

    [[ "$mtime" -gt "$threshold" ]]
}

# Check if file is older than duration
# @pre: path is non-empty, duration is valid
# @post: returns 0 if older than duration, 1 otherwise
# Usage: is::older_than "/path" "7d"
is::older_than() {
    local path="$1"
    local duration="$2"
    [[ -z "$path" || -z "$duration" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local seconds now mtime threshold
    seconds=$(_fluent_duration_to_seconds "$duration")
    now=$(_fluent_now)
    mtime=$(_fluent_file_mtime "$path")
    threshold=$(( now - seconds ))

    _fluent_debug "older_than: mtime=$mtime threshold=$threshold (now=$now - $seconds)"

    [[ "$mtime" -lt "$threshold" ]]
}

# Check if file was modified after timestamp
# @pre: path is non-empty, timestamp is epoch seconds
# @post: returns 0 if modified after timestamp, 1 otherwise
# Usage: is::modified_after "/path" "1705312896"
is::modified_after() {
    local path="$1"
    local timestamp="$2"
    [[ -z "$path" || -z "$timestamp" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local mtime
    mtime=$(_fluent_file_mtime "$path")

    [[ "$mtime" -gt "$timestamp" ]]
}

# Check if file was modified before timestamp
# @pre: path is non-empty, timestamp is epoch seconds
# @post: returns 0 if modified before timestamp, 1 otherwise
# Usage: is::modified_before "/path" "1705312896"
is::modified_before() {
    local path="$1"
    local timestamp="$2"
    [[ -z "$path" || -z "$timestamp" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local mtime
    mtime=$(_fluent_file_mtime "$path")

    [[ "$mtime" -lt "$timestamp" ]]
}

# Check if file was accessed within duration
# @pre: path is non-empty, duration is valid
# @post: returns 0 if accessed within duration, 1 otherwise
# Usage: is::accessed_within "/path" "1d"
is::accessed_within() {
    local path="$1"
    local duration="$2"
    [[ -z "$path" || -z "$duration" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local seconds now atime threshold
    seconds=$(_fluent_duration_to_seconds "$duration")
    now=$(_fluent_now)
    atime=$(_fluent_file_atime "$path")
    threshold=$(( now - seconds ))

    [[ "$atime" -gt "$threshold" ]]
}

# Check if file was modified today
# @pre: path is non-empty
# @post: returns 0 if modified today, 1 otherwise
# Usage: is::modified_today "/path"
is::modified_today() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local mtime file_date today
    mtime=$(_fluent_file_mtime "$path")
    file_date=$(printf '%(%Y-%m-%d)T' "$mtime")
    today=$(printf '%(%Y-%m-%d)T' -1)

    [[ "$file_date" == "$today" ]]
}

# =============================================================================
# STRING/VALUE CHECKS (is::*)
# =============================================================================

# Check if value is a non-empty string
# @pre: none
# @post: returns 0 if non-empty string, 1 otherwise
# Usage: is::string "value"
is::string() {
    local value="$1"
    [[ -n "$value" ]]
}

# Check if value is a valid integer
# @pre: none
# @post: returns 0 if valid integer, 1 otherwise
# Usage: is::integer "123"
is::integer() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^-?[0-9]+$ ]]
}

# Check if value is a valid float
# @pre: none
# @post: returns 0 if valid float, 1 otherwise
# Usage: is::float "3.14"
is::float() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^-?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]
}

# Check if value is a valid UUID
# @pre: none
# @post: returns 0 if valid UUID, 1 otherwise
# Usage: is::uuid "550e8400-e29b-41d4-a716-446655440000"
is::uuid() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# Check if value is a valid email
# @pre: none
# @post: returns 0 if valid email, 1 otherwise
# Usage: is::email "user@domain.com"
is::email() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Check if value is a valid URL
# @pre: none
# @post: returns 0 if valid URL, 1 otherwise
# Usage: is::url "https://example.com/path"
is::url() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^(https?|ftp|file)://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$ ]]
}

# Check if value is valid JSON
# @pre: none
# @post: returns 0 if valid JSON, 1 otherwise
# Usage: is::json '{"key":"value"}'
is::json() {
    local value="$1"
    [[ -z "$value" ]] && return 1

    # Try to parse with pure bash (basic check)
    # This handles: objects, arrays, strings, numbers, booleans, null
    local trimmed="${value#"${value%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    # Check basic structure
    case "${trimmed:0:1}" in
        '{')
            # Object: must end with }
            [[ "${trimmed: -1}" == '}' ]] || return 1
            ;;
        '[')
            # Array: must end with ]
            [[ "${trimmed: -1}" == ']' ]] || return 1
            ;;
        '"')
            # String: must end with "
            [[ "${trimmed: -1}" == '"' ]] || return 1
            ;;
        [0-9-])
            # Number: basic check
            [[ "$trimmed" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]] || return 1
            ;;
        t|f)
            # Boolean
            [[ "$trimmed" == "true" || "$trimmed" == "false" ]] || return 1
            ;;
        n)
            # Null
            [[ "$trimmed" == "null" ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# Check if value is valid semantic version
# @pre: none
# @post: returns 0 if valid semver, 1 otherwise
# Usage: is::semver "1.2.3"
is::semver() {
    local value="$1"
    [[ -z "$value" ]] && return 1

    # Strip optional 'v' prefix
    [[ "$value" == v* ]] && value="${value:1}"

    [[ "$value" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

# Check if value is a valid hostname
# @pre: none
# @post: returns 0 if valid hostname, 1 otherwise
# Usage: is::hostname "example.com"
is::hostname() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ ${#value} -gt 253 ]] && return 1

    # Split and validate each label
    local IFS='.'
    local labels
    read -ra labels <<< "$value"

    [[ ${#labels[@]} -lt 1 ]] && return 1

    for label in "${labels[@]}"; do
        [[ -z "$label" ]] && return 1
        [[ ${#label} -gt 63 ]] && return 1
        [[ ! "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] && return 1
    done

    return 0
}

# Check if value is a valid IPv4 address
# @pre: none
# @post: returns 0 if valid IPv4, 1 otherwise
# Usage: is::ipv4 "192.168.1.1"
is::ipv4() {
    local value="$1"
    [[ -z "$value" ]] && return 1

    local IFS='.'
    local octets
    read -ra octets <<< "$value"

    [[ ${#octets[@]} -ne 4 ]] && return 1

    for octet in "${octets[@]}"; do
        [[ ! "$octet" =~ ^(0|[1-9][0-9]*)$ ]] && return 1
        (( octet < 0 || octet > 255 )) && return 1
    done

    return 0
}

# Check if value is a boolean
# @pre: none
# @post: returns 0 if boolean (true/false/yes/no/1/0), 1 otherwise
# Usage: is::boolean "true"
is::boolean() {
    local value="${1,,}"  # lowercase
    case "$value" in
        true|false|yes|no|1|0|on|off) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if value is hex string
# @pre: none
# @post: returns 0 if hex string, 1 otherwise
# Usage: is::hex "deadbeef"
is::hex() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" =~ ^[0-9a-fA-F]+$ ]]
}

# Check if value matches regex pattern
# @pre: value and pattern are provided
# @post: returns 0 if matches, 1 otherwise
# Usage: is::matching "value" "^[a-z]+$"
is::matching() {
    local value="$1"
    local pattern="$2"
    [[ -z "$pattern" ]] && return 1
    [[ "$value" =~ $pattern ]]
}

# =============================================================================
# NEGATION CHECKS (is::not::*)
# =============================================================================

# Negate any is:: check
# Usage: is::not::empty "/path"
is::not::file() { ! is::file "$@"; }
is::not::dir() { ! is::dir "$@"; }
is::not::link() { ! is::link "$@"; }
is::not::exists() { ! is::exists "$@"; }
is::not::readable() { ! is::readable "$@"; }
is::not::writable() { ! is::writable "$@"; }
is::not::executable() { ! is::executable "$@"; }
is::not::empty() { ! is::empty "$@"; }
is::not::nonempty() { ! is::nonempty "$@"; }
is::not::owned_by() { ! is::owned_by "$@"; }
is::not::group_owned() { ! is::group_owned "$@"; }
is::not::newer_than() { ! is::newer_than "$@"; }
is::not::older_than() { ! is::older_than "$@"; }
is::not::string() { ! is::string "$@"; }
is::not::integer() { ! is::integer "$@"; }
is::not::float() { ! is::float "$@"; }
is::not::uuid() { ! is::uuid "$@"; }
is::not::email() { ! is::email "$@"; }
is::not::url() { ! is::url "$@"; }
is::not::json() { ! is::json "$@"; }
is::not::semver() { ! is::semver "$@"; }
is::not::boolean() { ! is::boolean "$@"; }
is::not::hex() { ! is::hex "$@"; }
is::not::matching() { ! is::matching "$@"; }

# =============================================================================
# CONDITIONAL CHECKS (when::*)
# =============================================================================

# Conditionally execute when path exists
# @pre: path is non-empty
# @post: returns 0 if exists (to chain with &&), 1 otherwise
# Usage: when::exists "/path" && then::do "command"
when::exists() {
    local path="$1"
    is::exists "$path"
}

# Conditionally execute when path is missing
# @pre: path is non-empty
# @post: returns 0 if missing (to chain with &&), 1 otherwise
# Usage: when::missing "/path" && then::create "content"
when::missing() {
    local path="$1"
    ! is::exists "$path"
}

# Conditionally execute when file
# Usage: when::file "/path" && echo "is file"
when::file() {
    local path="$1"
    is::file "$path"
}

# Conditionally execute when directory
# Usage: when::dir "/path" && echo "is dir"
when::dir() {
    local path="$1"
    is::dir "$path"
}

# Conditionally execute when older than duration
# Usage: when::older_than "/cache" "1h" && then::refresh
when::older_than() {
    local path="$1"
    local duration="$2"
    is::older_than "$path" "$duration"
}

# Conditionally execute when newer than duration
# Usage: when::newer_than "/log" "5m" && echo "recent"
when::newer_than() {
    local path="$1"
    local duration="$2"
    is::newer_than "$path" "$duration"
}

# Conditionally execute when empty
# Usage: when::empty "/file" && echo "empty"
when::empty() {
    local path="$1"
    is::empty "$path"
}

# Conditionally execute when nonempty
# Usage: when::nonempty "/file" && cat "/file"
when::nonempty() {
    local path="$1"
    is::nonempty "$path"
}

# Conditionally execute when readable
# Usage: when::readable "/file" && cat "/file"
when::readable() {
    local path="$1"
    is::readable "$path"
}

# Conditionally execute when writable
# Usage: when::writable "/file" && echo "data" >> "/file"
when::writable() {
    local path="$1"
    is::writable "$path"
}

# =============================================================================
# THEN ACTIONS (then::*)
# =============================================================================

# Execute command
# @pre: called after when:: check
# @post: executes command and returns its exit status
# Usage: when::exists "/config" && then::do "source /config"
then::do() {
    eval "$@"
}

# Create file with content
# @pre: called after when::missing check
# @post: creates file with content
# Usage: when::missing "/config" && then::create "default content"
then::create() {
    local content="$1"
    local path="${FLUENT_THEN_PATH:-}"

    if [[ -n "$path" ]]; then
        printf '%s' "$content" > "$path"
    else
        # When path not set, output content
        printf '%s' "$content"
    fi
}

# Refresh/touch file
# @pre: path exists
# @post: updates file mtime
# Usage: when::older_than "/cache" "1h" && then::refresh "/cache"
then::refresh() {
    local path="$1"
    [[ -n "$path" ]] && touch "$path"
}

# Delete file/directory
# @pre: path exists
# @post: removes path
# Usage: when::older_than "/tmp/cache" "7d" && then::delete "/tmp/cache"
then::delete() {
    local path="$1"
    [[ -n "$path" && -e "$path" ]] && rm -rf "$path"
}

# =============================================================================
# ASSERTION FUNCTIONS (assert::*)
# =============================================================================

# Generic assertion handler
_fluent_assert() {
    local check_func="$1"
    local path="$2"
    local message="${3:-Assertion failed}"
    shift 3

    if ! "$check_func" "$path" "$@"; then
        _fluent_emit_error "$path" "${check_func#is::}" "$message"

        if [[ "$FLUENT_EXIT_ON_FAILURE" == "1" ]]; then
            exit 1
        fi
        return 1
    fi
    return 0
}

# Assert path is a file
# @pre: path is non-empty
# @post: exits 1 on failure (unless --no-exit)
# Usage: assert::file "/path" "File required"
assert::file() {
    local path="$1"
    local message="${2:-File required: $path}"
    _fluent_assert is::file "$path" "$message"
}

# Assert path is a directory
# Usage: assert::dir "/path" "Directory required"
assert::dir() {
    local path="$1"
    local message="${2:-Directory required: $path}"
    _fluent_assert is::dir "$path" "$message"
}

# Assert path exists
# Usage: assert::exists "/path" "Path must exist"
assert::exists() {
    local path="$1"
    local message="${2:-Path must exist: $path}"
    _fluent_assert is::exists "$path" "$message"
}

# Assert path is readable
# Usage: assert::readable "/path"
assert::readable() {
    local path="$1"
    local message="${2:-Path must be readable: $path}"
    _fluent_assert is::readable "$path" "$message"
}

# Assert path is writable
# Usage: assert::writable "/path"
assert::writable() {
    local path="$1"
    local message="${2:-Path must be writable: $path}"
    _fluent_assert is::writable "$path" "$message"
}

# Assert path is executable
# Usage: assert::executable "/path"
assert::executable() {
    local path="$1"
    local message="${2:-Path must be executable: $path}"
    _fluent_assert is::executable "$path" "$message"
}

# Assert file is non-empty
# Usage: assert::nonempty "/path"
assert::nonempty() {
    local path="$1"
    local message="${2:-Path must be non-empty: $path}"
    _fluent_assert is::nonempty "$path" "$message"
}

# Assert file is empty
# Usage: assert::empty "/path"
assert::empty() {
    local path="$1"
    local message="${2:-Path must be empty: $path}"
    _fluent_assert is::empty "$path" "$message"
}

# Assert value is a string
# Usage: assert::string "$var" "Variable must be set"
assert::string() {
    local value="$1"
    local message="${2:-Value must be non-empty string}"
    _fluent_assert is::string "$value" "$message"
}

# Assert value is an integer
# Usage: assert::integer "$port"
assert::integer() {
    local value="$1"
    local message="${2:-Value must be integer: $value}"
    _fluent_assert is::integer "$value" "$message"
}

# Assert value is a float
# Usage: assert::float "$price"
assert::float() {
    local value="$1"
    local message="${2:-Value must be float: $value}"
    _fluent_assert is::float "$value" "$message"
}

# Assert value is valid email
# Usage: assert::email "$email"
assert::email() {
    local value="$1"
    local message="${2:-Value must be valid email: $value}"
    _fluent_assert is::email "$value" "$message"
}

# Assert value is valid URL
# Usage: assert::url "$url"
assert::url() {
    local value="$1"
    local message="${2:-Value must be valid URL: $value}"
    _fluent_assert is::url "$value" "$message"
}

# Assert value is valid JSON
# Usage: assert::json "$data"
assert::json() {
    local value="$1"
    local message="${2:-Value must be valid JSON}"
    _fluent_assert is::json "$value" "$message"
}

# Assert value is valid semver
# Usage: assert::semver "$version"
assert::semver() {
    local value="$1"
    local message="${2:-Value must be valid semver: $value}"
    _fluent_assert is::semver "$value" "$message"
}

# Assert value is valid UUID
# Usage: assert::uuid "$id"
assert::uuid() {
    local value="$1"
    local message="${2:-Value must be valid UUID: $value}"
    _fluent_assert is::uuid "$value" "$message"
}

# =============================================================================
# MULTI-VALUE ASSERTIONS (assert::all, assert::any, assert::none)
# =============================================================================

# Assert all values pass check
# @pre: check_func is valid is:: function, values are provided
# @post: exits 1 if any fails
# Usage: assert::all is::file "/a" "/b" "/c"
assert::all() {
    local check_func="$1"
    shift

    for value in "$@"; do
        if ! "$check_func" "$value"; then
            _fluent_emit_error "$value" "${check_func#is::}" "All check failed"
            if [[ "$FLUENT_EXIT_ON_FAILURE" == "1" ]]; then
                exit 1
            fi
            return 1
        fi
    done
    return 0
}

# Assert any value passes check
# @pre: check_func is valid is:: function, values are provided
# @post: exits 1 if none pass
# Usage: assert::any is::writable "/a" "/b"
assert::any() {
    local check_func="$1"
    shift

    for value in "$@"; do
        if "$check_func" "$value"; then
            return 0
        fi
    done

    _fluent_emit_error "${1:-none}" "${check_func#is::}" "None of the values passed the check"
    if [[ "$FLUENT_EXIT_ON_FAILURE" == "1" ]]; then
        exit 1
    fi
    return 1
}

# Assert none of the values pass check
# @pre: check_func is valid is:: function, values are provided
# @post: exits 1 if any pass
# Usage: assert::none is::empty "/a" "/b"
assert::none() {
    local check_func="$1"
    shift

    for value in "$@"; do
        if "$check_func" "$value"; then
            _fluent_emit_error "$value" "${check_func#is::}" "None check failed - found matching value"
            if [[ "$FLUENT_EXIT_ON_FAILURE" == "1" ]]; then
                exit 1
            fi
            return 1
        fi
    done
    return 0
}

# =============================================================================
# FLUENT CHAIN HELPERS
# =============================================================================

# Check multiple conditions on a path
# @pre: path is non-empty, conditions are valid check names
# @post: returns 0 if all pass, 1 otherwise
# Usage: fluent_check "/path" file readable nonempty
fluent_check() {
    local path="$1"
    shift

    for condition in "$@"; do
        local check_func="is::$condition"
        if ! "$check_func" "$path"; then
            _fluent_debug "fluent_check: $path failed $condition"
            return 1
        fi
    done
    return 0
}

# Run validation pipeline and collect results
# @pre: path is non-empty, checks are valid
# @post: outputs JSON with all check results
# Usage: fluent_validate "/path" file readable nonempty
fluent_validate() {
    local path="$1"
    shift

    local results="["
    local first=true
    local all_passed=true

    for condition in "$@"; do
        local check_func="is::$condition"
        local passed="false"

        if "$check_func" "$path"; then
            passed="true"
        else
            all_passed=false
        fi

        if [[ "$first" == "true" ]]; then
            first=false
        else
            results+=","
        fi
        results+="{\"check\":\"$condition\",\"passed\":$passed}"
    done

    results+="]"

    local escaped_path
    escaped_path=$(_fluent_escape_json "$path")

    if [[ "$all_passed" == "true" ]]; then
        printf '{"success":true,"path":"%s","results":%s}\n' "$escaped_path" "$results"
        return 0
    else
        printf '{"success":false,"path":"%s","results":%s}\n' "$escaped_path" "$results"
        return 1
    fi
}

# Batch validate multiple paths
# @pre: check is valid condition name, paths are provided
# @post: outputs JSON array with results
# Usage: fluent_batch_check file "/a" "/b" "/c"
fluent_batch_check() {
    local condition="$1"
    shift
    local check_func="is::$condition"

    local results="["
    local first=true
    local total=0
    local passed_count=0

    for path in "$@"; do
        local passed="false"
        ((total++))

        if "$check_func" "$path"; then
            passed="true"
            ((passed_count++))
        fi

        local escaped_path
        escaped_path=$(_fluent_escape_json "$path")

        if [[ "$first" == "true" ]]; then
            first=false
        else
            results+=","
        fi
        results+="{\"path\":\"$escaped_path\",\"passed\":$passed}"
    done

    results+="]"

    printf '{"check":"%s","total":%d,"passed":%d,"results":%s}\n' \
        "$condition" "$total" "$passed_count" "$results"

    [[ "$passed_count" -eq "$total" ]]
}

# =============================================================================
# SOFT ASSERTION MODE
# =============================================================================

# Enter soft assertion mode (don't exit on failure)
# Usage: fluent_soft_mode
fluent_soft_mode() {
    FLUENT_EXIT_ON_FAILURE=0
}

# Enter strict assertion mode (exit on failure)
# Usage: fluent_strict_mode
fluent_strict_mode() {
    FLUENT_EXIT_ON_FAILURE=1
}

# Run assertions in soft mode within scope
# Usage: fluent_with_soft_mode 'assert::file "/a"; assert::file "/b"'
fluent_with_soft_mode() {
    local code="$1"
    local old_mode="$FLUENT_EXIT_ON_FAILURE"
    FLUENT_EXIT_ON_FAILURE=0
    eval "$code"
    local result=$?
    FLUENT_EXIT_ON_FAILURE="$old_mode"
    return $result
}

# =============================================================================
# JSON OUTPUT MODE
# =============================================================================

# Enable JSON error output
# Usage: fluent_json_mode
fluent_json_mode() {
    FLUENT_OUTPUT_FORMAT=json
}

# Enable plain text error output
# Usage: fluent_plain_mode
fluent_plain_mode() {
    FLUENT_OUTPUT_FORMAT=plain
}

# =============================================================================
# COMPOUND CHECKS
# =============================================================================

# Check if path is a readable file
# Usage: is::readable_file "/path"
is::readable_file() {
    local path="$1"
    is::file "$path" && is::readable "$path"
}

# Check if path is a writable file
# Usage: is::writable_file "/path"
is::writable_file() {
    local path="$1"
    is::file "$path" && is::writable "$path"
}

# Check if path is an executable file
# Usage: is::executable_file "/path"
is::executable_file() {
    local path="$1"
    is::file "$path" && is::executable "$path"
}

# Check if path is a readable directory
# Usage: is::readable_dir "/path"
is::readable_dir() {
    local path="$1"
    is::dir "$path" && is::readable "$path"
}

# Check if path is a writable directory
# Usage: is::writable_dir "/path"
is::writable_dir() {
    local path="$1"
    is::dir "$path" && is::writable "$path"
}

# Check if path is valid config file (exists, file, readable, non-empty)
# Usage: is::config_file "/etc/app.conf"
is::config_file() {
    local path="$1"
    is::file "$path" && is::readable "$path" && is::nonempty "$path"
}

# Check if path is valid log directory (exists, dir, writable)
# Usage: is::log_dir "/var/log/app"
is::log_dir() {
    local path="$1"
    is::dir "$path" && is::writable "$path"
}

# =============================================================================
# SIZE CHECKS
# =============================================================================

# Check if file size is less than limit (in bytes, or with suffix)
# @pre: path exists, size is valid (e.g., "1024", "1K", "1M", "1G")
# @post: returns 0 if smaller, 1 otherwise
# Usage: is::smaller_than "/path" "10M"
is::smaller_than() {
    local path="$1"
    local limit="$2"
    [[ -z "$path" || -z "$limit" ]] && return 1
    [[ ! -f "$path" ]] && return 1

    local limit_bytes
    limit_bytes=$(_fluent_parse_size "$limit")

    local size
    size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null)

    [[ "$size" -lt "$limit_bytes" ]]
}

# Check if file size is greater than limit
# Usage: is::larger_than "/path" "1K"
is::larger_than() {
    local path="$1"
    local limit="$2"
    [[ -z "$path" || -z "$limit" ]] && return 1
    [[ ! -f "$path" ]] && return 1

    local limit_bytes
    limit_bytes=$(_fluent_parse_size "$limit")

    local size
    size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null)

    [[ "$size" -gt "$limit_bytes" ]]
}

# Parse size string to bytes
_fluent_parse_size() {
    local size="$1"
    local value="${size%[KMGTkmgt]*}"
    local suffix="${size#"$value"}"

    [[ -z "$value" ]] && value=0

    case "${suffix^^}" in
        K|KB) echo $(( value * 1024 )) ;;
        M|MB) echo $(( value * 1024 * 1024 )) ;;
        G|GB) echo $(( value * 1024 * 1024 * 1024 )) ;;
        T|TB) echo $(( value * 1024 * 1024 * 1024 * 1024 )) ;;
        *) echo "$value" ;;
    esac
}

# =============================================================================
# PERMISSION CHECKS
# =============================================================================

# Check if file has specific permission mode
# @pre: path exists, mode is octal (e.g., "644", "755")
# @post: returns 0 if matches, 1 otherwise
# Usage: is::mode "/path" "644"
is::mode() {
    local path="$1"
    local expected_mode="$2"
    [[ -z "$path" || -z "$expected_mode" ]] && return 1
    [[ ! -e "$path" ]] && return 1

    local actual_mode
    actual_mode=$(stat -c %a "$path" 2>/dev/null || stat -f %Lp "$path" 2>/dev/null)

    [[ "$actual_mode" == "$expected_mode" ]]
}

# Check if file has SUID bit set
# Usage: is::suid "/path"
is::suid() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -u "$path" ]]
}

# Check if file has SGID bit set
# Usage: is::sgid "/path"
is::sgid() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -g "$path" ]]
}

# Check if file has sticky bit set
# Usage: is::sticky "/path"
is::sticky() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -k "$path" ]]
}

# =============================================================================
# CONTENT CHECKS
# =============================================================================

# Check if file contains pattern
# @pre: path is readable file, pattern is non-empty
# @post: returns 0 if contains pattern, 1 otherwise
# Usage: is::containing "/path" "pattern"
is::containing() {
    local path="$1"
    local pattern="$2"
    [[ -z "$path" || -z "$pattern" ]] && return 1
    [[ ! -r "$path" ]] && return 1

    grep -q "$pattern" "$path" 2>/dev/null
}

# Check if file starts with pattern
# Usage: is::starting_with "/path" "#!"
is::starting_with() {
    local path="$1"
    local pattern="$2"
    [[ -z "$path" || -z "$pattern" ]] && return 1
    [[ ! -r "$path" ]] && return 1

    local first_line
    first_line=$(head -n1 "$path" 2>/dev/null)
    [[ "$first_line" == "$pattern"* ]]
}

# Check if file has specific extension
# Usage: is::extension "/path/file.txt" "txt"
is::extension() {
    local path="$1"
    local ext="$2"
    [[ -z "$path" || -z "$ext" ]] && return 1

    [[ "${path##*.}" == "$ext" ]]
}

# Check if file is a bash script (has bash shebang)
# Usage: is::bash_script "/path"
is::bash_script() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ ! -r "$path" ]] && return 1

    local first_line
    first_line=$(head -n1 "$path" 2>/dev/null)
    [[ "$first_line" == "#!/"*"bash"* || "$first_line" == "#!/usr/bin/env bash" ]]
}

# =============================================================================
# COMPARISON CHECKS
# =============================================================================

# Check if file is same as another (by content hash)
# Usage: is::same_as "/path1" "/path2"
is::same_as() {
    local path1="$1"
    local path2="$2"
    [[ -z "$path1" || -z "$path2" ]] && return 1
    [[ ! -f "$path1" || ! -f "$path2" ]] && return 1

    local hash1 hash2
    hash1=$(sha256sum "$path1" 2>/dev/null | cut -d' ' -f1)
    hash2=$(sha256sum "$path2" 2>/dev/null | cut -d' ' -f1)

    [[ -n "$hash1" && "$hash1" == "$hash2" ]]
}

# Check if file is different from another
# Usage: is::different_from "/path1" "/path2"
is::different_from() {
    local path1="$1"
    local path2="$2"
    ! is::same_as "$path1" "$path2"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# List all available is:: checks
# Usage: fluent_list_checks
fluent_list_checks() {
    compgen -A function | grep '^is::' | grep -v '^is::not::' | sort
}

# List all available assert:: functions
# Usage: fluent_list_assertions
fluent_list_assertions() {
    compgen -A function | grep '^assert::' | sort
}

# List all available when:: functions
# Usage: fluent_list_conditions
fluent_list_conditions() {
    compgen -A function | grep '^when::' | sort
}

# Get fluent module version
# Usage: fluent_version
fluent_version() {
    printf '1.0.0\n'
}

# Show fluent module status
# Usage: fluent_status
fluent_status() {
    local check_count when_count assert_count
    check_count=$(fluent_list_checks | wc -l)
    when_count=$(fluent_list_conditions | wc -l)
    assert_count=$(fluent_list_assertions | wc -l)

    printf '{"version":"1.0.0","checks":%d,"conditions":%d,"assertions":%d,"exit_on_failure":%s,"output_format":"%s"}\n' \
        "$check_count" "$when_count" "$assert_count" \
        "$FLUENT_EXIT_ON_FAILURE" "$FLUENT_OUTPUT_FORMAT"
}

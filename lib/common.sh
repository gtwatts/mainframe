#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/common.sh - Core shared library for MAINFRAME toolkit
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
# Version: 1.0.0
# License: MIT
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_COMMON_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COMMON_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly MAINFRAME_VERSION="1.0.0"
readonly MAINFRAME_NAME="mainframe"

# Aliases for backward compatibility
readonly BASHER_VERSION="$MAINFRAME_VERSION"
readonly BASHER_NAME="$MAINFRAME_NAME"

# Exit codes (following BSD conventions)
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_USAGE=64        # Command line usage error
readonly EXIT_DATAERR=65      # Data format error
readonly EXIT_NOINPUT=66      # Cannot open input
readonly EXIT_NOUSER=67       # Addressee unknown
readonly EXIT_NOHOST=68       # Host name unknown
readonly EXIT_UNAVAILABLE=69  # Service unavailable
readonly EXIT_SOFTWARE=70     # Internal software error
readonly EXIT_OSERR=71        # System error
readonly EXIT_OSFILE=72       # Critical OS file missing
readonly EXIT_CANTCREAT=73    # Can't create output file
readonly EXIT_IOERR=74        # Input/output error
readonly EXIT_TEMPFAIL=75     # Temp failure; retry later
readonly EXIT_PROTOCOL=76     # Remote protocol error
readonly EXIT_NOPERM=77       # Permission denied
readonly EXIT_CONFIG=78       # Configuration error

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================

# Check if colors should be enabled
_basher_colors_enabled() {
    [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

if _basher_colors_enabled; then
    readonly CLR_RESET='\033[0m'
    readonly CLR_BOLD='\033[1m'
    readonly CLR_DIM='\033[2m'
    readonly CLR_ITALIC='\033[3m'
    readonly CLR_UNDERLINE='\033[4m'

    # Foreground colors
    readonly CLR_BLACK='\033[30m'
    readonly CLR_RED='\033[31m'
    readonly CLR_GREEN='\033[32m'
    readonly CLR_YELLOW='\033[33m'
    readonly CLR_BLUE='\033[34m'
    readonly CLR_MAGENTA='\033[35m'
    readonly CLR_CYAN='\033[36m'
    readonly CLR_WHITE='\033[37m'

    # Bright foreground colors
    readonly CLR_BRIGHT_RED='\033[91m'
    readonly CLR_BRIGHT_GREEN='\033[92m'
    readonly CLR_BRIGHT_YELLOW='\033[93m'
    readonly CLR_BRIGHT_BLUE='\033[94m'
    readonly CLR_BRIGHT_MAGENTA='\033[95m'
    readonly CLR_BRIGHT_CYAN='\033[96m'

    # Background colors
    readonly CLR_BG_RED='\033[41m'
    readonly CLR_BG_GREEN='\033[42m'
    readonly CLR_BG_YELLOW='\033[43m'
    readonly CLR_BG_BLUE='\033[44m'
else
    readonly CLR_RESET=''
    readonly CLR_BOLD=''
    readonly CLR_DIM=''
    readonly CLR_ITALIC=''
    readonly CLR_UNDERLINE=''
    readonly CLR_BLACK=''
    readonly CLR_RED=''
    readonly CLR_GREEN=''
    readonly CLR_YELLOW=''
    readonly CLR_BLUE=''
    readonly CLR_MAGENTA=''
    readonly CLR_CYAN=''
    readonly CLR_WHITE=''
    readonly CLR_BRIGHT_RED=''
    readonly CLR_BRIGHT_GREEN=''
    readonly CLR_BRIGHT_YELLOW=''
    readonly CLR_BRIGHT_BLUE=''
    readonly CLR_BRIGHT_MAGENTA=''
    readonly CLR_BRIGHT_CYAN=''
    readonly CLR_BG_RED=''
    readonly CLR_BG_GREEN=''
    readonly CLR_BG_YELLOW=''
    readonly CLR_BG_BLUE=''
fi

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Log levels (following syslog conventions)
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Current log level (can be overridden by BASHER_LOG_LEVEL env var)
BASHER_LOG_LEVEL="${BASHER_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Log file (optional, set BASHER_LOG_FILE to enable file logging)
BASHER_LOG_FILE="${BASHER_LOG_FILE:-}"

# Internal logging function
_log() {
    local level="$1"
    local level_name="$2"
    local color="$3"
    local message="$4"
    local timestamp

    # Check if we should log at this level
    [[ "$level" -lt "$BASHER_LOG_LEVEL" ]] && return 0

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Format: [TIMESTAMP] [LEVEL] message
    local formatted_msg="[${timestamp}] [${level_name}] ${message}"

    # Output to stderr with color
    printf "%b[%s] [%b%s%b] %s%b\n" \
        "$CLR_DIM" "$timestamp" "$color" "$level_name" "$CLR_RESET$CLR_DIM" "$message" "$CLR_RESET" >&2

    # Optionally write to log file (without colors)
    if [[ -n "$BASHER_LOG_FILE" ]]; then
        printf "[%s] [%s] %s\n" "$timestamp" "$level_name" "$message" >> "$BASHER_LOG_FILE"
    fi
}

# Public logging functions
log_debug() { _log "$LOG_LEVEL_DEBUG" "DEBUG" "$CLR_CYAN" "$*"; }
log_info()  { _log "$LOG_LEVEL_INFO"  "INFO " "$CLR_GREEN" "$*"; }
log_warn()  { _log "$LOG_LEVEL_WARN"  "WARN " "$CLR_YELLOW" "$*"; }
log_error() { _log "$LOG_LEVEL_ERROR" "ERROR" "$CLR_RED" "$*"; }
log_fatal() { _log "$LOG_LEVEL_FATAL" "FATAL" "$CLR_BRIGHT_RED$CLR_BOLD" "$*"; }

# Convenience aliases
debug() { log_debug "$@"; }
info()  { log_info "$@"; }
warn()  { log_warn "$@"; }
error() { log_error "$@"; }

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Die with error message and exit code
die() {
    local exit_code="${1:-$EXIT_FAILURE}"
    shift
    log_fatal "$*"
    exit "$exit_code"
}

# Die with usage error
die_usage() {
    log_error "$*"
    [[ -n "${USAGE:-}" ]] && printf "\n%s\n" "$USAGE" >&2
    exit "$EXIT_USAGE"
}

# Assert condition or die
# Usage: assert "test -f file" "message"
# Usage: assert test -f "$file"  (preferred: pass command as separate args)
assert() {
    if [[ $# -eq 0 ]]; then
        die "$EXIT_SOFTWARE" "assert: no condition provided"
    fi

    local message="Assertion failed"

    # Two-arg legacy form: assert "condition string" "message"
    if [[ $# -eq 2 && "$1" == *" "* ]]; then
        message="$2"
        local -a _cond_parts
        read -ra _cond_parts <<< "$1"
        if ! "${_cond_parts[@]}" 2>/dev/null; then
            die "$EXIT_SOFTWARE" "$message"
        fi
        return
    fi

    # Multi-arg form: assert cmd arg1 arg2...
    if ! "$@" 2>/dev/null; then
        die "$EXIT_SOFTWARE" "$message"
    fi
}

# Trap handler for cleanup (eval-free for safety)
_mainframe_cleanup_files=()
_mainframe_cleanup_dirs=()
_mainframe_cleanup_funcs=()

# Register a cleanup function (called by name, no eval)
# Usage: on_exit my_cleanup_function
on_exit() {
    _mainframe_cleanup_funcs+=("$1")
}

# Execute all cleanup handlers safely
_mainframe_run_cleanup() {
    local exit_code=$?
    # Remove tracked temp files
    local f
    for f in "${_mainframe_cleanup_files[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
    # Remove tracked temp dirs
    for f in "${_mainframe_cleanup_dirs[@]}"; do
        rm -rf "$f" 2>/dev/null || true
    done
    # Call registered cleanup functions by name (no eval)
    local func
    for func in "${_mainframe_cleanup_funcs[@]}"; do
        "$func" 2>/dev/null || true
    done
    exit $exit_code
}

# Set up trap (only if not already set)
if [[ -z "${_MAINFRAME_TRAP_SET:-}" ]]; then
    trap _mainframe_run_cleanup EXIT
    readonly _MAINFRAME_TRAP_SET=1
fi

# =============================================================================
# OUTPUT FORMATTING
# =============================================================================

# Print a header
header() {
    local text="$1"
    local width="${2:-60}"
    local line
    line=$(printf '%*s' "$width" '' | tr ' ' '=')

    printf "\n%b%s%b\n" "$CLR_BOLD$CLR_BLUE" "$line" "$CLR_RESET"
    printf "%b%s%b\n" "$CLR_BOLD" "$text" "$CLR_RESET"
    printf "%b%s%b\n\n" "$CLR_BOLD$CLR_BLUE" "$line" "$CLR_RESET"
}

# Print a subheader
subheader() {
    local text="$1"
    printf "\n%b>>> %s%b\n\n" "$CLR_CYAN$CLR_BOLD" "$text" "$CLR_RESET"
}

# Print success message
success() {
    printf "%b[OK]%b %s\n" "$CLR_GREEN$CLR_BOLD" "$CLR_RESET" "$*"
}

# Print failure message
failure() {
    printf "%b[FAIL]%b %s\n" "$CLR_RED$CLR_BOLD" "$CLR_RESET" "$*" >&2
}

# Print a spinner while a command runs
spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%b%s%b %s" "$CLR_CYAN" "${spin_chars:i++%10:1}" "$CLR_RESET" "$message"
        sleep 0.1
    done
    printf "\r%*s\r" $((${#message} + 3)) ""
}

# Progress bar (provided by pure-util.sh core tier)

# Print table row
table_row() {
    local format="$1"
    shift
    printf "$format\n" "$@"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Require a command to exist
require_command() {
    local cmd="$1"
    local pkg="${2:-$cmd}"

    if ! command_exists "$cmd"; then
        die "$EXIT_UNAVAILABLE" "Required command '$cmd' not found. Install with: $pkg"
    fi
}

# Require multiple commands
require_commands() {
    for cmd in "$@"; do
        require_command "$cmd"
    done
}

# Check if file exists and is readable
require_file() {
    local file="$1"
    local description="${2:-File}"

    [[ -f "$file" ]] || die "$EXIT_NOINPUT" "$description not found: $file"
    [[ -r "$file" ]] || die "$EXIT_NOPERM" "$description not readable: $file"
}

# Check if directory exists
require_dir() {
    local dir="$1"
    local description="${2:-Directory}"

    [[ -d "$dir" ]] || die "$EXIT_NOINPUT" "$description not found: $dir"
}

# Validate JSON
is_valid_json() {
    local input="$1"

    if [[ -f "$input" ]]; then
        jq empty "$input" 2>/dev/null
    else
        jq empty <<< "$input" 2>/dev/null
    fi
}

# Validate email format
is_valid_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Validate URL format
is_valid_url() {
    local url="$1"
    [[ "$url" =~ ^https?:// ]]
}

# =============================================================================
# STRING UTILITIES
# =============================================================================

# Backward-compatible wrappers (canonical implementations in pure-string.sh)
trim() { trim_string "$@"; }
lowercase() { to_lower "$1"; }
uppercase() { to_upper "$1"; }

# contains, starts_with, ends_with, random_string provided by core tier libs

# array_contains, array_join provided by pure-array.sh core tier

# =============================================================================
# FILE UTILITIES
# =============================================================================

# Create temporary file with automatic cleanup
temp_file() {
    local prefix="${1:-mainframe}"
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    _mainframe_cleanup_files+=("$tmpfile")
    printf '%s' "$tmpfile"
}

# Create temporary directory with automatic cleanup
temp_dir() {
    local prefix="${1:-mainframe}"
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    _mainframe_cleanup_dirs+=("$tmpdir")
    printf '%s' "$tmpdir"
}

# Get absolute path
abs_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir file
        dir=$(dirname "$path")
        file=$(basename "$path")
        (cd "$dir" && printf '%s/%s' "$(pwd)" "$file")
    else
        printf '%s' "$path"
    fi
}

# Get file extension
file_ext() {
    local file="$1"
    local ext="${file##*.}"
    [[ "$ext" != "$file" ]] && printf '%s' "$ext"
}

# Get filename without extension
file_name() {
    local file="$1"
    local name
    name=$(basename "$file")
    printf '%s' "${name%.*}"
}

# =============================================================================
# CONFIRMATION AND INPUT
# =============================================================================

# Ask yes/no question
confirm() {
    local question="${1:-Continue?}"
    local default="${2:-n}"
    local prompt response

    if [[ "$default" =~ ^[Yy] ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    printf "%b%s %s%b " "$CLR_YELLOW" "$question" "$prompt" "$CLR_RESET"
    read -r response

    response="${response:-$default}"
    [[ "$response" =~ ^[Yy] ]]
}

# Ask for input with default
ask() {
    local prompt="$1"
    local default="${2:-}"
    local response

    if [[ -n "$default" ]]; then
        printf "%b%s [%s]:%b " "$CLR_CYAN" "$prompt" "$default" "$CLR_RESET"
    else
        printf "%b%s:%b " "$CLR_CYAN" "$prompt" "$CLR_RESET"
    fi

    read -r response
    printf '%s' "${response:-$default}"
}

# Ask for password (no echo)
ask_password() {
    local prompt="${1:-Password}"
    local password

    printf "%b%s:%b " "$CLR_CYAN" "$prompt" "$CLR_RESET"
    read -rs password
    printf '\n'
    printf '%s' "$password"
}

# =============================================================================
# VERSION COMPARISON
# =============================================================================

# Compare semantic versions
# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
version_compare() {
    local v1="$1"
    local v2="$2"

    [[ "$v1" == "$v2" ]] && return 0

    local IFS='.'
    local i v1_parts=($v1) v2_parts=($v2)

    for ((i=0; i<${#v1_parts[@]} || i<${#v2_parts[@]}; i++)); do
        local n1="${v1_parts[i]:-0}"
        local n2="${v2_parts[i]:-0}"

        ((n1 > n2)) && return 1
        ((n1 < n2)) && return 2
    done

    return 0
}

# Check if version is at least minimum
version_at_least() {
    local version="$1"
    local minimum="$2"

    version_compare "$version" "$minimum"
    [[ $? -ne 2 ]]
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize basher environment
basher_init() {
    # Set strict mode
    set -euo pipefail

    # Determine script directory
    BASHER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    BASHER_ROOT="$(cd "$BASHER_SCRIPT_DIR/.." && pwd)"

    # Export for child scripts
    export BASHER_SCRIPT_DIR BASHER_ROOT

    log_debug "Basher initialized: version=$BASHER_VERSION, root=$BASHER_ROOT"
}

# =============================================================================
# PURE BASH LIBRARIES
# =============================================================================

# Auto-source pure bash libraries if available
_MAINFRAME_LIB_DIR="${BASH_SOURCE[0]%/*}"

# =============================================================================
# LAZY LOADING ENGINE
# =============================================================================
# Controls which libraries are loaded via MAINFRAME_LIBS or MAINFRAME_PROFILE.
# When neither is set, all libraries load (backward compatible).
#
# Usage:
#   MAINFRAME_LIBS='json,validation,git' source common.sh  # specific libs
#   MAINFRAME_LIBS='core+standard' source common.sh        # tier loading
#   MAINFRAME_LIBS='all' source common.sh                  # everything
#   MAINFRAME_PROFILE='minimal' source common.sh           # preset profile
#
# Profiles: minimal, standard, full, ai
# =============================================================================

# --- Tier Definitions --------------------------------------------------------

# Core tier: always loaded regardless of MAINFRAME_LIBS setting
_MAINFRAME_TIER_CORE=(
    pure-string pure-array pure-util pure-file
    json ansi
    output errors hints
)

# Standard tier: common day-to-day libraries
_MAINFRAME_TIER_STANDARD=(
    validation path env datetime http csv
    git docker crypto proc args config
    log error tui template ci health
    device sysinfo service retry
    toml yaml
)

# Extended tier: advanced/specialized libraries
_MAINFRAME_TIER_EXTENDED=(
    k8s semver functional stream pipe
    procsub async meta cli fzf
    compat safe guard
)

# Phase 3 AI tier: agent-optimized modules
_MAINFRAME_TIER_AI=(
    idempotent atomic observe project
    contract perf netscan parsers trace
    risk dryrun undo
    limits confirm safewrap safecontext
    agent workflow taskstate
    context diff parse_output symbols agent_exec
)

# --- Profile Presets ---------------------------------------------------------

# Resolve MAINFRAME_PROFILE to MAINFRAME_LIBS if profile is set
if [[ -n "${MAINFRAME_PROFILE:-}" && -z "${MAINFRAME_LIBS:-}" ]]; then
    case "${MAINFRAME_PROFILE}" in
        minimal)  MAINFRAME_LIBS="core" ;;
        standard) MAINFRAME_LIBS="core+standard" ;;
        full)     MAINFRAME_LIBS="all" ;;
        ai)       MAINFRAME_LIBS="core+ai" ;;
        *)
            log_warn "Unknown MAINFRAME_PROFILE '${MAINFRAME_PROFILE}', loading all"
            MAINFRAME_LIBS="all"
            ;;
    esac
fi

# --- Loader Functions --------------------------------------------------------

# Track which libraries have been loaded to prevent double-sourcing
declare -gA _MAINFRAME_LOADED_LIBS 2>/dev/null || declare -A _MAINFRAME_LOADED_LIBS

# Initialize lazy loading state
# Called automatically during sourcing, but can be called again safely
# Usage: _mainframe_lazy_init
_mainframe_lazy_init() {
    # Ensure associative array exists (idempotent)
    if ! declare -p _MAINFRAME_LOADED_LIBS &>/dev/null 2>&1; then
        declare -gA _MAINFRAME_LOADED_LIBS 2>/dev/null || declare -A _MAINFRAME_LOADED_LIBS
    fi
}

# Load a single library by name (without .sh extension)
# Usage: _mainframe_load_library "json"
# Returns: 0 on success, 1 on failure (invalid name or file not found)
_mainframe_load_library() {
    local lib_name="$1"

    # Reject empty or whitespace-only names
    [[ -z "${lib_name// /}" ]] && return 1

    # Sanitize: only allow alphanumeric, underscore, hyphen (prevent path traversal)
    [[ "$lib_name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1

    local lib_file="${_MAINFRAME_LIB_DIR}/${lib_name}.sh"

    # Skip if already loaded
    [[ -n "${_MAINFRAME_LOADED_LIBS[${lib_name}]:-}" ]] && return 0

    # Source if file exists, otherwise return failure
    if [[ -f "$lib_file" ]]; then
        source "$lib_file"
        _MAINFRAME_LOADED_LIBS["${lib_name}"]=1
        return 0
    fi

    return 1
}

# Load all libraries in a named tier
# Usage: _mainframe_load_tier "core"
_mainframe_load_tier() {
    local tier_name="$1"
    local tier_var="_MAINFRAME_TIER_${tier_name^^}[@]"
    local lib

    for lib in "${!tier_var}"; do
        _mainframe_load_library "$lib"
    done
}

# Parse MAINFRAME_LIBS value and load requested libraries
# Supports: comma-separated names, tier names with +, 'all'
_mainframe_load_selected() {
    local libs_spec="$1"

    # Always load core tier first
    _mainframe_load_tier "core"

    # Handle 'all' keyword
    if [[ "$libs_spec" == "all" ]]; then
        _mainframe_load_tier "standard"
        _mainframe_load_tier "extended"
        _mainframe_load_tier "ai"
        return
    fi

    # Handle single tier name (e.g., 'core', 'standard', 'ai')
    case "$libs_spec" in
        core)     return ;;  # Already loaded core tier above
        standard) _mainframe_load_tier "standard"; return ;;
        extended) _mainframe_load_tier "extended"; return ;;
        ai)       _mainframe_load_tier "ai"; return ;;
    esac

    # Handle tier expressions (e.g., 'core+standard+ai')
    if [[ "$libs_spec" == *"+"* ]]; then
        local IFS='+'
        local tier
        for tier in $libs_spec; do
            case "$tier" in
                core)     ;; # Already loaded
                standard) _mainframe_load_tier "standard" ;;
                extended) _mainframe_load_tier "extended" ;;
                ai)       _mainframe_load_tier "ai" ;;
                *)        log_warn "Unknown tier: $tier" ;;
            esac
        done
        return
    fi

    # Handle comma-separated library names (e.g., 'json,validation,git')
    local IFS=','
    local lib
    for lib in $libs_spec; do
        # Trim whitespace
        lib="${lib#"${lib%%[![:space:]]*}"}"
        lib="${lib%"${lib##*[![:space:]]}"}"
        [[ -n "$lib" ]] && _mainframe_load_library "$lib"
    done
}

# --- Load Decision -----------------------------------------------------------

if [[ -n "${MAINFRAME_LIBS:-}" ]]; then
    # Selective loading: use lazy loading engine
    _mainframe_load_selected "${MAINFRAME_LIBS}"
else
    # Full loading: backward-compatible, source everything
    # Uses _mainframe_load_library to track what's loaded

    # Core tier libraries
    _mainframe_load_library "pure-string"
    _mainframe_load_library "pure-array"
    _mainframe_load_library "pure-util"
    _mainframe_load_library "pure-file"
    _mainframe_load_library "json"
    _mainframe_load_library "output"
    _mainframe_load_library "errors"
    _mainframe_load_library "ansi"
    _mainframe_load_library "hints"

    # Standard tier libraries
    _mainframe_load_library "validation"
    _mainframe_load_library "path"
    _mainframe_load_library "env"
    _mainframe_load_library "datetime"
    _mainframe_load_library "http"
    _mainframe_load_library "csv"
    _mainframe_load_library "git"
    _mainframe_load_library "docker"
    _mainframe_load_library "crypto"
    _mainframe_load_library "proc"
    _mainframe_load_library "args"
    _mainframe_load_library "config"
    _mainframe_load_library "log"
    _mainframe_load_library "error"
    _mainframe_load_library "tui"
    _mainframe_load_library "template"
    _mainframe_load_library "ci"
    _mainframe_load_library "health"
    _mainframe_load_library "device"
    _mainframe_load_library "sysinfo"
    _mainframe_load_library "service"
    _mainframe_load_library "retry"
    _mainframe_load_library "toml"
    _mainframe_load_library "yaml"

    # Extended tier libraries
    _mainframe_load_library "k8s"
    _mainframe_load_library "semver"
    _mainframe_load_library "functional"
    _mainframe_load_library "stream"
    _mainframe_load_library "pipe"
    _mainframe_load_library "procsub"
    _mainframe_load_library "async"
    _mainframe_load_library "meta"
    _mainframe_load_library "cli"
    _mainframe_load_library "fzf"
    _mainframe_load_library "compat"
    _mainframe_load_library "safe"
    _mainframe_load_library "guard"

    # AI tier libraries
    _mainframe_load_library "idempotent"
    _mainframe_load_library "atomic"
    _mainframe_load_library "observe"
    _mainframe_load_library "project"
    _mainframe_load_library "contract"
    _mainframe_load_library "perf"
    _mainframe_load_library "netscan"
    _mainframe_load_library "parsers"
    _mainframe_load_library "trace"
    _mainframe_load_library "cache"
    _mainframe_load_library "scope"
    _mainframe_load_library "risk"
    _mainframe_load_library "dryrun"
    _mainframe_load_library "undo"
    _mainframe_load_library "limits"
    _mainframe_load_library "confirm"
    _mainframe_load_library "safewrap"
    _mainframe_load_library "safecontext"
    _mainframe_load_library "agent"
    _mainframe_load_library "workflow"
    _mainframe_load_library "taskstate"
    _mainframe_load_library "context"
    _mainframe_load_library "diff"
    _mainframe_load_library "parse_output"
    _mainframe_load_library "symbols"
    _mainframe_load_library "agent_exec"

fi # End of full loading (backward-compatible path)

# =============================================================================
# PUBLIC API - Lazy Loading
# =============================================================================

# Load a specific library by name (public interface)
# Usage: mainframe_load "git"
# Returns: 0 on success, 1 on failure
mainframe_load() {
    local lib_name="$1"
    _mainframe_load_library "$lib_name"
}

# Load all available libraries (equivalent to MAINFRAME_LIBS='all')
# Usage: mainframe_load_all
mainframe_load_all() {
    _mainframe_load_tier "core"
    _mainframe_load_tier "standard"
    _mainframe_load_tier "extended"
    _mainframe_load_tier "ai"

    # Also load any .sh files in lib dir that aren't in tiers
    local lib_file lib_name
    for lib_file in "${_MAINFRAME_LIB_DIR}"/*.sh; do
        [[ -f "$lib_file" ]] || continue
        lib_name="${lib_file##*/}"
        lib_name="${lib_name%.sh}"
        # Skip common.sh itself
        [[ "$lib_name" == "common" ]] && continue
        _mainframe_load_library "$lib_name"
    done
}

# List all currently loaded libraries (one per line)
# Usage: mainframe_loaded
mainframe_loaded() {
    local lib
    for lib in "${!_MAINFRAME_LOADED_LIBS[@]}"; do
        printf '%s\n' "$lib"
    done | sort
}

# List all available libraries in the lib directory (one per line)
# Usage: mainframe_available
mainframe_available() {
    local lib_file lib_name
    for lib_file in "${_MAINFRAME_LIB_DIR}"/*.sh; do
        [[ -f "$lib_file" ]] || continue
        lib_name="${lib_file##*/}"
        lib_name="${lib_name%.sh}"
        # Skip common.sh itself
        [[ "$lib_name" == "common" ]] && continue
        printf '%s\n' "$lib_name"
    done | sort
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of all public functions (for documentation)
BASHER_COMMON_EXPORTS=(
    # Lazy Loading API
    mainframe_load mainframe_load_all mainframe_loaded mainframe_available
    _mainframe_lazy_init
    # Logging
    log_debug log_info log_warn log_error log_fatal
    debug info warn error
    # Error handling
    die die_usage assert on_exit
    # Output
    header subheader success failure spinner progress_bar table_row
    # Validation
    command_exists require_command require_commands require_file require_dir
    is_valid_json is_valid_email is_valid_url
    # Strings
    trim lowercase uppercase contains starts_with ends_with random_string
    # Arrays
    array_contains array_join
    # Files
    temp_file temp_dir abs_path file_ext file_name
    # Input
    confirm ask ask_password
    # Version
    version_compare version_at_least
    # Init
    basher_init
    # Git (from git.sh)
    git_is_repo git_root git_branch git_branches git_remote_branches git_default_branch
    git_is_dirty git_is_clean git_has_staged git_has_unstaged git_has_untracked
    git_status_short git_files_changed
    git_commit_hash git_commit_hash_full git_commit_message git_commit_author
    git_commit_date git_commit_count git_commits_ahead git_commits_behind
    git_tag_latest git_tags git_tag_exists git_describe
    git_remote_url git_remote_name git_has_remote git_is_pushed
    git_user_name git_user_email git_ignore_check git_file_history git_blame_line
    git_diff_files git_diff_stat git_merge_base
    git_summary git_log_oneline git_changed_since
    # Date/Time (from datetime.sh)
    now now_ms now_iso now_rfc2822
    parse_iso parse_date parse_datetime
    format_epoch format_iso format_date format_time format_datetime format_relative
    date_add date_subtract date_diff date_diff_human
    year month day hour minute second day_of_week day_of_year week_of_year is_leap_year
    is_before is_after is_same_day is_weekend is_weekday
    start_of_day end_of_day start_of_month end_of_month start_of_year end_of_year
    days_in_month make_datetime tz_offset tz_name is_dst
    # Process Management (from proc.sh)
    proc_exists proc_name proc_cmd proc_parent proc_children proc_tree
    proc_user proc_start_time proc_runtime
    proc_memory proc_memory_percent proc_cpu proc_threads proc_open_files
    proc_find_by_name proc_find_by_port proc_find_by_user proc_find_by_cmd
    pidfile_create pidfile_read pidfile_check pidfile_remove pidfile_kill
    lockfile_acquire lockfile_release lockfile_check with_lock
    proc_signal proc_kill proc_kill_force proc_kill_tree
    proc_wait proc_wait_timeout proc_wait_start
    proc_count proc_load proc_uptime proc_uptime_human
    # Path Manipulation (from path.sh)
    path_normalize path_absolute path_relative
    path_dir path_base path_ext path_ext_full path_stem path_stem_full
    path_join path_replace_ext path_add_suffix
    path_to_unix path_to_windows path_style
    path_quote path_is_safe path_ensure_dir path_sanitize
    path_expand_tilde path_common_prefix
    path_is_absolute path_is_relative path_has_parent_ref path_is_hidden
    path_equals path_depth path_split
    path_unique path_resolve
    # Validation (from validation.sh)
    validate_int validate_float validate_bool validate_uuid validate_hex
    validate_email validate_url validate_domain validate_ipv4 validate_ipv6
    validate_date validate_time validate_semver
    validate_path validate_path_safe validate_filename validate_path_chars
    sanitize_shell_arg sanitize_filename sanitize_sql sanitize_html sanitize_json
    validate_regex validate_length validate_enum validate_all
    validate_command_safe build_safe_command
    validate_port validate_mac validate_credit_card validate_phone
    validate_json validate_alnum validate_slug validate_cidr validate_base64
    # Environment (from env.sh)
    env_detect_shell env_config_file
    env_set env_persist env_get env_unset env_remove_persist
    env_path_prepend env_path_append env_path_remove env_path_list env_path_has
    env_path_persist_prepend env_path_persist_append env_path_clean
    env_load_dotenv env_save_dotenv
    env_is_set env_is_nonempty env_require env_require_all
    env_list env_export_from env_with env_copy env_swap
    env_get_int env_get_bool env_get_array env_set_array
    env_debug env_diff env_expand env_summary env_backup env_restore
    # Docker (from docker.sh)
    docker_running docker_version
    docker_container_exists docker_container_running docker_container_status
    docker_container_id docker_container_id_short
    docker_container_start docker_container_stop docker_container_restart docker_container_remove
    docker_containers_running docker_containers_all
    docker_exec docker_exec_it
    docker_logs docker_logs_follow
    docker_stats_json docker_cpu docker_memory docker_memory_percent
    docker_container_ip docker_container_ports docker_container_env docker_container_labels docker_container_image
    docker_image_exists docker_image_id docker_image_size docker_image_size_human
    docker_image_pull docker_image_remove docker_images
    docker_port_used docker_port_container
    compose_running compose_status compose_exec compose_up compose_down compose_logs compose_services
    docker_volume_exists docker_volume_create docker_volume_remove docker_volumes
    docker_network_exists docker_network_create docker_network_remove docker_networks
    docker_prune_containers docker_prune_images docker_prune_volumes docker_prune_all
    # Defensive Guards (from guard.sh) - AI coding assistant error prevention
    guard_init guard_on_exit
    guard_path_exists guard_path_safe guard_path_chars guard_symlink guard_destructive_path
    guard_var_set guard_var_safe guard_array_bounds
    guard_command guard_commands guard_os
    guard_lock guard_unlock guard_with_lock
    guard_disk_space guard_memory
    guard_integer guard_filename
    guard_file_op
    # Functional Programming (from functional.sh)
    is_even is_odd is_positive is_negative is_zero is_empty is_not_empty is_numeric is_alnum
    double square increment decrement negate abs
    sum product max min concat
    fp_map fp_map_v fp_map_v_nr
    fp_filter fp_filter_v
    fp_reduce fp_reduce_v fp_reduce_v_nr
    fp_find fp_find_v fp_find_index
    fp_any fp_all fp_none
    fp_compose fp_pipe fp_apply
    fp_partition_v
    fp_take fp_take_while fp_drop fp_drop_while
    fp_zip fp_zip_with
    fp_count fp_group_by identity fp_const
    double_nr square_nr increment_nr decrement_nr
    sum_nr product_nr max_nr min_nr
    # Metaprogramming (from meta.sh)
    var_get var_set var_exists var_nonempty var_unset
    vars_with_prefix vars_matching vars_exported
    var_copy var_swap
    var_type var_is_array var_is_assoc var_is_readonly
    const const_default
    func_exists call_func func_def func_source funcs_with_prefix
    var_ref var_ref_target
    call_method method_exists call_or_default
    var_incr var_decr var_append var_prepend
    array_push_byname array_pop_byname array_len_byname
    # Safe Execution (from safe.sh) - Strict mode and gotcha prevention
    enable_strict_mode disable_strict_mode is_strict_mode
    unsafe_run safe_exit_code
    safe_source safe_source_all source_if_exists
    capture_both capture_stdout capture_stderr capture_all
    retry_backoff retry_backoff_jitter retry_with_callback
    run_with_timeout timeout_cmd
    lint_script check_syntax lint_scripts
    enable_error_context disable_error_context
    default require_var array_get safe_math
    # Process Substitution (from procsub.sh) - subshell variable preservation
    read_lines_from for_each_line diff_commands capture_output
    process_file tee_to_var
    map_lines_from filter_lines_from reduce_lines_from
    commands_equal read_n_lines_from batch_lines_from
    interleave_commands count_lines_from read_pairs_from
    # Structured Output (from output.sh) - Universal Structured Output Protocol
    output_init output_mode output_success output_error
    output_timer_start output_timer_elapsed
    output_string output_int output_bool output_float
    output_json_object output_json_array output_file_path output_void
    output_raw output_json output_wrap output_v
    output_is_json output_is_raw output_is_debug output_is_minimal
    output_format output_with_mode
    mainframe_call output_auto output_list output_object output_progress
    output_structured_error output_try output_json_escape
    # Scope Boundary Enforcement (from scope.sh) - AI agent safety
    mainframe_scope_set mainframe_scope_check mainframe_scope_clear mainframe_scope_status
    mainframe_scope_check_path mainframe_scope_check_host mainframe_scope_check_cmd
    mainframe_scope_exec mainframe_scope_reload mainframe_scope_destroy
    mainframe_scope_add_path mainframe_scope_add_host mainframe_scope_add_cmd
    # Function Hints (from hints.sh) - Workflow discovery
    mainframe_hint mainframe_hints_for mainframe_hints_chain
    mainframe_hint_category mainframe_hint_categories mainframe_hints_count
    # Caching and Memoization (from cache.sh)
    memoize memoize_clear memoize_stats
    cas_store cas_get cas_exists cas_gc
    session_cache_set session_cache_get session_cache_has session_cache_clear session_cache_stats
    cache_invalidate cache_clear cache_stats cache_max_size cache_evict_lru cache_warm
    cache_depends_on cache_check_deps
    # Savant-Level Debugging (from trace.sh) - Function tracing, variable watching, replay
    trace_enable trace_disable trace_is_enabled trace_status
    trace_function trace_untrace trace_all_in_file
    trace_variable trace_unwatch trace_snapshot trace_diff
    trace_timer_start trace_timer_stop trace_timing
    trace_to_json trace_to_mermaid trace_clear trace_set_output
    trace_record_start trace_record_stop trace_replay trace_record_command
)

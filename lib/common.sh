#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/common.sh - Core shared library for MAINFRAME toolkit
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
# Version: 6.0.0
# License: MIT
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_COMMON_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COMMON_LOADED=1

# =============================================================================
# CONFIG FILE LOADING
# =============================================================================
# Load config file if present. Supports key=value format with comments.
# Config file location: $MAINFRAME_CONFIG or ~/.mainframe/config
# All keys are uppercased and prefixed with MAINFRAME_ when exported.
#
# Example config file:
#   profile=standard
#   log_level=info
#   quiet=0
#
# Results in: MAINFRAME_PROFILE=standard, MAINFRAME_LOG_LEVEL=info, etc.
# =============================================================================

_mainframe_load_config() {
    local config_file="${MAINFRAME_CONFIG:-$HOME/.mainframe/config}"
    [[ -f "$config_file" ]] || return 0

    local key value export_key
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// /}" ]] && continue

        # Trim whitespace from key and value
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Skip if key is empty after trimming
        [[ -z "$key" ]] && continue

        # Uppercase the key and export with MAINFRAME_ prefix
        key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
        export_key="MAINFRAME_${key}"

        # Explicit environment/bootstrap variables win over config defaults.
        [[ -n "${!export_key+x}" ]] && continue

        export "$export_key"="$value"
    done < "$config_file"
}
_mainframe_load_config

# =============================================================================
# CONSTANTS
# =============================================================================

readonly MAINFRAME_VERSION="10.2.0"
readonly MAINFRAME_NAME="mainframe"
export MAINFRAME_VERSION MAINFRAME_NAME

# Aliases for backward compatibility
readonly BASHER_VERSION="$MAINFRAME_VERSION"
readonly BASHER_NAME="$MAINFRAME_NAME"
export BASHER_VERSION BASHER_NAME

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

_mainframe_parse_log_level() {
    local raw_level="${1:-$LOG_LEVEL_INFO}"
    local normalized_level
    normalized_level=$(printf '%s' "$raw_level" | tr '[:upper:]' '[:lower:]')

    case "$normalized_level" in
        debug) printf '%s' "$LOG_LEVEL_DEBUG" ;;
        info)  printf '%s' "$LOG_LEVEL_INFO" ;;
        warn|warning) printf '%s' "$LOG_LEVEL_WARN" ;;
        error) printf '%s' "$LOG_LEVEL_ERROR" ;;
        fatal) printf '%s' "$LOG_LEVEL_FATAL" ;;
        ''|*[!0-9]*)
            printf '%s' "$LOG_LEVEL_INFO"
            ;;
        *)
            if [[ "$raw_level" =~ ^[0-4]$ ]]; then
                printf '%s' "$raw_level"
            else
                printf '%s' "$LOG_LEVEL_INFO"
            fi
            ;;
    esac
}

# Current log level.
# Priority: BASHER_LOG_LEVEL env > MAINFRAME_LOG_LEVEL config/env > default INFO.
BASHER_LOG_LEVEL="$(_mainframe_parse_log_level "${BASHER_LOG_LEVEL:-${MAINFRAME_LOG_LEVEL:-$LOG_LEVEL_INFO}}")"

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
# CENTRALIZED INTERNAL LOGGING
# =============================================================================
# Provides consistent logging for all MAINFRAME libraries. Each library calls
# _mainframe_log with its module name, eliminating duplicate _*_log() helpers.
#
# Usage from libraries:
#   _mainframe_log "awm" "info" "Session initialized"
#   _mainframe_log "cache" "error" "Cache miss for key: $key"
# =============================================================================

# Centralized internal logging for all libraries
# Usage: _mainframe_log "module" "level" "message..."
_mainframe_log() {
    local module="$1" level="$2"
    shift 2
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[$module] $*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[%s] %s: %s\n' "$module" "$level" "$*" >&2
    fi
}

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
_MAINFRAME_EXIT_TRAP_COMMANDS=()
_MAINFRAME_PREVIOUS_EXIT_TRAP=""
_MAINFRAME_EXIT_TRAP_INSTALLED=0

# Capture the current trap command for a signal so we can preserve it.
_mainframe_get_trap_command() {
    local signal="$1"
    local trap_def

    trap_def=$(trap -p "$signal") || return 0
    [[ -n "$trap_def" ]] || return 0

    trap_def=${trap_def#trap -- \'}
    trap_def=${trap_def%\' "$signal"}
    printf '%s\n' "$trap_def"
}

# Register an EXIT trap command without clobbering any pre-existing handler.
_mainframe_add_exit_trap() {
    local trap_command="$1"

    [[ -n "${trap_command//[[:space:]]/}" ]] || return 1

    if [[ "${_MAINFRAME_EXIT_TRAP_INSTALLED:-0}" != "1" ]]; then
        if (( ${BASH_SUBSHELL:-0} == 0 )); then
            _MAINFRAME_PREVIOUS_EXIT_TRAP="$(_mainframe_get_trap_command EXIT)"
        else
            # Inherited EXIT traps from parent shells are not safe to replay
            # inside subshells; Bats uses EXIT internally and will emit
            # duplicate/malformed results if we dispatch its parent trap here.
            _MAINFRAME_PREVIOUS_EXIT_TRAP=""
        fi
        trap '_mainframe_dispatch_exit_traps "$?"' EXIT
        _MAINFRAME_EXIT_TRAP_INSTALLED=1
    fi

    _MAINFRAME_EXIT_TRAP_COMMANDS+=("$trap_command")
}

# Register a cleanup function (called by name, no eval)
# Usage: on_exit my_cleanup_function
on_exit() {
    _mainframe_cleanup_funcs+=("$1")
}

# Execute registered EXIT trap handlers in LIFO order while preserving the
# original shell exit status and any pre-existing EXIT trap.
_mainframe_dispatch_exit_traps() {
    local exit_code="$1"
    local idx trap_command
    local restore_errexit=0

    if [[ $- == *e* ]]; then
        restore_errexit=1
        set +e
    fi

    for ((idx=${#_MAINFRAME_EXIT_TRAP_COMMANDS[@]} - 1; idx >= 0; idx -= 1)); do
        trap_command="${_MAINFRAME_EXIT_TRAP_COMMANDS[idx]}"
        builtin eval -- "$trap_command" || true
    done

    if [[ -n "${_MAINFRAME_PREVIOUS_EXIT_TRAP:-}" ]]; then
        builtin eval -- "$_MAINFRAME_PREVIOUS_EXIT_TRAP" || true
    fi

    if (( restore_errexit )); then
        set -e
    fi

    return "$exit_code"
}

# Execute all cleanup handlers safely.
_mainframe_run_cleanup() {
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
}

# Set up trap (only if not already set)
if [[ -z "${_MAINFRAME_TRAP_SET:-}" ]]; then
    _mainframe_add_exit_trap "_mainframe_run_cleanup"
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
        if jq empty "$input" >/dev/null 2>&1; then
            return 0
        fi
    else
        if jq empty <<< "$input" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
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

    # Split on '.' robustly (read -a instead of unquoted expansion)
    local i
    local -a v1_parts v2_parts
    IFS='.' read -r -a v1_parts <<< "$v1"
    IFS='.' read -r -a v2_parts <<< "$v2"

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
    git github docker crypto proc args config
    log structured_log error tui template ci health
    device sysinfo service retry download
    toml yaml collection queue regex schema
    bun audit
)

# Extended tier: advanced/specialized libraries
_MAINFRAME_TIER_EXTENDED=(
    k8s semver functional compose stream streaming pipe
    procsub async futures meta cli fzf
    compat safe guard telemetry otel
    proptest testing benchmark
    workpool
    temporal state_machine graph
    cache diff
)

# Phase 3 AI tier: agent-optimized modules
_MAINFRAME_TIER_AI=(
    idempotent atomic observe project
    contract perf netscan parsers trace forensics
    risk dryrun undo sandbox
    limits confirm safewrap safecontext
    agent workflow taskstate
    context parse_output symbols agent_exec
    agent_comm agent_safety agent_ai agent_context
    awm awm_storage awm_tiers awm_stream
    llm_tokens llm_functions llm_stream llm_providers
    embeddings registry vectordb rag policy rbac
    agent_loop ammma uap
    heal predict generate verify intent orchestrate
    agent_teams
    tirith tirith_url tirith_inject tirith_pipe tirith_ecosystem tirith_path tirith_hook
)

# --- Bundle Presets ---------------------------------------------------------
# Pre-defined library bundles for common use cases.
# Bundles provide finer granularity than tier-based profiles.
#
# Usage:
#   source common.sh
#   mainframe_bundle "agent_minimal"   # Load specific bundle
#   mainframe_bundle "data"            # Load data processing bundle
# =============================================================================

declare -gA MAINFRAME_BUNDLES=(
    [agent_minimal]="core,agent,awm,validation"
    [agent_memory]="core,awm,awm_storage,awm_tiers,awm_stream,agent_context"
    [agent_runtime]="core,agent,agent_exec,agent_comm,agent_safety,agent_loop,workflow,taskstate,validation,retry,queue,state_machine,awm,awm_storage,awm_tiers,awm_stream"
    [agent_full]="core,agent,agent_exec,agent_comm,agent_safety,agent_ai,agent_loop,agent_context,workflow,taskstate,observe,idempotent,atomic,validation,retry,queue,state_machine,diff,awm,awm_storage,awm_tiers,awm_stream,embeddings,rag"
    [data]="core,json,csv,datetime,parsers"
    [net]="core,http,burl,github"
    [devops]="core,git,docker,github_actions"
    [tui]="core,ansi,tui,anim,output"
    [testing]="core,testing,proptest,validation"
    [agent_teams]="core,agent,awm,agent_ai,agent_teams,taskstate"
    [terminal_security]="core,validation,parsers,fuzzy,security,risk,tirith_inject,tirith_path,tirith_pipe,tirith_url,tirith_ecosystem,tirith,tirith_hook"
    [full]="all"
)

# Load a specific bundle by name
# Usage: mainframe_bundle "agent_minimal"
# Returns: 0 on success, 1 if bundle not found
mainframe_bundle() {
    local bundle="${1:-${MAINFRAME_DEFAULT_BUNDLE:-agent_minimal}}"
    local libs="${MAINFRAME_BUNDLES[$bundle]:-}"

    [[ -z "$libs" ]] && {
        # Use printf for error since log_error may not be loaded yet
        printf '[ERROR] Unknown bundle: %s\n' "$bundle" >&2
        printf '[INFO] Available bundles: %s\n' "${!MAINFRAME_BUNDLES[*]}" >&2
        return 1
    }

    # Handle 'all' special case
    if [[ "$libs" == "all" ]]; then
        mainframe_load_all
        return 0
    fi

    # Load each library in the bundle
    local IFS=','
    local lib
    for lib in $libs; do
        # Handle 'core' as a tier reference
        if [[ "$lib" == "core" ]]; then
            _mainframe_load_tier "core"
        else
            _mainframe_load_library "$lib"
        fi
    done
}

# List available bundles
# Usage: mainframe_bundles
# Output: One bundle name per line with description
mainframe_bundles() {
    local bundle
    for bundle in "${!MAINFRAME_BUNDLES[@]}"; do
        printf '%s: %s\n' "$bundle" "${MAINFRAME_BUNDLES[$bundle]}"
    done | sort
}

# --- Profile Presets ---------------------------------------------------------

# Resolve MAINFRAME_PROFILE to MAINFRAME_LIBS if profile is set
if [[ -n "${MAINFRAME_PROFILE:-}" && -z "${MAINFRAME_LIBS:-}" ]]; then
    case "${MAINFRAME_PROFILE}" in
        minimal)  MAINFRAME_LIBS="core" ;;
        standard) MAINFRAME_LIBS="core+standard" ;;
        full)     MAINFRAME_LIBS="all" ;;
        ai)       MAINFRAME_LIBS="core+ai" ;;
        lazy)     MAINFRAME_LAZY=1 ;;  # Function-level lazy loading
        *)
            log_warn "Unknown MAINFRAME_PROFILE '${MAINFRAME_PROFILE}', loading all"
            MAINFRAME_LIBS="all"
            ;;
    esac
fi

# Command entry points may provide a cheap default without masking a profile or
# library selection loaded from the user's config file. Explicit MAINFRAME_LIBS,
# MAINFRAME_PROFILE, and lazy mode all remain authoritative.
if [[ -z "${MAINFRAME_LIBS:-}" && -n "${MAINFRAME_DEFAULT_LIBS:-}" && "${MAINFRAME_LAZY:-0}" != "1" ]]; then
    MAINFRAME_LIBS="$MAINFRAME_DEFAULT_LIBS"
fi

# --- Enhanced Lazy Loading (Function-Level) ----------------------------------
# When MAINFRAME_LAZY=1, uses stub functions that load libraries on first call.
# This provides maximum efficiency for AI agents that only need specific functions.
#
# Usage:
#   MAINFRAME_LAZY=1 source common.sh           # Stubs only (fastest startup)
#   MAINFRAME_PROFILE='lazy' source common.sh   # Same as above
#
# The lazy.sh library provides:
#   - Function stubs that auto-load libraries
#   - Library manifests for function->library mapping
#   - Precompiled bundles for deployment
#   - Load profiling and memory reporting
# =============================================================================

declare -g MAINFRAME_LAZY="${MAINFRAME_LAZY:-0}"
declare -g MAINFRAME_SKIP_AUTOLOAD="${MAINFRAME_SKIP_AUTOLOAD:-0}"

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

# Load a named bundle from MAINFRAME_BUNDLES.
_mainframe_load_bundle() {
    local bundle_name="$1"
    local libs="${MAINFRAME_BUNDLES[$bundle_name]:-}"
    local lib
    local IFS=','

    [[ -n "$libs" ]] || {
        log_warn "Unknown bundle: ${bundle_name}"
        return 1
    }

    if [[ "$libs" == "all" ]]; then
        _mainframe_load_tier "standard"
        _mainframe_load_tier "extended"
        _mainframe_load_tier "ai"
        return 0
    fi

    for lib in $libs; do
        lib="${lib#"${lib%%[![:space:]]*}"}"
        lib="${lib%"${lib##*[![:space:]]}"}"
        case "$lib" in
            core|standard|extended|ai)
                [[ "$lib" == "core" ]] || _mainframe_load_tier "$lib"
                ;;
            bundle:*)
                _mainframe_load_bundle "${lib#bundle:}"
                ;;
            *+*)
                _mainframe_load_selected "$lib"
                ;;
            *)
                [[ -n "$lib" ]] && _mainframe_load_library "$lib"
                ;;
        esac
    done
}

# Parse MAINFRAME_LIBS value and load requested libraries
# Supports: comma-separated names, tier names with +, bundle:name, 'all'
_mainframe_load_selected() {
    local libs_spec="$1"
    local IFS=','
    local item

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

    # Handle comma-separated bundle/tier/library selections
    for item in $libs_spec; do
        # Trim whitespace
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -n "$item" ]] || continue

        case "$item" in
            core)
                ;;
            standard|extended|ai)
                _mainframe_load_tier "$item"
                ;;
            bundle:*)
                _mainframe_load_bundle "${item#bundle:}"
                ;;
            *+*)
                _mainframe_load_selected "$item"
                ;;
            *)
                _mainframe_load_library "$item"
                ;;
        esac
    done
}

# --- Load Decision -----------------------------------------------------------

# Check for function-level lazy loading mode
if [[ "${MAINFRAME_SKIP_AUTOLOAD:-0}" == "1" ]]; then
    :
elif [[ "${MAINFRAME_LAZY:-0}" == "1" ]]; then
    # Function-level lazy loading: load only lazy.sh, create stubs for everything else
    # This is the most efficient mode for AI agents
    _mainframe_load_library "lazy"

    # Initialize function stubs - libraries load on first use
    if declare -F lazy_init_stubs &>/dev/null; then
        lazy_init_stubs
    fi

elif [[ -n "${MAINFRAME_LIBS:-}" ]]; then
    # Selective loading: use tier-based loading engine
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
    _mainframe_load_library "github"
    _mainframe_load_library "github_actions"
    _mainframe_load_library "github_security"
    _mainframe_load_library "docker"
    _mainframe_load_library "crypto"
    _mainframe_load_library "proc"
    _mainframe_load_library "args"
    _mainframe_load_library "config"
    _mainframe_load_library "log"
    _mainframe_load_library "structured_log"
    _mainframe_load_library "error"
    _mainframe_load_library "tui"
    _mainframe_load_library "anim"
    _mainframe_load_library "template"
    _mainframe_load_library "ci"
    _mainframe_load_library "health"
    _mainframe_load_library "device"
    _mainframe_load_library "sysinfo"
    _mainframe_load_library "service"
    _mainframe_load_library "retry"
    _mainframe_load_library "download"
    _mainframe_load_library "toml"
    _mainframe_load_library "yaml"
    _mainframe_load_library "collection"
    _mainframe_load_library "queue"
    _mainframe_load_library "schema"
    _mainframe_load_library "bun"
    _mainframe_load_library "audit"

    # Extended tier libraries
    _mainframe_load_library "k8s"
    _mainframe_load_library "semver"
    _mainframe_load_library "functional"
    _mainframe_load_library "compose"
    _mainframe_load_library "stream"
    _mainframe_load_library "streaming"
    _mainframe_load_library "pipe"
    _mainframe_load_library "procsub"
    _mainframe_load_library "async"
    _mainframe_load_library "futures"
    _mainframe_load_library "meta"
    _mainframe_load_library "cli"
    _mainframe_load_library "fzf"
    _mainframe_load_library "compat"
    _mainframe_load_library "safe"
    _mainframe_load_library "guard"
    _mainframe_load_library "telemetry"
    _mainframe_load_library "otel"
    _mainframe_load_library "proptest"
    _mainframe_load_library "testing"
    _mainframe_load_library "benchmark"
    _mainframe_load_library "workpool"
    _mainframe_load_library "temporal"
    _mainframe_load_library "state_machine"
    _mainframe_load_library "graph"

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
    _mainframe_load_library "forensics"
    _mainframe_load_library "cache"
    _mainframe_load_library "scope"
    _mainframe_load_library "risk"
    _mainframe_load_library "dryrun"
    _mainframe_load_library "undo"
    _mainframe_load_library "sandbox"
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
    # Note: agent_comm.sh disabled - conflicts with agent.sh functions
    # _mainframe_load_library "agent_comm"
    _mainframe_load_library "agent_safety"
    _mainframe_load_library "agent_ai"
    _mainframe_load_library "agent_context"
    _mainframe_load_library "awm"
    _mainframe_load_library "awm_storage"
    _mainframe_load_library "awm_tiers"
    _mainframe_load_library "awm_stream"
    _mainframe_load_library "llm_tokens"
    _mainframe_load_library "llm_functions"
    _mainframe_load_library "llm_providers"
    _mainframe_load_library "registry"
    _mainframe_load_library "registry_schema"
    _mainframe_load_library "embeddings"
    _mainframe_load_library "vectordb"
    _mainframe_load_library "rag"
    _mainframe_load_library "policy"
    _mainframe_load_library "rbac"
    _mainframe_load_library "agent_loop"
    _mainframe_load_library "ammma"
    _mainframe_load_library "uap"
    _mainframe_load_library "heal"
    _mainframe_load_library "predict"
    _mainframe_load_library "generate"
    _mainframe_load_library "verify"
    _mainframe_load_library "intent"
    _mainframe_load_library "orchestrate"

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
    # Bundle API
    mainframe_bundle mainframe_bundles
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
    # Arrays (canonical value-list API from pure-array.sh)
    array_contains array_join
    array_count array_filter array_first array_get array_intersect
    array_last array_length array_reverse array_slice array_sum array_unique
    # Explicit named-array alternatives from collection.sh
    collection_count collection_filter collection_first collection_intersect
    collection_last collection_length collection_reverse collection_slice
    collection_sum collection_unique
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
    # Bun.js Runtime (from bun.sh) - Bun package manager and runtime helpers
    bun_detect bun_version bun_is_project
    bun_install bun_add bun_remove bun_list
    bun_run bun_exec bun_test
    bun_workspace_detect bun_workspace_run bun_workspace_list
    bun_project_summary bun_config bun_suggest_command
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
    # Function Composition (from compose.sh)
    compose pipe_fn chain
    partial curry flip
    tap identity constant apply
    lazy force lazy_seq take_lazy
    memoize_fn cache_clear_fn
    compose_reset compose_stats
    try_each when if_else times
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
    default require_var safe_array_get safe_math
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
    memo_wrap memo_unwrap memo_clear
    cache_command cache_file cache_file_invalidate cache_compute
    cache_stats_reset cache_prewarm
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
    # Queue and Data Structures (from queue.sh)
    queue_create queue_push queue_pop queue_pop_v queue_peek queue_peek_v queue_peek_back
    queue_size queue_is_empty queue_clear queue_to_array queue_from_array
    stack_create stack_push stack_pop stack_pop_v stack_peek stack_peek_v
    stack_size stack_is_empty stack_clear stack_reverse stack_to_array
    deque_create deque_push_front deque_push_back deque_pop_front deque_pop_front_v
    deque_pop_back deque_pop_back_v deque_peek_front deque_peek_back
    deque_size deque_is_empty deque_clear deque_rotate_left deque_rotate_right
    pqueue_create pqueue_push pqueue_pop pqueue_pop_v pqueue_peek pqueue_peek_priority
    pqueue_size pqueue_is_empty pqueue_clear pqueue_update_priority
    ring_create ring_push ring_pop ring_pop_v ring_peek ring_size ring_capacity
    ring_is_empty ring_is_full ring_clear ring_to_array
    queue_drain queue_each queue_filter queue_to_json queue_from_json pqueue_to_json
    # Stream Processing (from streaming.sh)
    stream_map stream_map_v stream_filter stream_filter_v stream_reduce stream_reduce_v
    stream_take stream_skip stream_head stream_tail stream_unique stream_sort stream_reverse
    stream_parallel stream_batch stream_chunk stream_fanout stream_fanin stream_rate_limit
    stream_json_lines stream_csv_lines stream_detect_type stream_validate
    stream_count stream_any stream_all stream_none stream_find
    stream_take_while stream_drop_while stream_group_by stream_enumerate stream_zip
    stream_to_usop stream_from_usop stream_stats stream_compose stream_tap
    # Download Helper (from download.sh) - Universal download with fallback chain
    download_backend download download_stdout download_progress
    download_batch download_resume download_verify download_extract
    # CI/CD Platform Detection (from ci.sh) - 17 CI platform detectors
    ci_is_ci ci_platform ci_info
    ci_is_github_actions ci_is_gitlab_ci ci_is_jenkins ci_is_buildkite
    ci_is_bitbucket ci_is_teamcity ci_is_circleci ci_is_travis ci_is_appveyor
    ci_is_azure_pipelines ci_is_aws_codebuild ci_is_gcp_cloud_build
    ci_is_drone ci_is_semaphore ci_is_buddy ci_is_woodpecker ci_is_gitea_actions
    ci::is_ci ci::detect ci::name ci::set_output ci::set_env ci::add_path
    ci::group_start ci::group_end ci::warning ci::error ci::notice ci::debug
    ci::artifact_checksum ci::artifact_create ci::is_pull_request ci::pr_number
    ci::pr_branch ci::pr_target ci::commit_sha ci::commit_short ci::branch
    ci::tag ci::is_tag ci::runner ci::build_number ci::repository ci::mask_value
    ci::cache_key_prefix
    # GitHub CLI Wrapper (from github.sh) - 100+ GitHub operations
    gh_auth_status gh_auth_token gh_whoami gh_config_get gh_config_set
    gh_repo_view gh_repo_list gh_repo_create gh_repo_clone gh_repo_fork
    gh_repo_delete gh_repo_archive gh_repo_topics gh_repo_languages
    gh_repo_contributors gh_repo_stars gh_repo_forks gh_repo_exists
    gh_repo_default_branch gh_repo_is_fork gh_repo_parent gh_repo_visibility
    gh_repo_rename gh_repo_sync
    gh_issue_list gh_issue_create gh_issue_view gh_issue_close gh_issue_reopen
    gh_issue_comment gh_issue_labels gh_issue_add_labels gh_issue_assignees
    gh_issue_assign gh_issue_search gh_issue_edit gh_issue_transfer
    gh_issue_pin gh_issue_unpin
    gh_pr_list gh_pr_create gh_pr_view gh_pr_diff gh_pr_files gh_pr_merge
    gh_pr_close gh_pr_reopen gh_pr_review gh_pr_comment gh_pr_checks
    gh_pr_ready gh_pr_draft gh_pr_labels gh_pr_reviewers gh_pr_checkout
    gh_pr_is_merged gh_pr_merge_commit gh_pr_edit
    gh_gist_list gh_gist_create gh_gist_view gh_gist_clone gh_gist_edit
    gh_gist_delete gh_gist_rename
    gh_release_list gh_release_latest gh_release_create gh_release_view
    gh_release_delete gh_release_download gh_release_upload gh_release_notes
    gh_release_edit
    gh_search_repos gh_search_code gh_search_issues gh_search_users
    gh_search_commits gh_search_topics
    gh_user_info gh_user_repos gh_user_orgs gh_user_followers gh_user_following
    gh_star_repo gh_unstar_repo gh_watch_repo gh_is_starred
    gh_follow_user gh_unfollow_user
    gh_notifications_list gh_notifications_count gh_notifications_mark_read
    gh_notifications_mark_read_repo
    gh_run_list gh_run_view gh_run_rerun gh_run_cancel gh_run_watch gh_run_download
    gh_context_json gh_pr_context gh_issue_context gh_codeowners
    gh_repo_summary gh_repo_tree gh_recent_commits
    # Agent Working Memory (from awm.sh) - Persistent external memory for AI agents
    awm_init awm_resume awm_close awm_namespace
    awm_checkpoint awm_log awm_progress awm_discovery
    awm_get awm_recent awm_summary awm_context_for
    awm_handoff_prepare awm_handoff_accept
    awm_compress awm_export awm_inherit
    awm_token_estimate awm_estimate_read
    awm_list awm_cleanup awm_check_limits
    # AWM v2 Integration (from awm.sh) - Tiered memory with multi-backend support
    awm_v2_init awm_v2_status
    awm_checkpoint_v2 awm_get_v2 awm_context_v2
    awm_recovery_checkpoint awm_recovery_restore
    # AWM Storage (from awm_storage.sh) - Multi-backend storage abstraction
    awm_storage_init awm_storage_backend awm_storage_caps
    awm_store_set awm_store_get awm_store_delete awm_store_exists
    awm_store_push awm_store_pop awm_store_range awm_store_len
    awm_store_search awm_store_index
    awm_store_publish awm_store_subscribe
    awm_storage_clear awm_storage_stats awm_storage_health awm_storage_status
    # AWM Tiers (from awm_tiers.sh) - Hot/warm/cold tier management
    awm_tier_init awm_tier_write awm_tier_read awm_tier_delete
    awm_hot_set awm_hot_get awm_hot_delete awm_hot_exists awm_hot_size awm_hot_keys
    awm_warm_set awm_warm_get awm_warm_delete awm_warm_exists awm_warm_size
    awm_cold_set awm_cold_get awm_cold_delete awm_cold_search
    awm_tier_promote awm_tier_demote awm_tier_prefetch
    awm_evict_hot awm_evict_warm awm_evict_cold awm_evict_all
    awm_tier_stats awm_tier_checkpoint awm_tier_recover awm_tier_clear
    # AWM Streaming (from awm_stream.sh) - Token budget and semantic chunking
    awm_budget_init awm_budget_max awm_budget_used awm_budget_remaining
    awm_budget_fits awm_budget_use awm_budget_reset awm_budget_summary
    awm_estimate_tokens awm_estimate_file_tokens awm_detect_content_type
    awm_pointer_create awm_pointer_resolve awm_pointer_exists awm_pointer_meta
    awm_wrap_result awm_chunk awm_summarize_chunks
    awm_stream_compress
    awm_truncate awm_read_plan
    # Explicit legacy protocol-v4 handoff compatibility API
    awm_protocol_handoff_prepare awm_protocol_handoff_accept
    # Structured Logging (from structured_log.sh) - JSON-structured logging for observability
    slog_init slog_debug slog_info slog_warn slog_error slog_fatal
    slog_set_level slog_set_output slog_with_context slog_clear_context
    slog_flush slog_rotate
    slog_get_level slog_get_output slog_would_log slog_stats slog_build_v
    # Telemetry (from telemetry.sh) - Opt-in anonymous usage telemetry
    telemetry_enabled telemetry_init telemetry_track telemetry_flush telemetry_report
    # OpenTelemetry (from otel.sh) - Distributed tracing with W3C Trace Context
    otel_init otel_trace_start otel_trace_end
    otel_trace_add_event otel_trace_set_attribute otel_trace_set_status
    otel_trace_id otel_span_id
    otel_inject_headers otel_extract_headers
    otel_export otel_flush
    otel_instrument otel_timed
    # Property-Based Testing (from proptest.sh) - Random input generation and shrinking
    proptest_run proptest_check proptest_shrink proptest_suite proptest proptest_reset proptest_stats
    proptest_assert_eq proptest_assert_ne proptest_assert_match
    gen_int gen_positive_int gen_nat gen_string gen_ascii gen_alpha gen_lower gen_upper
    gen_choice gen_bool gen_array gen_email gen_uuid gen_json_object gen_url gen_date
    gen_ipv4 gen_port gen_oneof gen_hex gen_float
    proptest_shrink_int proptest_shrink_string proptest_usop_result
    # Error Forensics (from forensics.sh) - Deep debugging for multi-agent systems
    forensics_stack forensics_stack_json forensics_caller
    forensics_capture forensics_snapshot forensics_diff
    forensics_error forensics_chain_add forensics_chain_dump forensics_root_cause
    forensics_watch forensics_unwatch forensics_watched_changes
    forensics_bundle forensics_bundle_save forensics_bundle_load
    forensics_trap_install forensics_trap_uninstall
    forensics_clear forensics_status
    # LLM Token Estimation (from llm_tokens.sh) - Model-specific token counting and cost estimation
    llm_count_tokens llm_count_tokens_file llm_count_tokens_usop llm_clear_cache
    llm_estimate_cost llm_get_pricing llm_list_models
    llm_truncate_to_tokens llm_truncate_usop
    llm_split_chunks llm_split_chunks_file
    llm_context_window llm_fits_context llm_model_family
    # LLM Function/Tool Calling (from llm_functions.sh) - Tool registration and execution
    llm_register_tool llm_unregister_tool llm_list_tools llm_get_tool_schema
    llm_tool_exists llm_clear_tools
    llm_detect_format llm_parse_tool_call llm_parse_tool_calls
    llm_validate_tool_args llm_validate_tool_args_errors
    llm_execute_tool llm_execute_tool_safe
    llm_format_tool_result llm_format_tool_error
    llm_tools_to_openai llm_tools_to_anthropic llm_tool_export
    llm_process_tool_call llm_tool_info
    llm_parse_tool_call_v llm_execute_tool_v llm_validate_tool_args_v
    # Function Registry (from registry.sh) - Function scanner and catalog system
    registry_scan registry_scan_all
    registry_get_function registry_list_by_category registry_list_by_library
    registry_search registry_export registry_stats
    registry_save_cache registry_load_cache registry_clear_cache
    registry_list_categories registry_list_libraries registry_function_exists
    registry_count registry_list_all
    # Vector Database (from vectordb.sh) - Universal vector database interface
    vectordb_init vectordb_reset vectordb_info vectordb_health
    vectordb_create_collection vectordb_delete_collection vectordb_list_collections
    vectordb_upsert vectordb_search vectordb_get vectordb_delete vectordb_count
    # RAG Pipeline (from rag.sh) - Retrieval-Augmented Generation
    rag_init rag_reset rag_is_initialized rag_collection
    rag_ingest rag_ingest_file rag_ingest_text
    rag_chunk_text
    rag_query rag_search
    rag_augment_prompt rag_rerank
    rag_delete rag_stats
    # Role-Based Access Control (from rbac.sh) - Enterprise RBAC for AI agents
    rbac_init rbac_reset
    rbac_define_role rbac_inherit_role rbac_delete_role rbac_list_roles rbac_get_role
    rbac_assign_role rbac_revoke_role rbac_get_roles rbac_list_subjects
    rbac_check_permission rbac_require_permission rbac_get_permissions
    rbac_set_audit_log rbac_audit_access
    rbac_export rbac_import
    rbac_stats rbac_clear_cache
)

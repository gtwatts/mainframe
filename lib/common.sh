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
assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if ! eval "$condition"; then
        die "$EXIT_SOFTWARE" "$message"
    fi
}

# Trap handler for cleanup
_basher_cleanup_handlers=()

# Register a cleanup handler
on_exit() {
    _basher_cleanup_handlers+=("$1")
}

# Execute all cleanup handlers
_basher_run_cleanup() {
    local exit_code=$?
    for handler in "${_basher_cleanup_handlers[@]}"; do
        eval "$handler" || true
    done
    exit $exit_code
}

# Set up trap (only if not already set)
if [[ -z "${_BASHER_TRAP_SET:-}" ]]; then
    trap _basher_run_cleanup EXIT
    readonly _BASHER_TRAP_SET=1
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

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width="${3:-40}"
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r[%b%*s%b%*s] %3d%%" \
        "$CLR_GREEN" "$filled" '' "$CLR_RESET" "$empty" '' "$percent"

    [[ "$current" -eq "$total" ]] && printf "\n"
}

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

# Trim whitespace from string
trim() {
    local str="$*"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Convert to lowercase
lowercase() {
    printf '%s' "${1,,}"
}

# Convert to uppercase
uppercase() {
    printf '%s' "${1^^}"
}

# Check if string contains substring
contains() {
    local string="$1"
    local substring="$2"
    [[ "$string" == *"$substring"* ]]
}

# Check if string starts with prefix
starts_with() {
    local string="$1"
    local prefix="$2"
    [[ "$string" == "$prefix"* ]]
}

# Check if string ends with suffix
ends_with() {
    local string="$1"
    local suffix="$2"
    [[ "$string" == *"$suffix" ]]
}

# Generate random string
random_string() {
    local length="${1:-16}"
    local charset="${2:-a-zA-Z0-9}"
    tr -dc "$charset" </dev/urandom | head -c "$length"
}

# =============================================================================
# ARRAY UTILITIES
# =============================================================================

# Check if array contains element
array_contains() {
    local needle="$1"
    shift
    local element
    for element in "$@"; do
        [[ "$element" == "$needle" ]] && return 0
    done
    return 1
}

# Join array elements with delimiter
array_join() {
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf '%s' "$first"
    printf '%s' "${@/#/$delimiter}"
}

# =============================================================================
# FILE UTILITIES
# =============================================================================

# Create temporary file with automatic cleanup
temp_file() {
    local prefix="${1:-basher}"
    local tmpfile
    tmpfile=$(mktemp "/tmp/${prefix}.XXXXXX")
    on_exit "rm -f '$tmpfile'"
    printf '%s' "$tmpfile"
}

# Create temporary directory with automatic cleanup
temp_dir() {
    local prefix="${1:-basher}"
    local tmpdir
    tmpdir=$(mktemp -d "/tmp/${prefix}.XXXXXX")
    on_exit "rm -rf '$tmpdir'"
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

# Source pure-string.sh for advanced string operations
if [[ -f "${_MAINFRAME_LIB_DIR}/pure-string.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/pure-string.sh"
fi

# Source pure-array.sh for advanced array operations
if [[ -f "${_MAINFRAME_LIB_DIR}/pure-array.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/pure-array.sh"
fi

# Source pure-util.sh for utilities
if [[ -f "${_MAINFRAME_LIB_DIR}/pure-util.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/pure-util.sh"
fi

# Source pure-file.sh for file operations
if [[ -f "${_MAINFRAME_LIB_DIR}/pure-file.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/pure-file.sh"
fi

# Source json.sh for JSON generation
if [[ -f "${_MAINFRAME_LIB_DIR}/json.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/json.sh"
fi

# Source ansi.sh for terminal colors and UI
if [[ -f "${_MAINFRAME_LIB_DIR}/ansi.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/ansi.sh"
fi

# Source async.sh for async/parallel operations
if [[ -f "${_MAINFRAME_LIB_DIR}/async.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/async.sh"
fi

# Source semver.sh for semantic versioning
if [[ -f "${_MAINFRAME_LIB_DIR}/semver.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/semver.sh"
fi

# Source args.sh for argument parsing
if [[ -f "${_MAINFRAME_LIB_DIR}/args.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/args.sh"
fi

# Source config.sh for config file handling
if [[ -f "${_MAINFRAME_LIB_DIR}/config.sh" ]]; then
    source "${_MAINFRAME_LIB_DIR}/config.sh"
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of all public functions (for documentation)
BASHER_COMMON_EXPORTS=(
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
)

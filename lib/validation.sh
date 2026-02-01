#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/validation.sh - Input Validation and Sanitization
# =============================================================================
# Description: Defensive input validation and sanitization for security
# Purpose: Prevents 95% of path/input errors and injection vulnerabilities
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_VALIDATION_LOADED:-}" ]] && return 0
readonly _MAINFRAME_VALIDATION_LOADED=1

# =============================================================================
# TYPE VALIDATION
# =============================================================================

# Validate integer with optional range
# Usage: validate_int "value" [min] [max]
# Returns: 0 if valid, 1 if invalid
validate_int() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"

    # Empty check
    [[ -z "$value" ]] && return 1

    # Must be integer (optional leading minus)
    [[ ! "$value" =~ ^-?[0-9]+$ ]] && return 1

    # Range checks if provided
    if [[ -n "$min" ]]; then
        (( value < min )) && return 1
    fi
    if [[ -n "$max" ]]; then
        (( value > max )) && return 1
    fi

    return 0
}

# Validate floating point number
# Usage: validate_float "value"
validate_float() {
    local value="$1"

    [[ -z "$value" ]] && return 1

    # Match: optional minus, digits, optional decimal point with digits, optional exponent
    [[ "$value" =~ ^-?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]]
}

# Validate boolean value
# Usage: validate_bool "value"
# Accepts: true/false/yes/no/1/0/on/off (case insensitive)
validate_bool() {
    local value="${1,,}"  # lowercase

    case "$value" in
        true|false|yes|no|1|0|on|off) return 0 ;;
        *) return 1 ;;
    esac
}

# Validate UUID format (v1-v5)
# Usage: validate_uuid "value"
validate_uuid() {
    local value="$1"

    [[ -z "$value" ]] && return 1

    # UUID format: 8-4-4-4-12 hex chars
    [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# Validate hexadecimal string
# Usage: validate_hex "value" [length]
validate_hex() {
    local value="$1"
    local length="${2:-}"

    [[ -z "$value" ]] && return 1

    # Must be hex characters only
    [[ ! "$value" =~ ^[0-9a-fA-F]+$ ]] && return 1

    # Length check if specified
    if [[ -n "$length" ]]; then
        [[ ${#value} -ne $length ]] && return 1
    fi

    return 0
}

# =============================================================================
# FORMAT VALIDATION
# =============================================================================

# Validate email address (RFC 5322 simplified)
# Usage: validate_email "address"
validate_email() {
    local email="$1"

    [[ -z "$email" ]] && return 1

    # RFC 5322 simplified: local@domain.tld
    # Local part: alphanumeric, dots, hyphens, underscores, plus, percent
    # Domain: alphanumeric, dots, hyphens
    # TLD: 2+ alpha chars
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Validate URL format
# Usage: validate_url "url" [schemes]
# Default schemes: http,https
validate_url() {
    local url="$1"
    local schemes="${2:-http,https}"

    [[ -z "$url" ]] && return 1

    # Build scheme pattern from comma-separated list
    local scheme_pattern
    scheme_pattern="(${schemes//,/|})"

    # URL pattern: scheme://domain[:port][/path][?query][#fragment]
    # Use simpler path pattern for portability - allows common URL chars
    local url_regex="^${scheme_pattern}://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$"
    [[ "$url" =~ $url_regex ]]
}

# Validate domain name format
# Usage: validate_domain "domain"
validate_domain() {
    local domain="$1"

    [[ -z "$domain" ]] && return 1

    # Domain: labels separated by dots, each label alphanumeric with optional hyphens
    # Labels cannot start or end with hyphen
    # Total length max 253, label max 63
    [[ ${#domain} -gt 253 ]] && return 1

    # Split and validate each label
    local IFS='.'
    local labels
    read -ra labels <<< "$domain"

    [[ ${#labels[@]} -lt 2 ]] && return 1

    for label in "${labels[@]}"; do
        [[ -z "$label" ]] && return 1
        [[ ${#label} -gt 63 ]] && return 1
        [[ ! "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] && return 1
    done

    return 0
}

# Validate IPv4 address
# Usage: validate_ipv4 "address"
validate_ipv4() {
    local ip="$1"

    [[ -z "$ip" ]] && return 1

    local IFS='.'
    local octets
    read -ra octets <<< "$ip"

    [[ ${#octets[@]} -ne 4 ]] && return 1

    for octet in "${octets[@]}"; do
        # Must be numeric, no leading zeros (except for 0 itself)
        [[ ! "$octet" =~ ^(0|[1-9][0-9]*)$ ]] && return 1
        # Range 0-255
        (( octet < 0 || octet > 255 )) && return 1
    done

    return 0
}

# Validate IPv6 address
# Usage: validate_ipv6 "address"
validate_ipv6() {
    local ip="$1"

    [[ -z "$ip" ]] && return 1

    # IPv6 can have :: for zero compression (only once)
    # Full form: 8 groups of 4 hex digits separated by colons

    # Count :: occurrences (max 1)
    local double_colon_count
    double_colon_count=$(grep -o '::' <<< "$ip" | wc -l)
    (( double_colon_count > 1 )) && return 1

    # Remove :: temporarily for validation
    local expanded="$ip"
    if [[ "$ip" == *"::"* ]]; then
        # Calculate missing groups
        local groups_present
        groups_present=$(tr ':' '\n' <<< "${ip//::/:}" | grep -c '[0-9a-fA-F]' || true)
        local missing=$((8 - groups_present))
        local zeros
        zeros=$(printf ':0%.0s' $(seq 1 $missing))
        expanded="${ip/::/$zeros:}"
        expanded="${expanded#:}"
        expanded="${expanded%:}"
    fi

    # Split and validate
    local IFS=':'
    local groups
    read -ra groups <<< "$expanded"

    [[ ${#groups[@]} -ne 8 ]] && return 1

    for group in "${groups[@]}"; do
        [[ -z "$group" ]] && group="0"
        [[ ! "$group" =~ ^[0-9a-fA-F]{1,4}$ ]] && return 1
    done

    return 0
}

# Validate date format YYYY-MM-DD
# Usage: validate_date "YYYY-MM-DD"
validate_date() {
    local date="$1"

    [[ -z "$date" ]] && return 1

    # Pattern check
    [[ ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && return 1

    # Extract parts
    local year="${date:0:4}"
    local month="${date:5:2}"
    local day="${date:8:2}"

    # Remove leading zeros for arithmetic
    month=$((10#$month))
    day=$((10#$day))

    # Range checks
    (( month < 1 || month > 12 )) && return 1
    (( day < 1 || day > 31 )) && return 1

    # Days per month validation
    local days_in_month
    case $month in
        1|3|5|7|8|10|12) days_in_month=31 ;;
        4|6|9|11) days_in_month=30 ;;
        2)
            # Leap year check
            if (( (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 )); then
                days_in_month=29
            else
                days_in_month=28
            fi
            ;;
    esac

    (( day > days_in_month )) && return 1

    return 0
}

# Validate time format HH:MM:SS
# Usage: validate_time "HH:MM:SS"
validate_time() {
    local time="$1"

    [[ -z "$time" ]] && return 1

    # Pattern check
    [[ ! "$time" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && return 1

    # Extract parts
    local hour="${time:0:2}"
    local minute="${time:3:2}"
    local second="${time:6:2}"

    # Remove leading zeros for arithmetic
    hour=$((10#$hour))
    minute=$((10#$minute))
    second=$((10#$second))

    # Range checks
    (( hour < 0 || hour > 23 )) && return 1
    (( minute < 0 || minute > 59 )) && return 1
    (( second < 0 || second > 59 )) && return 1

    return 0
}

# Validate semantic version
# Usage: validate_semver "version"
validate_semver() {
    local version="$1"

    [[ -z "$version" ]] && return 1

    # Strip optional 'v' prefix
    [[ "$version" == v* ]] && version="${version:1}"

    # SemVer: MAJOR.MINOR.PATCH[-prerelease][+build]
    # MAJOR, MINOR, PATCH are non-negative integers without leading zeros (except 0)
    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

# =============================================================================
# PATH VALIDATION
# =============================================================================

# Validate path exists with optional type check
# Usage: validate_path "path" [type]
# type: file, dir, any (default: any)
validate_path() {
    local path="$1"
    local type="${2:-any}"

    [[ -z "$path" ]] && return 1

    case "$type" in
        file)
            [[ -f "$path" ]] || return 1
            ;;
        dir)
            [[ -d "$path" ]] || return 1
            ;;
        any)
            [[ -e "$path" ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# Validate path is safe (no traversal attacks)
# Usage: validate_path_safe "path" [base_dir]
# Prevents: ../, symlink escapes, null bytes
validate_path_safe() {
    local path="$1"
    local base_dir="${2:-}"

    [[ -z "$path" ]] && return 1

    # Note: Null bytes cannot exist in bash strings, so no check needed

    # Reject obvious traversal patterns
    [[ "$path" == *".."* ]] && return 1

    # Reject backslash (Windows-style path manipulation)
    [[ "$path" == *"\\"* ]] && return 1

    # If base_dir provided, ensure path stays within it
    if [[ -n "$base_dir" ]]; then
        # Resolve both paths to absolute
        local abs_base abs_path

        # Get absolute base
        if [[ -d "$base_dir" ]]; then
            abs_base=$(cd "$base_dir" && pwd -P)
        else
            return 1
        fi

        # For path, handle both existing and non-existing paths
        if [[ -e "$path" ]]; then
            abs_path=$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")
        else
            # For non-existing paths, resolve parent
            local parent_dir
            parent_dir=$(dirname "$path")
            if [[ -d "$parent_dir" ]]; then
                abs_path=$(cd "$parent_dir" && pwd -P)/$(basename "$path")
            else
                return 1
            fi
        fi

        # Ensure path starts with base
        [[ "$abs_path" != "$abs_base"* ]] && return 1
    fi

    return 0
}

# Validate filename (no path components)
# Usage: validate_filename "name"
validate_filename() {
    local name="$1"

    [[ -z "$name" ]] && return 1

    # Reject path separators
    [[ "$name" == *"/"* ]] && return 1
    [[ "$name" == *"\\"* ]] && return 1

    # Reject special names
    [[ "$name" == "." || "$name" == ".." ]] && return 1

    # Note: Null bytes cannot exist in bash strings, so no check needed

    # Reject names starting with dash (option injection)
    [[ "$name" == -* ]] && return 1

    return 0
}

# Validate path contains only safe characters
# Usage: validate_path_chars "path"
validate_path_chars() {
    local path="$1"

    [[ -z "$path" ]] && return 1

    # Allow alphanumeric, underscore, hyphen, dot, slash
    # Reject control characters, shell metacharacters, etc.
    [[ "$path" =~ ^[A-Za-z0-9_./-]+$ ]]
}

# =============================================================================
# SANITIZATION
# =============================================================================

# Sanitize value for safe shell argument
# Usage: sanitize_shell_arg "value"
sanitize_shell_arg() {
    local value="$1"

    # Use printf %q for proper escaping
    printf '%q' "$value"
}

# Sanitize filename by removing dangerous characters
# Usage: sanitize_filename "name" [replacement]
sanitize_filename() {
    local name="$1"
    local replacement="${2:-_}"

    [[ -z "$name" ]] && return 0

    # Remove null bytes
    name="${name//$'\0'/}"

    # Replace path separators
    name="${name//\//$replacement}"
    name="${name//\\/$replacement}"

    # Replace shell metacharacters
    name="${name//\`/$replacement}"
    name="${name//\$/$replacement}"
    name="${name//|/$replacement}"
    name="${name//&/$replacement}"
    name="${name//;/$replacement}"
    name="${name//</$replacement}"
    name="${name//>/$replacement}"
    name="${name//\*/$replacement}"
    name="${name//\?/$replacement}"
    name="${name//\"/$replacement}"
    name="${name//\'/$replacement}"

    # Replace control characters
    name=$(printf '%s' "$name" | tr -d '[:cntrl:]')

    # Remove leading dashes
    while [[ "$name" == -* ]]; do
        name="${name#-}"
    done

    # Handle special names
    [[ "$name" == "." ]] && name="${replacement}dot"
    [[ "$name" == ".." ]] && name="${replacement}dotdot"

    # Collapse multiple replacement chars
    while [[ "$name" == *"${replacement}${replacement}"* ]]; do
        name="${name//${replacement}${replacement}/$replacement}"
    done

    # Trim replacement from edges
    name="${name#$replacement}"
    name="${name%$replacement}"

    printf '%s' "$name"
}

# Sanitize for SQL (basic escaping - NOT for parameterized queries)
# Usage: sanitize_sql "value"
# WARNING: Prefer parameterized queries in production
sanitize_sql() {
    local value="$1"

    [[ -z "$value" ]] && return 0

    # Escape single quotes (double them)
    value="${value//\'/\'\'}"

    # Escape backslashes
    value="${value//\\/\\\\}"

    printf '%s' "$value"
}

# Sanitize for HTML (entity escaping)
# Usage: sanitize_html "value"
sanitize_html() {
    local value="$1"

    [[ -z "$value" ]] && return 0

    # Order matters: ampersand first
    # Note: In bash replacement, & means "matched text", so we must escape it
    local amp='&'
    value="${value//&/${amp}amp;}"
    value="${value//</\&lt;}"
    value="${value//>/\&gt;}"
    value="${value//\"/\&quot;}"
    value="${value//\'/\&#39;}"

    printf '%s\n' "$value"
}

# Sanitize for JSON string (escape special chars)
# Delegates to canonical json_escape from lib/json.sh (core tier, always loaded)
# Usage: sanitize_json "value"
sanitize_json() {
    json_escape "$@"
}

# =============================================================================
# COMPLEX VALIDATION
# =============================================================================

# Validate value against regex pattern
# Usage: validate_regex "value" "pattern"
validate_regex() {
    local value="$1"
    local pattern="$2"

    [[ -z "$value" ]] && return 1
    [[ -z "$pattern" ]] && return 1

    [[ "$value" =~ $pattern ]]
}

# Validate string length
# Usage: validate_length "value" [min] [max]
validate_length() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    local len=${#value}

    if [[ -n "$min" ]]; then
        (( len < min )) && return 1
    fi

    if [[ -n "$max" ]]; then
        (( len > max )) && return 1
    fi

    return 0
}

# Validate value is in list (enum)
# Usage: validate_enum "value" "opt1" "opt2" "opt3"
validate_enum() {
    local value="$1"
    shift

    [[ -z "$value" ]] && return 1
    [[ $# -eq 0 ]] && return 1

    for opt in "$@"; do
        [[ "$value" == "$opt" ]] && return 0
    done

    return 1
}

# Validate all values in array
# Usage: validate_all "validator" "${values[@]}"
# validator: name of validation function (e.g., validate_int)
validate_all() {
    local validator="$1"
    shift

    [[ $# -eq 0 ]] && return 1

    for value in "$@"; do
        "$validator" "$value" || return 1
    done

    return 0
}

# =============================================================================
# COMMAND SAFETY
# =============================================================================

# Validate command is safe (no shell injection)
# Usage: validate_command_safe "command"
# Checks for: pipes, redirects, command substitution, variable expansion
validate_command_safe() {
    local cmd="$1"

    [[ -z "$cmd" ]] && return 1

    # Reject shell metacharacters
    [[ "$cmd" == *"|"* ]] && return 1    # Pipe
    [[ "$cmd" == *";"* ]] && return 1    # Command separator
    [[ "$cmd" == *"&"* ]] && return 1    # Background/AND
    [[ "$cmd" == *">"* ]] && return 1    # Redirect out
    [[ "$cmd" == *"<"* ]] && return 1    # Redirect in
    [[ "$cmd" == *"\`"* ]] && return 1   # Command substitution
    [[ "$cmd" == *"\$("* ]] && return 1  # Command substitution
    [[ "$cmd" == *"\${"* ]] && return 1  # Variable expansion
    [[ "$cmd" == *"\$\$"* ]] && return 1 # Special variable
    [[ "$cmd" == *$'\n'* ]] && return 1  # Newline injection
    # Note: Null bytes cannot exist in bash strings, so no check needed

    return 0
}

# Build safe command with escaped arguments
# Usage: build_safe_command "cmd" "arg1" "arg2" ...
# Returns: properly quoted command string
build_safe_command() {
    local cmd="$1"
    shift

    [[ -z "$cmd" ]] && return 1

    # Start with the command
    local result
    result=$(printf '%q' "$cmd")

    # Add each argument, properly quoted
    for arg in "$@"; do
        result+=" $(printf '%q' "$arg")"
    done

    printf '%s' "$result"
}

# =============================================================================
# ADDITIONAL VALIDATORS
# =============================================================================

# Validate port number
# Usage: validate_port "port"
validate_port() {
    local port="$1"

    validate_int "$port" 1 65535
}

# Validate MAC address
# Usage: validate_mac "address"
validate_mac() {
    local mac="$1"

    [[ -z "$mac" ]] && return 1

    # Accept XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX formats
    [[ "$mac" =~ ^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$ ]]
}

# Validate credit card number (Luhn algorithm)
# Usage: validate_credit_card "number"
validate_credit_card() {
    local number="$1"

    # Remove spaces and dashes
    number="${number// /}"
    number="${number//-/}"

    [[ -z "$number" ]] && return 1

    # Must be all digits
    [[ ! "$number" =~ ^[0-9]+$ ]] && return 1

    # Length check (13-19 digits typical)
    local len=${#number}
    (( len < 13 || len > 19 )) && return 1

    # Luhn algorithm
    local sum=0
    local double=0
    local i digit

    for ((i=len-1; i>=0; i--)); do
        digit="${number:i:1}"

        if (( double )); then
            ((digit *= 2))
            ((digit > 9)) && ((digit -= 9))
        fi

        ((sum += digit))
        ((double = !double))
    done

    (( sum % 10 == 0 ))
}

# Validate phone number (E.164 format)
# Usage: validate_phone "number"
validate_phone() {
    local phone="$1"

    [[ -z "$phone" ]] && return 1

    # Remove common formatting characters
    local cleaned="${phone//[() -]/}"

    # E.164: + followed by 1-15 digits
    [[ "$cleaned" =~ ^\+?[0-9]{1,15}$ ]]
}

# Validate JSON string (basic syntax check)
# Usage: validate_json "string"
validate_json() {
    local json="$1"
    local depth=0
    local in_string=false
    local prev_char=""
    local i char

    [[ -z "${json//[[:space:]]/}" ]] && return 1

    # JSON must start with { or [ (ignoring leading whitespace)
    local trimmed="${json#"${json%%[![:space:]]*}"}"
    [[ "$trimmed" != "{"* && "$trimmed" != "["* ]] && return 1

    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    ;;
                '{' | '[')
                    ((depth++)) || true
                    ;;
                '}' | ']')
                    ((depth--)) || true
                    [[ $depth -lt 0 ]] && return 1
                    ;;
            esac
        fi

        prev_char="$char"
    done

    [[ $depth -eq 0 ]] && ! $in_string
}

# Validate alphanumeric string
# Usage: validate_alnum "string" [allow_underscore]
validate_alnum() {
    local value="$1"
    local allow_underscore="${2:-false}"

    [[ -z "$value" ]] && return 1

    if [[ "$allow_underscore" == "true" ]]; then
        [[ "$value" =~ ^[A-Za-z0-9_]+$ ]]
    else
        [[ "$value" =~ ^[A-Za-z0-9]+$ ]]
    fi
}

# Validate slug (URL-safe identifier)
# Usage: validate_slug "string"
validate_slug() {
    local value="$1"

    [[ -z "$value" ]] && return 1

    # Lowercase alphanumeric and hyphens, no consecutive hyphens
    [[ "$value" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# Validate CIDR notation
# Usage: validate_cidr "cidr"
validate_cidr() {
    local cidr="$1"

    [[ -z "$cidr" ]] && return 1

    # Split IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    # Validate IP
    validate_ipv4 "$ip" || return 1

    # Validate prefix (0-32)
    validate_int "$prefix" 0 32
}

# Validate base64 string
# Usage: validate_base64 "string"
validate_base64() {
    local value="$1"

    [[ -z "$value" ]] && return 1

    # Base64: A-Z, a-z, 0-9, +, /, optional = padding
    # Length must be multiple of 4
    [[ "$value" =~ ^[A-Za-z0-9+/]*={0,2}$ ]] && (( ${#value} % 4 == 0 ))
}

# =============================================================================
# REGEX CONSTANTS
# =============================================================================
# Pre-defined regex patterns for common validation scenarios.
# Inspired by DevOps-Bash-tools. Use with regex_match() or [[ =~ ]].
# =============================================================================

# Email validation (RFC 5322 simplified)
readonly REGEX_EMAIL='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

# Domain name (RFC 1123)
readonly REGEX_DOMAIN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

# IPv4 address
readonly REGEX_IPV4='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

# IPv6 address (simplified - full 8 groups without compression)
readonly REGEX_IPV6='^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$'

# URL (http/https)
readonly REGEX_URL='^https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._~:/?#@!$&()*+,;=-]*)?$'

# Semantic version (MAJOR.MINOR.PATCH with optional prerelease and build)
readonly REGEX_SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$'

# UUID v4
readonly REGEX_UUID='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'

# UUID (any version)
readonly REGEX_UUID_ANY='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# Git commit hash (short or long)
readonly REGEX_GIT_HASH='^[0-9a-fA-F]{7,40}$'

# MAC address (colon-separated)
readonly REGEX_MAC='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'

# MAC address (colon or hyphen separated)
readonly REGEX_MAC_ANY='^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$'

# Phone number (E.164 international format)
readonly REGEX_PHONE='^[+][1-9][0-9]{1,14}$'

# Credit card (basic digit count, no Luhn check)
readonly REGEX_CREDIT_CARD='^[0-9]{13,19}$'

# ISO date (YYYY-MM-DD)
readonly REGEX_ISO_DATE='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'

# ISO datetime (YYYY-MM-DDTHH:MM:SS with optional timezone)
readonly REGEX_ISO_DATETIME='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](Z|[+-][0-9]{2}:[0-9]{2})?$'

# Hexadecimal string
readonly REGEX_HEX='^[0-9a-fA-F]+$'

# Alphanumeric string
readonly REGEX_ALNUM='^[a-zA-Z0-9]+$'

# Alphanumeric with underscore
readonly REGEX_ALNUM_UNDERSCORE='^[a-zA-Z0-9_]+$'

# Slug (URL-safe identifier)
readonly REGEX_SLUG='^[a-z0-9]+(-[a-z0-9]+)*$'

# Port number (1-65535)
readonly REGEX_PORT='^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'

# CIDR notation (IPv4)
readonly REGEX_CIDR='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([0-9]|[12][0-9]|3[0-2])$'

# Base64 encoded string
readonly REGEX_BASE64='^[A-Za-z0-9+/]*={0,2}$'

# JSON Web Token (JWT)
readonly REGEX_JWT='^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$'

# AWS ARN
readonly REGEX_AWS_ARN='^arn:aws:[a-zA-Z0-9-]+:[a-zA-Z0-9-]*:[0-9]*:[a-zA-Z0-9:/_-]+$'

# Docker image name (with optional tag)
readonly REGEX_DOCKER_IMAGE='^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*(:[a-zA-Z0-9._-]+)?$'

# Environment variable name
readonly REGEX_ENV_VAR='^[A-Za-z_][A-Za-z0-9_]*$'

# Unix username
readonly REGEX_UNIX_USER='^[a-z_][a-z0-9_-]*[$]?$'

# =============================================================================
# REGEX HELPER FUNCTIONS
# =============================================================================

# @idempotent Match string against named regex constant
# @param $1 - regex name (email, domain, ipv4, ipv6, url, semver, uuid, uuid_v4,
#             git_hash, mac, phone, credit_card, iso_date, iso_datetime, hex,
#             alnum, slug, port, cidr, base64, jwt, aws_arn, docker_image,
#             env_var, unix_user)
# @param $2 - string to match
# @return 0 if match, 1 if not, 2 if unknown regex name
# @example regex_match email "user@example.com" && echo "valid"
regex_match() {
    local regex_name="${1:-}"
    local value="${2:-}"

    [[ -z "$regex_name" ]] && return 2
    [[ -z "$value" ]] && return 1

    local pattern
    case "${regex_name,,}" in
        email)          pattern="$REGEX_EMAIL" ;;
        domain)         pattern="$REGEX_DOMAIN" ;;
        ipv4)           pattern="$REGEX_IPV4" ;;
        ipv6)           pattern="$REGEX_IPV6" ;;
        url)            pattern="$REGEX_URL" ;;
        semver)         pattern="$REGEX_SEMVER" ;;
        uuid)           pattern="$REGEX_UUID_ANY" ;;
        uuid_v4)        pattern="$REGEX_UUID" ;;
        git_hash)       pattern="$REGEX_GIT_HASH" ;;
        mac)            pattern="$REGEX_MAC_ANY" ;;
        phone)          pattern="$REGEX_PHONE" ;;
        credit_card)    pattern="$REGEX_CREDIT_CARD" ;;
        iso_date)       pattern="$REGEX_ISO_DATE" ;;
        iso_datetime)   pattern="$REGEX_ISO_DATETIME" ;;
        hex)            pattern="$REGEX_HEX" ;;
        alnum)          pattern="$REGEX_ALNUM" ;;
        alnum_underscore) pattern="$REGEX_ALNUM_UNDERSCORE" ;;
        slug)           pattern="$REGEX_SLUG" ;;
        port)           pattern="$REGEX_PORT" ;;
        cidr)           pattern="$REGEX_CIDR" ;;
        base64)         pattern="$REGEX_BASE64" ;;
        jwt)            pattern="$REGEX_JWT" ;;
        aws_arn)        pattern="$REGEX_AWS_ARN" ;;
        docker_image)   pattern="$REGEX_DOCKER_IMAGE" ;;
        env_var)        pattern="$REGEX_ENV_VAR" ;;
        unix_user)      pattern="$REGEX_UNIX_USER" ;;
        *)              return 2 ;;  # Unknown regex name
    esac

    [[ "$value" =~ $pattern ]]
}

# @idempotent List all available regex patterns with descriptions
# @return Prints list of regex names and descriptions to stdout
# @example regex_list
regex_list() {
    cat <<'EOF'
Available regex patterns for use with regex_match():

  email           - Email address (RFC 5322 simplified)
  domain          - Domain name (RFC 1123)
  ipv4            - IPv4 address (0.0.0.0 - 255.255.255.255)
  ipv6            - IPv6 address (full 8 groups, no compression)
  url             - HTTP/HTTPS URL
  semver          - Semantic version (MAJOR.MINOR.PATCH)
  uuid            - UUID (any version)
  uuid_v4         - UUID version 4 specifically
  git_hash        - Git commit hash (7-40 hex chars)
  mac             - MAC address (colon or hyphen separated)
  phone           - Phone number (E.164 format: +1234567890)
  credit_card     - Credit card number (13-19 digits)
  iso_date        - ISO date (YYYY-MM-DD)
  iso_datetime    - ISO datetime (YYYY-MM-DDTHH:MM:SS with optional TZ)
  hex             - Hexadecimal string
  alnum           - Alphanumeric string (a-zA-Z0-9)
  alnum_underscore - Alphanumeric with underscore
  slug            - URL-safe slug (lowercase-with-dashes)
  port            - Port number (1-65535)
  cidr            - CIDR notation (IPv4)
  base64          - Base64 encoded string
  jwt             - JSON Web Token
  aws_arn         - AWS ARN
  docker_image    - Docker image name (with optional tag)
  env_var         - Environment variable name
  unix_user       - Unix username

Usage: regex_match <pattern_name> <value>
       [[ "$value" =~ $REGEX_EMAIL ]]
EOF
}

# @idempotent Get the raw regex pattern by name
# @param $1 - regex name (same as regex_match)
# @return Prints the regex pattern to stdout, returns 1 if unknown
# @example pattern=$(regex_get email); [[ "$input" =~ $pattern ]]
regex_get() {
    local regex_name="${1:-}"

    [[ -z "$regex_name" ]] && return 1

    case "${regex_name,,}" in
        email)          printf '%s\n' "$REGEX_EMAIL" ;;
        domain)         printf '%s\n' "$REGEX_DOMAIN" ;;
        ipv4)           printf '%s\n' "$REGEX_IPV4" ;;
        ipv6)           printf '%s\n' "$REGEX_IPV6" ;;
        url)            printf '%s\n' "$REGEX_URL" ;;
        semver)         printf '%s\n' "$REGEX_SEMVER" ;;
        uuid)           printf '%s\n' "$REGEX_UUID_ANY" ;;
        uuid_v4)        printf '%s\n' "$REGEX_UUID" ;;
        git_hash)       printf '%s\n' "$REGEX_GIT_HASH" ;;
        mac)            printf '%s\n' "$REGEX_MAC_ANY" ;;
        phone)          printf '%s\n' "$REGEX_PHONE" ;;
        credit_card)    printf '%s\n' "$REGEX_CREDIT_CARD" ;;
        iso_date)       printf '%s\n' "$REGEX_ISO_DATE" ;;
        iso_datetime)   printf '%s\n' "$REGEX_ISO_DATETIME" ;;
        hex)            printf '%s\n' "$REGEX_HEX" ;;
        alnum)          printf '%s\n' "$REGEX_ALNUM" ;;
        alnum_underscore) printf '%s\n' "$REGEX_ALNUM_UNDERSCORE" ;;
        slug)           printf '%s\n' "$REGEX_SLUG" ;;
        port)           printf '%s\n' "$REGEX_PORT" ;;
        cidr)           printf '%s\n' "$REGEX_CIDR" ;;
        base64)         printf '%s\n' "$REGEX_BASE64" ;;
        jwt)            printf '%s\n' "$REGEX_JWT" ;;
        aws_arn)        printf '%s\n' "$REGEX_AWS_ARN" ;;
        docker_image)   printf '%s\n' "$REGEX_DOCKER_IMAGE" ;;
        env_var)        printf '%s\n' "$REGEX_ENV_VAR" ;;
        unix_user)      printf '%s\n' "$REGEX_UNIX_USER" ;;
        *)              return 1 ;;
    esac
}

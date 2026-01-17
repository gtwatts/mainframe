#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Universal Input Validation
# =============================================================================
# Description: Validate inputs before operations to prevent common failures
# Category:    validation
# WOW Factor:  10/10
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
#
# Provides comprehensive input validation for:
# - Files (exists, readable, writable, executable, non-empty)
# - Directories (exists, readable, writable)
# - Numbers (integer, positive, range)
# - Strings (non-empty, pattern match, length)
# - Paths (safe characters, normalized)
#
# Usage:
#   mainframe validate file /path/to/file
#   mainframe validate dir /path/to/dir
#   mainframe validate number 42
#   mainframe validate url https://example.com
#
# =============================================================================

set -euo pipefail

# Source MAINFRAME libraries
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="validate-input"
readonly SCRIPT_VERSION="1.0.0"

# Exit codes for specific validation failures
readonly VALID_OK=0
readonly VALID_EMPTY=10
readonly VALID_NOT_FOUND=11
readonly VALID_NOT_READABLE=12
readonly VALID_NOT_WRITABLE=13
readonly VALID_NOT_EXECUTABLE=14
readonly VALID_EMPTY_FILE=15
readonly VALID_NOT_NUMBER=16
readonly VALID_OUT_OF_RANGE=17
readonly VALID_PATTERN_MISMATCH=18
readonly VALID_UNSAFE_PATH=19

# =============================================================================
# FILE VALIDATION
# =============================================================================

validate_file() {
    local file="$1"
    local checks="${2:-exists}"  # exists, readable, writable, executable, nonempty

    # Check if argument is empty
    if [[ -z "$file" ]]; then
        echo "Error: Empty file path provided"
        return $VALID_EMPTY
    fi

    # Check file exists
    if [[ ! -e "$file" ]]; then
        echo "Error: File not found: $file"
        return $VALID_NOT_FOUND
    fi

    # Check it's a regular file (not directory, symlink, etc)
    if [[ ! -f "$file" ]]; then
        echo "Error: Not a regular file: $file"
        return $VALID_NOT_FOUND
    fi

    # Apply additional checks
    IFS=',' read -ra check_array <<< "$checks"
    for check in "${check_array[@]}"; do
        case "$check" in
            exists)
                # Already checked above
                ;;
            readable|read|r)
                if [[ ! -r "$file" ]]; then
                    echo "Error: File not readable: $file"
                    return $VALID_NOT_READABLE
                fi
                ;;
            writable|write|w)
                if [[ ! -w "$file" ]]; then
                    echo "Error: File not writable: $file"
                    return $VALID_NOT_WRITABLE
                fi
                ;;
            executable|exec|x)
                if [[ ! -x "$file" ]]; then
                    echo "Error: File not executable: $file"
                    return $VALID_NOT_EXECUTABLE
                fi
                ;;
            nonempty|content)
                if [[ ! -s "$file" ]]; then
                    echo "Error: File is empty: $file"
                    return $VALID_EMPTY_FILE
                fi
                ;;
            *)
                echo "Warning: Unknown check: $check"
                ;;
        esac
    done

    echo "Valid: $file"
    return $VALID_OK
}

# =============================================================================
# DIRECTORY VALIDATION
# =============================================================================

validate_dir() {
    local dir="$1"
    local checks="${2:-exists}"  # exists, readable, writable

    # Check if argument is empty
    if [[ -z "$dir" ]]; then
        echo "Error: Empty directory path provided"
        return $VALID_EMPTY
    fi

    # Check directory exists
    if [[ ! -e "$dir" ]]; then
        echo "Error: Directory not found: $dir"
        return $VALID_NOT_FOUND
    fi

    # Check it's actually a directory
    if [[ ! -d "$dir" ]]; then
        echo "Error: Not a directory: $dir"
        return $VALID_NOT_FOUND
    fi

    # Apply additional checks
    IFS=',' read -ra check_array <<< "$checks"
    for check in "${check_array[@]}"; do
        case "$check" in
            exists)
                # Already checked above
                ;;
            readable|read|r)
                if [[ ! -r "$dir" ]]; then
                    echo "Error: Directory not readable: $dir"
                    return $VALID_NOT_READABLE
                fi
                ;;
            writable|write|w)
                if [[ ! -w "$dir" ]]; then
                    echo "Error: Directory not writable: $dir"
                    return $VALID_NOT_WRITABLE
                fi
                ;;
            *)
                echo "Warning: Unknown check: $check"
                ;;
        esac
    done

    echo "Valid: $dir"
    return $VALID_OK
}

# =============================================================================
# NUMBER VALIDATION
# =============================================================================

validate_number() {
    local value="$1"
    local constraints="${2:-integer}"  # integer, positive, range:min:max

    # Check if argument is empty
    if [[ -z "$value" ]]; then
        echo "Error: Empty value provided"
        return $VALID_EMPTY
    fi

    # Check if it's a valid integer (including negative)
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "Error: Not a valid integer: $value"
        return $VALID_NOT_NUMBER
    fi

    # Apply additional checks
    IFS=',' read -ra check_array <<< "$constraints"
    for check in "${check_array[@]}"; do
        case "$check" in
            integer)
                # Already checked above
                ;;
            positive|pos)
                if [[ "$value" -lt 0 ]]; then
                    echo "Error: Value must be positive: $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            negative|neg)
                if [[ "$value" -ge 0 ]]; then
                    echo "Error: Value must be negative: $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            nonzero)
                if [[ "$value" -eq 0 ]]; then
                    echo "Error: Value must be non-zero: $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            range:*)
                # Parse range:min:max
                local range_part="${check#range:}"
                local min="${range_part%%:*}"
                local max="${range_part##*:}"

                if [[ "$value" -lt "$min" ]] || [[ "$value" -gt "$max" ]]; then
                    echo "Error: Value out of range ($min-$max): $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            min:*)
                local min="${check#min:}"
                if [[ "$value" -lt "$min" ]]; then
                    echo "Error: Value below minimum ($min): $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            max:*)
                local max="${check#max:}"
                if [[ "$value" -gt "$max" ]]; then
                    echo "Error: Value above maximum ($max): $value"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            *)
                echo "Warning: Unknown constraint: $check"
                ;;
        esac
    done

    echo "Valid: $value"
    return $VALID_OK
}

# =============================================================================
# STRING VALIDATION
# =============================================================================

validate_string() {
    local value="$1"
    local constraints="${2:-nonempty}"  # nonempty, length:min:max, pattern:regex

    # Apply checks
    IFS=',' read -ra check_array <<< "$constraints"
    for check in "${check_array[@]}"; do
        case "$check" in
            nonempty|required)
                if [[ -z "$value" ]]; then
                    echo "Error: Empty string not allowed"
                    return $VALID_EMPTY
                fi
                ;;
            length:*)
                local length_part="${check#length:}"
                local min="${length_part%%:*}"
                local max="${length_part##*:}"
                local len=${#value}

                if [[ "$len" -lt "$min" ]] || [[ "$len" -gt "$max" ]]; then
                    echo "Error: String length ($len) out of range ($min-$max)"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            minlen:*)
                local min="${check#minlen:}"
                local len=${#value}
                if [[ "$len" -lt "$min" ]]; then
                    echo "Error: String too short (min: $min, got: $len)"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            maxlen:*)
                local max="${check#maxlen:}"
                local len=${#value}
                if [[ "$len" -gt "$max" ]]; then
                    echo "Error: String too long (max: $max, got: $len)"
                    return $VALID_OUT_OF_RANGE
                fi
                ;;
            alphanumeric|alnum)
                if ! [[ "$value" =~ ^[a-zA-Z0-9]+$ ]]; then
                    echo "Error: String must be alphanumeric"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            alpha)
                if ! [[ "$value" =~ ^[a-zA-Z]+$ ]]; then
                    echo "Error: String must contain only letters"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            *)
                echo "Warning: Unknown constraint: $check"
                ;;
        esac
    done

    echo "Valid: $value"
    return $VALID_OK
}

# =============================================================================
# PATH VALIDATION
# =============================================================================

validate_path() {
    local path="$1"
    local checks="${2:-safe}"  # safe, absolute, relative, notraversal

    # Check if argument is empty
    if [[ -z "$path" ]]; then
        echo "Error: Empty path provided"
        return $VALID_EMPTY
    fi

    # Apply checks
    IFS=',' read -ra check_array <<< "$checks"
    for check in "${check_array[@]}"; do
        case "$check" in
            safe)
                # Check for dangerous characters
                if [[ "$path" =~ [[:cntrl:]] ]]; then
                    echo "Error: Path contains control characters"
                    return $VALID_UNSAFE_PATH
                fi
                # Check for null bytes
                if [[ "$path" == *$'\0'* ]]; then
                    echo "Error: Path contains null bytes"
                    return $VALID_UNSAFE_PATH
                fi
                ;;
            absolute|abs)
                if [[ "$path" != /* ]]; then
                    echo "Error: Path must be absolute: $path"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            relative|rel)
                if [[ "$path" == /* ]]; then
                    echo "Error: Path must be relative: $path"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            notraversal|noparent)
                if [[ "$path" == *".."* ]]; then
                    echo "Error: Path traversal not allowed: $path"
                    return $VALID_UNSAFE_PATH
                fi
                ;;
            nospace)
                if [[ "$path" == *" "* ]]; then
                    echo "Error: Path contains spaces: $path"
                    return $VALID_UNSAFE_PATH
                fi
                ;;
            *)
                echo "Warning: Unknown check: $check"
                ;;
        esac
    done

    echo "Valid: $path"
    return $VALID_OK
}

# =============================================================================
# URL VALIDATION
# =============================================================================

validate_url() {
    local url="$1"
    local checks="${2:-format}"  # format, reachable, https

    # Check if argument is empty
    if [[ -z "$url" ]]; then
        echo "Error: Empty URL provided"
        return $VALID_EMPTY
    fi

    # Apply checks
    IFS=',' read -ra check_array <<< "$checks"
    for check in "${check_array[@]}"; do
        case "$check" in
            format)
                # Basic URL format check
                if ! [[ "$url" =~ ^https?:// ]]; then
                    echo "Error: Invalid URL format: $url"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            https|secure)
                if ! [[ "$url" =~ ^https:// ]]; then
                    echo "Error: URL must use HTTPS: $url"
                    return $VALID_PATTERN_MISMATCH
                fi
                ;;
            reachable|live)
                if ! curl -sf --max-time 10 -o /dev/null "$url" 2>/dev/null; then
                    echo "Error: URL not reachable: $url"
                    return $VALID_NOT_FOUND
                fi
                ;;
            *)
                echo "Warning: Unknown check: $check"
                ;;
        esac
    done

    echo "Valid: $url"
    return $VALID_OK
}

# =============================================================================
# COMMAND VALIDATION
# =============================================================================

validate_command() {
    local cmd="$1"

    # Check if argument is empty
    if [[ -z "$cmd" ]]; then
        echo "Error: Empty command provided"
        return $VALID_EMPTY
    fi

    # Check if command exists
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Command not found: $cmd"
        return $VALID_NOT_FOUND
    fi

    echo "Valid: $cmd ($(command -v "$cmd"))"
    return $VALID_OK
}

# =============================================================================
# BATCH VALIDATION
# =============================================================================

validate_batch() {
    local failures=0
    local total=0

    while IFS=: read -r type value checks; do
        total=$((total + 1))

        case "$type" in
            file)
                if ! validate_file "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            dir)
                if ! validate_dir "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            number)
                if ! validate_number "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            string)
                if ! validate_string "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            path)
                if ! validate_path "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            url)
                if ! validate_url "$value" "$checks"; then
                    failures=$((failures + 1))
                fi
                ;;
            command)
                if ! validate_command "$value"; then
                    failures=$((failures + 1))
                fi
                ;;
            *)
                echo "Warning: Unknown type: $type"
                failures=$((failures + 1))
                ;;
        esac
    done

    if [[ $failures -gt 0 ]]; then
        echo "Validation failed: $failures/$total checks failed"
        return 1
    fi

    echo "All $total validations passed"
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    cat << EOF
${CLR_BOLD}$SCRIPT_NAME${CLR_RESET} - Universal Input Validation

${CLR_BOLD}Usage:${CLR_RESET}
  mainframe $SCRIPT_NAME <type> <value> [checks]
  mainframe $SCRIPT_NAME batch < input.txt

${CLR_BOLD}Types:${CLR_RESET}
  file      Validate file (exists, readable, writable, executable, nonempty)
  dir       Validate directory (exists, readable, writable)
  number    Validate number (integer, positive, range:min:max)
  string    Validate string (nonempty, length:min:max, alphanumeric)
  path      Validate path (safe, absolute, relative, notraversal)
  url       Validate URL (format, https, reachable)
  command   Validate command exists

${CLR_BOLD}Examples:${CLR_RESET}
  # Check file exists and is readable
  mainframe $SCRIPT_NAME file /etc/passwd exists,readable

  # Check directory is writable
  mainframe $SCRIPT_NAME dir /tmp exists,writable

  # Validate port number
  mainframe $SCRIPT_NAME number 8080 integer,positive,range:1:65535

  # Validate non-empty string
  mainframe $SCRIPT_NAME string "hello" nonempty,minlen:1

  # Check URL is reachable
  mainframe $SCRIPT_NAME url https://example.com format,reachable

  # Batch validation
  echo "file:/etc/passwd:readable" | mainframe $SCRIPT_NAME batch

${CLR_BOLD}Exit Codes:${CLR_RESET}
  0   Valid
  10  Empty input
  11  Not found
  12  Not readable
  13  Not writable
  14  Not executable
  15  Empty file
  16  Not a number
  17  Out of range
  18  Pattern mismatch
  19  Unsafe path

${CLR_DIM}YO JOE!${CLR_RESET}
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 0
    fi

    local type="$1"
    shift

    case "$type" in
        file)
            validate_file "$@"
            ;;
        dir|directory)
            validate_dir "$@"
            ;;
        number|num|int)
            validate_number "$@"
            ;;
        string|str)
            validate_string "$@"
            ;;
        path)
            validate_path "$@"
            ;;
        url)
            validate_url "$@"
            ;;
        command|cmd)
            validate_command "$@"
            ;;
        batch)
            validate_batch
            ;;
        -h|--help)
            show_help
            ;;
        *)
            die "$EXIT_USAGE" "Unknown validation type: $type"
            ;;
    esac
}

main "$@"

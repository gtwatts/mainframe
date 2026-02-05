#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/guard_enhanced.sh - Enhanced Security Guards
# =============================================================================
# Description: Additional security validations beyond existing guard.sh.
#              Provides defense-in-depth for AI-generated code execution.
#              Focuses on injection prevention, path safety, and input validation.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GUARD_ENHANCED_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GUARD_ENHANCED_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Strict mode for guards (fail on any violation)
GUARD_ENHANCED_STRICT="${GUARD_ENHANCED_STRICT:-0}"

# Log security events
GUARD_ENHANCED_LOG="${GUARD_ENHANCED_LOG:-1}"

# Maximum pattern length for ReDoS check
GUARD_MAX_REGEX_LENGTH="${GUARD_MAX_REGEX_LENGTH:-1000}"

# Maximum upload size (MB)
GUARD_MAX_UPLOAD_MB="${GUARD_MAX_UPLOAD_MB:-100}"

# Allowed URL schemes
GUARD_ALLOWED_URL_SCHEMES="${GUARD_ALLOWED_URL_SCHEMES:-https http}"

# =============================================================================
# LOGGING HELPERS
# =============================================================================

_guard_e_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[guard-enhanced] $*"
    elif [[ "$GUARD_ENHANCED_LOG" == "1" ]]; then
        printf '[%s] [guard-enhanced] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "$*" >&2
    fi
}

_guard_e_error() { _guard_e_log error "$@"; }
_guard_e_warn() { _guard_e_log warn "$@"; }
_guard_e_info() { _guard_e_log info "$@"; }
_guard_e_debug() { _guard_e_log debug "$@"; }

# =============================================================================
# PATH TRAVERSAL DETECTION
# =============================================================================

# Detect path traversal attempts including encoded variants
# Usage: guard_path_traversal --path "..."
# Returns: 0 if safe, 1 if traversal detected
guard_path_traversal() {
    local path=""
    local strict="${GUARD_ENHANCED_STRICT}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                path="$2"
                shift 2
                ;;
            --strict)
                strict=1
                shift
                ;;
            *)
                path="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$path" ]]; then
        _guard_e_error "guard_path_traversal: empty path"
        return 1
    fi

    # Direct traversal patterns
    if [[ "$path" == *'../'* ]] || [[ "$path" == *'/..'* ]]; then
        _guard_e_error "Path traversal detected (dot-dot): $path"
        return 1
    fi

    # shellcheck disable=SC1003
    if [[ "$path" == *'..\'* ]] || [[ "$path" == *'\..'* ]]; then
        _guard_e_error "Path traversal detected (Windows): $path"
        return 1
    fi

    # Double-dot without separator
    if [[ "$path" == *'/..'* ]] || [[ "$path" == '..'/* ]]; then
        _guard_e_error "Path traversal detected: $path"
        return 1
    fi

    # URL-encoded traversal (single encoding)
    if [[ "$path" == *'%2e%2e%2f'* ]] || [[ "$path" == *'%2E%2E%2F'* ]]; then
        _guard_e_error "Path traversal detected (URL-encoded): $path"
        return 1
    fi

    if [[ "$path" == *'%2e%2e'* ]] || [[ "$path" == *'%2E%2E'* ]]; then
        _guard_e_error "Path traversal detected (partial encoding): $path"
        return 1
    fi

    # Double URL-encoded
    if [[ "$path" == *'%252e%252e'* ]] || [[ "$path" == *'%252E%252E'* ]]; then
        _guard_e_error "Path traversal detected (double-encoded): $path"
        return 1
    fi

    if [[ "$path" == *'..%252f'* ]] || [[ "$path" == *'..%252F'* ]]; then
        _guard_e_error "Path traversal detected (mixed encoding): $path"
        return 1
    fi

    # Unicode/UTF-8 encoding tricks
    if [[ "$path" == *'%c0%ae'* ]] || [[ "$path" == *'%C0%AE'* ]]; then
        _guard_e_error "Path traversal detected (UTF-8): $path"
        return 1
    fi

    # Null byte injection (path truncation)
    if [[ "$path" == *'%00'* ]]; then
        _guard_e_error "Null byte detected in path: $path"
        return 1
    fi

    # Absolute path to sensitive locations (strict mode)
    if [[ "$strict" == "1" ]]; then
        local sensitive=('/etc/passwd' '/etc/shadow' '/root' '/home' '/var/log')
        for sens in "${sensitive[@]}"; do
            if [[ "$path" == "$sens"* ]]; then
                _guard_e_warn "Access to sensitive path: $path"
                if [[ "$GUARD_ENHANCED_STRICT" == "1" ]]; then
                    return 1
                fi
            fi
        done
    fi

    _guard_e_debug "Path passed traversal check: $path"
    return 0
}

# =============================================================================
# COMMAND INJECTION DETECTION
# =============================================================================

# Detect command injection patterns
# Usage: guard_command_injection --cmd "..."
# Returns: 0 if safe, 1 if injection detected
guard_command_injection() {
    local cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cmd)
                cmd="$2"
                shift 2
                ;;
            *)
                cmd="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        _guard_e_error "guard_command_injection: empty command"
        return 1
    fi

    # Command substitution
    # shellcheck disable=SC2016
    if [[ "$cmd" == *'$('* ]] && [[ "$cmd" == *')'* ]]; then
        _guard_e_error "Command substitution detected: \$()"
        return 1
    fi

    if [[ "$cmd" == *'`'* ]]; then
        _guard_e_error "Command substitution detected: backticks"
        return 1
    fi

    # Command chaining
    if [[ "$cmd" == *';'* ]]; then
        _guard_e_error "Command chaining detected: semicolon"
        return 1
    fi

    if [[ "$cmd" == *'&&'* ]]; then
        _guard_e_error "Command chaining detected: &&"
        return 1
    fi

    if [[ "$cmd" == *'||'* ]]; then
        _guard_e_error "Command chaining detected: ||"
        return 1
    fi

    # Pipes
    if [[ "$cmd" == *'|'* ]]; then
        _guard_e_error "Pipe detected: |"
        return 1
    fi

    # Redirections
    if [[ "$cmd" == *'>'* ]] || [[ "$cmd" == *'<'* ]]; then
        _guard_e_error "Redirection detected"
        return 1
    fi

    # Background execution
    if [[ "$cmd" == *'&'* ]]; then
        _guard_e_error "Background execution detected: &"
        return 1
    fi

    # IFS manipulation
    if [[ "$cmd" == *'${IFS}'* ]] || [[ "$cmd" == *'$IFS'* ]]; then
        _guard_e_error "IFS manipulation detected"
        return 1
    fi

    # Variable expansion tricks
    if [[ "$cmd" == *'${!'* ]]; then
        _guard_e_error "Indirect variable expansion detected"
        return 1
    fi

    # Brace expansion abuse
    if [[ "$cmd" =~ \{[^}]+,[^}]+\}.* ]]; then
        _guard_e_error "Brace expansion detected"
        return 1
    fi

    # Newline injection
    if [[ "$cmd" == *$'\n'* ]]; then
        _guard_e_error "Newline in command detected"
        return 1
    fi

    _guard_e_debug "Command passed injection check"
    return 0
}

# =============================================================================
# SQL INJECTION DETECTION
# =============================================================================

# Basic SQL injection detection
# Usage: guard_sql_injection --query "..."
# Returns: 0 if safe, 1 if injection detected
guard_sql_injection() {
    local query=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query)
                query="$2"
                shift 2
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$query" ]]; then
        return 0  # Empty query is safe
    fi

    local upper_query
    upper_query=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    # Classic patterns
    if [[ "$upper_query" == *'; DROP'* ]] || [[ "$upper_query" == *';DROP'* ]]; then
        _guard_e_error "SQL injection detected: DROP statement"
        return 1
    fi

    if [[ "$upper_query" == *'; DELETE'* ]] || [[ "$upper_query" == *';DELETE'* ]]; then
        _guard_e_error "SQL injection detected: DELETE statement"
        return 1
    fi

    # UNION-based injection
    if [[ "$upper_query" == *'UNION SELECT'* ]] || [[ "$upper_query" == *'UNION  SELECT'* ]]; then
        _guard_e_error "SQL injection detected: UNION SELECT"
        return 1
    fi

    if [[ "$upper_query" == *'UNION ALL SELECT'* ]]; then
        _guard_e_error "SQL injection detected: UNION ALL SELECT"
        return 1
    fi

    # Comment-based injection
    if [[ "$query" == *'--'* ]] || [[ "$query" == *'/*'* ]] || [[ "$query" == *'#'* ]]; then
        _guard_e_error "SQL injection detected: comment sequence"
        return 1
    fi

    # OR-based authentication bypass
    if [[ "$upper_query" == *' OR '*'*=*'* ]] || [[ "$upper_query" == *' OR 1=1'* ]]; then
        _guard_e_error "SQL injection detected: OR-based bypass"
        return 1
    fi

    if [[ "$upper_query" == *' AND '*'*=*'* ]]; then
        _guard_e_error "SQL injection detected: AND-based injection"
        return 1
    fi

    # Stacked queries (multiple statements)
    if [[ "$query" == *';'*'SELECT'* ]] || [[ "$query" == *';'*'INSERT'* ]] || \
       [[ "$query" == *';'*'UPDATE'* ]] || [[ "$query" == *';'*'DELETE'* ]]; then
        _guard_e_error "SQL injection detected: stacked queries"
        return 1
    fi

    # Time-based blind injection
    if [[ "$upper_query" == *'SLEEP('* ]] || [[ "$upper_query" == *'BENCHMARK('* ]]; then
        _guard_e_error "SQL injection detected: time-based function"
        return 1
    fi

    # Error-based injection
    if [[ "$upper_query" == *'EXTRACTVALUE('* ]] || [[ "$upper_query" == *'UPDATEXML('* ]]; then
        _guard_e_error "SQL injection detected: error-based function"
        return 1
    fi

    _guard_e_debug "Query passed SQL injection check"
    return 0
}

# =============================================================================
# NULL BYTE INJECTION
# =============================================================================

# Detect null byte injection attempts
# Usage: guard_null_byte --input "..."
# Returns: 0 if safe, 1 if null byte detected
guard_null_byte() {
    local input=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input="$2"
                shift 2
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$input" ]]; then
        return 0
    fi

    # URL-encoded null byte
    if [[ "$input" == *'%00'* ]]; then
        _guard_e_error "Null byte detected (URL-encoded): %00"
        return 1
    fi

    # Hex-encoded null byte
    if [[ "$input" == *'\x00'* ]] || [[ "$input" == *'\\x00'* ]]; then
        _guard_e_error "Null byte detected (hex-encoded)"
        return 1
    fi

    # Raw null byte (bash typically strips these but check anyway)
    if [[ "$input" == *$'\x00'* ]]; then
        _guard_e_error "Null byte detected (raw)"
        return 1
    fi

    # Unicode null byte variants
    if [[ "$input" == *'%u0000'* ]] || [[ "$input" == *'%U0000'* ]]; then
        _guard_e_error "Null byte detected (Unicode)"
        return 1
    fi

    # HTML entity encoding
    if [[ "$input" == *'&#0;'* ]] || [[ "$input" == *'&#x0;'* ]]; then
        _guard_e_error "Null byte detected (HTML entity)"
        return 1
    fi

    _guard_e_debug "Input passed null byte check"
    return 0
}

# =============================================================================
# ENVIRONMENT VARIABLE SAFETY
# =============================================================================

# Check environment variable for safety
# Usage: guard_env_safe --name "..." --value "..."
# Returns: 0 if safe, 1 if dangerous
guard_env_safe() {
    local name=""
    local value=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --value)
                value="$2"
                shift 2
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                else
                    value="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        _guard_e_error "guard_env_safe: variable name required"
        return 1
    fi

    local upper_name
    upper_name=$(echo "$name" | tr '[:lower:]' '[:upper:]')

    # Dangerous variable names
    local dangerous_vars=(
        'LD_PRELOAD'
        'LD_LIBRARY_PATH'
        'LD_AUDIT'
        'LD_PROFILE'
        'PATH'
        'SHELL'
        'IFS'
        'PS4'
        'BASH_ENV'
        'ENV'
        'PROMPT_COMMAND'
    )

    for var in "${dangerous_vars[@]}"; do
        if [[ "$upper_name" == "$var" ]]; then
            # PATH manipulation requires extra scrutiny
            if [[ "$var" == "PATH" ]]; then
                if [[ "$value" == *'..'/* ]] || [[ "$value" == *'.:'* ]] || \
                   [[ "$value" == *'/tmp'* ]] || [[ "$value" == *'/var/tmp'* ]]; then
                    _guard_e_error "Dangerous PATH manipulation detected: $value"
                    return 1
                fi
                _guard_e_warn "PATH modification detected: $value"
                return 0  # Allow but warn
            fi

            _guard_e_error "Dangerous environment variable: $name"
            return 1
        fi
    done

    # Check value for injection patterns
    if [[ -n "$value" ]]; then
        # Function export trick
        if [[ "$value" == *'() {'* ]] || [[ "$value" == *'(){'* ]]; then
            _guard_e_error "Function export attempt in $name"
            return 1
        fi

        # Command substitution in value
        # shellcheck disable=SC2016
        if [[ "$value" == *'$('* ]] || [[ "$value" == *'`'* ]]; then
            _guard_e_error "Command substitution in environment variable $name"
            return 1
        fi
    fi

    _guard_e_debug "Environment variable passed check: $name"
    return 0
}

# =============================================================================
# URL SAFETY
# =============================================================================

# Validate URL safety
# Usage: guard_url_safe --url "..."
# Returns: 0 if safe, 1 if dangerous
guard_url_safe() {
    local url=""
    local allowed_schemes="$GUARD_ALLOWED_URL_SCHEMES"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                url="$2"
                shift 2
                ;;
            --allowed)
                allowed_schemes="$2"
                shift 2
                ;;
            *)
                url="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$url" ]]; then
        _guard_e_error "guard_url_safe: empty URL"
        return 1
    fi

    # Extract scheme
    local scheme=""
    if [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*): ]]; then
        scheme="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$scheme" ]]; then
        _guard_e_error "No URL scheme found: $url"
        return 1
    fi

    # Convert scheme to lowercase for comparison
    scheme=$(echo "$scheme" | tr '[:upper:]' '[:lower:]')

    # Check against allowed schemes
    local is_allowed=false
    local allowed
    for allowed in $allowed_schemes; do
        allowed=$(echo "$allowed" | tr '[:upper:]' '[:lower:]')
        if [[ "$scheme" == "$allowed" ]]; then
            is_allowed=true
            break
        fi
    done

    if [[ "$is_allowed" != true ]]; then
        _guard_e_error "URL scheme not allowed: $scheme"
        return 1
    fi

    # Dangerous schemes (always block)
    local dangerous_schemes=('file' 'javascript' 'data' 'vbscript' 'about' 'chrome')
    for dangerous in "${dangerous_schemes[@]}"; do
        if [[ "$scheme" == "$dangerous" ]]; then
            _guard_e_error "Dangerous URL scheme: $scheme"
            return 1
        fi
    done

    # Check for credentials in URL
    if [[ "$url" =~ @.*: ]]; then
        _guard_e_warn "URL contains credentials (username:password@)"
    fi

    # Check for URL-encoded traversal in path
    local url_path="${url#*://}"
    url_path="${url_path#*/}"
    if [[ -n "$url_path" ]]; then
        if [[ "$url_path" == *'%2f..'* ]] || [[ "$url_path" == *'..%2f'* ]]; then
            _guard_e_error "URL path traversal detected"
            return 1
        fi
    fi

    # Check for null byte in URL
    if [[ "$url" == *'%00'* ]]; then
        _guard_e_error "Null byte in URL detected"
        return 1
    fi

    # SSRF prevention - block internal IPs
    if [[ "$url" =~ (127\.[0-9]+\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|0\.0\.0\.0|::1|localhost) ]]; then
        _guard_e_warn "URL points to internal address"
        if [[ "$GUARD_ENHANCED_STRICT" == "1" ]]; then
            return 1
        fi
    fi

    _guard_e_debug "URL passed safety check: $scheme://..."
    return 0
}

# =============================================================================
# REGEX SAFETY (ReDoS PREVENTION)
# =============================================================================

# Check regex for catastrophic backtracking patterns
# Usage: guard_regex_safe --pattern "..."
# Returns: 0 if safe, 1 if dangerous pattern detected
guard_regex_safe() {
    local pattern=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pattern)
                pattern="$2"
                shift 2
                ;;
            *)
                pattern="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        return 0  # Empty pattern is safe
    fi

    # Check pattern length
    if [[ ${#pattern} -gt $GUARD_MAX_REGEX_LENGTH ]]; then
        _guard_e_warn "Regex pattern exceeds maximum length (${#pattern} > $GUARD_MAX_REGEX_LENGTH)"
        if [[ "$GUARD_ENHANCED_STRICT" == "1" ]]; then
            return 1
        fi
    fi

    # Nested quantifiers (classic ReDoS)
    # Patterns like (a+)+, (a*)*, (a+)*, etc.
    if [[ "$pattern" =~ \(+[a-zA-Z.*+]+\)+[+*] ]]; then
        _guard_e_error "Dangerous regex: nested quantifiers detected"
        return 1
    fi

    # Overlapping alternation with repetition
    # (a|a)*, (ab|a)*, etc.
    if [[ "$pattern" =~ \([^\)]*\|[^\)]*\)[+*] ]]; then
        # Check for overlap potential
        if [[ "$pattern" =~ \((.+)\|(.+)\)[+*] ]]; then
            local alt1="${BASH_REMATCH[1]}"
            local alt2="${BASH_REMATCH[2]}"
            if [[ "$alt1" == "$alt2"* ]] || [[ "$alt2" == "$alt1"* ]]; then
                _guard_e_error "Dangerous regex: overlapping alternation detected"
                return 1
            fi
        fi
    fi

    # Excessive repetition
    # {100,}, {0,100000}, etc.
    if [[ "$pattern" =~ \{[0-9]+,\} ]]; then
        _guard_e_warn "Regex has unbounded repetition"
        if [[ "$GUARD_ENHANCED_STRICT" == "1" ]]; then
            return 1
        fi
    fi

    if [[ "$pattern" =~ \{[0-9]+,[0-9]{4,}\} ]]; then
        _guard_e_error "Regex has excessive repetition count"
        return 1
    fi

    # Multiple optional groups with wildcards
    local optional_count=0
    if [[ "$pattern" == *'?'* ]]; then
        optional_count=$(echo "$pattern" | grep -o '?' | wc -l)
        if [[ $optional_count -gt 5 ]]; then
            _guard_e_warn "Regex has many optional elements ($optional_count)"
        fi
    fi

    # Lookarounds (can be expensive)
    if [[ "$pattern" == *'?='* ]] || [[ "$pattern" == *'?!'* ]] || \
       [[ "$pattern" == *'?<='* ]] || [[ "$pattern" == *'?<!'* ]]; then
        _guard_e_warn "Regex contains lookarounds (can be slow)"
    fi

    # Backreferences (not supported in all regex engines, can be slow)
    if [[ "$pattern" =~ \\[0-9] ]]; then
        _guard_e_warn "Regex contains backreferences"
    fi

    _guard_e_debug "Regex passed safety check"
    return 0
}

# =============================================================================
# FILE UPLOAD VALIDATION
# =============================================================================

# Validate file upload
# Usage: guard_upload_safe --path "..." [--content "..."] [--max-size N]
# Returns: 0 if safe, 1 if dangerous
guard_upload_safe() {
    local path=""
    local content=""
    local max_size_mb="$GUARD_MAX_UPLOAD_MB"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                path="$2"
                shift 2
                ;;
            --content)
                content="$2"
                shift 2
                ;;
            --max-size)
                max_size_mb="$2"
                shift 2
                ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$path" ]]; then
        _guard_e_error "guard_upload_safe: path required"
        return 1
    fi

    # Check path for traversal
    if ! guard_path_traversal --path "$path"; then
        return 1
    fi

    # Validate filename
    local filename
    filename=$(basename "$path")

    # Check for double extensions (exploit attempt)
    if [[ "$filename" =~ \.[a-zA-Z0-9]+\.[a-zA-Z0-9]+$ ]]; then
        # Check for dangerous double extensions like .php.jpg
        if [[ "$filename" =~ \.(php|php3|php4|php5|phtml|pl|py|rb|sh|bash|exe|dll|bat|cmd)\.[a-zA-Z]+$ ]]; then
            _guard_e_error "Suspicious double extension: $filename"
            return 1
        fi
    fi

    # Null byte in filename
    if [[ "$filename" == *'%00'* ]]; then
        _guard_e_error "Null byte in filename"
        return 1
    fi

    # Check content size
    if [[ -n "$content" ]]; then
        local content_size=${#content}
        local max_bytes=$((max_size_mb * 1024 * 1024))

        if [[ $content_size -gt $max_bytes ]]; then
            _guard_e_error "Upload size exceeds limit: ${content_size} bytes > ${max_bytes} bytes"
            return 1
        fi

        # Check for embedded PHP/executable code
        if [[ "$content" == *'<?php'* ]] || [[ "$content" == *'<?='* ]]; then
            _guard_e_error "PHP code detected in upload"
            return 1
        fi

        if [[ "$content" == *'%PDF'* ]] && [[ "$filename" != *.pdf ]]; then
            _guard_e_warn "PDF content but extension is not .pdf"
        fi

        # Check for executable magic bytes
        local magic="${content:0:4}"
        case "$magic" in
            $'\x7fELF')
                _guard_e_error "ELF executable detected in upload"
                return 1
                ;;
            $'MZ'*)  # Windows executable
                _guard_e_error "Windows executable detected in upload"
                return 1
                ;;
            $'#!'*)  # Shebang script
                _guard_e_error "Script file detected in upload"
                return 1
                ;;
        esac
    fi

    # Extension-based checks
    local ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    local dangerous_exts=('exe' 'dll' 'bat' 'cmd' 'sh' 'bash' 'php' 'php3' 'php4' 'php5' 'phtml' 'pl' 'py' 'rb' 'jsp' 'asp' 'aspx' 'cgi' 'com' 'scr' 'jar')
    for dangerous in "${dangerous_exts[@]}"; do
        if [[ "$ext" == "$dangerous" ]]; then
            _guard_e_error "Dangerous file extension: .$ext"
            return 1
        fi
    done

    _guard_e_debug "Upload passed safety check: $filename"
    return 0
}

# =============================================================================
# COMBINED SAFETY CHECK
# =============================================================================

# Run all applicable safety checks
# Usage: guard_all [--path "..."] [--cmd "..."] [--input "..."] [--url "..."] [--query "..."]
# Returns: 0 if all safe, 1 if any check fails
guard_all() {
    local path=""
    local cmd=""
    local input=""
    local url=""
    local query=""
    local regex=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                path="$2"
                shift 2
                ;;
            --cmd)
                cmd="$2"
                shift 2
                ;;
            --input)
                input="$2"
                shift 2
                ;;
            --url)
                url="$2"
                shift 2
                ;;
            --query)
                query="$2"
                shift 2
                ;;
            --regex)
                regex="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local failed=0

    if [[ -n "$path" ]]; then
        guard_path_traversal --path "$path" || ((failed++))
    fi

    if [[ -n "$cmd" ]]; then
        guard_command_injection --cmd "$cmd" || ((failed++))
    fi

    if [[ -n "$input" ]]; then
        guard_null_byte --input "$input" || ((failed++))
    fi

    if [[ -n "$url" ]]; then
        guard_url_safe --url "$url" || ((failed++))
    fi

    if [[ -n "$query" ]]; then
        guard_sql_injection --query "$query" || ((failed++))
    fi

    if [[ -n "$regex" ]]; then
        guard_regex_safe --pattern "$regex" || ((failed++))
    fi

    return $((failed > 0 ? 1 : 0))
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_GUARD_ENHANCED_EXPORTS=(
    # Path security
    guard_path_traversal

    # Injection detection
    guard_command_injection
    guard_sql_injection
    guard_null_byte

    # Environment and URL
    guard_env_safe
    guard_url_safe

    # Input validation
    guard_regex_safe
    guard_upload_safe

    # Combined check
    guard_all
)

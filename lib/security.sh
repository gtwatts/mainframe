#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/security.sh - Security Anti-Pattern Detection for AI-Generated Code
# =============================================================================
# Description: Scans source code files for common security vulnerabilities that
#              AI coding assistants frequently generate. Based on research from
#              150+ sources including CVE databases, academic papers, and security
#              advisories. Integrates with risk.sh for severity scoring.
# Version: 1.0.0
# Requires: Bash 4.3+ (uses namerefs for block comment tracking)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SECURITY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SECURITY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Source file extensions to scan
readonly _SEC_EXTENSIONS="js|ts|tsx|jsx|py|go|rs|java|php|rb|sh|cs|cpp|c|swift|kt"

# Maximum file size to scan (1MB)
readonly _SEC_MAX_FILE_SIZE=1048576

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Findings array: each entry is "line|severity|cwe|message"
declare -ga _SEC_FINDINGS 2>/dev/null || declare -a _SEC_FINDINGS
_SEC_FINDINGS=()

# Severity counters
_SEC_CRITICAL=0
_SEC_HIGH=0
_SEC_MEDIUM=0
_SEC_LOW=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _sec_in_block_comment CONTENT IN_BLOCK_VAR
# Track multi-line block comment state (/* ... */).
# Updates the variable named by IN_BLOCK_VAR. Returns 0 if line should be skipped.
_sec_in_block_comment() {
    local content="$1"
    local -n _in_block="$2"

    if [[ $_in_block -eq 1 ]]; then
        # Currently inside a block comment - check for close
        if [[ "$content" == *"*/"* ]]; then
            _in_block=0
        fi
        return 0  # Skip this line (inside block comment)
    fi

    # Not in block comment - check for open
    if [[ "$content" == *"/*"* ]]; then
        # Check if it closes on the same line
        if [[ "$content" != *"*/"* ]]; then
            _in_block=1
        fi
        return 0  # Skip this line (block comment starts here)
    fi

    return 1  # Not a comment line
}

# _sec_is_comment CONTENT IN_BLOCK_VAR
# Return 0 if line is inside a comment (single-line or block), 1 otherwise.
# Handles //, #, *, --, and /* ... */ block comments.
_sec_is_comment() {
    local content="$1"
    local block_var="$2"

    # Check block comment state first
    _sec_in_block_comment "$content" "$block_var" && return 0

    # Single-line comment patterns
    [[ "$content" =~ ^[[:space:]]*(//|#|\*|--) ]] && return 0

    return 1
}

# _sec_escape_json STRING
# Escape special characters for JSON string values
_sec_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# _sec_reset
# Reset findings state for a new scan
_sec_reset() {
    _SEC_FINDINGS=()
    _SEC_CRITICAL=0
    _SEC_HIGH=0
    _SEC_MEDIUM=0
    _SEC_LOW=0
}

# _sec_add_finding LINE SEVERITY CWE MESSAGE
# Add a finding to the global array and increment counters
_sec_add_finding() {
    local line="$1"
    local severity="$2"
    local cwe="$3"
    local message="$4"

    _SEC_FINDINGS+=("${line}"$'\x1f'"${severity}"$'\x1f'"${cwe}"$'\x1f'"${message}")

    case "$severity" in
        critical) _SEC_CRITICAL=$((_SEC_CRITICAL + 1)) ;;
        high)     _SEC_HIGH=$((_SEC_HIGH + 1)) ;;
        medium)   _SEC_MEDIUM=$((_SEC_MEDIUM + 1)) ;;
        low)      _SEC_LOW=$((_SEC_LOW + 1)) ;;
    esac
}

# _sec_grep FILE PATTERN
# Run grep -nE on file, output matching lines with line numbers.
# Uses POSIX Extended regex for portability (works on macOS and Linux).
_sec_grep() {
    local file="$1"
    local pattern="$2"
    grep -nE -- "$pattern" "$file" 2>/dev/null || true
}

# _sec_has_pattern FILE PATTERN
# Return 0 if pattern exists in file, 1 otherwise.
# Uses POSIX Extended regex for portability.
_sec_has_pattern() {
    local file="$1"
    local pattern="$2"
    grep -qE -- "$pattern" "$file" 2>/dev/null
}

# _sec_is_scannable FILE
# Check if file exists, is readable, and within size limit
_sec_is_scannable() {
    local file="$1"

    [[ -f "$file" ]] || return 1
    [[ -r "$file" ]] || return 1

    local size
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [[ ${size:-0} -gt $_SEC_MAX_FILE_SIZE ]] && return 1

    return 0
}

# _sec_findings_json FILE
# Convert current findings to JSON string
_sec_findings_json() {
    local file="$1"
    local file_escaped
    file_escaped=$(_sec_escape_json "$file")
    local total=${#_SEC_FINDINGS[@]}

    printf '{"file":"%s",' "$file_escaped"
    printf '"total_findings":%d,' "$total"
    printf '"critical":%d,' "$_SEC_CRITICAL"
    printf '"high":%d,' "$_SEC_HIGH"
    printf '"medium":%d,' "$_SEC_MEDIUM"
    printf '"low":%d,' "$_SEC_LOW"
    printf '"risk_score":%d,' "$(sec_severity_max)"
    printf '"findings":['

    local i=0
    local line severity cwe message
    for finding in "${_SEC_FINDINGS[@]}"; do
        IFS=$'\x1f' read -r line severity cwe message <<< "$finding"
        [[ $i -gt 0 ]] && printf ','
        printf '{"line":%s,' "${line:-null}"
        printf '"severity":"%s",' "$severity"
        printf '"cwe":"%s",' "$cwe"
        printf '"message":"%s"}' "$(_sec_escape_json "$message")"
        (( i++ )) || true
    done

    printf ']}'
}

# =============================================================================
# SECURITY CHECKERS
# =============================================================================

# sec_check_secrets FILE
# Detect hardcoded secrets and credentials (CWE-798, CWE-259)
sec_check_secrets() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # API key prefixes (AWS, GitHub, GitLab, Slack, Stripe, OpenAI)
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-798" "Hardcoded API key prefix detected"
    done < <(_sec_grep "$file" '(sk-[a-zA-Z0-9]{20,}|sk_live_|sk_test_|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9\-]{20}|xox[brap]-[a-zA-Z0-9\-]+|rk_live_|rk_test_)')

    # Password/secret assignments
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-798" "Hardcoded password or secret in assignment"
    done < <(_sec_grep "$file" '(password|passwd|secret|api_key|apikey|api_secret|auth_token|access_token|private_key)[[:space:]]*[:=][[:space:]]*["'"'"'][^[:space:]"'"'"']{4,}["'"'"']')

    # Private keys
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-321" "Private key embedded in source code"
    done < <(_sec_grep "$file" '-----BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+)?PRIVATE[[:space:]]+KEY-----')

    # Bearer tokens in code
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-798" "Hardcoded Bearer token"
    done < <(_sec_grep "$file" 'Authorization.*Bearer[[:space:]]+[a-zA-Z0-9_\-\.]{15,}')
}

# sec_check_injection FILE
# Detect SQL injection and command injection (CWE-89, CWE-78)
sec_check_injection() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # SQL injection via string concatenation
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-89" "SQL query built via string concatenation"
    done < <(_sec_grep "$file" '(query|sql|stmt)[[:space:]]*[=+][[:space:]]*["'"'"'].*(SELECT|INSERT|UPDATE|DELETE|DROP).*["'"'"'][[:space:]]*\+')

    # SQL with f-strings or format
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-89" "SQL query built via string interpolation"
    done < <(_sec_grep "$file" 'f["'"'"'](SELECT|INSERT|UPDATE|DELETE).*\{')

    # OS command injection - system/exec with concatenation
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-78" "OS command built via string concatenation"
    done < <(_sec_grep "$file" '(os\.system|subprocess\.call|subprocess\.run|exec|execSync|child_process)[[:space:]]*\([^)]*\+')

    # shell=True in subprocess
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-78" "subprocess with shell=True enables command injection"
    done < <(_sec_grep "$file" 'subprocess\.(call|run|Popen)[[:space:]]*\([^)]*shell[[:space:]]*=[[:space:]]*True')

    # eval() with external input
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-78" "eval() with potential user input"
    done < <(_sec_grep "$file" 'eval[[:space:]]*\([[:space:]]*(req|request|params|input|user|data|body)')
}

# sec_check_xss FILE
# Detect Cross-Site Scripting patterns (CWE-79)
sec_check_xss() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # innerHTML assignment with variables
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-79" "innerHTML set with dynamic content"
    done < <(_sec_grep "$file" '\.innerHTML[[:space:]]*=[[:space:]]*.*(\+|`|\$\{)')

    # document.write with concatenation
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-79" "document.write with dynamic content"
    done < <(_sec_grep "$file" 'document\.write[[:space:]]*\([[:space:]]*.*\+')

    # dangerouslySetInnerHTML (React)
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "medium" "CWE-79" "dangerouslySetInnerHTML used (verify input is sanitized)"
    done < <(_sec_grep "$file" 'dangerouslySetInnerHTML')

    # jQuery .html() with variables
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-79" "jQuery .html() with dynamic content"
    done < <(_sec_grep "$file" '\.html[[:space:]]*\([[:space:]]*.*(\+|\$\{|`)')

    # Unescaped template output
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "medium" "CWE-79" "Unescaped template variable (use escaped output)"
    done < <(_sec_grep "$file" '\{\{\{.*\}\}\}|\{!!.*!!\}|<%=.*%>')
}

# sec_check_auth FILE
# Detect authentication and cryptography weaknesses (CWE-287, CWE-327, CWE-384)
sec_check_auth() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # Weak hashing for passwords (MD5, SHA1)
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-327" "Weak hash algorithm used for password (use bcrypt/scrypt/argon2)"
    done < <(_sec_grep "$file" '(md5|sha1|SHA1|MD5)[[:space:]]*\([[:space:]]*.*(password|passwd|pass|pwd)')

    # JWT with none algorithm
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-287" "JWT none algorithm allows token forgery"
    done < <(_sec_grep "$file" '(algorithm|alg).*["'"'"']none["'"'"']|"alg"[[:space:]]*:[[:space:]]*"none"')

    # Weak JWT secrets
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-287" "JWT secret is too short or predictable"
    done < <(_sec_grep "$file" '(JWT_SECRET|jwt_secret|SECRET_KEY)[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9]{1,12}["'"'"']')

    # Session not regenerated (no session regeneration after login)
    if _sec_has_pattern "$file" '(login|authenticate|sign_in)' && \
       ! _sec_has_pattern "$file" '(regenerate|rotate.*session|new_session|session\.destroy)'; then
        # Only flag if file has login logic but no session regeneration
        if _sec_has_pattern "$file" 'session'; then
            local line_num
            line_num=$(grep -n -m1 -E '(login|authenticate|sign_in)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
            [[ -n "$line_num" ]] && _sec_add_finding "$line_num" "medium" "CWE-384" "Session not regenerated after authentication"
        fi
    fi

    # Hardcoded encryption key
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "critical" "CWE-321" "Hardcoded encryption key"
    done < <(_sec_grep "$file" '(encrypt|cipher|aes|des|ENCRYPTION_KEY)[[:space:]]*[:=(][[:space:]]*["'"'"'][a-zA-Z0-9+/=]{16,}["'"'"']')
}

# sec_check_input_validation FILE
# Detect missing input validation (CWE-20)
sec_check_input_validation() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # Direct use of request body in file operations
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-20" "User input used directly in file operation"
    done < <(_sec_grep "$file" '(fs\.(writeFile|readFile|unlink|mkdir)|open|fopen|file_get_contents)[[:space:]]*\([[:space:]]*(req\.|request\.|params\.|user_input|\$_(GET|POST|REQUEST))')

    # Direct use in database without sanitization
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-20" "Unsanitized input used in database operation"
    done < <(_sec_grep "$file" '(db|database|collection|model)\.(find|query|execute|run)[[:space:]]*\([^)]*req\.(body|params|query)')

    # Path traversal vulnerability
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "high" "CWE-22" "Potential path traversal (user input in file path)"
    done < <(_sec_grep "$file" '(path\.join|os\.path\.join|File\.join)[[:space:]]*\([^)]*req\.|path\.resolve[[:space:]]*\([^)]*req\.')

    # Integer overflow / no type checking on numeric input
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "medium" "CWE-20" "Numeric input used without type validation"
    done < <(_sec_grep "$file" '(parseInt|int\(|Integer\.parseInt|atoi)[[:space:]]*\([[:space:]]*(req\.|request\.|params\.)')
}

# sec_check_deps FILE
# Detect dependency risks and supply chain issues (CWE-1357)
sec_check_deps() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    # Lifecycle scripts that auto-execute
    while IFS=: read -r line_num _; do
        _sec_add_finding "$line_num" "medium" "CWE-1357" "Package lifecycle script can execute arbitrary code on install"
    done < <(_sec_grep "$file" '"(preinstall|postinstall|prebuild|prepublish|preuninstall)"[[:space:]]*:')

    # Wildcard or unpinned versions
    while IFS=: read -r line_num _; do
        _sec_add_finding "$line_num" "low" "CWE-1357" "Unpinned dependency version (use exact versions)"
    done < <(_sec_grep "$file" '"[a-zA-Z0-9@/_-]+"[[:space:]]*:[[:space:]]*"[\^~><=*]')

    # Known malicious package name patterns (typosquatting indicators)
    while IFS=: read -r line_num _; do
        _sec_add_finding "$line_num" "high" "CWE-1357" "Potential typosquatting package name"
    done < <(_sec_grep "$file" '"(lod[a-z]sh|req[u]?ests|beautifu[l]?soup[0-9]?|djang[o0]|fla[s]?k[0-9])"')
}

# sec_check_file_upload FILE
# Detect unrestricted file upload patterns (CWE-434)
sec_check_file_upload() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    # File upload without extension validation
    if _sec_has_pattern "$file" '(multer|formidable|req\.files|request\.file|move_uploaded_file|upload)'; then
        if ! _sec_has_pattern "$file" '(allowedExtensions|fileFilter|mimetype|content.type|extension.*check|\.endsWith)'; then
            local line_num
            line_num=$(grep -n -m1 -E '(multer|formidable|req\.files|move_uploaded_file)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
            [[ -n "$line_num" ]] && _sec_add_finding "$line_num" "high" "CWE-434" "File upload without extension or MIME type validation"
        fi

        # No file size limit
        if ! _sec_has_pattern "$file" '(maxFileSize|limits.*fileSize|size.*limit|MAX_FILE_SIZE|content.length)'; then
            local line_num
            line_num=$(grep -n -m1 -E '(multer|formidable|req\.files|move_uploaded_file)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
            [[ -n "$line_num" ]] && _sec_add_finding "$line_num" "medium" "CWE-434" "File upload without size limit"
        fi
    fi

    # Upload to web-accessible directory
    while IFS=: read -r line_num _; do
        _sec_add_finding "$line_num" "high" "CWE-434" "File uploaded directly to web-accessible directory"
    done < <(_sec_grep "$file" '(move|save|write).*(/public/|/static/|/www/|/html/|/uploads/).*\.(file|name|original)')
}

# sec_check_rate_limiting FILE
# Detect missing rate limiting on endpoints (CWE-770)
sec_check_rate_limiting() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    # Check if file has route handlers
    if _sec_has_pattern "$file" '\.(get|post|put|delete|patch)[[:space:]]*\(|@app\.(route|get|post)|Router\.(get|post)'; then
        # Check if rate limiting is configured
        if ! _sec_has_pattern "$file" '(rateLimit|rate.limit|throttle|slowDown|express-rate-limit|@Throttle|RateLimiter|limiter)'; then
            local line_num
            line_num=$(grep -n -m1 -E '\.(get|post|put|delete)[[:space:]]*\(|@app\.(route|get|post)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
            [[ -n "$line_num" ]] && _sec_add_finding "$line_num" "medium" "CWE-770" "API routes without rate limiting"
        fi
    fi
}

# sec_check_data_exposure FILE
# Detect excessive data exposure (CWE-200)
sec_check_data_exposure() {
    local file="$1"
    _sec_is_scannable "$file" || return 0

    local _block_state=0

    # SELECT * queries
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "medium" "CWE-200" "SELECT * may expose sensitive columns"
    done < <(_sec_grep "$file" 'SELECT[[:space:]]+\*[[:space:]]+FROM')

    # Returning full objects without filtering
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "low" "CWE-200" "Full object returned to client (filter sensitive fields)"
    done < <(_sec_grep "$file" '(res\.json|res\.send|return.*jsonify|JsonResponse)[[:space:]]*\([[:space:]]*(user|account|profile|record)[[:space:]]*\)')

    # Stack traces or errors returned to client
    _block_state=0
    while IFS=: read -r line_num content; do
        _sec_is_comment "$content" _block_state && continue
        _sec_add_finding "$line_num" "medium" "CWE-209" "Error details may leak to client"
    done < <(_sec_grep "$file" '(res\.json|res\.send|response\.write)[[:space:]]*\([[:space:]]*(err|error|exception|e\.stack|traceback)')
}

# =============================================================================
# AGGREGATE FUNCTIONS
# =============================================================================

# sec_scan_file FILE
# Run all security checks on a single file and output JSON report
sec_scan_file() {
    local file="$1"

    if [[ ! "$file" =~ \.($_SEC_EXTENSIONS)$ ]]; then
        printf '{"file":"%s","error":"unsupported file type"}' "$(_sec_escape_json "$file")"
        return 0
    fi

    if ! _sec_is_scannable "$file"; then
        return 0
    fi
    _sec_reset

    sec_check_secrets "$file"
    sec_check_injection "$file"
    sec_check_xss "$file"
    sec_check_auth "$file"
    sec_check_input_validation "$file"
    sec_check_deps "$file"
    sec_check_file_upload "$file"
    sec_check_rate_limiting "$file"
    sec_check_data_exposure "$file"

    _sec_findings_json "$file"
}

# sec_scan_dir DIR [--recursive]
# Scan all source files in a directory
sec_scan_dir() {
    local dir="$1"
    local recursive="${2:---recursive}"
    [[ -d "$dir" ]] || return 1

    local -a find_args=("$dir")
    [[ "$recursive" != "--recursive" ]] && find_args+=("-maxdepth" "1")
    # Exclude common dependency, build, and VCS directories
    find_args+=(
        "!" "-path" "*/node_modules/*"
        "!" "-path" "*/.git/*"
        "!" "-path" "*/vendor/*"
        "!" "-path" "*/venv/*"
        "!" "-path" "*/__pycache__/*"
        "!" "-path" "*/target/*"
        "!" "-path" "*/dist/*"
        "!" "-path" "*/.next/*"
    )
    find_args+=("-type" "f")

    local total_findings=0
    local file_reports=()

    while IFS= read -r file; do
        if [[ "$file" =~ \.($_SEC_EXTENSIONS)$ ]]; then
            local report
            report=$(sec_scan_file "$file")
            if [[ -n "$report" && "$report" != *'"error"'* ]]; then
                file_reports+=("$report")
                local findings
                findings=$(printf '%s' "$report" | sed -n 's/.*"total_findings":\([0-9]*\).*/\1/p' 2>/dev/null)
                findings="${findings:-0}"
                (( total_findings += findings )) || true
            fi
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)

    # Aggregate report
    printf '{"directory":"%s",' "$(_sec_escape_json "$dir")"
    printf '"files_scanned":%d,' "${#file_reports[@]}"
    printf '"total_findings":%d,' "$total_findings"
    printf '"files":['

    local i=0
    for report in "${file_reports[@]}"; do
        [[ $i -gt 0 ]] && printf ','
        printf '%s' "$report"
        (( i++ )) || true
    done

    printf ']}'
}

# sec_report [JSON]
# Pretty-print security findings with colored output
# Reads from argument or stdin
sec_report() {
    local json="${1:-$(cat)}"

    local total
    total=$(printf '%s' "$json" | sed -n 's/.*"total_findings":\([0-9]*\).*/\1/p' 2>/dev/null | head -1)

    printf '\n'
    printf '  ╔══════════════════════════════════════════════════════╗\n'
    printf '  ║          MAINFRAME Security Scan Report             ║\n'
    printf '  ╚══════════════════════════════════════════════════════╝\n\n'

    if [[ "${total:-0}" -eq 0 ]]; then
        printf '  \033[0;32m[PASS]\033[0m No security findings detected.\n\n'
        return 0
    fi

    printf '  \033[1;31mFindings: %d\033[0m\n\n' "${total:-0}"

    # Parse and display findings from internal state (avoids fragile JSON parsing)
    local finding line_num severity cwe msg
    for finding in "${_SEC_FINDINGS[@]}"; do
        IFS=$'\x1f' read -r line_num severity cwe msg <<< "$finding"

        [[ -z "$severity" ]] && continue

        local color
        case "$severity" in
            critical) color='\033[1;31m' ;;
            high)     color='\033[0;31m' ;;
            medium)   color='\033[0;33m' ;;
            low)      color='\033[0;36m' ;;
            *)        color='\033[0m' ;;
        esac

        printf "  ${color}[%s]\033[0m L%s %s (%s)\n" \
            "$(printf '%s' "$severity" | tr '[:lower:]' '[:upper:]')" \
            "${line_num:-?}" \
            "${msg:-unknown}" \
            "${cwe:-N/A}"
    done

    printf '\n'
    return 1
}

# =============================================================================
# RISK INTEGRATION
# =============================================================================

# sec_severity LEVEL
# Map severity string to numeric risk score (compatible with risk.sh)
sec_severity() {
    local level="$1"
    case "$level" in
        critical) echo 9 ;;
        high)     echo 7 ;;
        medium)   echo 5 ;;
        low)      echo 3 ;;
        info)     echo 1 ;;
        *)        echo 0 ;;
    esac
}

# sec_severity_max
# Return the highest risk score from current findings
sec_severity_max() {
    local max=0
    if [[ $_SEC_CRITICAL -gt 0 ]]; then
        max=9
    elif [[ $_SEC_HIGH -gt 0 ]]; then
        max=7
    elif [[ $_SEC_MEDIUM -gt 0 ]]; then
        max=5
    elif [[ $_SEC_LOW -gt 0 ]]; then
        max=3
    fi
    echo "$max"
}

# sec_integrate_risk FILE
# Bridge function: scan file and return risk score for use with risk.sh
# Returns: numeric risk score 0-10
sec_integrate_risk() {
    local file="$1"
    _sec_reset

    sec_check_secrets "$file"
    sec_check_injection "$file"
    sec_check_xss "$file"
    sec_check_auth "$file"
    sec_check_input_validation "$file"
    sec_check_file_upload "$file"

    sec_severity_max
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith.sh - Terminal Security Orchestrator
# =============================================================================
# Description: Aggregates all tirith_* security libraries into a unified
#              scanning interface. Provides URL trust scoring, JSONL audit
#              logging, configuration loading, and reporting.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Config directory and file
declare -g TIRITH_CONFIG_DIR="${TIRITH_CONFIG_DIR:-${HOME}/.mainframe/security}"
declare -g TIRITH_CONFIG_FILE="${TIRITH_CONFIG_FILE:-${TIRITH_CONFIG_DIR}/tirith.yaml}"

# Audit log location
declare -g TIRITH_AUDIT_LOG="${TIRITH_AUDIT_LOG:-${TIRITH_CONFIG_DIR}/tirith-audit.jsonl}"

# Fail mode: "open" (warn only) or "closed" (block on HIGH+)
declare -g TIRITH_FAIL_MODE="${TIRITH_FAIL_MODE:-open}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Allowlist and blocklist (loaded from config)
declare -ga _TIRITH_ALLOWLIST=()
declare -ga _TIRITH_BLOCKLIST=()

# Severity overrides: associative array of rule_id -> severity
declare -gA _TIRITH_SEVERITY_OVERRIDES=()

# Track initialization
declare -g _TIRITH_INITIALIZED=0

# =============================================================================
# INITIALIZATION
# =============================================================================

# tirith_init
# Initialize the tirith subsystem: set up shared state, load config.
# Safe to call multiple times (idempotent).
tirith_init() {
    (( _TIRITH_INITIALIZED )) && return 0

    # Initialize shared findings state
    if declare -F _tirith_init_state &>/dev/null; then
        _tirith_init_state
    else
        # Standalone fallback
        if ! declare -p _TIRITH_FINDINGS &>/dev/null 2>&1; then
            declare -ga _TIRITH_FINDINGS=()
            declare -g _TIRITH_CRITICAL=0
            declare -g _TIRITH_HIGH=0
            declare -g _TIRITH_MEDIUM=0
            declare -g _TIRITH_LOW=0
        fi
    fi

    # Ensure config directory exists
    [[ -d "$TIRITH_CONFIG_DIR" ]] || mkdir -p "$TIRITH_CONFIG_DIR" 2>/dev/null

    # Load config if present
    tirith_load_config

    _TIRITH_INITIALIZED=1
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# tirith_load_config [FILE]
# Load tirith configuration from a YAML-like file.
# Format:
#   version: 1
#   fail_mode: open
#   allowlist:
#     - *.trusted.com
#     - github.com
#   blocklist:
#     - evil.com
#   severity_overrides:
#     RawIpUrl: low
#     ShortenedUrl: high
tirith_load_config() {
    local file="${1:-$TIRITH_CONFIG_FILE}"
    [[ -f "$file" ]] || return 0

    local section=""
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Detect section headers
        if [[ "$line" =~ ^([a-z_]+): ]]; then
            key="${BASH_REMATCH[1]}"
            value="${line#*: }"
            value="${value#"${value%%[![:space:]]*}"}"

            case "$key" in
                version) : ;; # Acknowledged but unused
                fail_mode)
                    if [[ "$value" == "open" || "$value" == "closed" ]]; then
                        TIRITH_FAIL_MODE="$value"
                    fi
                    section=""
                    ;;
                allowlist)  section="allowlist" ;;
                blocklist)  section="blocklist" ;;
                severity_overrides) section="severity_overrides" ;;
                *) section="" ;;
            esac
            continue
        fi

        # Process list items (- value)
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            value="${BASH_REMATCH[1]}"
            case "$section" in
                allowlist)  _TIRITH_ALLOWLIST+=("$value") ;;
                blocklist)  _TIRITH_BLOCKLIST+=("$value") ;;
            esac
            continue
        fi

        # Process key-value pairs in sections (key: value)
        if [[ "$line" =~ ^[[:space:]]+([A-Za-z_]+):[[:space:]]+(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$section" in
                severity_overrides) _TIRITH_SEVERITY_OVERRIDES["$key"]="$value" ;;
            esac
        fi
    done < "$file"
}

# =============================================================================
# RULE: ProxyEnvSet
# =============================================================================

# tirith_check_proxy_env [SOURCE]
# Check if proxy environment variables are set, which could redirect traffic.
# Severity: low | Rule: ProxyEnvSet
# Returns: 0 if finding detected, 1 if clean
tirith_check_proxy_env() {
    local source="${1:-environment}"

    if [[ -n "${http_proxy:-}" ]] || [[ -n "${HTTP_PROXY:-}" ]] || \
       [[ -n "${https_proxy:-}" ]] || [[ -n "${HTTPS_PROXY:-}" ]] || \
       [[ -n "${all_proxy:-}" ]] || [[ -n "${ALL_PROXY:-}" ]]; then
        local proxies=""
        [[ -n "${http_proxy:-}" ]] && proxies="http_proxy=${http_proxy}"
        [[ -n "${HTTP_PROXY:-}" ]] && proxies="${proxies:+$proxies, }HTTP_PROXY=${HTTP_PROXY}"
        [[ -n "${https_proxy:-}" ]] && proxies="${proxies:+$proxies, }https_proxy=${https_proxy}"
        [[ -n "${HTTPS_PROXY:-}" ]] && proxies="${proxies:+$proxies, }HTTPS_PROXY=${HTTPS_PROXY}"
        [[ -n "${all_proxy:-}" ]] && proxies="${proxies:+$proxies, }all_proxy=${all_proxy}"
        [[ -n "${ALL_PROXY:-}" ]] && proxies="${proxies:+$proxies, }ALL_PROXY=${ALL_PROXY}"

        _tirith_add_finding "$source" "low" "ProxyEnvSet" \
            "Proxy environment variable(s) set: ${proxies}"
        return 0
    fi

    return 1
}

# =============================================================================
# ALLOWLIST / BLOCKLIST MATCHING
# =============================================================================

# _tirith_is_allowed URL_OR_DOMAIN
# Check if a URL or domain matches the allowlist.
# Returns: 0 if allowed, 1 if not
_tirith_is_allowed() {
    local target="$1"
    local pattern

    for pattern in "${_TIRITH_ALLOWLIST[@]}"; do
        # Glob-style matching
        # shellcheck disable=SC2254
        case "$target" in
            $pattern) return 0 ;;
        esac
        # Also check if the domain part matches
        local host
        host=$(_tirith_simple_host "$target")
        # shellcheck disable=SC2254
        case "$host" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

# _tirith_is_blocked URL_OR_DOMAIN
# Check if a URL or domain matches the blocklist.
# Returns: 0 if blocked, 1 if not
_tirith_is_blocked() {
    local target="$1"
    local pattern

    for pattern in "${_TIRITH_BLOCKLIST[@]}"; do
        # shellcheck disable=SC2254
        case "$target" in
            $pattern) return 0 ;;
        esac
        local host
        host=$(_tirith_simple_host "$target")
        # shellcheck disable=SC2254
        case "$host" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

# _tirith_simple_host URL
# Quick host extraction without parse_url dependency
_tirith_simple_host() {
    local url="$1"
    url="${url#*://}"
    url="${url%%/*}"
    url="${url%%\?*}"
    url="${url%%#*}"
    url="${url##*@}"
    url="${url%%:*}"
    printf '%s' "$url"
}

# =============================================================================
# AGGREGATE SCANNERS
# =============================================================================

# tirith_scan_command CMD [SOURCE]
# Full security scan of a shell command string.
# Runs injection, pipe, path, URL, and ecosystem checks.
# Returns: 0 if any findings, 1 if clean
tirith_scan_command() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    tirith_init

    # Check allowlist bypass
    _tirith_is_allowed "$cmd" && return 1

    local found=1

    # Injection checks (ANSI, bidi, zero-width, control chars, hidden multiline)
    if declare -F tirith_scan_injection &>/dev/null; then
        tirith_scan_injection "$cmd" "$source" && found=0
    fi

    # Pipe-to-shell checks
    if declare -F tirith_scan_pipe &>/dev/null; then
        tirith_scan_pipe "$cmd" "$source" && found=0
    fi

    # Extract URLs from command and scan each
    local -a urls=()
    _tirith_extract_urls "$cmd" urls

    local url
    for url in "${urls[@]}"; do
        # Check blocklist
        if _tirith_is_blocked "$url"; then
            _tirith_add_finding "$source" "high" "BlocklistedUrl" \
                "URL matches blocklist: ${url}"
            found=0
            continue
        fi

        # URL security checks
        if declare -F tirith_scan_url_checks &>/dev/null; then
            tirith_scan_url_checks "$url" "$source" && found=0
        fi

        # Ecosystem checks
        if declare -F tirith_scan_ecosystem &>/dev/null; then
            tirith_scan_ecosystem "$cmd" "$source" && found=0
        fi
    done

    # Ecosystem checks on full command (for non-URL patterns like docker, pip, npm)
    if declare -F tirith_scan_ecosystem &>/dev/null; then
        tirith_scan_ecosystem "$cmd" "$source" && found=0
    fi

    # Proxy environment check
    tirith_check_proxy_env "$source" && found=0

    return "$found"
}

# tirith_scan_url URL [SOURCE]
# Full security scan of a single URL.
# Returns: 0 if any findings, 1 if clean
tirith_scan_url() {
    local url="$1"
    local source="${2:-url}"

    [[ -z "$url" ]] && return 1

    tirith_init

    _tirith_is_allowed "$url" && return 1

    if _tirith_is_blocked "$url"; then
        _tirith_add_finding "$source" "high" "BlocklistedUrl" \
            "URL matches blocklist: ${url}"
        return 0
    fi

    local found=1

    # Run URL-specific checks
    if declare -F tirith_scan_url_checks &>/dev/null; then
        tirith_scan_url_checks "$url" "$source" && found=0
    fi

    # Path check on URL path component
    if declare -F tirith_scan_path &>/dev/null; then
        local path="${url#*://}"
        path="/${path#*/}"
        path="${path%%\?*}"
        path="${path%%#*}"
        tirith_scan_path "$path" "$source" && found=0
    fi

    return "$found"
}

# tirith_scan_input TEXT [SOURCE]
# Scan arbitrary text for injection attacks.
# Returns: 0 if any findings, 1 if clean
tirith_scan_input() {
    local text="$1"
    local source="${2:-input}"

    [[ -z "$text" ]] && return 1

    tirith_init

    local found=1

    if declare -F tirith_scan_injection &>/dev/null; then
        tirith_scan_injection "$text" "$source" && found=0
    fi

    # Extract and scan any URLs in the text
    local -a urls=()
    _tirith_extract_urls "$text" urls

    local url
    for url in "${urls[@]}"; do
        if declare -F tirith_scan_url_checks &>/dev/null; then
            tirith_scan_url_checks "$url" "$source" && found=0
        fi
    done

    return "$found"
}

# =============================================================================
# URL EXTRACTION HELPER
# =============================================================================

# _tirith_extract_urls TEXT ARRAY_NAME
# Extract URLs from a text string into the named array.
_tirith_extract_urls() {
    local text="$1"
    local -n _urls_out="$2"
    _urls_out=()

    # Match http://, https://, ftp://, and schemeless //
    local word
    for word in $text; do
        if [[ "$word" =~ ^https?:// ]] || \
           [[ "$word" =~ ^ftp:// ]] || \
           [[ "$word" =~ ^// ]]; then
            # Strip trailing punctuation that's likely not part of URL
            word="${word%%[,;)\"\']*}"
            _urls_out+=("$word")
        fi
    done
}

# =============================================================================
# URL TRUST SCORING
# =============================================================================

# tirith_url_trust_score URL
# Calculate a trust score for a URL on a 0-100 scale.
# Higher score = more trustworthy.
# Output: Integer score on stdout
tirith_url_trust_score() {
    local url="$1"
    [[ -z "$url" ]] && { printf '0'; return 1; }

    local score=100

    # -30: Plain HTTP (no TLS)
    if [[ "$url" =~ ^http:// ]]; then
        ((score -= 30))
    fi

    # -20: URL shortener
    local host
    host=$(_tirith_simple_host "$url")
    if declare -p _TIRITH_SHORTENERS &>/dev/null 2>&1; then
        local shortener
        for shortener in "${_TIRITH_SHORTENERS[@]}"; do
            if [[ "$host" == "$shortener" ]]; then
                ((score -= 20))
                break
            fi
        done
    fi

    # -20: Confusable domain (check skeleton if function available)
    if declare -F _tirith_skeleton &>/dev/null; then
        local skeleton
        skeleton=$(_tirith_skeleton "$host")
        if [[ "$skeleton" != "$host" ]]; then
            ((score -= 20))
        fi
    fi

    # -15: Raw IP address
    if declare -F validate_ipv4 &>/dev/null; then
        validate_ipv4 "$host" && ((score -= 15))
    elif [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ((score -= 15))
    fi

    # -10: Non-standard port
    local port_part="${url#*://}"
    port_part="${port_part%%/*}"
    port_part="${port_part##*@}"
    if [[ "$port_part" == *":"* ]]; then
        local port="${port_part##*:}"
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" != "80" ]] && [[ "$port" != "443" ]]; then
            ((score -= 10))
        fi
    fi

    # -10: Punycode domain
    if [[ "$host" == *"xn--"* ]]; then
        ((score -= 10))
    fi

    # -10: Userinfo trick (user@host)
    local authority="${url#*://}"
    authority="${authority%%/*}"
    if [[ "$authority" == *"@"* ]]; then
        ((score -= 10))
    fi

    # -5: Schemeless URL
    if [[ "$url" =~ ^// ]]; then
        ((score -= 5))
    fi

    # Clamp to 0-100
    (( score < 0 )) && score=0
    (( score > 100 )) && score=100

    printf '%d' "$score"
}

# =============================================================================
# REPORTING
# =============================================================================

# tirith_report
# Print a human-readable report of all findings to stderr.
tirith_report() {
    local count="${#_TIRITH_FINDINGS[@]}"

    if (( count == 0 )); then
        printf 'Tirith: No security findings.\n' >&2
        return 0
    fi

    printf '\n' >&2
    printf '╔══════════════════════════════════════════════════════════╗\n' >&2
    printf '║  Tirith Terminal Security Report                       ║\n' >&2
    printf '╚══════════════════════════════════════════════════════════╝\n' >&2
    printf '\n' >&2

    # Summary
    printf '  Findings: %d total\n' "$count" >&2
    (( _TIRITH_CRITICAL > 0 )) && printf '    CRITICAL: %d\n' "$_TIRITH_CRITICAL" >&2
    (( _TIRITH_HIGH > 0 ))     && printf '    HIGH:     %d\n' "$_TIRITH_HIGH" >&2
    (( _TIRITH_MEDIUM > 0 ))   && printf '    MEDIUM:   %d\n' "$_TIRITH_MEDIUM" >&2
    (( _TIRITH_LOW > 0 ))      && printf '    LOW:      %d\n' "$_TIRITH_LOW" >&2
    printf '\n' >&2

    # Detail
    local finding source severity rule_id message
    local i=1
    for finding in "${_TIRITH_FINDINGS[@]}"; do
        IFS=$'\x1f' read -r source severity rule_id message <<< "$finding"

        local color=""
        local reset=""
        if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
            reset=$'\033[0m'
            case "$severity" in
                critical) color=$'\033[1;31m' ;; # Bold red
                high)     color=$'\033[31m' ;;    # Red
                medium)   color=$'\033[33m' ;;    # Yellow
                low)      color=$'\033[36m' ;;    # Cyan
            esac
        fi

        printf '  %d. [%s%s%s] %s\n' "$i" "$color" "${severity^^}" "$reset" "$rule_id" >&2
        printf '     %s\n' "$message" >&2
        printf '     Source: %s\n\n' "$source" >&2
        ((i++))
    done
}

# tirith_report_json
# Output all findings as a JSON object on stdout.
tirith_report_json() {
    printf '{"findings":['

    local first=true
    local finding source severity rule_id message
    for finding in "${_TIRITH_FINDINGS[@]}"; do
        IFS=$'\x1f' read -r source severity rule_id message <<< "$finding"

        $first || printf ','
        first=false

        # Escape JSON strings
        source="${source//\\/\\\\}"
        source="${source//\"/\\\"}"
        message="${message//\\/\\\\}"
        message="${message//\"/\\\"}"

        printf '{"source":"%s","severity":"%s","rule":"%s","message":"%s"}' \
            "$source" "$severity" "$rule_id" "$message"
    done

    printf '],"summary":{"critical":%d,"high":%d,"medium":%d,"low":%d,"total":%d}}' \
        "$_TIRITH_CRITICAL" "$_TIRITH_HIGH" "$_TIRITH_MEDIUM" "$_TIRITH_LOW" \
        "${#_TIRITH_FINDINGS[@]}"
}

# =============================================================================
# AUDIT LOGGING
# =============================================================================

# tirith_audit_log CMD RESULT [EXTRA]
# Append a JSONL entry to the audit log.
tirith_audit_log() {
    local cmd="$1"
    local result="$2"
    local extra="${3:-}"

    [[ -z "$TIRITH_AUDIT_LOG" ]] && return 0

    # Ensure directory exists
    local log_dir
    log_dir=$(dirname "$TIRITH_AUDIT_LOG")
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)

    # Escape strings for JSON
    cmd="${cmd//\\/\\\\}"
    cmd="${cmd//\"/\\\"}"
    cmd="${cmd//$'\n'/\\n}"
    extra="${extra//\\/\\\\}"
    extra="${extra//\"/\\\"}"

    printf '{"timestamp":"%s","command":"%s","result":"%s","findings":%d,"critical":%d,"high":%d,"medium":%d,"low":%d%s}\n' \
        "$ts" "$cmd" "$result" \
        "${#_TIRITH_FINDINGS[@]}" "$_TIRITH_CRITICAL" "$_TIRITH_HIGH" "$_TIRITH_MEDIUM" "$_TIRITH_LOW" \
        "${extra:+,\"extra\":\"$extra\"}" \
        >> "$TIRITH_AUDIT_LOG" 2>/dev/null
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# tirith_clear
# Reset all findings and counters.
tirith_clear() {
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
}

# tirith_has_findings [SEVERITY]
# Check if there are any findings, optionally of a specific severity.
# Returns: 0 if findings exist, 1 if clean
tirith_has_findings() {
    local severity="${1:-}"

    if [[ -z "$severity" ]]; then
        (( ${#_TIRITH_FINDINGS[@]} > 0 ))
        return $?
    fi

    case "$severity" in
        critical) (( _TIRITH_CRITICAL > 0 )) ;;
        high)     (( _TIRITH_HIGH > 0 )) ;;
        medium)   (( _TIRITH_MEDIUM > 0 )) ;;
        low)      (( _TIRITH_LOW > 0 )) ;;
        *)        return 1 ;;
    esac
}

# tirith_should_block
# Determine if current findings warrant blocking execution.
# In "closed" mode: block on HIGH or CRITICAL
# In "open" mode: block only on CRITICAL
# Returns: 0 if should block, 1 if should allow
tirith_should_block() {
    case "$TIRITH_FAIL_MODE" in
        closed)
            (( _TIRITH_CRITICAL > 0 || _TIRITH_HIGH > 0 ))
            return $?
            ;;
        *)
            (( _TIRITH_CRITICAL > 0 ))
            return $?
            ;;
    esac
}

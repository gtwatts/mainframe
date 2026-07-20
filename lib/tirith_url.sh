#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith_url.sh - URL and Hostname Security
# =============================================================================
# Description: Detects URL-based attacks including homograph/confusable domains,
#              punycode tricks, userinfo deception, plain HTTP to sensitive
#              endpoints, URL shorteners, and insecure TLS configurations.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_URL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_URL_LOADED=1

# =============================================================================
# SHARED TIRITH STATE (portable - will defer to tirith_core.sh if loaded)
# =============================================================================

# Initialize findings state if not already present
if ! declare -F _tirith_init_state &>/dev/null; then
    _tirith_init_state() {
        declare -ga _TIRITH_FINDINGS 2>/dev/null || declare -a _TIRITH_FINDINGS
        _TIRITH_FINDINGS=()
        _TIRITH_FINDING_COUNT=0
    }
fi

# Add a finding to the shared findings array
# Usage: _tirith_add_finding SOURCE SEVERITY RULE_ID MESSAGE
if ! declare -F _tirith_add_finding &>/dev/null; then
    _tirith_add_finding() {
        local source="${1:-unknown}"
        local severity="${2:-medium}"
        local rule_id="${3:-UnknownRule}"
        local message="${4:-}"

        local finding
        # Escape message for safe storage
        local safe_msg="${message//\\/\\\\}"
        safe_msg="${safe_msg//\"/\\\"}"

        finding="{\"source\":\"${source}\",\"severity\":\"${severity}\",\"rule\":\"${rule_id}\",\"message\":\"${safe_msg}\"}"
        _TIRITH_FINDINGS+=("$finding")
        _TIRITH_FINDING_COUNT=$((_TIRITH_FINDING_COUNT + 1))
    }
fi

# Initialize state at load
_tirith_init_state

# =============================================================================
# CONFUSABLE CHARACTER MAP
# =============================================================================

declare -gA _TIRITH_CONFUSABLES 2>/dev/null || declare -A _TIRITH_CONFUSABLES
_TIRITH_CONFUSABLES=()

# Initialize confusables - visually similar characters from non-Latin scripts
_tirith_init_confusables() {
    # Cyrillic -> Latin
    _TIRITH_CONFUSABLES[$'\xd0\xb0']="a"   # а -> a (U+0430)
    _TIRITH_CONFUSABLES[$'\xd0\xb5']="e"   # е -> e (U+0435)
    _TIRITH_CONFUSABLES[$'\xd0\xbe']="o"   # о -> o (U+043E)
    _TIRITH_CONFUSABLES[$'\xd1\x80']="p"   # р -> p (U+0440)
    _TIRITH_CONFUSABLES[$'\xd1\x81']="c"   # с -> c (U+0441)
    _TIRITH_CONFUSABLES[$'\xd1\x96']="i"   # і -> i (U+0456)
    _TIRITH_CONFUSABLES[$'\xd2\xbb']="h"   # һ -> h (U+04BB)
    _TIRITH_CONFUSABLES[$'\xd1\x83']="y"   # у -> y (U+0443)
    _TIRITH_CONFUSABLES[$'\xd0\xba']="k"   # к -> k (U+043A)
    _TIRITH_CONFUSABLES[$'\xd1\x85']="x"   # х -> x (U+0445)
    # Greek -> Latin
    _TIRITH_CONFUSABLES[$'\xce\xb1']="a"   # α -> a (U+03B1)
    _TIRITH_CONFUSABLES[$'\xce\xb5']="e"   # ε -> e (U+03B5)
    _TIRITH_CONFUSABLES[$'\xce\xbf']="o"   # ο -> o (U+03BF)
    _TIRITH_CONFUSABLES[$'\xcf\x81']="p"   # ρ -> p (U+03C1)
    # Fullwidth punctuation -> ASCII
    _TIRITH_CONFUSABLES[$'\xef\xbc\x8e']="."  # ．-> . (U+FF0E)
    _TIRITH_CONFUSABLES[$'\xe3\x80\x82']="."  # 。-> . (U+3002)
    _TIRITH_CONFUSABLES[$'\xef\xbd\xa1']="."  # ｡ -> . (U+FF61)
}
_tirith_init_confusables

# =============================================================================
# REFERENCE DATA
# =============================================================================

# URL shortener domains
readonly -a _TIRITH_SHORTENERS=(
    "bit.ly" "t.co" "tinyurl.com" "goo.gl" "ow.ly"
    "is.gd" "buff.ly" "rebrand.ly" "cutt.ly" "shorturl.at"
)

# Lookalike TLDs that impersonate file extensions
readonly -a _TIRITH_LOOKALIKE_TLDS=(
    "zip" "mov" "exe" "bat" "cmd" "com0" "app0"
)

# Well-known domains for confusable/skeleton comparison
readonly -a _TIRITH_KNOWN_DOMAINS=(
    "github.com" "google.com" "microsoft.com" "apple.com" "amazon.com"
    "facebook.com" "twitter.com" "linkedin.com" "paypal.com" "netflix.com"
    "npmjs.com" "pypi.org" "docker.com" "cloudflare.com" "amazonaws.com"
    "gitlab.com" "bitbucket.org" "stackoverflow.com" "mozilla.org" "ubuntu.com"
    "debian.org" "archlinux.org" "fedoraproject.org" "redhat.com" "oracle.com"
    "slack.com" "discord.com" "zoom.us" "dropbox.com" "icloud.com"
    "chase.com" "bankofamerica.com" "wellsfargo.com" "citibank.com"
    "stripe.com" "twilio.com" "sendgrid.com" "mailchimp.com"
    "openai.com" "anthropic.com" "huggingface.co" "kaggle.com"
    "wordpress.org" "drupal.org" "joomla.org"
    "python.org" "nodejs.org" "rust-lang.org" "golang.org" "ruby-lang.org"
)

# Sensitive URL sinks (paths that receive credentials, tokens, payments)
readonly -a _TIRITH_SENSITIVE_SINKS=(
    "login" "signin" "auth" "oauth" "token" "api/key"
    "password" "reset" "verify" "confirm" "webhook"
    "payment" "checkout" "billing" "account"
)

# Insecure TLS flags in commands
readonly -a _TIRITH_INSECURE_TLS_FLAGS=(
    "--insecure" "-k" "--no-check-certificate"
    "NODE_TLS_REJECT_UNAUTHORIZED=0"
    "PYTHONHTTPSVERIFY=0"
    "verify=False" "verify_ssl=False"
    "rejectUnauthorized.*false"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _tirith_extract_host URL
# Extract hostname from URL, using parse_url if available, else simple parsing
# @pre: url is a non-empty string
# @post: prints hostname to stdout
# @idempotent: yes
# @returns: 0
_tirith_extract_host() {
    local url="$1"

    if declare -F parse_url &>/dev/null; then
        local parsed
        parsed=$(parse_url "$url")
        # Extract host from JSON output
        local host="${parsed#*\"host\":\"}"
        host="${host%%\"*}"
        printf '%s' "$host"
    else
        # Simple extraction: strip scheme, strip path, strip port, strip userinfo
        local tmp="$url"
        tmp="${tmp#*://}"
        tmp="${tmp%%/*}"
        tmp="${tmp%%\?*}"
        tmp="${tmp%%#*}"
        tmp="${tmp##*@}"
        tmp="${tmp%%:*}"
        printf '%s' "$tmp"
    fi
}

# _tirith_extract_scheme URL
# Extract scheme from URL
# @pre: url is a non-empty string
# @post: prints scheme to stdout (empty if no scheme)
# @idempotent: yes
# @returns: 0
_tirith_extract_scheme() {
    local url="$1"

    if [[ "$url" == *"://"* ]]; then
        printf '%s' "${url%%://*}"
    fi
}

# _tirith_extract_port URL
# Extract port from URL
# @pre: url is a non-empty string
# @post: prints port to stdout (empty if no explicit port)
# @idempotent: yes
# @returns: 0
_tirith_extract_port() {
    local url="$1"

    if declare -F parse_url &>/dev/null; then
        local parsed
        parsed=$(parse_url "$url")
        # Extract port from JSON - it is numeric, not quoted
        if [[ "$parsed" == *"\"port\":"* ]]; then
            local port="${parsed#*\"port\":}"
            port="${port%%[,\}]*}"
            printf '%s' "$port"
        fi
    else
        # Simple extraction
        local tmp="$url"
        tmp="${tmp#*://}"
        tmp="${tmp%%/*}"
        tmp="${tmp%%\?*}"
        tmp="${tmp%%#*}"
        tmp="${tmp##*@}"
        if [[ "$tmp" == *":"* ]]; then
            local maybe_port="${tmp##*:}"
            if [[ "$maybe_port" =~ ^[0-9]+$ ]]; then
                printf '%s' "$maybe_port"
            fi
        fi
    fi
}

# _tirith_extract_path URL
# Extract path from URL
# @pre: url is a non-empty string
# @post: prints path to stdout (empty if no path)
# @idempotent: yes
# @returns: 0
_tirith_extract_path() {
    local url="$1"

    if declare -F parse_url &>/dev/null; then
        local parsed
        parsed=$(parse_url "$url")
        if [[ "$parsed" == *"\"path\":\""* ]]; then
            local path="${parsed#*\"path\":\"}"
            path="${path%%\"*}"
            printf '%s' "$path"
        fi
    else
        local tmp="$url"
        tmp="${tmp#*://}"
        # Remove userinfo
        if [[ "$tmp" == *"@"* ]]; then
            tmp="${tmp#*@}"
        fi
        if [[ "$tmp" == *"/"* ]]; then
            local path="/${tmp#*/}"
            # Strip query and fragment
            path="${path%%\?*}"
            path="${path%%#*}"
            printf '%s' "$path"
        fi
    fi
}

# _tirith_extract_userinfo URL
# Extract userinfo (user:pass@ portion) from URL
# @pre: url is a non-empty string
# @post: prints userinfo to stdout (empty if none)
# @idempotent: yes
# @returns: 0
_tirith_extract_userinfo() {
    local url="$1"

    local tmp="$url"
    # Strip scheme
    if [[ "$tmp" == *"://"* ]]; then
        tmp="${tmp#*://}"
    fi
    # Strip path
    tmp="${tmp%%/*}"
    tmp="${tmp%%\?*}"
    tmp="${tmp%%#*}"

    if [[ "$tmp" == *"@"* ]]; then
        printf '%s' "${tmp%%@*}"
    fi
}

# _tirith_extract_tld HOST
# Extract TLD from hostname
# @pre: host is a hostname string
# @post: prints TLD to stdout
# @idempotent: yes
# @returns: 0
_tirith_extract_tld() {
    local host="$1"
    # Remove trailing dot if present
    host="${host%.}"

    if [[ "$host" == *"."* ]]; then
        printf '%s' "${host##*.}"
    fi
}

# _tirith_skeleton DOMAIN
# Convert a domain to its ASCII skeleton by replacing confusable chars
# Short-circuits if input is pure ASCII
# @pre: domain is a non-empty string
# @post: prints skeleton to stdout
# @idempotent: yes
# @returns: 0
_tirith_skeleton() {
    local domain="$1"
    local skeleton=""
    local i=0 len=${#domain}

    # Fast path: pure ASCII
    local is_ascii=true
    while ((i < len)); do
        local byte
        printf -v byte '%d' "'${domain:i:1}"
        if ((byte > 127 || byte < 0)); then
            is_ascii=false
            break
        fi
        i=$((i + 1))
    done

    if $is_ascii; then
        printf '%s' "$domain"
        return 0
    fi

    # Slow path: check each character against confusables map
    # Note: bash ${str:i:1} returns one character which may be multi-byte in UTF-8.
    # Confusable map keys are stored as their UTF-8 byte sequences (e.g., $'\xd0\xbe').
    # Since bash handles multi-byte chars as single characters, we check 1-char
    # sequences against the map.
    i=0
    while ((i < len)); do
        local char="${domain:i:1}"
        local byte
        printf -v byte '%d' "'$char"

        if ((byte >= 0 && byte <= 127)); then
            # ASCII char - keep as-is
            skeleton+="$char"
        elif [[ -n "${_TIRITH_CONFUSABLES[$char]+x}" ]]; then
            # Multi-byte char found in confusables map
            skeleton+="${_TIRITH_CONFUSABLES[$char]}"
        else
            # Unknown non-ASCII char - keep as-is
            skeleton+="$char"
        fi
        i=$((i + 1))
    done

    printf '%s' "$skeleton"
}

# _tirith_has_non_ascii STRING
# Check if string contains non-ASCII bytes
# @pre: string is non-empty
# @post: returns 0 if non-ASCII found, 1 if pure ASCII
# @idempotent: yes
_tirith_has_non_ascii() {
    local str="$1"
    local i=0 len=${#str}

    while ((i < len)); do
        local byte
        printf -v byte '%d' "'${str:i:1}"
        if ((byte > 127 || byte < 0)); then
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# _tirith_path_contains_sink PATH
# Check if URL path contains a sensitive sink keyword
# @pre: path is a URL path string
# @post: returns 0 if sink found, 1 if clean
# @idempotent: yes
_tirith_path_contains_sink() {
    local path="${1,,}"  # lowercase for comparison
    local sink

    for sink in "${_TIRITH_SENSITIVE_SINKS[@]}"; do
        if [[ "$path" == *"$sink"* ]]; then
            return 0
        fi
    done
    return 1
}

# =============================================================================
# RULE 1: NON-ASCII HOSTNAME
# =============================================================================

# tirith_check_non_ascii_hostname URL [SOURCE]
# Detect hostnames containing non-ASCII characters (potential homograph attack)
# @pre: url is a non-empty URL string
# @post: adds finding if non-ASCII bytes found in hostname
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_non_ascii_hostname() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    if _tirith_has_non_ascii "$host"; then
        _tirith_add_finding "$source" "high" "NonAsciiHostname" \
            "Hostname contains non-ASCII characters (potential IDN homograph attack): ${host}"
        return 0
    fi
    return 1
}

# =============================================================================
# RULE 2: PUNYCODE DOMAIN
# =============================================================================

# tirith_check_punycode_domain URL [SOURCE]
# Detect punycode-encoded hostname labels (xn-- prefix)
# @pre: url is a non-empty URL string
# @post: adds finding if punycode labels found
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_punycode_domain() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    # Split hostname into labels and check for xn-- prefix
    local IFS='.'
    local -a labels
    read -ra labels <<< "$host"

    local label
    for label in "${labels[@]}"; do
        if [[ "${label,,}" == xn--* ]]; then
            _tirith_add_finding "$source" "high" "PunycodeDomain" \
                "Hostname contains punycode-encoded label '${label}' (internationalized domain, may hide real destination): ${host}"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# RULE 3: MIXED SCRIPT IN LABEL
# =============================================================================

# tirith_check_mixed_script URL [SOURCE]
# Detect hostname labels that mix ASCII letters with non-ASCII confusable chars
# @pre: url is a non-empty URL string
# @post: adds finding if mixed scripts found in any hostname label
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_mixed_script() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    # Split into labels
    local IFS='.'
    local -a labels
    read -ra labels <<< "$host"

    local label
    for label in "${labels[@]}"; do
        [[ -z "$label" ]] && continue

        local has_ascii=false
        local has_confusable=false
        local i=0 len=${#label}

        while ((i < len)); do
            local char="${label:i:1}"
            local byte
            printf -v byte '%d' "'$char"

            if ((byte >= 0 && byte <= 127)); then
                # Check if it is a letter (a-z, A-Z)
                if [[ "$char" =~ [a-zA-Z] ]]; then
                    has_ascii=true
                fi
                i=$((i + 1))
            else
                # Non-ASCII character - check if it maps to a confusable
                # bash ${str:i:1} already returns full multi-byte char
                has_confusable=true
                i=$((i + 1))
            fi

            if $has_ascii && $has_confusable; then
                _tirith_add_finding "$source" "high" "MixedScriptInLabel" \
                    "Hostname label '${label}' mixes ASCII and non-ASCII scripts (homograph risk): ${host}"
                return 0
            fi
        done
    done
    return 1
}

# =============================================================================
# RULE 4: USERINFO TRICK
# =============================================================================

# tirith_check_userinfo_trick URL [SOURCE]
# Detect user:pass@host pattern that disguises the real destination
# e.g. http://google.com@evil.com/path looks like google.com but goes to evil.com
# @pre: url is a non-empty URL string
# @post: adds finding if userinfo contains what looks like a domain
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_userinfo_trick() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local userinfo
    userinfo=$(_tirith_extract_userinfo "$url")
    [[ -z "$userinfo" ]] && return 1

    # Userinfo exists - this is suspicious in most contexts
    # Especially if userinfo contains a dot (looks like a domain)
    local user="${userinfo%%:*}"
    if [[ "$user" == *"."* ]]; then
        local real_host
        real_host=$(_tirith_extract_host "$url")
        _tirith_add_finding "$source" "high" "UserinfoTrick" \
            "URL contains userinfo '${user}' that resembles a domain, real destination is '${real_host}': ${url}"
        return 0
    fi

    # Even without dots, userinfo in URLs is suspicious
    _tirith_add_finding "$source" "high" "UserinfoTrick" \
        "URL contains userinfo component '${userinfo}' which may disguise the real destination: ${url}"
    return 0
}

# =============================================================================
# RULE 5: INVALID HOST CHARS
# =============================================================================

# tirith_check_invalid_host_chars URL [SOURCE]
# Detect characters that should not appear in hostnames
# @pre: url is a non-empty URL string
# @post: adds finding if invalid characters found in hostname
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_invalid_host_chars() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    # Characters that should not appear in hostnames
    # Spaces, angle brackets, braces, pipes, caret, tilde, square brackets
    local _invalid_host_pattern='[][:space:]<>{}|^~[]'
    if [[ "$host" =~ $_invalid_host_pattern ]]; then
        _tirith_add_finding "$source" "high" "InvalidHostChars" \
            "Hostname contains invalid characters (spaces, brackets, or special symbols): ${host}"
        return 0
    fi
    return 1
}

# =============================================================================
# RULE 6: TRAILING DOT / WHITESPACE
# =============================================================================

# tirith_check_trailing_dot_whitespace URL [SOURCE]
# Detect trailing dots or whitespace in hostname that could confuse DNS resolution
# @pre: url is a non-empty URL string
# @post: adds finding if trailing dot or whitespace found
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_trailing_dot_whitespace() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    local found_issue=false

    # Check for trailing dot (FQDN notation - can confuse some parsers)
    if [[ "$host" == *"." ]]; then
        _tirith_add_finding "$source" "medium" "TrailingDotWhitespace" \
            "Hostname has trailing dot (FQDN notation may confuse URL parsers): ${host}"
        found_issue=true
    fi

    # Check for leading/trailing whitespace
    local trimmed="$host"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ "$trimmed" != "$host" ]]; then
        _tirith_add_finding "$source" "medium" "TrailingDotWhitespace" \
            "Hostname contains leading or trailing whitespace: '${host}'"
        found_issue=true
    fi

    $found_issue && return 0
    return 1
}

# =============================================================================
# RULE 7: CONFUSABLE DOMAIN
# =============================================================================

# tirith_check_confusable_domain URL [SOURCE]
# Detect domains that look like well-known domains via confusable characters
# Uses skeleton comparison and Levenshtein distance (if fuzzy.sh loaded)
# @pre: url is a non-empty URL string
# @post: adds finding if domain skeleton matches a known domain
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_confusable_domain() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    # Lowercase for comparison
    local host_lower="${host,,}"

    # Generate skeleton of the input domain
    local skeleton
    skeleton=$(_tirith_skeleton "$host_lower")

    local known
    for known in "${_TIRITH_KNOWN_DOMAINS[@]}"; do
        # Exact match - not confusable, it IS the real domain
        if [[ "$host_lower" == "$known" ]]; then
            return 1
        fi

        # Skeleton match: domain looks like a known domain after confusable replacement
        if [[ "$skeleton" == "$known" ]]; then
            _tirith_add_finding "$source" "high" "ConfusableDomain" \
                "Domain '${host}' is visually confusable with '${known}' (skeleton match after confusable character substitution)"
            return 0
        fi
    done

    # Levenshtein near-miss check (if fuzzy.sh is loaded)
    if declare -F levenshtein_distance &>/dev/null; then
        local max_distance=2
        for known in "${_TIRITH_KNOWN_DOMAINS[@]}"; do
            # Skip if lengths differ too much (optimization)
            local len_diff=$(( ${#skeleton} - ${#known} ))
            if ((len_diff < 0)); then
                len_diff=$((-len_diff))
            fi
            if ((len_diff > max_distance)); then
                continue
            fi

            local dist
            dist=$(levenshtein_distance "$skeleton" "$known")
            if ((dist > 0 && dist <= max_distance)); then
                _tirith_add_finding "$source" "high" "ConfusableDomain" \
                    "Domain '${host}' is suspiciously similar to '${known}' (Levenshtein distance: ${dist})"
                return 0
            fi
        done
    fi

    return 1
}

# =============================================================================
# RULE 8: RAW IP URL
# =============================================================================

# tirith_check_raw_ip_url URL [SOURCE]
# Detect URLs that use raw IP addresses instead of hostnames
# @pre: url is a non-empty URL string
# @post: adds finding if URL uses a raw IP address
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_raw_ip_url() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    # Check for IPv4 using validation.sh if available
    if declare -F validate_ipv4 &>/dev/null; then
        if validate_ipv4 "$host"; then
            _tirith_add_finding "$source" "medium" "RawIpUrl" \
                "URL uses raw IPv4 address instead of hostname: ${host}"
            return 0
        fi
    else
        # Fallback: simple IPv4 pattern
        if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _tirith_add_finding "$source" "medium" "RawIpUrl" \
                "URL uses raw IPv4 address instead of hostname: ${host}"
            return 0
        fi
    fi

    # Check for IPv6 - may be wrapped in brackets in URLs
    local ipv6_host="$host"
    ipv6_host="${ipv6_host#\[}"
    ipv6_host="${ipv6_host%\]}"

    if declare -F validate_ipv6 &>/dev/null; then
        if validate_ipv6 "$ipv6_host"; then
            _tirith_add_finding "$source" "medium" "RawIpUrl" \
                "URL uses raw IPv6 address instead of hostname: ${host}"
            return 0
        fi
    else
        # Fallback: simple IPv6 pattern (contains colons and hex digits)
        if [[ "$ipv6_host" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ipv6_host" == *":"* ]]; then
            _tirith_add_finding "$source" "medium" "RawIpUrl" \
                "URL uses raw IPv6 address instead of hostname: ${host}"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# RULE 9: NON-STANDARD PORT
# =============================================================================

# tirith_check_non_standard_port URL [SOURCE]
# Flag URLs with ports other than 80 (http) or 443 (https)
# @pre: url is a non-empty URL string
# @post: adds finding if non-standard port detected
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_non_standard_port() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local port
    port=$(_tirith_extract_port "$url")

    # No explicit port - nothing to flag
    [[ -z "$port" ]] && return 1

    local scheme
    scheme=$(_tirith_extract_scheme "$url")
    scheme="${scheme,,}"

    # Standard ports per scheme
    case "$scheme" in
        http)
            if [[ "$port" != "80" ]]; then
                _tirith_add_finding "$source" "medium" "NonStandardPort" \
                    "HTTP URL uses non-standard port ${port} (expected 80): ${url}"
                return 0
            fi
            ;;
        https)
            if [[ "$port" != "443" ]]; then
                _tirith_add_finding "$source" "medium" "NonStandardPort" \
                    "HTTPS URL uses non-standard port ${port} (expected 443): ${url}"
                return 0
            fi
            ;;
        *)
            # Unknown scheme with explicit port
            _tirith_add_finding "$source" "medium" "NonStandardPort" \
                "URL uses explicit port ${port} with scheme '${scheme}': ${url}"
            return 0
            ;;
    esac

    return 1
}

# =============================================================================
# RULE 10: LOOKALIKE TLD
# =============================================================================

# tirith_check_lookalike_tld URL [SOURCE]
# Check if TLD is a lookalike that impersonates file extensions
# @pre: url is a non-empty URL string
# @post: adds finding if TLD is in the lookalike list
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_lookalike_tld() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    local tld
    tld=$(_tirith_extract_tld "$host")
    [[ -z "$tld" ]] && return 1

    local tld_lower="${tld,,}"
    local lookalike
    for lookalike in "${_TIRITH_LOOKALIKE_TLDS[@]}"; do
        if [[ "$tld_lower" == "$lookalike" ]]; then
            _tirith_add_finding "$source" "medium" "LookalikeTld" \
                "Domain uses lookalike TLD '.${tld}' that resembles a file extension: ${host}"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# RULE 11: PLAIN HTTP TO SENSITIVE SINK
# =============================================================================

# tirith_check_plain_http URL [SOURCE]
# Flag plain HTTP URLs that point to sensitive sinks (login, auth, payment, etc.)
# @pre: url is a non-empty URL string
# @post: adds finding if plain HTTP targets a sensitive endpoint
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_plain_http() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local scheme
    scheme=$(_tirith_extract_scheme "$url")

    # Only flag plain HTTP (not HTTPS, not other schemes)
    [[ "${scheme,,}" != "http" ]] && return 1

    local path
    path=$(_tirith_extract_path "$url")
    [[ -z "$path" ]] && return 1

    if _tirith_path_contains_sink "$path"; then
        # Identify which sink was matched
        local path_lower="${path,,}"
        local matched_sink=""
        local sink
        for sink in "${_TIRITH_SENSITIVE_SINKS[@]}"; do
            if [[ "$path_lower" == *"$sink"* ]]; then
                matched_sink="$sink"
                break
            fi
        done
        _tirith_add_finding "$source" "high" "PlainHttpToSink" \
            "Plain HTTP URL targets sensitive endpoint '${matched_sink}' (credentials transmitted in cleartext): ${url}"
        return 0
    fi
    return 1
}

# =============================================================================
# RULE 12: SCHEMELESS TO SINK
# =============================================================================

# tirith_check_schemeless URL [SOURCE]
# Flag URLs without scheme (e.g. //evil.com/login) pointing to sensitive sinks
# @pre: url is a non-empty URL string
# @post: adds finding if schemeless URL targets a sensitive endpoint
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_schemeless() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    # Check for protocol-relative URLs (//host/path) or no scheme at all
    local scheme
    scheme=$(_tirith_extract_scheme "$url")

    # If scheme is present, this is not a schemeless URL
    [[ -n "$scheme" ]] && return 1

    # Must start with // to be a protocol-relative URL
    [[ "$url" != "//"* ]] && return 1

    # Extract the path portion
    local tmp="${url#//}"
    local path=""
    if [[ "$tmp" == *"/"* ]]; then
        path="/${tmp#*/}"
        path="${path%%\?*}"
        path="${path%%#*}"
    fi

    [[ -z "$path" ]] && return 1

    if _tirith_path_contains_sink "$path"; then
        local path_lower="${path,,}"
        local matched_sink=""
        local sink
        for sink in "${_TIRITH_SENSITIVE_SINKS[@]}"; do
            if [[ "$path_lower" == *"$sink"* ]]; then
                matched_sink="$sink"
                break
            fi
        done
        _tirith_add_finding "$source" "medium" "SchemelessToSink" \
            "Schemeless URL targets sensitive endpoint '${matched_sink}' (protocol inheritance may downgrade to HTTP): ${url}"
        return 0
    fi
    return 1
}

# =============================================================================
# RULE 13: SHORTENED URL
# =============================================================================

# tirith_check_shortened_url URL [SOURCE]
# Detect URLs using known URL shortener domains
# @pre: url is a non-empty URL string
# @post: adds finding if URL uses a shortener domain
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_shortened_url() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local host
    host=$(_tirith_extract_host "$url")
    [[ -z "$host" ]] && return 1

    local host_lower="${host,,}"
    local shortener
    for shortener in "${_TIRITH_SHORTENERS[@]}"; do
        if [[ "$host_lower" == "$shortener" ]]; then
            _tirith_add_finding "$source" "medium" "ShortenedUrl" \
                "URL uses shortener domain '${shortener}' (hides real destination): ${url}"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# RULE 14: INSECURE TLS FLAGS
# =============================================================================

# tirith_check_insecure_tls CMD [SOURCE]
# Check command string for insecure TLS flags that disable certificate validation
# @pre: cmd is a non-empty command string
# @post: adds finding if insecure TLS flags found
# @idempotent: yes
# @returns: 0 if finding, 1 if clean
tirith_check_insecure_tls() {
    local cmd="$1"
    local source="${2:-url_scan}"

    [[ -z "$cmd" ]] && return 1

    local flag
    local found=false
    for flag in "${_TIRITH_INSECURE_TLS_FLAGS[@]}"; do
        # Use regex for patterns containing .* and plain match for others
        if [[ "$flag" == *".*"* ]]; then
            if [[ "$cmd" =~ $flag ]]; then
                _tirith_add_finding "$source" "high" "InsecureTlsFlags" \
                    "Command contains insecure TLS flag matching '${flag}' (disables certificate validation): ${cmd}"
                found=true
            fi
        else
            if [[ "$cmd" == *"$flag"* ]]; then
                _tirith_add_finding "$source" "high" "InsecureTlsFlags" \
                    "Command contains insecure TLS flag '${flag}' (disables certificate validation): ${cmd}"
                found=true
            fi
        fi
    done

    $found && return 0
    return 1
}

# =============================================================================
# AGGREGATE SCANNER
# =============================================================================

# tirith_scan_url_checks URL [SOURCE]
# Run all URL security checks against a URL
# @pre: url is a non-empty URL string
# @post: runs all 13 URL-specific checks (excludes insecure_tls which takes a command)
# @idempotent: yes
# @returns: 0 if any findings, 1 if clean
#
# Usage: tirith_scan_url_checks "https://gооgle.com/login"
# Usage: tirith_scan_url_checks "http://google.com@evil.com/auth" "code_review"
tirith_scan_url_checks() {
    local url="$1"
    local source="${2:-url_scan}"

    [[ -z "$url" ]] && return 1

    local count_before=${#_TIRITH_FINDINGS[@]}

    # Run all URL checks - order: cheap checks first, expensive last
    # Each check returns 0 on finding, 1 on clean; use || true to prevent set -e exits
    tirith_check_invalid_host_chars "$url" "$source" || true
    tirith_check_trailing_dot_whitespace "$url" "$source" || true
    tirith_check_userinfo_trick "$url" "$source" || true
    tirith_check_non_ascii_hostname "$url" "$source" || true
    tirith_check_punycode_domain "$url" "$source" || true
    tirith_check_mixed_script "$url" "$source" || true
    tirith_check_raw_ip_url "$url" "$source" || true
    tirith_check_non_standard_port "$url" "$source" || true
    tirith_check_lookalike_tld "$url" "$source" || true
    tirith_check_shortened_url "$url" "$source" || true
    tirith_check_plain_http "$url" "$source" || true
    tirith_check_schemeless "$url" "$source" || true
    tirith_check_confusable_domain "$url" "$source" || true

    # Return 0 if any new findings were added
    local count_after=${#_TIRITH_FINDINGS[@]}
    ((count_after > count_before)) && return 0
    return 1
}

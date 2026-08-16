#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/netscan.sh - Network Scanning & Service Detection
# =============================================================================
# Description: Pure-bash network utilities for port checking, host discovery,
#              banner grabbing, and HTTP header extraction. Designed for
#              defensive administration and AI-automated infrastructure checks.
# Version: 1.0.0
# Requires: Bash 4.0+, /dev/tcp (or nc/ncat/nmap for fallback)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_NETSCAN_LOADED:-}" ]] && return 0

# http.sh owns the canonical http_headers dispatcher. Loading it explicitly
# keeps direct `source lib/netscan.sh` usage compatible with common.sh loading.
source "${BASH_SOURCE[0]%/*}/http.sh"

readonly _MAINFRAME_NETSCAN_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default timeout for network operations (seconds)
MAINFRAME_NET_TIMEOUT="${MAINFRAME_NET_TIMEOUT:-3}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Validate hostname format (RFC 1123 compliant)
# Usage: _netscan_validate_host "example.com"
# Returns: 0 if valid, 1 if invalid
_netscan_validate_host() {
    local host="$1"

    # Empty check
    [[ -z "$host" ]] && return 1

    # Length check (max 253 chars)
    [[ ${#host} -gt 253 ]] && return 1

    # IPv4 address (simple validation)
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local IFS='.'
        read -ra octets <<< "$host"
        for octet in "${octets[@]}"; do
            [[ "$octet" =~ ^[0-9]+$ ]] || return 1
            (( octet >= 0 && octet <= 255 )) || return 1
        done
        return 0
    fi

    # RFC 1123 hostname validation
    # Labels: alphanumeric, hyphens (not at start/end), 1-63 chars each
    local label_re='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
    local IFS='.'
    read -ra labels <<< "$host"

    for label in "${labels[@]}"; do
        [[ -z "$label" ]] && return 1
        [[ ${#label} -gt 63 ]] && return 1
        [[ "$label" =~ $label_re ]] || return 1
    done

    return 0
}

_netscan_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Check if /dev/tcp is available (bash compiled with net redirections)
_netscan_has_dev_tcp() {
    (echo >/dev/tcp/127.0.0.1/1 2>/dev/null) 2>/dev/null
    # Can't actually test without a known open port, check if bash supports it
    [[ -n "${BASH_VERSINFO:-}" ]]
}

# =============================================================================
# PORT CHECKING
# =============================================================================

# @pre: host is resolvable, port is 1-65535
# @post: returns 0 if port is open, 1 if closed/filtered
# @idempotent: yes
# @returns: 0 if open, 1 if closed, 2 on error
#
# Check if a TCP port is open on a host. Uses /dev/tcp first,
# falls back to nc/ncat if available.
#
# Usage: port_check "host" port [timeout_seconds]
# Example: port_check "localhost" 8080
# Example: port_check "192.168.1.1" 22 5
port_check() {
    local host="$1"
    local port="$2"
    local timeout="${3:-$MAINFRAME_NET_TIMEOUT}"

    if [[ -z "$host" ]] || [[ -z "$port" ]]; then
        return 2
    fi

    # Validate hostname format (Security: prevent injection)
    if ! _netscan_validate_host "$host"; then
        return 2
    fi

    # Validate port range
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        return 2
    fi

    # Try /dev/tcp first (fastest, no fork)
    if (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
        return 0
    fi

    # Try nc/ncat with timeout
    if command -v nc &>/dev/null; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null && return 0
    elif command -v ncat &>/dev/null; then
        ncat -z -w "$timeout" "$host" "$port" 2>/dev/null && return 0
    fi

    return 1
}

# =============================================================================
# HOST DISCOVERY
# =============================================================================

# @pre: host is a hostname or IP address
# @post: returns 0 if host responds, 1 if not
# @idempotent: yes
# @returns: 0 if alive, 1 if not reachable
#
# Check if a host is alive using ping (ICMP) or TCP fallback.
#
# Usage: host_alive "host" [timeout_seconds]
# Example: host_alive "192.168.1.1"
# Example: host_alive "google.com" 5
host_alive() {
    local host="$1"
    local timeout="${2:-$MAINFRAME_NET_TIMEOUT}"

    if [[ -z "$host" ]]; then
        return 2
    fi

    # Try ping first
    if command -v ping &>/dev/null; then
        if [[ "$OSTYPE" == darwin* ]]; then
            ping -c 1 -W "$((timeout * 1000))" "$host" &>/dev/null && return 0
        else
            ping -c 1 -W "$timeout" "$host" &>/dev/null && return 0
        fi
    fi

    # TCP fallback: try common ports
    local p
    for p in 80 443 22; do
        if port_check "$host" "$p" "$timeout"; then
            return 0
        fi
    done

    return 1
}

# =============================================================================
# BANNER GRABBING
# =============================================================================

# @pre: host:port is accessible
# @post: prints service banner (first line of response)
# @idempotent: yes
# @returns: 0 on success, 1 if no banner received
#
# Grab the service banner from an open port. Connects and reads
# the first response line (useful for SSH, SMTP, FTP, etc.).
#
# Usage: banner=$(banner_grab "host" port [timeout])
# Example: banner=$(banner_grab "192.168.1.1" 22)
banner_grab() {
    local host="$1"
    local port="$2"
    local timeout="${3:-$MAINFRAME_NET_TIMEOUT}"

    if [[ -z "$host" ]] || [[ -z "$port" ]]; then
        return 1
    fi

    # Validate hostname format (Security: prevent injection)
    if ! _netscan_validate_host "$host"; then
        return 1
    fi

    local banner=""

    # Try with /dev/tcp
    if banner=$(timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port 2>/dev/null; read -r -t $timeout line <&3; printf '%s' \"\$line\"; exec 3>&-" 2>/dev/null); then
        if [[ -n "$banner" ]]; then
            printf '%s' "$banner"
            return 0
        fi
    fi

    # Try with nc
    if command -v nc &>/dev/null; then
        banner=$(echo "" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
        if [[ -n "$banner" ]]; then
            printf '%s' "$banner"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# HTTP OPERATIONS
# =============================================================================

# @pre: url is a valid HTTP/HTTPS URL or host:port
# @post: prints HTTP response headers as JSON
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Extract HTTP response headers from a URL. Uses curl if available,
# falls back to /dev/tcp for HTTP (not HTTPS).
#
# Usage: headers=$(netscan_http_headers "http://example.com")
# Example: headers=$(netscan_http_headers "localhost:8080")
netscan_http_headers() {
    local url="${1:-}"
    local timeout="${2:-$MAINFRAME_NET_TIMEOUT}"

    if [[ -z "$url" ]]; then
        return 1
    fi

    # Add http:// if no scheme
    if [[ "$url" != http://* ]] && [[ "$url" != https://* ]]; then
        url="http://$url"
    fi

    local headers=""

    # Use curl if available (handles HTTPS)
    if command -v curl &>/dev/null; then
        headers=$(curl -sI -m "$timeout" "$url" 2>/dev/null)
    elif command -v wget &>/dev/null; then
        headers=$(wget -qS --timeout="$timeout" -O /dev/null "$url" 2>&1 | head -20)
    fi

    if [[ -z "$headers" ]]; then
        return 1
    fi

    # Parse headers into JSON
    local json="{"
    local first=true
    local line key value status_line=""

    while IFS= read -r line; do
        # Remove trailing CR
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue

        # First line is status
        if [[ "$line" == HTTP/* ]]; then
            status_line="$line"
            continue
        fi

        # Parse key: value
        if [[ "$line" == *": "* ]]; then
            key="${line%%: *}"
            value="${line#*: }"

            local escaped_key escaped_value
            escaped_key=$(_netscan_escape "$key")
            escaped_value=$(_netscan_escape "$value")

            if [[ "$first" == "true" ]]; then
                first=false
            else
                json+=","
            fi
            json+="\"$escaped_key\":\"$escaped_value\""
        fi
    done <<< "$headers"

    if [[ -n "$status_line" ]]; then
        local escaped_status
        escaped_status=$(_netscan_escape "$status_line")
        if [[ "$first" != "true" ]]; then
            json+=","
        fi
        json+="\"_status\":\"$escaped_status\""
    fi

    json+="}"
    printf '%s' "$json"
    return 0
}

# =============================================================================
# PORT MONITORING
# =============================================================================

# @pre: host:port combination specified
# @post: prints JSON with port state and optional change detection
# @idempotent: yes
# @returns: 0
#
# Check port state and return structured JSON result.
# Useful for watchdog scripts and monitoring loops.
#
# Usage: result=$(monitor_port "host" port)
# Example: result=$(monitor_port "localhost" 5432)
monitor_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-$MAINFRAME_NET_TIMEOUT}"

    if [[ -z "$host" ]] || [[ -z "$port" ]]; then
        printf '{"error":"host and port required"}'
        return 1
    fi

    local state="closed"
    local banner=""

    if port_check "$host" "$port" "$timeout"; then
        state="open"
        banner=$(banner_grab "$host" "$port" "$timeout" 2>/dev/null) || banner=""
    fi

    local escaped_host escaped_banner
    escaped_host=$(_netscan_escape "$host")
    escaped_banner=$(_netscan_escape "$banner")

    local timestamp
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        timestamp="$EPOCHSECONDS"
    else
        timestamp=$(date +%s)
    fi

    local json
    json="{\"host\":\"$escaped_host\",\"port\":$port,\"state\":\"$state\",\"timestamp\":$timestamp"
    if [[ -n "$banner" ]]; then
        json+=",\"banner\":\"$escaped_banner\""
    fi
    json+="}"

    printf '%s' "$json"
}

# =============================================================================
# RANGE SCANNING
# =============================================================================

# @pre: host is valid, ports is a comma-separated list or range (e.g., "22,80,443" or "1-1024")
# @post: prints JSON array of open ports
# @idempotent: yes
# @returns: 0
#
# Scan a host for open ports from a list or range.
# Returns JSON array of results.
#
# Usage: results=$(scan_range "host" "port_list" [timeout])
# Example: scan_range "localhost" "22,80,443,8080"
# Example: scan_range "192.168.1.1" "1-100"
scan_range() {
    local host="$1"
    local ports="$2"
    local timeout="${3:-1}"

    if [[ -z "$host" ]] || [[ -z "$ports" ]]; then
        printf '[]'
        return 1
    fi

    local port_list=()

    # Parse port specification
    if [[ "$ports" == *"-"* ]] && [[ "$ports" != *","* ]]; then
        # Range: start-end
        local start_port="${ports%%-*}"
        local end_port="${ports##*-}"
        local p
        for ((p=start_port; p<=end_port; p++)); do
            port_list+=("$p")
        done
    else
        # Comma-separated list
        IFS=',' read -ra port_list <<< "$ports"
    fi

    local json="["
    local first=true

    for port in "${port_list[@]}"; do
        port="${port// /}"  # trim whitespace
        [[ -z "$port" ]] && continue
        [[ ! "$port" =~ ^[0-9]+$ ]] && continue

        local state="closed"
        if port_check "$host" "$port" "$timeout"; then
            state="open"
        fi

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="{\"port\":$port,\"state\":\"$state\"}"
    done

    json+="]"
    printf '%s' "$json"
}

# =============================================================================
# NMAP OUTPUT PARSING
# =============================================================================

# @pre: input is nmap greppable output (-oG format)
# @post: prints JSON array of parsed hosts/ports
# @idempotent: yes
# @returns: 0
#
# Parse nmap greppable output (-oG) into structured JSON.
# Each host becomes a JSON object with IP, hostname, and open ports.
#
# Usage: result=$(parse_nmap < scan_results.gnmap)
# Example: nmap -oG - 192.168.1.0/24 | parse_nmap
parse_nmap() {
    local input=""
    if [[ $# -gt 0 ]]; then
        input="$1"
    else
        input=$(cat)
    fi

    if [[ -z "$input" ]]; then
        printf '[]'
        return 0
    fi

    local json="["
    local first_host=true
    local line

    while IFS= read -r line; do
        # Skip comments and status lines
        [[ "$line" == "#"* ]] && continue
        [[ "$line" != *"Ports:"* ]] && continue

        # Parse: Host: IP (hostname) ... Ports: port/state/protocol/...
        local ip="" hostname="" ports_str=""

        # Extract IP
        if [[ "$line" =~ Host:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            ip="${BASH_REMATCH[1]}"
        fi

        # Extract hostname (regex stored in var to avoid parser issues with parens)
        local _hostname_re='\(([^)]+)\)'
        if [[ "$line" =~ $_hostname_re ]]; then
            hostname="${BASH_REMATCH[1]}"
        fi

        # Extract ports section
        if [[ "$line" == *"Ports: "* ]]; then
            ports_str="${line#*Ports: }"
            # Remove anything after next tab-separated field
            ports_str="${ports_str%%	*}"
        fi

        [[ -z "$ip" ]] && continue

        if [[ "$first_host" == "true" ]]; then
            first_host=false
        else
            json+=","
        fi

        local escaped_ip escaped_hostname
        escaped_ip=$(_netscan_escape "$ip")
        escaped_hostname=$(_netscan_escape "$hostname")

        json+="{\"ip\":\"$escaped_ip\""
        [[ -n "$hostname" ]] && json+=",\"hostname\":\"$escaped_hostname\""

        # Parse individual ports
        json+=",\"ports\":["
        local first_port=true
        IFS=',' read -ra port_entries <<< "$ports_str"
        for entry in "${port_entries[@]}"; do
            entry="${entry## }"  # trim leading space
            # Format: port/state/protocol/owner/service/...
            IFS='/' read -ra parts <<< "$entry"
            local p_num="${parts[0]:-}"
            local p_state="${parts[1]:-}"
            local p_proto="${parts[2]:-}"
            local p_service="${parts[4]:-}"

            [[ -z "$p_num" ]] && continue

            if [[ "$first_port" == "true" ]]; then
                first_port=false
            else
                json+=","
            fi

            local escaped_service
            escaped_service=$(_netscan_escape "$p_service")

            json+="{\"port\":$p_num,\"state\":\"$p_state\",\"protocol\":\"$p_proto\""
            [[ -n "$p_service" ]] && json+=",\"service\":\"$escaped_service\""
            json+="}"
        done
        json+="]}"

    done <<< "$input"

    json+="]"
    printf '%s' "$json"
}

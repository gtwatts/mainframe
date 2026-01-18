#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/health.sh - Health Check Framework
# =============================================================================
# Description: Register, run, and monitor health checks for services
# Features:    Check registration, built-in checks, JSON output, HTTP server
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_HEALTH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_HEALTH_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Health check storage
declare -gA _HEALTH_CHECKS=()
declare -gA _HEALTH_RESULTS=()
declare -gA _HEALTH_TIMESTAMPS=()
declare -gA _HEALTH_MESSAGES=()

# Default timeouts
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"
HEALTH_HTTP_TIMEOUT="${HEALTH_HTTP_TIMEOUT:-3}"

# =============================================================================
# REGISTRATION
# =============================================================================

# Register a health check
# Usage: health::register "name" "command"
# Example: health::register "database" 'pg_isready -h localhost'
health::register() {
    local name="$1"
    local command="$2"
    
    [[ -z "$name" ]] && return 1
    [[ -z "$command" ]] && return 1
    
    _HEALTH_CHECKS["$name"]="$command"
}

# Unregister a health check
# Usage: health::unregister "name"
health::unregister() {
    local name="$1"
    unset "_HEALTH_CHECKS[$name]"
    unset "_HEALTH_RESULTS[$name]"
    unset "_HEALTH_TIMESTAMPS[$name]"
    unset "_HEALTH_MESSAGES[$name]"
}

# List all registered health checks
# Usage: health::list
health::list() {
    local name
    for name in "${!_HEALTH_CHECKS[@]}"; do
        printf '%s\n' "$name"
    done
}

# Clear all health checks
# Usage: health::clear
health::clear() {
    _HEALTH_CHECKS=()
    _HEALTH_RESULTS=()
    _HEALTH_TIMESTAMPS=()
    _HEALTH_MESSAGES=()
}

# =============================================================================
# RUNNING CHECKS
# =============================================================================

# Run a specific health check
# Usage: health::run "name"
# Returns: 0 if healthy, 1 if unhealthy
health::run() {
    local name="$1"
    local command="${_HEALTH_CHECKS[$name]:-}"
    local output
    local status
    
    if [[ -z "$command" ]]; then
        _HEALTH_RESULTS["$name"]="unknown"
        _HEALTH_MESSAGES["$name"]="Check not registered"
        _HEALTH_TIMESTAMPS["$name"]=$(date +%s)
        return 2
    fi
    
    # Execute the check with timeout
    output=$(timeout "$HEALTH_CHECK_TIMEOUT" bash -c "$command" 2>&1)
    status=$?
    
    _HEALTH_TIMESTAMPS["$name"]=$(date +%s)
    
    if [[ $status -eq 0 ]]; then
        _HEALTH_RESULTS["$name"]="healthy"
        _HEALTH_MESSAGES["$name"]="${output:-OK}"
        return 0
    elif [[ $status -eq 124 ]]; then
        _HEALTH_RESULTS["$name"]="unhealthy"
        _HEALTH_MESSAGES["$name"]="Timeout after ${HEALTH_CHECK_TIMEOUT}s"
        return 1
    else
        _HEALTH_RESULTS["$name"]="unhealthy"
        _HEALTH_MESSAGES["$name"]="${output:-Check failed with status $status}"
        return 1
    fi
}

# Run all registered health checks
# Usage: health::run_all
# Returns: 0 if all healthy, 1 if any unhealthy
health::run_all() {
    local name
    local all_healthy=0
    
    for name in "${!_HEALTH_CHECKS[@]}"; do
        health::run "$name" || all_healthy=1
    done
    
    return $all_healthy
}

# Check if a specific check is healthy
# Usage: health::is_healthy "name"
health::is_healthy() {
    local name="$1"
    [[ "${_HEALTH_RESULTS[$name]:-}" == "healthy" ]]
}

# Check if all checks are healthy (ready)
# Usage: health::is_ready
health::is_ready() {
    local name
    for name in "${!_HEALTH_CHECKS[@]}"; do
        [[ "${_HEALTH_RESULTS[$name]:-}" == "healthy" ]] || return 1
    done
    return 0
}

# Check if any check is healthy (live)
# Usage: health::is_live
health::is_live() {
    local name
    for name in "${!_HEALTH_CHECKS[@]}"; do
        [[ "${_HEALTH_RESULTS[$name]:-}" == "healthy" ]] && return 0
    done
    [[ ${#_HEALTH_CHECKS[@]} -eq 0 ]]  # Empty checks = live
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

# Escape string for JSON
_health_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Get status as JSON
# Usage: health::status
health::status() {
    local name
    local overall_status="healthy"
    local checks_json=""
    local first=true
    local now
    now=$(date +%s)
    
    # Determine overall status
    for name in "${!_HEALTH_CHECKS[@]}"; do
        if [[ "${_HEALTH_RESULTS[$name]:-unknown}" != "healthy" ]]; then
            overall_status="unhealthy"
            break
        fi
    done
    
    # Build checks JSON
    for name in "${!_HEALTH_CHECKS[@]}"; do
        local status="${_HEALTH_RESULTS[$name]:-unknown}"
        local message="${_HEALTH_MESSAGES[$name]:-Not checked}"
        local timestamp="${_HEALTH_TIMESTAMPS[$name]:-0}"
        local age=$((now - timestamp))
        
        $first || checks_json+=","
        first=false
        
        checks_json+="\"$name\":{\"status\":\"$status\",\"message\":\"$(_health_json_escape "$message")\",\"timestamp\":$timestamp,\"age_seconds\":$age}"
    done
    
    printf '{"status":"%s","checks":{%s},"timestamp":%d}' \
        "$overall_status" "$checks_json" "$now"
}

# Get status as pretty JSON
# Usage: health::status_pretty
health::status_pretty() {
    local json
    json=$(health::status)
    
    # Simple pretty print
    printf '%s\n' "$json" | sed 's/,"/,\n  "/g; s/{"/{\n  "/g; s/}}/\n  }\n}/g'
}

# =============================================================================
# BUILT-IN CHECKS
# =============================================================================

# Check HTTP endpoint
# Usage: health::check_http "http://localhost:8080/health" [expected_code]
health::check_http() {
    local url="$1"
    local expected="${2:-200}"
    local code
    
    if command -v curl &>/dev/null; then
        code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time "$HEALTH_HTTP_TIMEOUT" "$url" 2>/dev/null) || code="000"
    elif command -v wget &>/dev/null; then
        code=$(wget -q --spider --server-response --timeout="$HEALTH_HTTP_TIMEOUT" "$url" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}') || code="000"
    else
        echo "No HTTP client available (curl or wget)"
        return 1
    fi
    
    if [[ "$code" == "$expected" ]]; then
        echo "HTTP $code"
        return 0
    else
        echo "HTTP $code (expected $expected)"
        return 1
    fi
}

# Check TCP connection
# Usage: health::check_tcp "localhost" 5432 [timeout]
health::check_tcp() {
    local host="$1"
    local port="$2"
    local timeout="${3:-$HEALTH_CHECK_TIMEOUT}"
    
    if command -v nc &>/dev/null; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            echo "TCP $host:$port open"
            return 0
        fi
    elif [[ -e /dev/tcp/$host/$port ]]; then
        # Bash built-in TCP support
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            echo "TCP $host:$port open"
            return 0
        fi
    else
        # Fallback using /dev/tcp directly
        if timeout "$timeout" bash -c ": </dev/tcp/$host/$port" 2>/dev/null; then
            echo "TCP $host:$port open"
            return 0
        fi
    fi
    
    echo "TCP $host:$port closed"
    return 1
}

# Check disk usage
# Usage: health::check_disk "/" 90
health::check_disk() {
    local path="${1:-/}"
    local threshold="${2:-90}"
    local usage
    
    usage=$(df -P "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    
    if [[ -z "$usage" ]]; then
        echo "Cannot check disk at $path"
        return 1
    fi
    
    if [[ $usage -lt $threshold ]]; then
        echo "Disk ${usage}% used (threshold: ${threshold}%)"
        return 0
    else
        echo "Disk ${usage}% used exceeds threshold ${threshold}%"
        return 1
    fi
}

# Check memory usage
# Usage: health::check_memory 80
health::check_memory() {
    local threshold="${1:-80}"
    local usage
    
    if [[ -f /proc/meminfo ]]; then
        local total available
        total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        
        if [[ -n "$total" && -n "$available" && "$total" -gt 0 ]]; then
            usage=$(( (total - available) * 100 / total ))
        fi
    elif command -v vm_stat &>/dev/null; then
        # macOS
        # shellcheck disable=SC2034  # These variables are set via eval from vm_stat output
        local pages_free pages_active pages_inactive pages_speculative pages_wired page_size
        page_size=$(pagesize 2>/dev/null || echo 4096)
        # shellcheck disable=SC2046  # Word splitting is intentional for eval
        eval $(vm_stat | awk -v ps="$page_size" '
            /Pages free/ {free=$3}
            /Pages active/ {active=$3}
            /Pages inactive/ {inactive=$3}
            /Pages wired/ {wired=$3}
            END {
                gsub(/\./, "", free); gsub(/\./, "", active)
                gsub(/\./, "", inactive); gsub(/\./, "", wired)
                total = free + active + inactive + wired
                used = active + wired
                if (total > 0) printf "usage=%d", (used * 100 / total)
            }
        ')
    fi
    
    if [[ -z "${usage:-}" ]]; then
        echo "Cannot determine memory usage"
        return 1
    fi
    
    if [[ $usage -lt $threshold ]]; then
        echo "Memory ${usage}% used (threshold: ${threshold}%)"
        return 0
    else
        echo "Memory ${usage}% used exceeds threshold ${threshold}%"
        return 1
    fi
}

# Check if process is running
# Usage: health::check_process "nginx"
health::check_process() {
    local process="$1"
    local count
    
    count=$(pgrep -c "$process" 2>/dev/null) || count=0
    
    if [[ $count -gt 0 ]]; then
        echo "Process '$process' running ($count instances)"
        return 0
    else
        echo "Process '$process' not found"
        return 1
    fi
}

# Check if file exists
# Usage: health::check_file_exists "/var/run/app.pid"
health::check_file_exists() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        echo "File '$file' exists"
        return 0
    else
        echo "File '$file' not found"
        return 1
    fi
}

# Check if port is open (listening)
# Usage: health::check_port_open 8080
health::check_port_open() {
    local port="$1"
    
    if command -v ss &>/dev/null; then
        if ss -tln | grep -q ":$port "; then
            echo "Port $port is listening"
            return 0
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tln | grep -q ":$port "; then
            echo "Port $port is listening"
            return 0
        fi
    elif command -v lsof &>/dev/null; then
        if lsof -i ":$port" -P -n | grep -q LISTEN; then
            echo "Port $port is listening"
            return 0
        fi
    else
        echo "No tool available to check port (ss, netstat, or lsof)"
        return 1
    fi
    
    echo "Port $port is not listening"
    return 1
}

# Check command exists
# Usage: health::check_command "docker"
health::check_command() {
    local cmd="$1"
    
    if command -v "$cmd" &>/dev/null; then
        echo "Command '$cmd' available"
        return 0
    else
        echo "Command '$cmd' not found"
        return 1
    fi
}

# Check URL returns expected content
# Usage: health::check_http_content "http://localhost/health" "OK"
health::check_http_content() {
    local url="$1"
    local expected="$2"
    local content
    
    if command -v curl &>/dev/null; then
        content=$(curl -sf --max-time "$HEALTH_HTTP_TIMEOUT" "$url" 2>/dev/null) || {
            echo "Failed to fetch $url"
            return 1
        }
    elif command -v wget &>/dev/null; then
        content=$(wget -qO- --timeout="$HEALTH_HTTP_TIMEOUT" "$url" 2>/dev/null) || {
            echo "Failed to fetch $url"
            return 1
        }
    else
        echo "No HTTP client available"
        return 1
    fi
    
    if [[ "$content" == *"$expected"* ]]; then
        echo "Content contains '$expected'"
        return 0
    else
        echo "Content does not contain '$expected'"
        return 1
    fi
}

# =============================================================================
# CONTINUOUS MONITORING
# =============================================================================

# Watch health checks continuously
# Usage: health::watch --interval 30 --on-failure 'alert::send'
health::watch() {
    local interval=30
    local on_failure=""
    local on_recovery=""
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval|-i)
                interval="$2"
                shift 2
                ;;
            --on-failure|-f)
                on_failure="$2"
                shift 2
                ;;
            --on-recovery|-r)
                on_recovery="$2"
                shift 2
                ;;
            --verbose|-v)
                verbose=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local prev_status=""
    
    while true; do
        health::run_all
        local current_status
        health::is_ready && current_status="healthy" || current_status="unhealthy"
        
        if $verbose; then
            printf '[%s] Status: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$current_status"
        fi
        
        # Handle state transitions
        if [[ "$current_status" == "unhealthy" && "$prev_status" != "unhealthy" ]]; then
            if [[ -n "$on_failure" ]]; then
                eval "$on_failure" "$(health::status)"
            fi
        elif [[ "$current_status" == "healthy" && "$prev_status" == "unhealthy" ]]; then
            if [[ -n "$on_recovery" ]]; then
                eval "$on_recovery" "$(health::status)"
            fi
        fi
        
        prev_status="$current_status"
        sleep "$interval"
    done
}

# =============================================================================
# HEALTH HTTP SERVER
# =============================================================================

# Start a simple HTTP health server using netcat
# Usage: health::serve [port]
# GET /health      - Full JSON status
# GET /health/live - 200 if any check passes, 503 otherwise
# GET /health/ready - 200 if all checks pass, 503 otherwise
health::serve() {
    local port="${1:-8081}"
    
    # Check if nc (netcat) is available
    if ! command -v nc &>/dev/null; then
        echo "Error: netcat (nc) required for health server" >&2
        return 1
    fi
    
    echo "Starting health server on port $port..."
    echo "Endpoints:"
    echo "  GET /health       - Full JSON status"
    echo "  GET /health/live  - Liveness probe"
    echo "  GET /health/ready - Readiness probe"
    echo ""
    
    while true; do
        # Handle HTTP request
        {
            local request=""
            local line
            
            # Read HTTP request
            while IFS= read -r line; do
                line="${line%$'\r'}"
                [[ -z "$line" ]] && break
                [[ -z "$request" ]] && request="$line"
            done
            
            # Parse method and path (method kept for logging/debugging)
            local path method
            # shellcheck disable=SC2034  # method kept for debugging/logging
            read -r method path _ <<< "$request"
            
            local status_code="200"
            local status_text="OK"
            local content_type="application/json"
            local body=""
            
            # Run checks before responding
            health::run_all >/dev/null 2>&1
            
            case "$path" in
                /health|/health/)
                    body=$(health::status)
                    health::is_ready || { status_code="503"; status_text="Service Unavailable"; }
                    ;;
                /health/live|/health/live/)
                    if health::is_live; then
                        body='{"status":"live"}'
                    else
                        status_code="503"
                        status_text="Service Unavailable"
                        body='{"status":"not live"}'
                    fi
                    ;;
                /health/ready|/health/ready/)
                    if health::is_ready; then
                        body='{"status":"ready"}'
                    else
                        status_code="503"
                        status_text="Service Unavailable"
                        body='{"status":"not ready"}'
                    fi
                    ;;
                *)
                    status_code="404"
                    status_text="Not Found"
                    body='{"error":"Not Found"}'
                    ;;
            esac
            
            local content_length=${#body}
            
            # Send HTTP response
            printf 'HTTP/1.1 %s %s\r\n' "$status_code" "$status_text"
            printf 'Content-Type: %s\r\n' "$content_type"
            printf 'Content-Length: %d\r\n' "$content_length"
            printf 'Connection: close\r\n'
            printf '\r\n'
            printf '%s' "$body"
            
        } | nc -l -p "$port" -q 1 2>/dev/null || nc -l "$port" 2>/dev/null
    done
}

# Start health server in background
# Usage: health::serve_background [port]
# Returns: PID of server
health::serve_background() {
    local port="${1:-8081}"
    
    health::serve "$port" &
    local pid=$!
    
    echo "$pid"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get summary of all checks
# Usage: health::summary
health::summary() {
    local total=${#_HEALTH_CHECKS[@]}
    local healthy=0
    local unhealthy=0
    local unknown=0
    local name
    
    for name in "${!_HEALTH_CHECKS[@]}"; do
        case "${_HEALTH_RESULTS[$name]:-unknown}" in
            healthy)   ((healthy++)) ;;
            unhealthy) ((unhealthy++)) ;;
            *)         ((unknown++)) ;;
        esac
    done
    
    printf 'Total: %d | Healthy: %d | Unhealthy: %d | Unknown: %d\n' \
        "$total" "$healthy" "$unhealthy" "$unknown"
}

# Print human-readable status
# Usage: health::print
health::print() {
    local name
    local now
    now=$(date +%s)
    
    printf '%-20s %-10s %s\n' "CHECK" "STATUS" "MESSAGE"
    printf '%s\n' "$(printf '%.0s-' {1..60})"
    
    for name in "${!_HEALTH_CHECKS[@]}"; do
        local status="${_HEALTH_RESULTS[$name]:-unknown}"
        local message="${_HEALTH_MESSAGES[$name]:-Not checked}"
        local color=""
        local reset=""
        
        # Add colors if terminal supports it
        if [[ -t 1 ]]; then
            case "$status" in
                healthy)   color='\033[32m'; reset='\033[0m' ;;
                unhealthy) color='\033[31m'; reset='\033[0m' ;;
                *)         color='\033[33m'; reset='\033[0m' ;;
            esac
        fi
        
        printf '%-20s %b%-10s%b %s\n' "$name" "$color" "$status" "$reset" "$message"
    done
    
    printf '%s\n' "$(printf '%.0s-' {1..60})"
    health::summary
}

# Export results to environment variables
# Usage: health::export_env [prefix]
health::export_env() {
    local prefix="${1:-HEALTH}"
    local name
    
    for name in "${!_HEALTH_CHECKS[@]}"; do
        local var_name="${prefix}_${name^^}"
        # shellcheck disable=SC2031  # var_name is not modified in subshell
        var_name="${var_name//[^A-Z0-9_]/_}"
        export "${var_name}=${_HEALTH_RESULTS[$name]:-unknown}"
    done
}


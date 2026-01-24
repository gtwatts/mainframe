#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/agent/health-monitor.sh - Service Health Monitor
# =============================================================================
# Description: Monitors services/endpoints with configurable checks, alerting,
#              and status dashboard. Supports HTTP, TCP, and process checks.
# Version: 1.0.0
# Requires: Bash 4.0+, curl
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
CONFIG_FILE=""
CHECK_INTERVAL=30
ALERT_CMD=""
OUTPUT_FORMAT="text"  # text|json|dashboard
MAX_FAILURES=3
VERBOSE=false
ONCE=false

# State
declare -A CHECK_NAMES
declare -A CHECK_TYPES
declare -A CHECK_TARGETS
declare -A CHECK_STATUS
declare -A CHECK_FAILURES
declare -A CHECK_LAST_OK

usage() {
    cat <<EOF
Usage: health-monitor.sh [options] <config-file>

Monitor service health with configurable checks.

Config File Format (one check per line):
    name type target [options]

Types:
    http <url>           HTTP GET, expect 2xx
    tcp <host:port>      TCP connection check
    proc <process-name>  Process existence check
    cmd <command>        Custom command (exit 0 = healthy)

Example Config:
    api http http://localhost:8080/health
    db tcp localhost:5432
    redis proc redis-server
    disk cmd "df / | awk 'NR==2{exit (\$5+0 > 90)}'"

Options:
    -i, --interval <sec>   Check interval (default: 30)
    --alert <cmd>          Alert command (receives: name status message)
    --max-failures <n>     Failures before alert (default: 3)
    --format <fmt>         Output: text|json|dashboard (default: text)
    --once                 Run checks once and exit
    -v, --verbose          Verbose output
    -h, --help             Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interval)     CHECK_INTERVAL="$2"; shift 2 ;;
            --alert)           ALERT_CMD="$2"; shift 2 ;;
            --max-failures)    MAX_FAILURES="$2"; shift 2 ;;
            --format)          OUTPUT_FORMAT="$2"; shift 2 ;;
            --once)            ONCE=true; shift ;;
            -v|--verbose)      VERBOSE=true; shift ;;
            -h|--help)         usage ;;
            -*)                log_error "Unknown option: $1"; usage ;;
            *)                 CONFIG_FILE="$1"; shift ;;
        esac
    done
}

# Parse config file
parse_config() {
    local file="$1"
    local idx=0

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue

        local name type target
        name=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        target=$(echo "$line" | cut -d' ' -f3-)

        CHECK_NAMES[$idx]="$name"
        CHECK_TYPES[$idx]="$type"
        CHECK_TARGETS[$idx]="$target"
        CHECK_STATUS[$idx]="unknown"
        CHECK_FAILURES[$idx]=0
        CHECK_LAST_OK[$idx]="never"

        ((idx++))
    done < "$file"
}

# Perform HTTP check
check_http() {
    local url="$1"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)

    if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
        return 0
    fi
    return 1
}

# Perform TCP check
check_tcp() {
    local target="$1"
    local host="${target%%:*}"
    local port="${target##*:}"

    if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Perform process check
check_proc() {
    local name="$1"
    if pgrep -x "$name" >/dev/null 2>&1; then
        return 0
    fi
    # Also check partial match
    if pgrep -f "$name" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Perform command check
check_cmd() {
    local cmd="$1"
    if bash -c "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Run all checks
run_checks() {
    local ts
    ts=$(date '+%H:%M:%S')

    for idx in "${!CHECK_NAMES[@]}"; do
        local name="${CHECK_NAMES[$idx]}"
        local type="${CHECK_TYPES[$idx]}"
        local target="${CHECK_TARGETS[$idx]}"
        local prev_status="${CHECK_STATUS[$idx]}"
        local healthy=false

        case "$type" in
            http) check_http "$target" && healthy=true ;;
            tcp)  check_tcp "$target" && healthy=true ;;
            proc) check_proc "$target" && healthy=true ;;
            cmd)  check_cmd "$target" && healthy=true ;;
            *)    log_warn "Unknown check type: $type"; continue ;;
        esac

        if [[ "$healthy" == true ]]; then
            CHECK_STATUS[$idx]="healthy"
            CHECK_FAILURES[$idx]=0
            CHECK_LAST_OK[$idx]="$ts"

            # Recovery alert
            if [[ "$prev_status" == "unhealthy" ]]; then
                send_alert "$name" "recovered" "Service recovered at $ts"
            fi
        else
            CHECK_FAILURES[$idx]=$(( ${CHECK_FAILURES[$idx]} + 1 ))

            if [[ ${CHECK_FAILURES[$idx]} -ge $MAX_FAILURES ]]; then
                CHECK_STATUS[$idx]="unhealthy"

                # Alert on transition to unhealthy
                if [[ "$prev_status" != "unhealthy" ]]; then
                    send_alert "$name" "unhealthy" "Failed ${CHECK_FAILURES[$idx]} consecutive checks"
                fi
            else
                CHECK_STATUS[$idx]="degraded"
            fi
        fi
    done
}

# Send alert
send_alert() {
    local name="$1"
    local status="$2"
    local message="$3"

    log_warn "ALERT: [$name] $status - $message"

    if [[ -n "$ALERT_CMD" ]]; then
        bash -c "$ALERT_CMD" -- "$name" "$status" "$message" 2>/dev/null &
    fi
}

# Display status
display_status() {
    case "$OUTPUT_FORMAT" in
        text)
            echo ""
            printf "%-15s %-10s %-5s %-10s %s\n" "SERVICE" "STATUS" "FAILS" "LAST OK" "TARGET"
            printf "%-15s %-10s %-5s %-10s %s\n" "-------" "------" "-----" "-------" "------"
            for idx in "${!CHECK_NAMES[@]}"; do
                local status_icon=""
                case "${CHECK_STATUS[$idx]}" in
                    healthy)   status_icon="OK" ;;
                    degraded)  status_icon="WARN" ;;
                    unhealthy) status_icon="FAIL" ;;
                    *)         status_icon="?" ;;
                esac
                printf "%-15s %-10s %-5d %-10s %s\n" \
                    "${CHECK_NAMES[$idx]}" \
                    "$status_icon" \
                    "${CHECK_FAILURES[$idx]}" \
                    "${CHECK_LAST_OK[$idx]}" \
                    "${CHECK_TYPES[$idx]}:${CHECK_TARGETS[$idx]:0:30}"
            done
            ;;
        json)
            echo "{"
            echo "  \"timestamp\": \"$(date -Iseconds)\","
            echo "  \"checks\": ["
            local first=1
            for idx in "${!CHECK_NAMES[@]}"; do
                [[ $first -eq 0 ]] && echo ","
                first=0
                printf '    {"name":"%s","status":"%s","failures":%d,"type":"%s"}' \
                    "${CHECK_NAMES[$idx]}" \
                    "${CHECK_STATUS[$idx]}" \
                    "${CHECK_FAILURES[$idx]}" \
                    "${CHECK_TYPES[$idx]}"
            done
            echo ""
            echo "  ]"
            echo "}"
            ;;
        dashboard)
            clear
            echo "=== Health Monitor Dashboard ==="
            echo "Time: $(date '+%Y-%m-%d %H:%M:%S') | Interval: ${CHECK_INTERVAL}s"
            echo ""
            for idx in "${!CHECK_NAMES[@]}"; do
                local icon=""
                case "${CHECK_STATUS[$idx]}" in
                    healthy)   icon="[OK]  " ;;
                    degraded)  icon="[WARN]" ;;
                    unhealthy) icon="[FAIL]" ;;
                    *)         icon="[??] " ;;
                esac
                echo "  $icon ${CHECK_NAMES[$idx]} (${CHECK_TYPES[$idx]})"
            done
            echo ""
            echo "Press Ctrl+C to stop"
            ;;
    esac
}

cleanup() {
    echo ""
    log_info "Health monitor stopped"
    exit 0
}

main() {
    parse_args "$@"

    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "Config file required"
        usage
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config not found: $CONFIG_FILE"
        exit 1
    fi

    parse_config "$CONFIG_FILE"

    local check_count=${#CHECK_NAMES[@]}
    log_info "Health Monitor: $check_count checks, interval: ${CHECK_INTERVAL}s"

    trap cleanup INT TERM

    if [[ "$ONCE" == true ]]; then
        run_checks
        display_status
        # Exit with error if any unhealthy
        for idx in "${!CHECK_STATUS[@]}"; do
            [[ "${CHECK_STATUS[$idx]}" == "unhealthy" ]] && exit 1
        done
        exit 0
    fi

    # Continuous monitoring loop
    while true; do
        run_checks
        display_status
        sleep "$CHECK_INTERVAL"
    done
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/service.sh - Service Management Library
# =============================================================================
# Description: Cross-platform service management. Wraps systemctl on Linux,
#              launchctl on macOS, with graceful fallback to sysvinit/openrc.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SERVICE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SERVICE_LOADED=1

source "${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh" 2>/dev/null || true

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_service_normalize_name() {
    local name="$1"
    case "$(_service_detect_manager)" in
        systemd)
            # Strip .service suffix for uniform handling; systemctl adds it
            echo "${name%.service}" ;;
        launchctl)
            # Accept bare name or full domain form
            echo "$name" ;;
        *) echo "$name" ;;
    esac
}

_service_detect_manager() {
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
        echo "systemd"
    elif command -v launchctl &>/dev/null; then
        echo "launchctl"
    elif command -v rc-status &>/dev/null; then
        echo "openrc"
    elif [[ -d /etc/init.d ]]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

_service_warn_permission() {
    if [[ $EUID -ne 0 ]]; then
        echo "warning: operation may require root privileges" >&2
    fi
}

_service_systemd_status() {
    local name="$1"
    local state
    state=$(systemctl is-active "$name" 2>/dev/null)
    case "$state" in
        active|activating) echo "running" ;;
        inactive|deactivating) echo "stopped" ;;
        failed) echo "failed" ;;
        *) echo "unknown" ;;
    esac
}

_service_launchctl_status() {
    local name="$1"
    local pid
    # Try system domain first, then user domain
    pid=$(launchctl list 2>/dev/null | awk -v n="$name" '$3 == n {print $1}')
    if [[ -z "$pid" ]]; then
        echo "stopped"
    elif [[ "$pid" == "-" ]]; then
        echo "stopped"
    else
        echo "running"
    fi
}

# =============================================================================
# MANAGER DETECTION
# =============================================================================

service_manager() {
    _service_detect_manager
}

service_manager_version() {
    case "$(service_manager)" in
        systemd) systemctl --version 2>/dev/null | head -1 | awk '{print $2}' ;;
        launchctl) sw_vers -productVersion 2>/dev/null || echo "unknown" ;;
        openrc) rc-status --version 2>/dev/null | head -1 || echo "unknown" ;;
        *) echo "unknown" ;;
    esac
}

# =============================================================================
# SERVICE STATUS
# =============================================================================

service_status() {
    local name
    name=$(_service_normalize_name "$1")
    case "$(service_manager)" in
        systemd) _service_systemd_status "$name" ;;
        launchctl) _service_launchctl_status "$name" ;;
        openrc|sysvinit)
            if service "$name" status &>/dev/null; then
                echo "running"
            else
                echo "stopped"
            fi ;;
        *) echo "unknown" ;;
    esac
}

service_is_running() {
    [[ "$(service_status "$1")" == "running" ]]
}

service_pid() {
    local name
    name=$(_service_normalize_name "$1")
    case "$(service_manager)" in
        systemd)
            local pid
            pid=$(systemctl show "$name" -p MainPID --value 2>/dev/null)
            [[ "$pid" -gt 0 ]] 2>/dev/null && echo "$pid" ;;
        launchctl)
            local pid
            pid=$(launchctl list 2>/dev/null | awk -v n="$name" '$3 == n {print $1}')
            [[ -n "$pid" && "$pid" != "-" ]] && echo "$pid" ;;
        *)
            # Best-effort: pidof or pgrep
            pidof "$name" 2>/dev/null | awk '{print $1}' ;;
    esac
}

service_uptime() {
    local name
    name=$(_service_normalize_name "$1")
    service_is_running "$name" || return 0
    case "$(service_manager)" in
        systemd)
            local ts
            ts=$(systemctl show "$name" -p ActiveEnterTimestamp --value 2>/dev/null)
            if [[ -n "$ts" && "$ts" != "" ]]; then
                local start_epoch now_epoch
                start_epoch=$(date -d "$ts" +%s 2>/dev/null) || return 0
                now_epoch=$(date +%s)
                echo $(( now_epoch - start_epoch ))
            fi ;;
        *)
            # Fallback: use /proc if PID available
            local pid
            pid=$(service_pid "$name")
            if [[ -n "$pid" && -d "/proc/$pid" ]]; then
                local start_epoch now_epoch
                start_epoch=$(stat -c %Y "/proc/$pid" 2>/dev/null) || return 0
                now_epoch=$(date +%s)
                echo $(( now_epoch - start_epoch ))
            fi ;;
    esac
}

# =============================================================================
# SERVICE LISTS
# =============================================================================

service_list_running() {
    case "$(service_manager)" in
        systemd)
            systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null \
                | awk '{print $1}' | sed 's/\.service$//' | grep -v '^$' ;;
        launchctl)
            launchctl list 2>/dev/null | awk 'NR>1 && $1 != "-" {print $3}' ;;
        openrc)
            rc-status 2>/dev/null | awk '/started/ {print $1}' ;;
        *) echo "unknown manager" >&2; return 1 ;;
    esac
}

service_list_failed() {
    case "$(service_manager)" in
        systemd)
            systemctl list-units --type=service --state=failed --no-pager --plain 2>/dev/null \
                | awk '{print $1}' | sed 's/\.service$//' | grep -v '^$' ;;
        launchctl)
            launchctl list 2>/dev/null | awk 'NR>1 && $2 != "0" && $2 != "-" {print $3}' ;;
        *) echo "unknown manager" >&2; return 1 ;;
    esac
}

service_list_enabled() {
    case "$(service_manager)" in
        systemd)
            systemctl list-unit-files --type=service --state=enabled --no-pager --plain 2>/dev/null \
                | awk '{print $1}' | sed 's/\.service$//' | grep -v '^$' ;;
        launchctl)
            # All loaded plists are effectively enabled
            launchctl list 2>/dev/null | awk 'NR>1 {print $3}' ;;
        *) echo "unknown manager" >&2; return 1 ;;
    esac
}

service_list_all() {
    case "$(service_manager)" in
        systemd)
            systemctl list-unit-files --type=service --no-pager --plain 2>/dev/null \
                | awk 'NF>=2 {print $1}' | sed 's/\.service$//' | grep -v '^$' ;;
        launchctl)
            launchctl list 2>/dev/null | awk 'NR>1 {print $3}' ;;
        openrc)
            rc-status -a 2>/dev/null | awk '{print $1}' | grep -v '^$' ;;
        sysvinit)
            for script in /etc/init.d/*; do
                [[ -x "$script" && "${script##*/}" != "README" ]] && echo "${script##*/}"
            done ;;
        *) echo "unknown manager" >&2; return 1 ;;
    esac
}

# =============================================================================
# SERVICE CONTROL
# =============================================================================

service_start() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl start "$name" 2>&1 ;;
        launchctl) launchctl start "$name" 2>&1 ;;
        openrc|sysvinit) service "$name" start 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

service_stop() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl stop "$name" 2>&1 ;;
        launchctl) launchctl stop "$name" 2>&1 ;;
        openrc|sysvinit) service "$name" stop 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

service_restart() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl restart "$name" 2>&1 ;;
        launchctl) launchctl stop "$name" 2>&1; launchctl start "$name" 2>&1 ;;
        openrc|sysvinit) service "$name" restart 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

service_reload() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl reload "$name" 2>&1 ;;
        launchctl)
            local pid
            pid=$(service_pid "$name")
            [[ -n "$pid" ]] && kill -HUP "$pid" 2>&1 || echo "error: cannot reload, no PID" >&2 ;;
        openrc|sysvinit) service "$name" reload 2>&1 || service "$name" restart 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

service_enable() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl enable "$name" 2>&1 ;;
        launchctl) launchctl load -w "/Library/LaunchDaemons/${name}.plist" 2>&1 \
                   || launchctl load -w "$HOME/Library/LaunchAgents/${name}.plist" 2>&1 ;;
        openrc) rc-update add "$name" default 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

service_disable() {
    local name
    name=$(_service_normalize_name "$1")
    _service_warn_permission
    case "$(service_manager)" in
        systemd) systemctl disable "$name" 2>&1 ;;
        launchctl) launchctl unload -w "/Library/LaunchDaemons/${name}.plist" 2>&1 \
                   || launchctl unload -w "$HOME/Library/LaunchAgents/${name}.plist" 2>&1 ;;
        openrc) rc-update del "$name" default 2>&1 ;;
        *) echo "error: unsupported service manager" >&2; return 1 ;;
    esac
}

# =============================================================================
# SERVICE LOGS
# =============================================================================

service_logs() {
    local name n
    name=$(_service_normalize_name "$1")
    n="${2:-20}"
    case "$(service_manager)" in
        systemd) journalctl -u "$name" -n "$n" --no-pager 2>/dev/null ;;
        launchctl) log show --predicate "subsystem == \"$name\"" --last "${n}m" --style compact 2>/dev/null \
                   | tail -n "$n" ;;
        *) echo "error: log retrieval not supported for $(service_manager)" >&2; return 1 ;;
    esac
}

service_log_follow() {
    local name
    name=$(_service_normalize_name "$1")
    echo "Press Ctrl-C to stop" >&2
    case "$(service_manager)" in
        systemd) journalctl -u "$name" -f --no-pager 2>/dev/null ;;
        launchctl) log stream --predicate "subsystem == \"$name\"" --style compact 2>/dev/null ;;
        *) echo "error: log streaming not supported for $(service_manager)" >&2; return 1 ;;
    esac
}

service_log_errors() {
    local name n
    name=$(_service_normalize_name "$1")
    n="${2:-20}"
    case "$(service_manager)" in
        systemd) journalctl -u "$name" -p err -n "$n" --no-pager 2>/dev/null ;;
        launchctl) log show --predicate "subsystem == \"$name\" AND messageType == error" \
                   --last "${n}m" --style compact 2>/dev/null | tail -n "$n" ;;
        *) echo "error: error log retrieval not supported for $(service_manager)" >&2; return 1 ;;
    esac
}

# =============================================================================
# SUMMARY
# =============================================================================

service_summary() {
    local manager running failed enabled
    manager=$(service_manager)
    running=$(service_list_running 2>/dev/null | wc -l)
    failed=$(service_list_failed 2>/dev/null | wc -l)
    enabled=$(service_list_enabled 2>/dev/null | wc -l)
    printf '{"manager":"%s","running":%d,"failed":%d,"enabled":%d}\n' \
        "$manager" "$running" "$failed" "$enabled"
}

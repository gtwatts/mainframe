#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/sysinfo.sh - System Information Library
# =============================================================================
# Description: Parse system information as text streams. Every function outputs
#              simple text suitable for piping, grepping, and further processing.
#              Reads /proc/* and /sys/* on Linux, sysctl/sw_vers on macOS.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SYSINFO_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SYSINFO_LOADED=1

source "${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh" 2>/dev/null || true

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_sysinfo_is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
_sysinfo_is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

_sysinfo_read_proc() {
    local file="$1"
    [[ -r "$file" ]] && cat "$file" 2>/dev/null
}

_sysinfo_bytes_human() {
    local bytes="${1:-0}"
    if (( bytes >= 1099511627776 )); then
        printf "%.1fT" "$(echo "scale=1; $bytes / 1099511627776" | bc 2>/dev/null)"
    elif (( bytes >= 1073741824 )); then
        printf "%.1fG" "$(echo "scale=1; $bytes / 1073741824" | bc 2>/dev/null)"
    elif (( bytes >= 1048576 )); then
        printf "%.1fM" "$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null)"
    elif (( bytes >= 1024 )); then
        printf "%.1fK" "$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null)"
    else
        printf "%dB" "$bytes"
    fi
}

# =============================================================================
# CPU
# =============================================================================

sysinfo_cpu_count() {
    if _sysinfo_is_linux; then
        grep -c '^processor' /proc/cpuinfo 2>/dev/null || nproc 2>/dev/null
    elif _sysinfo_is_macos; then
        sysctl -n hw.ncpu 2>/dev/null
    else
        echo ""; return 1
    fi
}

sysinfo_cpu_model() {
    if _sysinfo_is_linux; then
        grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //'
    elif _sysinfo_is_macos; then
        sysctl -n machdep.cpu.brand_string 2>/dev/null
    else
        echo ""; return 1
    fi
}

sysinfo_cpu_usage() {
    if _sysinfo_is_linux; then
        local -a s1 s2
        read -ra s1 <<< "$(grep '^cpu ' /proc/stat)"
        sleep 0.5
        read -ra s2 <<< "$(grep '^cpu ' /proc/stat)"
        local idle1="${s1[4]}" idle2="${s2[4]}"
        local total1=0 total2=0
        for i in {1..7}; do (( total1 += s1[i] )); (( total2 += s2[i] )); done
        local dtotal=$(( total2 - total1 ))
        local didle=$(( idle2 - idle1 ))
        if (( dtotal > 0 )); then
            echo $(( (dtotal - didle) * 100 / dtotal ))
        else
            echo 0
        fi
    elif _sysinfo_is_macos; then
        local idle
        idle=$(top -l 2 -n 0 2>/dev/null | grep -m1 'CPU usage' | awk '{print $7}' | tr -d '%')
        if [[ -n "$idle" ]]; then
            printf "%.0f" "$(echo "100 - $idle" | bc 2>/dev/null)"
        else
            echo ""; return 1
        fi
    else
        echo ""; return 1
    fi
}

sysinfo_load() {
    if _sysinfo_is_linux; then
        read -r l1 l5 l15 _ < /proc/loadavg 2>/dev/null && echo "$l1 $l5 $l15"
    elif _sysinfo_is_macos; then
        sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs
    else
        echo ""; return 1
    fi
}

sysinfo_load_1m() {
    local load
    load=$(sysinfo_load) && echo "${load%% *}"
}

# =============================================================================
# MEMORY
# =============================================================================

_sysinfo_meminfo_kb() {
    grep -i "^$1:" /proc/meminfo 2>/dev/null | awk '{print $2}'
}

sysinfo_mem_total() {
    if _sysinfo_is_linux; then
        local kb; kb=$(_sysinfo_meminfo_kb "MemTotal") && echo $(( kb * 1024 ))
    elif _sysinfo_is_macos; then
        sysctl -n hw.memsize 2>/dev/null
    else
        echo ""; return 1
    fi
}

sysinfo_mem_available() {
    if _sysinfo_is_linux; then
        local kb; kb=$(_sysinfo_meminfo_kb "MemAvailable") && echo $(( kb * 1024 ))
    elif _sysinfo_is_macos; then
        local page_size free_pages
        page_size=$(sysctl -n hw.pagesize 2>/dev/null)
        free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,""); print $3}')
        [[ -n "$page_size" && -n "$free_pages" ]] && echo $(( free_pages * page_size ))
    else
        echo ""; return 1
    fi
}

sysinfo_mem_used() {
    local total avail
    total=$(sysinfo_mem_total) || return 1
    avail=$(sysinfo_mem_available) || return 1
    echo $(( total - avail ))
}

sysinfo_mem_usage() {
    local total used
    total=$(sysinfo_mem_total) || return 1
    used=$(sysinfo_mem_used) || return 1
    (( total > 0 )) && echo $(( used * 100 / total )) || echo 0
}

sysinfo_swap_total() {
    if _sysinfo_is_linux; then
        local kb; kb=$(_sysinfo_meminfo_kb "SwapTotal") && echo $(( kb * 1024 ))
    elif _sysinfo_is_macos; then
        sysctl -n vm.swapusage 2>/dev/null | awk '{gsub(/M/,""); print int($2 * 1048576)}'
    else
        echo ""; return 1
    fi
}

sysinfo_swap_used() {
    if _sysinfo_is_linux; then
        local total free
        total=$(_sysinfo_meminfo_kb "SwapTotal")
        free=$(_sysinfo_meminfo_kb "SwapFree")
        echo $(( (total - free) * 1024 ))
    elif _sysinfo_is_macos; then
        sysctl -n vm.swapusage 2>/dev/null | awk '{gsub(/M/,""); print int($6 * 1048576)}'
    else
        echo ""; return 1
    fi
}

sysinfo_swap_usage() {
    local total used
    total=$(sysinfo_swap_total) || return 1
    used=$(sysinfo_swap_used) || return 1
    (( total > 0 )) && echo $(( used * 100 / total )) || echo 0
}

sysinfo_mem_human() {
    local total used pct
    total=$(sysinfo_mem_total) || return 1
    used=$(sysinfo_mem_used) || return 1
    pct=$(sysinfo_mem_usage) || return 1
    printf "%s / %s (%d%%)\n" "$(_sysinfo_bytes_human "$used")" "$(_sysinfo_bytes_human "$total")" "$pct"
}

# =============================================================================
# NETWORK
# =============================================================================

sysinfo_interfaces() {
    if _sysinfo_is_linux; then
        for iface in /sys/class/net/*/; do
            iface="${iface%/}"; iface="${iface##*/}"
            [[ "$iface" != "lo" ]] && echo "$iface"
        done
    elif _sysinfo_is_macos; then
        ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -v '^lo'
    else
        echo ""; return 1
    fi
}

sysinfo_ip() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
    elif _sysinfo_is_macos; then
        ifconfig "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1
    else
        echo ""; return 1
    fi
}

sysinfo_ip6() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        ip -6 addr show "$iface" 2>/dev/null | awk '/inet6/{print $2}' | cut -d/ -f1 | grep -v '^fe80' | head -1
    elif _sysinfo_is_macos; then
        ifconfig "$iface" 2>/dev/null | awk '/inet6/{print $2}' | grep -v '^fe80' | head -1
    else
        echo ""; return 1
    fi
}

sysinfo_mac() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        cat "/sys/class/net/$iface/address" 2>/dev/null
    elif _sysinfo_is_macos; then
        ifconfig "$iface" 2>/dev/null | awk '/ether/{print $2}'
    else
        echo ""; return 1
    fi
}

sysinfo_gateway() {
    if _sysinfo_is_linux; then
        ip route show default 2>/dev/null | awk '/default/{print $3; exit}'
    elif _sysinfo_is_macos; then
        route -n get default 2>/dev/null | awk '/gateway:/{print $2}'
    else
        echo ""; return 1
    fi
}

sysinfo_dns() {
    grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}'
}

sysinfo_is_up() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        local state
        state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
        [[ "$state" == "up" ]]
    elif _sysinfo_is_macos; then
        ifconfig "$iface" 2>/dev/null | grep -q 'status: active'
    else
        return 1
    fi
}

sysinfo_public_ip() {
    curl -sf --max-time 3 "https://ifconfig.me/ip" 2>/dev/null || echo ""
}

sysinfo_rx_bytes() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null
    elif _sysinfo_is_macos; then
        netstat -ibI "$iface" 2>/dev/null | awk 'NR==2{print $7}'
    else
        echo ""; return 1
    fi
}

sysinfo_tx_bytes() {
    local iface="${1:?interface required}"
    if _sysinfo_is_linux; then
        cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null
    elif _sysinfo_is_macos; then
        netstat -ibI "$iface" 2>/dev/null | awk 'NR==2{print $10}'
    else
        echo ""; return 1
    fi
}

# =============================================================================
# OS / SYSTEM
# =============================================================================

sysinfo_os() { uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]'; }
sysinfo_kernel() { uname -r 2>/dev/null; }
sysinfo_arch() { uname -m 2>/dev/null; }
sysinfo_hostname() { hostname 2>/dev/null; }

sysinfo_distro() {
    if _sysinfo_is_linux; then
        (source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo "Linux"
    elif _sysinfo_is_macos; then
        local ver; ver=$(sw_vers -productVersion 2>/dev/null)
        echo "macOS $ver"
    else
        uname -s
    fi
}

sysinfo_uptime() {
    if _sysinfo_is_linux; then
        awk '{printf "%d", $1}' /proc/uptime 2>/dev/null
    elif _sysinfo_is_macos; then
        local boot; boot=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[= ,]' '{print $4}')
        [[ -n "$boot" ]] && echo $(( $(date +%s) - boot ))
    else
        echo ""; return 1
    fi
}

sysinfo_uptime_human() {
    local secs days hours mins
    secs=$(sysinfo_uptime) || return 1
    days=$(( secs / 86400 )); hours=$(( (secs % 86400) / 3600 )); mins=$(( (secs % 3600) / 60 ))
    local out=""
    (( days > 0 )) && out="${days}d "
    (( hours > 0 || days > 0 )) && out+="${hours}h "
    out+="${mins}m"
    echo "$out"
}

sysinfo_boot_time() {
    if _sysinfo_is_linux; then
        local up; up=$(sysinfo_uptime) && echo $(( $(date +%s) - up ))
    elif _sysinfo_is_macos; then
        sysctl -n kern.boottime 2>/dev/null | awk -F'[= ,]' '{print $4}'
    else
        echo ""; return 1
    fi
}

sysinfo_users_logged_in() {
    who 2>/dev/null | wc -l | tr -d ' '
}

# =============================================================================
# DISK
# =============================================================================

sysinfo_disk_total() {
    local path="${1:-.}"
    df -B1 "$path" 2>/dev/null | awk 'NR==2{print $2}'
}

sysinfo_disk_free() {
    local path="${1:-.}"
    df -B1 "$path" 2>/dev/null | awk 'NR==2{print $4}'
}

sysinfo_disk_usage() {
    local path="${1:-.}"
    df "$path" 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}'
}

# =============================================================================
# SUMMARY
# =============================================================================

sysinfo_summary() {
    local os distro arch cores model mem_total mem_used mem_pct disk_free uptime load
    os=$(sysinfo_os)
    distro=$(sysinfo_distro)
    arch=$(sysinfo_arch)
    cores=$(sysinfo_cpu_count)
    model=$(sysinfo_cpu_model)
    mem_total=$(sysinfo_mem_total)
    mem_used=$(sysinfo_mem_used)
    mem_pct=$(sysinfo_mem_usage)
    disk_free=$(sysinfo_disk_free "/")
    uptime=$(sysinfo_uptime)
    load=$(sysinfo_load_1m)
    printf '{"os":"%s","distro":"%s","arch":"%s","cpu_cores":%s,"cpu_model":"%s","mem_total":%s,"mem_used":%s,"mem_pct":%s,"disk_free":%s,"uptime":%s,"load_1m":"%s"}\n' \
        "$os" "$distro" "$arch" "${cores:-0}" "$model" "${mem_total:-0}" "${mem_used:-0}" "${mem_pct:-0}" "${disk_free:-0}" "${uptime:-0}" "$load"
}

sysinfo_oneliner() {
    local distro cores mem_total disk_free
    distro=$(sysinfo_distro)
    cores=$(sysinfo_cpu_count)
    mem_total=$(_sysinfo_bytes_human "$(sysinfo_mem_total)")
    disk_free=$(_sysinfo_bytes_human "$(sysinfo_disk_free /)")
    printf "%s | %s cores | %s | %s free\n" "$distro" "$cores" "$mem_total" "$disk_free"
}

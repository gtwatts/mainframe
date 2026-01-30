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

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

# @idempotent Check if running as root
# @return 0 if root, 1 if not
is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

# @idempotent Check if running in a container
# @return 0 if container, 1 if not
is_container() {
    # Check for Docker
    if [[ -f /.dockerenv ]]; then
        return 0
    fi

    # Check cgroup for docker/lxc/containerd
    if [[ -f /proc/1/cgroup ]]; then
        if grep -qE '(docker|lxc|containerd|kubepods|libpod)' /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi

    # Check for container environment variables
    if [[ -n "${container:-}" || -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        return 0
    fi

    # Check /proc/1/environ for container runtime
    if [[ -r /proc/1/environ ]]; then
        if tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -qE '^container=' ; then
            return 0
        fi
    fi

    # Check for systemd-nspawn
    if [[ -d /run/systemd/container ]]; then
        return 0
    fi

    return 1
}

# @idempotent Check if running in a virtual machine
# @return 0 if VM, 1 if bare metal (best effort detection)
is_vm() {
    # Check systemd-detect-virt first (most reliable)
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null)
        if [[ "$virt" != "none" && -n "$virt" ]]; then
            return 0
        fi
    fi

    # Check DMI/SMBIOS data on Linux
    if _sysinfo_is_linux; then
        # Check product name for common VM vendors
        if [[ -r /sys/class/dmi/id/product_name ]]; then
            local product
            product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
            case "$product" in
                *VirtualBox*|*VMware*|*QEMU*|*KVM*|*Bochs*|*Parallels*|*Xen*|*HVM*|*Microsoft*Virtual*|*Virtual*)
                    return 0
                    ;;
            esac
        fi

        # Check sys_vendor
        if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
            local vendor
            vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
            case "$vendor" in
                *VMware*|*innotek*|*QEMU*|*Xen*|*Bochs*|*Parallels*|*Microsoft*|*Amazon*EC2*|*Google*)
                    return 0
                    ;;
            esac
        fi

        # Check for hypervisor flag in cpuinfo
        if grep -q '^flags.*hypervisor' /proc/cpuinfo 2>/dev/null; then
            return 0
        fi

        # Check for Xen
        if [[ -d /proc/xen ]] || [[ -f /sys/hypervisor/type ]]; then
            return 0
        fi
    fi

    # macOS: check for VM by model identifier
    if _sysinfo_is_macos; then
        local model
        model=$(sysctl -n hw.model 2>/dev/null)
        case "$model" in
            *VMware*|*VirtualBox*|*Parallels*)
                return 0
                ;;
        esac

        # Check for virtualization via sysctl
        if sysctl -n machdep.cpu.features 2>/dev/null | grep -qi 'VMX'; then
            # Has VMX but check if itself is virtualized
            if system_profiler SPHardwareDataType 2>/dev/null | grep -qi 'VMware\|Parallels\|VirtualBox'; then
                return 0
            fi
        fi
    fi

    return 1
}

# =============================================================================
# SPECIFICATION-COMPLIANT ALIASES
# =============================================================================
# These functions match the specification interface exactly

# @idempotent Get CPU count (cores)
# Works on Linux, macOS, BSD
# @return Number of CPU cores
cpu_count() {
    sysinfo_cpu_count
}

# @idempotent Get total memory in bytes
# @return Memory in bytes
memory_total() {
    sysinfo_mem_total
}

# @idempotent Get available memory in bytes
# @return Available memory in bytes
memory_available() {
    sysinfo_mem_available
}

# @idempotent Get memory usage as percentage
# @return Percentage (0-100)
memory_usage_percent() {
    sysinfo_mem_usage
}

# @idempotent Get disk usage for path
# @param $1 - path (default: /)
# @return {"total":N,"used":N,"available":N,"percent":N}
disk_usage() {
    local path="${1:-/}"
    local total used available percent

    if _sysinfo_is_macos; then
        # macOS df -B1 not available, use different approach
        local df_output
        df_output=$(df -k "$path" 2>/dev/null | awk 'NR==2{print $2,$3,$4,$5}')
        read -r total used available percent <<< "$df_output"
        # Convert from KB to bytes
        total=$(( total * 1024 ))
        used=$(( used * 1024 ))
        available=$(( available * 1024 ))
        percent="${percent%\%}"
    else
        total=$(df -B1 "$path" 2>/dev/null | awk 'NR==2{print $2}')
        used=$(df -B1 "$path" 2>/dev/null | awk 'NR==2{print $3}')
        available=$(df -B1 "$path" 2>/dev/null | awk 'NR==2{print $4}')
        percent=$(df "$path" 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}')
    fi

    printf '{"total":%s,"used":%s,"available":%s,"percent":%s}\n' \
        "${total:-0}" "${used:-0}" "${available:-0}" "${percent:-0}"
}

# @idempotent Get OS name
# @return "linux", "darwin", "freebsd", etc.
os_name() {
    sysinfo_os
}

# @idempotent Get OS version
# @return Version string
os_version() {
    if _sysinfo_is_linux; then
        # Try to get version from os-release
        if [[ -f /etc/os-release ]]; then
            (source /etc/os-release 2>/dev/null && echo "${VERSION_ID:-${VERSION:-unknown}}")
        else
            uname -r 2>/dev/null
        fi
    elif _sysinfo_is_macos; then
        sw_vers -productVersion 2>/dev/null
    else
        uname -r 2>/dev/null
    fi
}

# @idempotent Get architecture
# @return "x86_64", "arm64", etc.
arch() {
    sysinfo_arch
}

# @idempotent Get hostname
# @return Hostname string
hostname_get() {
    sysinfo_hostname
}

# @idempotent Get system uptime in seconds
# @return Seconds since boot
uptime_seconds() {
    sysinfo_uptime
}

# @idempotent Get load average
# @return {"1min":N,"5min":N,"15min":N}
load_average() {
    local load_str l1 l5 l15

    if _sysinfo_is_linux; then
        read -r l1 l5 l15 _ < /proc/loadavg 2>/dev/null
    elif _sysinfo_is_macos; then
        load_str=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')
        read -r l1 l5 l15 <<< "$load_str"
    else
        echo '{"1min":0,"5min":0,"15min":0}'
        return 1
    fi

    printf '{"1min":%s,"5min":%s,"15min":%s}\n' \
        "${l1:-0}" "${l5:-0}" "${l15:-0}"
}

# @idempotent Full system summary as JSON
# @return {"os":"linux","arch":"x86_64","cpus":8,"memory_gb":16,...}
system_info() {
    local os_val arch_val cpus mem_bytes mem_gb uptime_val hostname_val
    local kernel_val is_root_val is_container_val is_vm_val

    os_val=$(os_name)
    arch_val=$(arch)
    cpus=$(cpu_count)
    mem_bytes=$(memory_total)
    # Convert bytes to GB with integer math (divide by 1073741824)
    mem_gb=$(( mem_bytes / 1073741824 ))
    uptime_val=$(uptime_seconds)
    hostname_val=$(hostname_get)
    kernel_val=$(sysinfo_kernel)

    # Boolean checks
    is_root_val="false"
    is_root && is_root_val="true"

    is_container_val="false"
    is_container && is_container_val="true"

    is_vm_val="false"
    is_vm && is_vm_val="true"

    printf '{"os":"%s","arch":"%s","cpus":%s,"memory_gb":%s,"memory_bytes":%s,"uptime_seconds":%s,"hostname":"%s","kernel":"%s","is_root":%s,"is_container":%s,"is_vm":%s}\n' \
        "$os_val" "$arch_val" "${cpus:-0}" "${mem_gb:-0}" "${mem_bytes:-0}" \
        "${uptime_val:-0}" "$hostname_val" "$kernel_val" \
        "$is_root_val" "$is_container_val" "$is_vm_val"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_SYSINFO_EXPORTS=(
    # Internal helpers (prefixed)
    _sysinfo_is_linux
    _sysinfo_is_macos
    _sysinfo_read_proc
    _sysinfo_bytes_human
    _sysinfo_meminfo_kb
    # CPU
    sysinfo_cpu_count
    sysinfo_cpu_model
    sysinfo_cpu_usage
    sysinfo_load
    sysinfo_load_1m
    # Memory
    sysinfo_mem_total
    sysinfo_mem_available
    sysinfo_mem_used
    sysinfo_mem_usage
    sysinfo_swap_total
    sysinfo_swap_used
    sysinfo_swap_usage
    sysinfo_mem_human
    # Network
    sysinfo_interfaces
    sysinfo_ip
    sysinfo_ip6
    sysinfo_mac
    sysinfo_gateway
    sysinfo_dns
    sysinfo_is_up
    sysinfo_public_ip
    sysinfo_rx_bytes
    sysinfo_tx_bytes
    # OS/System
    sysinfo_os
    sysinfo_kernel
    sysinfo_arch
    sysinfo_hostname
    sysinfo_distro
    sysinfo_uptime
    sysinfo_uptime_human
    sysinfo_boot_time
    sysinfo_users_logged_in
    # Disk
    sysinfo_disk_total
    sysinfo_disk_free
    sysinfo_disk_usage
    # Summary
    sysinfo_summary
    sysinfo_oneliner
    # Environment detection
    is_root
    is_container
    is_vm
    # Specification-compliant aliases
    cpu_count
    memory_total
    memory_available
    memory_usage_percent
    disk_usage
    os_name
    os_version
    arch
    hostname_get
    uptime_seconds
    load_average
    system_info
)

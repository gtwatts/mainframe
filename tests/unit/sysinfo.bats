#!/usr/bin/env bats

setup() {
    export MAINFRAME_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${MAINFRAME_ROOT}/lib/sysinfo.sh"
}

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

@test "_sysinfo_is_linux returns 0 on Linux" {
    [[ "$(uname -s)" == "Linux" ]] || skip "Not running on Linux"
    _sysinfo_is_linux
}

@test "_sysinfo_is_macos returns 1 on Linux" {
    [[ "$(uname -s)" == "Linux" ]] || skip "Not running on Linux"
    run _sysinfo_is_macos
    [[ "$status" -ne 0 ]]
}

@test "sysinfo_os outputs linux on Linux" {
    [[ "$(uname -s)" == "Linux" ]] || skip "Not running on Linux"
    local result
    result=$(sysinfo_os)
    [[ "$result" == "linux" ]]
}

# =============================================================================
# CPU
# =============================================================================

@test "sysinfo_cpu_count outputs integer > 0" {
    local result
    result=$(sysinfo_cpu_count)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_cpu_model outputs non-empty string" {
    local result
    result=$(sysinfo_cpu_model)
    [[ -n "$result" ]]
}

@test "sysinfo_cpu_usage outputs integer 0-100" {
    local result
    result=$(sysinfo_cpu_usage)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
    [[ "$result" -le 100 ]]
}

@test "sysinfo_load outputs 3 space-separated numbers" {
    local result
    result=$(sysinfo_load)
    [[ -n "$result" ]]
    local count
    count=$(echo "$result" | wc -w | tr -d ' ')
    [[ "$count" -eq 3 ]]
    # Each field should be a number (integer or decimal)
    local f1 f2 f3
    read -r f1 f2 f3 <<< "$result"
    [[ "$f1" =~ ^[0-9]+\.?[0-9]*$ ]]
    [[ "$f2" =~ ^[0-9]+\.?[0-9]*$ ]]
    [[ "$f3" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "sysinfo_load_1m outputs single number" {
    local result
    result=$(sysinfo_load_1m)
    [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]
}

# =============================================================================
# MEMORY
# =============================================================================

@test "sysinfo_mem_total outputs integer > 0" {
    local result
    result=$(sysinfo_mem_total)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_mem_available outputs integer > 0" {
    local result
    result=$(sysinfo_mem_available)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_mem_used outputs integer > 0" {
    local result
    result=$(sysinfo_mem_used)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_mem_usage outputs integer 0-100" {
    local result
    result=$(sysinfo_mem_usage)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
    [[ "$result" -le 100 ]]
}

@test "sysinfo_mem_available < sysinfo_mem_total (sanity)" {
    local avail total
    avail=$(sysinfo_mem_available)
    total=$(sysinfo_mem_total)
    [[ "$avail" -lt "$total" ]]
}

@test "sysinfo_swap_total outputs integer >= 0" {
    local result
    result=$(sysinfo_swap_total)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
}

@test "sysinfo_mem_human contains slash and parenthesis" {
    local result
    result=$(sysinfo_mem_human)
    [[ "$result" == *"/"* ]]
    [[ "$result" == *"("* ]]
}

# =============================================================================
# NETWORK
# =============================================================================

@test "sysinfo_interfaces outputs at least one interface" {
    local result
    result=$(sysinfo_interfaces)
    [[ -n "$result" ]]
    local count
    count=$(echo "$result" | wc -l)
    [[ "$count" -ge 1 ]]
}

@test "sysinfo_ip with first interface returns IPv4-like string" {
    local iface result
    iface=$(sysinfo_interfaces | head -1)
    [[ -n "$iface" ]] || skip "No interfaces found"
    result=$(sysinfo_ip "$iface")
    # May be empty if interface has no IPv4 address
    if [[ -n "$result" ]]; then
        [[ "$result" == *.* ]]
    fi
}

@test "sysinfo_mac with first interface returns MAC-like string or empty" {
    local iface result
    iface=$(sysinfo_interfaces | head -1)
    [[ -n "$iface" ]] || skip "No interfaces found"
    result=$(sysinfo_mac "$iface")
    # MAC may be empty on some CI environments
    if [[ -n "$result" ]]; then
        [[ "$result" == *":"* ]]
    fi
}

@test "sysinfo_gateway outputs IP-like string or empty" {
    local result
    result=$(sysinfo_gateway)
    # Gateway may be empty in some CI environments
    if [[ -n "$result" ]]; then
        [[ "$result" == *.* ]]
    fi
}

@test "sysinfo_dns outputs at least one line" {
    [[ -r /etc/resolv.conf ]] || skip "No resolv.conf available"
    local result
    result=$(sysinfo_dns)
    [[ -n "$result" ]]
}

@test "sysinfo_is_up with first interface returns 0" {
    local iface
    iface=$(sysinfo_interfaces | head -1)
    [[ -n "$iface" ]] || skip "No interfaces found"
    # Check operstate exists and is "up"; skip if interface is not up
    local state
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null) || skip "Cannot read operstate"
    [[ "$state" == "up" ]] || skip "Interface $iface is not up"
    sysinfo_is_up "$iface"
}

# =============================================================================
# OS / SYSTEM
# =============================================================================

@test "sysinfo_distro outputs non-empty string" {
    local result
    result=$(sysinfo_distro)
    [[ -n "$result" ]]
}

@test "sysinfo_kernel outputs version-like string with dots" {
    local result
    result=$(sysinfo_kernel)
    [[ -n "$result" ]]
    [[ "$result" == *.* ]]
}

@test "sysinfo_arch outputs recognized architecture" {
    local result
    result=$(sysinfo_arch)
    [[ "$result" =~ ^(x86_64|aarch64|arm64|armv7l|i686|i386|s390x|ppc64le|riscv64)$ ]]
}

@test "sysinfo_hostname outputs non-empty string" {
    local result
    result=$(sysinfo_hostname)
    [[ -n "$result" ]]
}

@test "sysinfo_uptime outputs integer > 0" {
    local result
    result=$(sysinfo_uptime)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_uptime_human contains time unit" {
    local result
    result=$(sysinfo_uptime_human)
    [[ -n "$result" ]]
    # Must contain at least one time unit: s, m, h, or d
    [[ "$result" =~ [smhd] ]]
}

@test "sysinfo_boot_time outputs epoch timestamp > 1000000000" {
    local result
    result=$(sysinfo_boot_time)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 1000000000 ]]
}

@test "sysinfo_users_logged_in outputs integer >= 0" {
    local result
    result=$(sysinfo_users_logged_in)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
}

# =============================================================================
# DISK
# =============================================================================

@test "sysinfo_disk_total / outputs integer > 0" {
    local result
    result=$(sysinfo_disk_total "/")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_disk_free / outputs integer > 0" {
    local result
    result=$(sysinfo_disk_free "/")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "sysinfo_disk_usage / outputs integer 0-100" {
    local result
    result=$(sysinfo_disk_usage "/")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
    [[ "$result" -le 100 ]]
}

@test "sysinfo_disk_free < sysinfo_disk_total for / (sanity)" {
    local free total
    free=$(sysinfo_disk_free "/")
    total=$(sysinfo_disk_total "/")
    [[ "$free" -lt "$total" ]]
}

# =============================================================================
# SUMMARY
# =============================================================================

@test "sysinfo_summary starts with {" {
    local result
    result=$(sysinfo_summary)
    [[ "${result:0:1}" == "{" ]]
}

@test "sysinfo_summary contains cpu, memory, os keys" {
    local result
    result=$(sysinfo_summary)
    [[ "$result" == *"cpu"* ]]
    [[ "$result" == *"mem"* ]]
    [[ "$result" == *"os"* ]]
}

@test "sysinfo_oneliner is a single line" {
    local result count
    result=$(sysinfo_oneliner)
    [[ -n "$result" ]]
    count=$(echo "$result" | wc -l)
    [[ "$count" -eq 1 ]]
}

@test "sysinfo_oneliner contains pipe separator" {
    local result
    result=$(sysinfo_oneliner)
    [[ "$result" == *"|"* ]]
}

# =============================================================================
# HELPERS
# =============================================================================

@test "_sysinfo_bytes_human 1073741824 outputs 1.0G" {
    local result
    result=$(_sysinfo_bytes_human 1073741824)
    [[ "$result" == "1.0G" ]]
}

@test "_sysinfo_bytes_human 1048576 outputs 1.0M" {
    local result
    result=$(_sysinfo_bytes_human 1048576)
    [[ "$result" == "1.0M" ]]
}

@test "_sysinfo_bytes_human 1024 outputs 1.0K" {
    local result
    result=$(_sysinfo_bytes_human 1024)
    [[ "$result" == "1.0K" ]]
}

@test "_sysinfo_bytes_human 500 outputs 500B" {
    local result
    result=$(_sysinfo_bytes_human 500)
    [[ "$result" == "500B" ]]
}

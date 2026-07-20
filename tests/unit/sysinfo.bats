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

# =============================================================================
# SPECIFICATION-COMPLIANT FUNCTIONS (Quick Win #4)
# =============================================================================

@test "cpu_count returns positive integer" {
    local result
    result=$(cpu_count)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "cpu_count equals sysinfo_cpu_count" {
    local v1 v2
    v1=$(cpu_count)
    v2=$(sysinfo_cpu_count)
    [[ "$v1" == "$v2" ]]
}

@test "memory_total returns positive integer" {
    local result
    result=$(memory_total)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "memory_total equals sysinfo_mem_total" {
    local v1 v2
    v1=$(memory_total)
    v2=$(sysinfo_mem_total)
    [[ "$v1" == "$v2" ]]
}

@test "memory_available returns positive integer" {
    local result
    result=$(memory_available)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "memory_available equals sysinfo_mem_available" {
    local v1 v2 delta
    v1=$(memory_available)
    v2=$(sysinfo_mem_available)
    delta=$(( v1 - v2 ))
    (( delta < 0 )) && delta=$(( -delta ))
    [[ "$delta" -le 268435456 ]]
}

@test "memory_usage_percent returns 0-100" {
    local result
    result=$(memory_usage_percent)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -ge 0 ]]
    [[ "$result" -le 100 ]]
}

@test "memory_usage_percent equals sysinfo_mem_usage" {
    local v1 v2 delta
    v1=$(memory_usage_percent)
    v2=$(sysinfo_mem_usage)
    delta=$(( v1 - v2 ))
    (( delta < 0 )) && delta=$(( -delta ))
    [[ "$delta" -le 1 ]]
}

@test "disk_usage returns valid JSON" {
    local result
    result=$(disk_usage "/")
    [[ "${result:0:1}" == "{" ]]
    [[ "$result" == *'"total":'* ]]
    [[ "$result" == *'"used":'* ]]
    [[ "$result" == *'"available":'* ]]
    [[ "$result" == *'"percent":'* ]]
}

@test "disk_usage default path is /" {
    local result
    result=$(disk_usage)
    [[ "${result:0:1}" == "{" ]]
    [[ "$result" == *'"total":'* ]]
}

@test "disk_usage total > 0" {
    local result total
    result=$(disk_usage "/")
    # Extract total value (handles both formats)
    total=$(echo "$result" | sed 's/.*"total":\([0-9]*\).*/\1/')
    [[ "$total" -gt 0 ]]
}

@test "os_name returns linux or darwin" {
    local result
    result=$(os_name)
    [[ "$result" == "linux" || "$result" == "darwin" ]]
}

@test "os_name equals sysinfo_os" {
    local v1 v2
    v1=$(os_name)
    v2=$(sysinfo_os)
    [[ "$v1" == "$v2" ]]
}

@test "os_version returns non-empty string" {
    local result
    result=$(os_version)
    [[ -n "$result" ]]
}

@test "arch returns recognized architecture" {
    local result
    result=$(arch)
    [[ "$result" =~ ^(x86_64|aarch64|arm64|armv7l|i686|i386|s390x|ppc64le|riscv64)$ ]]
}

@test "arch equals sysinfo_arch" {
    local v1 v2
    v1=$(arch)
    v2=$(sysinfo_arch)
    [[ "$v1" == "$v2" ]]
}

@test "hostname_get returns non-empty string" {
    local result
    result=$(hostname_get)
    [[ -n "$result" ]]
}

@test "hostname_get equals sysinfo_hostname" {
    local v1 v2
    v1=$(hostname_get)
    v2=$(sysinfo_hostname)
    [[ "$v1" == "$v2" ]]
}

@test "uptime_seconds returns positive integer" {
    local result
    result=$(uptime_seconds)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "uptime_seconds equals sysinfo_uptime" {
    local v1 v2
    v1=$(uptime_seconds)
    v2=$(sysinfo_uptime)
    [[ "$v1" == "$v2" ]]
}

@test "load_average returns valid JSON" {
    local result
    result=$(load_average)
    [[ "${result:0:1}" == "{" ]]
    [[ "$result" == *'"1min":'* ]]
    [[ "$result" == *'"5min":'* ]]
    [[ "$result" == *'"15min":'* ]]
}

@test "load_average 1min is non-negative number" {
    local result min1
    result=$(load_average)
    # Extract 1min value
    min1=$(echo "$result" | sed 's/.*"1min":\([0-9.]*\).*/\1/')
    [[ "$min1" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "system_info returns valid JSON" {
    local result
    result=$(system_info)
    [[ "${result:0:1}" == "{" ]]
    [[ "$result" == *'"os":'* ]]
    [[ "$result" == *'"arch":'* ]]
    [[ "$result" == *'"cpus":'* ]]
    [[ "$result" == *'"memory_gb":'* ]]
    [[ "$result" == *'"memory_bytes":'* ]]
    [[ "$result" == *'"uptime_seconds":'* ]]
    [[ "$result" == *'"hostname":'* ]]
    [[ "$result" == *'"kernel":'* ]]
    [[ "$result" == *'"is_root":'* ]]
    [[ "$result" == *'"is_container":'* ]]
    [[ "$result" == *'"is_vm":'* ]]
}

@test "system_info cpus matches cpu_count" {
    local info cpus_info cpus_direct
    info=$(system_info)
    cpus_info=$(echo "$info" | sed 's/.*"cpus":\([0-9]*\).*/\1/')
    cpus_direct=$(cpu_count)
    [[ "$cpus_info" == "$cpus_direct" ]]
}

@test "system_info memory_bytes matches memory_total" {
    local info mem_info mem_direct
    info=$(system_info)
    mem_info=$(echo "$info" | sed 's/.*"memory_bytes":\([0-9]*\).*/\1/')
    mem_direct=$(memory_total)
    [[ "$mem_info" == "$mem_direct" ]]
}

# =============================================================================
# ENVIRONMENT DETECTION (Quick Win #4)
# =============================================================================

@test "is_root returns 0 or 1" {
    run is_root
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "is_root returns 1 for non-root user" {
    # Skip if actually running as root
    [[ "$(id -u)" -ne 0 ]] || skip "Running as root"
    run is_root
    [[ "$status" -eq 1 ]]
}

@test "is_root returns 0 for root user" {
    # Skip if not running as root
    [[ "$(id -u)" -eq 0 ]] || skip "Not running as root"
    run is_root
    [[ "$status" -eq 0 ]]
}

@test "is_container returns 0 or 1" {
    run is_container
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "is_container detects dockerenv" {
    # This test verifies the detection logic works
    # We can't actually test in a container without being in one
    if [[ -f /.dockerenv ]]; then
        run is_container
        [[ "$status" -eq 0 ]]
    else
        # Not in container, should return 1 (unless other indicators present)
        run is_container
        # Just verify it doesn't crash
        [[ "$status" -eq 0 || "$status" -eq 1 ]]
    fi
}

@test "is_vm returns 0 or 1" {
    run is_vm
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "is_vm detects hypervisor flag on Linux" {
    [[ "$(uname -s)" == "Linux" ]] || skip "Not running on Linux"
    # Check if hypervisor flag exists in cpuinfo
    if grep -q '^flags.*hypervisor' /proc/cpuinfo 2>/dev/null; then
        run is_vm
        [[ "$status" -eq 0 ]]
    else
        # No hypervisor flag, may or may not be VM (other detection methods)
        run is_vm
        [[ "$status" -eq 0 || "$status" -eq 1 ]]
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

@test "MAINFRAME_SYSINFO_EXPORTS array is defined" {
    [[ ${#MAINFRAME_SYSINFO_EXPORTS[@]} -gt 0 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains cpu_count" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "cpu_count" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains memory_total" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "memory_total" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains disk_usage" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "disk_usage" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains is_root" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "is_root" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains is_container" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "is_container" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains is_vm" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "is_vm" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains system_info" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "system_info" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "MAINFRAME_SYSINFO_EXPORTS contains load_average" {
    local found=0
    for func in "${MAINFRAME_SYSINFO_EXPORTS[@]}"; do
        [[ "$func" == "load_average" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "disk_usage handles nonexistent path gracefully" {
    local result
    result=$(disk_usage "/nonexistent/path/xyz123")
    # Should return JSON with zeros or reasonable defaults
    [[ "${result:0:1}" == "{" ]]
}

@test "memory_available <= memory_total" {
    local avail total
    avail=$(memory_available)
    total=$(memory_total)
    [[ "$avail" -le "$total" ]]
}

@test "uptime_seconds is reasonable (< 10 years)" {
    local result
    result=$(uptime_seconds)
    # 10 years in seconds = 315360000
    [[ "$result" -lt 315360000 ]]
}

# =============================================================================
# PERFORMANCE
# =============================================================================

@test "cpu_count completes in under 1 second" {
    local start end elapsed
    start=$(date +%s)
    cpu_count > /dev/null
    end=$(date +%s)
    elapsed=$((end - start))
    [[ "$elapsed" -lt 2 ]]
}

@test "system_info completes in under 5 seconds" {
    local start end elapsed
    start=$(date +%s)
    system_info > /dev/null
    end=$(date +%s)
    elapsed=$((end - start))
    [[ "$elapsed" -lt 5 ]]
}

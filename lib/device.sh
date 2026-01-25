#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/device.sh - Hardware Discovery & Management
# =============================================================================
# Description: Discovers block devices, USB drives, and mounted filesystems.
#              Provides mount/unmount/eject helpers and disk usage analysis.
#              Wraps standard Linux utilities (lsblk, findmnt, blkid, udisksctl)
#              with graceful fallbacks and macOS partial support via diskutil.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS:
#   - Most functions are Linux-only (require lsblk, findmnt, blkid)
#   - macOS support is partial: device_list_blocks, device_list_usb,
#     device_mountpoint, device_fstype, device_size via diskutil
#   - device_eject requires udisksctl on Linux
#   - device_mount/device_unmount require sudo on Linux
#   - device_is_busy requires fuser or lsof
#   - device_uuid requires blkid (Linux only)
#   - device_largest_files/device_oldest_files use find with -maxdepth 3
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

[[ -n "${_MAINFRAME_DEVICE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DEVICE_LOADED=1

# Source common.sh for logging
source "${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh" 2>/dev/null || true

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _device_is_linux
# Returns 0 if running on Linux
_device_is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

# _device_is_macos
# Returns 0 if running on macOS
_device_is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

# _device_check_tools TOOL...
# Verify required tools are available. Returns 1 and logs warning if missing.
_device_check_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            log_warn "device: required tool '$tool' not found"
            return 1
        fi
    done
    return 0
}

# _device_parse_lsblk [ARGS...]
# Run lsblk with standard output columns, return normalized lines.
# Output: NAME SIZE TYPE FSTYPE MOUNTPOINT LABEL (space-separated)
_device_parse_lsblk() {
    lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL "$@" 2>/dev/null
}

# _device_escape_json STRING
# Escape a string for safe JSON embedding
_device_escape_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# =============================================================================
# DEVICE DISCOVERY
# =============================================================================

# device_list_blocks
# List all block devices. Output: "NAME SIZE TYPE FSTYPE MOUNTPOINT LABEL" per line
device_list_blocks() {
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        _device_parse_lsblk
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
        diskutil list 2>/dev/null | grep -E '^\s+[0-9]+:' | \
            awk '{print $NF, $3, $2, "-", "-", "-"}'
    else
        log_warn "device: unsupported platform"
        return 1
    fi
}

# device_list_usb
# List USB/removable drives only (RM=1 or TRAN=usb)
device_list_usb() {
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,RM,TRAN 2>/dev/null | \
            awk '$7 == "1" || $8 == "usb" { print $1, $2, $3, $4, $5, $6 }'
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
        diskutil list external 2>/dev/null | grep -E '^\s+[0-9]+:' | \
            awk '{print $NF, $3, $2, "-", "-", "-"}'
    else
        log_warn "device: unsupported platform"
        return 1
    fi
}

# device_list_unmounted
# List partitions with no mountpoint
device_list_unmounted() {
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | \
            awk '$3 == "part" && $5 == "" { print "/dev/" $1, $2, $4 }'
    elif _device_is_macos; then
        log_warn "device: device_list_unmounted not supported on macOS"
        return 1
    fi
}

# device_list_mounted
# List currently mounted filesystems (from findmnt)
device_list_mounted() {
    if _device_is_linux; then
        _device_check_tools findmnt || return 1
        findmnt -ln -o SOURCE,TARGET,FSTYPE,SIZE,USED 2>/dev/null | \
            grep -E '^/dev/'
    elif _device_is_macos; then
        mount 2>/dev/null | grep -E '^/dev/' | awk '{print $1, $3, $5}'
    else
        log_warn "device: unsupported platform"
        return 1
    fi
}

# device_mountpoint DEVICE
# Get mount point for /dev/sdX. Prints mountpoint or empty string.
device_mountpoint() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_mountpoint requires device path"; return 1; }
    if _device_is_linux; then
        _device_check_tools findmnt || return 1
        findmnt -n -o TARGET "$dev" 2>/dev/null | head -1
    elif _device_is_macos; then
        diskutil info "$dev" 2>/dev/null | awk -F: '/Mount Point/ { gsub(/^[ \t]+/, "", $2); print $2 }'
    fi
}

# device_fstype DEVICE
# Get filesystem type for device
device_fstype() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_fstype requires device path"; return 1; }
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o FSTYPE "$dev" 2>/dev/null | head -1
    elif _device_is_macos; then
        diskutil info "$dev" 2>/dev/null | awk -F: '/File System Personality/ { gsub(/^[ \t]+/, "", $2); print $2 }'
    fi
}

# device_size DEVICE
# Human-readable size (e.g., "16G")
device_size() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_size requires device path"; return 1; }
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o SIZE "$dev" 2>/dev/null | head -1
    elif _device_is_macos; then
        diskutil info "$dev" 2>/dev/null | awk -F: '/Disk Size/ { gsub(/^[ \t]+/, "", $2); print $2 }' | awk '{print $1 $2}'
    fi
}

# device_label DEVICE
# Get partition label
device_label() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_label requires device path"; return 1; }
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o LABEL "$dev" 2>/dev/null | head -1
    elif _device_is_macos; then
        diskutil info "$dev" 2>/dev/null | awk -F: '/Volume Name/ { gsub(/^[ \t]+/, "", $2); print $2 }'
    fi
}

# device_is_removable DEVICE
# Return 0 if removable, 1 if not
device_is_removable() {
    local dev="$1"
    [[ -z "$dev" ]] && return 1
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        local rm
        rm=$(lsblk -ln -o RM "$dev" 2>/dev/null | head -1 | tr -d ' ')
        [[ "$rm" == "1" ]]
    elif _device_is_macos; then
        diskutil info "$dev" 2>/dev/null | grep -qi "Removable Media:.*Yes"
    fi
}

# device_uuid DEVICE
# Get UUID for device (Linux only, requires blkid)
device_uuid() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_uuid requires device path"; return 1; }
    if _device_is_linux; then
        _device_check_tools blkid || return 1
        blkid -s UUID -o value "$dev" 2>/dev/null
    else
        log_warn "device: device_uuid is Linux-only"
        return 1
    fi
}

# =============================================================================
# MOUNT HELPERS
# =============================================================================

# device_mount DEVICE DIRECTORY
# Mount device to directory. Requires sudo.
device_mount() {
    local dev="$1" dir="$2"
    [[ -z "$dev" || -z "$dir" ]] && { log_warn "device: device_mount requires device and directory"; return 1; }
    log_warn "device: device_mount may require sudo"
    if _device_is_linux; then
        _device_check_tools mount || return 1
        [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null
        sudo mount "$dev" "$dir"
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
        [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null
        sudo mount -t auto "$dev" "$dir"
    fi
}

# device_unmount DEVICE_OR_MOUNTPOINT
# Unmount by device path or mountpoint. Requires sudo on Linux.
device_unmount() {
    local target="$1"
    [[ -z "$target" ]] && { log_warn "device: device_unmount requires device or mountpoint"; return 1; }
    log_warn "device: device_unmount may require sudo"
    if _device_is_linux; then
        _device_check_tools umount || return 1
        sudo umount "$target" 2>/dev/null
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
        diskutil unmount "$target" 2>/dev/null
    fi
}

# device_eject DEVICE
# Unmount + power-off for safe USB removal. Verifies removable first.
device_eject() {
    local dev="$1"
    [[ -z "$dev" ]] && { log_warn "device: device_eject requires device path"; return 1; }

    if ! device_is_removable "$dev"; then
        log_warn "device: '$dev' is not removable, refusing to eject"
        return 1
    fi

    if _device_is_linux; then
        # Unmount all partitions of this device
        local part
        while IFS= read -r part; do
            [[ -n "$part" ]] && sudo umount "/dev/$part" 2>/dev/null
        done < <(lsblk -ln -o NAME,MOUNTPOINT "$dev" 2>/dev/null | awk '$2 != "" {print $1}')

        if command -v udisksctl &>/dev/null; then
            udisksctl power-off -b "$dev" 2>/dev/null
        else
            log_warn "device: udisksctl not found, device unmounted but not powered off"
        fi
    elif _device_is_macos; then
        diskutil eject "$dev" 2>/dev/null
    fi
}

# device_is_busy DEVICE_OR_MOUNTPOINT
# Check if device/mountpoint is busy. Returns 0 if busy, 1 if free.
device_is_busy() {
    local target="$1"
    [[ -z "$target" ]] && return 1
    if command -v fuser &>/dev/null; then
        fuser -s "$target" 2>/dev/null
        return $?
    elif command -v lsof &>/dev/null; then
        lsof "$target" &>/dev/null
        return $?
    else
        log_warn "device: neither fuser nor lsof available"
        return 1
    fi
}

# =============================================================================
# DISCOVERY HELPERS
# =============================================================================

# device_find_by_label LABEL
# Find device path by partition label
device_find_by_label() {
    local lbl="$1"
    [[ -z "$lbl" ]] && { log_warn "device: device_find_by_label requires a label"; return 1; }
    if _device_is_linux; then
        _device_check_tools blkid || return 1
        blkid -L "$lbl" 2>/dev/null
    elif _device_is_macos; then
        diskutil list 2>/dev/null | awk -v lbl="$lbl" '$0 ~ lbl { print $NF }'
    fi
}

# device_find_by_uuid UUID
# Find device path by UUID
device_find_by_uuid() {
    local uuid="$1"
    [[ -z "$uuid" ]] && { log_warn "device: device_find_by_uuid requires a UUID"; return 1; }
    if _device_is_linux; then
        _device_check_tools blkid || return 1
        blkid -U "$uuid" 2>/dev/null
    else
        log_warn "device: device_find_by_uuid is Linux-only"
        return 1
    fi
}

# device_find_by_fstype FSTYPE
# Find devices by filesystem type. Output: device paths, one per line.
device_find_by_fstype() {
    local fs="$1"
    [[ -z "$fs" ]] && { log_warn "device: device_find_by_fstype requires a filesystem type"; return 1; }
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
        lsblk -ln -o NAME,FSTYPE 2>/dev/null | awk -v fs="$fs" '$2 == fs { print "/dev/" $1 }'
    elif _device_is_macos; then
        log_warn "device: device_find_by_fstype is Linux-only"
        return 1
    fi
}

# =============================================================================
# DISK USAGE
# =============================================================================

# device_usage PATH
# Output: "used total available percent" for the filesystem containing PATH
device_usage() {
    local path="${1:-.}"
    [[ -e "$path" ]] || { log_warn "device: path '$path' does not exist"; return 1; }
    df -h "$path" 2>/dev/null | awk 'NR==2 { print $3, $2, $4, $5 }'
}

# device_largest_files PATH [N]
# Top N largest files under PATH (default 10, maxdepth 3)
device_largest_files() {
    local path="${1:-.}" n="${2:-10}"
    [[ -d "$path" ]] || { log_warn "device: '$path' is not a directory"; return 1; }
    find "$path" -maxdepth 3 -type f -printf '%s %p\n' 2>/dev/null | \
        sort -rn | head -n "$n" | \
        awk '{
            size=$1
            if (size >= 1073741824) printf "%.1fG %s\n", size/1073741824, $2
            else if (size >= 1048576) printf "%.1fM %s\n", size/1048576, $2
            else if (size >= 1024) printf "%.1fK %s\n", size/1024, $2
            else printf "%dB %s\n", size, $2
        }'
}

# device_oldest_files PATH [N]
# Top N oldest files by mtime under PATH (default 10, maxdepth 3)
device_oldest_files() {
    local path="${1:-.}" n="${2:-10}"
    [[ -d "$path" ]] || { log_warn "device: '$path' is not a directory"; return 1; }
    find "$path" -maxdepth 3 -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | head -n "$n" | \
        awk '{
            ts=int($1)
            cmd="date -d @" ts " +%Y-%m-%d 2>/dev/null"
            cmd | getline dt
            close(cmd)
            print dt, $2
        }'
}

# =============================================================================
# SUMMARY
# =============================================================================

# device_summary
# JSON summary of all block devices
device_summary() {
    if _device_is_linux; then
        _device_check_tools lsblk || return 1
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
    else
        log_warn "device: unsupported platform"
        return 1
    fi

    local json="["
    local first=1
    local name size dtype fstype mountpoint label

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r name size dtype fstype mountpoint label <<< "$line"
        [[ -z "$name" ]] && continue

        # Clean empty fields
        [[ "$fstype" == "-" ]] && fstype=""
        [[ "$mountpoint" == "-" ]] && mountpoint=""
        [[ "$label" == "-" ]] && label=""

        [[ $first -eq 0 ]] && json+=","
        first=0

        json+="{"
        json+="\"name\":\"$(_device_escape_json "$name")\","
        json+="\"size\":\"$(_device_escape_json "$size")\","
        json+="\"type\":\"$(_device_escape_json "$dtype")\","
        json+="\"fstype\":\"$(_device_escape_json "$fstype")\","
        json+="\"mountpoint\":\"$(_device_escape_json "$mountpoint")\","
        json+="\"label\":\"$(_device_escape_json "$label")\""
        json+="}"
    done < <(device_list_blocks)

    json+="]"
    echo "$json"
}

# device_summary_oneliner
# Quick summary: "3 disks | 2 USB | 1.2TB free"
device_summary_oneliner() {
    if _device_is_linux; then
        _device_check_tools lsblk || return 1

        local disk_count usb_count free_bytes
        disk_count=$(lsblk -ln -o TYPE 2>/dev/null | grep -c '^disk$')
        usb_count=$(device_list_usb 2>/dev/null | wc -l)

        # Sum available space from all mounted real filesystems
        free_bytes=$(df -B1 --output=avail 2>/dev/null | tail -n +2 | \
            awk '{ sum += $1 } END { print sum }')

        local free_human
        if [[ -n "$free_bytes" ]] && [[ "$free_bytes" -gt 0 ]]; then
            if [[ "$free_bytes" -ge 1099511627776 ]]; then
                free_human="$(awk "BEGIN { printf \"%.1f\", $free_bytes/1099511627776 }")TB"
            elif [[ "$free_bytes" -ge 1073741824 ]]; then
                free_human="$(awk "BEGIN { printf \"%.1f\", $free_bytes/1073741824 }")GB"
            else
                free_human="$(awk "BEGIN { printf \"%.0f\", $free_bytes/1048576 }")MB"
            fi
        else
            free_human="unknown"
        fi

        echo "${disk_count} disks | ${usb_count} USB | ${free_human} free"
    elif _device_is_macos; then
        _device_check_tools diskutil || return 1
        local disk_count usb_count free_human
        disk_count=$(diskutil list 2>/dev/null | grep -c '/dev/disk')
        usb_count=$(diskutil list external 2>/dev/null | grep -c '/dev/disk')
        free_human=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
        echo "${disk_count} disks | ${usb_count} USB | ${free_human} free"
    fi
}

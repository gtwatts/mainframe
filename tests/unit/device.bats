#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Device Library Tests
# =============================================================================
# Tests for lib/device.sh - Hardware Discovery & Management
# =============================================================================
# NOTE: Device functions depend on system state (lsblk, mount, etc.)
# We test helpers/parsers directly, mock external tools where needed,
# and verify graceful failure on missing tools.
# =============================================================================

setup() {
    # Source the library directly
    export MAINFRAME_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${MAINFRAME_ROOT}/lib/device.sh"

    # Create temporary test directory
    TEST_DIR=$(mktemp -d "/tmp/mainframe-device.XXXXXX")

    # Detect platform once for conditional tests
    PLATFORM="$(uname -s)"
}

teardown() {
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
    # Restore PATH if modified
    if [[ -n "${ORIG_PATH:-}" ]]; then
        export PATH="$ORIG_PATH"
        unset ORIG_PATH
    fi
}

# =============================================================================
# INTERNAL HELPERS: _device_is_linux / _device_is_macos
# =============================================================================

@test "_device_is_linux returns 0 on Linux" {
    if [[ "$PLATFORM" == "Linux" ]]; then
        run _device_is_linux
        [ "$status" -eq 0 ]
    else
        skip "Not running on Linux"
    fi
}

@test "_device_is_macos returns 0 on macOS" {
    if [[ "$PLATFORM" == "Darwin" ]]; then
        run _device_is_macos
        [ "$status" -eq 0 ]
    else
        skip "Not running on macOS"
    fi
}

@test "_device_is_linux and _device_is_macos are mutually exclusive" {
    local linux_rc macos_rc
    _device_is_linux && linux_rc=0 || linux_rc=1
    _device_is_macos && macos_rc=0 || macos_rc=1

    # Exactly one should succeed (or both fail on unknown platform)
    [[ $linux_rc -ne $macos_rc ]] || { [[ $linux_rc -eq 1 ]] && [[ $macos_rc -eq 1 ]]; }
}

@test "_device_is_linux returns 1 on macOS" {
    if [[ "$PLATFORM" == "Darwin" ]]; then
        run _device_is_linux
        [ "$status" -eq 1 ]
    else
        skip "Not running on macOS"
    fi
}

@test "_device_is_macos returns 1 on Linux" {
    if [[ "$PLATFORM" == "Linux" ]]; then
        run _device_is_macos
        [ "$status" -eq 1 ]
    else
        skip "Not running on Linux"
    fi
}

# =============================================================================
# INTERNAL HELPERS: _device_check_tools
# =============================================================================

@test "_device_check_tools succeeds for available tool" {
    run _device_check_tools "bash"
    [ "$status" -eq 0 ]
}

@test "_device_check_tools fails for missing tool" {
    run _device_check_tools "nonexistent_tool_xyz_12345"
    [ "$status" -eq 1 ]
}

@test "_device_check_tools checks multiple tools" {
    run _device_check_tools "bash" "cat" "echo"
    [ "$status" -eq 0 ]
}

@test "_device_check_tools fails if any tool is missing" {
    run _device_check_tools "bash" "nonexistent_tool_xyz_12345"
    [ "$status" -eq 1 ]
}

# =============================================================================
# INTERNAL HELPERS: _device_escape_json
# =============================================================================

@test "_device_escape_json escapes double quotes" {
    run _device_escape_json 'say "hello"'
    [ "$status" -eq 0 ]
    [[ "$output" == 'say \"hello\"' ]]
}

@test "_device_escape_json escapes backslashes" {
    run _device_escape_json 'path\to\file'
    [ "$status" -eq 0 ]
    [[ "$output" == 'path\\to\\file' ]]
}

@test "_device_escape_json handles empty string" {
    run _device_escape_json ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# =============================================================================
# DEVICE DISCOVERY: device_list_blocks
# =============================================================================

@test "device_list_blocks produces output on supported platform" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v lsblk &>/dev/null; then
        run device_list_blocks
        [ "$status" -eq 0 ]
        [ "${#lines[@]}" -ge 1 ]
    elif [[ "$PLATFORM" == "Darwin" ]] && command -v diskutil &>/dev/null; then
        run device_list_blocks
        [ "$status" -eq 0 ]
    else
        skip "No lsblk or diskutil available"
    fi
}

@test "device_list_blocks returns 1 if lsblk not available" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    # Hide lsblk by overriding PATH
    ORIG_PATH="$PATH"
    export PATH="$TEST_DIR/bin"
    mkdir -p "$TEST_DIR/bin"
    # Provide only essential tools (bash, etc.) but not lsblk
    run device_list_blocks
    [ "$status" -eq 1 ]
    export PATH="$ORIG_PATH"
    unset ORIG_PATH
}

# =============================================================================
# DEVICE DISCOVERY: device_list_mounted
# =============================================================================

@test "device_list_mounted shows at least root on Linux" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v findmnt &>/dev/null; then
        skip "findmnt not available"
    fi
    run device_list_mounted
    [ "$status" -eq 0 ]
    [[ "$output" == *"/"* ]]
}

@test "device_list_mounted produces output on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_list_mounted
    [ "$status" -eq 0 ]
    [[ "$output" == *"/"* ]]
}

# =============================================================================
# DEVICE DISCOVERY: device_mountpoint
# =============================================================================

@test "device_mountpoint returns error for empty device" {
    run device_mountpoint ""
    [ "$status" -eq 1 ]
}

@test "device_mountpoint returns empty for nonexistent device" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v findmnt &>/dev/null; then
        run device_mountpoint "/dev/nonexistent_device_xyz"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    elif [[ "$PLATFORM" == "Darwin" ]]; then
        run device_mountpoint "/dev/nonexistent_device_xyz"
        [ -z "$output" ]
    else
        skip "No findmnt or diskutil available"
    fi
}

# =============================================================================
# DEVICE DISCOVERY: device_fstype
# =============================================================================

@test "device_fstype returns error for empty device" {
    run device_fstype ""
    [ "$status" -eq 1 ]
}

@test "device_fstype returns empty for nonexistent device" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v lsblk &>/dev/null; then
        run device_fstype "/dev/nonexistent_device_xyz"
        [ -z "$output" ]
    else
        skip "Linux with lsblk required"
    fi
}

# =============================================================================
# DEVICE DISCOVERY: device_size
# =============================================================================

@test "device_size returns error for empty device" {
    run device_size ""
    [ "$status" -eq 1 ]
}

@test "device_size returns empty for nonexistent device" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v lsblk &>/dev/null; then
        run device_size "/dev/nonexistent_device_xyz"
        [ -z "$output" ]
    else
        skip "Linux with lsblk required"
    fi
}

# =============================================================================
# DEVICE DISCOVERY: device_is_removable
# =============================================================================

@test "device_is_removable returns 1 for empty device" {
    run device_is_removable ""
    [ "$status" -eq 1 ]
}

@test "device_is_removable returns 1 for nonexistent device" {
    run device_is_removable "/dev/nonexistent_device_xyz"
    [ "$status" -ne 0 ]
}

@test "device_is_removable returns 1 for root device on Linux" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    # Find the root device
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    if [[ -z "$root_dev" ]]; then
        skip "Cannot determine root device"
    fi
    # Root device should not be removable
    run device_is_removable "$root_dev"
    [ "$status" -eq 1 ]
}

# =============================================================================
# DISCOVERY HELPERS: device_find_by_label
# =============================================================================

@test "device_find_by_label returns error for empty label" {
    run device_find_by_label ""
    [ "$status" -eq 1 ]
}

@test "device_find_by_label returns empty for nonexistent label" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v blkid &>/dev/null; then
        run device_find_by_label "NONEXISTENT_LABEL_XYZ_12345"
        [ -z "$output" ]
    elif [[ "$PLATFORM" == "Darwin" ]]; then
        run device_find_by_label "NONEXISTENT_LABEL_XYZ_12345"
        [ -z "$output" ]
    else
        skip "blkid or diskutil required"
    fi
}

# =============================================================================
# DISCOVERY HELPERS: device_find_by_uuid
# =============================================================================

@test "device_find_by_uuid returns error for empty UUID" {
    run device_find_by_uuid ""
    [ "$status" -eq 1 ]
}

@test "device_find_by_uuid returns empty for nonexistent UUID" {
    if [[ "$PLATFORM" == "Linux" ]] && command -v blkid &>/dev/null; then
        run device_find_by_uuid "00000000-0000-0000-0000-000000000000"
        [ -z "$output" ]
    else
        skip "Linux with blkid required"
    fi
}

@test "device_find_by_uuid fails on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_find_by_uuid "some-uuid"
    [ "$status" -eq 1 ]
}

# =============================================================================
# DISK USAGE: device_usage
# =============================================================================

@test "device_usage returns 4 fields for root path" {
    run device_usage "/"
    [ "$status" -eq 0 ]
    local field_count
    field_count=$(echo "$output" | awk '{print NF}')
    [ "$field_count" -eq 4 ]
}

@test "device_usage percent field contains %" {
    run device_usage "/"
    [ "$status" -eq 0 ]
    local percent
    percent=$(echo "$output" | awk '{print $4}')
    [[ "$percent" == *"%" ]]
}

@test "device_usage fails for nonexistent path" {
    run device_usage "/nonexistent_path_xyz_12345"
    [ "$status" -eq 1 ]
}

# =============================================================================
# DISK USAGE: device_largest_files
# =============================================================================

@test "device_largest_files returns files from directory" {
    # Create some temp files with known sizes
    dd if=/dev/zero of="$TEST_DIR/large.bin" bs=1024 count=10 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/small.bin" bs=1024 count=1 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/medium.bin" bs=1024 count=5 2>/dev/null

    run device_largest_files "$TEST_DIR" 3
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -le 3 ]
    # Largest file should appear first
    [[ "${lines[0]}" == *"large.bin"* ]]
}

@test "device_largest_files respects N parameter" {
    dd if=/dev/zero of="$TEST_DIR/a.bin" bs=1024 count=5 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/b.bin" bs=1024 count=3 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/c.bin" bs=1024 count=1 2>/dev/null

    run device_largest_files "$TEST_DIR" 2
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "device_largest_files fails for nonexistent directory" {
    run device_largest_files "/nonexistent_dir_xyz_12345"
    [ "$status" -eq 1 ]
}

@test "device_largest_files shows human-readable sizes" {
    dd if=/dev/zero of="$TEST_DIR/file.bin" bs=1024 count=10 2>/dev/null

    run device_largest_files "$TEST_DIR" 1
    [ "$status" -eq 0 ]
    # Should contain K, M, G, or B suffix
    [[ "$output" =~ [0-9]+\.[0-9]+[KMG]|[0-9]+B ]]
}

# =============================================================================
# DISK USAGE: device_oldest_files
# =============================================================================

@test "device_oldest_files returns files from directory" {
    # Create files - oldest first
    printf "old content\n" > "$TEST_DIR/old.txt"
    touch -d "2020-01-01" "$TEST_DIR/old.txt" 2>/dev/null || \
        touch -t 202001010000 "$TEST_DIR/old.txt" 2>/dev/null || true
    printf "new content\n" > "$TEST_DIR/new.txt"

    run device_oldest_files "$TEST_DIR" 5
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]
}

@test "device_oldest_files respects N parameter" {
    printf "a\n" > "$TEST_DIR/a.txt"
    printf "b\n" > "$TEST_DIR/b.txt"
    printf "c\n" > "$TEST_DIR/c.txt"

    run device_oldest_files "$TEST_DIR" 2
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -le 2 ]
}

@test "device_oldest_files fails for nonexistent directory" {
    run device_oldest_files "/nonexistent_dir_xyz_12345"
    [ "$status" -eq 1 ]
}

# =============================================================================
# SUMMARY: device_summary
# =============================================================================

@test "device_summary outputs JSON array" {
    if [[ "$PLATFORM" == "Linux" ]] && ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    if [[ "$PLATFORM" == "Darwin" ]] && ! command -v diskutil &>/dev/null; then
        skip "diskutil not available"
    fi
    run device_summary
    [ "$status" -eq 0 ]
    # JSON array starts with [
    [[ "$output" == "["* ]]
    # JSON array ends with ]
    [[ "$output" == *"]" ]]
}

@test "device_summary contains expected JSON keys" {
    if [[ "$PLATFORM" == "Linux" ]] && ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    if [[ "$PLATFORM" == "Darwin" ]] && ! command -v diskutil &>/dev/null; then
        skip "diskutil not available"
    fi
    run device_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name"'* ]]
    [[ "$output" == *'"size"'* ]]
    [[ "$output" == *'"type"'* ]]
}

# =============================================================================
# SUMMARY: device_summary_oneliner
# =============================================================================

@test "device_summary_oneliner produces single line output" {
    if [[ "$PLATFORM" == "Linux" ]] && ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    if [[ "$PLATFORM" == "Darwin" ]] && ! command -v diskutil &>/dev/null; then
        skip "diskutil not available"
    fi
    run device_summary_oneliner
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "device_summary_oneliner contains disk and free info" {
    if [[ "$PLATFORM" == "Linux" ]] && ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    if [[ "$PLATFORM" == "Darwin" ]] && ! command -v diskutil &>/dev/null; then
        skip "diskutil not available"
    fi
    run device_summary_oneliner
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk"* ]]
    [[ "$output" == *"free"* ]]
}

@test "device_summary_oneliner contains USB count" {
    if [[ "$PLATFORM" == "Linux" ]] && ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    if [[ "$PLATFORM" == "Darwin" ]] && ! command -v diskutil &>/dev/null; then
        skip "diskutil not available"
    fi
    run device_summary_oneliner
    [ "$status" -eq 0 ]
    [[ "$output" == *"USB"* ]]
}

# =============================================================================
# USB AND UNMOUNTED: device_list_usb / device_list_unmounted
# =============================================================================

@test "device_list_usb runs without error on Linux" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    run device_list_usb
    # Should succeed even if output is empty (no USB devices)
    [ "$status" -eq 0 ]
}

@test "device_list_usb runs without error on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_list_usb
    [ "$status" -eq 0 ]
}

@test "device_list_unmounted runs without error on Linux" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    run device_list_unmounted
    [ "$status" -eq 0 ]
}

@test "device_list_unmounted fails on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_list_unmounted
    [ "$status" -eq 1 ]
}

# =============================================================================
# MOUNT HELPERS: device_mount / device_unmount / device_eject
# =============================================================================

@test "device_mount returns error for missing arguments" {
    run device_mount "" ""
    [ "$status" -eq 1 ]
}

@test "device_mount returns error for missing directory" {
    run device_mount "/dev/sda1" ""
    [ "$status" -eq 1 ]
}

@test "device_unmount returns error for missing argument" {
    run device_unmount ""
    [ "$status" -eq 1 ]
}

@test "device_eject returns error for missing argument" {
    run device_eject ""
    [ "$status" -eq 1 ]
}

@test "device_eject refuses non-removable device" {
    run device_eject "/dev/nonexistent_device_xyz"
    [ "$status" -eq 1 ]
}

# =============================================================================
# MOUNT HELPERS: device_is_busy
# =============================================================================

@test "device_is_busy returns 1 for nonexistent path" {
    run device_is_busy "/nonexistent_path_xyz_12345"
    [ "$status" -eq 1 ]
}

@test "device_is_busy returns 1 for empty argument" {
    run device_is_busy ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# DEVICE INFO: device_label / device_uuid
# =============================================================================

@test "device_label returns error for empty device" {
    run device_label ""
    [ "$status" -eq 1 ]
}

@test "device_uuid returns error for empty device" {
    run device_uuid ""
    [ "$status" -eq 1 ]
}

@test "device_uuid fails on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_uuid "/dev/disk0"
    [ "$status" -eq 1 ]
}

# =============================================================================
# DISCOVERY HELPERS: device_find_by_fstype
# =============================================================================

@test "device_find_by_fstype returns error for empty fstype" {
    run device_find_by_fstype ""
    [ "$status" -eq 1 ]
}

@test "device_find_by_fstype finds ext4 on Linux" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    # ext4 is the most common Linux filesystem; if not present, skip
    run device_find_by_fstype "ext4"
    if [ "$status" -eq 0 ] && [ -n "$output" ]; then
        [[ "$output" == *"/dev/"* ]]
    fi
    # Status 0 is valid even if no ext4 partitions exist
    [ "$status" -eq 0 ]
}

@test "device_find_by_fstype returns empty for nonexistent fstype" {
    if [[ "$PLATFORM" != "Linux" ]]; then
        skip "Linux-specific test"
    fi
    if ! command -v lsblk &>/dev/null; then
        skip "lsblk not available"
    fi
    run device_find_by_fstype "nonexistent_fs_xyz"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "device_find_by_fstype fails on macOS" {
    if [[ "$PLATFORM" != "Darwin" ]]; then
        skip "macOS-specific test"
    fi
    run device_find_by_fstype "apfs"
    [ "$status" -eq 1 ]
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/idempotent.sh - Idempotent Operations for AI Agents
# =============================================================================
# Description: Check-before-act operations that produce the same result
#              regardless of how many times they're executed. Essential for
#              AI coding assistants that frequently re-run scripts after
#              context loss or retry failed operations.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_IDEMPOTENT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_IDEMPOTENT_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_idem_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[idempotent] %s: %s\n' "${level}" "$*" >&2
    fi
}

# =============================================================================
# DIRECTORY OPERATIONS
# =============================================================================

# @pre: parent directory is writable (or path is creatable)
# @post: directory exists with given permissions
# @idempotent: yes - no-op if directory already exists with correct perms
# @returns: 0 on success (created or already exists), 1 on failure
#
# Create directory only if it doesn't exist.
# Optionally set permissions if provided.
#
# Usage: ensure_dir "/path/to/dir" [mode]
# Example: ensure_dir "/var/log/myapp" "0755"
ensure_dir() {
    local dir="$1"
    local mode="${2:-}"

    if [[ -z "$dir" ]]; then
        _idem_log error "ensure_dir: directory path required"
        return 1
    fi

    # Already exists as directory
    if [[ -d "$dir" ]]; then
        # Fix permissions if mode specified and different
        if [[ -n "$mode" ]]; then
            local current_mode
            if [[ "$OSTYPE" == darwin* ]]; then
                current_mode=$(stat -f '%Lp' "$dir" 2>/dev/null)
            else
                current_mode=$(stat -c '%a' "$dir" 2>/dev/null)
            fi
            if [[ "$current_mode" != "${mode#0}" ]]; then
                chmod "$mode" "$dir" || return 1
                _idem_log debug "ensure_dir: fixed permissions on $dir to $mode"
            fi
        fi
        return 0
    fi

    # Exists but is not a directory
    if [[ -e "$dir" ]]; then
        _idem_log error "ensure_dir: $dir exists but is not a directory"
        return 1
    fi

    # Create it
    mkdir -p "$dir" || return 1
    if [[ -n "$mode" ]]; then
        chmod "$mode" "$dir" || return 1
    fi
    _idem_log debug "ensure_dir: created $dir"
    return 0
}

# =============================================================================
# FILE OPERATIONS
# =============================================================================

# @pre: parent directory exists and is writable
# @post: file exists with specified content (or empty)
# @idempotent: yes - no-op if file exists with matching content
# @returns: 0 on success, 1 on failure
#
# Create file with content only if it doesn't exist or content differs.
# If content is not provided, creates empty file (like touch).
#
# Usage: ensure_file "/path/to/file" ["content"] [mode]
# Example: ensure_file "/etc/myapp.conf" "key=value" "0644"
ensure_file() {
    local file="$1"
    local content="${2:-}"
    local mode="${3:-}"

    if [[ -z "$file" ]]; then
        _idem_log error "ensure_file: file path required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${file%/*}"
    if [[ "$parent_dir" != "$file" ]] && [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    if [[ -z "$content" ]]; then
        # No content specified - just ensure file exists
        if [[ -f "$file" ]]; then
            # Fix permissions if needed
            if [[ -n "$mode" ]]; then
                chmod "$mode" "$file" 2>/dev/null
            fi
            return 0
        fi
        : > "$file" || return 1
    else
        # Content specified - check if it matches
        if [[ -f "$file" ]]; then
            local existing
            existing=$(<"$file")
            if [[ "$existing" == "$content" ]]; then
                # Fix permissions if needed
                if [[ -n "$mode" ]]; then
                    chmod "$mode" "$file" 2>/dev/null
                fi
                return 0
            fi
        fi
        # Write content
        printf '%s' "$content" > "$file" || return 1
    fi

    if [[ -n "$mode" ]]; then
        chmod "$mode" "$file" || return 1
    fi
    _idem_log debug "ensure_file: created/updated $file"
    return 0
}

# @pre: file exists (or will be created)
# @post: line exists in file exactly once
# @idempotent: yes - no-op if line already present
# @returns: 0 on success, 1 on failure
#
# Append a line to a file only if it's not already present.
# Uses a marker for identification if the line might appear as substring.
#
# Usage: ensure_line "/path/to/file" "line content" [marker]
# Example: ensure_line "/etc/hosts" "127.0.0.1 myapp.local"
# Example: ensure_line "~/.bashrc" 'export PATH="/opt/bin:$PATH"' "MANAGED:opt-bin"
ensure_line() {
    local file="$1"
    local line="$2"
    local marker="${3:-$line}"

    if [[ -z "$file" ]] || [[ -z "$line" ]]; then
        _idem_log error "ensure_line: file and line required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${file%/*}"
    if [[ "$parent_dir" != "$file" ]] && [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    # Create file if it doesn't exist
    [[ -f "$file" ]] || : > "$file"

    # Check if marker already exists in file
    if grep -qF "$marker" "$file" 2>/dev/null; then
        return 0
    fi

    # Append the line
    printf '%s\n' "$line" >> "$file" || return 1
    _idem_log debug "ensure_line: added line to $file"
    return 0
}

# =============================================================================
# SYMLINK OPERATIONS
# =============================================================================

# @pre: target exists (or force=true), parent of link is writable
# @post: symlink points to target
# @idempotent: yes - no-op if symlink already points to correct target
# @returns: 0 on success, 1 on failure
#
# Create or fix symlink to point to the correct target.
# If link exists but points elsewhere, it's replaced.
# If something else exists at link path, fails unless force=true.
#
# Usage: ensure_symlink "target" "link_path" [force]
# Example: ensure_symlink "/opt/app-v2" "/opt/app-current"
# Example: ensure_symlink "/opt/app-v2" "/opt/app-current" true
ensure_symlink() {
    local target="$1"
    local link="$2"
    local force="${3:-false}"

    if [[ -z "$target" ]] || [[ -z "$link" ]]; then
        _idem_log error "ensure_symlink: target and link path required"
        return 1
    fi

    # Already correct
    if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$target" ]]; then
        return 0
    fi

    # Something exists at link path
    if [[ -e "$link" ]] || [[ -L "$link" ]]; then
        if [[ "$force" == "true" ]]; then
            rm -f "$link" || return 1
        else
            if [[ -L "$link" ]]; then
                # Wrong symlink target - safe to replace
                rm -f "$link" || return 1
            else
                _idem_log error "ensure_symlink: $link exists and is not a symlink (use force=true)"
                return 1
            fi
        fi
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${link%/*}"
    if [[ "$parent_dir" != "$link" ]] && [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    ln -sf "$target" "$link" || return 1
    _idem_log debug "ensure_symlink: $link -> $target"
    return 0
}

# =============================================================================
# MOUNT OPERATIONS
# =============================================================================

# @pre: device exists, mountpoint is a directory
# @post: device is mounted at mountpoint
# @idempotent: yes - no-op if already mounted
# @returns: 0 on success, 1 on failure
#
# Mount a device at a mountpoint only if not already mounted.
# Creates the mountpoint directory if needed.
#
# Usage: ensure_mount "device" "mountpoint" [options]
# Example: ensure_mount "/dev/sdb1" "/mnt/data"
# Example: ensure_mount "tmpfs" "/tmp/ramdisk" "-t tmpfs -o size=512m"
ensure_mount() {
    local device="$1"
    local mountpoint="$2"
    local options="${3:-}"

    if [[ -z "$device" ]] || [[ -z "$mountpoint" ]]; then
        _idem_log error "ensure_mount: device and mountpoint required"
        return 1
    fi

    # Check if already mounted at this point
    if mountpoint -q "$mountpoint" 2>/dev/null; then
        return 0
    fi

    # Fallback check if mountpoint command not available
    if ! command -v mountpoint &>/dev/null; then
        if grep -qsF " $mountpoint " /proc/mounts 2>/dev/null; then
            return 0
        fi
    fi

    # Ensure mountpoint directory exists
    ensure_dir "$mountpoint" || return 1

    # Mount with options
    if [[ -n "$options" ]]; then
        # shellcheck disable=SC2086
        mount $options "$device" "$mountpoint" || return 1
    else
        mount "$device" "$mountpoint" || return 1
    fi

    _idem_log debug "ensure_mount: mounted $device at $mountpoint"
    return 0
}

# =============================================================================
# SERVICE OPERATIONS
# =============================================================================

# @pre: service management system available (systemd or init.d)
# @post: service is running
# @idempotent: yes - no-op if service is already active
# @returns: 0 on success (running or started), 1 on failure
#
# Start a system service only if it's not already running.
# Supports systemd, init.d, and simple process checks.
#
# Usage: ensure_service "service_name" [check_command]
# Example: ensure_service "nginx"
# Example: ensure_service "redis" "redis-cli ping"
ensure_service() {
    local service="$1"
    local check_cmd="${2:-}"

    if [[ -z "$service" ]]; then
        _idem_log error "ensure_service: service name required"
        return 1
    fi

    # Custom check command takes priority
    if [[ -n "$check_cmd" ]]; then
        if eval "$check_cmd" &>/dev/null; then
            return 0
        fi
    fi

    # Try systemd first
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            return 0
        fi
        systemctl start "$service" 2>/dev/null && return 0
    fi

    # Try service command
    if command -v service &>/dev/null; then
        if service "$service" status &>/dev/null; then
            return 0
        fi
        service "$service" start 2>/dev/null && return 0
    fi

    # Try init.d
    if [[ -x "/etc/init.d/$service" ]]; then
        if "/etc/init.d/$service" status &>/dev/null; then
            return 0
        fi
        "/etc/init.d/$service" start 2>/dev/null && return 0
    fi

    _idem_log error "ensure_service: could not start $service"
    return 1
}

# =============================================================================
# PACKAGE OPERATIONS
# =============================================================================

# @pre: package manager available
# @post: package is installed
# @idempotent: yes - no-op if package already installed
# @returns: 0 on success (installed or already present), 1 on failure
#
# Install a package only if it's not already installed.
# Auto-detects package manager (apt, dnf, yum, pacman, brew, apk).
#
# Usage: ensure_package "package_name"
# Example: ensure_package "jq"
# Example: ensure_package "curl"
ensure_package() {
    local package="$1"

    if [[ -z "$package" ]]; then
        _idem_log error "ensure_package: package name required"
        return 1
    fi

    # Check if command exists (fast path for common case)
    if command -v "$package" &>/dev/null; then
        return 0
    fi

    # Check with package manager if package is installed
    # (handles cases where package name != binary name)
    if command -v dpkg &>/dev/null; then
        if dpkg -s "$package" &>/dev/null; then
            return 0
        fi
        _idem_log debug "ensure_package: installing $package via apt"
        apt-get install -y "$package" &>/dev/null && return 0
    elif command -v rpm &>/dev/null; then
        if rpm -q "$package" &>/dev/null; then
            return 0
        fi
        if command -v dnf &>/dev/null; then
            dnf install -y "$package" &>/dev/null && return 0
        elif command -v yum &>/dev/null; then
            yum install -y "$package" &>/dev/null && return 0
        fi
    elif command -v pacman &>/dev/null; then
        if pacman -Qi "$package" &>/dev/null; then
            return 0
        fi
        pacman -S --noconfirm "$package" &>/dev/null && return 0
    elif command -v brew &>/dev/null; then
        if brew list "$package" &>/dev/null; then
            return 0
        fi
        brew install "$package" &>/dev/null && return 0
    elif command -v apk &>/dev/null; then
        if apk info -e "$package" &>/dev/null; then
            return 0
        fi
        apk add "$package" &>/dev/null && return 0
    fi

    _idem_log error "ensure_package: could not install $package"
    return 1
}

# =============================================================================
# COMPOUND IDEMPOTENT OPERATIONS
# =============================================================================

# @pre: none
# @post: all specified directories exist
# @idempotent: yes
# @returns: 0 if all created, 1 if any failed
#
# Ensure multiple directories exist in one call.
#
# Usage: ensure_dirs "/path/a" "/path/b" "/path/c"
ensure_dirs() {
    local dir
    local failed=0
    for dir in "$@"; do
        ensure_dir "$dir" || ((failed++))
    done
    return $((failed > 0 ? 1 : 0))
}

# @pre: file exists
# @post: specified lines all exist in file
# @idempotent: yes
# @returns: 0 if all added, 1 if any failed
#
# Ensure multiple lines exist in a file.
#
# Usage: ensure_lines "/path/to/file" "line1" "line2" "line3"
ensure_lines() {
    local file="$1"
    shift
    local line
    local failed=0
    for line in "$@"; do
        ensure_line "$file" "$line" || ((failed++))
    done
    return $((failed > 0 ? 1 : 0))
}

# @pre: command available in PATH or as function
# @post: command/binary is available
# @idempotent: yes - no-op if already available
# @returns: 0 if available, 1 if not
#
# Verify a command is available (doesn't install, just checks).
# Use ensure_package for install behavior.
#
# Usage: ensure_command "jq" || { echo "jq required"; exit 1; }
ensure_command() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        _idem_log error "ensure_command: command name required"
        return 1
    fi
    command -v "$cmd" &>/dev/null
}

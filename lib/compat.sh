#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/compat.sh - BSD/GNU Compatibility Layer
# =============================================================================
# Description: Cross-platform wrappers for common utilities that differ between
#              macOS (BSD) and Linux (GNU coreutils). Provides consistent API
#              regardless of underlying OS.
# Purpose: Write portable scripts that work on macOS, Linux, and BSD without
#          conditionals scattered throughout your code.
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_COMPAT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COMPAT_LOADED=1

# =============================================================================
# BASH VERSION CHECK
# =============================================================================
# Verify minimum bash version
# Called automatically when compat.sh is sourced
_compat_check_bash_version() {
    if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
        printf 'MAINFRAME requires bash 4.0+. Found: %s\n' "${BASH_VERSION:-unknown}" >&2
        printf 'macOS users: brew install bash\n' >&2
        printf 'Then: chsh -s /opt/homebrew/bin/bash\n' >&2
        return 1
    fi
    return 0
}
_compat_check_bash_version || return 1

# =============================================================================
# FEATURE DETECTION FLAGS
# =============================================================================
# Feature flags based on bash version - check capabilities at source time
declare -g BASH_HAS_ASSOC_ARRAYS=0
declare -g BASH_HAS_NAMEREFS=0
declare -g BASH_HAS_NEGATIVE_INDICES=0
declare -g BASH_HAS_EPOCHREALTIME=0
declare -g BASH_HAS_CURRENTSHELL_SUBST=0

((BASH_VERSINFO[0] >= 4)) && BASH_HAS_ASSOC_ARRAYS=1
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))) && {
    BASH_HAS_NAMEREFS=1
    BASH_HAS_NEGATIVE_INDICES=1
}
((BASH_VERSINFO[0] >= 5)) && BASH_HAS_EPOCHREALTIME=1
((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))) && BASH_HAS_CURRENTSHELL_SUBST=1

# =============================================================================
# OS DETECTION (cached on first call)
# =============================================================================

# Cache for detected OS - set once, read many
declare -g _COMPAT_OS=""
declare -g _COMPAT_OS_FAMILY=""

# Detect and cache the operating system
# Internal function - called automatically on first use
_compat_detect_os() {
    [[ -n "$_COMPAT_OS" ]] && return 0

    local uname_s
    uname_s="$(uname -s 2>/dev/null)" || uname_s="unknown"

    case "$uname_s" in
        Darwin)
            _COMPAT_OS="macos"
            _COMPAT_OS_FAMILY="bsd"
            ;;
        Linux)
            # Check for WSL before setting generic Linux
            if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
                _COMPAT_OS="wsl"
                _COMPAT_OS_FAMILY="gnu"
            else
                _COMPAT_OS="linux"
                _COMPAT_OS_FAMILY="gnu"
            fi
            ;;
        FreeBSD)
            _COMPAT_OS="freebsd"
            _COMPAT_OS_FAMILY="bsd"
            ;;
        OpenBSD)
            _COMPAT_OS="openbsd"
            _COMPAT_OS_FAMILY="bsd"
            ;;
        NetBSD)
            _COMPAT_OS="netbsd"
            _COMPAT_OS_FAMILY="bsd"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            _COMPAT_OS="windows"
            _COMPAT_OS_FAMILY="gnu"  # GNU tools typically available
            ;;
        *)
            _COMPAT_OS="unknown"
            _COMPAT_OS_FAMILY="unknown"
            ;;
    esac
}

# Get the detected OS name
# Usage: os=$(compat::get_os)
# Returns: macos, linux, freebsd, openbsd, netbsd, windows, or unknown
compat::get_os() {
    _compat_detect_os
    printf '%s' "$_COMPAT_OS"
}

# Get the OS family (bsd or gnu)
# Usage: family=$(compat::get_os_family)
# Returns: bsd, gnu, or unknown
compat::get_os_family() {
    _compat_detect_os
    printf '%s' "$_COMPAT_OS_FAMILY"
}

# Check if running on macOS
# Usage: compat::is_macos && echo "Running on macOS"
compat::is_macos() {
    _compat_detect_os
    [[ "$_COMPAT_OS" == "macos" ]]
}

# Check if running on Linux (includes WSL)
# Usage: compat::is_linux && echo "Running on Linux"
# Note: Returns true for both native Linux and WSL
compat::is_linux() {
    _compat_detect_os
    [[ "$_COMPAT_OS" == "linux" || "$_COMPAT_OS" == "wsl" ]]
}

# Check if running on any BSD variant
# Usage: compat::is_bsd && echo "Running on BSD"
compat::is_bsd() {
    _compat_detect_os
    [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]
}

# Check if running on FreeBSD specifically
# Usage: compat::is_freebsd && echo "Running on FreeBSD"
compat::is_freebsd() {
    _compat_detect_os
    [[ "$_COMPAT_OS" == "freebsd" ]]
}

# Check if GNU coreutils are available (Linux or GNU tools installed)
# Usage: compat::has_gnu && echo "GNU tools available"
compat::has_gnu() {
    _compat_detect_os
    [[ "$_COMPAT_OS_FAMILY" == "gnu" ]]
}

# =============================================================================
# WSL DETECTION AND PATH CONVERSION
# =============================================================================

# Check if running in WSL (Windows Subsystem for Linux)
# Usage: compat::is_wsl && echo "Running in WSL"
compat::is_wsl() {
    [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null
}

# Convert WSL path to Windows path
# Usage: compat::wsl_to_windows "/home/user/file"
# Returns: Windows-style path (e.g., C:\Users\...)
compat::wsl_to_windows() {
    local path="$1"
    if compat::is_wsl && command -v wslpath &>/dev/null; then
        wslpath -w "$path" 2>/dev/null || printf '%s' "$path"
    else
        printf '%s' "$path"
    fi
}

# Convert Windows path to WSL path
# Usage: compat::windows_to_wsl "C:\Users\file"
# Returns: WSL-style path (e.g., /mnt/c/Users/...)
compat::windows_to_wsl() {
    local path="$1"
    if compat::is_wsl && command -v wslpath &>/dev/null; then
        wslpath -u "$path" 2>/dev/null || printf '%s' "$path"
    else
        printf '%s' "$path"
    fi
}

# =============================================================================
# ALPINE/BUSYBOX DETECTION
# =============================================================================

# Check if running on Alpine Linux
# Usage: compat::is_alpine && echo "Running on Alpine"
compat::is_alpine() {
    [[ -f /etc/alpine-release ]]
}

# Check if shell commands are BusyBox
# Usage: compat::is_busybox && echo "Using BusyBox"
compat::is_busybox() {
    command -v busybox &>/dev/null && busybox --help 2>&1 | grep -q BusyBox
}

# =============================================================================
# SED WRAPPERS
# =============================================================================
# BSD sed (macOS) and GNU sed have key differences:
# - In-place editing: BSD requires -i '' while GNU uses -i or -i''
# - Extended regex: BSD uses -E, GNU uses -E or -r
# =============================================================================

# In-place sed edit that works on both BSD and GNU
# Usage: compat::sed_inplace file 'expression'
# Example: compat::sed_inplace config.txt 's/old/new/g'
compat::sed_inplace() {
    local file="$1"
    shift
    local expression="$*"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        # BSD sed requires '' after -i
        sed -i '' "$expression" "$file"
    else
        # GNU sed uses -i without argument
        sed -i "$expression" "$file"
    fi
}

# In-place sed with extended regex (ERE) that works on both BSD and GNU
# Usage: compat::sed_inplace_extended file 'expression'
# Example: compat::sed_inplace_extended file.txt 's/(foo|bar)/baz/g'
compat::sed_inplace_extended() {
    local file="$1"
    shift
    local expression="$*"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        sed -i '' -E "$expression" "$file"
    else
        sed -i -E "$expression" "$file"
    fi
}

# Extended regex sed (non-inplace) - portable ERE
# Usage: compat::sed_extended 'expression' [file...]
# Example: echo "foobar" | compat::sed_extended 's/(foo)(bar)/\2\1/'
compat::sed_extended() {
    # -E works on both modern BSD and GNU sed
    sed -E "$@"
}

# Create a backup before in-place edit
# Usage: compat::sed_inplace_backup file 'expression' [backup_suffix]
# Example: compat::sed_inplace_backup config.txt 's/old/new/g' '.bak'
compat::sed_inplace_backup() {
    local file="$1"
    local expression="$2"
    local backup="${3:-.bak}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        sed -i "$backup" "$expression" "$file"
    else
        sed -i"$backup" "$expression" "$file"
    fi
}

# =============================================================================
# GREP WRAPPERS
# =============================================================================
# BSD grep and GNU grep differences:
# - -P (Perl regex) not available on BSD grep
# - -E (extended regex) works on both
# =============================================================================

# Extended regex grep - portable -E
# Usage: compat::grep_extended 'pattern' [file...]
# Example: compat::grep_extended '(foo|bar)' file.txt
compat::grep_extended() {
    grep -E "$@"
}

# Perl-compatible regex grep with fallback
# Usage: compat::grep_perl 'pattern' [file...]
# Note: Falls back to grep -E on systems without -P support
# Example: compat::grep_perl '\bword\b' file.txt
compat::grep_perl() {
    local pattern="$1"
    shift
    
    # Try -P first (GNU grep), fall back to -E
    if grep -P '' /dev/null 2>/dev/null; then
        grep -P "$pattern" "$@"
    else
        # Fallback to extended regex - some patterns may not work
        grep -E "$pattern" "$@"
    fi
}

# Check if Perl regex is supported
# Usage: compat::has_grep_perl && grep -P 'pattern' file
compat::has_grep_perl() {
    grep -P '' /dev/null 2>/dev/null
}

# Quiet grep that only returns exit status
# Usage: compat::grep_quiet 'pattern' file && echo "found"
compat::grep_quiet() {
    grep -q "$@"
}

# Count matching lines portably
# Usage: count=$(compat::grep_count 'pattern' file)
compat::grep_count() {
    local count
    count=$(grep -c "$@" 2>/dev/null) || count=0
    printf '%s' "$count"
}

# =============================================================================
# DATE WRAPPERS
# =============================================================================
# BSD date (macOS) and GNU date are very different:
# - BSD: date -r <timestamp> +format, date -v+1d
# - GNU: date -d @<timestamp> +format, date -d "+1 day"
# =============================================================================

# Format a Unix timestamp portably
# Usage: compat::date_format '%Y-%m-%d' "$timestamp"
# Example: compat::date_format '%Y-%m-%d %H:%M:%S' 1609459200
compat::date_format() {
    local format="$1"
    local timestamp="${2:-$(date +%s)}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        # BSD date uses -r for timestamp
        date -r "$timestamp" +"$format"
    else
        # GNU date uses -d @timestamp
        date -d "@$timestamp" +"$format"
    fi
}

# Get current date in specified format
# Usage: compat::date_now '%Y-%m-%d'
compat::date_now() {
    local format="${1:-%Y-%m-%d %H:%M:%S}"
    date +"$format"
}

# Add days to current date (or specified date)
# Usage: compat::date_add_days 7 [base_timestamp]
# Returns: Unix timestamp of resulting date
compat::date_add_days() {
    local days="$1"
    local base="${2:-$(date +%s)}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        # BSD date with -v for relative dates
        date -j -v+"${days}d" -f '%s' "$base" '+%s'
    else
        # GNU date: calculate manually for reliability
        echo $((base + days * 86400))
    fi
}

# Subtract days from current date (or specified date)
# Usage: compat::date_sub_days 7 [base_timestamp]
# Returns: Unix timestamp of resulting date
compat::date_sub_days() {
    local days="$1"
    local base="${2:-$(date +%s)}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        date -j -v-"${days}d" -f '%s' "$base" '+%s'
    else
        # GNU date: calculate manually for reliability
        echo $((base - days * 86400))
    fi
}

# Add hours to current date (or specified date)
# Usage: compat::date_add_hours 24 [base_timestamp]
# Returns: Unix timestamp
compat::date_add_hours() {
    local hours="$1"
    local base="${2:-$(date +%s)}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        date -j -v+"${hours}H" -f '%s' "$base" '+%s'
    else
        # GNU date: calculate manually for reliability
        echo $((base + hours * 3600))
    fi
}

# Parse a date string to Unix timestamp
# Usage: compat::date_parse "2024-01-15" "%Y-%m-%d"
# Returns: Unix timestamp
compat::date_parse() {
    local datestr="$1"
    local format="${2:-%Y-%m-%d}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        date -j -f "$format" "$datestr" '+%s'
    else
        date -d "$datestr" '+%s'
    fi
}

# Get day of week (0=Sunday, 6=Saturday)
# Usage: dow=$(compat::date_dow [timestamp])
compat::date_dow() {
    local timestamp="${1:-$(date +%s)}"
    compat::date_format '%w' "$timestamp"
}

# Get ISO week number
# Usage: week=$(compat::date_week [timestamp])
compat::date_week() {
    local timestamp="${1:-$(date +%s)}"
    compat::date_format '%V' "$timestamp"
}

# =============================================================================
# STAT WRAPPERS
# =============================================================================
# BSD stat and GNU stat have completely different syntax:
# - BSD: stat -f '%z' file (size), stat -f '%m' file (mtime)
# - GNU: stat -c '%s' file (size), stat -c '%Y' file (mtime)
# =============================================================================

# Get file size in bytes
# Usage: size=$(compat::stat_size file)
compat::stat_size() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%z' "$file"
    else
        stat -c '%s' "$file"
    fi
}

# Get file modification time as Unix timestamp
# Usage: mtime=$(compat::stat_mtime file)
compat::stat_mtime() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%m' "$file"
    else
        stat -c '%Y' "$file"
    fi
}

# Get file access time as Unix timestamp
# Usage: atime=$(compat::stat_atime file)
compat::stat_atime() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%a' "$file"
    else
        stat -c '%X' "$file"
    fi
}

# Get file creation/birth time (if available)
# Usage: btime=$(compat::stat_btime file)
# Note: Not all filesystems/OS support birth time
compat::stat_btime() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%B' "$file"
    else
        # GNU stat: %W for birth time (0 if unknown)
        local btime
        btime=$(stat -c '%W' "$file" 2>/dev/null) || btime=0
        if [[ "$btime" == "0" ]]; then
            # Fall back to mtime if btime unavailable
            stat -c '%Y' "$file"
        else
            printf '%s' "$btime"
        fi
    fi
}

# Get file permissions in octal
# Usage: perms=$(compat::stat_perms file)
# Returns: e.g., "644" or "755"
compat::stat_perms() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%Lp' "$file"
    else
        stat -c '%a' "$file"
    fi
}

# Get file owner username
# Usage: owner=$(compat::stat_owner file)
compat::stat_owner() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%Su' "$file"
    else
        stat -c '%U' "$file"
    fi
}

# Get file group name
# Usage: group=$(compat::stat_group file)
compat::stat_group() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%Sg' "$file"
    else
        stat -c '%G' "$file"
    fi
}

# Get inode number
# Usage: inode=$(compat::stat_inode file)
compat::stat_inode() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%i' "$file"
    else
        stat -c '%i' "$file"
    fi
}

# Get number of hard links
# Usage: links=$(compat::stat_links file)
compat::stat_links() {
    local file="$1"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        stat -f '%l' "$file"
    else
        stat -c '%h' "$file"
    fi
}

# =============================================================================
# READLINK WRAPPERS  
# =============================================================================
# BSD readlink doesn't support -f (canonicalize), need to use realpath or
# a combination of commands
# =============================================================================

# Get canonical/absolute path (resolve all symlinks)
# Usage: abspath=$(compat::realpath file)
compat::realpath() {
    local path="$1"
    
    # Try realpath first (available on most modern systems)
    if command -v realpath &>/dev/null; then
        realpath "$path"
        return
    fi
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        # macOS: Use Python as fallback, or manual resolution
        if command -v python3 &>/dev/null; then
            python3 -c "import os; print(os.path.realpath('$path'))"
        elif command -v python &>/dev/null; then
            python -c "import os; print(os.path.realpath('$path'))"
        else
            # Manual resolution for simple cases
            cd "$(dirname "$path")" && pwd -P
        fi
    else
        # GNU readlink -f
        readlink -f "$path"
    fi
}

# Get the target of a symlink (non-recursive)
# Usage: target=$(compat::readlink symlink)
compat::readlink() {
    local link="$1"
    readlink "$link"
}

# =============================================================================
# MKTEMP WRAPPERS
# =============================================================================
# BSD mktemp requires template, GNU mktemp has defaults
# =============================================================================

# Create a temporary file
# Usage: tmpfile=$(compat::mktemp)
# Usage: tmpfile=$(compat::mktemp "prefix")
compat::mktemp() {
    local prefix="${1:-tmp}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        mktemp -t "${prefix}"
    else
        mktemp --tmpdir "${prefix}.XXXXXXXXXX"
    fi
}

# Create a temporary directory
# Usage: tmpdir=$(compat::mktemp_dir)
# Usage: tmpdir=$(compat::mktemp_dir "prefix")
compat::mktemp_dir() {
    local prefix="${1:-tmp}"
    
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        mktemp -d -t "${prefix}"
    else
        mktemp -d --tmpdir "${prefix}.XXXXXXXXXX"
    fi
}

# =============================================================================
# TAR WRAPPERS
# =============================================================================
# BSD tar and GNU tar have some option differences
# =============================================================================

# Extract tar archive with auto-detection
# Usage: compat::tar_extract archive.tar.gz [destination]
compat::tar_extract() {
    local archive="$1"
    local dest="${2:-.}"
    
    # Auto-detect compression
    case "$archive" in
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$dest"
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "$archive" -C "$dest"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$archive" -C "$dest"
            ;;
        *.tar)
            tar -xf "$archive" -C "$dest"
            ;;
        *)
            # Try auto-detection
            tar -xaf "$archive" -C "$dest" 2>/dev/null || \
            tar -xf "$archive" -C "$dest"
            ;;
    esac
}

# Create tar archive
# Usage: compat::tar_create archive.tar.gz file1 file2...
compat::tar_create() {
    local archive="$1"
    shift
    
    case "$archive" in
        *.tar.gz|*.tgz)
            tar -czf "$archive" "$@"
            ;;
        *.tar.bz2|*.tbz2)
            tar -cjf "$archive" "$@"
            ;;
        *.tar.xz|*.txz)
            tar -cJf "$archive" "$@"
            ;;
        *.tar)
            tar -cf "$archive" "$@"
            ;;
        *)
            tar -czf "$archive" "$@"
            ;;
    esac
}

# =============================================================================
# FIND WRAPPERS
# =============================================================================
# GNU find has more options than BSD find
# =============================================================================

# Find files modified within N days
# Usage: compat::find_modified_days /path 7
compat::find_modified_days() {
    local path="$1"
    local days="$2"
    find "$path" -type f -mtime -"$days"
}

# Find files by extension
# Usage: compat::find_by_ext /path "sh"
compat::find_by_ext() {
    local path="$1"
    local ext="$2"
    find "$path" -type f -name "*.$ext"
}

# =============================================================================
# XARGS WRAPPERS
# =============================================================================
# BSD xargs doesn't support -d, GNU xargs doesn't support -0 in all cases
# =============================================================================

# xargs with null delimiter (for files with spaces)
# Usage: find . -print0 | compat::xargs_null command
compat::xargs_null() {
    xargs -0 "$@"
}

# xargs that handles empty input gracefully
# Usage: echo "" | compat::xargs_safe command
compat::xargs_safe() {
    _compat_detect_os
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        xargs "$@"  # BSD xargs doesn't run on empty input by default
    else
        xargs -r "$@"  # GNU: -r means don't run if empty
    fi
}

# =============================================================================
# BASE64 WRAPPERS
# =============================================================================
# BSD base64 uses -D for decode, GNU uses -d
# =============================================================================

# Encode to base64
# Usage: echo "text" | compat::base64_encode
# Usage: compat::base64_encode "text"
compat::base64_encode() {
    if [[ $# -gt 0 ]]; then
        printf '%s' "$1" | base64
    else
        base64
    fi
}

# Decode from base64
# Usage: echo "dGV4dA==" | compat::base64_decode
# Usage: compat::base64_decode "dGV4dA=="
compat::base64_decode() {
    _compat_detect_os
    
    local input=""
    if [[ $# -gt 0 ]]; then
        input="$1"
    else
        input=$(cat)
    fi
    
    if [[ "$_COMPAT_OS_FAMILY" == "bsd" ]]; then
        printf '%s' "$input" | base64 -D
    else
        printf '%s' "$input" | base64 -d
    fi
}

# =============================================================================
# CHECKSUM WRAPPERS
# =============================================================================
# macOS uses shasum, Linux typically has sha256sum etc.
# =============================================================================

# Calculate SHA256 hash
# Usage: hash=$(compat::sha256 file)
# Usage: echo "text" | compat::sha256
compat::sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$@" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$@" | cut -d' ' -f1
    else
        openssl dgst -sha256 "$@" | awk '{print $NF}'
    fi
}

# Calculate MD5 hash (for compatibility checks, not security)
# Usage: hash=$(compat::md5 file)
compat::md5() {
    if command -v md5sum &>/dev/null; then
        md5sum "$@" | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        md5 -q "$@"
    else
        openssl dgst -md5 "$@" | awk '{print $NF}'
    fi
}

# =============================================================================
# CLIPBOARD WRAPPERS
# =============================================================================
# macOS uses pbcopy/pbpaste, Linux uses xclip/xsel, WSL uses Windows clipboard
# =============================================================================

# Copy to clipboard
# Usage: echo "text" | compat::clipboard_copy
# Usage: compat::clipboard_copy "text"
compat::clipboard_copy() {
    local text="${1:-$(cat)}"

    _compat_detect_os

    case "$_COMPAT_OS" in
        macos)
            printf '%s' "$text" | pbcopy
            ;;
        wsl)
            # WSL: Use Windows clip.exe
            if command -v clip.exe &>/dev/null; then
                printf '%s' "$text" | clip.exe
            else
                return 1
            fi
            ;;
        linux)
            if command -v xclip &>/dev/null; then
                printf '%s' "$text" | xclip -selection clipboard
            elif command -v xsel &>/dev/null; then
                printf '%s' "$text" | xsel --clipboard --input
            elif command -v wl-copy &>/dev/null; then
                printf '%s' "$text" | wl-copy
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Paste from clipboard
# Usage: text=$(compat::clipboard_paste)
compat::clipboard_paste() {
    _compat_detect_os

    case "$_COMPAT_OS" in
        macos)
            pbpaste
            ;;
        wsl)
            # WSL: Use PowerShell to get clipboard content
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -NoProfile -Command "Get-Clipboard" 2>/dev/null | tr -d '\r'
            else
                return 1
            fi
            ;;
        linux)
            if command -v xclip &>/dev/null; then
                xclip -selection clipboard -o
            elif command -v xsel &>/dev/null; then
                xsel --clipboard --output
            elif command -v wl-paste &>/dev/null; then
                wl-paste
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# OPEN/BROWSE WRAPPERS
# =============================================================================
# macOS uses 'open', Linux uses 'xdg-open', WSL uses Windows explorer
# =============================================================================

# Open file/URL with default application
# Usage: compat::open "https://example.com"
# Usage: compat::open document.pdf
compat::open() {
    local target="$1"

    _compat_detect_os

    case "$_COMPAT_OS" in
        macos)
            open "$target"
            ;;
        wsl)
            # WSL: Use Windows explorer.exe or cmd.exe /c start
            if command -v explorer.exe &>/dev/null; then
                # Convert path if it's a local file
                if [[ -e "$target" ]]; then
                    target="$(compat::wsl_to_windows "$target")"
                fi
                explorer.exe "$target" 2>/dev/null || cmd.exe /c start "" "$target" 2>/dev/null
            elif command -v cmd.exe &>/dev/null; then
                cmd.exe /c start "" "$target" 2>/dev/null
            else
                return 1
            fi
            ;;
        linux)
            if command -v xdg-open &>/dev/null; then
                xdg-open "$target"
            elif command -v gnome-open &>/dev/null; then
                gnome-open "$target"
            else
                return 1
            fi
            ;;
        windows)
            start "$target"
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print OS compatibility info
# Usage: compat::info
compat::info() {
    _compat_detect_os

    printf 'OS: %s\n' "$_COMPAT_OS"
    printf 'Family: %s\n' "$_COMPAT_OS_FAMILY"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'Arch: %s\n' "$(uname -m)"
    printf 'Bash: %s\n' "${BASH_VERSION:-unknown}"

    # Environment detection
    printf '\nEnvironment:\n'
    compat::is_wsl && printf '  WSL: yes\n' || printf '  WSL: no\n'
    compat::is_alpine && printf '  Alpine: yes\n' || printf '  Alpine: no\n'
    compat::is_busybox && printf '  BusyBox: yes\n' || printf '  BusyBox: no\n'

    # Feature flags
    printf '\nBash features:\n'
    printf '  Associative arrays (4.0+): %s\n' "$([[ $BASH_HAS_ASSOC_ARRAYS -eq 1 ]] && echo yes || echo no)"
    printf '  Namerefs (4.3+): %s\n' "$([[ $BASH_HAS_NAMEREFS -eq 1 ]] && echo yes || echo no)"
    printf '  Negative indices (4.3+): %s\n' "$([[ $BASH_HAS_NEGATIVE_INDICES -eq 1 ]] && echo yes || echo no)"
    printf '  EPOCHREALTIME (5.0+): %s\n' "$([[ $BASH_HAS_EPOCHREALTIME -eq 1 ]] && echo yes || echo no)"
    printf '  Current shell subst (5.3+): %s\n' "$([[ $BASH_HAS_CURRENTSHELL_SUBST -eq 1 ]] && echo yes || echo no)"

    # Check for key tools
    printf '\nTool availability:\n'
    command -v gsed &>/dev/null && printf '  gsed: available (GNU sed)\n' || printf '  gsed: not found\n'
    command -v ggrep &>/dev/null && printf '  ggrep: available (GNU grep)\n' || printf '  ggrep: not found\n'
    command -v gdate &>/dev/null && printf '  gdate: available (GNU date)\n' || printf '  gdate: not found\n'
    command -v gstat &>/dev/null && printf '  gstat: available (GNU stat)\n' || printf '  gstat: not found\n'
    compat::has_grep_perl && printf '  grep -P: supported\n' || printf '  grep -P: not supported\n'
}

# Run command with GNU version if available (on macOS with homebrew)
# Usage: compat::gnu_prefer sed -i '' 's/old/new/' file
# This will use gsed if available, otherwise falls back to sed
compat::gnu_prefer() {
    local cmd="$1"
    shift
    
    if command -v "g$cmd" &>/dev/null; then
        "g$cmd" "$@"
    else
        "$cmd" "$@"
    fi
}

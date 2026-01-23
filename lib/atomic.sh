#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/atomic.sh - Atomic File Operations with Recovery
# =============================================================================
# Description: File write operations that prevent partial state through
#              temp-file-then-rename patterns, flock for concurrent access,
#              and checkpoint/rollback mechanisms for safe recovery.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ATOMIC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ATOMIC_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Directory for checkpoint storage
MAINFRAME_CHECKPOINT_DIR="${MAINFRAME_CHECKPOINT_DIR:-${TMPDIR:-/tmp}/mainframe_checkpoints}"

# Trash directory for safe_remove
MAINFRAME_TRASH_DIR="${MAINFRAME_TRASH_DIR:-${TMPDIR:-/tmp}/mainframe_trash}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_atomic_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[atomic] %s: %s\n' "${level}" "$*" >&2
    fi
}

# Generate a unique temporary filename in the same directory as target
# This ensures rename is atomic (same filesystem)
_atomic_tmpfile() {
    local target="$1"
    local dir
    dir="${target%/*}"
    [[ "$dir" == "$target" ]] && dir="."
    printf '%s/.mainframe_atomic_%s_%s' "$dir" "$$" "$RANDOM"
}

# Generate checkpoint ID from filename
_checkpoint_id() {
    local file="$1"
    local name="${file##*/}"
    name="${name//\//_}"
    printf '%s' "$name"
}

# =============================================================================
# ATOMIC WRITE OPERATIONS
# =============================================================================

# @pre: parent directory exists and is writable
# @post: file contains exactly the given content, or unchanged on failure
# @idempotent: yes - overwrites with same content is safe
# @atomic: yes - uses write-to-temp + rename (single syscall)
# @returns: 0 on success, 1 on failure (original file unchanged)
#
# Write content to a file atomically. Writes to a temporary file first,
# then renames it to the target. The rename is atomic on POSIX filesystems,
# preventing any reader from seeing partial content.
#
# Usage: atomic_write "/path/to/file" "content" [mode]
# Example: atomic_write "/etc/myapp.conf" "$config_content" "0644"
atomic_write() {
    local target="$1"
    local content="$2"
    local mode="${3:-}"

    if [[ -z "$target" ]]; then
        _atomic_log error "atomic_write: target path required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${target%/*}"
    if [[ "$parent_dir" != "$target" ]] && [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    # Write to temp file in same directory (same filesystem = atomic rename)
    local tmpfile
    tmpfile=$(_atomic_tmpfile "$target")

    # Write content to temp file
    if ! printf '%s' "$content" > "$tmpfile"; then
        rm -f "$tmpfile" 2>/dev/null
        _atomic_log error "atomic_write: failed to write temp file"
        return 1
    fi

    # Set permissions before rename if specified
    if [[ -n "$mode" ]]; then
        chmod "$mode" "$tmpfile" || {
            rm -f "$tmpfile" 2>/dev/null
            return 1
        }
    elif [[ -f "$target" ]]; then
        # Preserve existing file permissions
        if [[ "$OSTYPE" == darwin* ]]; then
            chmod "$(stat -f '%Lp' "$target")" "$tmpfile" 2>/dev/null
        else
            chmod --reference="$target" "$tmpfile" 2>/dev/null
        fi
    fi

    # Atomic rename
    if ! mv -f "$tmpfile" "$target"; then
        rm -f "$tmpfile" 2>/dev/null
        _atomic_log error "atomic_write: rename failed for $target"
        return 1
    fi

    _atomic_log debug "atomic_write: wrote $target"
    return 0
}

# @pre: parent directory exists and is writable
# @post: content appended to file, concurrent-safe via flock
# @idempotent: no - appends each time called
# @atomic: yes - flock prevents interleaved writes from concurrent processes
# @returns: 0 on success, 1 on failure
#
# Append content to a file with file locking for concurrent safety.
# Uses flock to prevent interleaved writes from multiple processes.
#
# Usage: atomic_append "/path/to/file" "content"
# Example: atomic_append "/var/log/myapp.log" "[$(date)] Event occurred"
atomic_append() {
    local target="$1"
    local content="$2"

    if [[ -z "$target" ]] || [[ -z "$content" ]]; then
        _atomic_log error "atomic_append: target and content required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${target%/*}"
    if [[ "$parent_dir" != "$target" ]] && [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    # Use flock if available for concurrent safety
    if command -v flock &>/dev/null; then
        (
            flock -x 200
            printf '%s\n' "$content" >> "$target"
        ) 200>"${target}.lock"
        local rc=$?
        rm -f "${target}.lock" 2>/dev/null
        return $rc
    else
        # Fallback: no locking (still works, just not concurrent-safe)
        printf '%s\n' "$content" >> "$target"
    fi
}

# @pre: target file exists
# @post: file replaced with new content, backup available for rollback
# @idempotent: no - creates new backup each time
# @atomic: yes - write-to-temp + backup + rename
# @returns: 0 on success, 1 on failure (original unchanged)
#
# Replace file content with automatic backup for rollback.
# Creates a timestamped backup, writes new content atomically,
# and verifies the write succeeded before completing.
#
# Usage: atomic_replace "/path/to/file" "new content" [verify_cmd]
# Example: atomic_replace "/etc/nginx.conf" "$new_config" "nginx -t"
atomic_replace() {
    local target="$1"
    local content="$2"
    local verify_cmd="${3:-}"

    if [[ -z "$target" ]]; then
        _atomic_log error "atomic_replace: target path required"
        return 1
    fi

    # Create backup if file exists
    local backup=""
    if [[ -f "$target" ]]; then
        backup="${target}.bak.$(date +%s)"
        cp -p "$target" "$backup" || {
            _atomic_log error "atomic_replace: backup failed"
            return 1
        }
    fi

    # Write atomically
    if ! atomic_write "$target" "$content"; then
        # Restore from backup if write failed
        if [[ -n "$backup" ]] && [[ -f "$backup" ]]; then
            mv -f "$backup" "$target" 2>/dev/null
        fi
        return 1
    fi

    # Run verification command if provided
    if [[ -n "$verify_cmd" ]]; then
        if ! eval "$verify_cmd" &>/dev/null; then
            _atomic_log error "atomic_replace: verification failed, rolling back"
            if [[ -n "$backup" ]] && [[ -f "$backup" ]]; then
                mv -f "$backup" "$target"
            fi
            return 1
        fi
    fi

    _atomic_log debug "atomic_replace: replaced $target (backup: $backup)"
    return 0
}

# =============================================================================
# SAFE REMOVAL
# =============================================================================

# @pre: path exists
# @post: path moved to trash (recoverable), not permanently deleted
# @idempotent: yes - no-op if path doesn't exist
# @atomic: yes - single rename operation
# @returns: 0 on success, 1 on failure
#
# Move file/directory to trash instead of permanent deletion.
# Files can be recovered with safe_restore.
#
# Usage: safe_remove "/path/to/file"
# Example: safe_remove "/etc/old-config.conf"
safe_remove() {
    local path="$1"

    if [[ -z "$path" ]]; then
        _atomic_log error "safe_remove: path required"
        return 1
    fi

    # Nothing to remove
    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        return 0
    fi

    # Ensure trash directory exists
    mkdir -p "$MAINFRAME_TRASH_DIR" || return 1

    # Generate trash filename with timestamp and original path info
    local basename
    basename="${path##*/}"
    local trash_name
    trash_name="${basename}.$(date +%s).$$"
    local trash_path="${MAINFRAME_TRASH_DIR}/${trash_name}"

    # Store original path for restore
    printf '%s\n' "$path" > "${trash_path}.origin" || return 1

    # Move to trash
    if ! mv -f "$path" "$trash_path"; then
        rm -f "${trash_path}.origin" 2>/dev/null
        _atomic_log error "safe_remove: failed to move $path to trash"
        return 1
    fi

    _atomic_log debug "safe_remove: $path -> $trash_path"
    return 0
}

# @pre: trashed file exists
# @post: file restored to original location
# @returns: 0 on success, 1 on failure
#
# Restore the most recently trashed file with the given name.
#
# Usage: safe_restore "filename"
# Example: safe_restore "old-config.conf"
safe_restore() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _atomic_log error "safe_restore: filename required"
        return 1
    fi

    # Find most recent trash entry matching name
    local latest=""
    local latest_time=0
    local entry

    for entry in "${MAINFRAME_TRASH_DIR}/${name}."*; do
        [[ -f "$entry" ]] || continue
        [[ "$entry" == *.origin ]] && continue
        local etime
        etime="${entry##*.}"
        etime="${etime%%.*}"
        if [[ "$etime" =~ ^[0-9]+$ ]] && (( etime > latest_time )); then
            latest_time=$etime
            latest="$entry"
        fi
    done

    if [[ -z "$latest" ]]; then
        _atomic_log error "safe_restore: no trashed file found for $name"
        return 1
    fi

    # Read original path
    local origin_file="${latest}.origin"
    if [[ ! -f "$origin_file" ]]; then
        _atomic_log error "safe_restore: origin info missing for $latest"
        return 1
    fi

    local original_path
    original_path=$(<"$origin_file")

    # Restore
    mv -f "$latest" "$original_path" || return 1
    rm -f "$origin_file" 2>/dev/null

    _atomic_log debug "safe_restore: restored $name to $original_path"
    return 0
}

# =============================================================================
# CHECKPOINT / ROLLBACK
# =============================================================================

# @pre: file exists
# @post: checkpoint copy saved with given name
# @idempotent: yes - overwrites checkpoint with same name
# @returns: 0 on success, 1 on failure
#
# Create a named checkpoint (snapshot) of a file for later rollback.
# Multiple checkpoints can coexist with different names.
#
# Usage: file_checkpoint "/path/to/file" "checkpoint_name"
# Example: file_checkpoint "/etc/nginx.conf" "before-ssl-update"
file_checkpoint() {
    local file="$1"
    local name="${2:-default}"

    if [[ -z "$file" ]]; then
        _atomic_log error "file_checkpoint: file path required"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _atomic_log error "file_checkpoint: file does not exist: $file"
        return 1
    fi

    # Create checkpoint directory
    mkdir -p "$MAINFRAME_CHECKPOINT_DIR" || return 1

    # Generate checkpoint filename
    local file_id
    file_id=$(_checkpoint_id "$file")
    local checkpoint_path="${MAINFRAME_CHECKPOINT_DIR}/${file_id}__${name}"

    # Store the checkpoint with metadata
    cp -p "$file" "$checkpoint_path" || return 1
    printf '%s\n' "$file" > "${checkpoint_path}.meta" || return 1

    _atomic_log debug "file_checkpoint: saved $file as checkpoint '$name'"
    return 0
}

# @pre: checkpoint exists for given file and name
# @post: file restored to checkpoint state
# @atomic: yes - uses atomic_write for the restore
# @returns: 0 on success, 1 on failure
#
# Restore a file from a named checkpoint.
#
# Usage: file_rollback "/path/to/file" "checkpoint_name"
# Example: file_rollback "/etc/nginx.conf" "before-ssl-update"
file_rollback() {
    local file="$1"
    local name="${2:-default}"

    if [[ -z "$file" ]]; then
        _atomic_log error "file_rollback: file path required"
        return 1
    fi

    # Find checkpoint
    local file_id
    file_id=$(_checkpoint_id "$file")
    local checkpoint_path="${MAINFRAME_CHECKPOINT_DIR}/${file_id}__${name}"

    if [[ ! -f "$checkpoint_path" ]]; then
        _atomic_log error "file_rollback: no checkpoint '$name' for $file"
        return 1
    fi

    # Restore using atomic write
    local content
    content=$(<"$checkpoint_path")
    atomic_write "$file" "$content" || return 1

    _atomic_log debug "file_rollback: restored $file from checkpoint '$name'"
    return 0
}

# @pre: none
# @post: lists available checkpoints
# @returns: 0
#
# List all checkpoints, optionally filtered by file path.
#
# Usage: file_checkpoints ["/path/to/file"]
file_checkpoints() {
    local filter_file="${1:-}"

    if [[ ! -d "$MAINFRAME_CHECKPOINT_DIR" ]]; then
        return 0
    fi

    local entry
    for entry in "${MAINFRAME_CHECKPOINT_DIR}"/*.meta; do
        [[ -f "$entry" ]] || continue
        local original_file
        original_file=$(<"$entry")
        if [[ -z "$filter_file" ]] || [[ "$original_file" == "$filter_file" ]]; then
            local base="${entry%.meta}"
            local name="${base##*__}"
            local checkpoint_file="${base}"
            if [[ -f "$checkpoint_file" ]]; then
                local size
                if [[ "$OSTYPE" == darwin* ]]; then
                    size=$(stat -f%z "$checkpoint_file" 2>/dev/null || echo "?")
                else
                    size=$(stat -c%s "$checkpoint_file" 2>/dev/null || echo "?")
                fi
                printf '%s\t%s\t%s bytes\n' "$name" "$original_file" "$size"
            fi
        fi
    done
}

# @pre: none
# @post: old checkpoints removed
# @returns: 0
#
# Clean up checkpoints older than N seconds (default: 86400 = 24h).
#
# Usage: file_checkpoint_cleanup [max_age_seconds]
# Example: file_checkpoint_cleanup 3600  # Remove checkpoints older than 1h
file_checkpoint_cleanup() {
    local max_age="${1:-86400}"
    local now
    now=$(date +%s)

    if [[ ! -d "$MAINFRAME_CHECKPOINT_DIR" ]]; then
        return 0
    fi

    local entry
    local removed=0
    for entry in "${MAINFRAME_CHECKPOINT_DIR}"/*; do
        [[ -f "$entry" ]] || continue
        [[ "$entry" == *.meta ]] && continue

        local file_time
        if [[ "$OSTYPE" == darwin* ]]; then
            file_time=$(stat -f%m "$entry" 2>/dev/null || echo "0")
        else
            file_time=$(stat -c%Y "$entry" 2>/dev/null || echo "0")
        fi

        if (( now - file_time > max_age )); then
            rm -f "$entry" "${entry}.meta" 2>/dev/null
            removed=$((removed + 1))
        fi
    done

    if (( removed > 0 )); then
        _atomic_log debug "file_checkpoint_cleanup: removed $removed old checkpoints"
    fi
    return 0
}

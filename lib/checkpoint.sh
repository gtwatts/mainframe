#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/checkpoint.sh - Multi-File Checkpoint & Rollback System
# =============================================================================
# Description: Transaction-like checkpoint/rollback for multi-file atomic
#              operations with tar archives, JSON metadata, and SHA-256
#              integrity verification. Designed for AI agent recovery scenarios.
# Version: 1.0.0
# Requires: Bash 4.0+, tar, sha256sum/shasum/openssl
# Dependencies: lib/atomic.sh, lib/crypto.sh, lib/datetime.sh
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CHECKPOINT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CHECKPOINT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default checkpoint storage directory
MAINFRAME_CHECKPOINT_DIR="${MAINFRAME_CHECKPOINT_DIR:-${HOME}/.mainframe/checkpoints}"

# Maximum checkpoint size in MB (default: 100MB)
MAINFRAME_CHECKPOINT_MAX_SIZE_MB="${MAINFRAME_CHECKPOINT_MAX_SIZE_MB:-100}"

# Maximum number of checkpoints to retain
MAINFRAME_CHECKPOINT_MAX_COUNT="${MAINFRAME_CHECKPOINT_MAX_COUNT:-50}"

# Maximum age in seconds (default: 7 days)
MAINFRAME_CHECKPOINT_MAX_AGE="${MAINFRAME_CHECKPOINT_MAX_AGE:-604800}"

# Lock timeout in seconds
MAINFRAME_CHECKPOINT_LOCK_TIMEOUT="${MAINFRAME_CHECKPOINT_LOCK_TIMEOUT:-30}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Auto-checkpoint tracking (for auto_start/commit/abort pattern)
declare -gA _CHECKPOINT_AUTO_IDS       # [scope_name] -> checkpoint_id
declare -gA _CHECKPOINT_AUTO_FILES     # [scope_name] -> space-separated file list

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_checkpoint_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[checkpoint] %s: %s\n' "$level" "$*" >&2
    fi
}

# Generate unique checkpoint ID
_checkpoint_gen_id() {
    local prefix="${1:-chk}"
    local timestamp
    timestamp=$(date +%s)
    local rand
    rand=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 12)
    printf '%s_%s_%s' "$prefix" "$timestamp" "$rand"
}

# Validate checkpoint name (alphanumeric, dash, underscore only)
# Security: Prevents path traversal attacks
_checkpoint_validate_name() {
    local name="$1"

    # Reject empty
    [[ -z "$name" ]] && return 1

    # Reject path traversal attempts
    [[ "$name" == *".."* ]] && return 1
    [[ "$name" == *"/"* ]] && return 1
    [[ "$name" == *"\\"* ]] && return 1
    # Note: Bash cannot properly handle null bytes in strings.
    # Names containing null bytes are rejected by the regex check below.

    # Allow only safe characters
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1

    # Length limit (max 64 chars)
    [[ ${#name} -le 64 ]] || return 1

    return 0
}

# Validate path is safe (not a symlink escaping base, no traversal)
# Security: Prevents symlink attacks and path traversal
_checkpoint_validate_path() {
    local path="$1"
    local base="${2:-}"

    # Must be non-empty
    [[ -z "$path" ]] && return 1

    # Check for null bytes
    [[ "$path" == *$'\0'* ]] && return 1

    # If base is provided, verify path stays within it
    if [[ -n "$base" ]]; then
        local resolved
        resolved=$(realpath -m "$path" 2>/dev/null) || return 1
        local base_resolved
        base_resolved=$(realpath -m "$base" 2>/dev/null) || return 1

        [[ "$resolved" == "$base_resolved"* ]] || return 1
    fi

    return 0
}

# Check if path is a symlink pointing outside allowed boundary
_checkpoint_is_symlink_escape() {
    local path="$1"
    local allowed_base="$2"

    [[ ! -L "$path" ]] && return 1  # Not a symlink

    local target
    target=$(readlink -f "$path" 2>/dev/null) || return 0

    # If symlink target is outside allowed base, it's an escape
    [[ "$target" != "$allowed_base"* ]]
}

# Calculate total size of files in bytes
_checkpoint_calc_size() {
    local -a files=("$@")
    local total=0
    local file

    for file in "${files[@]}"; do
        local size
        size=$(_checkpoint_size_bytes "$file")
        total=$((total + size))
    done

    printf '%d' "$total"
}

# Get SHA-256 hash of a file
_checkpoint_hash_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf ''
        return 1
    fi

    if type -p sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        _checkpoint_log error "No SHA-256 tool available"
        return 1
    fi
}

# Resolve an existing path to an absolute canonical location without relying
# on GNU-only realpath flags.
_checkpoint_resolve_existing_path() {
    local path="$1"
    [[ -e "$path" ]] || return 1

    local dir
    dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s' "$dir" "$(basename "$path")"
}

# Return file or directory size in bytes with BSD/GNU compatible tools.
_checkpoint_size_bytes() {
    local path="$1"
    local size=""

    if [[ -f "$path" ]]; then
        if [[ "$OSTYPE" == darwin* ]]; then
            size=$(stat -f%z "$path" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$path" 2>/dev/null || echo 0)
        fi
        printf '%s' "$size"
        return 0
    fi

    if [[ -d "$path" ]]; then
        size=$(du -sb "$path" 2>/dev/null | cut -f1)
        if [[ -z "$size" ]]; then
            size=$(du -sk "$path" 2>/dev/null | cut -f1)
            if [[ -n "$size" ]]; then
                size=$((size * 1024))
            else
                size=0
            fi
        fi
        printf '%s' "$size"
        return 0
    fi

    printf '0'
}

_checkpoint_tar_create() {
    local archive_path="$1"
    shift
    tar -czf "$archive_path" -P "$@" 2>/dev/null
}

_checkpoint_tar_extract() {
    local archive_path="$1"
    tar -xzf "$archive_path" -P -C / 2>/dev/null
}

# JSON escape helper
# Delegates to canonical json_escape when available, with a local fallback so
# this library also works when sourced standalone.
_checkpoint_json_escape() {
    if declare -F json_escape &>/dev/null; then
        json_escape "$@"
        return 0
    fi

    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

# Ensure checkpoint directory exists with proper permissions
_checkpoint_ensure_dir() {
    if [[ ! -d "$MAINFRAME_CHECKPOINT_DIR" ]]; then
        mkdir -p "$MAINFRAME_CHECKPOINT_DIR" || return 1
        chmod 700 "$MAINFRAME_CHECKPOINT_DIR" || return 1
    fi

    # Verify it's not a symlink (security)
    if [[ -L "$MAINFRAME_CHECKPOINT_DIR" ]]; then
        _checkpoint_log error "Checkpoint directory is a symlink - security risk"
        return 1
    fi

    return 0
}

# Acquire lock for checkpoint operations
_checkpoint_lock() {
    local lockfile="${MAINFRAME_CHECKPOINT_DIR}/.lock"

    _checkpoint_ensure_dir || return 1

    if command -v flock &>/dev/null; then
        exec 200>"$lockfile"
        flock -x -w "$MAINFRAME_CHECKPOINT_LOCK_TIMEOUT" 200 || {
            _checkpoint_log error "Could not acquire checkpoint lock within ${MAINFRAME_CHECKPOINT_LOCK_TIMEOUT}s"
            return 1
        }
    fi
    return 0
}

# Release lock
_checkpoint_unlock() {
    if command -v flock &>/dev/null; then
        exec 200>&- 2>/dev/null || true
    fi
}

# =============================================================================
# PUBLIC API
# =============================================================================

# checkpoint_create - Create named checkpoint with files/dirs
# @description Create a new checkpoint containing snapshots of specified files/directories
# @pre        Files/directories exist
# @post       Checkpoint tar archive and metadata created
# @idempotent No - creates new checkpoint each time
# @param      $1 name - Human-readable checkpoint name (alphanumeric, dash, underscore)
# @param      $@ files/dirs - Paths to include in checkpoint
# @stdout     Checkpoint ID on success
# @stderr     JSON error on failure
# @return     0 on success, 1 on invalid name, 2 on size limit exceeded, 3 on archive failure
#
# Usage: checkpoint_id=$(checkpoint_create "pre-deploy" /etc/nginx/nginx.conf /var/www/html)
# Usage: checkpoint_id=$(checkpoint_create "config-backup" /app/config/)
checkpoint_create() {
    local name="$1"
    shift
    local -a paths=("$@")

    # Validate name
    if ! _checkpoint_validate_name "$name"; then
        printf '{"error":"invalid checkpoint name","allowed":"alphanumeric, dash, underscore, max 64 chars"}\n' >&2
        return 1
    fi

    # Validate at least one path provided
    if [[ ${#paths[@]} -eq 0 ]]; then
        printf '{"error":"no files or directories specified"}\n' >&2
        return 1
    fi

    # Validate and resolve all paths
    local -a resolved_paths=()
    local path
    for path in "${paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            printf '{"error":"path not found","path":"%s"}\n' "$(_checkpoint_json_escape "$path")" >&2
            return 1
        fi

        # Resolve to absolute path
        local abs_path
        abs_path=$(_checkpoint_resolve_existing_path "$path") || {
            printf '{"error":"cannot resolve path","path":"%s"}\n' "$(_checkpoint_json_escape "$path")" >&2
            return 1
        }

        resolved_paths+=("$abs_path")
    done

    # Calculate total size
    local total_size
    total_size=$(_checkpoint_calc_size "${resolved_paths[@]}")
    local max_size_bytes=$((MAINFRAME_CHECKPOINT_MAX_SIZE_MB * 1024 * 1024))

    if ((total_size > max_size_bytes)); then
        printf '{"error":"size limit exceeded","size_bytes":%d,"max_bytes":%d}\n' "$total_size" "$max_size_bytes" >&2
        return 2
    fi

    # Acquire lock
    _checkpoint_lock || return 3

    # Generate checkpoint ID
    local checkpoint_id
    checkpoint_id=$(_checkpoint_gen_id "$name")
    local checkpoint_dir="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}"

    # Create checkpoint directory
    mkdir -p "$checkpoint_dir" || {
        _checkpoint_unlock
        printf '{"error":"cannot create checkpoint directory"}\n' >&2
        return 3
    }
    chmod 700 "$checkpoint_dir"

    # Create tar archive
    local archive_path="${checkpoint_dir}/data.tar.gz"
    local tmparchive="${archive_path}.tmp.$$"

    # Use tar with absolute paths preserved
    if ! _checkpoint_tar_create "$tmparchive" "${resolved_paths[@]}"; then
        rm -f "$tmparchive" 2>/dev/null
        rm -rf "$checkpoint_dir" 2>/dev/null
        _checkpoint_unlock
        printf '{"error":"tar archive creation failed"}\n' >&2
        return 3
    fi

    # Atomic rename
    mv -f "$tmparchive" "$archive_path" || {
        rm -f "$tmparchive" 2>/dev/null
        rm -rf "$checkpoint_dir" 2>/dev/null
        _checkpoint_unlock
        printf '{"error":"archive rename failed"}\n' >&2
        return 3
    }

    # Calculate archive hash
    local archive_hash
    archive_hash=$(_checkpoint_hash_file "$archive_path")

    # Get archive size
    local archive_size
    if [[ "$OSTYPE" == darwin* ]]; then
        archive_size=$(stat -f%z "$archive_path" 2>/dev/null || echo 0)
    else
        archive_size=$(stat -c%s "$archive_path" 2>/dev/null || echo 0)
    fi

    # Build file list for metadata
    local files_json="["
    local first=true
    for path in "${resolved_paths[@]}"; do
        $first || files_json+=","
        first=false
        files_json+="\"$(_checkpoint_json_escape "$path")\""
    done
    files_json+="]"

    # Create metadata JSON
    local timestamp
    timestamp=$(date +%s)
    local iso_timestamp
    iso_timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    local metadata_path="${checkpoint_dir}/metadata.json"
    local metadata_content
    metadata_content=$(cat <<EOF
{
  "checkpoint_id": "$checkpoint_id",
  "name": "$(_checkpoint_json_escape "$name")",
  "created_at": "$iso_timestamp",
  "created_epoch": $timestamp,
  "files": $files_json,
  "file_count": ${#resolved_paths[@]},
  "original_size_bytes": $total_size,
  "archive_size_bytes": $archive_size,
  "archive_hash": "$archive_hash",
  "status": "active",
  "version": "1.0"
}
EOF
)

    # Write metadata atomically
    local tmp_metadata="${metadata_path}.tmp.$$"
    printf '%s\n' "$metadata_content" > "$tmp_metadata" || {
        rm -f "$tmp_metadata" 2>/dev/null
        rm -rf "$checkpoint_dir" 2>/dev/null
        _checkpoint_unlock
        printf '{"error":"metadata write failed"}\n' >&2
        return 3
    }
    mv -f "$tmp_metadata" "$metadata_path"

    # Enforce quotas (cleanup old checkpoints if needed)
    _checkpoint_enforce_quotas &>/dev/null || true

    _checkpoint_unlock

    _checkpoint_log debug "Created checkpoint: $checkpoint_id (name=$name, files=${#resolved_paths[@]}, size=$archive_size)"
    printf '%s' "$checkpoint_id"
    return 0
}

# checkpoint_rollback - Restore from checkpoint (atomic)
# @description Restore all files from a checkpoint to their original locations
# @pre        Checkpoint exists and is valid
# @post       All files restored to original paths, checkpoint marked as used
# @idempotent Yes - can rollback multiple times
# @param      $1 checkpoint_id - Checkpoint ID from checkpoint_create
# @param      --force - Force rollback even if integrity check fails
# @param      --dry-run - Show what would be restored without actually restoring
# @stdout     JSON summary of restored files
# @stderr     JSON error on failure
# @return     0 on success, 1 if checkpoint not found, 2 if integrity check failed
#
# Usage: checkpoint_rollback "chk_1234567890_abc123"
# Usage: checkpoint_rollback "chk_1234567890_abc123" --dry-run
checkpoint_rollback() {
    local checkpoint_id="$1"
    shift
    local force=0
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    # Validate checkpoint ID
    if ! _checkpoint_validate_name "$checkpoint_id"; then
        printf '{"error":"invalid checkpoint ID"}\n' >&2
        return 1
    fi

    local checkpoint_dir="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}"
    local metadata_path="${checkpoint_dir}/metadata.json"
    local archive_path="${checkpoint_dir}/data.tar.gz"

    # Check checkpoint exists
    if [[ ! -d "$checkpoint_dir" ]] || [[ ! -f "$metadata_path" ]] || [[ ! -f "$archive_path" ]]; then
        printf '{"error":"checkpoint not found","checkpoint_id":"%s"}\n' "$checkpoint_id" >&2
        return 1
    fi

    # Verify archive integrity
    local stored_hash
    stored_hash=$(grep -o '"archive_hash"[[:space:]]*:[[:space:]]*"[^"]*"' "$metadata_path" | sed 's/.*"\([^"]*\)"$/\1/')
    local actual_hash
    actual_hash=$(_checkpoint_hash_file "$archive_path")

    if [[ "$stored_hash" != "$actual_hash" ]]; then
        if [[ $force -eq 0 ]]; then
            printf '{"error":"integrity check failed","expected":"%s","actual":"%s"}\n' "$stored_hash" "$actual_hash" >&2
            return 2
        else
            _checkpoint_log warn "Integrity check failed but --force specified, proceeding"
        fi
    fi

    # Dry run - just show what would be restored
    if [[ $dry_run -eq 1 ]]; then
        local files_list
        files_list=$(tar -tzf "$archive_path" 2>/dev/null | head -100)
        local file_count
        file_count=$(tar -tzf "$archive_path" 2>/dev/null | wc -l)
        printf '{"dry_run":true,"checkpoint_id":"%s","file_count":%d,"sample_files":[' "$checkpoint_id" "$file_count"
        local first=true
        while IFS= read -r file; do
            $first || printf ','
            first=false
            printf '"%s"' "$(_checkpoint_json_escape "$file")"
        done <<< "$(echo "$files_list" | head -10)"
        printf ']}\n'
        return 0
    fi

    # Acquire lock
    _checkpoint_lock || return 3

    # Extract archive to restore files
    if ! _checkpoint_tar_extract "$archive_path"; then
        _checkpoint_unlock
        printf '{"error":"archive extraction failed"}\n' >&2
        return 3
    fi

    # Update metadata to record rollback
    local rollback_timestamp
    rollback_timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    # Count restored files
    local restored_count
    restored_count=$(tar -tzf "$archive_path" 2>/dev/null | wc -l)

    _checkpoint_unlock

    _checkpoint_log info "Rolled back checkpoint: $checkpoint_id ($restored_count files restored)"
    printf '{"rolled_back":true,"checkpoint_id":"%s","restored_count":%d,"timestamp":"%s"}\n' \
        "$checkpoint_id" "$restored_count" "$rollback_timestamp"
    return 0
}

# checkpoint_list - List all checkpoints
# @description List all available checkpoints with their metadata
# @pre        None
# @post       None (read-only)
# @idempotent Yes
# @param      --json - Output as JSON array (default: table)
# @param      --all - Include deleted/expired checkpoints
# @stdout     List of checkpoints
# @return     0 always
#
# Usage: checkpoint_list
# Usage: checkpoint_list --json
checkpoint_list() {
    local json_output=0
    local show_all=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --all) show_all=1; shift ;;
            *) shift ;;
        esac
    done

    _checkpoint_ensure_dir || return 0

    local -a checkpoints=()
    local entry

    for entry in "${MAINFRAME_CHECKPOINT_DIR}"/*/metadata.json; do
        [[ -f "$entry" ]] || continue

        local dir="${entry%/metadata.json}"
        local id="${dir##*/}"

        # Validate ID format
        _checkpoint_validate_name "$id" || continue

        # Read metadata
        local name created_at file_count archive_size status
        name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$entry" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
        created_at=$(grep -o '"created_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$entry" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
        file_count=$(grep -o '"file_count"[[:space:]]*:[[:space:]]*[0-9]*' "$entry" | sed 's/.*:[[:space:]]*//' | head -1)
        archive_size=$(grep -o '"archive_size_bytes"[[:space:]]*:[[:space:]]*[0-9]*' "$entry" | sed 's/.*:[[:space:]]*//' | head -1)
        status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$entry" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)

        [[ -z "$status" ]] && status="active"
        [[ $show_all -eq 0 && "$status" != "active" ]] && continue

        if [[ $json_output -eq 1 ]]; then
            checkpoints+=("{\"id\":\"$id\",\"name\":\"$(_checkpoint_json_escape "$name")\",\"created_at\":\"$created_at\",\"file_count\":${file_count:-0},\"size_bytes\":${archive_size:-0},\"status\":\"$status\"}")
        else
            printf '%-36s %-20s %-24s %5s files %10s bytes %s\n' \
                "$id" "$name" "$created_at" "${file_count:-0}" "${archive_size:-0}" "$status"
        fi
    done

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${checkpoints[*]}")"
    fi

    return 0
}

# checkpoint_info - JSON metadata about checkpoint
# @description Get detailed information about a specific checkpoint
# @pre        Checkpoint exists
# @post       None (read-only)
# @idempotent Yes
# @param      $1 checkpoint_id - Checkpoint ID
# @stdout     JSON metadata
# @return     0 on success, 1 if not found
#
# Usage: checkpoint_info "chk_1234567890_abc123"
checkpoint_info() {
    local checkpoint_id="$1"

    if ! _checkpoint_validate_name "$checkpoint_id"; then
        printf '{"error":"invalid checkpoint ID"}\n' >&2
        return 1
    fi

    local metadata_path="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"

    if [[ ! -f "$metadata_path" ]]; then
        printf '{"error":"checkpoint not found","checkpoint_id":"%s"}\n' "$checkpoint_id" >&2
        return 1
    fi

    cat "$metadata_path"
    return 0
}

# checkpoint_delete - Remove checkpoint
# @description Delete a checkpoint and free its storage
# @pre        Checkpoint exists
# @post       Checkpoint directory and all contents removed
# @idempotent Yes - deleting non-existent checkpoint is no-op
# @param      $1 checkpoint_id - Checkpoint ID
# @stdout     JSON confirmation
# @return     0 on success, 1 if not found
#
# Usage: checkpoint_delete "chk_1234567890_abc123"
checkpoint_delete() {
    local checkpoint_id="$1"

    if ! _checkpoint_validate_name "$checkpoint_id"; then
        printf '{"error":"invalid checkpoint ID"}\n' >&2
        return 1
    fi

    local checkpoint_dir="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}"

    if [[ ! -d "$checkpoint_dir" ]]; then
        # Already deleted - idempotent success
        printf '{"deleted":true,"checkpoint_id":"%s","already_deleted":true}\n' "$checkpoint_id"
        return 0
    fi

    _checkpoint_lock || return 1

    # Get size before deletion for reporting
    local freed_bytes
    freed_bytes=$(_checkpoint_size_bytes "$checkpoint_dir")

    rm -rf "$checkpoint_dir" || {
        _checkpoint_unlock
        printf '{"error":"deletion failed","checkpoint_id":"%s"}\n' "$checkpoint_id" >&2
        return 1
    }

    _checkpoint_unlock

    _checkpoint_log debug "Deleted checkpoint: $checkpoint_id (freed ${freed_bytes} bytes)"
    printf '{"deleted":true,"checkpoint_id":"%s","freed_bytes":%d}\n' "$checkpoint_id" "$freed_bytes"
    return 0
}

# checkpoint_prune - Cleanup old checkpoints
# @description Remove checkpoints older than max age or exceeding quota
# @pre        None
# @post       Old checkpoints removed
# @idempotent Yes
# @param      --max-age - Override max age in seconds
# @param      --max-count - Override max count
# @param      --dry-run - Show what would be pruned without deleting
# @stdout     JSON summary
# @return     0 always
#
# Usage: checkpoint_prune
# Usage: checkpoint_prune --max-age 3600 --dry-run
checkpoint_prune() {
    local max_age="$MAINFRAME_CHECKPOINT_MAX_AGE"
    local max_count="$MAINFRAME_CHECKPOINT_MAX_COUNT"
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-age) max_age="$2"; shift 2 ;;
            --max-count) max_count="$2"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    _checkpoint_ensure_dir || return 0

    local now
    now=$(date +%s)
    local pruned=0
    local freed_bytes=0
    local -a to_prune=()

    # Find checkpoints to prune by age
    local entry
    for entry in "${MAINFRAME_CHECKPOINT_DIR}"/*/metadata.json; do
        [[ -f "$entry" ]] || continue

        local dir="${entry%/metadata.json}"
        local id="${dir##*/}"

        _checkpoint_validate_name "$id" || continue

        local created_epoch
        created_epoch=$(grep -o '"created_epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$entry" | sed 's/.*:[[:space:]]*//' | head -1)
        [[ -z "$created_epoch" ]] && continue

        local age=$((now - created_epoch))
        if ((age > max_age)); then
            to_prune+=("$id")
        fi
    done

    # Also prune if over max count (oldest first)
    local current_count
    current_count=$(find "$MAINFRAME_CHECKPOINT_DIR" -maxdepth 1 -type d | wc -l)
    current_count=$((current_count - 1))

    if ((current_count > max_count)); then
        # Get oldest checkpoints
        local oldest
        oldest=$(for entry in "${MAINFRAME_CHECKPOINT_DIR}"/*/metadata.json; do
            [[ -f "$entry" ]] || continue
            local dir="${entry%/metadata.json}"
            local id="${dir##*/}"
            local epoch
            epoch=$(grep -o '"created_epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$entry" | sed 's/.*:[[:space:]]*//')
            [[ -n "$epoch" ]] && printf '%s %s\n' "$epoch" "$id"
        done | sort -n | head -n $((current_count - max_count + 5)) | awk '{print $2}')

        while IFS= read -r id; do
            [[ -n "$id" ]] && to_prune+=("$id")
        done <<< "$oldest"
    fi

    # Remove duplicates
    local -A seen
    local -a unique_prune=()
    for id in "${to_prune[@]}"; do
        if [[ -z "${seen[$id]:-}" ]]; then
            seen[$id]=1
            unique_prune+=("$id")
        fi
    done

    # Perform pruning
    for id in "${unique_prune[@]}"; do
        local checkpoint_dir="${MAINFRAME_CHECKPOINT_DIR}/${id}"
        local size
        size=$(_checkpoint_size_bytes "$checkpoint_dir")

        if [[ $dry_run -eq 1 ]]; then
            _checkpoint_log info "[dry-run] Would prune: $id (${size} bytes)"
        else
            rm -rf "$checkpoint_dir" 2>/dev/null && {
                _checkpoint_log debug "Pruned checkpoint: $id"
                pruned=$((pruned + 1))
                freed_bytes=$((freed_bytes + size))
            }
        fi
    done

    printf '{"pruned":%d,"freed_bytes":%d,"dry_run":%s}\n' \
        "$pruned" "$freed_bytes" "$([[ $dry_run -eq 1 ]] && echo "true" || echo "false")"
    return 0
}

# checkpoint_auto_start - Begin auto-checkpoint scope
# @description Start an automatic checkpoint scope that tracks file changes
# @pre        None
# @post       Scope initialized for tracking
# @idempotent No - creates new scope each time
# @param      $1 scope_name - Unique name for this scope
# @param      $@ files - Files to track and checkpoint
# @stdout     None
# @return     0 on success, 1 on invalid scope or files
#
# Usage: checkpoint_auto_start "deploy" /etc/nginx/nginx.conf /var/www/html
checkpoint_auto_start() {
    local scope_name="$1"
    shift
    local -a files=("$@")

    if ! _checkpoint_validate_name "$scope_name"; then
        _checkpoint_log error "Invalid scope name"
        return 1
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        _checkpoint_log error "No files specified for auto-checkpoint"
        return 1
    fi

    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "auto_${scope_name}" "${files[@]}") || return 1

    # Store in tracking arrays
    _CHECKPOINT_AUTO_IDS[$scope_name]="$checkpoint_id"
    _CHECKPOINT_AUTO_FILES[$scope_name]="${files[*]}"

    _checkpoint_log debug "Auto-checkpoint scope started: $scope_name (id=$checkpoint_id)"
    return 0
}

# checkpoint_auto_commit - Commit and cleanup on success
# @description Commit auto-checkpoint scope - delete checkpoint (changes are permanent)
# @pre        Scope exists (from checkpoint_auto_start)
# @post       Checkpoint deleted, scope cleared
# @idempotent Yes - committing non-existent scope is no-op
# @param      $1 scope_name - Scope name from checkpoint_auto_start
# @stdout     JSON confirmation
# @return     0 on success
#
# Usage: checkpoint_auto_commit "deploy"
checkpoint_auto_commit() {
    local scope_name="$1"

    local checkpoint_id="${_CHECKPOINT_AUTO_IDS[$scope_name]:-}"

    if [[ -z "$checkpoint_id" ]]; then
        _checkpoint_log debug "No checkpoint found for scope: $scope_name (already committed?)"
        printf '{"committed":true,"scope":"%s","already_committed":true}\n' "$scope_name"
        return 0
    fi

    # Delete the checkpoint (changes are now permanent)
    checkpoint_delete "$checkpoint_id" &>/dev/null

    # Clear tracking
    unset "_CHECKPOINT_AUTO_IDS[$scope_name]"
    unset "_CHECKPOINT_AUTO_FILES[$scope_name]"

    _checkpoint_log debug "Auto-checkpoint committed: $scope_name"
    printf '{"committed":true,"scope":"%s","checkpoint_id":"%s"}\n' "$scope_name" "$checkpoint_id"
    return 0
}

# checkpoint_auto_abort - Rollback and cleanup on failure
# @description Abort auto-checkpoint scope - rollback changes and cleanup
# @pre        Scope exists (from checkpoint_auto_start)
# @post       Files restored, checkpoint deleted, scope cleared
# @idempotent Yes - aborting non-existent scope is no-op
# @param      $1 scope_name - Scope name from checkpoint_auto_start
# @stdout     JSON summary
# @return     0 on success
#
# Usage: checkpoint_auto_abort "deploy"
checkpoint_auto_abort() {
    local scope_name="$1"

    local checkpoint_id="${_CHECKPOINT_AUTO_IDS[$scope_name]:-}"

    if [[ -z "$checkpoint_id" ]]; then
        _checkpoint_log debug "No checkpoint found for scope: $scope_name"
        printf '{"aborted":true,"scope":"%s","no_checkpoint":true}\n' "$scope_name"
        return 0
    fi

    # Rollback to checkpoint
    local rollback_result
    rollback_result=$(checkpoint_rollback "$checkpoint_id" --force 2>&1) || {
        _checkpoint_log error "Rollback failed for scope: $scope_name"
        printf '{"error":"rollback failed","scope":"%s","checkpoint_id":"%s"}\n' "$scope_name" "$checkpoint_id" >&2
        return 1
    }

    # Delete the checkpoint after successful rollback
    checkpoint_delete "$checkpoint_id" &>/dev/null

    # Clear tracking
    unset "_CHECKPOINT_AUTO_IDS[$scope_name]"
    unset "_CHECKPOINT_AUTO_FILES[$scope_name]"

    _checkpoint_log info "Auto-checkpoint aborted and rolled back: $scope_name"
    printf '{"aborted":true,"scope":"%s","checkpoint_id":"%s","rolled_back":true}\n' "$scope_name" "$checkpoint_id"
    return 0
}

# checkpoint_exists - Check if checkpoint exists
# @description Check if a checkpoint with the given ID exists
# @pre        None
# @post       None (read-only)
# @idempotent Yes
# @param      $1 checkpoint_id - Checkpoint ID to check
# @stdout     None
# @return     0 if exists, 1 if not found
#
# Usage: if checkpoint_exists "chk_123"; then echo "exists"; fi
checkpoint_exists() {
    local checkpoint_id="$1"

    if ! _checkpoint_validate_name "$checkpoint_id"; then
        return 1
    fi

    local checkpoint_dir="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}"
    local metadata_path="${checkpoint_dir}/metadata.json"
    local archive_path="${checkpoint_dir}/data.tar.gz"

    [[ -d "$checkpoint_dir" ]] && [[ -f "$metadata_path" ]] && [[ -f "$archive_path" ]]
}

# =============================================================================
# INTERNAL QUOTA ENFORCEMENT
# =============================================================================

_checkpoint_enforce_quotas() {
    # Count enforcement
    local count
    count=$(find "$MAINFRAME_CHECKPOINT_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    count=$((count - 1))

    if ((count > MAINFRAME_CHECKPOINT_MAX_COUNT)); then
        checkpoint_prune --max-count "$MAINFRAME_CHECKPOINT_MAX_COUNT" &>/dev/null
    fi

    # Age enforcement
    checkpoint_prune --max-age "$MAINFRAME_CHECKPOINT_MAX_AGE" &>/dev/null
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _CHECKPOINT_EXPORTS=(
    checkpoint_create
    checkpoint_rollback
    checkpoint_list
    checkpoint_info
    checkpoint_delete
    checkpoint_prune
    checkpoint_auto_start
    checkpoint_auto_commit
    checkpoint_auto_abort
    checkpoint_exists
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_CHECKPOINT_EXPORTS[@]}" 2>/dev/null || true
fi

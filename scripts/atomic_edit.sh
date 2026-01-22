#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/atomic_edit.sh - Atomic Multi-File Editor
# =============================================================================
# Description: Performs atomic multi-file edits with full rollback capability
# Purpose: Critical for AI agents making coordinated changes across codebases
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
# Version: 1.0.0
# License: MIT
# =============================================================================
#
# Usage:
#   atomic_edit begin                              Start atomic transaction
#   atomic_edit stage "file" "content"             Stage full file replacement
#   atomic_edit patch "file" "old" "new"           Stage pattern replacement
#   atomic_edit append "file" "content"            Stage content append
#   atomic_edit prepend "file" "content"           Stage content prepend
#   atomic_edit delete "file"                      Stage file deletion
#   atomic_edit create "file" "content" [mode]     Stage new file creation
#   atomic_edit commit                             Commit all staged changes
#   atomic_edit rollback                           Rollback all changes
#   atomic_edit status                             Show transaction status
#   atomic_edit diff                               Show staged changes
#
# Environment Variables:
#   ATOMIC_EDIT_DEBUG=1       Enable debug output
#   ATOMIC_EDIT_DRY_RUN=1     Simulate commit without actual changes
#   ATOMIC_EDIT_BACKUP=1      Keep backups after commit (default: cleanup)
#
# Examples:
#   # Coordinated config update
#   atomic_edit begin
#   atomic_edit stage "/etc/app/config.yml" "$NEW_CONFIG"
#   atomic_edit patch "/etc/app/version.txt" "1.0.0" "1.1.0"
#   atomic_edit commit
#
#   # Safe multi-file refactoring
#   atomic_edit begin
#   atomic_edit patch "src/module.js" "oldFunction" "newFunction"
#   atomic_edit patch "src/utils.js" "oldFunction" "newFunction"
#   atomic_edit patch "tests/module.test.js" "oldFunction" "newFunction"
#   if ! atomic_edit commit; then
#       echo "Failed - all changes rolled back"
#   fi
#
# =============================================================================

# Source MAINFRAME library
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# =============================================================================
# CONSTANTS
# =============================================================================

readonly ATOMIC_EDIT_VERSION="1.0.0"
readonly ATOMIC_EDIT_PREFIX="atomic_edit"

# Transaction operation types
readonly OP_STAGE="STAGE"
readonly OP_PATCH="PATCH"
readonly OP_APPEND="APPEND"
readonly OP_PREPEND="PREPEND"
readonly OP_DELETE="DELETE"
readonly OP_CREATE="CREATE"

# Exit codes specific to atomic_edit
readonly EXIT_NO_TRANSACTION=10
readonly EXIT_ACTIVE_TRANSACTION=11
readonly EXIT_COMMIT_FAILED=12
readonly EXIT_ROLLBACK_FAILED=13
readonly EXIT_VALIDATION_FAILED=14

# =============================================================================
# TRANSACTION STATE
# =============================================================================

# Global state variables (set during transaction)
declare -g ATOMIC_EDIT_DIR=""
declare -g ATOMIC_EDIT_MANIFEST=""
declare -g ATOMIC_EDIT_LOCK=""
declare -g ATOMIC_EDIT_ID=""
declare -ga ATOMIC_EDIT_FILES=()

# State file for persistent transactions
readonly ATOMIC_EDIT_STATE_DIR="${TMPDIR:-/tmp}/.atomic_edit_state"

# =============================================================================
# INTERNAL UTILITIES
# =============================================================================

# Debug logging
_ae_debug() {
    [[ "${ATOMIC_EDIT_DEBUG:-0}" == "1" ]] && log_debug "[atomic_edit] $*"
}

# Generate unique transaction ID
_ae_generate_id() {
    printf '%s_%s_%s' "$$" "$(date +%s%N)" "$(random_string 8)"
}

# Encode path for safe filename storage
_ae_encode_path() {
    local path="$1"
    # Base64 encode the path for safe storage
    printf '%s' "$path" | base64 -w0 | tr '+/' '-_'
}

# Decode path from safe filename
_ae_decode_path() {
    local encoded="$1"
    printf '%s' "$encoded" | tr '-_' '+/' | base64 -d
}

# Check if transaction is active
_ae_is_active() {
    [[ -n "$ATOMIC_EDIT_DIR" && -d "$ATOMIC_EDIT_DIR" && -f "$ATOMIC_EDIT_MANIFEST" ]]
}

# Load transaction state from persistent storage
_ae_load_state() {
    local state_file="$ATOMIC_EDIT_STATE_DIR/current_$$"
    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

# Save transaction state to persistent storage
_ae_save_state() {
    mkdir -p "$ATOMIC_EDIT_STATE_DIR"
    local state_file="$ATOMIC_EDIT_STATE_DIR/current_$$"
    cat > "$state_file" <<EOF
ATOMIC_EDIT_DIR="$ATOMIC_EDIT_DIR"
ATOMIC_EDIT_MANIFEST="$ATOMIC_EDIT_MANIFEST"
ATOMIC_EDIT_LOCK="$ATOMIC_EDIT_LOCK"
ATOMIC_EDIT_ID="$ATOMIC_EDIT_ID"
ATOMIC_EDIT_FILES=(${ATOMIC_EDIT_FILES[*]@Q})
EOF
}

# Clear transaction state
_ae_clear_state() {
    local state_file="$ATOMIC_EDIT_STATE_DIR/current_$$"
    [[ -f "$state_file" ]] && rm -f "$state_file"
}

# Verify file is writable (or can be created)
_ae_verify_writable() {
    local target="$1"
    local dir
    dir=$(dirname "$target")

    # Directory must exist and be writable
    if [[ ! -d "$dir" ]]; then
        log_error "Directory does not exist: $dir"
        return 1
    fi

    if [[ ! -w "$dir" ]]; then
        log_error "Directory not writable: $dir"
        return 1
    fi

    # If file exists, it must be writable
    if [[ -e "$target" && ! -w "$target" ]]; then
        log_error "File not writable: $target"
        return 1
    fi

    return 0
}

# Create backup of a file
_ae_backup_file() {
    local target="$1"
    local backup_name="$2"

    if [[ -f "$target" ]]; then
        cp -p "$target" "$ATOMIC_EDIT_DIR/$backup_name" || {
            log_error "Failed to backup: $target"
            return 1
        }
        _ae_debug "Backed up: $target -> $backup_name"
    elif [[ -e "$target" ]]; then
        log_error "Target exists but is not a regular file: $target"
        return 1
    fi
    # If file doesn't exist, no backup needed (will be created)
    return 0
}

# Restore file from backup
_ae_restore_file() {
    local target="$1"
    local backup_name="$2"

    if [[ -f "$ATOMIC_EDIT_DIR/$backup_name" ]]; then
        mv "$ATOMIC_EDIT_DIR/$backup_name" "$target" || {
            log_error "Failed to restore: $target"
            return 1
        }
        _ae_debug "Restored: $target from $backup_name"
    else
        # No backup means file was newly created - remove it
        if [[ -f "$target" ]]; then
            rm -f "$target" || {
                log_error "Failed to remove newly created file: $target"
                return 1
            }
            _ae_debug "Removed new file: $target"
        fi
    fi
    return 0
}

# =============================================================================
# TRANSACTION MANAGEMENT
# =============================================================================

# Begin a new atomic transaction
atomic_edit_begin() {
    # Check for existing transaction
    if _ae_is_active; then
        log_error "Transaction already active: $ATOMIC_EDIT_ID"
        log_error "Use 'atomic_edit commit' or 'atomic_edit rollback' first"
        return $EXIT_ACTIVE_TRANSACTION
    fi

    # Try to load existing state
    if _ae_load_state && _ae_is_active; then
        log_error "Transaction already active: $ATOMIC_EDIT_ID"
        return $EXIT_ACTIVE_TRANSACTION
    fi

    # Generate transaction ID
    ATOMIC_EDIT_ID=$(_ae_generate_id)

    # Create transaction directory
    ATOMIC_EDIT_DIR=$(mktemp -d -t "atomic_edit_${ATOMIC_EDIT_ID}_XXXXXX") || {
        log_error "Failed to create transaction directory"
        return $EXIT_FAILURE
    }

    # Initialize manifest and lock
    ATOMIC_EDIT_MANIFEST="$ATOMIC_EDIT_DIR/manifest"
    ATOMIC_EDIT_LOCK="$ATOMIC_EDIT_DIR/lock"
    ATOMIC_EDIT_FILES=()

    # Create manifest with header
    cat > "$ATOMIC_EDIT_MANIFEST" <<EOF
# Atomic Edit Transaction Manifest
# ID: $ATOMIC_EDIT_ID
# Started: $(date -Iseconds)
# PID: $$
# User: $(whoami)
EOF

    # Create lock file
    touch "$ATOMIC_EDIT_LOCK"

    # Save state for persistence across subshells
    _ae_save_state

    log_info "Transaction started: $ATOMIC_EDIT_ID"
    _ae_debug "Transaction directory: $ATOMIC_EDIT_DIR"

    return 0
}

# Stage a full file replacement
atomic_edit_stage() {
    local target="$1"
    local content="$2"

    # Validate arguments
    if [[ -z "$target" ]]; then
        log_error "Usage: atomic_edit stage <file> <content>"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath -m "$target" 2>/dev/null) || abs_target="$target"
    [[ "$abs_target" != /* ]] && abs_target="$(pwd)/$abs_target"

    # Verify writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local backup_name="backup_${encoded_name}"
    local staged_name="staged_${encoded_name}"

    # Backup original if exists
    _ae_backup_file "$abs_target" "$backup_name" || return $EXIT_FAILURE

    # Write new content to staging
    printf '%s' "$content" > "$ATOMIC_EDIT_DIR/$staged_name" || {
        log_error "Failed to write staged content for: $target"
        return $EXIT_FAILURE
    }

    # Record in manifest
    printf '%s|%s|%s|%s\n' "$OP_STAGE" "$abs_target" "$staged_name" "$backup_name" >> "$ATOMIC_EDIT_MANIFEST"
    ATOMIC_EDIT_FILES+=("$abs_target")

    _ae_save_state
    _ae_debug "Staged: $target"

    return 0
}

# Stage a pattern replacement (patch)
atomic_edit_patch() {
    local target="$1"
    local pattern="$2"
    local replacement="$3"
    local global="${4:-true}"  # Replace all occurrences by default

    # Validate arguments
    if [[ -z "$target" || -z "$pattern" ]]; then
        log_error "Usage: atomic_edit patch <file> <pattern> <replacement> [global]"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # File must exist for patching
    if [[ ! -f "$target" ]]; then
        log_error "File does not exist: $target"
        return $EXIT_NOINPUT
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath "$target")

    # Verify writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local backup_name="backup_${encoded_name}"
    local staged_name="staged_${encoded_name}"

    # Check if already staged - if so, work from staged version
    local source_file="$abs_target"
    if [[ -f "$ATOMIC_EDIT_DIR/$staged_name" ]]; then
        source_file="$ATOMIC_EDIT_DIR/$staged_name"
        _ae_debug "Using existing staged version for patching"
    else
        # Backup original
        _ae_backup_file "$abs_target" "$backup_name" || return $EXIT_FAILURE
    fi

    # Read content
    local content
    content=$(cat "$source_file") || {
        log_error "Failed to read file: $target"
        return $EXIT_IOERR
    }

    # Check if pattern exists
    if [[ "$content" != *"$pattern"* ]]; then
        log_warn "Pattern not found in file: $target"
        log_warn "Pattern: $pattern"
        return $EXIT_DATAERR
    fi

    # Apply replacement
    local new_content
    if [[ "$global" == "true" ]]; then
        new_content="${content//"$pattern"/"$replacement"}"
    else
        new_content="${content/"$pattern"/"$replacement"}"
    fi

    # Write to staging
    printf '%s' "$new_content" > "$ATOMIC_EDIT_DIR/$staged_name" || {
        log_error "Failed to write staged content for: $target"
        return $EXIT_FAILURE
    }

    # Record in manifest (only if not already recorded)
    if ! grep -q "^[^|]*|${abs_target}|" "$ATOMIC_EDIT_MANIFEST" 2>/dev/null; then
        printf '%s|%s|%s|%s\n' "$OP_PATCH" "$abs_target" "$staged_name" "$backup_name" >> "$ATOMIC_EDIT_MANIFEST"
        ATOMIC_EDIT_FILES+=("$abs_target")
    fi

    _ae_save_state
    _ae_debug "Patched: $target (pattern: ${pattern:0:30}...)"

    return 0
}

# Stage content append
atomic_edit_append() {
    local target="$1"
    local content="$2"

    # Validate arguments
    if [[ -z "$target" || -z "$content" ]]; then
        log_error "Usage: atomic_edit append <file> <content>"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath -m "$target" 2>/dev/null) || abs_target="$target"
    [[ "$abs_target" != /* ]] && abs_target="$(pwd)/$abs_target"

    # Verify writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local backup_name="backup_${encoded_name}"
    local staged_name="staged_${encoded_name}"

    # Get existing content
    local existing=""
    local source_file=""

    if [[ -f "$ATOMIC_EDIT_DIR/$staged_name" ]]; then
        # Use staged version if exists
        source_file="$ATOMIC_EDIT_DIR/$staged_name"
        existing=$(cat "$source_file")
    elif [[ -f "$abs_target" ]]; then
        # Backup and use original
        _ae_backup_file "$abs_target" "$backup_name" || return $EXIT_FAILURE
        existing=$(cat "$abs_target")
    fi

    # Append content
    printf '%s%s' "$existing" "$content" > "$ATOMIC_EDIT_DIR/$staged_name" || {
        log_error "Failed to write staged content for: $target"
        return $EXIT_FAILURE
    }

    # Record in manifest (only if not already recorded)
    if ! grep -q "^[^|]*|${abs_target}|" "$ATOMIC_EDIT_MANIFEST" 2>/dev/null; then
        printf '%s|%s|%s|%s\n' "$OP_APPEND" "$abs_target" "$staged_name" "$backup_name" >> "$ATOMIC_EDIT_MANIFEST"
        ATOMIC_EDIT_FILES+=("$abs_target")
    fi

    _ae_save_state
    _ae_debug "Append staged: $target"

    return 0
}

# Stage content prepend
atomic_edit_prepend() {
    local target="$1"
    local content="$2"

    # Validate arguments
    if [[ -z "$target" || -z "$content" ]]; then
        log_error "Usage: atomic_edit prepend <file> <content>"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath -m "$target" 2>/dev/null) || abs_target="$target"
    [[ "$abs_target" != /* ]] && abs_target="$(pwd)/$abs_target"

    # Verify writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local backup_name="backup_${encoded_name}"
    local staged_name="staged_${encoded_name}"

    # Get existing content
    local existing=""
    local source_file=""

    if [[ -f "$ATOMIC_EDIT_DIR/$staged_name" ]]; then
        # Use staged version if exists
        source_file="$ATOMIC_EDIT_DIR/$staged_name"
        existing=$(cat "$source_file")
    elif [[ -f "$abs_target" ]]; then
        # Backup and use original
        _ae_backup_file "$abs_target" "$backup_name" || return $EXIT_FAILURE
        existing=$(cat "$abs_target")
    fi

    # Prepend content
    printf '%s%s' "$content" "$existing" > "$ATOMIC_EDIT_DIR/$staged_name" || {
        log_error "Failed to write staged content for: $target"
        return $EXIT_FAILURE
    }

    # Record in manifest (only if not already recorded)
    if ! grep -q "^[^|]*|${abs_target}|" "$ATOMIC_EDIT_MANIFEST" 2>/dev/null; then
        printf '%s|%s|%s|%s\n' "$OP_PREPEND" "$abs_target" "$staged_name" "$backup_name" >> "$ATOMIC_EDIT_MANIFEST"
        ATOMIC_EDIT_FILES+=("$abs_target")
    fi

    _ae_save_state
    _ae_debug "Prepend staged: $target"

    return 0
}

# Stage file deletion
atomic_edit_delete() {
    local target="$1"

    # Validate arguments
    if [[ -z "$target" ]]; then
        log_error "Usage: atomic_edit delete <file>"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # File must exist for deletion
    if [[ ! -f "$target" ]]; then
        log_error "File does not exist: $target"
        return $EXIT_NOINPUT
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath "$target")

    # Verify writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local backup_name="backup_${encoded_name}"

    # Backup original
    _ae_backup_file "$abs_target" "$backup_name" || return $EXIT_FAILURE

    # Record in manifest
    printf '%s|%s|%s|%s\n' "$OP_DELETE" "$abs_target" "" "$backup_name" >> "$ATOMIC_EDIT_MANIFEST"
    ATOMIC_EDIT_FILES+=("$abs_target")

    _ae_save_state
    _ae_debug "Delete staged: $target"

    return 0
}

# Stage new file creation
atomic_edit_create() {
    local target="$1"
    local content="$2"
    local mode="${3:-644}"

    # Validate arguments
    if [[ -z "$target" ]]; then
        log_error "Usage: atomic_edit create <file> <content> [mode]"
        return $EXIT_USAGE
    fi

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction. Use 'atomic_edit begin' first"
        return $EXIT_NO_TRANSACTION
    fi

    # Get absolute path
    local abs_target
    abs_target=$(realpath -m "$target" 2>/dev/null) || abs_target="$target"
    [[ "$abs_target" != /* ]] && abs_target="$(pwd)/$abs_target"

    # File must NOT exist for create operation
    if [[ -e "$abs_target" ]]; then
        log_error "File already exists: $target"
        log_error "Use 'atomic_edit stage' to replace existing files"
        return $EXIT_DATAERR
    fi

    # Verify parent directory is writable
    if ! _ae_verify_writable "$abs_target"; then
        return $EXIT_VALIDATION_FAILED
    fi

    # Create encoded filename for storage
    local encoded_name
    encoded_name=$(_ae_encode_path "$abs_target")
    local staged_name="staged_${encoded_name}"

    # Write content to staging
    printf '%s' "$content" > "$ATOMIC_EDIT_DIR/$staged_name" || {
        log_error "Failed to write staged content for: $target"
        return $EXIT_FAILURE
    }

    # Store mode in manifest
    printf '%s|%s|%s|%s|%s\n' "$OP_CREATE" "$abs_target" "$staged_name" "" "$mode" >> "$ATOMIC_EDIT_MANIFEST"
    ATOMIC_EDIT_FILES+=("$abs_target")

    _ae_save_state
    _ae_debug "Create staged: $target (mode: $mode)"

    return 0
}

# Commit all staged changes
atomic_edit_commit() {
    local dry_run="${ATOMIC_EDIT_DRY_RUN:-0}"
    local keep_backups="${ATOMIC_EDIT_BACKUP:-0}"

    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction to commit"
        return $EXIT_NO_TRANSACTION
    fi

    local file_count=0
    local failed=0
    local -a committed_files=()

    log_info "Committing transaction: $ATOMIC_EDIT_ID"

    # First pass: verify all targets are writable
    _ae_debug "Verifying write permissions..."
    while IFS='|' read -r op target staged backup mode; do
        # Skip comments and empty lines
        [[ "$op" == "#"* || -z "$op" ]] && continue

        local dir
        dir=$(dirname "$target")
        if [[ ! -w "$dir" ]]; then
            log_error "Cannot write to directory: $dir"
            failed=1
        fi

        ((file_count++))
    done < "$ATOMIC_EDIT_MANIFEST"

    if ((failed)); then
        log_error "Pre-commit validation failed"
        return $EXIT_VALIDATION_FAILED
    fi

    if ((file_count == 0)); then
        log_warn "No files staged for commit"
        atomic_edit_rollback
        return 0
    fi

    if [[ "$dry_run" == "1" ]]; then
        log_info "[DRY RUN] Would commit $file_count file(s)"
        atomic_edit_diff
        return 0
    fi

    # Second pass: apply changes
    _ae_debug "Applying changes..."
    while IFS='|' read -r op target staged backup mode; do
        # Skip comments and empty lines
        [[ "$op" == "#"* || -z "$op" ]] && continue

        _ae_debug "Processing: $op $target"

        case "$op" in
            "$OP_STAGE"|"$OP_PATCH"|"$OP_APPEND"|"$OP_PREPEND")
                # Move staged file to target (atomic on same filesystem)
                if ! mv "$ATOMIC_EDIT_DIR/$staged" "$target"; then
                    log_error "Failed to commit: $target"
                    # Rollback committed files
                    for committed in "${committed_files[@]}"; do
                        _ae_debug "Rolling back: $committed"
                        local enc
                        enc=$(_ae_encode_path "$committed")
                        _ae_restore_file "$committed" "backup_${enc}"
                    done
                    return $EXIT_COMMIT_FAILED
                fi
                committed_files+=("$target")
                ;;

            "$OP_DELETE")
                # Remove the file
                if ! rm -f "$target"; then
                    log_error "Failed to delete: $target"
                    # Rollback committed files
                    for committed in "${committed_files[@]}"; do
                        local enc
                        enc=$(_ae_encode_path "$committed")
                        _ae_restore_file "$committed" "backup_${enc}"
                    done
                    return $EXIT_COMMIT_FAILED
                fi
                committed_files+=("$target")
                ;;

            "$OP_CREATE")
                # Move staged file to target with specified mode
                if ! mv "$ATOMIC_EDIT_DIR/$staged" "$target"; then
                    log_error "Failed to create: $target"
                    # Rollback committed files
                    for committed in "${committed_files[@]}"; do
                        local enc
                        enc=$(_ae_encode_path "$committed")
                        _ae_restore_file "$committed" "backup_${enc}"
                    done
                    return $EXIT_COMMIT_FAILED
                fi
                chmod "$mode" "$target" 2>/dev/null || true
                committed_files+=("$target")
                ;;

            *)
                log_warn "Unknown operation: $op"
                ;;
        esac
    done < "$ATOMIC_EDIT_MANIFEST"

    # Cleanup
    if [[ "$keep_backups" == "1" ]]; then
        local backup_dir="${ATOMIC_EDIT_DIR}_committed"
        mv "$ATOMIC_EDIT_DIR" "$backup_dir"
        log_info "Backups preserved at: $backup_dir"
    else
        rm -rf "$ATOMIC_EDIT_DIR"
    fi

    _ae_clear_state

    # Reset state
    ATOMIC_EDIT_DIR=""
    ATOMIC_EDIT_MANIFEST=""
    ATOMIC_EDIT_LOCK=""
    ATOMIC_EDIT_ID=""
    ATOMIC_EDIT_FILES=()

    success "Transaction committed: ${#committed_files[@]} file(s)"
    return 0
}

# Rollback all staged changes
atomic_edit_rollback() {
    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_error "No active transaction to rollback"
        return $EXIT_NO_TRANSACTION
    fi

    log_info "Rolling back transaction: $ATOMIC_EDIT_ID"

    local rollback_count=0

    # Restore from backups
    while IFS='|' read -r op target staged backup mode; do
        # Skip comments and empty lines
        [[ "$op" == "#"* || -z "$op" ]] && continue

        # Only restore if file was committed (shouldn't happen in rollback before commit)
        # and backup exists
        if [[ -n "$backup" && -f "$ATOMIC_EDIT_DIR/$backup" ]]; then
            if _ae_restore_file "$target" "$backup"; then
                ((rollback_count++))
            fi
        fi
    done < "$ATOMIC_EDIT_MANIFEST"

    # Cleanup transaction directory
    rm -rf "$ATOMIC_EDIT_DIR"
    _ae_clear_state

    # Reset state
    ATOMIC_EDIT_DIR=""
    ATOMIC_EDIT_MANIFEST=""
    ATOMIC_EDIT_LOCK=""
    ATOMIC_EDIT_ID=""
    ATOMIC_EDIT_FILES=()

    success "Transaction rolled back"
    return 0
}

# Show transaction status
atomic_edit_status() {
    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_info "No active transaction"
        return 0
    fi

    printf "\n%b=== Atomic Edit Transaction ===%b\n\n" "$CLR_BOLD$CLR_CYAN" "$CLR_RESET"
    printf "  ID:        %s\n" "$ATOMIC_EDIT_ID"
    printf "  Directory: %s\n" "$ATOMIC_EDIT_DIR"
    printf "  Files:     %d staged\n" "${#ATOMIC_EDIT_FILES[@]}"
    printf "\n"

    # Show staged files with operation type
    if [[ ${#ATOMIC_EDIT_FILES[@]} -gt 0 ]]; then
        printf "%bStaged Changes:%b\n" "$CLR_BOLD" "$CLR_RESET"
        while IFS='|' read -r op target staged backup mode; do
            # Skip comments and empty lines
            [[ "$op" == "#"* || -z "$op" ]] && continue

            local op_color="$CLR_GREEN"
            case "$op" in
                "$OP_DELETE") op_color="$CLR_RED" ;;
                "$OP_PATCH")  op_color="$CLR_YELLOW" ;;
                "$OP_CREATE") op_color="$CLR_CYAN" ;;
            esac

            printf "  %b%-8s%b %s\n" "$op_color" "$op" "$CLR_RESET" "$target"
        done < "$ATOMIC_EDIT_MANIFEST"
        printf "\n"
    fi

    return 0
}

# Show diff of staged changes
atomic_edit_diff() {
    # Try to load state if not active
    _ae_is_active || _ae_load_state

    if ! _ae_is_active; then
        log_info "No active transaction"
        return 0
    fi

    printf "\n%b=== Staged Changes ===%b\n\n" "$CLR_BOLD$CLR_CYAN" "$CLR_RESET"

    # Show diffs for each file
    while IFS='|' read -r op target staged backup mode; do
        # Skip comments and empty lines
        [[ "$op" == "#"* || -z "$op" ]] && continue

        printf "%b--- %s (%s) ---%b\n" "$CLR_BOLD" "$target" "$op" "$CLR_RESET"

        case "$op" in
            "$OP_DELETE")
                printf "%b[FILE WILL BE DELETED]%b\n" "$CLR_RED" "$CLR_RESET"
                ;;

            "$OP_CREATE")
                printf "%b[NEW FILE - mode %s]%b\n" "$CLR_GREEN" "$mode" "$CLR_RESET"
                if command_exists head; then
                    head -20 "$ATOMIC_EDIT_DIR/$staged" 2>/dev/null
                    local lines
                    lines=$(wc -l < "$ATOMIC_EDIT_DIR/$staged" 2>/dev/null || echo "0")
                    ((lines > 20)) && printf "... (%d more lines)\n" "$((lines - 20))"
                fi
                ;;

            *)
                # Show diff if diff command available
                if command_exists diff; then
                    if [[ -f "$ATOMIC_EDIT_DIR/$backup" ]]; then
                        diff -u "$ATOMIC_EDIT_DIR/$backup" "$ATOMIC_EDIT_DIR/$staged" 2>/dev/null || true
                    else
                        printf "%b[NEW FILE]%b\n" "$CLR_GREEN" "$CLR_RESET"
                        head -20 "$ATOMIC_EDIT_DIR/$staged" 2>/dev/null
                    fi
                else
                    printf "(diff not available)\n"
                fi
                ;;
        esac
        printf "\n"
    done < "$ATOMIC_EDIT_MANIFEST"

    return 0
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Quick atomic write of single file (begin -> stage -> commit)
atomic_edit_quick() {
    local target="$1"
    local content="$2"

    atomic_edit_begin || return $?
    atomic_edit_stage "$target" "$content" || {
        atomic_edit_rollback
        return $?
    }
    atomic_edit_commit || return $?
}

# Quick atomic patch of single file
atomic_edit_quick_patch() {
    local target="$1"
    local pattern="$2"
    local replacement="$3"

    atomic_edit_begin || return $?
    atomic_edit_patch "$target" "$pattern" "$replacement" || {
        atomic_edit_rollback
        return $?
    }
    atomic_edit_commit || return $?
}

# =============================================================================
# HELP
# =============================================================================

atomic_edit_help() {
    cat <<'EOF'
atomic_edit - Atomic Multi-File Editor

SYNOPSIS
    atomic_edit <command> [arguments...]

COMMANDS
    begin                           Start a new atomic transaction
    stage <file> <content>          Stage full file replacement
    patch <file> <old> <new>        Stage pattern replacement
    append <file> <content>         Stage content append
    prepend <file> <content>        Stage content prepend
    delete <file>                   Stage file deletion
    create <file> <content> [mode]  Stage new file creation
    commit                          Commit all staged changes atomically
    rollback                        Rollback all staged changes
    status                          Show current transaction status
    diff                            Show staged changes diff
    help                            Show this help message

ENVIRONMENT
    ATOMIC_EDIT_DEBUG=1     Enable debug output
    ATOMIC_EDIT_DRY_RUN=1   Simulate commit without changes
    ATOMIC_EDIT_BACKUP=1    Preserve backups after commit

EXAMPLES
    # Multi-file coordinated update
    atomic_edit begin
    atomic_edit stage "config.yml" "$NEW_CONFIG"
    atomic_edit patch "version.txt" "1.0.0" "1.1.0"
    atomic_edit commit

    # Safe refactoring across files
    atomic_edit begin
    atomic_edit patch "src/main.js" "oldName" "newName"
    atomic_edit patch "src/utils.js" "oldName" "newName"
    atomic_edit patch "tests/main.test.js" "oldName" "newName"
    if atomic_edit commit; then
        echo "Refactoring complete"
    else
        echo "Failed - all changes rolled back"
    fi

    # Create new file atomically
    atomic_edit begin
    atomic_edit create "newfile.sh" "#!/bin/bash\necho hello" 755
    atomic_edit commit

VERSION
    atomic_edit v1.0.0
EOF
}

# =============================================================================
# MAIN DISPATCH
# =============================================================================

atomic_edit() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        begin)    atomic_edit_begin "$@" ;;
        stage)    atomic_edit_stage "$@" ;;
        patch)    atomic_edit_patch "$@" ;;
        append)   atomic_edit_append "$@" ;;
        prepend)  atomic_edit_prepend "$@" ;;
        delete)   atomic_edit_delete "$@" ;;
        create)   atomic_edit_create "$@" ;;
        commit)   atomic_edit_commit "$@" ;;
        rollback) atomic_edit_rollback "$@" ;;
        status)   atomic_edit_status "$@" ;;
        diff)     atomic_edit_diff "$@" ;;
        quick)    atomic_edit_quick "$@" ;;
        quick-patch) atomic_edit_quick_patch "$@" ;;
        help|--help|-h) atomic_edit_help ;;
        version|--version|-v) printf 'atomic_edit v%s\n' "$ATOMIC_EDIT_VERSION" ;;
        *)
            log_error "Unknown command: $cmd"
            log_error "Use 'atomic_edit help' for usage"
            return $EXIT_USAGE
            ;;
    esac
}

# Execute if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    atomic_edit "$@"
fi

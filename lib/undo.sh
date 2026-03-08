#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/undo.sh - Automatic Undo/Rollback for AI Agent Safety
# =============================================================================
# Description: Records inverse operations for every tracked action, enabling
#              AI agents to roll back mistakes safely. Provides in-memory undo
#              stack with disk-backed file backups, size-limited storage, and
#              content-deduplicated backup via SHA-256 hashing.
# Version: 1.0.0
# Requires: Bash 4.0+, sha256sum/shasum/openssl, coreutils (cp, mv, rm, stat)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_UNDO_LOADED:-}" ]] && return 0
readonly _MAINFRAME_UNDO_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

MAINFRAME_UNDO_ENABLED="${MAINFRAME_UNDO_ENABLED:-1}"           # Enable undo recording
MAINFRAME_UNDO_DIR="${MAINFRAME_UNDO_DIR:-${TMPDIR:-/tmp}/mainframe_undo_${UID:-$(id -u)}_$$}"  # Backup storage
MAINFRAME_UNDO_MAX_STEPS="${MAINFRAME_UNDO_MAX_STEPS:-50}"      # Max undo history
MAINFRAME_UNDO_MAX_SIZE="${MAINFRAME_UNDO_MAX_SIZE:-52428800}"   # Max backup size (50MB)

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -ga _MAINFRAME_UNDO_STACK=()      # Undo stack (indexed array of records)
declare -gi _MAINFRAME_UNDO_COUNT=0       # Step counter
declare -g _MAINFRAME_UNDO_INITIALIZED="" # Init flag

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_undo_escape() {
    local str="$1"
    str="${str//\\/\\\\}"; str="${str//\"/\\\"}";
    str="${str//$'\n'/\\n}"; str="${str//$'\t'/\\t}"; str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Delegate to centralized logging (with fallback for standalone testing)
_undo_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "undo" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[undo] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

_undo_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then printf '%s' "$EPOCHSECONDS"
    else date +%s; fi
}

# @returns: SHA-256 hex hash of file contents
_undo_sha256_file() {
    local file="$1"
    [[ -f "$file" ]] || { printf ''; return 1; }
    if type -p sha256sum &>/dev/null; then sha256sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then shasum -a 256 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then openssl dgst -sha256 "$file" | awk '{print $NF}'
    else printf ''; return 1; fi
}

# @returns: file size in bytes (portable GNU/BSD)
_undo_file_size() {
    local file="$1"
    [[ -f "$file" ]] || { printf '0'; return; }
    stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0
}

# @returns: octal file permission mode
_undo_file_mode() {
    local file="$1"
    [[ -e "$file" ]] || { printf ''; return 1; }
    stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null
}

# @returns: total backup directory size in bytes
_undo_backup_size() {
    local dir="${MAINFRAME_UNDO_DIR}/backups"
    [[ -d "$dir" ]] || { printf '0'; return; }
    local size
    size=$(du -sb "$dir" 2>/dev/null | cut -f1)
    if [[ -z "$size" ]]; then
        size=$(du -sk "$dir" 2>/dev/null | cut -f1)
        size=$(( ${size:-0} * 1024 ))
    fi
    printf '%s' "${size:-0}"
}

_undo_is_dryrun() { [[ "${MAINFRAME_DRYRUN:-0}" == "1" ]]; }

# Emit output respecting USOP (json/raw)
_undo_output() {
    local data="$1"
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]] && declare -F output &>/dev/null; then
        output -t json_object "$data"
    else
        printf '%s\n' "$data"
    fi
}

# Emit error respecting USOP
_undo_output_error() {
    local code="$1" msg="$2" suggestion="${3:-}"
    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]] && declare -F output_error &>/dev/null; then
        output_error -s "$suggestion" "$code" "$msg"; return
    fi
    printf 'error: [%s] %s\n' "$code" "$msg" >&2
    [[ -n "$suggestion" ]] && printf '  suggestion: %s\n' "$suggestion" >&2
}

# @pre: file exists and is readable
# @post: file copied to backups/HASH (deduplicated), hash printed to stdout
# @returns: 0 on success, 1 if size limit exceeded or hash fails
_undo_backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    local current_size file_size
    current_size=$(_undo_backup_size)
    file_size=$(_undo_file_size "$file")
    if (( current_size + file_size > MAINFRAME_UNDO_MAX_SIZE )); then
        _undo_log warn "Backup storage limit reached (${MAINFRAME_UNDO_MAX_SIZE} bytes)"
        return 1
    fi
    local hash
    hash=$(_undo_sha256_file "$file")
    [[ -z "$hash" ]] && return 1
    local backup_path="${MAINFRAME_UNDO_DIR}/backups/${hash}"
    [[ -f "$backup_path" ]] || cp -p "$file" "$backup_path" 2>/dev/null || return 1
    printf '%s' "$hash"
}

# Push entry, evict oldest if at capacity
_undo_push() {
    while (( ${#_MAINFRAME_UNDO_STACK[@]} >= MAINFRAME_UNDO_MAX_STEPS )); do
        _MAINFRAME_UNDO_STACK=("${_MAINFRAME_UNDO_STACK[@]:1}")
    done
    _MAINFRAME_UNDO_STACK+=("$1")
    _MAINFRAME_UNDO_COUNT=$((_MAINFRAME_UNDO_COUNT + 1))
}

# Format: step|timestamp|operation|target|inverse|backup_hash|extra|description
_undo_make_entry() {
    local ts; ts=$(_undo_epoch)
    printf '%s|%s|%s|%s|%s|%s|%s|%s' \
        "$_MAINFRAME_UNDO_COUNT" "$ts" "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}"
}

# Parse pipe-delimited field by 0-based index
_undo_get_field() {
    local IFS='|'; local -a fields; read -ra fields <<< "$1"
    printf '%s' "${fields[$2]:-}"
}

# =============================================================================
# PUBLIC API: INITIALIZATION
# =============================================================================

# @pre: none
# @post: undo directory created, cleanup trap set
# @idempotent: yes
# @returns: 0 on success, 1 if directory creation fails
mainframe_undo_init() {
    [[ -n "$_MAINFRAME_UNDO_INITIALIZED" ]] && return 0
    [[ "$MAINFRAME_UNDO_ENABLED" != "1" ]] && return 0
    mkdir -p "${MAINFRAME_UNDO_DIR}/backups" 2>/dev/null || {
        _undo_log error "Failed to create undo directory: ${MAINFRAME_UNDO_DIR}"
        MAINFRAME_UNDO_ENABLED=0; return 1
    }
    chmod 700 "${MAINFRAME_UNDO_DIR}" 2>/dev/null
    trap 'rm -rf "${MAINFRAME_UNDO_DIR}" 2>/dev/null' EXIT
    _MAINFRAME_UNDO_INITIALIZED=1
}

# =============================================================================
# PUBLIC API: RECORDING
# =============================================================================

# @pre: undo system initialized (auto-initializes if needed)
# @post: operation recorded with backup (if applicable)
# @returns: 0 on success, 1 if recording disabled or backup failed
#
# Record an operation with its inverse. Operations and inverses:
#   write->restore, delete->restore, move->move_back, copy->delete_copy,
#   mkdir->rmdir, chmod->chmod_back, rename->rename_back,
#   append->truncate_to, truncate->restore
mainframe_undo_record() {
    [[ "$MAINFRAME_UNDO_ENABLED" != "1" ]] && return 0
    local operation="$1" target="$2" description="${3:-${1} ${2}}"
    if [[ -z "$operation" ]] || [[ -z "$target" ]]; then
        _undo_output_error "E_ARG_MISSING" "mainframe_undo_record: operation and target required"
        return 1
    fi
    mainframe_undo_init || return 1
    local inverse="" backup="" extra=""
    case "$operation" in
        write)
            inverse="restore"
            [[ -f "$target" ]] && { backup=$(_undo_backup_file "$target") || return 1; }
            ;;
        delete)
            inverse="restore"
            if [[ -f "$target" ]]; then backup=$(_undo_backup_file "$target") || return 1
            elif [[ -d "$target" ]]; then _undo_log warn "Directory deletion undo unsupported"; return 1; fi
            ;;
        move)     inverse="move_back"; extra="$target" ;;
        copy)     inverse="delete_copy" ;;
        mkdir)    inverse="rmdir" ;;
        chmod)    inverse="chmod_back"; extra=$(_undo_file_mode "$target"); [[ -z "$extra" ]] && return 1 ;;
        rename)   inverse="rename_back"; extra="$target" ;;
        append)   inverse="truncate_to"; extra=$(_undo_file_size "$target") ;;
        truncate)
            inverse="restore"
            [[ -f "$target" ]] && { backup=$(_undo_backup_file "$target") || return 1; }
            ;;
        *)
            _undo_output_error "E_ARG_INVALID" "Unknown operation: $operation" \
                "Supported: write, delete, move, copy, mkdir, chmod, rename, append, truncate"
            return 1 ;;
    esac
    _undo_push "$(_undo_make_entry "$operation" "$target" "$inverse" "$backup" "$extra" "$description")"
}

# =============================================================================
# PUBLIC API: UNDO EXECUTION
# =============================================================================

# @pre: undo stack is non-empty
# @post: inverse operations executed in reverse order, stack trimmed
# @returns: 0 if all undos succeed, 1 if any fail (stops on first failure)
mainframe_undo() {
    [[ "$MAINFRAME_UNDO_ENABLED" != "1" ]] && return 1
    local steps=1 to_step=-1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --steps) steps="$2"; shift 2 ;; --to) to_step="$2"; shift 2 ;; *) shift ;;
        esac
    done
    local stack_size=${#_MAINFRAME_UNDO_STACK[@]}
    (( stack_size == 0 )) && { _undo_output_error "E_STATE_EMPTY" "Undo stack is empty"; return 1; }

    local undo_count=$steps
    if (( to_step >= 0 )); then
        undo_count=0
        local i; for (( i = stack_size - 1; i >= 0; i-- )); do
            local s; s=$(_undo_get_field "${_MAINFRAME_UNDO_STACK[$i]}" 0)
            (( s <= to_step )) && break
            undo_count=$((undo_count + 1))
        done
    fi
    (( undo_count > stack_size )) && undo_count=$stack_size

    local succeeded=0 failed=0
    local n; for (( n = 0; n < undo_count; n++ )); do
        local idx=$(( stack_size - 1 - n ))
        local entry="${_MAINFRAME_UNDO_STACK[$idx]}"
        local op target inverse backup extra
        op=$(_undo_get_field "$entry" 2); target=$(_undo_get_field "$entry" 3)
        inverse=$(_undo_get_field "$entry" 4); backup=$(_undo_get_field "$entry" 5)
        extra=$(_undo_get_field "$entry" 6)
        local undo_ok=true

        case "$inverse" in
            restore)
                if [[ -n "$backup" ]]; then
                    local bp="${MAINFRAME_UNDO_DIR}/backups/${backup}"
                    if [[ -f "$bp" ]]; then cp -p "$bp" "$target" 2>/dev/null || undo_ok=false
                    else _undo_log warn "Backup missing: $backup"; undo_ok=false; fi
                else rm -f "$target" 2>/dev/null || undo_ok=false; fi
                ;;
            move_back)
                [[ -e "$target" ]] && mv "$target" "$extra" 2>/dev/null || undo_ok=false ;;
            delete_copy)
                rm -f "$target" 2>/dev/null || undo_ok=false ;;
            rmdir)
                [[ -d "$target" ]] && { rmdir "$target" 2>/dev/null || undo_ok=false; } ;;
            chmod_back)
                [[ -e "$target" ]] && [[ -n "$extra" ]] && chmod "$extra" "$target" 2>/dev/null || undo_ok=false ;;
            rename_back)
                [[ -e "$target" ]] && mv "$target" "$extra" 2>/dev/null || undo_ok=false ;;
            truncate_to)
                if [[ -f "$target" ]] && [[ -n "$extra" ]]; then
                    truncate -s "$extra" "$target" 2>/dev/null || {
                        dd if="$target" of="${target}.undo_tmp" bs=1 count="$extra" 2>/dev/null && \
                            mv "${target}.undo_tmp" "$target" 2>/dev/null || undo_ok=false
                    }
                else undo_ok=false; fi
                ;;
            *) _undo_log warn "Unknown inverse: $inverse"; undo_ok=false ;;
        esac

        if [[ "$undo_ok" == true ]]; then succeeded=$((succeeded + 1))
        else
            failed=$((failed + 1))
            _undo_log error "Undo failed at step $idx ($op on $target)"
            break
        fi
    done

    (( succeeded > 0 )) && _MAINFRAME_UNDO_STACK=("${_MAINFRAME_UNDO_STACK[@]:0:$((stack_size - succeeded))}")
    (( failed > 0 )) && {
        _undo_output_error "E_UNDO_PARTIAL" "$succeeded succeeded, $failed failed" \
            "Check file permissions and backup integrity"; return 1; }
    return 0
}

# =============================================================================
# PUBLIC API: INSPECTION
# =============================================================================

# @pre: none
# @post: undo history printed to stdout (text or json format)
# @returns: 0
mainframe_undo_show() {
    local format="text"
    while [[ $# -gt 0 ]]; do case "$1" in --format) format="$2"; shift 2 ;; *) shift ;; esac; done
    local stack_size=${#_MAINFRAME_UNDO_STACK[@]}

    if [[ "$format" == "json" ]]; then
        local json="[" first=true i
        for (( i = 0; i < stack_size; i++ )); do
            local entry="${_MAINFRAME_UNDO_STACK[$i]}"
            local step ts op target inverse backup desc
            step=$(_undo_get_field "$entry" 0); ts=$(_undo_get_field "$entry" 1)
            op=$(_undo_get_field "$entry" 2); target=$(_undo_get_field "$entry" 3)
            inverse=$(_undo_get_field "$entry" 4); backup=$(_undo_get_field "$entry" 5)
            desc=$(_undo_get_field "$entry" 7)
            $first || json+=","; first=false
            json+="{\"step\":${step},\"timestamp\":${ts},\"operation\":\"$(_undo_escape "$op")\","
            json+="\"target\":\"$(_undo_escape "$target")\",\"inverse\":\"$(_undo_escape "$inverse")\","
            json+="\"backup\":\"$(_undo_escape "$backup")\",\"description\":\"$(_undo_escape "$desc")\"}"
        done
        _undo_output "${json}]"
    else
        (( stack_size == 0 )) && { printf 'Undo history is empty.\n'; return 0; }
        printf '%-6s %-12s %-10s %-30s %s\n' "STEP" "TIMESTAMP" "OPERATION" "TARGET" "DESCRIPTION"
        printf '%-6s %-12s %-10s %-30s %s\n' "----" "---------" "---------" "------" "-----------"
        local i; for (( i = 0; i < stack_size; i++ )); do
            local entry="${_MAINFRAME_UNDO_STACK[$i]}"
            local step ts op target desc
            step=$(_undo_get_field "$entry" 0); ts=$(_undo_get_field "$entry" 1)
            op=$(_undo_get_field "$entry" 2); target=$(_undo_get_field "$entry" 3)
            desc=$(_undo_get_field "$entry" 7)
            [[ ${#target} -gt 30 ]] && target="${target:0:27}..."
            printf '%-6s %-12s %-10s %-30s %s\n' "$step" "$ts" "$op" "$target" "$desc"
        done
    fi
}

# @pre: none
# @post: preview printed (no state changes)
# @returns: 0
mainframe_undo_peek() {
    local count="${1:-1}"
    local stack_size=${#_MAINFRAME_UNDO_STACK[@]}
    (( stack_size == 0 )) && { printf 'Nothing to undo.\n'; return 0; }
    (( count > stack_size )) && count=$stack_size
    printf 'Pending undo operations (%d):\n' "$count"
    local n; for (( n = 0; n < count; n++ )); do
        local idx=$(( stack_size - 1 - n ))
        local entry="${_MAINFRAME_UNDO_STACK[$idx]}"
        local op target inverse extra desc
        op=$(_undo_get_field "$entry" 2); target=$(_undo_get_field "$entry" 3)
        inverse=$(_undo_get_field "$entry" 4); extra=$(_undo_get_field "$entry" 6)
        desc=$(_undo_get_field "$entry" 7)
        printf '  %d. [%s] %s -> %s' "$((n + 1))" "$op" "$target" "$inverse"
        [[ -n "$extra" ]] && printf ' (%s)' "$extra"
        printf '\n'
        [[ -n "$desc" ]] && printf '     %s\n' "$desc"
    done
}

# @post: stack and backups cleared  @returns: 0
mainframe_undo_clear() {
    _MAINFRAME_UNDO_STACK=(); _MAINFRAME_UNDO_COUNT=0
    rm -rf "${MAINFRAME_UNDO_DIR}/backups" 2>/dev/null
    mkdir -p "${MAINFRAME_UNDO_DIR}/backups" 2>/dev/null
    return 0
}

# @returns: 0 if undoable operations exist, 1 if empty
mainframe_undo_can_undo() { (( ${#_MAINFRAME_UNDO_STACK[@]} > 0 )); }

# @post: prints number of undoable steps
mainframe_undo_count() { printf '%d' "${#_MAINFRAME_UNDO_STACK[@]}"; }

# @post: prints total backup storage size in bytes
mainframe_undo_size() { _undo_backup_size; }

# =============================================================================
# PUBLIC API: MAINTENANCE
# =============================================================================

# @pre: undo system initialized
# @post: orphaned backup files removed, count printed
# @returns: 0
mainframe_undo_cleanup() {
    local backup_dir="${MAINFRAME_UNDO_DIR}/backups"
    [[ -d "$backup_dir" ]] || { printf '0'; return 0; }
    local -A referenced=()
    local i; for (( i = 0; i < ${#_MAINFRAME_UNDO_STACK[@]}; i++ )); do
        local h; h=$(_undo_get_field "${_MAINFRAME_UNDO_STACK[$i]}" 5)
        [[ -n "$h" ]] && referenced["$h"]=1
    done
    local removed=0 file
    for file in "$backup_dir"/*; do
        [[ -f "$file" ]] || continue
        [[ -z "${referenced[${file##*/}]:-}" ]] && rm -f "$file" 2>/dev/null && removed=$((removed + 1))
    done
    printf '%d' "$removed"
}

# =============================================================================
# TRACKED OPERATION WRAPPERS
# =============================================================================

# @pre: FILE path writable  @post: file written, previous backed up  @returns: 0/1
undo_write() {
    local file="$1" content="$2"
    [[ -z "$file" ]] && { _undo_output_error "E_ARG_MISSING" "undo_write: file required"; return 1; }
    mainframe_undo_record "write" "$file" "write ${file##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would write: $file"; return 0; }
    local dir="${file%/*}"; [[ "$dir" != "$file" ]] && mkdir -p "$dir" 2>/dev/null
    printf '%s' "$content" > "$file" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Write failed: $file"; return 1; }
}

# @pre: FILE exists or creatable  @post: content appended, size recorded  @returns: 0/1
undo_append() {
    local file="$1" content="$2"
    [[ -z "$file" ]] && { _undo_output_error "E_ARG_MISSING" "undo_append: file required"; return 1; }
    mainframe_undo_record "append" "$file" "append to ${file##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would append: $file"; return 0; }
    printf '%s' "$content" >> "$file" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Append failed: $file"; return 1; }
}

# @pre: PATH exists  @post: file removed, backup stored  @returns: 0/1
undo_rm() {
    local path="$1"
    [[ -z "$path" ]] && { _undo_output_error "E_ARG_MISSING" "undo_rm: path required"; return 1; }
    [[ -e "$path" ]] || { _undo_output_error "E_PATH_NOT_FOUND" "Not found: $path"; return 1; }
    mainframe_undo_record "delete" "$path" "delete ${path##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would remove: $path"; return 0; }
    rm -f "$path" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Remove failed: $path"; return 1; }
}

# @pre: SRC exists  @post: moved to DST, inverse recorded  @returns: 0/1
undo_mv() {
    local src="$1" dst="$2"
    [[ -z "$src" ]] || [[ -z "$dst" ]] && { _undo_output_error "E_ARG_MISSING" "undo_mv: src and dst required"; return 1; }
    [[ -e "$src" ]] || { _undo_output_error "E_PATH_NOT_FOUND" "Not found: $src"; return 1; }
    [[ "$MAINFRAME_UNDO_ENABLED" == "1" ]] && {
        mainframe_undo_init || return 1
        _undo_push "$(_undo_make_entry "move" "$dst" "move_back" "" "$src" "move ${src##*/} -> ${dst##*/}")"
    }
    _undo_is_dryrun && { _undo_log info "[dry-run] Would move: $src -> $dst"; return 0; }
    mv "$src" "$dst" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Move failed: $src -> $dst"; return 1; }
}

# @pre: SRC exists  @post: copied to DST, inverse deletes copy  @returns: 0/1
undo_cp() {
    local src="$1" dst="$2"
    [[ -z "$src" ]] || [[ -z "$dst" ]] && { _undo_output_error "E_ARG_MISSING" "undo_cp: src and dst required"; return 1; }
    [[ -e "$src" ]] || { _undo_output_error "E_PATH_NOT_FOUND" "Not found: $src"; return 1; }
    [[ "$MAINFRAME_UNDO_ENABLED" == "1" ]] && {
        mainframe_undo_init || return 1
        _undo_push "$(_undo_make_entry "copy" "$dst" "delete_copy" "" "$src" "copy ${src##*/} -> ${dst##*/}")"
    }
    _undo_is_dryrun && { _undo_log info "[dry-run] Would copy: $src -> $dst"; return 0; }
    cp -p "$src" "$dst" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Copy failed: $src -> $dst"; return 1; }
}

# @pre: PATH does not exist  @post: directory created, rmdir inverse  @returns: 0/1
undo_mkdir() {
    local path="$1"
    [[ -z "$path" ]] && { _undo_output_error "E_ARG_MISSING" "undo_mkdir: path required"; return 1; }
    [[ -d "$path" ]] && return 0
    mainframe_undo_record "mkdir" "$path" "mkdir ${path##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would mkdir: $path"; return 0; }
    mkdir -p "$path" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Mkdir failed: $path"; return 1; }
}

# @pre: PATH exists  @post: mode changed, original recorded  @returns: 0/1
undo_chmod() {
    local path="$1" mode="$2"
    if [[ "$1" =~ ^[0-7]{3,4}$ ]] && [[ -n "$2" ]]; then
        mode="$1"
        path="$2"
    fi
    [[ -z "$mode" ]] || [[ -z "$path" ]] && { _undo_output_error "E_ARG_MISSING" "undo_chmod: mode and path required"; return 1; }
    [[ -e "$path" ]] || { _undo_output_error "E_PATH_NOT_FOUND" "Not found: $path"; return 1; }
    mainframe_undo_record "chmod" "$path" "chmod $mode ${path##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would chmod $mode: $path"; return 0; }
    chmod "$mode" "$path" 2>/dev/null || { _undo_output_error "E_IO_WRITE" "Chmod failed: $path"; return 1; }
}

# @pre: FILE exists  @post: sed applied in-place, full backup stored  @returns: 0/1
undo_sed() {
    local file="$1" pattern="$2"
    if [[ ! -f "$file" ]] && [[ -f "$2" ]]; then
        pattern="$1"
        file="$2"
    fi
    [[ -z "$pattern" ]] || [[ -z "$file" ]] && { _undo_output_error "E_ARG_MISSING" "undo_sed: pattern and file required"; return 1; }
    [[ -f "$file" ]] || { _undo_output_error "E_PATH_NOT_FOUND" "Not found: $file"; return 1; }
    mainframe_undo_record "write" "$file" "sed '$pattern' ${file##*/}"
    _undo_is_dryrun && { _undo_log info "[dry-run] Would sed on: $file"; return 0; }
    local rc=0
    if sed --version 2>/dev/null | grep -q GNU; then sed -i "$pattern" "$file" 2>/dev/null; rc=$?
    else sed -i '' "$pattern" "$file" 2>/dev/null; rc=$?; fi
    [[ $rc -ne 0 ]] && { _undo_output_error "E_EXEC_FAILED" "sed failed: $file"; return 1; }
    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_UNDO_EXPORTS=(
    mainframe_undo_init
    mainframe_undo_record
    mainframe_undo
    mainframe_undo_show
    mainframe_undo_peek
    mainframe_undo_can_undo
    mainframe_undo_count
    mainframe_undo_size
    mainframe_undo_clear
    mainframe_undo_cleanup
    undo_write
    undo_append
    undo_rm
    undo_mv
    undo_cp
    undo_mkdir
    undo_chmod
    undo_sed
)

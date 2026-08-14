#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/host_lifecycle.sh - Managed-host acquisition and recovery
# =============================================================================
# This mutation boundary assembles only the exact SRI-pinned package closure
# already authorized by the trusted native-host manifest and package lock. The
# closure may come from an explicit offline directory or an explicit direct
# registry download. Neither path invokes npm, package lifecycle scripts, or
# vendor executables, and neither changes PATH, shell profiles, system CLIs,
# host configuration, or projects.
# =============================================================================

[[ -n "${_MAINFRAME_HOST_LIFECYCLE_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_HOST_LIFECYCLE_LOADED=1

declare -g _MAINFRAME_HOST_LIFECYCLE_LOCK=""
declare -g _MAINFRAME_HOST_LIFECYCLE_LOCK_IDENTITY=""
declare -g _MAINFRAME_HOST_LIFECYCLE_LOCK_OWNED=false
declare -g _MAINFRAME_HOST_LIFECYCLE_WORKSPACE=""
declare -g _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY=""
declare -g _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_PARENT_IDENTITY=""
declare -g _MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT=""
declare -g _MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY=""
declare -g _MAINFRAME_HOST_LIFECYCLE_PYTHON=""
declare -g _MAINFRAME_HOST_LIFECYCLE_OPERATION_PID=""
declare -g _MAINFRAME_HOST_LIFECYCLE_JSON=false
declare -g _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE="E_HOST_LIFECYCLE"
declare -g _MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND="host-install"
declare -g _MAINFRAME_HOST_LIFECYCLE_HOST=""
declare -g _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE="unspecified"
declare -g _MAINFRAME_HOST_LIFECYCLE_NETWORK_USED=false
declare -g _MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT=0
declare -g _MAINFRAME_HOST_LIFECYCLE_CHANGED=false
declare -g _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE="unchanged"
declare -g _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID=""
declare -g _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT=""
declare -g _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION=""
declare -g _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY=""
declare -g _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0

_mainframe_host_lifecycle_begin_terminal_output() {
    # Once a terminal result starts, do not let a late signal append a second
    # result or change the process status after success has been reported. The
    # lifecycle entrypoints run in subshells, so this disposition is bounded to
    # the current transaction.
    trap '' INT TERM
}

_mainframe_host_lifecycle_usage() {
    _mainframe_host_lifecycle_begin_terminal_output
    cat <<'EOF'
Usage:
  mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]
  mainframe host remove HOST [--dry-run | --yes] [--json]
  mainframe host restore HOST --quarantine-id removed.<18-hex> [--dry-run | --yes] [--json]

Offline form: mainframe host install HOST --package-dir DIR [--dry-run | --yes] [--json]

Managed lifecycle hosts: codex, claude-code, copilot
Recognized but not installable: gemini

Install assembles the current certified host from the exact npm tarballs named
by MAINFRAME's package lock. --download makes direct HTTPS requests only to the
locked registry.npmjs.org URLs. --package-dir uses a local, already-populated
directory and stays offline. Neither source invokes npm, package scripts, or a
vendor executable.

Remove authenticates only the current deterministic generation, then atomically
moves it into a private same-filesystem quarantine. It does not purge bytes or
touch stale/sibling generations. Corrupt targets are refused.

Restore requires one exact generated quarantine ID, authenticates that current
generation again, and atomically republishes the same directory only when the
active deterministic target is absent. Restore is strictly offline and never
selects "latest", a path, a glob, or an implicit quarantine entry.

Mutation requires --yes, or an affirmative interactive --download prompt.
--dry-run performs complete authentication and staging without creating or
changing the managed root; with --download it does use the network. JSON output
is path-redacted and never prompts. A noninteractive request that reaches an
actionable install, remove, or restore requires --dry-run or --yes; a safe
no-op, refusal, or validation error may return before that consent boundary.
EOF
}

_mainframe_host_lifecycle_error() {
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" != true ]]; then
        _mainframe_host_error "$*"
    fi
}

_mainframe_host_lifecycle_set_error() {
    local code="$1"
    shift
    [[ "$code" =~ ^E_[A-Z0-9_]+$ ]] || code=E_HOST_LIFECYCLE
    _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE="$code"
    _mainframe_host_lifecycle_error "$*"
}

_mainframe_host_lifecycle_usage_error() {
    _mainframe_host_lifecycle_set_error E_USAGE "$*"
    return 2
}

_mainframe_host_lifecycle_error_message() {
    case "${1:-E_HOST_LIFECYCLE}" in
        E_SOURCE_REQUIRED) printf 'exactly one package source is required\n' ;;
        E_SOURCE_CONFLICT) printf 'package sources are mutually exclusive\n' ;;
        E_CONSENT) printf 'managed-host mutation requires explicit consent\n' ;;
        E_NETWORK_CONSENT) printf 'online acquisition requires explicit action consent\n' ;;
        E_HOST_UNSUPPORTED) printf 'managed host is unsupported or gated\n' ;;
        E_NETWORK_POLICY) printf 'online acquisition policy rejected the request\n' ;;
        E_NETWORK_TRANSFER) printf 'registry transfer failed within the closed network policy\n' ;;
        E_DOWNLOAD_LIMIT) printf 'registry response exceeded an acquisition bound\n' ;;
        E_PACKAGE_INTEGRITY) printf 'package integrity did not match the trusted lock\n' ;;
        E_PACKAGE_ARCHIVE) printf 'package archive failed bounded authentication or extraction\n' ;;
        E_RUNTIME) printf 'a reviewed acquisition runtime is unavailable\n' ;;
        E_QUARANTINE_ID) printf 'quarantine ID is malformed or unsupported\n' ;;
        E_QUARANTINE_NOT_FOUND) printf 'the exact quarantine generation was not found\n' ;;
        E_QUARANTINE_CORRUPT) printf 'the exact quarantine generation failed authentication\n' ;;
        E_TARGET_PRESENT) printf 'the active managed target is already present\n' ;;
        E_INTERRUPTED) printf 'managed-host lifecycle operation was interrupted\n' ;;
        E_STATE) printf 'managed-host state changed or is unsafe\n' ;;
        E_USAGE) printf 'managed-host command arguments are invalid\n' ;;
        *) printf 'managed-host lifecycle operation failed closed\n' ;;
    esac
}

_mainframe_host_lifecycle_emit_error_json() {
    _mainframe_host_lifecycle_begin_terminal_output
    local code="${_MAINFRAME_HOST_LIFECYCLE_ERROR_CODE:-E_HOST_LIFECYCLE}"
    local public_code message source
    message="$(_mainframe_host_lifecycle_error_message "$code")" || return 1
    case "$code" in
        E_SOURCE_REQUIRED) public_code='source-required' ;;
        E_SOURCE_CONFLICT) public_code='source-conflict' ;;
        E_CONSENT) public_code='consent-required' ;;
        E_NETWORK_CONSENT) public_code='consent-required' ;;
        E_HOST_UNSUPPORTED) public_code='host-unsupported' ;;
        E_NETWORK_POLICY) public_code='network-policy' ;;
        E_NETWORK_TRANSFER) public_code='network-transfer' ;;
        E_DOWNLOAD_LIMIT) public_code='download-limit' ;;
        E_PACKAGE_INTEGRITY) public_code='package-integrity' ;;
        E_PACKAGE_ARCHIVE) public_code='package-archive' ;;
        E_RUNTIME) public_code='runtime-unavailable' ;;
        E_QUARANTINE_ID) public_code='quarantine-id-invalid' ;;
        E_QUARANTINE_NOT_FOUND) public_code='quarantine-not-found' ;;
        E_QUARANTINE_CORRUPT) public_code='quarantine-corrupt' ;;
        E_TARGET_PRESENT) public_code='target-present' ;;
        E_INTERRUPTED) public_code='interrupted' ;;
        E_STATE) public_code='unsafe-state' ;;
        E_USAGE) public_code='usage' ;;
        *) public_code='lifecycle-failed' ;;
    esac
    case "$_MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE" in
        online-registry) source=download ;;
        offline-package-dir) source=package-dir ;;
        conflict) source=conflict ;;
        *) source="" ;;
    esac
    _mainframe_enforce_bind_jq "${MAINFRAME_ROOT:-}" \
        "${_MAINFRAME_HOST_DISCOVERY_PATH:-${PATH:-}}" >/dev/null 2>&1 || return 1
    _mainframe_enforce_jq -n \
        --arg command "$_MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND" \
        --arg host "$_MAINFRAME_HOST_LIFECYCLE_HOST" \
        --arg source "$source" \
        --arg code "$public_code" \
        --arg message "$message" \
        --arg mutation_state "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" \
        --argjson changed "$_MAINFRAME_HOST_LIFECYCLE_CHANGED" \
        --argjson network_attempted "$_MAINFRAME_HOST_LIFECYCLE_NETWORK_USED" \
        --argjson archive_count "$_MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT" \
        --arg quarantine "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID" '
      {
        schema_version: 1,
        command: $command,
        host: (if $host == "" then null else $host end),
        result: "error",
        changed: (if $mutation_state == "uncertain" then null else $changed end),
        mutation_state: $mutation_state,
        source: (if $command != "host-install" or $source == "" then null else $source end),
        network_attempted: $network_attempted,
        archive_count: $archive_count,
        quarantine_id: (
          if ($command == "host-remove" or $command == "host-restore") and
             $quarantine != ""
          then $quarantine else null end
        ),
        error: {code: $code, message: $message}
      }
    '
}

_mainframe_host_lifecycle_find_bin() {
    local name="$1" candidate
    for candidate in "/usr/bin/$name" "/bin/$name"; do
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

_mainframe_host_lifecycle_python() {
    local candidate resolved owner mode numeric
    for candidate in \
        /usr/bin/python3 \
        /bin/python3 \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3; do
        [[ -x "$candidate" ]] || continue
        resolved="$(_mainframe_launch_resolve_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        case "$resolved" in
            /usr/bin/python3|/usr/bin/python3.[0-9]*|\
            /bin/python3|/bin/python3.[0-9]*|\
            /usr/local/bin/python3|/usr/local/bin/python3.[0-9]*|\
            /opt/homebrew/Cellar/python@*/[0-9]*/Frameworks/Python.framework/Versions/*/bin/python3*|\
            /opt/homebrew/Cellar/python@*/[0-9]*/bin/python3*|\
            /usr/local/Cellar/python@*/[0-9]*/Frameworks/Python.framework/Versions/*/bin/python3*|\
            /usr/local/Cellar/python@*/[0-9]*/bin/python3*|\
            /home/linuxbrew/.linuxbrew/Cellar/python@*/[0-9]*/bin/python3*) ;;
            *) continue ;;
        esac
        [[ -f "$resolved" && ! -L "$resolved" ]] || continue
        read -r owner mode < <(_mainframe_host_stat_owner_mode "$resolved") || continue
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || continue
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
           (numeric & 0100) != 0 )) || continue
        _mainframe_host_no_write_acl "$resolved" || continue
        if /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
            "$resolved" -I -S -B -c '
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
' >/dev/null 2>&1; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

_mainframe_host_lifecycle_probe_managed() {
    local host="$1" project="$2"
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
        _mainframe_host_probe_managed "$host" "$project" >/dev/null 2>&1 || true
    else
        _mainframe_host_probe_managed "$host" "$project" || true
    fi
}

_mainframe_host_lifecycle_authenticate_generation() {
    local host="$1" generation="$2"
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
        _mainframe_host_authenticate_generation "$host" "$generation" \
            >/dev/null 2>&1
    else
        _mainframe_host_authenticate_generation "$host" "$generation"
    fi
}

_mainframe_host_lifecycle_cleanup_lock() {
    [[ "$_MAINFRAME_HOST_LIFECYCLE_LOCK_OWNED" == true ]] || return 0
    _mainframe_host_lifecycle_fs lock-release \
        "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT" \
        "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY" \
        "${_MAINFRAME_HOST_LIFECYCLE_LOCK##*/}" \
        "$_MAINFRAME_HOST_LIFECYCLE_LOCK_IDENTITY" "$$" || {
        _mainframe_host_lifecycle_error \
            'managed-host lifecycle lock release failed; no success result was emitted'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_LOCK_OWNED=false
    _MAINFRAME_HOST_LIFECYCLE_LOCK=""
    _MAINFRAME_HOST_LIFECYCLE_LOCK_IDENTITY=""
}

_mainframe_host_lifecycle_acquire_lock() {
    local runtime_root="$1" lock root_identity lock_identity
    local lock_status=0 pending_signal=0 lock_identity_valid=false
    lock="$runtime_root/.lifecycle-lock"
    root_identity="$(_mainframe_host_stat_identity "$runtime_root")" || return 1
    [[ "$root_identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1

    # Bash can run a pending trap immediately after the command substitution
    # returns but before these ownership globals are assigned. Defer signals
    # across that narrow publication window so an acquired lock is always
    # tracked before the ordinary signal handler attempts cleanup.
    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    trap '_mainframe_host_lifecycle_defer_signal 130' INT
    trap '_mainframe_host_lifecycle_defer_signal 143' TERM
    lock_identity="$(_mainframe_host_lifecycle_fs lock-acquire \
        "$runtime_root" "$root_identity" "${lock##*/}" "$$")" || lock_status=$?
    if [[ "$lock_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
        _MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY="$root_identity"
        _MAINFRAME_HOST_LIFECYCLE_LOCK="$lock"
        _MAINFRAME_HOST_LIFECYCLE_LOCK_IDENTITY="$lock_identity"
        _MAINFRAME_HOST_LIFECYCLE_LOCK_OWNED=true
        lock_identity_valid=true
    elif [[ "$lock_status" -eq 0 ]]; then
        lock_status=1
    fi
    if [[ "$lock_identity_valid" != true &&
          "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" == unchanged ]]; then
        # Without an authenticated identity record, the shell cannot prove
        # whether the helper created state or whether its rollback completed.
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    fi

    trap '_mainframe_host_lifecycle_on_signal 130' INT
    trap '_mainframe_host_lifecycle_on_signal 143' TERM
    pending_signal="$_MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL"
    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    if [[ "$pending_signal" -eq 130 || "$pending_signal" -eq 143 ]]; then
        _mainframe_host_lifecycle_on_signal "$pending_signal"
    fi
    [[ "$lock_status" -eq 0 && "$lock_identity_valid" == true ]]
}

_mainframe_host_lifecycle_defer_signal() {
    local status="${1:-130}"
    [[ "$status" -eq 130 || "$status" -eq 143 ]] || status=130
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL" -eq 0 ]]; then
        _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL="$status"
    fi
}

_mainframe_host_lifecycle_cleanup_workspace() {
    local workspace="$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE" parent leaf temp_parent
    [[ -n "$workspace" && -n "$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY" &&
       -n "$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE_PARENT_IDENTITY" ]] || return 0
    [[ -d "$workspace" && ! -L "$workspace" ]] || {
        _mainframe_host_lifecycle_error \
            'lifecycle workspace disappeared or changed type before cleanup'
        return 1
    }
    parent="${workspace%/*}"
    leaf="${workspace##*/}"
    temp_parent="$(cd /tmp 2>/dev/null && pwd -P)" || return 1
    if [[ "$parent" == "$temp_parent" && "$leaf" == mainframe-host-stage.* ]]; then
        :
    elif [[ "$parent" == "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT" &&
            "$leaf" == .install-stage.* ]]; then
        :
    else
        _mainframe_host_lifecycle_error \
            'refusing to clean an unexpected lifecycle workspace'
        return 1
    fi
    _mainframe_host_lifecycle_fs cleanup \
        "$parent" "$leaf" \
        "$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE_PARENT_IDENTITY" \
        "$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY" || {
        _mainframe_host_lifecycle_error \
            'lifecycle workspace cleanup failed; no success result was emitted'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_WORKSPACE=""
    _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY=""
    _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_PARENT_IDENTITY=""
}

_mainframe_host_lifecycle_cleanup() {
    local failed=false
    _mainframe_host_lifecycle_cleanup_workspace || failed=true
    _mainframe_host_lifecycle_cleanup_lock || failed=true
    [[ "$failed" == false ]]
}

_mainframe_host_lifecycle_note_cleanup_failure() {
    _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_HOST_LIFECYCLE
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" == unchanged ]]; then
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    fi
}

_mainframe_host_lifecycle_recovery_guidance() {
    [[ "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" != unchanged &&
       -n "$_MAINFRAME_HOST_LIFECYCLE_HOST" ]] || return 0
    case "$_MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND" in
        host-install)
            printf 'The install outcome could not be proved. Inspect first: mainframe host status %s --runtime managed\n' \
                "$_MAINFRAME_HOST_LIFECYCLE_HOST" >&2
            return 0
            ;;
        host-remove|host-restore) ;;
        *) return 0 ;;
    esac
    [[ "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID" =~ ^removed\.[0-9a-f]{18}$ ]] || {
        printf 'The lifecycle outcome could not be proved. Inspect first: mainframe host status %s --runtime managed\n' \
            "$_MAINFRAME_HOST_LIFECYCLE_HOST" >&2
        return 0
    }
    printf 'Recovery ID: %s\n' \
        "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID" >&2
    printf 'Inspect first: mainframe host status %s --runtime managed\n' \
        "$_MAINFRAME_HOST_LIFECYCLE_HOST" >&2
    printf 'If the active target is absent, preview recovery with: mainframe host restore %s --quarantine-id %s --dry-run\n' \
        "$_MAINFRAME_HOST_LIFECYCLE_HOST" \
        "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID" >&2
}

_mainframe_host_lifecycle_finalize_failure() {
    local status="${1:-1}"
    if ! _mainframe_host_lifecycle_cleanup; then
        _mainframe_host_lifecycle_note_cleanup_failure
        status=1
    fi
    _mainframe_host_lifecycle_begin_terminal_output
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
        _mainframe_host_lifecycle_emit_error_json || status=1
    else
        _mainframe_host_lifecycle_recovery_guidance
    fi
    return "$status"
}

_mainframe_host_lifecycle_on_signal() {
    local status="${1:-130}" cleanup_failed=false
    trap - EXIT
    trap '' INT TERM
    _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_INTERRUPTED
    if ! _mainframe_host_lifecycle_cleanup; then
        _mainframe_host_lifecycle_note_cleanup_failure
        cleanup_failed=true
    fi
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
        _mainframe_host_lifecycle_emit_error_json || true
    else
        if [[ "$cleanup_failed" == true ]]; then
            _mainframe_host_error \
                'managed-host lifecycle operation was interrupted and cleanup could not be authenticated'
        else
            _mainframe_host_error \
                'managed-host lifecycle operation was interrupted; no success result was emitted'
        fi
        _mainframe_host_lifecycle_recovery_guidance
    fi
    exit "$status"
}

_mainframe_host_lifecycle_on_exit() {
    local status=$?
    trap - EXIT
    trap '' INT TERM
    _mainframe_host_lifecycle_cleanup || true
    exit "$status"
}

_mainframe_host_lifecycle_create_private_path() {
    local path="$1" parents="$2" status=0 pending_signal=0

    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    trap '_mainframe_host_lifecycle_defer_signal 130' INT
    trap '_mainframe_host_lifecycle_defer_signal 143' TERM
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" == unchanged ]]; then
        # mkdir can fail after creating only part of a -p path. Until its
        # bounded result is known, claiming no mutation would be unsafe.
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    fi
    if [[ "$parents" == true ]]; then
        (
            trap '' INT TERM
            umask 077
            exec /bin/mkdir -p -- "$path"
        ) || status=$?
    else
        (
            trap '' INT TERM
            umask 077
            exec /bin/mkdir -- "$path"
        ) || status=$?
    fi
    if [[ "$status" -eq 0 ]]; then
        _MAINFRAME_HOST_LIFECYCLE_CHANGED=true
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=changed
    fi

    trap '_mainframe_host_lifecycle_on_signal 130' INT
    trap '_mainframe_host_lifecycle_on_signal 143' TERM
    pending_signal="$_MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL"
    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    if [[ "$pending_signal" -eq 130 || "$pending_signal" -eq 143 ]]; then
        _mainframe_host_lifecycle_on_signal "$pending_signal"
    fi
    [[ "$status" -eq 0 ]]
}

_mainframe_host_lifecycle_create_runtime_root() {
    local data_home="$1" runtime_root="$2" data_home_existed=false runtime_existed=false
    [[ -e "$data_home" || -L "$data_home" ]] && data_home_existed=true
    [[ -e "$runtime_root" || -L "$runtime_root" ]] && runtime_existed=true

    _mainframe_host_trusted_ancestry "$data_home" || {
        _mainframe_host_lifecycle_error 'XDG data home has unsafe ownership, permissions, or ancestry'
        return 1
    }
    if [[ "$data_home_existed" == true ]]; then
        [[ -d "$data_home" && ! -L "$data_home" ]] || return 1
        _mainframe_host_owned_private "$data_home" || return 1
    else
        _mainframe_host_lifecycle_create_private_path "$data_home" true || return 1
        /bin/chmod 700 "$data_home" || return 1
    fi
    _mainframe_host_no_symlink_ancestry "$runtime_root" || return 1
    if [[ "$runtime_existed" == true ]]; then
        [[ -d "$runtime_root" && ! -L "$runtime_root" ]] || return 1
        _mainframe_host_owned_private "$runtime_root" 700 || return 1
    else
        _mainframe_host_lifecycle_create_private_path "$runtime_root" true || return 1
        /bin/chmod 700 "$runtime_root" || return 1
    fi
    _mainframe_host_trusted_ancestry "$data_home" || return 1
    _mainframe_host_private_directory_chain "$data_home" "$runtime_root" || return 1
    _mainframe_host_no_nested_mounts "$data_home" "$runtime_root" || return 1
    _mainframe_host_owned_private "$runtime_root" 700
}

_mainframe_host_lifecycle_prepare() {
    local host="$1" project discovery_path runtime_root data_home
    project="${MAINFRAME_ROOT:-}"
    [[ "$project" == /* && -d "$project" ]] || {
        _mainframe_host_lifecycle_error 'MAINFRAME_ROOT is not a safe absolute directory'
        return 1
    }
    discovery_path="${_MAINFRAME_HOST_DISCOVERY_PATH:-${PATH:-}}"
    _mainframe_enforce_bind_jq "$project" "$discovery_path" || {
        _mainframe_host_lifecycle_error \
            "trusted host metadata is unavailable: ${_MAINFRAME_ENFORCE_BIND_ERROR:-jq binding failed}"
        return 1
    }
    _mainframe_host_platform_policy_valid || {
        _mainframe_host_lifecycle_error 'release-platform policy is missing, malformed, ambiguous, or unsafe'
        return 1
    }
    _mainframe_host_prepare_expected "$host" || {
        _mainframe_host_lifecycle_error \
            "${_MAINFRAME_HOST_EXPECTED_ERROR:-managed host metadata is invalid}"
        return 1
    }
    [[ "$_MAINFRAME_HOST_EXPECTED_SUPPORTED" == true ]] || {
        _mainframe_host_lifecycle_set_error E_HOST_UNSUPPORTED \
            "managed $host lifecycle is unsupported: $_MAINFRAME_HOST_EXPECTED_ERROR"
        return 1
    }
    runtime_root="$(_mainframe_host_runtime_root)" || return 1
    data_home="$(_mainframe_host_data_home)" || return 1
    if _mainframe_host_path_within "$project" "$runtime_root"; then
        _mainframe_host_lifecycle_error 'managed payload root resolves inside MAINFRAME_ROOT'
        return 1
    fi
    _mainframe_host_trusted_ancestry "$data_home" || {
        _mainframe_host_lifecycle_error 'XDG data home has unsafe ownership, permissions, or ancestry'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT="$runtime_root"
}

_mainframe_host_lifecycle_validate_quarantine_generation() {
    local host="$1" quarantine_id="$2"
    local runtime_root="$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT" data_home
    local quarantine_root version_root platform_root bundle_root slot generation
    local directory generation_identity

    data_home="$(_mainframe_host_data_home)" || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'managed data home is unavailable or unsafe'
        return 1
    }
    quarantine_root="$runtime_root/quarantine"
    version_root="$quarantine_root/v1/$host/$_MAINFRAME_HOST_EXPECTED_VERSION"
    platform_root="$version_root/$_MAINFRAME_HOST_EXPECTED_PLATFORM"
    bundle_root="$platform_root/$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID"
    slot="$bundle_root/$quarantine_id"
    generation="$slot/generation"
    [[ "$runtime_root" != / && "$runtime_root" == "$data_home"/* &&
       "$slot" == "$runtime_root/quarantine/v1/$host/"* &&
       "$generation" == "$slot/generation" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'derived quarantine location escaped the managed root'
        return 1
    }

    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT="$slot"
    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION="$generation"
    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY=""
    if [[ ! -e "$slot" && ! -L "$slot" ]]; then
        _mainframe_host_lifecycle_set_error E_QUARANTINE_NOT_FOUND \
            'the exact quarantine slot does not exist'
        return 1
    fi
    if [[ -L "$slot" || ! -d "$slot" ||
          ! -e "$generation" || -L "$generation" || ! -d "$generation" ]]; then
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'the exact quarantine slot is missing its real generation directory'
        return 1
    fi
    _mainframe_host_no_symlink_ancestry "$generation" || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantine ancestry contains a symbolic link or unsafe component'
        return 1
    }
    _mainframe_host_private_directory_chain "$data_home" "$generation" || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantine ancestry has unsafe ownership, modes, or filesystem identity'
        return 1
    }
    _mainframe_host_no_nested_mounts "$data_home" "$generation" || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantine ancestry crosses an unsafe nested mount'
        return 1
    }
    for directory in \
        "$runtime_root" \
        "$quarantine_root" \
        "$quarantine_root/v1" \
        "$quarantine_root/v1/$host" \
        "$version_root" \
        "$platform_root" \
        "$bundle_root" \
        "$slot" \
        "$generation"; do
        [[ -d "$directory" && ! -L "$directory" ]] &&
            _mainframe_host_owned_private "$directory" 700 || {
            _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
                'quarantine directories are not exact owner-only mode 0700'
            return 1
        }
    done
    _mainframe_host_directory_children_exact "$slot" generation || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantine slot does not contain exactly one generation'
        return 1
    }
    _mainframe_host_lifecycle_authenticate_generation "$host" "$generation" || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantined generation receipt or complete payload is not current'
        return 1
    }
    generation_identity="$(_mainframe_host_stat_identity "$generation")" || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_CORRUPT \
            'quarantined generation identity is unavailable'
        return 1
    }
    [[ "$generation_identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY="$generation_identity"
}

_mainframe_host_lifecycle_resolve_package_dir() {
    local requested="$1" resolved
    [[ -n "$requested" && "$requested" != -* && "$requested" != *$'\n'* &&
       "$requested" != *$'\r'* && "$requested" != *$'\t'* ]] || return 1
    [[ "$requested" == /* ]] || requested="$PWD/$requested"
    [[ -d "$requested" && ! -L "$requested" ]] || return 1
    resolved="$(cd -- "$requested" 2>/dev/null && pwd -P)" || return 1
    [[ "$resolved" != / && -d "$resolved" && ! -L "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
}

_mainframe_host_lifecycle_archive_basename() {
    local resolved="$1" basename
    basename="${resolved##*/}"
    [[ "$basename" =~ ^[A-Za-z0-9._+-]+\.tgz$ ]] || return 1
    printf '%s\n' "$basename"
}

_mainframe_host_lifecycle_archive_source_safe() {
    local source="$1" size
    [[ -f "$source" && ! -L "$source" ]] || return 1
    [[ "$(_mainframe_host_link_count "$source")" == 1 ]] || return 1
    size="$(/usr/bin/wc -c < "$source" 2>/dev/null)" || return 1
    size="${size//[[:space:]]/}"
    [[ "$size" =~ ^[1-9][0-9]*$ && "$size" -le 536870912 ]]
}

_mainframe_host_lifecycle_extract_package() {
    local python="$1" archive="$2" destination="$3" integrity="$4"
    local package_name="$5" package_version="$6" extractor helper_error
    extractor="${MAINFRAME_ROOT:-}/scripts/dev/native-host/extract-managed-package.py"
    [[ -f "$extractor" && ! -L "$extractor" && -r "$extractor" ]] || {
        _mainframe_host_lifecycle_error 'managed-package extractor is missing or unsafe'
        return 1
    }
    if helper_error="$(/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
        PYTHONNOUSERSITE=1 PYTHONSAFEPATH=1 \
        "$python" -I -S -B "$extractor" \
        "$archive" "$destination" "$integrity" "$package_name" "$package_version" \
        2>&1)"; then
        [[ -z "$helper_error" ]] || {
            _mainframe_host_lifecycle_set_error E_PACKAGE_ARCHIVE \
                'managed-package extractor produced an unexpected result'
            return 1
        }
        return 0
    fi
    _mainframe_host_lifecycle_set_error E_PACKAGE_ARCHIVE \
        'managed package failed integrity or bounded archive authentication'
    return 1
}

_mainframe_host_lifecycle_acquire_package() {
    local python="$1" url="$2" scratch="$3" scratch_identity="$4"
    local destination="$5" destination_identity="$6" integrity="$7"
    local package_name="$8" package_version="$9"
    local helper helper_error code=E_NETWORK_TRANSFER message

    helper="${MAINFRAME_ROOT:-}/scripts/dev/native-host/acquire-managed-package.py"
    [[ -f "$helper" && ! -L "$helper" && -r "$helper" ]] || {
        _mainframe_host_lifecycle_set_error E_RUNTIME \
            'managed-package acquisition helper is missing or unsafe'
        return 1
    }

    # The helper receives a completely closed environment: ambient proxy,
    # registry, CA, Python, curl, npm, and package-manager configuration cannot
    # influence this direct registry request.
    _MAINFRAME_HOST_LIFECYCLE_NETWORK_USED=true
    if helper_error="$(/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
        PYTHONNOUSERSITE=1 PYTHONSAFEPATH=1 \
        "$python" -I -S -B "$helper" \
        "$url" "$scratch" "$scratch_identity" \
        "$destination" "$destination_identity" "$integrity" \
        "$package_name" "$package_version" 2>&1)"; then
        [[ -z "$helper_error" ]] || {
            _mainframe_host_lifecycle_set_error E_NETWORK_TRANSFER \
                'managed-package acquisition produced an unexpected result'
            return 1
        }
        return 0
    fi

    # Only finite helper codes may cross the Python/shell boundary. Never relay
    # exception text, local paths, registry URLs, peer addresses, or headers.
    case "$helper_error" in
        'managed package acquisition failed: '*)
            helper_error="${helper_error#managed package acquisition failed: }"
            ;;
    esac
    [[ "$helper_error" =~ ^[a-z0-9-]+$ ]] || helper_error=transfer-failed
    case "$helper_error" in
        *integrity*|*sri*)
            code=E_PACKAGE_INTEGRITY
            message='downloaded package did not match the trusted package lock'
            ;;
        *extractor*)
            code=E_RUNTIME
            message='managed-package extractor failed its runtime trust policy'
            ;;
        *archive*|*extract*|*package-identity*)
            code=E_PACKAGE_ARCHIVE
            message='downloaded package failed bounded archive authentication'
            ;;
        *size*|*limit*|*large*)
            code=E_DOWNLOAD_LIMIT
            message='registry transfer exceeded a bounded acquisition limit'
            ;;
        *url*|*peer*|*dns*|*policy*|*redirect*|*encoding*|*response*)
            code=E_NETWORK_POLICY
            message='registry request was rejected by the closed acquisition policy'
            ;;
        *scratch*|*destination*|*identity-changed*)
            code=E_STATE
            message='private acquisition state changed or failed its identity policy'
            ;;
        *)
            message='direct registry transfer failed closed'
            ;;
    esac
    _mainframe_host_lifecycle_set_error "$code" "$message"
    return 1
}

_mainframe_host_lifecycle_fs() {
    local helper operation_pid
    helper="${MAINFRAME_ROOT:-}/scripts/dev/native-host/managed-host-fs.py"
    [[ -n "$_MAINFRAME_HOST_LIFECYCLE_PYTHON" &&
       -f "$helper" && ! -L "$helper" && -r "$helper" ]] || {
        _mainframe_host_lifecycle_error \
            'managed-host filesystem helper is missing or unsafe'
        return 1
    }
    operation_pid="${_MAINFRAME_HOST_LIFECYCLE_OPERATION_PID:-$$}"
    [[ "$operation_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
        (
            # INT/TERM are owned by the transaction process. A terminal
            # process-group signal must not kill this bounded helper between a
            # filesystem mutation and its authenticated identity result.
            trap '' INT TERM
            exec /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
                PYTHONNOUSERSITE=1 PYTHONSAFEPATH=1 \
                MAINFRAME_HOST_LIFECYCLE_PID="$operation_pid" \
                "$_MAINFRAME_HOST_LIFECYCLE_PYTHON" -I -S -B "$helper" "$@"
        ) 2>/dev/null
    else
        (
            trap '' INT TERM
            exec /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
                PYTHONNOUSERSITE=1 PYTHONSAFEPATH=1 \
                MAINFRAME_HOST_LIFECYCLE_PID="$operation_pid" \
                "$_MAINFRAME_HOST_LIFECYCLE_PYTHON" -I -S -B "$helper" "$@"
        )
    fi
}

_mainframe_host_lifecycle_write_receipt() {
    local host="$1" generation="$2" manifest lock manifest_sha lock_sha temporary
    manifest="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hosts.json"
    lock="${MAINFRAME_ROOT:-}/scripts/dev/native-host/package-lock.json"
    manifest_sha="$(_mainframe_host_sha256_file "$manifest")" || return 1
    lock_sha="$(_mainframe_host_sha256_file "$lock")" || return 1
    temporary="$(/usr/bin/mktemp "$generation/.receipt.XXXXXX")" || return 1
    if ! _mainframe_enforce_jq -n \
        --arg bundle_id "$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID" \
        --arg mainframe_version "${MAINFRAME_VERSION:-}" \
        --arg host "$host" \
        --arg version "$_MAINFRAME_HOST_EXPECTED_VERSION" \
        --arg platform "$_MAINFRAME_HOST_EXPECTED_PLATFORM" \
        --arg manifest_sha "$manifest_sha" \
        --arg lock_sha "$lock_sha" \
        --arg package_set_sha "$_MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA" \
        --arg tree_root "$_MAINFRAME_HOST_EXPECTED_TREE_ROOT" \
        --arg tree_sha "$_MAINFRAME_HOST_EXPECTED_TREE_SHA" \
        --arg executable "$_MAINFRAME_HOST_EXPECTED_EXECUTABLE" \
        --arg executable_sha "$_MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA" '
      {
        schema_version: 1,
        kind: "mainframe-managed-host-payload",
        bundle_id: $bundle_id,
        mainframe_version: $mainframe_version,
        host: $host,
        host_version: $version,
        platform: $platform,
        hosts_manifest_sha256: $manifest_sha,
        package_lock_sha256: $lock_sha,
        package_set_sha256: $package_set_sha,
        tree_root: $tree_root,
        tree_sha256: $tree_sha,
        executable: $executable,
        executable_sha256: $executable_sha,
        launch_mode: "direct-native"
      }
    ' > "$temporary"; then
        /bin/rm -f -- "$temporary"
        return 1
    fi
    /bin/chmod 600 "$temporary" || return 1
    /bin/mv -- "$temporary" "$generation/receipt.json" || return 1
}

_mainframe_host_lifecycle_normalize_payload() {
    local payload="$1" find_bin
    [[ -d "$payload" && ! -L "$payload" ]] || return 1
    find_bin="$(_mainframe_host_lifecycle_find_bin find)" || return 1
    "$find_bin" "$payload" -type d -exec /bin/chmod 500 {} + || return 1
    "$find_bin" "$payload" -type f -exec /bin/chmod 500 {} + || return 1
}

_mainframe_host_lifecycle_assemble() {
    local host="$1" source_mode="$2" package_dir="$3" workspace="$4" python="$5"
    local generation="$workspace/generation"
    local plan lock_path package_name package_version resolved integrity basename
    local source destination destination_identity scratch="" scratch_identity=""
    local expected_count=0 extracted_count=0 target_before bundle_before
    local -A seen_basenames=()

    target_before="$_MAINFRAME_HOST_EXPECTED_TARGET"
    bundle_before="$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID"
    plan="$(_mainframe_host_package_plan "$host" "$_MAINFRAME_HOST_EXPECTED_PLATFORM")" || {
        _mainframe_host_lifecycle_error 'could not derive the exact certified package set'
        return 1
    }
    ( umask 077; /bin/mkdir -p -- "$generation/payload" ) || return 1
    /bin/chmod 700 "$generation" "$generation/payload" || return 1

    # Validate the entire closed package plan before extracting or making the
    # first network request. Each source path then uses one stable descriptor
    # through SRI verification and bounded extraction.
    while IFS=$'\t' read -r lock_path package_name package_version resolved integrity; do
        [[ -n "$lock_path" && -n "$package_name" && -n "$package_version" &&
           -n "$resolved" && -n "$integrity" ]] || return 1
        basename="$(_mainframe_host_lifecycle_archive_basename "$resolved")" || {
            _mainframe_host_lifecycle_error "locked package URL has an unsafe basename: $resolved"
            return 1
        }
        [[ -z "${seen_basenames[$basename]+x}" ]] || {
            _mainframe_host_lifecycle_error "locked package basenames collide: $basename"
            return 1
        }
        seen_basenames[$basename]=1
        expected_count=$((expected_count + 1))
        if [[ "$source_mode" == offline-package-dir ]]; then
            source="$package_dir/$basename"
            _mainframe_host_lifecycle_archive_source_safe "$source" || {
                _mainframe_host_lifecycle_set_error E_PACKAGE_ARCHIVE \
                    "required package archive is missing, linked, changing, or oversized: $basename"
                return 1
            }
        elif [[ "$source_mode" != online-registry ]]; then
            return 1
        fi
    done <<< "$plan"
    [[ "$expected_count" -ge 2 && "$expected_count" -le 3 ]] || return 1
    _MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT="$expected_count"

    if [[ "$source_mode" == online-registry ]]; then
        scratch="$workspace/.network"
        ( umask 077; /bin/mkdir -- "$scratch" ) || return 1
        /bin/chmod 700 "$scratch" || return 1
        scratch_identity="$(_mainframe_host_stat_identity "$scratch")" || return 1
        [[ "$scratch_identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    fi

    while IFS=$'\t' read -r lock_path package_name package_version resolved integrity; do
        basename="$(_mainframe_host_lifecycle_archive_basename "$resolved")" || return 1
        destination="$generation/payload/$lock_path"
        ( umask 077; /bin/mkdir -p -- "$destination" ) || return 1
        /bin/chmod 700 "$destination" || return 1
        if [[ "$source_mode" == offline-package-dir ]]; then
            source="$package_dir/$basename"
            _mainframe_host_lifecycle_extract_package \
                "$python" "$source" "$destination" "$integrity" \
                "$package_name" "$package_version" || return 1
        else
            destination_identity="$(_mainframe_host_stat_identity "$destination")" || return 1
            [[ "$destination_identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1
            _mainframe_host_lifecycle_acquire_package \
                "$python" "$resolved" "$scratch" "$scratch_identity" \
                "$destination" "$destination_identity" "$integrity" \
                "$package_name" "$package_version" || return 1
            [[ "$(_mainframe_host_stat_identity "$scratch")" == "$scratch_identity" ]] || {
                _mainframe_host_lifecycle_set_error E_STATE \
                    'private acquisition workspace changed during transfer'
                return 1
            }
        fi
        extracted_count=$((extracted_count + 1))
    done <<< "$plan"
    [[ "$extracted_count" -eq "$expected_count" ]] || return 1

    _mainframe_host_prepare_expected "$host" || return 1
    [[ "$_MAINFRAME_HOST_EXPECTED_TARGET" == "$target_before" &&
       "$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID" == "$bundle_before" ]] || {
        _mainframe_host_lifecycle_error 'trusted host metadata changed during package assembly'
        return 1
    }
    _mainframe_host_lifecycle_normalize_payload "$generation/payload" || return 1
    _mainframe_host_lifecycle_write_receipt "$host" "$generation" || return 1
    /bin/chmod 700 "$generation" || return 1
    _MAINFRAME_RUNTIME_MANAGED_STATE=corrupt
    _MAINFRAME_RUNTIME_MANAGED_DETAIL='staged managed payload authentication failed'
    _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE=""
    _mainframe_host_lifecycle_authenticate_generation "$host" "$generation" || {
        _mainframe_host_lifecycle_error "$_MAINFRAME_RUNTIME_MANAGED_DETAIL"
        return 1
    }
}

_mainframe_host_lifecycle_make_workspace() {
    local stage_only="$1" runtime_root="$2" workspace parent kind record
    local leaf="" returned_parent_identity="" workspace_identity="" extra=""
    local parent_identity="" pending_signal=0 status=0 record_valid=false

    if [[ "$stage_only" == true ]]; then
        parent="$(cd /tmp 2>/dev/null && pwd -P)" || return 1
        kind=temporary
    else
        parent="$runtime_root"
        kind=managed
    fi
    parent_identity="$(_mainframe_host_stat_identity "$parent")" || return 1
    [[ "$parent_identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1

    # Creation, mode/identity checks, durability, and result publication form
    # one descriptor-safe helper transaction. The helper removes its exact
    # empty directory on any pre-publication failure. Defer cancellation until
    # the authenticated record is installed in this transaction process.
    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    trap '_mainframe_host_lifecycle_defer_signal 130' INT
    trap '_mainframe_host_lifecycle_defer_signal 143' TERM
    record="$(_mainframe_host_lifecycle_fs workspace-create \
        "$parent" "$parent_identity" "$kind")" || status=$?
    read -r leaf returned_parent_identity workspace_identity extra <<< "$record"
    if [[ -z "$extra" && "$returned_parent_identity" == "$parent_identity" &&
          "$workspace_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
        case "$kind:$leaf" in
            temporary:mainframe-host-stage.[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]|managed:.install-stage.[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) record_valid=true ;;
        esac
    fi
    if [[ "$record_valid" == true ]]; then
        workspace="$parent/$leaf"
        _MAINFRAME_HOST_LIFECYCLE_WORKSPACE="$workspace"
        _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY="$workspace_identity"
        _MAINFRAME_HOST_LIFECYCLE_WORKSPACE_PARENT_IDENTITY="$parent_identity"
    else
        [[ "$status" -ne 0 ]] || status=1
        if [[ "$_MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE" == unchanged ]]; then
        # The helper cleans every authenticated pre-publication failure. If no
        # result can be authenticated, conservatively avoid claiming that its
        # filesystem outcome is known.
            _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
        fi
    fi

    trap '_mainframe_host_lifecycle_on_signal 130' INT
    trap '_mainframe_host_lifecycle_on_signal 143' TERM
    pending_signal="$_MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL"
    _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
    if [[ "$pending_signal" -eq 130 || "$pending_signal" -eq 143 ]]; then
        _mainframe_host_lifecycle_on_signal "$pending_signal"
    fi
    [[ "$status" -eq 0 ]]
}

_mainframe_host_lifecycle_emit_json() {
    _mainframe_host_lifecycle_begin_terminal_output
    local command="$1" host="$2" result="$3" changed="$4"
    local quarantine_id="${5:-}" source mode
    if [[ "$_MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE" == online-registry ]]; then
        source=download
        mode=online-registry
    else
        source=package-dir
        mode=offline-package-dir
    fi
    case "$command" in
        host-remove) mode=managed-quarantine ;;
        host-restore) mode=managed-quarantine-restore ;;
    esac
    _mainframe_enforce_jq -n \
        --arg command "$command" \
        --arg mode "$mode" \
        --arg source "$source" \
        --arg host "$host" \
        --arg result "$result" \
        --argjson changed "$changed" \
        --argjson network_attempted "$_MAINFRAME_HOST_LIFECYCLE_NETWORK_USED" \
        --argjson archive_count "$_MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT" \
        --arg version "$_MAINFRAME_HOST_EXPECTED_VERSION" \
        --arg platform "$_MAINFRAME_HOST_EXPECTED_PLATFORM" \
        --arg bundle "$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID" \
        --arg package_set "$_MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA" \
        --arg boundary "$(_mainframe_host_managed_boundary "$host")" \
        --arg quarantine "$quarantine_id" '
      {
        schema_version: 1,
        command: $command,
        mode: $mode,
        host: $host,
        result: $result,
        changed: $changed,
        source: (if $command == "host-install" then $source else null end),
        network_attempted: $network_attempted,
        archive_count: $archive_count,
        network: {
          used: $network_attempted,
          proxy: false,
          package_count: $archive_count
        },
        managed: {
          certified_version: $version,
          platform: $platform,
          bundle_id: $bundle,
          package_set_sha256: $package_set,
          trust_boundary: $boundary
        },
        quarantine_id: (if $quarantine == "" then null else $quarantine end)
      }
    '
}

_mainframe_host_lifecycle_plan_count() {
    local host="$1" plan lock_path package_name package_version resolved integrity basename
    local count=0
    local -A seen_basenames=()
    plan="$(_mainframe_host_package_plan "$host" "$_MAINFRAME_HOST_EXPECTED_PLATFORM")" || return 1
    while IFS=$'\t' read -r lock_path package_name package_version resolved integrity; do
        [[ -n "$lock_path" && -n "$package_name" && -n "$package_version" &&
           -n "$resolved" && -n "$integrity" ]] || return 1
        basename="$(_mainframe_host_lifecycle_archive_basename "$resolved")" || return 1
        [[ -z "${seen_basenames[$basename]+x}" ]] || return 1
        seen_basenames[$basename]=1
        count=$((count + 1))
    done <<< "$plan"
    [[ "$count" -ge 2 && "$count" -le 3 ]] || return 1
    printf '%s\n' "$count"
}

_mainframe_host_lifecycle_confirm_download() {
    local host="$1" count="$2" answer
    printf 'MAINFRAME will acquire managed %s %s for %s.\n' \
        "$host" "$_MAINFRAME_HOST_EXPECTED_VERSION" \
        "$_MAINFRAME_HOST_EXPECTED_PLATFORM"
    printf 'Source: %s exact SRI-pinned archive(s) from https://registry.npmjs.org only.\n' \
        "$count"
    printf 'No redirects, npm, package scripts, or vendor executables are allowed.\n'
    printf 'Download, authenticate, and install this managed host? [y/N] '
    IFS= read -r answer || answer=""
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *)
            _mainframe_host_lifecycle_set_error E_NETWORK_CONSENT \
                'online acquisition cancelled before the first network request'
            return 2
            ;;
    esac
}

_mainframe_host_install_impl() {
    local requested_host="" package_dir_raw="" package_dir="" dry_run=false yes=false json=false
    local host_set=false package_set=false download=false download_set=false
    local dry_set=false yes_set=false json_set=false
    local project runtime_root data_home before_state python workspace target
    local target_identity source_identity stage_only=false source_relative target_relative
    local plan_count=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package-dir)
                [[ "$package_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--package-dir may be passed only once'
                    return 2
                }
                [[ $# -ge 2 && -n "${2:-}" && "$2" != -* ]] || {
                    _mainframe_host_lifecycle_usage_error '--package-dir requires exactly one directory'
                    return 2
                }
                package_dir_raw="$2"
                package_set=true
                shift 2
                ;;
            --download)
                [[ "$download_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--download may be passed only once'
                    return 2
                }
                download=true
                download_set=true
                shift
                ;;
            --dry-run)
                [[ "$dry_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--dry-run may be passed only once'
                    return 2
                }
                dry_run=true
                dry_set=true
                shift
                ;;
            --yes)
                [[ "$yes_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--yes may be passed only once'
                    return 2
                }
                yes=true
                yes_set=true
                shift
                ;;
            --json)
                [[ "$json_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--json may be passed only once'
                    return 2
                }
                json=true
                json_set=true
                shift
                ;;
            -h|--help)
                _mainframe_host_lifecycle_usage
                return 0
                ;;
            --*)
                _mainframe_host_lifecycle_usage_error "unknown install option: $1"
                return 2
                ;;
            *)
                [[ "$host_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error "unexpected install argument: $1"
                    return 2
                }
                requested_host="$1"
                host_set=true
                shift
                ;;
        esac
    done
    [[ "$host_set" == true ]] || {
        _mainframe_host_lifecycle_usage_error 'host install requires one host'
        return 2
    }
    _mainframe_host_supported "$requested_host" || {
        _mainframe_host_lifecycle_usage_error "unsupported host: $requested_host"
        return 2
    }
    _MAINFRAME_HOST_LIFECYCLE_HOST="$requested_host"
    if [[ "$package_set" == true && "$download" == true ]]; then
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=conflict
        _mainframe_host_lifecycle_set_error E_SOURCE_CONFLICT \
            '--download and --package-dir are mutually exclusive; select exactly one source'
        return 2
    elif [[ "$package_set" == false && "$download" == false ]]; then
        _mainframe_host_lifecycle_set_error E_SOURCE_REQUIRED \
            'host install requires exactly one source: --download or --package-dir DIR'
        return 2
    fi
    if [[ "$download" == true ]]; then
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=online-registry
    else
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=offline-package-dir
    fi
    [[ ! ( "$dry_run" == true && "$yes" == true ) ]] || {
        _mainframe_host_lifecycle_usage_error '--dry-run and --yes are mutually exclusive'
        return 2
    }
    if [[ "$download" == true && "$dry_run" == false && "$yes" == false &&
          ( "$json" == true || ! -t 0 || ! -t 1 ) ]]; then
        _mainframe_host_lifecycle_set_error E_NETWORK_CONSENT \
            'online acquisition requires --yes, --dry-run, or an affirmative interactive prompt before network access'
        return 2
    fi
    if [[ "$package_set" == true ]]; then
        package_dir="$(_mainframe_host_lifecycle_resolve_package_dir "$package_dir_raw")" || {
            _mainframe_host_lifecycle_set_error E_PACKAGE_ARCHIVE \
                'package directory must be a real non-symlink directory'
            return 1
        }
    fi
    _mainframe_host_lifecycle_prepare "$requested_host" || return 1
    project="${MAINFRAME_ROOT:-}"
    runtime_root="$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT"
    data_home="$(_mainframe_host_data_home)" || return 1
    target="$_MAINFRAME_HOST_EXPECTED_TARGET"

    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    before_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
    case "$before_state" in
        ready)
            if [[ "$json" == true ]]; then
                _mainframe_host_lifecycle_emit_json \
                    host-install "$requested_host" already-installed false
            else
                _mainframe_host_lifecycle_begin_terminal_output
                printf 'Managed %s %s is already installed and fully authenticated.\n' \
                    "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION"
            fi
            return 0
            ;;
        absent) ;;
        corrupt)
            _mainframe_host_lifecycle_error \
                "refusing to overwrite corrupt managed target: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
            ;;
        *)
            _mainframe_host_lifecycle_error \
                "managed install is unavailable: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
            ;;
    esac

    if [[ "$download" == true && "$dry_run" == false && "$yes" == false ]]; then
        plan_count="$(_mainframe_host_lifecycle_plan_count "$requested_host")" || {
            _mainframe_host_lifecycle_set_error E_NETWORK_POLICY \
                'could not derive the exact closed registry package plan'
            return 1
        }
        _mainframe_host_lifecycle_confirm_download "$requested_host" "$plan_count" || return $?
        yes=true
    fi

    python="$(_mainframe_host_lifecycle_python)" || {
        _mainframe_host_lifecycle_set_error E_RUNTIME \
            'host install requires a reviewed Python 3.10+ runtime for bounded extraction'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_PYTHON="$python"

    # A consent-free invocation performs its full package preflight in /tmp,
    # just like --dry-run, and leaves no durable managed-root state behind.
    # Only an explicit --yes is allowed to create the runtime root or lock.
    if [[ "$dry_run" == true || "$yes" == false ]]; then
        stage_only=true
    fi
    if [[ "$stage_only" == false ]]; then
        _mainframe_host_lifecycle_create_runtime_root "$data_home" "$runtime_root" || {
            _mainframe_host_lifecycle_error 'could not create a safe private managed-host root'
            return 1
        }
        _mainframe_host_lifecycle_acquire_lock "$runtime_root" || return 1
        _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
        [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == absent ]] || {
            _mainframe_host_lifecycle_error \
                "managed target changed while acquiring the lifecycle lock: $_MAINFRAME_RUNTIME_MANAGED_STATE"
            return 1
        }
    fi

    _mainframe_host_lifecycle_make_workspace "$stage_only" "$runtime_root" || {
        _mainframe_host_lifecycle_error 'could not create a private lifecycle workspace'
        return 1
    }
    workspace="$_MAINFRAME_HOST_LIFECYCLE_WORKSPACE"
    _mainframe_host_lifecycle_assemble \
        "$requested_host" "$_MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE" \
        "$package_dir" "$workspace" "$python" || return 1

    if [[ "$dry_run" == true ]]; then
        _mainframe_host_lifecycle_cleanup_workspace || return 1
        if [[ "$json" == true ]]; then
            _mainframe_host_lifecycle_emit_json \
                host-install "$requested_host" would-install false
        else
            _mainframe_host_lifecycle_begin_terminal_output
            if [[ "$download" == true ]]; then
                printf 'Downloaded and verified the exact package set for managed %s %s (%s).\n' \
                    "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION" \
                    "$_MAINFRAME_HOST_EXPECTED_PLATFORM"
                printf 'Dry run: network was used; no managed, shell, host, project, or package-manager state changed.\n'
            else
                printf 'Verified offline package set for managed %s %s (%s).\n' \
                    "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION" \
                    "$_MAINFRAME_HOST_EXPECTED_PLATFORM"
                printf 'Dry run: no managed, shell, host, project, package-manager, or network state changed.\n'
            fi
        fi
        return 0
    fi
    [[ "$yes" == true ]] || {
        _mainframe_host_lifecycle_cleanup_workspace || return 1
        _mainframe_host_lifecycle_set_error E_CONSENT \
            'verified package set is ready; rerun with --yes to publish or --dry-run to preflight only'
        return 2
    }

    _mainframe_host_prepare_expected "$requested_host" || return 1
    [[ "$_MAINFRAME_HOST_EXPECTED_TARGET" == "$target" ]] || {
        _mainframe_host_lifecycle_error 'trusted managed target changed before publication'
        return 1
    }
    _MAINFRAME_RUNTIME_MANAGED_STATE=corrupt
    _mainframe_host_lifecycle_authenticate_generation \
        "$requested_host" "$workspace/generation" || return 1
    source_identity="$(_mainframe_host_stat_identity "$workspace/generation")" || return 1
    [[ "$workspace" == "$runtime_root"/* && "$target" == "$runtime_root"/* ]] || return 1
    source_relative="${workspace#"$runtime_root/"}/generation"
    target_relative="${target#"$runtime_root/"}"
    # Once the no-replace publication helper starts, interruption or an fsync
    # error can occur after rename but before the helper returns its identity.
    # Report that window conservatively instead of claiming no mutation.
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    target_identity="$(_mainframe_host_lifecycle_fs move \
        "$runtime_root" "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY" \
        "$source_relative" "$target_relative" "$source_identity")" || return 1
    _MAINFRAME_HOST_LIFECYCLE_CHANGED=true
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=changed
    [[ "$target_identity" == "$source_identity" ]] || {
        _mainframe_host_lifecycle_error \
            'managed target was substituted during publication; leaving all paths for inspection'
        return 1
    }
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == ready ]] || {
        _mainframe_host_lifecycle_error \
            "published managed generation failed final authentication: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
        return 1
    }
    _mainframe_host_lifecycle_cleanup || return 1
    if [[ "$json" == true ]]; then
        _mainframe_host_lifecycle_emit_json host-install "$requested_host" installed true
    else
        _mainframe_host_lifecycle_begin_terminal_output
        printf 'Installed and authenticated managed %s %s for %s.\n' \
            "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION" \
            "$_MAINFRAME_HOST_EXPECTED_PLATFORM"
        printf 'No PATH, shell profile, global package, host configuration, or project file changed.\n'
    fi
}

_mainframe_host_install() {
    (
        local argument status=0 saw_download=false saw_package_dir=false
        _MAINFRAME_HOST_LIFECYCLE_JSON=false
        _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_HOST_LIFECYCLE
        _MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND="host-install"
        _MAINFRAME_HOST_LIFECYCLE_HOST=""
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=unspecified
        _MAINFRAME_HOST_LIFECYCLE_NETWORK_USED=false
        _MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT=0
        _MAINFRAME_HOST_LIFECYCLE_CHANGED=false
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=unchanged
        _MAINFRAME_HOST_LIFECYCLE_OPERATION_PID="${BASHPID:-$$}"
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY=""
        _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
        for argument in "$@"; do
            case "$argument" in
                --json) _MAINFRAME_HOST_LIFECYCLE_JSON=true ;;
                --download) saw_download=true ;;
                --package-dir) saw_package_dir=true ;;
            esac
        done
        trap _mainframe_host_lifecycle_on_exit EXIT
        trap '_mainframe_host_lifecycle_on_signal 130' INT
        trap '_mainframe_host_lifecycle_on_signal 143' TERM
        if [[ "$saw_download" == true && "$saw_package_dir" == true ]]; then
            _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=conflict
        elif [[ "$saw_download" == true ]]; then
            _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=online-registry
        elif [[ "$saw_package_dir" == true ]]; then
            _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=offline-package-dir
        fi
        if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
            _mainframe_host_install_impl "$@" 2>/dev/null || status=$?
        else
            _mainframe_host_install_impl "$@" || status=$?
        fi
        if [[ "$status" -ne 0 ]]; then
            trap - EXIT
            _mainframe_host_lifecycle_finalize_failure "$status" || status=$?
            trap '' INT TERM
            return "$status"
        fi
        trap - EXIT
        trap '' INT TERM
        return 0
    )
}

_mainframe_host_remove_impl() {
    local requested_host="" dry_run=false yes=false json=false
    local host_set=false dry_set=false yes_set=false json_set=false
    local project runtime_root data_home target target_identity quarantine_parent
    local python slot_id returned_slot destination moved_identity move_result
    local target_relative quarantine_relative

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                [[ "$dry_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--dry-run may be passed only once'
                    return 2
                }
                dry_run=true
                dry_set=true
                shift
                ;;
            --yes)
                [[ "$yes_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--yes may be passed only once'
                    return 2
                }
                yes=true
                yes_set=true
                shift
                ;;
            --json)
                [[ "$json_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--json may be passed only once'
                    return 2
                }
                json=true
                json_set=true
                shift
                ;;
            -h|--help)
                _mainframe_host_lifecycle_usage
                return 0
                ;;
            --*)
                _mainframe_host_lifecycle_usage_error "unknown remove option: $1"
                return 2
                ;;
            *)
                [[ "$host_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error "unexpected remove argument: $1"
                    return 2
                }
                requested_host="$1"
                host_set=true
                shift
                ;;
        esac
    done
    [[ "$host_set" == true ]] || {
        _mainframe_host_lifecycle_usage_error 'host remove requires one host'
        return 2
    }
    _mainframe_host_supported "$requested_host" || {
        _mainframe_host_lifecycle_usage_error "unsupported host: $requested_host"
        return 2
    }
    _MAINFRAME_HOST_LIFECYCLE_HOST="$requested_host"
    [[ ! ( "$dry_run" == true && "$yes" == true ) ]] || {
        _mainframe_host_lifecycle_usage_error '--dry-run and --yes are mutually exclusive'
        return 2
    }
    _mainframe_host_lifecycle_prepare "$requested_host" || return 1
    project="${MAINFRAME_ROOT:-}"
    runtime_root="$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT"
    data_home="$(_mainframe_host_data_home)" || return 1
    target="$_MAINFRAME_HOST_EXPECTED_TARGET"
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    case "$_MAINFRAME_RUNTIME_MANAGED_STATE" in
        absent)
            if [[ "$json" == true ]]; then
                _mainframe_host_lifecycle_emit_json \
                    host-remove "$requested_host" already-absent false
            else
                _mainframe_host_lifecycle_begin_terminal_output
                printf 'Managed %s %s is already absent.\n' \
                    "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION"
            fi
            return 0
            ;;
        ready) ;;
        corrupt)
            _mainframe_host_lifecycle_error \
                "refusing to move a corrupt managed target: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
            ;;
        *)
            _mainframe_host_lifecycle_error \
                "managed removal is unavailable: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
            ;;
    esac
    if [[ "$dry_run" == true ]]; then
        if [[ "$json" == true ]]; then
            _mainframe_host_lifecycle_emit_json \
                host-remove "$requested_host" would-remove false
        else
            _mainframe_host_lifecycle_begin_terminal_output
            printf 'Verified managed %s %s; removal would move only this generation to private quarantine.\n' \
                "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION"
            printf 'Dry run: no managed, shell, host, project, package-manager, or network state changed.\n'
        fi
        return 0
    fi
    [[ "$yes" == true ]] || {
        _mainframe_host_lifecycle_set_error E_CONSENT \
            'verified managed generation is ready; rerun with --yes to move it to quarantine'
        return 2
    }

    python="$(_mainframe_host_lifecycle_python)" || {
        _mainframe_host_lifecycle_error \
            'host remove requires a reviewed Python 3.10+ runtime for confined quarantine'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_PYTHON="$python"
    _mainframe_host_lifecycle_acquire_lock "$runtime_root" || return 1
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == ready ]] || {
        _mainframe_host_lifecycle_error \
            "managed target changed while acquiring the lifecycle lock: $_MAINFRAME_RUNTIME_MANAGED_STATE"
        return 1
    }
    target_identity="$(_mainframe_host_stat_identity "$target")" || return 1
    quarantine_parent="$runtime_root/quarantine/v1/$requested_host/$_MAINFRAME_HOST_EXPECTED_VERSION/$_MAINFRAME_HOST_EXPECTED_PLATFORM/$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID"
    [[ "$target" == "$runtime_root"/* && "$quarantine_parent" == "$runtime_root"/* ]] || return 1
    target_relative="${target#"$runtime_root/"}"
    quarantine_relative="${quarantine_parent#"$runtime_root/"}"
    slot_id="$(_mainframe_host_lifecycle_fs quarantine-id)" || {
        _mainframe_host_lifecycle_error \
            'could not generate an exact quarantine recovery ID'
        return 1
    }
    [[ "$slot_id" =~ ^removed\.[0-9a-f]{18}$ ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'filesystem helper returned a malformed quarantine recovery ID'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID="$slot_id"
    destination="$quarantine_parent/$slot_id/generation"
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    move_result="$(_mainframe_host_lifecycle_fs quarantine \
        "$runtime_root" "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY" \
        "$target_relative" "$quarantine_relative" "$slot_id" \
        "$target_identity")" || return 1
    _MAINFRAME_HOST_LIFECYCLE_CHANGED=true
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=changed
    read -r returned_slot moved_identity <<< "$move_result"
    [[ "$returned_slot" == "$slot_id" &&
       "$moved_identity" == "$target_identity" ]] || return 1
    if ! _mainframe_host_lifecycle_authenticate_generation \
        "$requested_host" "$destination"; then
        _mainframe_host_lifecycle_error \
            'quarantine move did not preserve the exact authenticated generation'
        return 1
    fi
    [[ ! -e "$target" && ! -L "$target" ]] || {
        _mainframe_host_lifecycle_error 'managed target reappeared during quarantine cutover'
        return 1
    }
    _mainframe_host_lifecycle_cleanup || return 1
    if [[ "$json" == true ]]; then
        _mainframe_host_lifecycle_emit_json \
            host-remove "$requested_host" removed true "$slot_id"
    else
        _mainframe_host_lifecycle_begin_terminal_output
        printf 'Removed managed %s %s from active resolution.\n' \
            "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION"
        printf 'Quarantine ID: %s\n' "$slot_id"
        printf 'Recoverable quarantine: %s\n' "$destination"
        printf 'Restore preview: mainframe host restore %s --quarantine-id %s --dry-run\n' \
            "$requested_host" "$slot_id"
        printf 'No PATH, shell profile, global package, host configuration, or project file changed.\n'
    fi
}

_mainframe_host_remove() {
    (
        local argument status=0
        _MAINFRAME_HOST_LIFECYCLE_JSON=false
        _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_HOST_LIFECYCLE
        _MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND="host-remove"
        _MAINFRAME_HOST_LIFECYCLE_HOST=""
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=unspecified
        _MAINFRAME_HOST_LIFECYCLE_NETWORK_USED=false
        _MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT=0
        _MAINFRAME_HOST_LIFECYCLE_CHANGED=false
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=unchanged
        _MAINFRAME_HOST_LIFECYCLE_OPERATION_PID="${BASHPID:-$$}"
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY=""
        _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
        for argument in "$@"; do
            [[ "$argument" == --json ]] && _MAINFRAME_HOST_LIFECYCLE_JSON=true
        done
        trap _mainframe_host_lifecycle_on_exit EXIT
        trap '_mainframe_host_lifecycle_on_signal 130' INT
        trap '_mainframe_host_lifecycle_on_signal 143' TERM
        if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
            _mainframe_host_remove_impl "$@" 2>/dev/null || status=$?
        else
            _mainframe_host_remove_impl "$@" || status=$?
        fi
        if [[ "$status" -ne 0 ]]; then
            trap - EXIT
            _mainframe_host_lifecycle_finalize_failure "$status" || status=$?
            trap '' INT TERM
            return "$status"
        fi
        trap - EXIT
        trap '' INT TERM
        return 0
    )
}

_mainframe_host_restore_impl() {
    local requested_host="" quarantine_id="" dry_run=false yes=false json=false
    local host_set=false quarantine_set=false dry_set=false yes_set=false json_set=false
    local project runtime_root target python move_result moved_identity target_identity
    local source_relative target_relative expected_target expected_slot expected_generation
    local expected_generation_identity

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quarantine-id)
                [[ "$quarantine_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error \
                        '--quarantine-id may be passed only once'
                    return 2
                }
                [[ $# -ge 2 && -n "${2:-}" && "$2" != -* ]] || {
                    _mainframe_host_lifecycle_usage_error \
                        '--quarantine-id requires one generated ID'
                    return 2
                }
                quarantine_id="$2"
                quarantine_set=true
                shift 2
                ;;
            --dry-run)
                [[ "$dry_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--dry-run may be passed only once'
                    return 2
                }
                dry_run=true
                dry_set=true
                shift
                ;;
            --yes)
                [[ "$yes_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--yes may be passed only once'
                    return 2
                }
                yes=true
                yes_set=true
                shift
                ;;
            --json)
                [[ "$json_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error '--json may be passed only once'
                    return 2
                }
                json=true
                json_set=true
                shift
                ;;
            -h|--help)
                _mainframe_host_lifecycle_usage
                return 0
                ;;
            --*)
                _mainframe_host_lifecycle_usage_error "unknown restore option: $1"
                return 2
                ;;
            *)
                [[ "$host_set" == false ]] || {
                    _mainframe_host_lifecycle_usage_error \
                        "unexpected restore argument: $1"
                    return 2
                }
                requested_host="$1"
                host_set=true
                shift
                ;;
        esac
    done
    [[ "$host_set" == true ]] || {
        _mainframe_host_lifecycle_usage_error 'host restore requires one host'
        return 2
    }
    _mainframe_host_supported "$requested_host" || {
        _mainframe_host_lifecycle_usage_error "unsupported host: $requested_host"
        return 2
    }
    _MAINFRAME_HOST_LIFECYCLE_HOST="$requested_host"
    [[ "$quarantine_set" == true ]] || {
        _mainframe_host_lifecycle_usage_error \
            'host restore requires --quarantine-id removed.<18-hex>'
        return 2
    }
    [[ "$quarantine_id" =~ ^removed\.[0-9a-f]{18}$ ]] || {
        _mainframe_host_lifecycle_set_error E_QUARANTINE_ID \
            'restore accepts only an exact generated removed.<18-lowercase-hex> ID'
        return 2
    }
    _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID="$quarantine_id"
    [[ ! ( "$dry_run" == true && "$yes" == true ) ]] || {
        _mainframe_host_lifecycle_usage_error '--dry-run and --yes are mutually exclusive'
        return 2
    }

    _mainframe_host_lifecycle_prepare "$requested_host" || return 1
    project="${MAINFRAME_ROOT:-}"
    runtime_root="$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT"
    target="$_MAINFRAME_HOST_EXPECTED_TARGET"
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    case "$_MAINFRAME_RUNTIME_MANAGED_STATE" in
        absent) ;;
        ready|corrupt)
            _mainframe_host_lifecycle_set_error E_TARGET_PRESENT \
                'refusing to restore over a present active managed target'
            return 1
            ;;
        *)
            _mainframe_host_lifecycle_set_error E_STATE \
                'active managed target state is unavailable or unsafe'
            return 1
            ;;
    esac
    if [[ "$json" == true ]]; then
        _mainframe_host_lifecycle_validate_quarantine_generation \
            "$requested_host" "$quarantine_id" 2>/dev/null || return 1
    else
        _mainframe_host_lifecycle_validate_quarantine_generation \
            "$requested_host" "$quarantine_id" || return 1
    fi
    expected_target="$target"
    expected_slot="$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT"
    expected_generation="$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION"
    expected_generation_identity="$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY"

    if [[ "$dry_run" == true ]]; then
        if [[ "$json" == true ]]; then
            _mainframe_host_lifecycle_emit_json \
                host-restore "$requested_host" would-restore false "$quarantine_id"
        else
            _mainframe_host_lifecycle_begin_terminal_output
            printf 'Verified quarantine %s for managed %s %s; restore would atomically republish the exact generation.\n' \
                "$quarantine_id" "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION"
            printf 'Dry run: no managed, shell, host, project, package-manager, or network state changed.\n'
        fi
        return 0
    fi
    [[ "$yes" == true ]] || {
        _mainframe_host_lifecycle_set_error E_CONSENT \
            'verified quarantine generation is ready; rerun with --yes to restore it'
        return 2
    }

    python="$(_mainframe_host_lifecycle_python)" || {
        _mainframe_host_lifecycle_set_error E_RUNTIME \
            'host restore requires a reviewed Python 3.10+ runtime for confined publication'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_PYTHON="$python"
    _mainframe_host_lifecycle_acquire_lock "$runtime_root" || return 1

    _mainframe_host_lifecycle_prepare "$requested_host" || return 1
    [[ "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT" == "$runtime_root" &&
       "$_MAINFRAME_HOST_EXPECTED_TARGET" == "$expected_target" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'trusted restore metadata changed while acquiring the lifecycle lock'
        return 1
    }
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == absent ]] || {
        _mainframe_host_lifecycle_set_error E_TARGET_PRESENT \
            'active managed target appeared while acquiring the lifecycle lock'
        return 1
    }
    if [[ "$json" == true ]]; then
        _mainframe_host_lifecycle_validate_quarantine_generation \
            "$requested_host" "$quarantine_id" 2>/dev/null || return 1
    else
        _mainframe_host_lifecycle_validate_quarantine_generation \
            "$requested_host" "$quarantine_id" || return 1
    fi
    [[ "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT" == "$expected_slot" &&
       "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION" == "$expected_generation" &&
       "$_MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY" == \
           "$expected_generation_identity" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'quarantine generation changed while acquiring the lifecycle lock'
        return 1
    }

    source_relative="${expected_generation#"$runtime_root/"}"
    target_relative="${expected_target#"$runtime_root/"}"
    [[ "$source_relative" != "$expected_generation" &&
       "$target_relative" != "$expected_target" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'restore source or destination escaped the managed root'
        return 1
    }
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=uncertain
    move_result="$(_mainframe_host_lifecycle_fs move \
        "$runtime_root" "$_MAINFRAME_HOST_LIFECYCLE_RUNTIME_ROOT_IDENTITY" \
        "$source_relative" "$target_relative" "$expected_generation_identity")" || return 1
    _MAINFRAME_HOST_LIFECYCLE_CHANGED=true
    _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=changed
    moved_identity="$move_result"
    [[ "$moved_identity" == "$expected_generation_identity" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'restore helper returned an unexpected generation identity'
        return 1
    }
    target_identity="$(_mainframe_host_stat_identity "$expected_target")" || return 1
    [[ "$target_identity" == "$expected_generation_identity" &&
       ! -e "$expected_generation" && ! -L "$expected_generation" &&
       -d "$expected_slot" && ! -L "$expected_slot" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'restore cutover did not preserve the exact source identity'
        return 1
    }
    _mainframe_host_directory_children_exact "$expected_slot" || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'consumed quarantine slot contains unexpected entries'
        return 1
    }
    _mainframe_host_lifecycle_probe_managed "$requested_host" "$project"
    [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == ready &&
       "$(_mainframe_host_stat_identity "$expected_target")" == \
           "$expected_generation_identity" ]] || {
        _mainframe_host_lifecycle_set_error E_STATE \
            'restored active generation failed final authentication'
        return 1
    }
    _mainframe_host_lifecycle_cleanup || return 1
    if [[ "$json" == true ]]; then
        _mainframe_host_lifecycle_emit_json \
            host-restore "$requested_host" restored true "$quarantine_id"
    else
        _mainframe_host_lifecycle_begin_terminal_output
        printf 'Restored managed %s %s from quarantine %s.\n' \
            "$requested_host" "$_MAINFRAME_HOST_EXPECTED_VERSION" "$quarantine_id"
        printf 'The consumed quarantine slot remains empty for inspection; no PATH, shell profile, global package, host configuration, project, or network state changed.\n'
    fi
}

_mainframe_host_restore() {
    (
        local argument status=0
        _MAINFRAME_HOST_LIFECYCLE_JSON=false
        _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_HOST_LIFECYCLE
        _MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND="host-restore"
        _MAINFRAME_HOST_LIFECYCLE_HOST=""
        _MAINFRAME_HOST_LIFECYCLE_SOURCE_MODE=unspecified
        _MAINFRAME_HOST_LIFECYCLE_NETWORK_USED=false
        _MAINFRAME_HOST_LIFECYCLE_PACKAGE_COUNT=0
        _MAINFRAME_HOST_LIFECYCLE_CHANGED=false
        _MAINFRAME_HOST_LIFECYCLE_MUTATION_STATE=unchanged
        _MAINFRAME_HOST_LIFECYCLE_OPERATION_PID="${BASHPID:-$$}"
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_ID=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_SLOT=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION=""
        _MAINFRAME_HOST_LIFECYCLE_QUARANTINE_GENERATION_IDENTITY=""
        _MAINFRAME_HOST_LIFECYCLE_DEFERRED_SIGNAL=0
        for argument in "$@"; do
            [[ "$argument" == --json ]] && _MAINFRAME_HOST_LIFECYCLE_JSON=true
        done
        trap _mainframe_host_lifecycle_on_exit EXIT
        trap '_mainframe_host_lifecycle_on_signal 130' INT
        trap '_mainframe_host_lifecycle_on_signal 143' TERM
        if [[ "$_MAINFRAME_HOST_LIFECYCLE_JSON" == true ]]; then
            _mainframe_host_restore_impl "$@" 2>/dev/null || status=$?
        else
            _mainframe_host_restore_impl "$@" || status=$?
        fi
        if [[ "$status" -ne 0 ]]; then
            trap - EXIT
            _mainframe_host_lifecycle_finalize_failure "$status" || status=$?
            trap '' INT TERM
            return "$status"
        fi
        trap - EXIT
        trap '' INT TERM
        return 0
    )
}

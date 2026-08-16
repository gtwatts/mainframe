#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pi.sh - First-party Pi integration lifecycle manager
# =============================================================================
# Public API:
#   mainframe_pi_status [--json]
#   mainframe_pi_doctor [--json]
#   mainframe_pi_install [--dry-run] [--yes]
#   mainframe_pi_remove [--dry-run] [--yes]
#   mainframe_pi_restore --backup-id ID (--dry-run|--yes)
#
# Pi's documented user-package schema is a local directory string in the
# top-level `packages` array of ~/.pi/agent/settings.json.  This manager writes
# that schema directly so it does not need to execute Pi or any caller-PATH
# interpreter while migrating older standalone extension/skill copies.
# =============================================================================

[[ -n "${_MAINFRAME_PI_LOADED:-}" ]] && return 0
_MAINFRAME_PI_LOADED=1

_MAINFRAME_PI_SYSTEM_PATH='/usr/bin:/bin:/usr/sbin:/sbin'
_MAINFRAME_PI_SOURCE_PATH="${BASH_SOURCE[0]}"
case "$_MAINFRAME_PI_SOURCE_PATH" in
    /*) ;;
    *) _MAINFRAME_PI_SOURCE_PATH="$PWD/$_MAINFRAME_PI_SOURCE_PATH" ;;
esac

_MAINFRAME_PI_SOURCE_UNSAFE=''
if [[ -L "$_MAINFRAME_PI_SOURCE_PATH" ]]; then
    _MAINFRAME_PI_SOURCE_UNSAFE='the Pi manager library is a symbolic link'
fi
_MAINFRAME_PI_LIB_DIR="$(
    cd -- "${_MAINFRAME_PI_SOURCE_PATH%/*}" 2>/dev/null && pwd -P
)" || _MAINFRAME_PI_SOURCE_UNSAFE='the Pi manager library directory cannot be resolved'
_MAINFRAME_PI_ROOT="$(
    cd -- "${_MAINFRAME_PI_LIB_DIR:-/}/.." 2>/dev/null && pwd -P
)" || _MAINFRAME_PI_SOURCE_UNSAFE='the Mainframe package root cannot be resolved'
_MAINFRAME_PI_PACKAGE_SOURCE="$_MAINFRAME_PI_ROOT"
_MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=false

_MAINFRAME_PI_PYTHON=''
_MAINFRAME_PI_BASH=''
_MAINFRAME_PI_BACKUP_DIR=''
_MAINFRAME_PI_QUARANTINED_EXTENSION='none'
_MAINFRAME_PI_QUARANTINED_SKILL='none'
_MAINFRAME_PI_SETTINGS_UPDATED='false'

_mainframe_pi_error() {
    printf 'MAINFRAME Pi: %s\n' "$*" >&2
}

_mainframe_pi_usage_status() {
    printf '%s\n' 'Usage: mainframe pi status [--json]'
}

_mainframe_pi_usage_doctor() {
    /bin/cat <<'EOF'
Usage: mainframe pi doctor [--json]

Read-only, offline diagnosis of the installed Pi version, MAINFRAME's exact
compatibility evidence, and the package configuration on disk. This command
does not start Pi and cannot prove what an already-running Pi process loaded;
run /mainframe doctor inside Pi for that final activation proof.

Exit 2 means the offline diagnosis completed but live activation still needs
operator action or in-Pi verification; exit 1 means inspection was blocked.
EOF
}

_mainframe_pi_usage_install() {
    /bin/cat <<'EOF'
Usage: mainframe pi install [--dry-run] [--yes]

  --dry-run  Print the exact migration plan without changing any file
  --yes      Confirm the real install on this same command invocation
EOF
}

_mainframe_pi_usage_remove() {
    /bin/cat <<'EOF'
Usage: mainframe pi remove [--dry-run] [--yes]

  --dry-run  Print the exact detach plan without changing any file
  --yes      Confirm the real detach on this same command invocation

Removal changes only Mainframe-managed package entries and its private receipt.
Legacy migration backups and unrelated Pi settings are preserved.
EOF
}

_mainframe_pi_usage_restore() {
    /bin/cat <<'EOF'
Usage: mainframe pi restore --backup-id ID (--dry-run|--yes)

  --backup-id ID  Exact private backup basename emitted by Pi install
  --dry-run        Validate the private snapshot and preview recovery without writes
  --yes            Confirm exact post-install recovery on this invocation

Restore accepts only a completed legacy-migration snapshot whose current
post-install settings and receipt still match exactly. Unrelated drift fails
closed. The private backup is preserved after recovery.
EOF
}

_mainframe_pi_has_control_character() {
    local value="$1"
    [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *$'\t'* ]]
}

_mainframe_pi_clean_absolute_path() {
    local path="$1" rest component

    [[ "$path" == /* && "$path" != / && "$path" != */ ]] || return 1
    _mainframe_pi_has_control_character "$path" && return 1

    rest="${path#/}"
    while [[ -n "$rest" ]]; do
        case "$rest" in
            */*) component="${rest%%/*}"; rest="${rest#*/}" ;;
            *) component="$rest"; rest='' ;;
        esac
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
    done
    return 0
}

_mainframe_pi_stat_owner_mode() {
    local path="$1" result owner mode stat_bin=''

    if [[ -x /usr/bin/stat ]]; then
        stat_bin=/usr/bin/stat
    elif [[ -x /bin/stat ]]; then
        stat_bin=/bin/stat
    else
        return 1
    fi
    result="$("$stat_bin" -c '%u %a' "$path" 2>/dev/null ||
        "$stat_bin" -f '%u %Mp%Lp' "$path" 2>/dev/null)" || return 1
    [[ "$result" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<< "$result"
    [[ ${#mode} -eq 4 && "$mode" == 0* ]] && mode="${mode#0}"
    printf '%s %s\n' "$owner" "$mode"
}

_mainframe_pi_link_count() {
    local path="$1" result stat_bin=''

    if [[ -x /usr/bin/stat ]]; then
        stat_bin=/usr/bin/stat
    elif [[ -x /bin/stat ]]; then
        stat_bin=/bin/stat
    else
        return 1
    fi
    result="$("$stat_bin" -c '%h' "$path" 2>/dev/null ||
        "$stat_bin" -f '%l' "$path" 2>/dev/null)" || return 1
    [[ "$result" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "$result"
}

_mainframe_pi_is_darwin() {
    local uname_bin=''
    if [[ -x /usr/bin/uname ]]; then
        uname_bin=/usr/bin/uname
    elif [[ -x /bin/uname ]]; then
        uname_bin=/bin/uname
    else
        return 1
    fi
    [[ "$("$uname_bin" -s 2>/dev/null)" == Darwin ]]
}

_mainframe_pi_no_write_acl() {
    local path="$1" line permissions listing

    _mainframe_pi_is_darwin || return 0
    [[ -x /bin/ls ]] || return 1
    listing="$(LC_ALL=C /bin/ls -lde "$path" 2>/dev/null)" || return 1
    while IFS= read -r line; do
        [[ "$line" == *' allow '* ]] || continue
        permissions=",${line#* allow },"
        case "$permissions" in
            *,write,*|*,append,*|*,delete,*|*,delete_child,*|\
            *,add_file,*|*,add_subdirectory,*|*,writeattr,*|\
            *,writeextattr,*|*,writeowner,*|*,writesecurity,*|*,chown,*)
                return 1
                ;;
        esac
    done <<< "$listing"
    return 0
}

_mainframe_pi_validate_directory_chain() {
    local path="$1" final_owner_policy="${2:-user}"
    local rest component current='' metadata owner mode numeric sticky_parent=false

    _mainframe_pi_clean_absolute_path "$path" || return 1
    rest="${path#/}"
    while [[ -n "$rest" ]]; do
        case "$rest" in
            */*) component="${rest%%/*}"; rest="${rest#*/}" ;;
            *) component="$rest"; rest='' ;;
        esac
        current="$current/$component"
        [[ ! -L "$current" && -d "$current" ]] || return 1
        _mainframe_pi_no_write_acl "$current" || return 1
        metadata="$(_mainframe_pi_stat_owner_mode "$current")" || return 1
        [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
        read -r owner mode <<< "$metadata" || return 1
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
        numeric=$((8#$mode))

        if [[ "$sticky_parent" == true ]]; then
            [[ "$owner" -eq "$EUID" ]] || return 1
            (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
            sticky_parent=false
        elif (( (numeric & 0022) != 0 || (numeric & 07000) != 0 )); then
            if [[ "$owner" -eq 0 ]] &&
               (( (numeric & 01000) != 0 && (numeric & 06000) == 0 )); then
                sticky_parent=true
            else
                return 1
            fi
        fi
    done
    [[ "$sticky_parent" == false ]] || return 1

    metadata="$(_mainframe_pi_stat_owner_mode "$path")" || return 1
    [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<< "$metadata" || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    if [[ "$final_owner_policy" == user ]]; then
        [[ "$owner" -eq "$EUID" ]] || return 1
    else
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    fi
    return 0
}

# Homebrew kegs can live below a package-manager prefix whose shared group is
# writable (for example /opt/homebrew). Every principal authorized to write
# that prefix is part of the trusted package-manager boundary and can retarget
# the stable opt source after activation. The selector authenticates the exact
# fixed layout and resolves it back to this already-loaded package root before
# enabling the narrower boundary. From that root down, every directory must
# still be a real, owner-controlled, non-writable node at validation time.
_mainframe_pi_validate_directory_subtree() {
    local root="$1" path="$2" final_owner_policy="${3:-root-or-user}"
    local rest component current metadata owner mode numeric owner_policy

    _mainframe_pi_clean_absolute_path "$root" || return 1
    _mainframe_pi_clean_absolute_path "$path" || return 1
    [[ "$path" == "$root" || "$path" == "$root"/* ]] || return 1

    current="$root"
    rest="${path#"$root"}"
    rest="${rest#/}"
    while :; do
        [[ ! -L "$current" && -d "$current" ]] || return 1
        _mainframe_pi_no_write_acl "$current" || return 1
        metadata="$(_mainframe_pi_stat_owner_mode "$current")" || return 1
        [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
        read -r owner mode <<< "$metadata" || return 1
        owner_policy='root-or-user'
        [[ "$current" != "$path" ]] || owner_policy="$final_owner_policy"
        if [[ "$owner_policy" == user ]]; then
            [[ "$owner" -eq "$EUID" ]] || return 1
        else
            [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
        fi
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1

        [[ -n "$rest" ]] || break
        case "$rest" in
            */*) component="${rest%%/*}"; rest="${rest#*/}" ;;
            *) component="$rest"; rest='' ;;
        esac
        current="$current/$component"
    done
    return 0
}

_mainframe_pi_validate_package_directory() {
    local path="$1"

    if [[ "$_MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE" == true ]]; then
        _mainframe_pi_validate_directory_subtree \
            "$_MAINFRAME_PI_ROOT" "$path" root-or-user
    else
        _mainframe_pi_validate_directory_chain "$path" root-or-user
    fi
}

_mainframe_pi_validate_regular_file() {
    local path="$1" owner_policy="${2:-user}" single_link="${3:-true}"
    local metadata owner mode numeric links

    [[ -e "$path" || -L "$path" ]] || return 1
    [[ ! -L "$path" && -f "$path" ]] || return 1
    _mainframe_pi_no_write_acl "$path" || return 1
    metadata="$(_mainframe_pi_stat_owner_mode "$path")" || return 1
    [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<< "$metadata" || return 1
    if [[ "$owner_policy" == user ]]; then
        [[ "$owner" -eq "$EUID" ]] || return 1
    else
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    fi
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    if [[ "$single_link" == true ]]; then
        links="$(_mainframe_pi_link_count "$path")" || return 1
        [[ "$links" -eq 1 ]] || return 1
    fi
    return 0
}

_mainframe_pi_resolve_executable() {
    local source="$1" dir target links=0 readlink_bin=''

    [[ "$source" == /* ]] || return 1
    if [[ -x /usr/bin/readlink ]]; then
        readlink_bin=/usr/bin/readlink
    elif [[ -x /bin/readlink ]]; then
        readlink_bin=/bin/readlink
    else
        return 1
    fi
    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        dir="${source%/*}"
        [[ -n "$dir" ]] || dir=/
        dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
        target="$("$readlink_bin" "$source")" || return 1
        if [[ "$target" == /* ]]; then
            source="$target"
        else
            source="$dir/$target"
        fi
    done
    dir="${source%/*}"
    [[ -n "$dir" ]] || dir=/
    dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
    source="$dir/${source##*/}"
    [[ -f "$source" && ! -L "$source" && -x "$source" ]] || return 1
    _mainframe_pi_has_control_character "$source" && return 1
    printf '%s\n' "$source"
}

_mainframe_pi_bash_layout_allowed() {
    case "$1" in
        /bin/bash|/usr/bin/bash|/usr/local/bin/bash|/opt/local/bin/bash|\
        /nix/store/*/bin/bash|\
        /opt/homebrew/Cellar/bash/*/bin/bash|\
        /usr/local/Cellar/bash/*/bin/bash|\
        /home/linuxbrew/.linuxbrew/Cellar/bash/*/bin/bash)
            return 0
            ;;
        *) return 1 ;;
    esac
}

_mainframe_pi_python_layout_allowed() {
    case "$1" in
        /bin/python3|/bin/python3.[0-9]*|\
        /usr/bin/python3|/usr/bin/python3.[0-9]*|\
        /usr/local/bin/python3|/usr/local/bin/python3.[0-9]*|\
        /opt/local/bin/python3|/opt/local/bin/python3.[0-9]*|\
        /nix/store/*/bin/python3|/nix/store/*/bin/python3.[0-9]*|\
        /opt/homebrew/Cellar/python*/*/bin/python3|\
        /opt/homebrew/Cellar/python*/*/bin/python3.[0-9]*|\
        /usr/local/Cellar/python*/*/bin/python3|\
        /usr/local/Cellar/python*/*/bin/python3.[0-9]*|\
        /home/linuxbrew/.linuxbrew/Cellar/python*/*/bin/python3|\
        /home/linuxbrew/.linuxbrew/Cellar/python*/*/bin/python3.[0-9]*|\
        /Library/Frameworks/Python.framework/Versions/*/bin/python3|\
        /Library/Frameworks/Python.framework/Versions/*/bin/python3.[0-9]*)
            return 0
            ;;
        *) return 1 ;;
    esac
}

_mainframe_pi_validate_executable() {
    local requested="$1" kind="$2" resolved metadata owner mode numeric

    resolved="$(_mainframe_pi_resolve_executable "$requested" 2>/dev/null)" || return 1
    case "$kind" in
        bash) _mainframe_pi_bash_layout_allowed "$resolved" || return 1 ;;
        python) _mainframe_pi_python_layout_allowed "$resolved" || return 1 ;;
        *) return 1 ;;
    esac
    metadata="$(_mainframe_pi_stat_owner_mode "$resolved")" || return 1
    [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<< "$metadata" || return 1
    [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
       (numeric & 0100) != 0 )) || return 1
    _mainframe_pi_no_write_acl "$resolved" || return 1
    printf '%s\n' "$resolved"
}

_mainframe_pi_resolve_python() {
    local candidate resolved
    for candidate in \
        /usr/bin/python3 \
        /bin/python3 \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3 \
        /opt/local/bin/python3; do
        resolved="$(_mainframe_pi_validate_executable "$candidate" python 2>/dev/null)" || continue
        if /usr/bin/env -i HOME=/ PATH="$_MAINFRAME_PI_SYSTEM_PATH" \
            LC_ALL=C LANG=C PYTHONSAFEPATH=1 \
            "$resolved" -I -B -c 'import json, os, pathlib, stat, sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' \
            >/dev/null 2>&1; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

_mainframe_pi_python() {
    [[ -n "$_MAINFRAME_PI_PYTHON" ]] || return 1
    /usr/bin/env -i HOME=/ PATH="$_MAINFRAME_PI_SYSTEM_PATH" \
        LC_ALL=C LANG=C PYTHONSAFEPATH=1 \
        "$_MAINFRAME_PI_PYTHON" -I -B - "$@"
}

_mainframe_pi_agent_dir() {
    local requested home_dir

    if [[ -n "${MAINFRAME_PI_AGENT_DIR:-}" ]]; then
        requested="$MAINFRAME_PI_AGENT_DIR"
    elif [[ -n "${PI_CODING_AGENT_DIR:-}" ]]; then
        requested="$PI_CODING_AGENT_DIR"
    else
        home_dir="${HOME:-}"
        [[ -n "$home_dir" ]] || return 1
        requested="$home_dir/.pi/agent"
    fi
    _mainframe_pi_clean_absolute_path "$requested" || return 1
    printf '%s\n' "$requested"
}

_mainframe_pi_receipt_path() {
    printf '%s/.mainframe-pi-receipt.json\n' "$1"
}

# Homebrew's versioned Cellar root disappears on upgrade.  The formula passes
# its stable opt_libexec path, but the manager accepts it only when it resolves
# to this exact, already-validated package root and uses a known Homebrew
# layout.  Caller-supplied lookalikes therefore cannot redirect Pi elsewhere.
_mainframe_pi_select_package_source() {
    local candidate resolved

    _MAINFRAME_PI_PACKAGE_SOURCE="$_MAINFRAME_PI_ROOT"
    _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=false
    [[ "${MAINFRAME_INSTALL_METHOD:-}" == homebrew ]] || return 0
    candidate="${MAINFRAME_HOMEBREW_OPT_LIBEXEC:-}"
    [[ -n "$candidate" ]] || {
        _mainframe_pi_error 'Homebrew did not provide its stable opt_libexec package source'
        return 1
    }
    _mainframe_pi_clean_absolute_path "$candidate" || {
        _mainframe_pi_error 'Homebrew opt_libexec package source is not a clean absolute path'
        return 1
    }
    case "$candidate" in
        /opt/homebrew/opt/mainframe/libexec|\
        /usr/local/opt/mainframe/libexec|\
        /home/linuxbrew/.linuxbrew/opt/mainframe/libexec) ;;
        *)
            _mainframe_pi_error "unrecognized Homebrew opt_libexec package source: $candidate"
            return 1
            ;;
    esac
    [[ -d "$candidate" ]] || {
        _mainframe_pi_error "Homebrew opt_libexec package source does not exist: $candidate"
        return 1
    }
    resolved="$(cd -- "$candidate" 2>/dev/null && pwd -P)" || {
        _mainframe_pi_error "Homebrew opt_libexec package source cannot be resolved: $candidate"
        return 1
    }
    [[ "$resolved" == "$_MAINFRAME_PI_ROOT" ]] || {
        _mainframe_pi_error 'Homebrew opt_libexec does not resolve to this Mainframe package root'
        return 1
    }
    _MAINFRAME_PI_PACKAGE_SOURCE="$candidate"
    _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=true
}

_mainframe_pi_validate_package_root() {
    local required parent

    [[ -z "$_MAINFRAME_PI_SOURCE_UNSAFE" ]] || {
        _mainframe_pi_error "$_MAINFRAME_PI_SOURCE_UNSAFE"
        return 1
    }
    _mainframe_pi_validate_package_directory "$_MAINFRAME_PI_ROOT" || {
        _mainframe_pi_error "Mainframe package root has unsafe ownership, permissions, or symlink ancestry: $_MAINFRAME_PI_ROOT"
        return 1
    }
    for required in \
        "$_MAINFRAME_PI_ROOT/VERSION" \
        "$_MAINFRAME_PI_ROOT/package.json" \
        "$_MAINFRAME_PI_ROOT/config/pi-compatibility.json" \
        "$_MAINFRAME_PI_ROOT/security/gate-rules.json" \
        "$_MAINFRAME_PI_ROOT/security/gate-normalizer.mjs" \
        "$_MAINFRAME_PI_ROOT/skills/pi/SKILL.md" \
        "$_MAINFRAME_PI_ROOT/skills/pi/extensions/mainframe.ts" \
        "$_MAINFRAME_PI_ROOT/lib/pi_restore.sh"; do
        parent="${required%/*}"
        _mainframe_pi_validate_package_directory "$parent" || {
            _mainframe_pi_error "Mainframe Pi resource ancestry is unsafe: $required"
            return 1
        }
        _mainframe_pi_validate_regular_file "$required" root-or-user true || {
            _mainframe_pi_error "Mainframe Pi resource is unsafe or missing: $required"
            return 1
        }
    done
    return 0
}

_mainframe_pi_validate_agent_dir() {
    local agent_dir="$1" home_path=''

    [[ "$agent_dir" != / ]] || {
        _mainframe_pi_error 'refusing to use / as the Pi agent directory'
        return 1
    }
    if [[ -n "${HOME:-}" && -d "$HOME" && ! -L "$HOME" ]]; then
        home_path="$(cd -- "$HOME" 2>/dev/null && pwd -P)" || home_path=''
        [[ -z "$home_path" || "$agent_dir" != "$home_path" ]] || {
            _mainframe_pi_error 'refusing to use HOME itself as the Pi agent directory'
            return 1
        }
    fi
    [[ -d "$agent_dir" ]] || {
        _mainframe_pi_error "Pi agent directory does not exist: $agent_dir"
        return 1
    }
    _mainframe_pi_validate_directory_chain "$agent_dir" user || {
        _mainframe_pi_error "Pi agent directory has unsafe ownership, permissions, or symlink ancestry: $agent_dir"
        return 1
    }
    return 0
}

_mainframe_pi_validate_tree() {
    local path="$1"

    _mainframe_pi_python "$path" "$EUID" <<'PY'
import os
import stat
import sys

root = sys.argv[1]
expected_uid = int(sys.argv[2])

def validate(path, expect_directory=None):
    metadata = os.lstat(path)
    if stat.S_ISLNK(metadata.st_mode):
        raise SystemExit(f"symbolic link is not allowed: {path}")
    if expect_directory is True and not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit(f"directory required: {path}")
    if expect_directory is False and not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"regular file required: {path}")
    if expect_directory is None and not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
        raise SystemExit(f"unsupported file type: {path}")
    if metadata.st_uid != expected_uid:
        raise SystemExit(f"unexpected owner: {path}")
    if stat.S_IMODE(metadata.st_mode) & 0o7022:
        raise SystemExit(f"unsafe permissions: {path}")
    if stat.S_ISREG(metadata.st_mode) and metadata.st_nlink != 1:
        raise SystemExit(f"hard-linked file is not allowed: {path}")

validate(root, os.path.isdir(root))
if os.path.isdir(root):
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        validate(current, True)
        for name in directories:
            validate(os.path.join(current, name), True)
        for name in files:
            validate(os.path.join(current, name), False)
PY
}

_mainframe_pi_validate_mutation_targets() {
    local agent_dir="$1" settings receipt legacy_extension legacy_skill resource_parent metadata owner mode

    settings="$agent_dir/settings.json"
    receipt="$(_mainframe_pi_receipt_path "$agent_dir")"
    legacy_extension="$agent_dir/extensions/mainframe.ts"
    legacy_skill="$agent_dir/skills/mainframe"

    if [[ -e "$settings" || -L "$settings" ]]; then
        _mainframe_pi_validate_regular_file "$settings" user true || {
            _mainframe_pi_error "settings.json is not a safe, singly linked user-owned regular file: $settings"
            return 1
        }
    fi
    if [[ -e "$receipt" || -L "$receipt" ]]; then
        _mainframe_pi_validate_regular_file "$receipt" user true || {
            _mainframe_pi_error "Pi manager receipt is not a safe, singly linked user-owned regular file: $receipt"
            return 1
        }
        metadata="$(_mainframe_pi_stat_owner_mode "$receipt")" || return 1
        [[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
        read -r owner mode <<< "$metadata" || return 1
        [[ "$owner" -eq "$EUID" && "$mode" == 600 ]] || {
            _mainframe_pi_error "Pi manager receipt must be a private mode-600 file: $receipt"
            return 1
        }
    fi
    if [[ -e "$legacy_extension" || -L "$legacy_extension" ]]; then
        resource_parent="${legacy_extension%/*}"
        _mainframe_pi_validate_directory_chain "$resource_parent" user || {
            _mainframe_pi_error "legacy Pi extension parent is unsafe: $resource_parent"
            return 1
        }
        _mainframe_pi_validate_regular_file "$legacy_extension" user true || {
            _mainframe_pi_error "legacy Pi extension is unsafe: $legacy_extension"
            return 1
        }
        _mainframe_pi_validate_tree "$legacy_extension" >/dev/null || {
            _mainframe_pi_error "legacy Pi extension has unsafe ownership, permissions, links, or file type: $legacy_extension"
            return 1
        }
    fi
    if [[ -e "$legacy_skill" || -L "$legacy_skill" ]]; then
        resource_parent="${legacy_skill%/*}"
        _mainframe_pi_validate_directory_chain "$resource_parent" user || {
            _mainframe_pi_error "legacy Pi skill parent is unsafe: $resource_parent"
            return 1
        }
        [[ -d "$legacy_skill" && ! -L "$legacy_skill" ]] || {
            _mainframe_pi_error "legacy Pi skill is not a safe directory: $legacy_skill"
            return 1
        }
        _mainframe_pi_validate_tree "$legacy_skill" >/dev/null || {
            _mainframe_pi_error "legacy Pi skill has unsafe ownership, permissions, links, or file type: $legacy_skill"
            return 1
        }
    fi
    return 0
}

_mainframe_pi_package_preflight() {
    local bash_path

    bash_path="$(_mainframe_pi_validate_executable "${BASH:-}" bash 2>/dev/null)" || {
        _mainframe_pi_error 'current Bash is not a protected system, Homebrew, Linuxbrew, MacPorts, or Nix executable'
        return 1
    }
    [[ -n "$bash_path" ]] || return 1
    _MAINFRAME_PI_BASH="$bash_path"
    _MAINFRAME_PI_PYTHON="$(_mainframe_pi_resolve_python 2>/dev/null)" || {
        _mainframe_pi_error 'a protected fixed-location Python 3.9+ interpreter with the required standard modules is required'
        return 1
    }
    _mainframe_pi_select_package_source || return 1
    _mainframe_pi_validate_package_root || return 1
    return 0
}

_mainframe_pi_preflight() {
    local agent_dir="$1"

    _mainframe_pi_package_preflight || return 1
    _mainframe_pi_validate_agent_dir "$agent_dir" || return 1
    _mainframe_pi_validate_mutation_targets "$agent_dir" || return 1
    return 0
}

_mainframe_pi_collect_status() {
    local agent_dir="$1" output_format="${2:-kv}"
    local settings receipt legacy_extension legacy_skill home_dir extension_present=false skill_present=false
    local project_dir project_settings project_extension project_skill
    local project_extension_present=false project_skill_present=false resource_parent

    settings="$agent_dir/settings.json"
    receipt="$(_mainframe_pi_receipt_path "$agent_dir")"
    legacy_extension="$agent_dir/extensions/mainframe.ts"
    legacy_skill="$agent_dir/skills/mainframe"
    home_dir="${HOME:-}"
    project_dir="$(pwd -P)" || {
        _mainframe_pi_error 'current project directory cannot be resolved physically'
        return 1
    }
    project_settings="$project_dir/.pi/settings.json"
    project_extension="$project_dir/.pi/extensions/mainframe.ts"
    project_skill="$project_dir/.pi/skills/mainframe"
    [[ -f "$legacy_extension" ]] && extension_present=true
    [[ -d "$legacy_skill" ]] && skill_present=true

    if [[ -e "$project_settings" || -L "$project_settings" ]]; then
        resource_parent="${project_settings%/*}"
        _mainframe_pi_validate_directory_chain "$resource_parent" user || {
            _mainframe_pi_error "project Pi settings parent is unsafe: $resource_parent"
            return 1
        }
        _mainframe_pi_validate_regular_file "$project_settings" user true || {
            _mainframe_pi_error "project Pi settings are unsafe: $project_settings"
            return 1
        }
    fi

    if [[ -e "$project_extension" || -L "$project_extension" ]]; then
        resource_parent="${project_extension%/*}"
        _mainframe_pi_validate_directory_chain "$resource_parent" user || {
            _mainframe_pi_error "project Pi extension parent is unsafe: $resource_parent"
            return 1
        }
        _mainframe_pi_validate_regular_file "$project_extension" user true || {
            _mainframe_pi_error "project Pi extension is unsafe: $project_extension"
            return 1
        }
        project_extension_present=true
    fi
    if [[ -e "$project_skill" || -L "$project_skill" ]]; then
        resource_parent="${project_skill%/*}"
        _mainframe_pi_validate_directory_chain "$resource_parent" user || {
            _mainframe_pi_error "project Pi skill parent is unsafe: $resource_parent"
            return 1
        }
        [[ -d "$project_skill" && ! -L "$project_skill" ]] || {
            _mainframe_pi_error "project Pi skill is unsafe: $project_skill"
            return 1
        }
        _mainframe_pi_validate_tree "$project_skill" >/dev/null || {
            _mainframe_pi_error "project Pi skill has unsafe ownership, permissions, links, or file type: $project_skill"
            return 1
        }
        project_skill_present=true
    fi

    _mainframe_pi_python \
        "$settings" "$receipt" "$agent_dir" "$_MAINFRAME_PI_ROOT" \
        "$_MAINFRAME_PI_PACKAGE_SOURCE" "$home_dir" \
        "$extension_present" "$skill_present" "$project_dir" \
        "$project_settings" "$project_extension_present" \
        "$project_skill_present" "$output_format" <<'PY'
import json
import os
import re
import sys

(
    settings_path,
    receipt_path,
    agent_dir,
    package_root,
    package_source,
    home_dir,
) = sys.argv[1:7]
legacy_extension_present = sys.argv[7] == "true"
legacy_skill_present = sys.argv[8] == "true"
project_dir = sys.argv[9]
project_settings_path = sys.argv[10]
project_extension_present = sys.argv[11] == "true"
project_skill_present = sys.argv[12] == "true"
output_format = sys.argv[13]


def read_settings(path, label):
    if not os.path.exists(path):
        return {}, False
    try:
        with open(path, "r", encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid {label}: {error}")
    if not isinstance(document, dict):
        raise SystemExit(f"invalid {label}: top-level value must be an object")
    return document, True


document, settings_present = read_settings(settings_path, "Pi settings.json")
project_document, project_settings_present = read_settings(
    project_settings_path, "project Pi settings.json"
)

receipt_source = None
receipt_present = os.path.exists(receipt_path)
if receipt_present:
    try:
        with open(receipt_path, "r", encoding="utf-8") as handle:
            receipt = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid Mainframe Pi manager receipt: {error}")
    if (
        not isinstance(receipt, dict)
        or set(receipt) != {"schema_version", "manager", "package_source"}
        or receipt.get("schema_version") != 1
        or receipt.get("manager") != "@gtwatts/mainframe-pi"
        or not isinstance(receipt.get("package_source"), str)
    ):
        raise SystemExit("invalid Mainframe Pi manager receipt: schema mismatch")
    receipt_source = receipt["package_source"]
    if (
        not os.path.isabs(receipt_source)
        or receipt_source == "/"
        or receipt_source.endswith("/")
        or os.path.normpath(receipt_source) != receipt_source
        or any(char in receipt_source for char in "\x00\r\n\t")
    ):
        raise SystemExit("invalid Mainframe Pi manager receipt: unsafe package source")

packages = document.get("packages", [])
extensions = document.get("extensions", [])
if not isinstance(packages, list):
    raise SystemExit("invalid Pi settings.json: packages must be an array")
if not isinstance(extensions, list) or not all(isinstance(item, str) for item in extensions):
    raise SystemExit("invalid Pi settings.json: extensions must be an array of strings")
project_packages = project_document.get("packages", [])
if not isinstance(project_packages, list):
    raise SystemExit("invalid project Pi settings.json: packages must be an array")

def source_string(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("source"), str):
        return entry["source"]
    raise SystemExit("invalid Pi settings.json: package entries must be strings or objects with a string source")

def local_path(source, base, *, resolve_links=True):
    source = source.strip()
    if source.startswith("npm:") or source.startswith("git:"):
        return None
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", source):
        return None
    if source == "~" or source.startswith("~/"):
        if not home_dir:
            return None
        source = home_dir + source[1:]
    if not os.path.isabs(source):
        source = os.path.join(base, source)
    source = os.path.normpath(os.path.abspath(source))
    return os.path.realpath(source) if resolve_links else source

def matching_package(entry):
    return local_path(source_string(entry), agent_dir) == package_root

def matching_receipt(entry, base):
    if receipt_source is None:
        return False
    return local_path(source_string(entry), base, resolve_links=False) == receipt_source

def managed_package(entry):
    return matching_package(entry) or matching_receipt(entry, agent_dir)

def resource_enabled(entry, key):
    if not isinstance(entry, dict):
        return True
    if entry.get("autoload") is False:
        return False
    configured = entry.get(key)
    return configured != []

matching = [entry for entry in packages if matching_package(entry)]
managed = [entry for entry in packages if managed_package(entry)]
receipt_matching = [entry for entry in packages if matching_receipt(entry, agent_dir)]
active_entries = [
    entry for entry in matching
    if resource_enabled(entry, "extensions") and resource_enabled(entry, "skills")
]
canonical_entries = [
    entry for entry in matching
    if isinstance(entry, str) and entry == package_source
]
bare_string_entries = [entry for entry in matching if isinstance(entry, str)]

def matching_project_package(entry):
    return (
        local_path(source_string(entry), os.path.dirname(project_settings_path)) == package_root
        or matching_receipt(entry, os.path.dirname(project_settings_path))
    )

project_matching = [entry for entry in project_packages if matching_project_package(entry)]
project_delta_entries = [
    entry for entry in project_matching
    if isinstance(entry, dict) and entry.get("autoload") is False
]

legacy_extension_path = os.path.normpath(os.path.join(agent_dir, "extensions", "mainframe.ts"))

def exact_legacy_extension(entry):
    entry = entry.strip()
    if not entry or entry[0] in "!-" or any(char in entry for char in "*?[]"):
        return False
    if entry.startswith("+"):
        entry = entry[1:]
    return local_path(entry, agent_dir) == legacy_extension_path

legacy_settings_entries = sum(1 for entry in extensions if exact_legacy_extension(entry))
package_entries = len(matching)
package_duplicates = max(0, package_entries - 1)
package_active = bool(active_entries)
managed_package_entries = len(managed)
receipt_package_entries = len(receipt_matching)
receipt_only_entries = sum(1 for entry in managed if not matching_package(entry))
receipt_current = receipt_source == package_source
legacy_collision = package_entries > 0 and (
    legacy_extension_present or legacy_skill_present or legacy_settings_entries > 0
)
project_collision = bool(
    project_extension_present or project_skill_present or project_matching
)

manifest_ready = False
try:
    with open(os.path.join(package_root, "package.json"), "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    pi_manifest = manifest.get("pi", {})
    manifest_ready = (
        "./skills/pi/extensions/mainframe.ts" in pi_manifest.get("extensions", [])
        and "./skills/pi" in pi_manifest.get("skills", [])
    )
except (OSError, TypeError, ValueError):
    manifest_ready = False

restart_needed = managed_package_entries > 0 and (
    not package_active or not manifest_ready or package_duplicates > 0
    or len(canonical_entries) != 1 or len(bare_string_entries) != 1
    or receipt_only_entries > 0 or legacy_collision or project_collision
)

if package_entries == 0:
    if receipt_only_entries:
        state = "upgrade-needed"
    elif legacy_extension_present or legacy_skill_present or legacy_settings_entries:
        state = "legacy"
    elif project_collision:
        state = "project-legacy"
    else:
        state = "not-installed"
elif package_duplicates:
    state = "duplicate"
elif receipt_only_entries:
    state = "upgrade-needed"
elif legacy_collision:
    state = "collision"
elif project_collision:
    state = "project-collision"
elif len(canonical_entries) != 1 or len(bare_string_entries) != 1:
    state = "noncanonical"
elif not package_active or not manifest_ready:
    state = "inactive"
else:
    state = "ready"

result = {
    "agent_dir": agent_dir,
    "mainframe_root": package_root,
    "package_source": package_source,
    "settings_present": settings_present,
    "package_manifest_ready": manifest_ready,
    "package_active": package_active and manifest_ready,
    "package_entries": package_entries,
    "package_canonical_entries": len(canonical_entries),
    "package_bare_string_entries": len(bare_string_entries),
    "package_duplicates": package_duplicates,
    "managed_package_entries": managed_package_entries,
    "receipt_package_entries": receipt_package_entries,
    "receipt_only_entries": receipt_only_entries,
    "manager_receipt_present": receipt_present,
    "manager_receipt_source": receipt_source or "none",
    "manager_receipt_current": receipt_current,
    "legacy_extension_present": legacy_extension_present,
    "legacy_skill_present": legacy_skill_present,
    "legacy_extension_settings_entries": legacy_settings_entries,
    "legacy_precedence_collision": legacy_collision,
    "project_dir": project_dir,
    "project_settings_present": project_settings_present,
    "project_package_entries": len(project_matching),
    "project_package_delta_entries": len(project_delta_entries),
    "project_extension_present": project_extension_present,
    "project_skill_present": project_skill_present,
    "project_precedence_collision": project_collision,
    "restart_needed": restart_needed,
    "state": state,
}

if output_format == "json":
    print(json.dumps(result, separators=(",", ":")))
else:
    for key, value in result.items():
        if isinstance(value, bool):
            value = "true" if value else "false"
        print(f"{key}={value}")
PY
}

_mainframe_pi_status_value() {
    local status_text="$1" wanted="$2" line
    while IFS= read -r line; do
        case "$line" in
            "$wanted"=*) printf '%s\n' "${line#*=}"; return 0 ;;
        esac
    done <<< "$status_text"
    return 1
}

_mainframe_pi_platform_tuple() {
    local uname_bin='' os arch libc='none' getconf_bin='' version

    if [[ -x /usr/bin/uname ]]; then
        uname_bin=/usr/bin/uname
    elif [[ -x /bin/uname ]]; then
        uname_bin=/bin/uname
    else
        return 1
    fi
    os="$("$uname_bin" -s 2>/dev/null)" || return 1
    arch="$("$uname_bin" -m 2>/dev/null)" || return 1
    case "$arch" in
        amd64) arch=x86_64 ;;
        aarch64) arch=arm64 ;;
    esac
    case "$os" in
        Darwin) libc=none ;;
        Linux)
            libc=unknown
            if [[ -x /usr/bin/getconf ]]; then
                getconf_bin=/usr/bin/getconf
            elif [[ -x /bin/getconf ]]; then
                getconf_bin=/bin/getconf
            fi
            if [[ -n "$getconf_bin" ]]; then
                version="$("$getconf_bin" GNU_LIBC_VERSION 2>/dev/null || true)"
                [[ "$version" == glibc\ * ]] && libc=glibc
            fi
            if [[ "$libc" == unknown ]] &&
               compgen -G '/lib/ld-musl-*.so.1' >/dev/null; then
                libc=musl
            fi
            ;;
        *) libc=unknown ;;
    esac
    printf '%s-%s-%s\n' "$os" "$arch" "$libc"
}

# Resolve the first executable named `pi` exactly as this shell's PATH would,
# but never execute it. Empty, relative, dot-segment, and control-character
# PATH entries are ignored so a project-local shim cannot become evidence.
_mainframe_pi_find_cli() {
    local remaining="${_MAINFRAME_PI_DISCOVERY_PATH:-${PATH:-}}"
    local entry candidate resolved last=false project_dir

    project_dir="$(pwd -P)" || return 1

    while [[ "$last" == false ]]; do
        case "$remaining" in
            *:*) entry="${remaining%%:*}"; remaining="${remaining#*:}" ;;
            *) entry="$remaining"; remaining=''; last=true ;;
        esac
        while [[ "$entry" != / && "$entry" == */ ]]; do
            entry="${entry%/}"
        done
        [[ "$entry" == /* && "$entry" != / ]] || continue
        _mainframe_pi_clean_absolute_path "$entry" || continue
        candidate="$entry/pi"
        [[ -x "$candidate" && ( -f "$candidate" || -L "$candidate" ) ]] || continue
        resolved="$(_mainframe_pi_resolve_executable "$candidate" 2>/dev/null)" || continue
        if [[ "$candidate" == "$project_dir" || "$candidate" == "$project_dir/"* ||
              "$resolved" == "$project_dir" || "$resolved" == "$project_dir/"* ]]; then
            continue
        fi
        printf '%s\n%s\n' "$candidate" "$resolved"
        return 0
    done
    return 1
}

# Trust package identity only when the resolved CLI is the exact `bin.pi`
# target declared by its nearest package manifest. The CLI itself is not run.
_mainframe_pi_read_cli_identity() {
    local resolved="$1" package_root manifest

    case "$resolved" in
        */dist/cli.js) package_root="${resolved%/dist/cli.js}" ;;
        *) return 1 ;;
    esac
    _mainframe_pi_clean_absolute_path "$package_root" || return 1
    manifest="$package_root/package.json"
    _mainframe_pi_validate_regular_file "$manifest" root-or-user true || return 1
    _mainframe_pi_python "$manifest" "$resolved" "$package_root" <<'PY'
import json
import os
import re
import sys

manifest_path, resolved_cli, package_root = sys.argv[1:4]
if os.path.getsize(manifest_path) > 1024 * 1024:
    raise SystemExit("Pi package manifest is unexpectedly large")
with open(manifest_path, "r", encoding="utf-8") as handle:
    document = json.load(handle)
if not isinstance(document, dict):
    raise SystemExit("Pi package manifest must be an object")
name = document.get("name")
version = document.get("version")
bin_value = document.get("bin")
if not isinstance(name, str) or not re.fullmatch(r"(?:@[A-Za-z0-9._-]+/)?[A-Za-z0-9._-]+", name):
    raise SystemExit("Pi package name is invalid")
if not isinstance(version, str) or not re.fullmatch(
    r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", version
):
    raise SystemExit("Pi package version is not an exact semantic version")
if isinstance(bin_value, dict):
    bin_target = bin_value.get("pi")
elif isinstance(bin_value, str):
    bin_target = bin_value
else:
    bin_target = None
if not isinstance(bin_target, str) or not bin_target or os.path.isabs(bin_target):
    raise SystemExit("Pi package does not declare a relative bin.pi target")
declared = os.path.realpath(os.path.join(package_root, bin_target))
if declared != resolved_cli:
    raise SystemExit("Pi package bin.pi does not resolve to the selected CLI")
print(name)
print(version)
print(package_root)
PY
}

_mainframe_pi_render_doctor() {
    local status_json="$1" status_available="$2" agent_dir="$3"
    local cli_path="$4" resolved_cli="$5" package_name="$6"
    local package_version="$7" package_root="$8" identity_consistent="$9"
    shift 9
    local platform="$1" output_format="$2"

    _mainframe_pi_python \
        "$_MAINFRAME_PI_ROOT/config/pi-compatibility.json" \
        "$_MAINFRAME_PI_ROOT/VERSION" \
        "$_MAINFRAME_PI_ROOT/security/gate-rules.json" \
        "$status_json" "$status_available" "$agent_dir" \
        "$cli_path" "$resolved_cli" "$package_name" "$package_version" \
        "$package_root" "$identity_consistent" "$platform" "$output_format" \
        "$_MAINFRAME_PI_ROOT" "$_MAINFRAME_PI_BASH" "$BASH_VERSION" <<'PY'
import json
import os
import re
import sys

(
    compatibility_path,
    version_path,
    gate_path,
    status_raw,
    status_available_raw,
    agent_dir,
    cli_path,
    resolved_cli,
    package_name,
    package_version,
    package_root,
    identity_consistent_raw,
    platform,
    output_format,
    mainframe_root,
    bash_path,
    bash_version,
) = sys.argv[1:18]


def fail(message):
    raise SystemExit(f"invalid Pi compatibility evidence: {message}")


def require(condition, message):
    if not condition:
        fail(message)


with open(version_path, "r", encoding="utf-8") as handle:
    mainframe_version = handle.read().strip()
with open(compatibility_path, "r", encoding="utf-8") as handle:
    compatibility_manifest = json.load(handle)
with open(gate_path, "r", encoding="utf-8") as handle:
    gate = json.load(handle)

require(isinstance(compatibility_manifest, dict), "top-level value must be an object")
require(compatibility_manifest.get("schema_version") == 1, "schema_version must be 1")
require(
    compatibility_manifest.get("integration") == "@gtwatts/mainframe-pi",
    "integration identifier mismatch",
)
require(
    compatibility_manifest.get("mainframe_version") == mainframe_version,
    "mainframe_version does not match VERSION",
)
unknown_policy = compatibility_manifest.get("unknown_policy")
require(
    unknown_policy == {"support": "unverified", "ready": False},
    "unknown policy must fail closed",
)
surface = compatibility_manifest.get("required_surface")
require(isinstance(surface, dict), "required_surface must be an object")
expected_tools = [
    "mainframe_awm",
    "mainframe_bash_safety_check",
    "mainframe_exec",
    "mainframe_help",
    "mainframe_install_commands",
    "mainframe_search",
    "mainframe_status",
]
require(surface.get("tools") == expected_tools, "required tool surface drift")
require(
    surface.get("hooks") == ["before_agent_start", "tool_call", "user_bash"],
    "required hook surface drift",
)
require(surface.get("caller_shells") == ["bash", "zsh"], "caller shell coverage drift")
require(surface.get("command") == "mainframe", "Pi command surface drift")
require(surface.get("extension") == "./skills/pi/extensions/mainframe.ts", "extension path drift")
require(surface.get("skill") == "./skills/pi", "skill path drift")

certifications = compatibility_manifest.get("certifications")
require(isinstance(certifications, list) and certifications, "certifications must be a non-empty array")
seen = set()
matches = []
required_capabilities = {
    "local_package_discovery",
    "prompt_hook",
    "seven_tool_surface",
    "agent_bash_gate",
    "tui_user_bash_gate",
    "rpc_user_bash_gate",
    "bash_and_zsh_callers",
}
for record in certifications:
    require(isinstance(record, dict), "each certification must be an object")
    require(record.get("support") in {"certified", "limited"}, "unsupported certification tier")
    require(isinstance(record.get("id"), str) and record["id"], "certification id missing")
    require(
        isinstance(record.get("mainframe_version"), str)
        and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", record["mainframe_version"]),
        "certification mainframe_version missing or invalid",
    )
    require(isinstance(record.get("package"), str) and record["package"], "certification package missing")
    require(isinstance(record.get("version"), str) and record["version"], "certification version missing")
    require(
        isinstance(record.get("npm_integrity"), str)
        and re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", record["npm_integrity"]),
        "certification npm_integrity missing or invalid",
    )
    platforms = record.get("platforms")
    require(isinstance(platforms, list) and platforms, "certification platforms missing")
    require(all(isinstance(item, str) and item for item in platforms), "invalid certification platform")
    capabilities = record.get("capabilities")
    require(isinstance(capabilities, dict), "certification capabilities missing")
    require(set(capabilities) == required_capabilities, "certification capability keys drift")
    limitations = record.get("limitations")
    require(isinstance(limitations, list), "certification limitations must be an array")
    if record["support"] == "certified":
        require(all(value == "verified" for value in capabilities.values()), "certified route is not verified")
        require(not limitations, "certified record must not carry limitations")
    else:
        require(bool(limitations), "limited record requires an explicit limitation")
    for candidate_platform in platforms:
        key = (record["mainframe_version"], record["package"], record["version"], candidate_platform)
        require(key not in seen, "duplicate MAINFRAME/package/version/platform record")
        seen.add(key)
        if key == (mainframe_version, package_name, package_version, platform):
            matches.append(record)

require(len(matches) <= 1, "ambiguous exact compatibility match")
identity_consistent = identity_consistent_raw == "true"
match = matches[0] if identity_consistent and matches else None
support = match["support"] if match else "unverified"
profile = match.get("profile") if match else None
capabilities = match.get("capabilities", {}) if match else {}
limitations = match.get("limitations", []) if match else []

require(isinstance(gate, dict), "gate-rules.json must be an object")
gate_rules = gate.get("rules")
gate_ready = gate.get("version") == mainframe_version and isinstance(gate_rules, list) and bool(gate_rules)
require(gate_ready, "canonical Bash gate is missing, empty, or version-mismatched")

status_available = status_available_raw == "true"
if status_available:
    status = json.loads(status_raw)
    require(isinstance(status, dict), "Pi status must be an object")
    disk_state = status.get("state", "inspection-failed")
else:
    status = {"agent_dir": agent_dir, "state": "not-initialized"}
    disk_state = "not-initialized"

if cli_path == "none":
    overall_state = "pi-not-found"
    reason_codes = ["pi-cli-not-found"]
elif not identity_consistent:
    overall_state = "compatibility-unverified"
    reason_codes = ["pi-package-identity-unverified"]
elif disk_state in {"project-legacy", "project-collision"}:
    overall_state = "project-override"
    reason_codes = [f"pi-disk-{disk_state}"]
elif disk_state != "ready":
    overall_state = "setup-required"
    reason_codes = [f"pi-disk-{disk_state}"]
elif support == "limited":
    overall_state = "limited"
    reason_codes = ["pi-version-known-limited"]
elif support != "certified":
    overall_state = "compatibility-unverified"
    reason_codes = ["pi-version-platform-unverified"]
else:
    overall_state = "activation-unverified"
    reason_codes = ["live-pi-process-not-inspectable-from-external-shell"]

actions = []
if cli_path == "none":
    actions.append({
        "code": "install-or-expose-pi",
        "context": "human-terminal",
        "command": None,
        "message": "Install Pi or add its trusted executable directory to PATH, then rerun mainframe pi doctor.",
    })
elif disk_state == "not-initialized":
    actions.append({
        "code": "initialize-pi",
        "context": "human-terminal",
        "command": "pi",
        "message": "Run Pi once to create its user agent directory, exit Pi, then rerun mainframe pi doctor.",
    })
elif disk_state in {"project-legacy", "project-collision"}:
    actions.append({
        "code": "review-project-pi-override",
        "context": "human-terminal",
        "command": "mainframe pi status --json",
        "message": "Review the project-local .pi configuration separately; MAINFRAME will not rewrite it.",
    })
elif disk_state != "ready":
    actions.extend([
        {
            "code": "preview-mainframe-pi-install",
            "context": "human-terminal",
            "command": "mainframe pi install --dry-run",
            "message": "Review the exact package migration without changing files.",
        },
        {
            "code": "confirm-mainframe-pi-install",
            "context": "human-terminal",
            "command": "mainframe pi install --yes",
            "message": "After reviewing the preview, the human operator may activate the package.",
        },
    ])

if support == "limited":
    actions.append({
        "code": "upgrade-pi-for-full-coverage",
        "context": "human-terminal",
        "command": None,
        "message": "Upgrade to an exactly certified Pi version; avoid Pi RPC Bash while this limited version is in use.",
    })
elif support != "certified" and cli_path != "none":
    actions.append({
        "code": "treat-pi-compatibility-as-unverified",
        "context": "operator-review",
        "command": None,
        "message": "Do not infer full interception for an unlisted package, version, or platform.",
    })

if disk_state == "ready" and support == "certified":
    actions.extend([
        {
            "code": "reload-pi",
            "context": "inside-pi",
            "command": "/reload",
            "message": "Reload Pi or restart it so the current process reads the canonical package.",
        },
        {
            "code": "verify-live-mainframe",
            "context": "inside-pi",
            "command": compatibility_manifest["runtime_verification_command"],
            "message": "Run the in-process doctor; only that command can establish live activation.",
        },
    ])

result = {
    "schema_version": 1,
    "command": "pi-doctor",
    "mode": "read-only-offline",
    "overall": {
        "state": overall_state,
        "ready": False,
        "reason_codes": reason_codes,
    },
    "platform": {
        "tuple": platform,
        "certification_scope": "exact-package-version-platform",
    },
    "mainframe": {
        "root": mainframe_root,
        "version": mainframe_version,
        "bash": {"path": bash_path, "version": bash_version},
        "python": {
            "path": sys.executable,
            "version": ".".join(str(item) for item in sys.version_info[:3]),
            "requirement": "Python >=3.9 with json, os, pathlib, stat, and sys standard-library modules",
        },
        "gate": {
            "ready": gate_ready,
            "version": gate.get("version"),
            "rule_count": len(gate_rules),
        },
    },
    "pi": {
        "cli_state": "found" if cli_path != "none" else "not-found",
        "cli_path": None if cli_path == "none" else cli_path,
        "resolved_cli_path": None if resolved_cli == "none" else resolved_cli,
        "package_root": None if package_root == "unknown" else package_root,
        "package": None if package_name == "unknown" else package_name,
        "version": None if package_version == "unknown" else package_version,
        "identity_consistent": identity_consistent,
        "executed": False,
    },
    "compatibility": {
        "known": match is not None,
        "match_id": match.get("id") if match else None,
        "support": support,
        "profile": profile,
        "capabilities": capabilities,
        "limitations": limitations,
        "evidence_date": match.get("evidence_date") if match else None,
        "evidence": match.get("evidence", []) if match else [],
        "npm_integrity": match.get("npm_integrity") if match else None,
    },
    "integration": {
        "disk_state": disk_state,
        "configured_active": bool(status.get("package_active", False)),
        "runtime_activation": "unverified",
        "runtime_verification_command": compatibility_manifest["runtime_verification_command"],
        "status": status,
    },
    "actions": actions,
    "boundary": "MAINFRAME is an approval, policy, and audit layer, not an operating-system sandbox.",
}

if output_format == "json":
    print(json.dumps(result, separators=(",", ":")))
else:
    print("MAINFRAME Pi Doctor")
    print("===================")
    print("Mode:              read-only and offline; Pi was not executed")
    print(f"Platform:          {platform}")
    print(f"Pi CLI:            {cli_path if cli_path != 'none' else 'NOT FOUND'}")
    if package_name != "unknown" and package_version != "unknown":
        print(f"Pi package:        {package_name} {package_version}")
    else:
        print("Pi package:        identity unverified")
    print(f"Compatibility:     {support.upper()}")
    if limitations:
        for limitation in limitations:
            print(f"  Limitation:      {limitation}")
    disk_label = "CANONICAL" if disk_state == "ready" else disk_state.upper()
    print(f"Disk state:        {disk_label}")
    print("Live Pi load:      UNVERIFIED (external commands cannot inspect a running Pi process)")
    print(f"Result:            {overall_state.upper().replace('-', '_')}")
    if actions:
        print("")
        print("Next actions:")
        for action in actions:
            command = f" [{action['command']}]" if action["command"] else ""
            print(f"  - {action['message']}{command}")
    print("")
    print(f"Boundary: {result['boundary']}")
    print("No Pi process was started and no file, package, project, shell, or network state changed.")

# External inspection can never establish live activation. Distinguish a
# normal action-required diagnosis from a broken/unsafe inspection (exit 1).
raise SystemExit(2)
PY
}

_mainframe_pi_would_change() {
    local status_text="$1" value

    value="$(_mainframe_pi_status_value "$status_text" package_active)" || return 1
    [[ "$value" == true ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" package_entries)" || return 1
    [[ "$value" == 1 ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" package_canonical_entries)" || return 1
    [[ "$value" == 1 ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" package_bare_string_entries)" || return 1
    [[ "$value" == 1 ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" managed_package_entries)" || return 1
    [[ "$value" == 1 ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" manager_receipt_current)" || return 1
    [[ "$value" == true ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" legacy_extension_present)" || return 1
    [[ "$value" == false ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" legacy_skill_present)" || return 1
    [[ "$value" == false ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" legacy_extension_settings_entries)" || return 1
    [[ "$value" == 0 ]] || return 0
    return 1
}

_mainframe_pi_would_remove() {
    local status_text="$1" value

    value="$(_mainframe_pi_status_value "$status_text" managed_package_entries)" || return 1
    [[ "$value" == 0 ]] || return 0
    value="$(_mainframe_pi_status_value "$status_text" manager_receipt_present)" || return 1
    [[ "$value" == false ]] || return 0
    return 1
}

_mainframe_pi_project_blocked() {
    local status_text="$1" value

    for value in \
        project_extension_present \
        project_skill_present \
        project_package_entries; do
        case "$(_mainframe_pi_status_value "$status_text" "$value")" in
            true|[1-9]*) return 0 ;;
        esac
    done
    return 1
}

_mainframe_pi_fixed_mktemp() {
    if [[ -x /usr/bin/mktemp ]]; then
        /usr/bin/mktemp "$@"
    elif [[ -x /bin/mktemp ]]; then
        /bin/mktemp "$@"
    else
        return 1
    fi
}

_mainframe_pi_fixed_date() {
    if [[ -x /bin/date ]]; then
        /bin/date "$@"
    elif [[ -x /usr/bin/date ]]; then
        /usr/bin/date "$@"
    else
        return 1
    fi
}

_mainframe_pi_prepare_settings() {
    local settings="$1" temp="$2" backup="$3" agent_dir="$4"
    local action="$5" receipt_source="$6"

    _mainframe_pi_python "$settings" "$temp" "$backup" "$agent_dir" \
        "$_MAINFRAME_PI_ROOT" "$_MAINFRAME_PI_PACKAGE_SOURCE" \
        "${HOME:-}" "$action" "$receipt_source" "$EUID" <<'PY'
import hashlib
import json
import os
import re
import stat
import sys

(
    settings_path,
    temp_path,
    backup_dir,
    agent_dir,
    package_root,
    package_source,
    home_dir,
    action,
    receipt_source,
) = sys.argv[1:10]
expected_uid = int(sys.argv[10])
if action not in {"install", "remove"}:
    raise SystemExit("invalid Pi package transaction action")
if receipt_source == "none":
    receipt_source = None

def read_settings():
    if not os.path.exists(settings_path):
        return b"", {}, "ABSENT", 0o600
    metadata_before = os.lstat(settings_path)
    if stat.S_ISLNK(metadata_before.st_mode) or not stat.S_ISREG(metadata_before.st_mode):
        raise SystemExit("settings.json changed to an unsafe file type")
    if metadata_before.st_uid != expected_uid or metadata_before.st_nlink != 1:
        raise SystemExit("settings.json ownership or link count changed")
    if stat.S_IMODE(metadata_before.st_mode) & 0o7022:
        raise SystemExit("settings.json permissions changed to an unsafe mode")
    with open(settings_path, "rb") as handle:
        raw = handle.read()
        metadata_after = os.fstat(handle.fileno())
    if (metadata_before.st_dev, metadata_before.st_ino) != (metadata_after.st_dev, metadata_after.st_ino):
        raise SystemExit("settings.json changed while it was read")
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid Pi settings.json: {error}")
    if not isinstance(document, dict):
        raise SystemExit("invalid Pi settings.json: top-level value must be an object")
    return raw, document, hashlib.sha256(raw).hexdigest(), stat.S_IMODE(metadata_before.st_mode)

raw, document, expected_digest, original_mode = read_settings()
packages = document.get("packages", [])
extensions = document.get("extensions", [])
if not isinstance(packages, list):
    raise SystemExit("invalid Pi settings.json: packages must be an array")
if not isinstance(extensions, list) or not all(isinstance(item, str) for item in extensions):
    raise SystemExit("invalid Pi settings.json: extensions must be an array of strings")

def source_string(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("source"), str):
        return entry["source"]
    raise SystemExit("invalid Pi settings.json: package entries must be strings or objects with a string source")

def local_path(source, base, *, resolve_links=True):
    source = source.strip()
    if source.startswith("npm:") or source.startswith("git:"):
        return None
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", source):
        return None
    if source == "~" or source.startswith("~/"):
        if not home_dir:
            return None
        source = home_dir + source[1:]
    if not os.path.isabs(source):
        source = os.path.join(base, source)
    source = os.path.normpath(os.path.abspath(source))
    return os.path.realpath(source) if resolve_links else source

def matches_root(entry):
    return local_path(source_string(entry), agent_dir) == package_root

def matches_receipt(entry):
    return receipt_source is not None and (
        local_path(source_string(entry), agent_dir, resolve_links=False) == receipt_source
    )

next_packages = [
    entry for entry in packages
    if not matches_root(entry) and not matches_receipt(entry)
]
if action == "install":
    next_packages.append(package_source)

legacy_extension = os.path.normpath(os.path.join(agent_dir, "extensions", "mainframe.ts"))

def exact_legacy(entry):
    entry = entry.strip()
    if not entry or entry[0] in "!-" or any(char in entry for char in "*?[]"):
        return False
    if entry.startswith("+"):
        entry = entry[1:]
    return local_path(entry, agent_dir) == legacy_extension

next_extensions = (
    [entry for entry in extensions if not exact_legacy(entry)]
    if action == "install"
    else list(extensions)
)
document["packages"] = next_packages
if action == "install" and "extensions" in document:
    document["extensions"] = next_extensions

next_raw = (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
settings_changed = (
    (action == "install" and not os.path.exists(settings_path))
    or (os.path.exists(settings_path) and document != json.loads(raw.decode("utf-8")))
)
new_digest = hashlib.sha256(next_raw).hexdigest()

if expected_digest == "ABSENT":
    marker_path = os.path.join(backup_dir, "settings.absent")
    descriptor = os.open(marker_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(descriptor)
else:
    backup_path = os.path.join(backup_dir, "settings.json.before")
    descriptor = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, raw)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    mode_path = os.path.join(backup_dir, "settings.mode")
    descriptor = os.open(mode_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, f"{original_mode:o}\n".encode("ascii"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

if settings_changed:
    descriptor = os.open(temp_path, os.O_WRONLY | os.O_TRUNC)
    try:
        os.write(descriptor, next_raw)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(temp_path, original_mode)

print(expected_digest)
print(new_digest)
print("true" if settings_changed else "false")
PY
}

_mainframe_pi_prepare_receipt() {
    local receipt="$1" temp="$2" backup="$3" action="$4"

    _mainframe_pi_python "$receipt" "$temp" "$backup" "$action" \
        "$_MAINFRAME_PI_PACKAGE_SOURCE" "$EUID" <<'PY'
import hashlib
import json
import os
import stat
import sys

receipt_path, temp_path, backup_dir, action, package_source = sys.argv[1:6]
expected_uid = int(sys.argv[6])
if action not in {"install", "remove"}:
    raise SystemExit("invalid Pi receipt transaction action")

if os.path.exists(receipt_path):
    before = os.lstat(receipt_path)
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        raise SystemExit("Pi manager receipt changed to an unsafe file type")
    if before.st_uid != expected_uid or before.st_nlink != 1:
        raise SystemExit("Pi manager receipt ownership or link count changed")
    if stat.S_IMODE(before.st_mode) != 0o600:
        raise SystemExit("Pi manager receipt permissions changed to an unsafe mode")
    with open(receipt_path, "rb") as handle:
        raw = handle.read()
        after = os.fstat(handle.fileno())
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise SystemExit("Pi manager receipt changed while it was read")
    try:
        prior = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid Mainframe Pi manager receipt: {error}")
    if (
        not isinstance(prior, dict)
        or set(prior) != {"schema_version", "manager", "package_source"}
        or prior.get("schema_version") != 1
        or prior.get("manager") != "@gtwatts/mainframe-pi"
        or not isinstance(prior.get("package_source"), str)
    ):
        raise SystemExit("invalid Mainframe Pi manager receipt: schema mismatch")
    prior_source = prior["package_source"]
    if (
        not os.path.isabs(prior_source)
        or prior_source == "/"
        or prior_source.endswith("/")
        or os.path.normpath(prior_source) != prior_source
        or any(char in prior_source for char in "\x00\r\n\t")
    ):
        raise SystemExit("invalid Mainframe Pi manager receipt: unsafe package source")
    expected_digest = hashlib.sha256(raw).hexdigest()
    backup_path = os.path.join(backup_dir, "manager-receipt.before.json")
    descriptor = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, raw)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
else:
    raw = b""
    prior_source = "none"
    expected_digest = "ABSENT"
    marker = os.path.join(backup_dir, "manager-receipt.absent")
    descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(descriptor)

if action == "install":
    document = {
        "schema_version": 1,
        "manager": "@gtwatts/mainframe-pi",
        "package_source": package_source,
    }
    next_raw = (json.dumps(document, indent=2) + "\n").encode("utf-8")
    next_digest = hashlib.sha256(next_raw).hexdigest()
    changed = raw != next_raw
    if changed:
        descriptor = os.open(temp_path, os.O_WRONLY | os.O_TRUNC)
        try:
            os.fchmod(descriptor, 0o600)
            os.write(descriptor, next_raw)
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
else:
    next_digest = "ABSENT"
    changed = expected_digest != "ABSENT"

print(expected_digest)
print(next_digest)
print("true" if changed else "false")
print(prior_source)
PY
}

_mainframe_pi_commit_receipt() {
    local receipt="$1" temp="$2" expected_digest="$3" action="$4"

    _mainframe_pi_python "$receipt" "$temp" "$expected_digest" "$action" "$EUID" <<'PY'
import hashlib
import os
import stat
import sys

receipt_path, temp_path, expected_digest, action = sys.argv[1:5]
expected_uid = int(sys.argv[5])

if expected_digest == "ABSENT":
    if os.path.lexists(receipt_path):
        raise SystemExit("Pi manager receipt appeared during the transaction")
else:
    metadata = os.lstat(receipt_path)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SystemExit("Pi manager receipt changed to an unsafe file type")
    if metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise SystemExit("Pi manager receipt identity changed")
    with open(receipt_path, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    if digest != expected_digest:
        raise SystemExit("Pi manager receipt changed concurrently")

if action == "install":
    metadata = os.lstat(temp_path)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SystemExit("prepared Pi manager receipt is unsafe")
    if metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise SystemExit("prepared Pi manager receipt identity is unsafe")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise SystemExit("prepared Pi manager receipt permissions are unsafe")
    os.replace(temp_path, receipt_path)
elif action == "remove":
    os.unlink(receipt_path)
else:
    raise SystemExit("invalid Pi receipt transaction action")

directory = os.open(os.path.dirname(receipt_path), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
}

_mainframe_pi_restore_receipt() {
    local receipt="$1" backup="$2" post_digest="$3"

    _mainframe_pi_python "$receipt" "$backup" "$post_digest" "$EUID" <<'PY'
import hashlib
import os
import stat
import sys
import tempfile

receipt_path, backup_dir, post_digest = sys.argv[1:4]
expected_uid = int(sys.argv[4])

if post_digest == "ABSENT":
    if os.path.lexists(receipt_path):
        raise SystemExit("refusing to roll back a receipt that reappeared")
else:
    metadata = os.lstat(receipt_path)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SystemExit("refusing to roll back an unsafe Pi manager receipt")
    if metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise SystemExit("refusing to roll back a changed Pi manager receipt identity")
    with open(receipt_path, "rb") as handle:
        if hashlib.sha256(handle.read()).hexdigest() != post_digest:
            raise SystemExit("refusing to overwrite a Pi manager receipt changed after commit")

backup_path = os.path.join(backup_dir, "manager-receipt.before.json")
absent_marker = os.path.join(backup_dir, "manager-receipt.absent")
if os.path.isfile(backup_path):
    descriptor, temporary = tempfile.mkstemp(
        prefix=".mainframe-pi-receipt.rollback.",
        dir=os.path.dirname(receipt_path),
    )
    try:
        os.fchmod(descriptor, 0o600)
        with open(backup_path, "rb") as handle:
            os.write(descriptor, handle.read())
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary, receipt_path)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)
elif os.path.isfile(absent_marker):
    if os.path.lexists(receipt_path):
        os.unlink(receipt_path)
else:
    raise SystemExit("Pi manager receipt rollback snapshot is missing")

directory = os.open(os.path.dirname(receipt_path), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
}

_mainframe_pi_commit_settings() {
    local settings="$1" temp="$2" expected_digest="$3"

    _mainframe_pi_python "$settings" "$temp" "$expected_digest" "$EUID" <<'PY'
import hashlib
import os
import stat
import sys

settings_path, temp_path, expected_digest = sys.argv[1:4]
expected_uid = int(sys.argv[4])

if expected_digest == "ABSENT":
    if os.path.lexists(settings_path):
        raise SystemExit("settings.json appeared during the transaction")
else:
    metadata = os.lstat(settings_path)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SystemExit("settings.json changed to an unsafe file type")
    if metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise SystemExit("settings.json ownership or link count changed")
    with open(settings_path, "rb") as handle:
        current_digest = hashlib.sha256(handle.read()).hexdigest()
    if current_digest != expected_digest:
        raise SystemExit("settings.json changed concurrently")

temp_metadata = os.lstat(temp_path)
if stat.S_ISLNK(temp_metadata.st_mode) or not stat.S_ISREG(temp_metadata.st_mode):
    raise SystemExit("prepared settings file is unsafe")
if temp_metadata.st_uid != expected_uid or temp_metadata.st_nlink != 1:
    raise SystemExit("prepared settings file ownership or link count is unsafe")
if stat.S_IMODE(temp_metadata.st_mode) & 0o7022:
    raise SystemExit("prepared settings file permissions are unsafe")

os.replace(temp_path, settings_path)
directory = os.open(os.path.dirname(settings_path), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
}

_mainframe_pi_restore_settings() {
    local settings="$1" backup="$2" installed_digest="$3"

    _mainframe_pi_python "$settings" "$backup" "$installed_digest" "$EUID" <<'PY'
import hashlib
import os
import stat
import sys
import tempfile

settings_path, backup_dir, installed_digest = sys.argv[1:4]
expected_uid = int(sys.argv[4])

metadata = os.lstat(settings_path)
if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
    raise SystemExit("refusing to roll back an unsafe settings.json")
if metadata.st_uid != expected_uid or metadata.st_nlink != 1:
    raise SystemExit("refusing to roll back a changed settings.json identity")
with open(settings_path, "rb") as handle:
    if hashlib.sha256(handle.read()).hexdigest() != installed_digest:
        raise SystemExit("refusing to overwrite settings.json changed after install")

backup_path = os.path.join(backup_dir, "settings.json.before")
absent_marker = os.path.join(backup_dir, "settings.absent")
if os.path.isfile(backup_path):
    with open(backup_path, "rb") as handle:
        original = handle.read()
    with open(os.path.join(backup_dir, "settings.mode"), "r", encoding="ascii") as handle:
        original_mode = int(handle.read().strip(), 8)
    if original_mode & 0o7022:
        raise SystemExit("settings rollback mode is unsafe")
    descriptor, temp_path = tempfile.mkstemp(prefix=".settings.mainframe-rollback.", dir=os.path.dirname(settings_path))
    try:
        os.fchmod(descriptor, original_mode)
        os.write(descriptor, original)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temp_path, settings_path)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temp_path):
            os.unlink(temp_path)
elif os.path.isfile(absent_marker):
    os.unlink(settings_path)
else:
    raise SystemExit("settings rollback snapshot is missing")

directory = os.open(os.path.dirname(settings_path), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
}

_mainframe_pi_verify_installed_state() {
    local agent_dir="$1" status_text value

    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    value="$(_mainframe_pi_status_value "$status_text" state)" || return 1
    [[ "$value" == ready ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" package_entries)" || return 1
    [[ "$value" == 1 ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" package_canonical_entries)" || return 1
    [[ "$value" == 1 ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" package_bare_string_entries)" || return 1
    [[ "$value" == 1 ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" managed_package_entries)" || return 1
    [[ "$value" == 1 ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" manager_receipt_current)" || return 1
    [[ "$value" == true ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" legacy_extension_settings_entries)" || return 1
    [[ "$value" == 0 ]] || return 1
    return 0
}

_mainframe_pi_verify_removed_state() {
    local agent_dir="$1" status_text value

    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    value="$(_mainframe_pi_status_value "$status_text" managed_package_entries)" || return 1
    [[ "$value" == 0 ]] || return 1
    value="$(_mainframe_pi_status_value "$status_text" manager_receipt_present)" || return 1
    [[ "$value" == false ]] || return 1
    return 0
}

_mainframe_pi_rollback() {
    local agent_dir="$1" settings="$2" settings_committed="$3" installed_digest="$4"
    local extension_moved="$5" skill_moved="$6" receipt="$7"
    local receipt_committed="$8" receipt_post_digest="$9" rollback_ok=true
    local legacy_extension legacy_skill backup_extension backup_skill

    legacy_extension="$agent_dir/extensions/mainframe.ts"
    legacy_skill="$agent_dir/skills/mainframe"
    backup_extension="$_MAINFRAME_PI_BACKUP_DIR/extensions/mainframe.ts"
    backup_skill="$_MAINFRAME_PI_BACKUP_DIR/skills/mainframe"

    if [[ "$receipt_committed" == true ]]; then
        _mainframe_pi_restore_receipt "$receipt" "$_MAINFRAME_PI_BACKUP_DIR" \
            "$receipt_post_digest" || rollback_ok=false
    fi
    if [[ "$skill_moved" == true ]]; then
        if [[ ! -e "$legacy_skill" && ! -L "$legacy_skill" ]]; then
            /bin/mv -- "$backup_skill" "$legacy_skill" || rollback_ok=false
        else
            rollback_ok=false
        fi
    fi
    if [[ "$extension_moved" == true ]]; then
        if [[ ! -e "$legacy_extension" && ! -L "$legacy_extension" ]]; then
            /bin/mv -- "$backup_extension" "$legacy_extension" || rollback_ok=false
        else
            rollback_ok=false
        fi
    fi
    if [[ "$settings_committed" == true ]]; then
        _mainframe_pi_restore_settings "$settings" "$_MAINFRAME_PI_BACKUP_DIR" "$installed_digest" || rollback_ok=false
    fi
    [[ "$rollback_ok" == true ]]
}

_mainframe_pi_install_transaction() {
    local agent_dir="$1" previous_receipt_source="${2:-none}"
    local settings receipt legacy_extension legacy_skill timestamp old_umask temp_file receipt_temp
    local prepared expected_digest installed_digest settings_changed
    local receipt_prepared receipt_expected_digest receipt_post_digest receipt_changed receipt_prior_source
    local settings_committed=false receipt_committed=false extension_moved=false skill_moved=false failed=false
    local restore_available=false

    settings="$agent_dir/settings.json"
    receipt="$(_mainframe_pi_receipt_path "$agent_dir")"
    legacy_extension="$agent_dir/extensions/mainframe.ts"
    legacy_skill="$agent_dir/skills/mainframe"
    timestamp="$(_mainframe_pi_fixed_date -u '+%Y%m%dT%H%M%SZ')" || {
        _mainframe_pi_error 'could not create a UTC backup timestamp'
        return 1
    }
    [[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
        _mainframe_pi_error 'the backup timestamp was invalid'
        return 1
    }

    old_umask="$(umask)"
    umask 077
    _MAINFRAME_PI_BACKUP_DIR="$(_mainframe_pi_fixed_mktemp -d \
        "$agent_dir/.mainframe-pi-backup-$timestamp.XXXXXX")" || {
        umask "$old_umask"
        _mainframe_pi_error 'could not create the private Pi migration backup'
        return 1
    }
    temp_file="$(_mainframe_pi_fixed_mktemp \
        "$agent_dir/.settings.mainframe.XXXXXX")" || {
        umask "$old_umask"
        _mainframe_pi_error "could not prepare settings; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        return 1
    }
    receipt_temp="$(_mainframe_pi_fixed_mktemp \
        "$agent_dir/.mainframe-pi-receipt.XXXXXX")" || {
        umask "$old_umask"
        /bin/rm -f -- "$temp_file"
        _mainframe_pi_error "could not prepare manager receipt; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        return 1
    }
    umask "$old_umask"
    /bin/chmod 700 "$_MAINFRAME_PI_BACKUP_DIR" || failed=true
    /bin/chmod 600 "$temp_file" || failed=true
    /bin/chmod 600 "$receipt_temp" || failed=true

    if [[ "$failed" == false ]]; then
        prepared="$(_mainframe_pi_prepare_settings \
            "$settings" "$temp_file" "$_MAINFRAME_PI_BACKUP_DIR" "$agent_dir" \
            install "$previous_receipt_source")" || failed=true
    fi
    if [[ "$failed" == false ]]; then
        receipt_prepared="$(_mainframe_pi_prepare_receipt \
            "$receipt" "$receipt_temp" "$_MAINFRAME_PI_BACKUP_DIR" install)" || failed=true
    fi
    if [[ "$failed" == false ]]; then
        receipt_expected_digest="${receipt_prepared%%$'\n'*}"
        receipt_prepared="${receipt_prepared#*$'\n'}"
        receipt_post_digest="${receipt_prepared%%$'\n'*}"
        receipt_prepared="${receipt_prepared#*$'\n'}"
        receipt_changed="${receipt_prepared%%$'\n'*}"
        receipt_prior_source="${receipt_prepared##*$'\n'}"
        [[ "$receipt_expected_digest" == ABSENT || "$receipt_expected_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$receipt_post_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$receipt_changed" == true || "$receipt_changed" == false ]] || failed=true
        [[ "$receipt_prior_source" == "$previous_receipt_source" ]] || failed=true
    fi
    if [[ "$failed" == false ]]; then
        expected_digest="${prepared%%$'\n'*}"
        prepared="${prepared#*$'\n'}"
        installed_digest="${prepared%%$'\n'*}"
        settings_changed="${prepared##*$'\n'}"
        [[ "$expected_digest" == ABSENT || "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$installed_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$settings_changed" == true || "$settings_changed" == false ]] || failed=true
    fi

    if [[ "$failed" == false && -f "$legacy_extension" ]]; then
        /bin/mkdir -m 700 "$_MAINFRAME_PI_BACKUP_DIR/extensions" || failed=true
        if [[ "$failed" == false ]]; then
            /bin/mv -- "$legacy_extension" "$_MAINFRAME_PI_BACKUP_DIR/extensions/mainframe.ts" || failed=true
            if [[ "$failed" == false ]]; then
                extension_moved=true
                _MAINFRAME_PI_QUARANTINED_EXTENSION="$_MAINFRAME_PI_BACKUP_DIR/extensions/mainframe.ts"
            fi
        fi
    fi
    if [[ "$failed" == false && -d "$legacy_skill" ]]; then
        /bin/mkdir -m 700 "$_MAINFRAME_PI_BACKUP_DIR/skills" || failed=true
        if [[ "$failed" == false ]]; then
            /bin/mv -- "$legacy_skill" "$_MAINFRAME_PI_BACKUP_DIR/skills/mainframe" || failed=true
            if [[ "$failed" == false ]]; then
                skill_moved=true
                _MAINFRAME_PI_QUARANTINED_SKILL="$_MAINFRAME_PI_BACKUP_DIR/skills/mainframe"
            fi
        fi
    fi
    if [[ "$failed" == false && "$settings_changed" == true ]]; then
        _mainframe_pi_commit_settings "$settings" "$temp_file" "$expected_digest" || failed=true
        if [[ "$failed" == false ]]; then
            settings_committed=true
            _MAINFRAME_PI_SETTINGS_UPDATED=true
        fi
    fi
    if [[ "$failed" == false && "$receipt_changed" == true ]]; then
        _mainframe_pi_commit_receipt "$receipt" "$receipt_temp" \
            "$receipt_expected_digest" install || failed=true
        [[ "$failed" == true ]] || receipt_committed=true
    fi
    if [[ "$failed" == false ]]; then
        _mainframe_pi_verify_installed_state "$agent_dir" || failed=true
    fi

    [[ ! -e "$temp_file" && ! -L "$temp_file" ]] || /bin/rm -f -- "$temp_file"
    [[ ! -e "$receipt_temp" && ! -L "$receipt_temp" ]] || /bin/rm -f -- "$receipt_temp"

    if [[ "$failed" == true ]]; then
        if _mainframe_pi_rollback "$agent_dir" "$settings" "$settings_committed" \
            "${installed_digest:-}" "$extension_moved" "$skill_moved" \
            "$receipt" "$receipt_committed" "${receipt_post_digest:-}"; then
            _mainframe_pi_error "install failed; rollback=complete; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        else
            _mainframe_pi_error "install failed; rollback=incomplete; recovery_backup=$_MAINFRAME_PI_BACKUP_DIR"
        fi
        return 1
    fi

    if [[ "$expected_digest" != ABSENT && "$receipt_expected_digest" == ABSENT &&
          "$extension_moved" == true && "$skill_moved" == true ]]; then
        restore_available=true
    fi

    printf '%s\n' \
        'action=install' \
        'dry_run=false' \
        'changed=true' \
        "agent_dir=$agent_dir" \
        "mainframe_root=$_MAINFRAME_PI_ROOT" \
        "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
        "backup_dir=$_MAINFRAME_PI_BACKUP_DIR" \
        "backup_id=${_MAINFRAME_PI_BACKUP_DIR##*/}" \
        "restore_available=$restore_available" \
        "quarantined_extension=$_MAINFRAME_PI_QUARANTINED_EXTENSION" \
        "quarantined_skill=$_MAINFRAME_PI_QUARANTINED_SKILL" \
        "settings_updated=$_MAINFRAME_PI_SETTINGS_UPDATED" \
        "receipt_updated=$receipt_changed" \
        'restart_needed=true' \
        'reload_hint=Use /reload in Pi, or restart Pi, then run /mainframe doctor.'
    return 0
}

_mainframe_pi_remove_transaction() {
    local agent_dir="$1" previous_receipt_source="${2:-none}"
    local settings receipt timestamp old_umask temp_file receipt_temp
    local prepared expected_digest removed_digest settings_changed
    local receipt_prepared receipt_expected_digest receipt_post_digest receipt_changed receipt_prior_source
    local settings_committed=false receipt_committed=false failed=false

    settings="$agent_dir/settings.json"
    receipt="$(_mainframe_pi_receipt_path "$agent_dir")"
    timestamp="$(_mainframe_pi_fixed_date -u '+%Y%m%dT%H%M%SZ')" || {
        _mainframe_pi_error 'could not create a UTC backup timestamp'
        return 1
    }
    [[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
        _mainframe_pi_error 'the backup timestamp was invalid'
        return 1
    }

    old_umask="$(umask)"
    umask 077
    _MAINFRAME_PI_BACKUP_DIR="$(_mainframe_pi_fixed_mktemp -d \
        "$agent_dir/.mainframe-pi-backup-$timestamp.XXXXXX")" || {
        umask "$old_umask"
        _mainframe_pi_error 'could not create the private Pi removal backup'
        return 1
    }
    temp_file="$(_mainframe_pi_fixed_mktemp \
        "$agent_dir/.settings.mainframe.XXXXXX")" || {
        umask "$old_umask"
        _mainframe_pi_error "could not prepare settings removal; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        return 1
    }
    receipt_temp="$(_mainframe_pi_fixed_mktemp \
        "$agent_dir/.mainframe-pi-receipt.XXXXXX")" || {
        umask "$old_umask"
        /bin/rm -f -- "$temp_file"
        _mainframe_pi_error "could not prepare manager receipt removal; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        return 1
    }
    umask "$old_umask"
    /bin/chmod 700 "$_MAINFRAME_PI_BACKUP_DIR" || failed=true
    /bin/chmod 600 "$temp_file" "$receipt_temp" || failed=true

    if [[ "$failed" == false ]]; then
        prepared="$(_mainframe_pi_prepare_settings \
            "$settings" "$temp_file" "$_MAINFRAME_PI_BACKUP_DIR" "$agent_dir" \
            remove "$previous_receipt_source")" || failed=true
    fi
    if [[ "$failed" == false ]]; then
        expected_digest="${prepared%%$'\n'*}"
        prepared="${prepared#*$'\n'}"
        removed_digest="${prepared%%$'\n'*}"
        settings_changed="${prepared##*$'\n'}"
        [[ "$expected_digest" == ABSENT || "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$removed_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$settings_changed" == true || "$settings_changed" == false ]] || failed=true
    fi
    if [[ "$failed" == false ]]; then
        receipt_prepared="$(_mainframe_pi_prepare_receipt \
            "$receipt" "$receipt_temp" "$_MAINFRAME_PI_BACKUP_DIR" remove)" || failed=true
    fi
    if [[ "$failed" == false ]]; then
        receipt_expected_digest="${receipt_prepared%%$'\n'*}"
        receipt_prepared="${receipt_prepared#*$'\n'}"
        receipt_post_digest="${receipt_prepared%%$'\n'*}"
        receipt_prepared="${receipt_prepared#*$'\n'}"
        receipt_changed="${receipt_prepared%%$'\n'*}"
        receipt_prior_source="${receipt_prepared##*$'\n'}"
        [[ "$receipt_expected_digest" == ABSENT || "$receipt_expected_digest" =~ ^[0-9a-f]{64}$ ]] || failed=true
        [[ "$receipt_post_digest" == ABSENT ]] || failed=true
        [[ "$receipt_changed" == true || "$receipt_changed" == false ]] || failed=true
        [[ "$receipt_prior_source" == "$previous_receipt_source" ]] || failed=true
    fi

    if [[ "$failed" == false && "$settings_changed" == true ]]; then
        _mainframe_pi_commit_settings "$settings" "$temp_file" "$expected_digest" || failed=true
        [[ "$failed" == true ]] || settings_committed=true
    fi
    if [[ "$failed" == false && "$receipt_changed" == true ]]; then
        _mainframe_pi_commit_receipt "$receipt" "$receipt_temp" \
            "$receipt_expected_digest" remove || failed=true
        [[ "$failed" == true ]] || receipt_committed=true
    fi
    if [[ "$failed" == false ]]; then
        _mainframe_pi_verify_removed_state "$agent_dir" || failed=true
    fi

    [[ ! -e "$temp_file" && ! -L "$temp_file" ]] || /bin/rm -f -- "$temp_file"
    [[ ! -e "$receipt_temp" && ! -L "$receipt_temp" ]] || /bin/rm -f -- "$receipt_temp"

    if [[ "$failed" == true ]]; then
        if _mainframe_pi_rollback "$agent_dir" "$settings" "$settings_committed" \
            "${removed_digest:-}" false false "$receipt" "$receipt_committed" \
            "${receipt_post_digest:-}"; then
            _mainframe_pi_error "remove failed; rollback=complete; backup_dir=$_MAINFRAME_PI_BACKUP_DIR"
        else
            _mainframe_pi_error "remove failed; rollback=incomplete; recovery_backup=$_MAINFRAME_PI_BACKUP_DIR"
        fi
        return 1
    fi

    printf '%s\n' \
        'action=remove' \
        'dry_run=false' \
        'changed=true' \
        "agent_dir=$agent_dir" \
        "mainframe_root=$_MAINFRAME_PI_ROOT" \
        "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
        "backup_dir=$_MAINFRAME_PI_BACKUP_DIR" \
        "settings_updated=$settings_changed" \
        "receipt_removed=$receipt_changed" \
        'backups_preserved=true' \
        'restart_needed=true' \
        'reload_hint=Use /reload in Pi, or restart Pi.'
}

# Opinionated, exact-version/platform Pi diagnosis. This path reads Pi's
# package manifest and MAINFRAME's evidence policy but deliberately never
# starts Pi. Consequently it never claims that a live process is ready.
mainframe_pi_doctor() {
    local output_format=human json_seen=false agent_dir status_json='{}'
    local status_available=false cli_text='' cli_path=none resolved_cli=none
    local identity_text='' package_name=unknown package_version=unknown
    local pi_package_root=unknown identity_consistent=false platform
    local -a cli_fields=() identity_fields=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                [[ "$json_seen" == false ]] || {
                    _mainframe_pi_error 'duplicate --json'
                    return 64
                }
                json_seen=true
                output_format=json
                ;;
            -h|--help) _mainframe_pi_usage_doctor; return 0 ;;
            *) _mainframe_pi_error "unknown doctor option: $1"; _mainframe_pi_usage_doctor >&2; return 64 ;;
        esac
        shift
    done

    agent_dir="$(_mainframe_pi_agent_dir)" || {
        _mainframe_pi_error 'Pi agent directory must be an absolute path without dot segments or control characters'
        return 64
    }
    _mainframe_pi_package_preflight || return 1
    if [[ -e "$agent_dir" || -L "$agent_dir" ]]; then
        _mainframe_pi_validate_agent_dir "$agent_dir" || return 1
        _mainframe_pi_validate_mutation_targets "$agent_dir" || return 1
        status_json="$(_mainframe_pi_collect_status "$agent_dir" json)" || return 1
        status_available=true
    fi

    if cli_text="$(_mainframe_pi_find_cli 2>/dev/null)"; then
        mapfile -t cli_fields <<< "$cli_text"
        if [[ ${#cli_fields[@]} -eq 2 ]]; then
            cli_path="${cli_fields[0]}"
            resolved_cli="${cli_fields[1]}"
            if identity_text="$(_mainframe_pi_read_cli_identity "$resolved_cli" 2>/dev/null)"; then
                mapfile -t identity_fields <<< "$identity_text"
                if [[ ${#identity_fields[@]} -eq 3 ]]; then
                    package_name="${identity_fields[0]}"
                    package_version="${identity_fields[1]}"
                    pi_package_root="${identity_fields[2]}"
                    identity_consistent=true
                fi
            fi
        fi
    fi
    platform="$(_mainframe_pi_platform_tuple)" || {
        _mainframe_pi_error 'operating-system compatibility tuple could not be determined'
        return 1
    }

    _mainframe_pi_render_doctor \
        "$status_json" "$status_available" "$agent_dir" \
        "$cli_path" "$resolved_cli" "$package_name" "$package_version" \
        "$pi_package_root" "$identity_consistent" "$platform" "$output_format"
}

# Read-only inspection of the first-party Pi package and legacy integration.
# Returns zero for a valid inspected configuration, including not-installed or
# migration-needed states. Unsafe paths, permissions, or invalid JSON fail.
mainframe_pi_status() {
    local output_format=kv agent_dir

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) output_format=json ;;
            -h|--help) _mainframe_pi_usage_status; return 0 ;;
            *) _mainframe_pi_error "unknown status option: $1"; _mainframe_pi_usage_status >&2; return 64 ;;
        esac
        shift
    done

    agent_dir="$(_mainframe_pi_agent_dir)" || {
        _mainframe_pi_error 'Pi agent directory must be an absolute path without dot segments or control characters'
        return 64
    }
    _mainframe_pi_preflight "$agent_dir" || return 1
    _mainframe_pi_collect_status "$agent_dir" "$output_format"
}

# Transactionally migrate legacy Pi resources and activate this Mainframe root
# as an absolute local Pi package source. Real mutation requires same-command
# --yes; environment variables never authorize it.
mainframe_pi_install() {
    local dry_run=false approved=false agent_dir status_text lock_dir='' changed=false
    local project_blocked=false next_apply_command=none
    local next_reload_instruction=none next_verify_command=none arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                [[ "$dry_run" == false ]] || { _mainframe_pi_error 'duplicate --dry-run'; return 64; }
                dry_run=true
                ;;
            --yes)
                [[ "$approved" == false ]] || { _mainframe_pi_error 'duplicate --yes'; return 64; }
                approved=true
                ;;
            -h|--help) _mainframe_pi_usage_install; return 0 ;;
            *) _mainframe_pi_error "unknown install option: $arg"; _mainframe_pi_usage_install >&2; return 64 ;;
        esac
        shift
    done
    if [[ "$dry_run" == false ]] &&
       [[ -n "${MAINFRAME_PI_YES+x}" || -n "${MAINFRAME_YES+x}" ]]; then
        _mainframe_pi_error 'inherited authorization is not accepted; unset it and pass --yes on this command'
        return 77
    fi
    if [[ "$dry_run" == false && "$approved" == false ]]; then
        _mainframe_pi_error 'install requires explicit same-command confirmation: --yes'
        return 77
    fi

    agent_dir="$(_mainframe_pi_agent_dir)" || {
        _mainframe_pi_error 'Pi agent directory must be an absolute path without dot segments or control characters'
        return 64
    }
    _mainframe_pi_preflight "$agent_dir" || return 1
    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    if _mainframe_pi_would_change "$status_text"; then
        changed=true
    fi
    if _mainframe_pi_project_blocked "$status_text"; then
        project_blocked=true
    fi
    if [[ "$changed" == true && "$project_blocked" == false ]]; then
        next_apply_command='mainframe pi install --yes'
        next_reload_instruction='Use /reload in Pi, or restart Pi.'
        next_verify_command='/mainframe doctor'
    fi

    if [[ "$dry_run" == true ]]; then
        printf '%s\n' \
            'action=install' \
            'dry_run=true' \
            "would_change=$changed" \
            "would_quarantine_extension=$(_mainframe_pi_status_value "$status_text" legacy_extension_present)" \
            "would_quarantine_skill=$(_mainframe_pi_status_value "$status_text" legacy_skill_present)" \
            "would_remove_legacy_extension_settings_entries=$(_mainframe_pi_status_value "$status_text" legacy_extension_settings_entries)" \
            "would_set_package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
            "would_leave_project_extension=$(_mainframe_pi_status_value "$status_text" project_extension_present)" \
            "would_leave_project_skill=$(_mainframe_pi_status_value "$status_text" project_skill_present)" \
            "would_leave_project_package_entries=$(_mainframe_pi_status_value "$status_text" project_package_entries)" \
            "would_leave_project_package_delta_entries=$(_mainframe_pi_status_value "$status_text" project_package_delta_entries)" \
            "blocked_by_project_legacy=$project_blocked" \
            "restart_needed=$(_mainframe_pi_status_value "$status_text" restart_needed)" \
            "restart_needed_after_install=$changed" \
            "next_apply_command=$next_apply_command" \
            "next_reload_instruction=$next_reload_instruction" \
            "next_verify_command=$next_verify_command"
        return 0
    fi

    if _mainframe_pi_project_blocked "$status_text"; then
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings require separate project authorization; no project or user files were changed'
        return 77
    fi

    if [[ "$changed" == false ]]; then
        printf '%s\n' \
            'action=install' \
            'dry_run=false' \
            'changed=false' \
            "agent_dir=$agent_dir" \
            "mainframe_root=$_MAINFRAME_PI_ROOT" \
            "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
            'backup_dir=none' \
            'quarantined_extension=none' \
            'quarantined_skill=none' \
            'settings_updated=false' \
            'restart_needed=false'
        return 0
    fi

    lock_dir="$agent_dir/.mainframe-pi-install.lock"
    if [[ -e "$lock_dir" || -L "$lock_dir" ]] || ! /bin/mkdir -m 700 "$lock_dir" 2>/dev/null; then
        _mainframe_pi_error "another Pi integration install is active or left a lock: $lock_dir"
        return 75
    fi

    # Revalidate after taking the lock so a preflight-to-commit change fails
    # closed. The lock is private to Mainframe; the digest check at commit also
    # detects concurrent writes by Pi or another settings editor.
    if ! _mainframe_pi_package_preflight ||
       ! _mainframe_pi_validate_mutation_targets "$agent_dir" ||
       ! status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        return 1
    fi
    if _mainframe_pi_project_blocked "$status_text"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings appeared during install; no project or user files were changed'
        return 77
    fi
    if ! _mainframe_pi_would_change "$status_text"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        printf '%s\n' \
            'action=install' 'dry_run=false' 'changed=false' \
            "agent_dir=$agent_dir" "mainframe_root=$_MAINFRAME_PI_ROOT" \
            "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
            'backup_dir=none' 'quarantined_extension=none' \
            'quarantined_skill=none' 'settings_updated=false' \
            'restart_needed=false'
        return 0
    fi

    _MAINFRAME_PI_BACKUP_DIR=''
    _MAINFRAME_PI_QUARANTINED_EXTENSION='none'
    _MAINFRAME_PI_QUARANTINED_SKILL='none'
    _MAINFRAME_PI_SETTINGS_UPDATED='false'
    if _mainframe_pi_install_transaction "$agent_dir" \
        "$(_mainframe_pi_status_value "$status_text" manager_receipt_source)"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || {
            _mainframe_pi_error "install succeeded but the private lock could not be removed: $lock_dir"
            return 0
        }
        return 0
    fi
    /bin/rmdir -- "$lock_dir" 2>/dev/null || true
    return 1
}

# Transactionally detach only the exact current/receipted Mainframe package
# sources.  Historical migration backups, legacy resources, and unrelated Pi
# settings are deliberately left untouched.
mainframe_pi_remove() {
    local dry_run=false approved=false agent_dir status_text lock_dir='' changed=false
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                [[ "$dry_run" == false ]] || { _mainframe_pi_error 'duplicate --dry-run'; return 64; }
                dry_run=true
                ;;
            --yes)
                [[ "$approved" == false ]] || { _mainframe_pi_error 'duplicate --yes'; return 64; }
                approved=true
                ;;
            -h|--help) _mainframe_pi_usage_remove; return 0 ;;
            *) _mainframe_pi_error "unknown remove option: $arg"; _mainframe_pi_usage_remove >&2; return 64 ;;
        esac
        shift
    done
    if [[ "$dry_run" == false ]] &&
       [[ -n "${MAINFRAME_PI_YES+x}" || -n "${MAINFRAME_YES+x}" ]]; then
        _mainframe_pi_error 'inherited authorization is not accepted; unset it and pass --yes on this command'
        return 77
    fi
    if [[ "$dry_run" == false && "$approved" == false ]]; then
        _mainframe_pi_error 'remove requires explicit same-command confirmation: --yes'
        return 77
    fi

    agent_dir="$(_mainframe_pi_agent_dir)" || {
        _mainframe_pi_error 'Pi agent directory must be an absolute path without dot segments or control characters'
        return 64
    }
    _mainframe_pi_preflight "$agent_dir" || return 1
    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    if _mainframe_pi_would_remove "$status_text"; then
        changed=true
    fi

    if [[ "$dry_run" == true ]]; then
        printf '%s\n' \
            'action=remove' \
            'dry_run=true' \
            "would_change=$changed" \
            "would_remove_managed_package_entries=$(_mainframe_pi_status_value "$status_text" managed_package_entries)" \
            "would_remove_manager_receipt=$(_mainframe_pi_status_value "$status_text" manager_receipt_present)" \
            "would_leave_project_extension=$(_mainframe_pi_status_value "$status_text" project_extension_present)" \
            "would_leave_project_skill=$(_mainframe_pi_status_value "$status_text" project_skill_present)" \
            "would_leave_project_package_entries=$(_mainframe_pi_status_value "$status_text" project_package_entries)" \
            "blocked_by_project_override=$(
                if _mainframe_pi_project_blocked "$status_text"; then printf 'true'; else printf 'false'; fi
            )" \
            'would_preserve_backups=true' \
            "restart_needed_after_remove=$changed"
        return 0
    fi

    if _mainframe_pi_project_blocked "$status_text"; then
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings require separate project authorization; no project or user files were changed'
        return 77
    fi
    if [[ "$changed" == false ]]; then
        printf '%s\n' \
            'action=remove' 'dry_run=false' 'changed=false' \
            "agent_dir=$agent_dir" "mainframe_root=$_MAINFRAME_PI_ROOT" \
            "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
            'backup_dir=none' 'settings_updated=false' \
            'receipt_removed=false' 'backups_preserved=true' \
            'restart_needed=false'
        return 0
    fi

    lock_dir="$agent_dir/.mainframe-pi-install.lock"
    if [[ -e "$lock_dir" || -L "$lock_dir" ]] || ! /bin/mkdir -m 700 "$lock_dir" 2>/dev/null; then
        _mainframe_pi_error "another Pi integration lifecycle operation is active or left a lock: $lock_dir"
        return 75
    fi

    if ! _mainframe_pi_package_preflight ||
       ! _mainframe_pi_validate_mutation_targets "$agent_dir" ||
       ! status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        return 1
    fi
    if _mainframe_pi_project_blocked "$status_text"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings appeared during removal; no project or user files were changed'
        return 77
    fi
    if ! _mainframe_pi_would_remove "$status_text"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        printf '%s\n' \
            'action=remove' 'dry_run=false' 'changed=false' \
            "agent_dir=$agent_dir" "mainframe_root=$_MAINFRAME_PI_ROOT" \
            "package_source=$_MAINFRAME_PI_PACKAGE_SOURCE" \
            'backup_dir=none' 'settings_updated=false' \
            'receipt_removed=false' 'backups_preserved=true' \
            'restart_needed=false'
        return 0
    fi

    _MAINFRAME_PI_BACKUP_DIR=''
    if _mainframe_pi_remove_transaction "$agent_dir" \
        "$(_mainframe_pi_status_value "$status_text" manager_receipt_source)"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || {
            _mainframe_pi_error "remove succeeded but the private lock could not be removed: $lock_dir"
            return 0
        }
        return 0
    fi
    /bin/rmdir -- "$lock_dir" 2>/dev/null || true
    return 1
}

# Exact recovery for a completed legacy-to-package migration whose subsequent
# live Pi verification failed. The implementation is loaded only on demand so
# ordinary status, doctor, install, and remove paths stay small.
mainframe_pi_restore() {
    # shellcheck source=lib/pi_restore.sh
    source "$_MAINFRAME_PI_ROOT/lib/pi_restore.sh"
    _mainframe_pi_restore_command "$@"
}

# Read-only uninstall interlock.  A package source that points at the current
# root (or the exact previous root in Mainframe's private receipt) would become
# a dangling, startup-breaking Pi setting after Mainframe is removed.
_mainframe_pi_uninstall_guard() {
    local agent_dir status_text attached project_attached

    agent_dir="$(_mainframe_pi_agent_dir 2>/dev/null)" || return 1
    [[ -d "$agent_dir" ]] || return 0
    _mainframe_pi_preflight "$agent_dir" || return 1
    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    attached="$(_mainframe_pi_status_value "$status_text" managed_package_entries)" || return 1
    project_attached="$(_mainframe_pi_status_value "$status_text" project_package_entries)" || return 1
    if [[ "$attached" != 0 || "$project_attached" != 0 ]]; then
        _mainframe_pi_error 'refusing to uninstall while the Mainframe Pi package is attached'
        _mainframe_pi_error 'preview and detach it first from a human terminal:'
        _mainframe_pi_error '  mainframe pi remove --dry-run'
        _mainframe_pi_error '  mainframe pi remove --yes'
        if [[ "${MAINFRAME_INSTALL_METHOD:-}" == homebrew ]]; then
            _mainframe_pi_error 'then run: brew uninstall gtwatts/mainframe/mainframe'
        fi
        return 77
    fi
    return 0
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/shell.sh - Bash/zsh integration identity and repair lifecycle
# =============================================================================
# Shell profiles are an execution surface: completions and directly sourced
# libraries use MAINFRAME_ROOT before the CLI can normalize it.  This module
# keeps those managed blocks aligned with the exact CLI selected by PATH.
# =============================================================================

[[ -n "${_MAINFRAME_SHELL_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_SHELL_LOADED=1

readonly _MAINFRAME_SHELL_BEGIN='# >>> MAINFRAME >>>'
readonly _MAINFRAME_SHELL_END='# <<< MAINFRAME <<<'
readonly _MAINFRAME_SHELL_LOGIN_BEGIN='# >>> MAINFRAME BASH LOGIN >>>'
readonly _MAINFRAME_SHELL_LOGIN_END='# <<< MAINFRAME BASH LOGIN <<<'

_mainframe_shell_usage() {
    cat <<'EOF'
Usage: mainframe shell <status|repair> [options]

Commands:
  status                 Compare the selected CLI, inherited root, and profiles
  repair                 Rewrite only MAINFRAME-managed profile blocks

Options:
  --shell bash|zsh|all   Shells to inspect or repair (default: all)
  --zdotdir DIR          Explicit zsh startup directory when not exported
  --json                 Closed JSON output for status
  --dry-run              Preview repair without changing profiles
  --yes                  Apply the reviewed repair
  -h, --help             Show this help

Repair rejects symbolic links, non-regular files, malformed/overlapping marker
blocks, files not owned by the current user, externally writable paths, and
multiply linked profiles. It prepares every target before replacing any file
and preserves unrelated text.
EOF
}

_mainframe_shell_stat_value() {
    local format_bsd="$1" format_gnu="$2" path="$3" value platform
    platform="$(/usr/bin/uname -s 2>/dev/null || true)"
    case "$platform" in
        Darwin)
            value="$(/usr/bin/stat -f "$format_bsd" "$path" 2>/dev/null || true)"
            ;;
        Linux)
            value="$(/usr/bin/stat -c "$format_gnu" "$path" 2>/dev/null || true)"
            ;;
        *) return 1 ;;
    esac
    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

_mainframe_shell_sha256() {
    local path="$1"
    if [[ -x /usr/bin/shasum ]]; then
        /usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}'
    elif [[ -x /usr/bin/sha256sum ]]; then
        /usr/bin/sha256sum "$path" | /usr/bin/awk '{print $1}'
    elif [[ -x /bin/sha256sum ]]; then
        /bin/sha256sum "$path" | /usr/bin/awk '{print $1}'
    elif [[ -x /usr/bin/openssl ]]; then
        /usr/bin/openssl dgst -sha256 "$path" | /usr/bin/awk '{print $NF}'
    else
        return 1
    fi
}

_mainframe_shell_file_identity() {
    _mainframe_shell_stat_value '%d:%i' '%d:%i' "$1"
}

_mainframe_shell_file_inode() {
    _mainframe_shell_stat_value '%i' '%i' "$1"
}

_mainframe_shell_descriptor_identity() {
    local path="$1" platform
    platform="$(/usr/bin/uname -s 2>/dev/null || true)"
    case "$platform" in
        # macOS fdesc exposes a synthetic device number for /dev/fd/N even
        # when it names the same open inode as the filesystem path.
        Darwin) /usr/bin/stat -f '%i' "$path" 2>/dev/null ;;
        # GNU stat otherwise reports the procfs /dev/fd symlink itself.
        Linux) /usr/bin/stat -L -c '%d:%i' "$path" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

_mainframe_shell_path_identity_for_descriptor() {
    local path="$1" platform
    platform="$(/usr/bin/uname -s 2>/dev/null || true)"
    case "$platform" in
        Darwin) _mainframe_shell_file_inode "$path" ;;
        Linux) _mainframe_shell_file_identity "$path" ;;
        *) return 1 ;;
    esac
}

_mainframe_shell_validate_created_file() {
    local path="$1" expected_identity="$2" expected_mode="${3:-}" expected_digest="${4:-}"
    local identity mode links digest final_identity
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
    links="$(_mainframe_shell_stat_value '%l' '%h' "$path")" || return 1
    [[ "$links" == 1 ]] || return 1
    identity="$(_mainframe_shell_file_identity "$path")" || return 1
    [[ "$identity" == "$expected_identity" ]] || return 1
    if [[ -n "$expected_mode" ]]; then
        mode="$(_mainframe_shell_stat_value '%Lp' '%a' "$path")" || return 1
        [[ "$mode" == "$expected_mode" ]] || return 1
    fi
    _mainframe_shell_path_has_no_write_acl "$path" || return 1
    if [[ -n "$expected_digest" ]]; then
        digest="$(_mainframe_shell_sha256 "$path")" || return 1
        [[ "$digest" == "$expected_digest" ]] || return 1
    fi
    final_identity="$(_mainframe_shell_file_identity "$path")" || return 1
    [[ "$final_identity" == "$expected_identity" ]] || return 1
    return 0
}

_mainframe_shell_digest_created_file() {
    local path="$1" identity="$2" mode="$3" digest
    _mainframe_shell_validate_created_file "$path" "$identity" "$mode" || return 1
    digest="$(_mainframe_shell_sha256 "$path")" || return 1
    _mainframe_shell_validate_created_file "$path" "$identity" "$mode" "$digest" || return 1
    printf '%s\n' "$digest"
}

_mainframe_shell_safe_remove_created() {
    local path="$1" identity="$2"
    [[ -n "$path" && -n "$identity" ]] || return 1
    _mainframe_shell_validate_created_file "$path" "$identity" || return 1
    rm -f -- "$path"
}

_mainframe_shell_open_exclusive_file() {
    local directory="$1" stem="$2" path_variable="$3" fd_variable="$4" identity_variable="$5"
    local _mf_candidate _mf_fd _mf_identity _mf_fd_identity _mf_path_identity _mf_attempt
    local _mf_prior_umask _mf_noclobber_was_set=false
    [[ -d "$directory" && ! -L "$directory" ]] || return 77
    _mf_prior_umask="$(umask)"
    [[ -o noclobber ]] && _mf_noclobber_was_set=true
    umask 077
    set -o noclobber
    for ((_mf_attempt = 0; _mf_attempt < 128; _mf_attempt++)); do
        _mf_candidate="$directory/.${stem}.$$.$RANDOM$RANDOM.$_mf_attempt"
        # Bash noclobber is specified for regular files; explicitly skip every
        # already-named object so a seeded symlink to a device or FIFO is never
        # opened through the normal collision path.
        if [[ -e "$_mf_candidate" || -L "$_mf_candidate" ]]; then
            continue
        fi
        if { exec {_mf_fd}> "$_mf_candidate"; } 2>/dev/null; then
            umask "$_mf_prior_umask"
            [[ "$_mf_noclobber_was_set" == true ]] || set +o noclobber
            _mf_identity="$(_mainframe_shell_file_identity "$_mf_candidate" 2>/dev/null || true)"
            _mf_fd_identity="$(_mainframe_shell_descriptor_identity \
                "/dev/fd/$_mf_fd" 2>/dev/null || true)"
            _mf_path_identity="$(_mainframe_shell_path_identity_for_descriptor \
                "$_mf_candidate" 2>/dev/null || true)"
            if [[ -z "$_mf_identity" || -z "$_mf_fd_identity" || \
                  "$_mf_path_identity" != "$_mf_fd_identity" ]]; then
                exec {_mf_fd}>&-
                _mainframe_shell_safe_remove_created \
                    "$_mf_candidate" "$_mf_identity" 2>/dev/null || true
                return 74
            fi
            printf -v "$path_variable" '%s' "$_mf_candidate"
            printf -v "$fd_variable" '%s' "$_mf_fd"
            printf -v "$identity_variable" '%s' "$_mf_identity"
            return 0
        fi
    done
    umask "$_mf_prior_umask"
    [[ "$_mf_noclobber_was_set" == true ]] || set +o noclobber
    return 73
}

_mainframe_shell_finalize_open_file() {
    local path="$1" fd="$2" identity="$3" mode="$4" digest="$5" fd_path
    fd_path="/dev/fd/$fd"
    if ! chmod "$mode" "$fd_path"; then
        exec {fd}>&-
        return 74
    fi
    exec {fd}>&-
    _mainframe_shell_validate_created_file "$path" "$identity" "$mode" "$digest"
}

_mainframe_shell_replace_path() {
    local source="$1" destination="$2" platform
    # BSD mv otherwise follows a destination symlink to a directory; GNU mv
    # does the same unless --no-target-directory is used. A real destination
    # directory is never a valid shell profile either.
    [[ ! -d "$destination" || -L "$destination" ]] || return 1
    platform="$(/usr/bin/uname -s 2>/dev/null || true)"
    case "$platform" in
        Darwin) /bin/mv -fh -- "$source" "$destination" ;;
        Linux) /bin/mv -fT -- "$source" "$destination" ;;
        *) return 1 ;;
    esac
}

_mainframe_shell_mode_has_external_write() {
    local mode="${1:-}" group_digit other_digit
    mode="${mode: -3}"
    [[ "$mode" =~ ^[0-7]{3}$ ]] || return 0
    group_digit="${mode:1:1}"
    other_digit="${mode:2:1}"
    case "$group_digit$other_digit" in
        *[2367]*) return 0 ;;
        *) return 1 ;;
    esac
}

_mainframe_shell_path_has_no_write_acl() {
    local path="$1" platform line listing permissions
    platform="$(/usr/bin/uname -s 2>/dev/null || true)"
    [[ "$platform" == Darwin ]] || return 0
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

_mainframe_shell_owned_write_directory() {
    local directory="$1" label="$2" mode
    [[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || {
        printf 'MAINFRAME shell lifecycle refuses an unsafe %s: %s\n' \
            "$label" "$directory" >&2
        return 77
    }
    mode="$(_mainframe_shell_stat_value '%Lp' '%a' "$directory")" || return 77
    if _mainframe_shell_mode_has_external_write "$mode"; then
        printf 'MAINFRAME shell lifecycle refuses a group/world-writable %s: %s\n' \
            "$label" "$directory" >&2
        return 77
    fi
    _mainframe_shell_path_has_no_write_acl "$directory" || {
        printf 'MAINFRAME shell lifecycle refuses a write ACL on %s: %s\n' \
            "$label" "$directory" >&2
        return 77
    }
}

_mainframe_shell_trusted_ancestry() {
    local directory="$1" current owner mode numeric parent
    current="$(_mainframe_shell_canonical_dir "$directory")" || return 77
    while :; do
        [[ -d "$current" && ! -L "$current" ]] || return 77
        owner="$(_mainframe_shell_stat_value '%u' '%u' "$current")" || return 77
        mode="$(_mainframe_shell_stat_value '%Mp%Lp' '%a' "$current")" || return 77
        [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] || return 77
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 77
        numeric=$((8#$mode))
        if (( (numeric & 0022) != 0 )); then
            case "$current" in
                /tmp|/private/tmp|/var/tmp|/private/var/tmp)
                    (( owner == 0 && (numeric & 01000) != 0 )) || return 77
                    ;;
                *) return 77 ;;
            esac
        fi
        _mainframe_shell_path_has_no_write_acl "$current" || return 77
        [[ "$current" == / ]] && break
        parent="${current%/*}"
        [[ -n "$parent" ]] || parent=/
        current="$parent"
    done
    return 0
}

_mainframe_shell_canonical_dir() {
    local path="$1"
    [[ "$path" == /* && -d "$path" ]] || return 1
    (cd -- "$path" 2>/dev/null && pwd -P)
}

_mainframe_shell_path_is_text_safe() {
    case "${1:-}" in
        *$'\n'*|*$'\r'*|*$'\t'*|*:* ) return 1 ;;
        *) return 0 ;;
    esac
}

_mainframe_shell_zshenv_mentions_zdotdir() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    /usr/bin/awk '
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^#/) next
            if (line ~ /(^|[;[:space:]])(export[[:space:]]+|typeset[^;]*[[:space:]]+)?ZDOTDIR[[:space:]]*=/) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

_mainframe_shell_resolve_file() {
    local source="$1" directory target links=0
    [[ "$source" == /* ]] || return 1
    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        directory="${source%/*}"
        [[ -n "$directory" ]] || directory=/
        directory="$(_mainframe_shell_canonical_dir "$directory")" || return 1
        if [[ -x /usr/bin/readlink ]]; then
            target="$(/usr/bin/readlink "$source")" || return 1
        elif [[ -x /bin/readlink ]]; then
            target="$(/bin/readlink "$source")" || return 1
        else
            return 1
        fi
        [[ "$target" == /* ]] && source="$target" || source="$directory/$target"
    done
    directory="${source%/*}"
    [[ -n "$directory" ]] || directory=/
    directory="$(_mainframe_shell_canonical_dir "$directory")" || return 1
    source="$directory/${source##*/}"
    [[ -f "$source" && -x "$source" ]] || return 1
    printf '%s\n' "$source"
}

_mainframe_shell_selected_cli() {
    local search_path="${_MAINFRAME_CLI_CALLER_PATH:-}" entry candidate resolved raw_entry
    local expected="$MAINFRAME_ROOT/bin/mainframe"

    _MAINFRAME_SHELL_SELECTED=false
    _MAINFRAME_SHELL_SELECTION_STATE=missing
    _MAINFRAME_SHELL_SELECTED_CLI='none'
    _MAINFRAME_SHELL_SELECTED_BIN='none'
    _MAINFRAME_SHELL_SELECTED_RESOLVED='none'
    expected="$(_mainframe_shell_resolve_file "$expected" 2>/dev/null || true)"
    [[ -n "$expected" ]] || return 1

    while IFS= read -r raw_entry; do
        entry="$raw_entry"
        if [[ -z "$entry" ]]; then
            candidate="${PWD:-.}/mainframe"
        else
            candidate="$entry/mainframe"
        fi
        [[ -x "$candidate" ]] || continue
        _MAINFRAME_SHELL_SELECTED_CLI="$candidate"
        _MAINFRAME_SHELL_SELECTION_STATE=unsafe

        # Shell command lookup stops at the first executable name. Never skip
        # an unsafe or ambiguous first hit and bless a later MAINFRAME binary.
        [[ "$entry" == /* && -d "$entry" && ! -L "$entry" ]] || return 0
        entry="$(_mainframe_shell_canonical_dir "$entry" 2>/dev/null || true)"
        [[ -n "$entry" ]] || return 0
        _mainframe_shell_path_is_text_safe "$entry" || return 0
        _mainframe_shell_owned_write_directory "$entry" 'selected CLI bin directory' \
            >/dev/null 2>&1 || return 0
        _mainframe_shell_trusted_ancestry "$entry" >/dev/null 2>&1 || return 0
        candidate="$entry/mainframe"
        resolved="$(_mainframe_shell_resolve_file "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || return 0
        _MAINFRAME_SHELL_SELECTED_CLI="$candidate"
        _MAINFRAME_SHELL_SELECTED_BIN="$entry"
        _MAINFRAME_SHELL_SELECTED_RESOLVED="$resolved"
        if [[ "$resolved" == "$expected" ]]; then
            _MAINFRAME_SHELL_SELECTED=true
            _MAINFRAME_SHELL_SELECTION_STATE=ready
        else
            _MAINFRAME_SHELL_SELECTION_STATE=mismatch
        fi
        return 0
    done < <(/usr/bin/printf '%s\n' "$search_path" | /usr/bin/tr ':' '\n')
    return 1
}

_mainframe_shell_profile_layout() {
    local file="$1" links mode
    if [[ ! -e "$file" && ! -L "$file" ]]; then
        printf 'absent\n'
        return 0
    fi
    if [[ -L "$file" || ! -f "$file" || ! -O "$file" ]]; then
        printf 'unsafe\n'
        return 0
    fi
    links="$(_mainframe_shell_stat_value '%l' '%h' "$file" 2>/dev/null || true)"
    if [[ "$links" != 1 ]]; then
        printf 'unsafe\n'
        return 0
    fi
    mode="$(_mainframe_shell_stat_value '%Lp' '%a' "$file" 2>/dev/null || true)"
    if [[ -z "$mode" ]] || _mainframe_shell_mode_has_external_write "$mode"; then
        printf 'unsafe\n'
        return 0
    fi
    if ! _mainframe_shell_path_has_no_write_acl "$file"; then
        printf 'unsafe\n'
        return 0
    fi
    /usr/bin/awk \
        -v runtime_begin="$_MAINFRAME_SHELL_BEGIN" \
        -v runtime_end="$_MAINFRAME_SHELL_END" \
        -v login_begin="$_MAINFRAME_SHELL_LOGIN_BEGIN" \
        -v login_end="$_MAINFRAME_SHELL_LOGIN_END" '
        BEGIN { inside = ""; runtime = 0; login = 0; invalid = 0 }
        $0 == runtime_begin {
            runtime++
            if (inside != "" || runtime > 1) invalid = 1
            inside = "runtime"
            next
        }
        $0 == login_begin {
            login++
            if (inside != "" || login > 1) invalid = 1
            inside = "login"
            next
        }
        $0 == runtime_end {
            if (inside != "runtime") invalid = 1
            inside = ""
            next
        }
        $0 == login_end {
            if (inside != "login") invalid = 1
            inside = ""
            next
        }
        END {
            if (inside != "" || invalid) print "malformed"
            else print "safe"
        }
    ' "$file"
}

_mainframe_shell_marker_state() {
    local file="$1" begin="$2" end="$3"
    [[ -f "$file" && ! -L "$file" ]] || { printf 'absent\n'; return 0; }
    /usr/bin/awk -v begin="$begin" -v end="$end" '
        BEGIN { inside = 0; begins = 0; ends = 0; invalid = 0 }
        $0 == begin { begins++; if (inside || begins > 1) invalid = 1; inside = 1; next }
        $0 == end { ends++; if (!inside || ends > 1) invalid = 1; inside = 0; next }
        END {
            if (inside || begins != ends || invalid) print "malformed"
            else if (begins == 1) print "valid"
            else print "absent"
        }
    ' "$file"
}

_mainframe_shell_extract_block() {
    local file="$1" begin="$2" end="$3"
    /usr/bin/awk -v begin="$begin" -v end="$end" '
        $0 == begin { inside = 1 }
        inside { print }
        inside && $0 == end { exit }
    ' "$file"
}

_mainframe_shell_write_runtime_block() {
    local shell_name="$1" runtime_bash
    runtime_bash="$(_mainframe_shell_resolve_file "${BASH:-}" 2>/dev/null || true)"
    [[ -n "$runtime_bash" ]] || return 1
    printf '%s\n' "$_MAINFRAME_SHELL_BEGIN"
    printf 'export MAINFRAME_ROOT=%q\n' "$MAINFRAME_ROOT"
    printf 'export MAINFRAME_BASH=%q\n' "$runtime_bash"
    printf 'export MAINFRAME_AI_ENABLED=1\n'
    printf '_MAINFRAME_SHELL_BIN_DIR=%q\n' "$_MAINFRAME_SHELL_SELECTED_BIN"
    printf 'case ":${PATH:-}:" in\n'
    printf '    *":${_MAINFRAME_SHELL_BIN_DIR}:"*) ;;\n'
    printf '    *) export PATH="${_MAINFRAME_SHELL_BIN_DIR}${PATH:+:${PATH}}" ;;\n'
    printf 'esac\n'
    printf 'unset _MAINFRAME_SHELL_BIN_DIR\n'
    if [[ "$shell_name" == bash ]]; then
        printf '_MAINFRAME_BASHRC_LOADED=1\n'
    fi
    printf '[[ -f "$MAINFRAME_ROOT/completions/mainframe.%s" ]] && source "$MAINFRAME_ROOT/completions/mainframe.%s"\n' \
        "$shell_name" "$shell_name"
    printf '%s\n' "$_MAINFRAME_SHELL_END"
}

_mainframe_shell_write_login_block() {
    printf '%s\n' "$_MAINFRAME_SHELL_LOGIN_BEGIN"
    printf 'if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && [ "${_MAINFRAME_BASHRC_LOADED:-}" != "1" ]; then\n'
    printf '    . "$HOME/.bashrc"\n'
    printf 'fi\n'
    printf 'unset _MAINFRAME_BASHRC_LOADED\n'
    printf '%s\n' "$_MAINFRAME_SHELL_LOGIN_END"
}

_mainframe_shell_expected_block() {
    local kind="$1"
    case "$kind" in
        bash-runtime) _mainframe_shell_write_runtime_block bash ;;
        zsh-runtime) _mainframe_shell_write_runtime_block zsh ;;
        bash-login) _mainframe_shell_write_login_block ;;
        none) : ;;
        *) return 64 ;;
    esac
}

_mainframe_shell_block_matches() {
    local file="$1" kind="$2" begin end actual expected marker_state
    case "$kind" in
        bash-runtime|zsh-runtime)
            begin="$_MAINFRAME_SHELL_BEGIN"
            end="$_MAINFRAME_SHELL_END"
            ;;
        bash-login)
            begin="$_MAINFRAME_SHELL_LOGIN_BEGIN"
            end="$_MAINFRAME_SHELL_LOGIN_END"
            ;;
        none) return 1 ;;
        *) return 1 ;;
    esac
    marker_state="$(_mainframe_shell_marker_state "$file" "$begin" "$end")"
    [[ "$marker_state" == valid ]] || return 1
    actual="$(_mainframe_shell_extract_block "$file" "$begin" "$end")"
    expected="$(_mainframe_shell_expected_block "$kind")"
    [[ "$actual" == "$expected" ]]
}

_mainframe_shell_profile_matches_kind() {
    local file="$1" kind="$2" runtime_state login_state
    [[ -f "$file" && ! -L "$file" ]] || return 1
    runtime_state="$(_mainframe_shell_marker_state \
        "$file" "$_MAINFRAME_SHELL_BEGIN" "$_MAINFRAME_SHELL_END")"
    login_state="$(_mainframe_shell_marker_state \
        "$file" "$_MAINFRAME_SHELL_LOGIN_BEGIN" "$_MAINFRAME_SHELL_LOGIN_END")"
    case "$kind" in
        bash-runtime|zsh-runtime)
            [[ "$login_state" == absent ]] && \
                _mainframe_shell_block_matches "$file" "$kind"
            ;;
        bash-login)
            [[ "$runtime_state" == absent ]] && \
                _mainframe_shell_block_matches "$file" "$kind"
            ;;
        none)
            [[ "$runtime_state" == absent && "$login_state" == absent ]]
            ;;
        *) return 1 ;;
    esac
}

_mainframe_shell_effective_login() {
    local profile
    for profile in \
        "$_MAINFRAME_SHELL_HOME/.bash_profile" \
        "$_MAINFRAME_SHELL_HOME/.bash_login" \
        "$_MAINFRAME_SHELL_HOME/.profile"; do
        if [[ -e "$profile" || -L "$profile" ]]; then
            printf '%s\n' "$profile"
            return 0
        fi
    done
    printf '%s/.bash_profile\n' "$_MAINFRAME_SHELL_HOME"
}

_mainframe_shell_note_repair() {
    local detail="$1"
    [[ "$_MAINFRAME_SHELL_OVERALL" != ready ]] || _MAINFRAME_SHELL_OVERALL=repair-required
    _MAINFRAME_SHELL_DETAILS+=("$detail")
}

_mainframe_shell_note_blocked() {
    _MAINFRAME_SHELL_OVERALL=blocked
    _MAINFRAME_SHELL_DETAILS+=("$1")
}

_mainframe_shell_scope_result() {
    local start="$1" index detail
    if (( ${#_MAINFRAME_SHELL_DETAILS[@]} == start )); then
        printf 'ready\n'
        return 0
    fi
    for ((index = start; index < ${#_MAINFRAME_SHELL_DETAILS[@]}; index++)); do
        detail="${_MAINFRAME_SHELL_DETAILS[$index]}"
        case "$detail" in
            *:unsafe|*:malformed) printf 'blocked\n'; return 0 ;;
        esac
    done
    printf 'repair-required\n'
}

_mainframe_shell_check_profile_kind() {
    local file="$1" kind="$2" label="$3" layout runtime_state login_state
    layout="$(_mainframe_shell_profile_layout "$file")"
    case "$layout" in
        unsafe|malformed)
            _mainframe_shell_note_blocked "$label:$layout"
            return 0
            ;;
        absent)
            if [[ "$kind" != none ]]; then
                _mainframe_shell_note_repair "$label:missing"
            fi
            return 0
            ;;
    esac

    runtime_state="$(_mainframe_shell_marker_state \
        "$file" "$_MAINFRAME_SHELL_BEGIN" "$_MAINFRAME_SHELL_END")"
    login_state="$(_mainframe_shell_marker_state \
        "$file" "$_MAINFRAME_SHELL_LOGIN_BEGIN" "$_MAINFRAME_SHELL_LOGIN_END")"
    case "$kind" in
        bash-runtime|zsh-runtime)
            if ! _mainframe_shell_block_matches "$file" "$kind"; then
                _mainframe_shell_note_repair "$label:runtime-stale"
            fi
            [[ "$login_state" == absent ]] || \
                _mainframe_shell_note_repair "$label:unexpected-login-block"
            ;;
        bash-login)
            if ! _mainframe_shell_block_matches "$file" "$kind"; then
                _mainframe_shell_note_repair "$label:login-stale"
            fi
            [[ "$runtime_state" == absent ]] || \
                _mainframe_shell_note_repair "$label:unexpected-runtime-block"
            ;;
        none)
            if [[ "$runtime_state" != absent || "$login_state" != absent ]]; then
                _mainframe_shell_note_repair "$label:unexpected-managed-block"
            fi
            ;;
    esac
}

_mainframe_shell_prepare_context() {
    local shell_scope="${1:-all}" zdotdir_candidate='' zdotdir_source=home
    [[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || {
        printf 'MAINFRAME shell lifecycle requires an existing absolute HOME.\n' >&2
        return 78
    }
    _MAINFRAME_SHELL_HOME="$(_mainframe_shell_canonical_dir "$HOME")" || return 78
    _mainframe_shell_path_is_text_safe "$_MAINFRAME_SHELL_HOME" || {
        printf 'MAINFRAME shell lifecycle refuses control characters or colons in HOME.\n' >&2
        return 78
    }
    _mainframe_shell_path_is_text_safe "$MAINFRAME_ROOT" || {
        printf 'MAINFRAME shell lifecycle refuses control characters or colons in MAINFRAME_ROOT.\n' >&2
        return 78
    }
    _mainframe_shell_owned_write_directory "$_MAINFRAME_SHELL_HOME" home || return $?
    _mainframe_shell_trusted_ancestry "$_MAINFRAME_SHELL_HOME" || {
        printf 'MAINFRAME shell lifecycle refuses unsafe home-directory ancestry: %s\n' \
            "$_MAINFRAME_SHELL_HOME" >&2
        return 77
    }
    _MAINFRAME_SHELL_ZSH_DIR="$_MAINFRAME_SHELL_HOME"
    _MAINFRAME_SHELL_ZDOTDIR_SOURCE=home
    if [[ "$shell_scope" == zsh || "$shell_scope" == all ]]; then
        if [[ -n "${_MAINFRAME_SHELL_ZDOTDIR_OVERRIDE:-}" ]]; then
            zdotdir_candidate="$_MAINFRAME_SHELL_ZDOTDIR_OVERRIDE"
            zdotdir_source=override
        elif [[ -n "${ZDOTDIR:-}" ]]; then
            zdotdir_candidate="$ZDOTDIR"
            zdotdir_source=environment
        elif _mainframe_shell_zshenv_mentions_zdotdir "$_MAINFRAME_SHELL_HOME/.zshenv"; then
            printf 'MAINFRAME shell lifecycle found a non-exported or otherwise hidden ZDOTDIR assignment in %s.\n' \
                "$_MAINFRAME_SHELL_HOME/.zshenv" >&2
            printf 'Pass the exact active directory with --zdotdir ABS, or export ZDOTDIR before invoking MAINFRAME.\n' >&2
            return 78
        fi
    fi
    if [[ -n "$zdotdir_candidate" ]]; then
        [[ "$zdotdir_candidate" == /* && -d "$zdotdir_candidate" ]] || {
            printf 'MAINFRAME shell lifecycle requires ZDOTDIR to be an existing absolute directory: %s\n' \
                "$zdotdir_candidate" >&2
            return 78
        }
        _MAINFRAME_SHELL_ZSH_DIR="$(_mainframe_shell_canonical_dir "$zdotdir_candidate")" || return 78
        _mainframe_shell_path_is_text_safe "$_MAINFRAME_SHELL_ZSH_DIR" || {
            printf 'MAINFRAME shell lifecycle refuses control characters or colons in ZDOTDIR.\n' >&2
            return 78
        }
        _mainframe_shell_owned_write_directory "$_MAINFRAME_SHELL_ZSH_DIR" ZDOTDIR || return $?
        _mainframe_shell_trusted_ancestry "$_MAINFRAME_SHELL_ZSH_DIR" || {
            printf 'MAINFRAME shell lifecycle refuses unsafe ZDOTDIR ancestry: %s\n' \
                "$_MAINFRAME_SHELL_ZSH_DIR" >&2
            return 77
        }
        _MAINFRAME_SHELL_ZDOTDIR_SOURCE="$zdotdir_source"
    fi
    _mainframe_shell_selected_cli || true
    _MAINFRAME_SHELL_EFFECTIVE_LOGIN="$(_mainframe_shell_effective_login)"
    return 0
}

_mainframe_shell_collect() {
    local shell_scope="$1" inherited="${_MAINFRAME_CLI_INHERITED_ROOT:-}"
    local inherited_canonical active_canonical profile
    _mainframe_shell_prepare_context "$shell_scope" || return $?
    _MAINFRAME_SHELL_OVERALL=ready
    _MAINFRAME_SHELL_BASH_STATE=not-checked
    _MAINFRAME_SHELL_ZSH_STATE=not-checked
    _MAINFRAME_SHELL_INHERITED_STATE=absent
    _MAINFRAME_SHELL_RELOAD_REQUIRED=false
    _MAINFRAME_SHELL_DETAILS=()

    if [[ "$_MAINFRAME_SHELL_SELECTED" != true ]]; then
        if [[ "$_MAINFRAME_SHELL_SELECTION_STATE" == unsafe ]]; then
            _mainframe_shell_note_blocked 'cli:unsafe-first-path-entry'
        else
            _MAINFRAME_SHELL_OVERALL=not-selected
            _MAINFRAME_SHELL_DETAILS+=("cli:$_MAINFRAME_SHELL_SELECTION_STATE")
        fi
    fi

    if [[ -n "$inherited" ]]; then
        active_canonical="$(_mainframe_shell_canonical_dir "$MAINFRAME_ROOT" 2>/dev/null || true)"
        inherited_canonical="$(_mainframe_shell_canonical_dir "$inherited" 2>/dev/null || true)"
        if [[ -n "$active_canonical" && "$inherited_canonical" == "$active_canonical" ]]; then
            _MAINFRAME_SHELL_INHERITED_STATE=ready
        else
            _MAINFRAME_SHELL_INHERITED_STATE=stale
            _MAINFRAME_SHELL_RELOAD_REQUIRED=true
            _MAINFRAME_SHELL_DETAILS+=('environment:stale-root')
        fi
    fi

    if [[ "$shell_scope" == bash || "$shell_scope" == all ]]; then
        local before="${#_MAINFRAME_SHELL_DETAILS[@]}"
        _mainframe_shell_check_profile_kind \
            "$_MAINFRAME_SHELL_HOME/.bashrc" bash-runtime bashrc
        for profile in \
            "$_MAINFRAME_SHELL_HOME/.bash_profile" \
            "$_MAINFRAME_SHELL_HOME/.bash_login" \
            "$_MAINFRAME_SHELL_HOME/.profile"; do
            if [[ "$profile" == "$_MAINFRAME_SHELL_EFFECTIVE_LOGIN" ]]; then
                _mainframe_shell_check_profile_kind "$profile" bash-login "${profile##*/}"
            else
                _mainframe_shell_check_profile_kind "$profile" none "${profile##*/}"
            fi
        done
        _MAINFRAME_SHELL_BASH_STATE="$(_mainframe_shell_scope_result "$before")"
    fi

    if [[ "$shell_scope" == zsh || "$shell_scope" == all ]]; then
        local before="${#_MAINFRAME_SHELL_DETAILS[@]}"
        _mainframe_shell_check_profile_kind \
            "$_MAINFRAME_SHELL_ZSH_DIR/.zshrc" zsh-runtime zshrc
        _MAINFRAME_SHELL_ZSH_STATE="$(_mainframe_shell_scope_result "$before")"
    fi

    # A parent process can retain a previously exported MAINFRAME_ROOT after
    # every persistent profile already points at the active CLI root. Profile
    # repair cannot alter that parent environment, so keep this state distinct
    # from actionable profile drift and direct the operator to reload instead.
    if [[ "$_MAINFRAME_SHELL_OVERALL" == ready &&
          "$_MAINFRAME_SHELL_RELOAD_REQUIRED" == true ]]; then
        _MAINFRAME_SHELL_OVERALL=reload-required
    fi
}

_mainframe_shell_render_status() {
    local shell_scope="$1" json="$2" details='' detail jq_bin
    for detail in "${_MAINFRAME_SHELL_DETAILS[@]}"; do
        details+="${details:+,}$detail"
    done
    [[ -n "$details" ]] || details=none

    if [[ "$json" == true ]]; then
        jq_bin="${_MAINFRAME_CLI_JQ:-}"
        [[ -x "$jq_bin" ]] || {
            printf 'MAINFRAME shell status requires the trusted jq binding.\n' >&2
            return 69
        }
        "$jq_bin" -n \
            --arg state "$_MAINFRAME_SHELL_OVERALL" \
            --arg scope "$shell_scope" \
            --arg active_root "$MAINFRAME_ROOT" \
            --arg selection_state "$_MAINFRAME_SHELL_SELECTION_STATE" \
            --arg selected_cli "$_MAINFRAME_SHELL_SELECTED_CLI" \
            --arg selected_resolved "$_MAINFRAME_SHELL_SELECTED_RESOLVED" \
            --arg inherited_root "${_MAINFRAME_CLI_INHERITED_ROOT:-none}" \
            --arg inherited_state "$_MAINFRAME_SHELL_INHERITED_STATE" \
            --arg bash_state "$_MAINFRAME_SHELL_BASH_STATE" \
            --arg zsh_state "$_MAINFRAME_SHELL_ZSH_STATE" \
            --arg zsh_profile "$_MAINFRAME_SHELL_ZSH_DIR/.zshrc" \
            --arg zdotdir_source "$_MAINFRAME_SHELL_ZDOTDIR_SOURCE" \
            --arg details "$details" \
            '{schema_version:1,state:$state,scope:$scope,active_root:$active_root,
              selection_state:$selection_state,
              selected_cli:$selected_cli,selected_cli_resolved:$selected_resolved,
              inherited_root:$inherited_root,inherited_state:$inherited_state,
              bash_state:$bash_state,zsh_state:$zsh_state,zsh_profile:$zsh_profile,
              zdotdir_source:$zdotdir_source,
              details:($details | split(","))}'
        return 0
    fi

    printf 'MAINFRAME Shell Integration\n'
    printf 'Active root:    %s\n' "$MAINFRAME_ROOT"
    printf 'Selected CLI:   %s (%s)\n' \
        "$_MAINFRAME_SHELL_SELECTED_CLI" "$_MAINFRAME_SHELL_SELECTION_STATE"
    printf 'Inherited root: %s (%s)\n' \
        "${_MAINFRAME_CLI_INHERITED_ROOT:-none}" "$_MAINFRAME_SHELL_INHERITED_STATE"
    [[ "$_MAINFRAME_SHELL_BASH_STATE" == not-checked ]] || \
        printf 'Bash profiles:  %s\n' "$_MAINFRAME_SHELL_BASH_STATE"
    [[ "$_MAINFRAME_SHELL_ZSH_STATE" == not-checked ]] || \
        printf 'zsh profile:    %s\n' "$_MAINFRAME_SHELL_ZSH_STATE"
    if [[ "$shell_scope" == zsh || "$shell_scope" == all ]]; then
        printf 'zsh file:       %s (%s)\n' \
            "$_MAINFRAME_SHELL_ZSH_DIR/.zshrc" "$_MAINFRAME_SHELL_ZDOTDIR_SOURCE"
    fi
    printf 'Details:        %s\n' "$details"
    printf 'State:          %s\n' "$_MAINFRAME_SHELL_OVERALL"
    if [[ "$_MAINFRAME_SHELL_OVERALL" == repair-required ]]; then
        printf 'Next: mainframe shell repair --shell %s --dry-run\n' "$shell_scope"
    elif [[ "$_MAINFRAME_SHELL_OVERALL" == reload-required ]]; then
        printf 'Next: start a fresh shell or restart the parent app to drop the stale inherited MAINFRAME_ROOT.\n'
    elif [[ "$_MAINFRAME_SHELL_OVERALL" == not-selected ]]; then
        printf 'Run the MAINFRAME selected by PATH before repairing shell profiles.\n'
    fi
}

_mainframe_shell_strip_blocks() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    /usr/bin/awk \
        -v runtime_begin="$_MAINFRAME_SHELL_BEGIN" \
        -v runtime_end="$_MAINFRAME_SHELL_END" \
        -v login_begin="$_MAINFRAME_SHELL_LOGIN_BEGIN" \
        -v login_end="$_MAINFRAME_SHELL_LOGIN_END" '
        $0 == runtime_begin { inside = "runtime"; next }
        $0 == login_begin { inside = "login"; next }
        inside == "runtime" && $0 == runtime_end { inside = ""; next }
        inside == "login" && $0 == login_end { inside = ""; next }
        inside == "" { print }
    ' "$file"
}

_mainframe_shell_preflight_file() {
    local file="$1" state
    state="$(_mainframe_shell_profile_layout "$file")"
    case "$state" in
        absent|safe) return 0 ;;
        unsafe)
            printf 'MAINFRAME shell repair refuses an unsafe profile: %s\n' "$file" >&2
            ;;
        malformed)
            printf 'MAINFRAME shell repair refuses malformed managed markers: %s\n' "$file" >&2
            ;;
    esac
    return 77
}

_mainframe_shell_target_set() {
    local shell_scope="$1" profile
    _MAINFRAME_SHELL_TARGET_FILES=()
    _MAINFRAME_SHELL_TARGET_KINDS=()
    if [[ "$shell_scope" == bash || "$shell_scope" == all ]]; then
        _MAINFRAME_SHELL_TARGET_FILES+=("$_MAINFRAME_SHELL_HOME/.bashrc")
        _MAINFRAME_SHELL_TARGET_KINDS+=(bash-runtime)
        for profile in \
            "$_MAINFRAME_SHELL_HOME/.bash_profile" \
            "$_MAINFRAME_SHELL_HOME/.bash_login" \
            "$_MAINFRAME_SHELL_HOME/.profile"; do
            _MAINFRAME_SHELL_TARGET_FILES+=("$profile")
            if [[ "$profile" == "$_MAINFRAME_SHELL_EFFECTIVE_LOGIN" ]]; then
                _MAINFRAME_SHELL_TARGET_KINDS+=(bash-login)
            else
                _MAINFRAME_SHELL_TARGET_KINDS+=(none)
            fi
        done
    fi
    if [[ "$shell_scope" == zsh || "$shell_scope" == all ]]; then
        _MAINFRAME_SHELL_TARGET_FILES+=("$_MAINFRAME_SHELL_ZSH_DIR/.zshrc")
        _MAINFRAME_SHELL_TARGET_KINDS+=(zsh-runtime)
    fi
    return 0
}

_mainframe_shell_prepare_files() {
    local dry_run="$1" index file kind temp mode original_digest output_digest
    local parent fd identity prepare_status
    _MAINFRAME_SHELL_CHANGE_FILES=()
    _MAINFRAME_SHELL_CHANGE_TEMPS=()
    _MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES=()
    _MAINFRAME_SHELL_CHANGE_ORIGINAL=()
    _MAINFRAME_SHELL_CHANGE_OUTPUT=()
    _MAINFRAME_SHELL_CHANGE_MODES=()
    for ((index = 0; index < ${#_MAINFRAME_SHELL_TARGET_FILES[@]}; index++)); do
        file="${_MAINFRAME_SHELL_TARGET_FILES[$index]}"
        kind="${_MAINFRAME_SHELL_TARGET_KINDS[$index]}"
        if [[ "$kind" == none && ! -e "$file" && ! -L "$file" ]]; then
            continue
        fi
        if _mainframe_shell_profile_matches_kind "$file" "$kind"; then
            continue
        fi
        if [[ -f "$file" ]]; then
            mode="$(_mainframe_shell_stat_value '%Lp' '%a' "$file")" || return 74
            original_digest="$(_mainframe_shell_sha256 "$file")" || return 69
        else
            mode=600
            original_digest=absent
        fi
        parent="${file%/*}"
        [[ -n "$parent" ]] || parent=/
        _mainframe_shell_open_exclusive_file \
            "$parent" "${file##*/}.mainframe-shell-prepare" temp fd identity || return $?
        if [[ -f "$file" ]]; then
            if ! _mainframe_shell_strip_blocks "$file" >&"$fd"; then
                exec {fd}>&-
                _mainframe_shell_safe_remove_created "$temp" "$identity" || true
                return 74
            fi
        fi
        if [[ "$kind" != none ]]; then
            if [[ -s "/dev/fd/$fd" ]]; then
                printf '\n' >&"$fd"
            fi
            if ! _mainframe_shell_expected_block "$kind" >&"$fd"; then
                exec {fd}>&-
                _mainframe_shell_safe_remove_created "$temp" "$identity" || true
                return 74
            fi
        fi
        if ! _mainframe_shell_finalize_open_file "$temp" "$fd" "$identity" "$mode" ''; then
            prepare_status=$?
            _mainframe_shell_safe_remove_created "$temp" "$identity" || true
            (( prepare_status != 0 )) || prepare_status=74
            return "$prepare_status"
        fi
        output_digest="$(_mainframe_shell_digest_created_file \
            "$temp" "$identity" "$mode" 2>/dev/null || true)"
        if [[ -z "$output_digest" ]]; then
            _mainframe_shell_safe_remove_created "$temp" "$identity" || true
            return 74
        fi
        if ! _mainframe_shell_revalidate_original "$file" "$original_digest" "$mode"; then
            _mainframe_shell_safe_remove_created "$temp" "$identity" || true
            printf 'Shell profile changed while its repair was prepared: %s\n' "$file" >&2
            return 75
        fi
        if [[ -f "$file" ]] && cmp -s "$file" "$temp"; then
            _mainframe_shell_safe_remove_created "$temp" "$identity" || return 74
            continue
        fi
        _MAINFRAME_SHELL_CHANGE_FILES+=("$file")
        _MAINFRAME_SHELL_CHANGE_TEMPS+=("$temp")
        _MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES+=("$identity")
        _MAINFRAME_SHELL_CHANGE_ORIGINAL+=("$original_digest")
        _MAINFRAME_SHELL_CHANGE_OUTPUT+=("$output_digest")
        _MAINFRAME_SHELL_CHANGE_MODES+=("$mode")
    done
    return 0
}

_mainframe_shell_cleanup_temps() {
    local index temp identity
    for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_TEMPS[@]}; index++)); do
        temp="${_MAINFRAME_SHELL_CHANGE_TEMPS[$index]}"
        identity="${_MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES[$index]}"
        [[ -e "$temp" || -L "$temp" ]] || continue
        _mainframe_shell_safe_remove_created "$temp" "$identity" || true
    done
    return 0
}

_mainframe_shell_revalidate_original() {
    local file="$1" expected="$2" expected_mode="$3" actual current_mode
    if [[ "$expected" == absent ]]; then
        [[ ! -e "$file" && ! -L "$file" ]]
        return
    fi
    _mainframe_shell_preflight_file "$file" || return 1
    actual="$(_mainframe_shell_sha256 "$file")" || return 1
    current_mode="$(_mainframe_shell_stat_value '%Lp' '%a' "$file")" || return 1
    [[ "$actual" == "$expected" && "$current_mode" == "$expected_mode" ]]
}

_mainframe_shell_apply_prepared() {
    local index file temp temp_identity expected expected_mode timestamp backup
    local backup_fd backup_identity parent backup_status=0
    local apply_status=0 failure_file=''
    local -a backups=() backup_identities=() committed=()
    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

    for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_FILES[@]}; index++)); do
        file="${_MAINFRAME_SHELL_CHANGE_FILES[$index]}"
        expected="${_MAINFRAME_SHELL_CHANGE_ORIGINAL[$index]}"
        if ! _mainframe_shell_revalidate_original \
            "$file" "$expected" "${_MAINFRAME_SHELL_CHANGE_MODES[$index]}"; then
            printf 'Shell profile changed after preflight; nothing was replaced: %s\n' "$file" >&2
            return 75
        fi
    done

    for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_FILES[@]}; index++)); do
        file="${_MAINFRAME_SHELL_CHANGE_FILES[$index]}"
        expected="${_MAINFRAME_SHELL_CHANGE_ORIGINAL[$index]}"
        expected_mode="${_MAINFRAME_SHELL_CHANGE_MODES[$index]}"
        if [[ "$expected" == absent ]]; then
            backups+=(absent)
            backup_identities+=(absent)
            continue
        fi
        parent="${file%/*}"
        [[ -n "$parent" ]] || parent=/
        if ! _mainframe_shell_open_exclusive_file \
            "$parent" "${file##*/}.mainframe-shell-backup-$timestamp.$index" \
            backup backup_fd backup_identity; then
            backup_status=$?
            (( backup_status != 0 )) || backup_status=74
            break
        fi
        if ! /bin/cat -- "$file" >&"$backup_fd"; then
            exec {backup_fd}>&-
            _mainframe_shell_safe_remove_created "$backup" "$backup_identity" || true
            backup_status=74
            break
        fi
        if ! _mainframe_shell_finalize_open_file \
                "$backup" "$backup_fd" "$backup_identity" "$expected_mode" "$expected"; then
            _mainframe_shell_safe_remove_created "$backup" "$backup_identity" || true
            backup_status=74
            break
        fi
        backups+=("$backup")
        backup_identities+=("$backup_identity")
    done

    if (( backup_status != 0 )); then
        printf 'Shell repair could not create and verify its private profile backups; no profile was replaced.\n' >&2
        for ((index = 0; index < ${#backups[@]}; index++)); do
            [[ "${backups[$index]}" == absent ]] && continue
            _mainframe_shell_safe_remove_created \
                "${backups[$index]}" "${backup_identities[$index]}" || true
        done
        return "$backup_status"
    fi

    for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_FILES[@]}; index++)); do
        file="${_MAINFRAME_SHELL_CHANGE_FILES[$index]}"
        temp="${_MAINFRAME_SHELL_CHANGE_TEMPS[$index]}"
        temp_identity="${_MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES[$index]}"
        expected="${_MAINFRAME_SHELL_CHANGE_ORIGINAL[$index]}"
        expected_mode="${_MAINFRAME_SHELL_CHANGE_MODES[$index]}"
        if ! _mainframe_shell_revalidate_original "$file" "$expected" "$expected_mode"; then
            apply_status=75
            failure_file="$file"
            break
        fi
        if ! _mainframe_shell_validate_created_file \
            "$temp" "$temp_identity" "$expected_mode" \
            "${_MAINFRAME_SHELL_CHANGE_OUTPUT[$index]}"; then
            apply_status=74
            failure_file="$file"
            break
        fi
        if _mainframe_shell_replace_path "$temp" "$file"; then
            committed+=("$index")
            if ! _mainframe_shell_validate_created_file \
                "$file" "$temp_identity" "$expected_mode" \
                "${_MAINFRAME_SHELL_CHANGE_OUTPUT[$index]}"; then
                apply_status=74
                failure_file="$file"
                break
            fi
            continue
        fi
        apply_status=74
        failure_file="$file"
        break
    done

    if (( apply_status != 0 )); then
        if (( apply_status == 75 )); then
            printf 'Shell profile changed during repair; preserving it and rolling back prior files: %s\n' \
                "$failure_file" >&2
        else
            printf 'Shell repair failed while replacing %s; rolling back prior files.\n' \
                "$failure_file" >&2
        fi
        local committed_index prior backup_value rollback_failed=false
        for ((committed_index = ${#committed[@]} - 1; committed_index >= 0; committed_index--)); do
            prior="${committed[$committed_index]}"
            file="${_MAINFRAME_SHELL_CHANGE_FILES[$prior]}"
            backup_value="${backups[$prior]}"
            temp_identity="${_MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES[$prior]}"
            if ! _mainframe_shell_validate_created_file \
                "$file" "$temp_identity" "${_MAINFRAME_SHELL_CHANGE_MODES[$prior]}" \
                "${_MAINFRAME_SHELL_CHANGE_OUTPUT[$prior]}"; then
                rollback_failed=true
                continue
            fi
            if [[ "$backup_value" == absent ]]; then
                _mainframe_shell_safe_remove_created \
                    "$file" "$temp_identity" || { rollback_failed=true; continue; }
                [[ ! -e "$file" && ! -L "$file" ]] || rollback_failed=true
            else
                if ! _mainframe_shell_validate_created_file \
                    "$backup_value" "${backup_identities[$prior]}" \
                    "${_MAINFRAME_SHELL_CHANGE_MODES[$prior]}" \
                    "${_MAINFRAME_SHELL_CHANGE_ORIGINAL[$prior]}"; then
                    rollback_failed=true
                    continue
                fi
                if [[ -d "$file" && ! -L "$file" ]]; then
                    rollback_failed=true
                    continue
                fi
                if _mainframe_shell_replace_path "$backup_value" "$file" && \
                   _mainframe_shell_validate_created_file \
                        "$file" "${backup_identities[$prior]}" \
                        "${_MAINFRAME_SHELL_CHANGE_MODES[$prior]}" \
                        "${_MAINFRAME_SHELL_CHANGE_ORIGINAL[$prior]}"; then
                    :
                else
                    rollback_failed=true
                fi
            fi
        done
        if [[ "$rollback_failed" == true ]]; then
            printf 'Shell repair could not prove a complete rollback; inspect the reported profile and retained private backups before opening a new shell.\n' >&2
        fi
        return "$apply_status"
    fi

    for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_FILES[@]}; index++)); do
        printf 'Repaired MAINFRAME shell integration: %s\n' \
            "${_MAINFRAME_SHELL_CHANGE_FILES[$index]}"
        if [[ "${backups[$index]}" != absent ]]; then
            printf 'Profile backup: %s\n' "${backups[$index]}"
        fi
    done
    return 0
}

_mainframe_shell_repair() {
    local shell_scope="$1" dry_run="$2" assume_yes="$3" index lock
    _mainframe_shell_prepare_context "$shell_scope" || return $?
    if [[ "$_MAINFRAME_SHELL_SELECTED" != true ]]; then
        printf 'Shell repair must run through the MAINFRAME CLI selected by PATH.\n' >&2
        printf 'Selection: %s\nSelected:  %s\nActive:    %s/bin/mainframe\n' \
            "$_MAINFRAME_SHELL_SELECTION_STATE" "$_MAINFRAME_SHELL_SELECTED_CLI" \
            "$MAINFRAME_ROOT" >&2
        return 78
    fi

    _mainframe_shell_target_set "$shell_scope"
    for ((index = 0; index < ${#_MAINFRAME_SHELL_TARGET_FILES[@]}; index++)); do
        _mainframe_shell_preflight_file "${_MAINFRAME_SHELL_TARGET_FILES[$index]}" || return $?
    done

    if [[ "$dry_run" == true ]]; then
        local prepare_status
        if _mainframe_shell_prepare_files true; then
            :
        else
            prepare_status=$?
            _mainframe_shell_cleanup_temps
            return "$prepare_status"
        fi
        if (( ${#_MAINFRAME_SHELL_CHANGE_FILES[@]} == 0 )); then
            printf 'Shell integration is already current for %s.\n' "$shell_scope"
        else
            for ((index = 0; index < ${#_MAINFRAME_SHELL_CHANGE_FILES[@]}; index++)); do
                printf 'Would repair MAINFRAME shell integration: %s\n' \
                    "${_MAINFRAME_SHELL_CHANGE_FILES[$index]}"
            done
        fi
        _mainframe_shell_cleanup_temps
        return 0
    fi
    [[ "$assume_yes" == true ]] || {
        printf 'Shell repair requires --dry-run or --yes.\n' >&2
        return 64
    }

    lock="$_MAINFRAME_SHELL_HOME/.mainframe-shell-lifecycle.lock"
    if ! mkdir "$lock" 2>/dev/null; then
        printf 'Another MAINFRAME shell lifecycle operation is active: %s\n' "$lock" >&2
        return 75
    fi
    chmod 700 "$lock" || { rmdir "$lock" 2>/dev/null || true; return 74; }

    for ((index = 0; index < ${#_MAINFRAME_SHELL_TARGET_FILES[@]}; index++)); do
        if ! _mainframe_shell_preflight_file "${_MAINFRAME_SHELL_TARGET_FILES[$index]}"; then
            rmdir "$lock" 2>/dev/null || true
            return 77
        fi
    done
    local status
    if _mainframe_shell_prepare_files false; then
        :
    else
        status=$?
        _mainframe_shell_cleanup_temps
        rmdir "$lock" 2>/dev/null || true
        return "$status"
    fi
    if (( ${#_MAINFRAME_SHELL_CHANGE_FILES[@]} == 0 )); then
        printf 'Shell integration is already current for %s.\n' "$shell_scope"
        rmdir "$lock" 2>/dev/null || true
        return 0
    fi
    if _mainframe_shell_apply_prepared; then
        :
    else
        status=$?
        _mainframe_shell_cleanup_temps
        rmdir "$lock" 2>/dev/null || true
        return "$status"
    fi
    _mainframe_shell_cleanup_temps
    rmdir "$lock" 2>/dev/null || true
}

_mainframe_shell_configured_scope() {
    local bash_state zsh_state
    _mainframe_shell_prepare_context all || return $?
    bash_state="$(_mainframe_shell_marker_state \
        "$_MAINFRAME_SHELL_HOME/.bashrc" "$_MAINFRAME_SHELL_BEGIN" "$_MAINFRAME_SHELL_END")"
    zsh_state="$(_mainframe_shell_marker_state \
        "$_MAINFRAME_SHELL_ZSH_DIR/.zshrc" "$_MAINFRAME_SHELL_BEGIN" "$_MAINFRAME_SHELL_END")"
    if [[ "$bash_state" != absent && "$zsh_state" != absent ]]; then
        printf 'all\n'
    elif [[ "$bash_state" != absent ]]; then
        printf 'bash\n'
    elif [[ "$zsh_state" != absent ]]; then
        printf 'zsh\n'
    else
        case "${SHELL:-}" in
            */bash) printf 'bash\n' ;;
            *) printf 'zsh\n' ;;
        esac
    fi
}

_mainframe_shell_homebrew_path_value_safe() {
    local value="${1:-}"
    [[ "$value" == /* && -d "$value" ]] || return 1
    _mainframe_shell_path_is_text_safe "$value" || return 1
    case "$value" in
        *'"'*|*'\'*|*'$'*|*'`'*) return 1 ;;
        *) return 0 ;;
    esac
}

_mainframe_shell_homebrew_wrapper_matches() {
    local wrapper="$1" active_root="$2" bash_opt_bin="$3" jq_opt_bin="$4"
    local opt_bin="$5" opt_libexec="$6" expected_line identity wrapper_fd
    local descriptor_identity path_identity matches=false

    [[ -x /usr/bin/cmp && -x /usr/bin/printf ]] || return 1
    identity="$(_mainframe_shell_file_identity "$wrapper" 2>/dev/null || true)"
    [[ -n "$identity" ]] || return 1
    _mainframe_shell_validate_created_file "$wrapper" "$identity" 555 || return 1
    # shellcheck disable=SC2016 # $PATH and $@ are literal wrapper syntax.
    builtin printf -v expected_line \
        'PATH="%s:%s:$PATH" MAINFRAME_INSTALL_METHOD="homebrew" MAINFRAME_HOMEBREW_BASH_OPT_BIN="%s" MAINFRAME_HOMEBREW_JQ_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_LIBEXEC="%s" MAINFRAME_PI_LIFECYCLE_REQUIRED="1" exec "%s/bin/mainframe"  "$@"' \
        "$bash_opt_bin" "$jq_opt_bin" "$bash_opt_bin" "$jq_opt_bin" \
        "$opt_bin" "$opt_libexec" "$active_root"

    exec {wrapper_fd}<"$wrapper" || return 1
    descriptor_identity="$(_mainframe_shell_descriptor_identity \
        "/dev/fd/$wrapper_fd" 2>/dev/null || true)"
    path_identity="$(_mainframe_shell_path_identity_for_descriptor \
        "$wrapper" 2>/dev/null || true)"
    if [[ -n "$descriptor_identity" && "$descriptor_identity" == "$path_identity" ]] && \
       /usr/bin/cmp -s "/dev/fd/$wrapper_fd" <(
           /usr/bin/printf '#!/bin/bash\n%s\n' "$expected_line"
       ); then
        matches=true
    fi
    exec {wrapper_fd}<&-

    [[ "$matches" == true ]] || return 1
    _mainframe_shell_validate_created_file "$wrapper" "$identity" 555
}

_mainframe_shell_homebrew_path_selection() {
    local expected_wrapper="$1" search_path="${_MAINFRAME_CLI_CALLER_PATH:-}"
    local raw_entry entry candidate resolved

    _MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE=missing
    _MAINFRAME_SHELL_HOMEBREW_SELECTED_CLI=none
    _MAINFRAME_SHELL_HOMEBREW_SELECTED_RESOLVED=none
    while IFS= read -r raw_entry; do
        if [[ -z "$raw_entry" ]]; then
            candidate="${PWD:-.}/mainframe"
        else
            candidate="$raw_entry/mainframe"
        fi
        [[ -x "$candidate" ]] || continue
        _MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE=unsafe
        _MAINFRAME_SHELL_HOMEBREW_SELECTED_CLI="$candidate"

        # Homebrew's public bin and Cellar ancestry may be group-writable by
        # design. Resolve only the first shell-lookup hit and admit it solely
        # when it reaches the already byte-authenticated keg wrapper.
        [[ "$raw_entry" == /* && -d "$raw_entry" ]] || return 0
        entry="$(_mainframe_shell_canonical_dir "$raw_entry" 2>/dev/null || true)"
        [[ -n "$entry" ]] || return 0
        _mainframe_shell_path_is_text_safe "$entry" || return 0
        candidate="$entry/mainframe"
        resolved="$(_mainframe_shell_resolve_file "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || return 0
        _MAINFRAME_SHELL_HOMEBREW_SELECTED_CLI="$candidate"
        _MAINFRAME_SHELL_HOMEBREW_SELECTED_RESOLVED="$resolved"
        if [[ "$resolved" == "$expected_wrapper" ]]; then
            _MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE=ready
        else
            _MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE=mismatch
        fi
        return 0
    done < <(/usr/bin/printf '%s\n' "$search_path" | /usr/bin/tr ':' '\n')
    return 0
}

_mainframe_shell_doctor_check() {
    local scope active_root homebrew_root homebrew_bin homebrew_wrapper homebrew_keg
    local opt_prefix opt_bin opt_libexec bash_opt_bin jq_opt_bin wrapper_candidate
    _mainframe_shell_prepare_context all || return $?
    if [[ "${MAINFRAME_INSTALL_METHOD:-}" == homebrew ]]; then
        opt_bin="${MAINFRAME_HOMEBREW_OPT_BIN:-}"
        opt_libexec="${MAINFRAME_HOMEBREW_OPT_LIBEXEC:-}"
        bash_opt_bin="${MAINFRAME_HOMEBREW_BASH_OPT_BIN:-}"
        jq_opt_bin="${MAINFRAME_HOMEBREW_JQ_OPT_BIN:-}"
        homebrew_root="$(_mainframe_shell_canonical_dir \
            "$opt_libexec" 2>/dev/null || true)"
        homebrew_bin="$(_mainframe_shell_canonical_dir \
            "$opt_bin" 2>/dev/null || true)"
        active_root="$(_mainframe_shell_canonical_dir "$MAINFRAME_ROOT" 2>/dev/null || true)"
        opt_prefix="${opt_libexec%/libexec}"
        homebrew_keg="${homebrew_root%/libexec}"
        wrapper_candidate="$homebrew_bin/mainframe"
        if ! _mainframe_shell_homebrew_path_value_safe "$opt_bin" || \
           ! _mainframe_shell_homebrew_path_value_safe "$opt_libexec" || \
           ! _mainframe_shell_homebrew_path_value_safe "$bash_opt_bin" || \
           ! _mainframe_shell_homebrew_path_value_safe "$jq_opt_bin" || \
           ! _mainframe_shell_homebrew_path_value_safe "$active_root" || \
           [[ "${MAINFRAME_PI_LIFECYCLE_REQUIRED:-}" != 1 || \
              -z "$homebrew_root" || "$homebrew_root" != "$active_root" || \
              "$opt_libexec" != "$opt_prefix/libexec" || \
              "$opt_bin" != "$opt_prefix/bin" || \
              "$homebrew_root" != "$homebrew_keg/libexec" || \
              "$homebrew_bin" != "$homebrew_keg/bin" || \
              ! -f "$wrapper_candidate" || -L "$wrapper_candidate" || \
              ! -x "$wrapper_candidate" ]]; then
            printf 'Shell identity: Homebrew-managed runtime binding is unverified (ERROR)\n'
            return 1
        fi
        homebrew_wrapper="$(_mainframe_shell_resolve_file \
            "$wrapper_candidate" 2>/dev/null || true)"
        if [[ "$homebrew_wrapper" != "$wrapper_candidate" ]] || \
           ! _mainframe_shell_homebrew_wrapper_matches \
               "$homebrew_wrapper" "$active_root" "$bash_opt_bin" "$jq_opt_bin" \
               "$opt_bin" "$opt_libexec"; then
            printf 'Shell identity: Homebrew-managed runtime binding is unverified (ERROR)\n'
            return 1
        fi
        _mainframe_shell_homebrew_path_selection "$homebrew_wrapper"
        # Revalidate after resolving a potentially group-writable public link.
        if ! _mainframe_shell_homebrew_wrapper_matches \
            "$homebrew_wrapper" "$active_root" "$bash_opt_bin" "$jq_opt_bin" \
            "$opt_bin" "$opt_libexec"; then
            printf 'Shell identity: Homebrew-managed runtime binding is unverified (ERROR)\n'
            return 1
        fi
        case "$_MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE" in
            ready)
                printf 'Shell identity: Homebrew-managed wrapper (selected; profiles not required)\n'
                return 0
                ;;
            missing)
                printf 'Shell identity: Homebrew-managed explicit runtime (profiles not required)\n'
                return 0
                ;;
        esac
        printf 'Shell identity: Homebrew-managed runtime is %s (ERROR)\n' \
            "$_MAINFRAME_SHELL_HOMEBREW_SELECTION_STATE"
        return 1
    fi
    if [[ "$_MAINFRAME_SHELL_SELECTED" != true && \
          "$_MAINFRAME_SHELL_SELECTION_STATE" == missing ]]; then
        printf 'Shell identity: Explicit runtime (selected PATH integration not checked)\n'
        return 0
    fi
    scope="$(_mainframe_shell_configured_scope)" || return $?
    _mainframe_shell_collect "$scope" || return $?
    if [[ "$_MAINFRAME_SHELL_OVERALL" == ready ]]; then
        printf 'Shell identity: Ready (OK; %s)\n' "$scope"
        return 0
    fi
    if [[ "$_MAINFRAME_SHELL_OVERALL" == reload-required ]]; then
        printf 'Shell identity: reload-required (%s; profiles current)\n' "$scope"
        printf 'Shell identity next: start a fresh shell or restart the parent app, then run mainframe doctor.\n'
        return 1
    fi
    printf 'Shell identity: %s (%s; run mainframe shell status)\n' \
        "$_MAINFRAME_SHELL_OVERALL" "$scope"
    return 1
}

mainframe_shell() {
    local action="${1:-status}" shell_scope=all json=false dry_run=false assume_yes=false
    local zdotdir_override=''
    [[ $# -eq 0 ]] || shift
    case "$action" in
        status|repair) ;;
        help|-h|--help) _mainframe_shell_usage; return 0 ;;
        *) printf 'Unknown shell command: %s\n' "$action" >&2; _mainframe_shell_usage >&2; return 64 ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --shell)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    printf '%s\n' '--shell requires bash, zsh, or all' >&2
                    return 64
                }
                shell_scope="$2"
                shift 2
                ;;
            --json) json=true; shift ;;
            --zdotdir)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    printf '%s\n' '--zdotdir requires an absolute directory' >&2
                    return 64
                }
                zdotdir_override="$2"
                shift 2
                ;;
            --dry-run) dry_run=true; shift ;;
            --yes) assume_yes=true; shift ;;
            -h|--help) _mainframe_shell_usage; return 0 ;;
            *) printf 'Unknown shell option: %s\n' "$1" >&2; return 64 ;;
        esac
    done
    case "$shell_scope" in bash|zsh|all) ;; *) printf 'Invalid --shell value: %s\n' "$shell_scope" >&2; return 64 ;; esac
    [[ "$shell_scope" != bash || -z "$zdotdir_override" ]] || {
        printf '%s\n' '--zdotdir is valid only when zsh is in scope' >&2
        return 64
    }
    _MAINFRAME_SHELL_ZDOTDIR_OVERRIDE="$zdotdir_override"

    if [[ "$action" == status ]]; then
        [[ "$dry_run" == false && "$assume_yes" == false ]] || {
            printf 'Shell status does not accept --dry-run or --yes.\n' >&2
            return 64
        }
        _mainframe_shell_collect "$shell_scope" || return $?
        _mainframe_shell_render_status "$shell_scope" "$json" || return $?
        case "$_MAINFRAME_SHELL_OVERALL" in
            ready) return 0 ;;
            blocked) return 77 ;;
            *) return 2 ;;
        esac
    fi

    [[ "$json" == false ]] || { printf 'Shell repair does not accept --json.\n' >&2; return 64; }
    [[ "$dry_run" != true || "$assume_yes" != true ]] || {
        printf 'Choose exactly one of --dry-run or --yes.\n' >&2
        return 64
    }
    _mainframe_shell_repair "$shell_scope" "$dry_run" "$assume_yes"
}

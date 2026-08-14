#!/bin/bash -p
# Trusted interpreter bootstrap shared by local release-construction scripts.
# This file is sourced; it does not perform release work on its own.

_mainframe_release_resolve_executable() {
    local source="${1:-}" dir target links=0
    [[ "$source" == /* ]] || return 1
    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        dir="${source%/*}"
        [[ -n "$dir" ]] || dir=/
        dir="$(builtin cd -- "$dir" 2>/dev/null && builtin pwd -P)" || return 1
        if [[ -x /usr/bin/readlink ]]; then
            target="$(/usr/bin/readlink "$source")" || return 1
        elif [[ -x /bin/readlink ]]; then
            target="$(/bin/readlink "$source")" || return 1
        else
            return 1
        fi
        [[ "$target" == /* ]] && source="$target" || source="$dir/$target"
    done
    dir="${source%/*}"
    [[ -n "$dir" ]] || dir=/
    dir="$(builtin cd -- "$dir" 2>/dev/null && builtin pwd -P)" || return 1
    source="$dir/${source##*/}"
    [[ -f "$source" && -x "$source" ]] || return 1
    [[ "$source" != *$'\n'* && "$source" != *$'\r'* &&
       "$source" != *$'\t'* ]] || return 1
    printf '%s\n' "$source"
}

_mainframe_release_bash_supported() {
    local candidate="${1:-}"
    [[ -x "$candidate" ]] || return 1
    "$candidate" --noprofile --norc -p -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
    ' >/dev/null 2>&1
}

_mainframe_release_select_bash() {
    local override="${MAINFRAME_BASH:-}" candidate resolved seen=':'

    if [[ -n "$override" && "$override" != /* ]]; then
        printf '%s\n' \
            'ERROR: MAINFRAME_BASH must be an absolute path to a reviewed Bash 4.4+ executable' >&2
        return 1
    fi

    if [[ -n "$override" ]]; then
        resolved="$(_mainframe_release_resolve_executable "$override" 2>/dev/null || true)"
        if [[ -z "$resolved" ]] || ! _mainframe_release_bash_supported "$resolved"; then
            printf '%s\n' \
                'ERROR: MAINFRAME_BASH must be an executable Bash 4.4 or newer' >&2
            return 1
        fi
        printf '%s\n' "$resolved"
        return 0
    fi

    for candidate in \
        "${BASH:-}" \
        /opt/homebrew/bin/bash \
        /usr/local/bin/bash \
        /home/linuxbrew/.linuxbrew/bin/bash \
        /usr/bin/bash \
        /bin/bash; do
        [[ -n "$candidate" ]] || continue
        resolved="$(_mainframe_release_resolve_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        case "$seen" in *":$resolved:"*) continue ;; esac
        seen="${seen}${resolved}:"
        if _mainframe_release_bash_supported "$resolved"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done

    printf '%s\n' \
        'ERROR: release construction requires Bash 4.4+; set MAINFRAME_BASH to an absolute reviewed executable' >&2
    return 1
}

_mainframe_release_python_supported() {
    local candidate="${1:-}"
    [[ -x "$candidate" ]] || return 1
    "$candidate" -I -S -c \
        'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
        >/dev/null 2>&1
}

_mainframe_release_select_python() {
    local override="${MAINFRAME_PYTHON:-}" candidate resolved seen=':'

    if [[ -n "$override" && "$override" != /* ]]; then
        printf '%s\n' \
            'ERROR: MAINFRAME_PYTHON must be an absolute path to a reviewed Python 3.10+ executable' >&2
        return 1
    fi

    if [[ -n "$override" ]]; then
        resolved="$(_mainframe_release_resolve_executable "$override" 2>/dev/null || true)"
        if [[ -z "$resolved" ]] || ! _mainframe_release_python_supported "$resolved"; then
            printf '%s\n' \
                'ERROR: MAINFRAME_PYTHON must be an executable Python 3.10 or newer' >&2
            return 1
        fi
        printf '%s\n' "$resolved"
        return 0
    fi

    for candidate in \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3 \
        /usr/bin/python3 \
        /bin/python3; do
        [[ -n "$candidate" ]] || continue
        resolved="$(_mainframe_release_resolve_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        case "$seen" in *":$resolved:"*) continue ;; esac
        seen="${seen}${resolved}:"
        if _mainframe_release_python_supported "$resolved"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done

    printf '%s\n' \
        'ERROR: release construction requires Python 3.10+; set MAINFRAME_PYTHON to an absolute reviewed executable' >&2
    return 1
}

_mainframe_release_scrub_loader_env() {
    local function_name variable prefix

    # An explicit `bash script` invocation is not privileged even when the
    # script's shebang is. Remove caller aliases and imported functions before
    # any interpreter probe; retain only this sourced bootstrap's own helpers.
    builtin unalias -a 2>/dev/null || true
    while IFS= builtin read -r function_name; do
        case "$function_name" in
            _mainframe_release_resolve_executable|\
            _mainframe_release_bash_supported|\
            _mainframe_release_select_bash|\
            _mainframe_release_python_supported|\
            _mainframe_release_select_python|\
            _mainframe_release_scrub_loader_env|\
            mainframe_release_bootstrap)
                ;;
            *)
                builtin unset -f "$function_name" 2>/dev/null || return 1
                ;;
        esac
    done < <(builtin compgen -A function)

    # These variables are readonly in Bash, but their export attributes are
    # mutable. Do not propagate even the protected shell's normalized values.
    builtin export -n BASHOPTS SHELLOPTS 2>/dev/null || return 1
    builtin unset -v \
        BASH_ENV BASH_LOADABLES_PATH BASH_XTRACEFD ENV CDPATH GLOBIGNORE \
        NODE_OPTIONS NODE_PATH NODE_REDIRECT_WARNINGS NODE_REPL_HISTORY \
        NODE_V8_COVERAGE PERL5OPT PERL5LIB PERLLIB \
        PYTHONHOME PYTHONPATH PYTHONSTARTUP PYTHONINSPECT PYTHONWARNINGS \
        PYTHONBREAKPOINT PYTHONUSERBASE PYTHONHASHSEED RUBYOPT RUBYLIB \
        MAINFRAME_ROOT MAINFRAME_MANIFEST_PATH \
        MAINFRAME_INVOCATION_INDEX_PATH MAINFRAME_LSP_META_PATH
    for prefix in LD_ DYLD_; do
        while IFS= builtin read -r variable; do
            builtin unset -v "$variable"
        done < <(builtin compgen -A variable "$prefix")
    done
}

mainframe_release_bootstrap() {
    local script="${1:?release script is required}"
    shift
    local selected_bash current_bash selected_python

    # Scrub before probing or re-executing either interpreter so dynamic
    # loader and non-interactive startup hooks cannot run in the child first.
    _mainframe_release_scrub_loader_env
    selected_bash="$(_mainframe_release_select_bash)" || return 1
    current_bash="$(_mainframe_release_resolve_executable "${BASH:-}" 2>/dev/null || true)"
    case "$-" in
        *p*) ;;
        *) exec "$selected_bash" --noprofile --norc -p "$script" "$@" ;;
    esac
    if [[ "$current_bash" != "$selected_bash" ]]; then
        exec "$selected_bash" --noprofile --norc -p "$script" "$@"
    fi

    selected_python="$(_mainframe_release_select_python)" || return 1

    MAINFRAME_RELEASE_BASH="$selected_bash"
    MAINFRAME_RELEASE_PYTHON="$selected_python"
    MAINFRAME_BASH="$selected_bash"
    MAINFRAME_PYTHON="$selected_python"
    # Trust is granted to the reviewed interpreter file, not every executable
    # beside it. Descendants invoke that absolute Python path directly while
    # ordinary utilities resolve only from fixed system directories.
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export MAINFRAME_RELEASE_BASH MAINFRAME_RELEASE_PYTHON
    export MAINFRAME_BASH MAINFRAME_PYTHON PATH

    readonly MAINFRAME_RELEASE_BASH MAINFRAME_RELEASE_PYTHON
    readonly MAINFRAME_BASH MAINFRAME_PYTHON PATH
}

#!/usr/bin/env bash
# Fixed public bridge from `mainframe invoke` to the durable control-plane.
#
# This layer parses only presentation compatibility options, then replaces
# itself with the fixed installed launcher.  It never selects an executable,
# function, policy outcome, authority, durable identity, or Evidence, and it
# never stages caller input or broker output in a named filesystem object.

[[ -n "${_MAINFRAME_DURABLE_INVOKE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DURABLE_INVOKE_LOADED=1

_mainframe_durable_usage() {
    /bin/cat <<'EOF'
Usage:
  mainframe invoke <canonical-id> --input-json '<object>'
  mainframe invoke <canonical-id> --input-json -
  mainframe invoke cancel --client-correlation-id <id>

Options:
  --profile stable-core
  --format raw|broker-json-v1|control-plane-json-v1
  --caller NAME                    Compatibility-only client label
  --client-correlation-id ID       Non-authorizing idempotency/cancel key
EOF
}

_mainframe_durable_correlation_is_valid() {
    local value="${1:-}"
    [[ ${#value} -ge 1 && ${#value} -le 128 &&
       "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]
}

_mainframe_durable_generate_correlation() {
    local epoch
    epoch="$(/bin/date -u '+%s' 2>/dev/null)" || return 1
    printf 'client-%s-%s-%s\n' "$epoch" "$$" "$RANDOM"
}

# Replace this Bash process with one fixed launcher under a minimal
# environment.  XDG_STATE_HOME is only forwarded after a cheap preflight; the
# Python launcher independently revalidates ownership, mode, symlinks, and the
# pwd-database fallback before opening its durable ledger.
_mainframe_durable_exec_clean() {
    local launcher="$1" state_home="${XDG_STATE_HOME:-}"
    local owner_mode owner mode numeric
    local -a environment=(
        /usr/bin/env -i
        "HOME=${HOME:-}"
        "USER=${USER:-}"
        "LOGNAME=${LOGNAME:-}"
        TMPDIR=/tmp
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        LC_ALL=C
        NO_COLOR=1
        TERM=dumb
    )
    shift

    if [[ "$state_home" == /* && -d "$state_home" && ! -L "$state_home" ]]; then
        owner_mode="$(_mainframe_cli_owner_mode "$state_home" 2>/dev/null || true)"
        read -r owner mode <<<"$owner_mode"
        if [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]]; then
            numeric=$((8#$mode))
            if [[ "$owner" -eq "$EUID" ]] && (( (numeric & 0077) == 0 )); then
                environment+=("XDG_STATE_HOME=$state_home")
            fi
        fi
    fi

    exec "${environment[@]}" "$launcher" "$@"
}

_mainframe_durable_cancel_main() {
    local launcher="$1" correlation_id=""
    shift

    while (( $# > 0 )); do
        case "$1" in
            --client-correlation-id)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                correlation_id="$2"
                shift 2
                ;;
            --client-correlation-id=*)
                correlation_id="${1#*=}"
                shift
                ;;
            *)
                _mainframe_durable_usage >&2
                return 64
                ;;
        esac
    done
    _mainframe_durable_correlation_is_valid "$correlation_id" || {
        _mainframe_durable_usage >&2
        return 64
    }
    _mainframe_durable_exec_clean "$launcher" canonical-cancel \
        --client-correlation-id "$correlation_id"
}

_mainframe_durable_invoke_main() {
    local launcher="$MAINFRAME_ROOT/control_plane/mainframe-control-plane"
    local canonical_id="${1:-}" input_source="" profile=stable-core format=raw
    local caller=cli correlation_id=""

    if [[ "$canonical_id" == cancel ]]; then
        shift
        _mainframe_durable_cancel_main "$launcher" "$@"
        return $?
    fi
    case "$canonical_id" in
        -h|--help)
            _mainframe_durable_usage
            return 0
            ;;
        '')
            _mainframe_durable_usage >&2
            return 64
            ;;
    esac
    shift

    while (( $# > 0 )); do
        case "$1" in
            --input-json)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                [[ -z "$input_source" ]] || { _mainframe_durable_usage >&2; return 64; }
                input_source="$2"
                shift 2
                ;;
            --input-json=*)
                [[ -z "$input_source" ]] || { _mainframe_durable_usage >&2; return 64; }
                input_source="${1#*=}"
                shift
                ;;
            --profile)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                profile="$2"
                shift 2
                ;;
            --profile=*) profile="${1#*=}"; shift ;;
            --format)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                format="$2"
                shift 2
                ;;
            --format=*) format="${1#*=}"; shift ;;
            --caller)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                caller="$2"
                shift 2
                ;;
            --caller=*) caller="${1#*=}"; shift ;;
            --client-correlation-id)
                (( $# >= 2 )) || { _mainframe_durable_usage >&2; return 64; }
                correlation_id="$2"
                shift 2
                ;;
            --client-correlation-id=*) correlation_id="${1#*=}"; shift ;;
            *)
                _mainframe_durable_usage >&2
                return 64
                ;;
        esac
    done

    [[ "$profile" == stable-core ]] || return 64
    case "$format" in
        raw|broker-json-v1|control-plane-json-v1) ;;
        *) return 64 ;;
    esac
    # Retained only so existing callers do not break.  It is deliberately not
    # forwarded to the kernel and cannot influence actor, workspace, or policy.
    [[ "$caller" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || return 64
    [[ -n "$input_source" ]] || { _mainframe_durable_usage >&2; return 64; }
    if [[ -z "$correlation_id" ]]; then
        correlation_id="$(_mainframe_durable_generate_correlation)" || return 70
    fi
    _mainframe_durable_correlation_is_valid "$correlation_id" || return 64

    _mainframe_durable_exec_clean "$launcher" canonical-invoke \
        --canonical-id "$canonical_id" \
        --input-json "$input_source" \
        --client-correlation-id "$correlation_id" \
        --format "$format"
}

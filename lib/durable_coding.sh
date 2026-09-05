#!/usr/bin/env bash
# Fixed public Bash facade for the kernel-owned coding control plane.
#
# This layer selects only one of five reviewed tool IDs and a presentation
# format. It creates canonical input JSON on an anonymous pipe, then replaces
# itself with the fixed installed Python launcher. The kernel generates every
# durable identity and owns policy evaluation, approval state, execution, and
# Evidence. No executable, argv, environment, ledger, identity, authority, or
# approval selector crosses this boundary.

[[ -n "${_MAINFRAME_DURABLE_CODING_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DURABLE_CODING_LOADED=1

readonly _MAINFRAME_CODING_READ='mainframe.coding.read_file.v1'
readonly _MAINFRAME_CODING_SEARCH='mainframe.coding.search_text.v1'
readonly _MAINFRAME_CODING_EDIT='mainframe.coding.atomic_edit.v1'
readonly _MAINFRAME_CODING_TEST='mainframe.coding.run_test.v1'
readonly _MAINFRAME_CODING_BUILD='mainframe.coding.run_build.v1'

_mainframe_durable_coding_usage() {
    /bin/cat <<'EOF'
Usage:
  mainframe code read [--json] [--] <relative-path>
  mainframe code search [--json] [--] <relative-path> <query>
  mainframe code edit --preimage-sha256 SHA256 [--] <relative-path>
  mainframe code test
  mainframe code build

`read` and `search` return raw output unless --json is selected. `edit`
reads replacement content only from stdin and requires the exact lowercase
SHA-256 of the current file. Mutating and code-execution requests return the
durable structured approval state; this facade cannot approve or execute them.
EOF
}

# Replace this process with the fixed launcher under a closed environment.
# XDG_STATE_HOME is forwarded only when it is already an absolute,
# owner-private directory. Python independently revalidates it and otherwise
# derives the current account's state directory from the password database.
_mainframe_durable_coding_exec_clean() {
    local launcher="$1" tool="$2" format="$3"
    local state_home="${XDG_STATE_HOME:-}" owner_mode owner mode numeric
    local -a environment=(
        /usr/bin/env -i
        TMPDIR=/tmp
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        LC_ALL=C
        NO_COLOR=1
        TERM=dumb
    )

    if [[ "$state_home" == /* && "$state_home" != / &&
          -d "$state_home" && ! -L "$state_home" ]]; then
        owner_mode="$(_mainframe_cli_owner_mode "$state_home" 2>/dev/null || true)"
        read -r owner mode <<<"$owner_mode"
        if [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]]; then
            numeric=$((8#$mode))
            if [[ "$owner" -eq "$EUID" ]] && (( (numeric & 0077) == 0 )); then
                environment+=("XDG_STATE_HOME=$state_home")
            fi
        fi
    fi

    exec "${environment[@]}" "$launcher" coding-invoke \
        --tool-id "$tool" --input-json - --format "$format"
}

_mainframe_durable_coding_read_or_search() {
    local launcher="$1" tool="$2" format="$3" path="$4"
    local query="${5-}" jq_path="${_MAINFRAME_CLI_JQ:-}"

    [[ -n "$jq_path" && -x "$jq_path" ]] || {
        builtin printf 'MAINFRAME code denied: trusted jq is unavailable\n' >&2
        return 69
    }
    if [[ "$tool" == "$_MAINFRAME_CODING_READ" ]]; then
        exec 0< <(
            "$jq_path" -cnS --arg path "$path" '{path:$path}'
        )
    else
        exec 0< <(
            "$jq_path" -cnS --arg path "$path" --arg query "$query" \
                '{path:$path,query:$query}'
        )
    fi
    _mainframe_durable_coding_exec_clean "$launcher" "$tool" "$format"
}

_mainframe_durable_coding_edit() {
    local launcher="$1" path="$2" expected_sha256="$3"
    local jq_path="${_MAINFRAME_CLI_JQ:-}" anonymous_path read_fd write_fd
    local content_bytes owner_mode owner mode numeric

    [[ -n "$jq_path" && -x "$jq_path" ]] || {
        builtin printf 'MAINFRAME code denied: trusted jq is unavailable\n' >&2
        return 69
    }
    [[ -x /usr/bin/mktemp && -x /usr/bin/iconv && -x /usr/bin/head &&
       -x /usr/bin/stat ]] || return 69
    # Open separate read/write descriptors while the file is still empty, then
    # unlink its pathname before reading the first caller byte. This provides a
    # seekable anonymous descriptor for jq without leaving edit content behind
    # after a crash. The UTF-8 and byte bounds are enforced before the kernel
    # sees any request, so jq cannot replace malformed bytes or buffer an
    # unbounded stream.
    anonymous_path=$(/usr/bin/mktemp /tmp/mainframe-coding-input.XXXXXX) || return 74
    /bin/chmod 0600 "$anonymous_path" || {
        /bin/rm -f -- "$anonymous_path"
        return 74
    }
    owner_mode="$(_mainframe_cli_owner_mode "$anonymous_path" 2>/dev/null || true)"
    read -r owner mode <<<"$owner_mode"
    [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] || {
        /bin/rm -f -- "$anonymous_path"
        return 74
    }
    numeric=$((8#$mode))
    [[ "$owner" -eq "$EUID" ]] && (( (numeric & 0077) == 0 )) || {
        /bin/rm -f -- "$anonymous_path"
        return 74
    }
    exec {read_fd}<"$anonymous_path" || {
        /bin/rm -f -- "$anonymous_path"
        return 74
    }
    exec {write_fd}>"$anonymous_path" || {
        exec {read_fd}<&-
        /bin/rm -f -- "$anonymous_path"
        return 74
    }
    /bin/rm -f -- "$anonymous_path" || {
        exec {read_fd}<&- {write_fd}>&-
        return 74
    }
    anonymous_path=''
    if ! /usr/bin/head -c 24577 <&0 |
        /usr/bin/iconv -f UTF-8 -t UTF-8 >&"$write_fd"; then
        exec {read_fd}<&- {write_fd}>&-
        return 65
    fi
    exec {write_fd}>&-
    content_bytes=$(
        /usr/bin/stat -Lc '%s' "/dev/fd/$read_fd" 2>/dev/null ||
            /usr/bin/stat -Lf '%z' "/dev/fd/$read_fd" 2>/dev/null
    ) || {
        exec {read_fd}<&-
        return 74
    }
    [[ "$content_bytes" =~ ^[0-9]+$ ]] && (( content_bytes <= 24576 )) || {
        exec {read_fd}<&-
        return 65
    }
    exec 0< <(
        "$jq_path" -cnS \
            --arg path "$path" \
            --arg expected_sha256 "$expected_sha256" \
            --rawfile content "/dev/fd/$read_fd" \
            '{content:$content,expected_sha256:$expected_sha256,path:$path}'
    )
    exec {read_fd}<&-
    _mainframe_durable_coding_exec_clean \
        "$launcher" "$_MAINFRAME_CODING_EDIT" control-plane-json-v1
}

_mainframe_durable_coding_parse_read() {
    local launcher="$1" action="$2"
    local format=raw options=true json_seen=false
    local -a values=()
    shift 2

    while (( $# > 0 )); do
        if [[ "$options" == true ]]; then
            case "$1" in
                --json)
                    [[ "$json_seen" == false ]] || {
                        _mainframe_durable_coding_usage >&2
                        return 64
                    }
                    json_seen=true
                    format=control-plane-json-v1
                    shift
                    continue
                    ;;
                --)
                    options=false
                    shift
                    continue
                    ;;
                -*)
                    _mainframe_durable_coding_usage >&2
                    return 64
                    ;;
            esac
        fi
        values+=("$1")
        shift
    done

    case "$action" in
        read)
            (( ${#values[@]} == 1 )) || {
                _mainframe_durable_coding_usage >&2
                return 64
            }
            _mainframe_durable_coding_read_or_search \
                "$launcher" "$_MAINFRAME_CODING_READ" "$format" "${values[0]}"
            ;;
        search)
            (( ${#values[@]} == 2 )) || {
                _mainframe_durable_coding_usage >&2
                return 64
            }
            _mainframe_durable_coding_read_or_search \
                "$launcher" "$_MAINFRAME_CODING_SEARCH" "$format" \
                "${values[0]}" "${values[1]}"
            ;;
        *) return 64 ;;
    esac
}

_mainframe_durable_coding_parse_edit() {
    local launcher="$1" expected_sha256='' preimage_seen=false options=true
    local -a values=()
    shift

    while (( $# > 0 )); do
        if [[ "$options" == true ]]; then
            case "$1" in
                --preimage-sha256)
                    [[ "$preimage_seen" == false && $# -ge 2 ]] || {
                        _mainframe_durable_coding_usage >&2
                        return 64
                    }
                    preimage_seen=true
                    expected_sha256="$2"
                    shift 2
                    continue
                    ;;
                --)
                    options=false
                    shift
                    continue
                    ;;
                -*)
                    _mainframe_durable_coding_usage >&2
                    return 64
                    ;;
            esac
        fi
        values+=("$1")
        shift
    done

    (( ${#values[@]} == 1 )) && [[ "$preimage_seen" == true ]] &&
        [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || {
        _mainframe_durable_coding_usage >&2
        return 64
    }
    _mainframe_durable_coding_edit "$launcher" "${values[0]}" "$expected_sha256"
}

_mainframe_durable_coding_main() {
    local launcher="$MAINFRAME_ROOT/control_plane/mainframe-control-plane"
    local action="${1:-}"
    shift || true

    case "$action" in
        read|search)
            _mainframe_durable_coding_parse_read "$launcher" "$action" "$@"
            ;;
        edit)
            _mainframe_durable_coding_parse_edit "$launcher" "$@"
            ;;
        test|build)
            (( $# == 0 )) || {
                _mainframe_durable_coding_usage >&2
                return 64
            }
            [[ -n "${_MAINFRAME_CLI_JQ:-}" && -x "$_MAINFRAME_CLI_JQ" ]] || {
                builtin printf 'MAINFRAME code denied: trusted jq is unavailable\n' >&2
                return 69
            }
            exec 0< <("$_MAINFRAME_CLI_JQ" -cnS '{}')
            if [[ "$action" == test ]]; then
                _mainframe_durable_coding_exec_clean \
                    "$launcher" "$_MAINFRAME_CODING_TEST" control-plane-json-v1
            else
                _mainframe_durable_coding_exec_clean \
                    "$launcher" "$_MAINFRAME_CODING_BUILD" control-plane-json-v1
            fi
            ;;
        -h|--help|help|'')
            _mainframe_durable_coding_usage
            ;;
        *)
            _mainframe_durable_coding_usage >&2
            return 64
            ;;
    esac
}

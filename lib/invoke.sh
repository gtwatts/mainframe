#!/usr/bin/env bash
# =============================================================================
# MAINFRAME canonical invocation broker
# =============================================================================
# This file is sourced only by bin/mainframe's protected, pre-runtime `invoke`
# fast path.  It intentionally does not source common.sh in the broker process.
# A reviewed manifest contract selects one Bash function and one owner module;
# the function then runs in a clean child environment with bounded time/output.
# =============================================================================

# jq programs and the fixed child script intentionally stay single-quoted so
# this shell cannot expand adapter-controlled values into executable text.
# shellcheck disable=SC2016

[[ -n "${_MAINFRAME_INVOKE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_INVOKE_LOADED=1

readonly _MAINFRAME_INVOKE_INPUT_LIMIT=32768
readonly _MAINFRAME_INVOKE_MAX_TIMEOUT_MS=30000
readonly _MAINFRAME_INVOKE_MAX_OUTPUT_LIMIT=1048576
readonly _MAINFRAME_INVOKE_CONTRACT_COUNT=26

if [[ -x /usr/bin/stat ]]; then
    _MAINFRAME_INVOKE_STAT=/usr/bin/stat
elif [[ -x /bin/stat ]]; then
    _MAINFRAME_INVOKE_STAT=/bin/stat
else
    _MAINFRAME_INVOKE_STAT=""
fi
if [[ -x /usr/bin/uname ]]; then
    _MAINFRAME_INVOKE_UNAME=/usr/bin/uname
elif [[ -x /bin/uname ]]; then
    _MAINFRAME_INVOKE_UNAME=/bin/uname
else
    _MAINFRAME_INVOKE_UNAME=""
fi
if [[ -n "$_MAINFRAME_INVOKE_UNAME" ]]; then
    _MAINFRAME_INVOKE_KERNEL="$("$_MAINFRAME_INVOKE_UNAME" -s 2>/dev/null || true)"
else
    _MAINFRAME_INVOKE_KERNEL=""
fi
readonly _MAINFRAME_INVOKE_STAT _MAINFRAME_INVOKE_UNAME
readonly _MAINFRAME_INVOKE_KERNEL

_MAINFRAME_INVOKE_ACTIVE_PID=""
_MAINFRAME_INVOKE_INPUT_B64=""
_MAINFRAME_INVOKE_RUN_STDOUT_READ_FD=""
_MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD=""
_MAINFRAME_INVOKE_RUN_STDERR_READ_FD=""
_MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD=""

_mainframe_invoke_group_exists() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 && "$pid" -ne $$ ]] || return 1
    kill -0 -- "-$pid" 2>/dev/null
}

_mainframe_invoke_kill_group() {
    local pid="${1:-}" attempt=0
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 && "$pid" -ne $$ ]] || return 0

    if _mainframe_invoke_group_exists "$pid"; then
        kill -TERM -- "-$pid" 2>/dev/null || true
        while (( attempt < 10 )); do
            _mainframe_invoke_group_exists "$pid" || break
            /bin/sleep 0.02
            attempt=$((attempt + 1))
        done
        _mainframe_invoke_group_exists "$pid" && \
            kill -KILL -- "-$pid" 2>/dev/null || true
    else
        kill -TERM "$pid" 2>/dev/null || true
        /bin/sleep 0.02
        kill -KILL "$pid" 2>/dev/null || true
    fi
}

_mainframe_invoke_cleanup_files() {
    local fd variable

    for variable in \
        _MAINFRAME_INVOKE_RUN_STDOUT_READ_FD \
        _MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD \
        _MAINFRAME_INVOKE_RUN_STDERR_READ_FD \
        _MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD; do
        fd="${!variable:-}"
        if [[ "$fd" =~ ^[0-9]+$ ]]; then
            exec {fd}>&- 2>/dev/null || true
        fi
        printf -v "$variable" '%s' ""
    done
    _MAINFRAME_INVOKE_INPUT_B64=""
}

_mainframe_invoke_cleanup_active() {
    local pid="${_MAINFRAME_INVOKE_ACTIVE_PID:-}"
    if [[ -n "$pid" ]]; then
        _mainframe_invoke_kill_group "$pid"
        wait "$pid" 2>/dev/null || true
        _MAINFRAME_INVOKE_ACTIVE_PID=""
    fi
}

_mainframe_invoke_cleanup_on_exit() {
    local exit_code="$1"
    trap - EXIT HUP INT TERM
    set +e
    _mainframe_invoke_cleanup_active
    _mainframe_invoke_cleanup_files
    exit "$exit_code"
}

_mainframe_invoke_cleanup_on_signal() {
    local exit_code="$1"
    trap - EXIT HUP INT TERM
    set +e
    _mainframe_invoke_cleanup_active
    _mainframe_invoke_cleanup_files
    exit "$exit_code"
}

_mainframe_invoke_install_cleanup_traps() {
    trap '_mainframe_invoke_cleanup_on_exit "$?"' EXIT
    trap '_mainframe_invoke_cleanup_on_signal 129' HUP
    trap '_mainframe_invoke_cleanup_on_signal 130' INT
    trap '_mainframe_invoke_cleanup_on_signal 143' TERM
}

_mainframe_invoke_usage() {
    /bin/cat <<'EOF'
Usage:
  mainframe invoke <canonical-id> --input-json '<object>'
  mainframe invoke <canonical-id> --input-json -

The current production broker accepts only reviewed stable-core canonical IDs.
Input is a closed JSON object described by MANIFEST.json. Unknown IDs, Bash
names, executable names, undeclared fields, and unreviewed effects fail closed.

Adapter options:
  --profile stable-core          Required profile (default: stable-core)
  --format raw|broker-json-v1    Raw function output or a versioned envelope
  --caller NAME                  Audit-only adapter label (default: cli)
EOF
}

_mainframe_invoke_error_text() {
    printf 'MAINFRAME invocation denied: %s\n' "$1" >&2
}

_mainframe_invoke_path_is_canonical() {
    local candidate="$1" component
    local -a components=()

    [[ "$candidate" == /* && "$candidate" != */ &&
       "$candidate" != *$'\n'* && "$candidate" != *$'\r'* &&
       "$candidate" != *$'\t'* ]] || return 1
    IFS='/' read -r -a components <<<"$candidate"
    for component in "${components[@]}"; do
        case "$component" in
            '') ;;
            .|..) return 1 ;;
        esac
    done
}

_mainframe_invoke_path_is_exact() {
    local path="$1" parent canonical_parent

    _mainframe_invoke_path_is_canonical "$path" || return 1
    parent="${path%/*}"
    [[ -n "$parent" ]] || parent=/
    canonical_parent="$(
        builtin cd -- "$parent" 2>/dev/null && builtin pwd -P
    )" || return 1
    [[ "$path" == "${canonical_parent%/}/${path##*/}" ]]
}

_mainframe_invoke_dir_is_safe() {
    local directory="$1" cursor="/" component target
    local -a components=()

    [[ "$directory" == /* ]] || return 1
    IFS='/' read -r -a components <<<"$directory"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        cursor="${cursor%/}/$component"
        if [[ -e "$cursor" || -L "$cursor" ]]; then
            if [[ -L "$cursor" ]]; then
                target="$(/usr/bin/readlink "$cursor" 2>/dev/null)" || return 1
                case "$cursor:$target" in
                    /tmp:private/tmp|/var:private/var) continue ;;
                    *) return 1 ;;
                esac
            fi
            [[ -d "$cursor" ]] || return 1
        fi
    done
}

_mainframe_invoke_stat_mode() {
    local result owner mode
    result="$(_mainframe_invoke_stat_owner_mode "$1")" || return 1
    read -r owner mode <<<"$result"
    printf '%s\n' "$mode"
}

_mainframe_invoke_stat_owner_mode() {
    local path="$1" result owner mode

    [[ -n "$_MAINFRAME_INVOKE_STAT" ]] || return 1
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin)
            result="$("$_MAINFRAME_INVOKE_STAT" -f '%u %Mp%Lp' \
                "$path" 2>/dev/null)" || return 1
            ;;
        Linux)
            result="$("$_MAINFRAME_INVOKE_STAT" -c '%u %a' \
                "$path" 2>/dev/null)" || return 1
            ;;
        *) return 1 ;;
    esac
    [[ "$result" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<<"$result"
    if [[ ${#mode} -eq 4 && "$mode" == 0* ]]; then
        mode="${mode#0}"
    fi
    printf '%s %s\n' "$owner" "$mode"
}

_mainframe_invoke_stat_links() {
    [[ -n "$_MAINFRAME_INVOKE_STAT" ]] || return 1
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin) "$_MAINFRAME_INVOKE_STAT" -f '%l' "$1" 2>/dev/null ;;
        Linux) "$_MAINFRAME_INVOKE_STAT" -c '%h' "$1" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

_mainframe_invoke_stat_identity() {
    [[ -n "$_MAINFRAME_INVOKE_STAT" ]] || return 1
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin) "$_MAINFRAME_INVOKE_STAT" -f '%i' "$1" 2>/dev/null ;;
        Linux) "$_MAINFRAME_INVOKE_STAT" -L -c '%d:%i' "$1" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

_mainframe_invoke_trust_file_is_safe() {
    local path="$1" owner mode numeric

    _mainframe_invoke_path_is_exact "$path" || return 1
    [[ -f "$path" && ! -L "$path" && -r "$path" ]] || return 1
    read -r owner mode < <(_mainframe_invoke_stat_owner_mode "$path") || return 1
    [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 ))
}

_mainframe_invoke_dir_permissions_are_safe() {
    local directory="$1" mode
    mode="$(_mainframe_invoke_stat_mode "$directory")" || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 0022) == 0 ))
}

_mainframe_invoke_file_has_one_link() {
    local links
    links="$(_mainframe_invoke_stat_links "$1")" || return 1
    [[ "$links" == 1 ]]
}

_mainframe_invoke_audit_target_is_current() {
    local path_identity fd_identity
    [[ -f "$_MAINFRAME_INVOKE_AUDIT_LOG" &&
       ! -L "$_MAINFRAME_INVOKE_AUDIT_LOG" &&
       -O "$_MAINFRAME_INVOKE_AUDIT_LOG" ]] || return 1
    _mainframe_invoke_file_has_one_link "$_MAINFRAME_INVOKE_AUDIT_LOG" || return 1
    path_identity="$(_mainframe_invoke_stat_identity \
        "$_MAINFRAME_INVOKE_AUDIT_LOG")" || return 1
    fd_identity="$(_mainframe_invoke_stat_identity \
        "/dev/fd/$_MAINFRAME_INVOKE_AUDIT_FD")" || return 1
    [[ -n "$path_identity" && "$path_identity" == "$fd_identity" ]]
}

_mainframe_invoke_open_audit() {
    local audit_dir mode

    if [[ -n "${MAINFRAME_INVOKE_AUDIT_LOG:-}" ]]; then
        _MAINFRAME_INVOKE_AUDIT_LOG="$MAINFRAME_INVOKE_AUDIT_LOG"
    elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
        _MAINFRAME_INVOKE_AUDIT_LOG="$XDG_STATE_HOME/mainframe/invocations.jsonl"
    elif [[ -n "${HOME:-}" ]]; then
        _MAINFRAME_INVOKE_AUDIT_LOG="$HOME/.local/state/mainframe/invocations.jsonl"
    else
        _MAINFRAME_INVOKE_AUDIT_LOG="/tmp/mainframe-${UID:-user}/invocations.jsonl"
    fi

    _mainframe_invoke_path_is_canonical "$_MAINFRAME_INVOKE_AUDIT_LOG" || return 1
    audit_dir="${_MAINFRAME_INVOKE_AUDIT_LOG%/*}"
    [[ -n "$audit_dir" ]] || audit_dir=/
    _mainframe_invoke_dir_is_safe "$audit_dir" || return 1
    [[ ! -L "$_MAINFRAME_INVOKE_AUDIT_LOG" ]] || return 1

    umask 077
    /bin/mkdir -p "$audit_dir" 2>/dev/null || return 1
    _mainframe_invoke_dir_is_safe "$audit_dir" || return 1
    [[ -d "$audit_dir" && -O "$audit_dir" ]] || return 1
    _mainframe_invoke_dir_permissions_are_safe "$audit_dir" || return 1

    if [[ -e "$_MAINFRAME_INVOKE_AUDIT_LOG" ]]; then
        [[ -f "$_MAINFRAME_INVOKE_AUDIT_LOG" &&
           ! -L "$_MAINFRAME_INVOKE_AUDIT_LOG" &&
           -O "$_MAINFRAME_INVOKE_AUDIT_LOG" ]] || return 1
        _mainframe_invoke_file_has_one_link "$_MAINFRAME_INVOKE_AUDIT_LOG" || return 1
    fi
    : >>"$_MAINFRAME_INVOKE_AUDIT_LOG" 2>/dev/null || return 1
    _mainframe_invoke_file_has_one_link "$_MAINFRAME_INVOKE_AUDIT_LOG" || return 1
    /bin/chmod 600 "$_MAINFRAME_INVOKE_AUDIT_LOG" 2>/dev/null || return 1
    exec {_MAINFRAME_INVOKE_AUDIT_FD}>>"$_MAINFRAME_INVOKE_AUDIT_LOG" || return 1
    _mainframe_invoke_audit_target_is_current || return 1

    readonly _MAINFRAME_INVOKE_AUDIT_LOG _MAINFRAME_INVOKE_AUDIT_FD
}

_mainframe_invoke_audit() {
    local status="$1" exit_code="$2" duration_ms="$3"
    local timed_out="$4" output_exceeded="$5" message="${6:-}"
    local record

    _mainframe_invoke_audit_target_is_current || return 1
    record="$("$_MAINFRAME_INVOKE_JQ" -cn \
        --arg audit_id "$_MAINFRAME_INVOKE_AUDIT_ID" \
        --arg canonical_id "${_MAINFRAME_INVOKE_CANONICAL_ID:-}" \
        --arg caller "$_MAINFRAME_INVOKE_CALLER" \
        --arg profile "$_MAINFRAME_INVOKE_PROFILE" \
        --arg status "$status" \
        --arg message "$message" \
        --argjson exit_code "$exit_code" \
        --argjson duration_ms "$duration_ms" \
        --argjson input_bytes "${_MAINFRAME_INVOKE_INPUT_BYTES:-0}" \
        --argjson timed_out "$timed_out" \
        --argjson output_exceeded "$output_exceeded" \
        '{schema_version:1,kind:"mainframe-invocation",audit_id:$audit_id,
          timestamp:(now|todateiso8601),canonical_id:$canonical_id,
          caller:$caller,profile:$profile,status:$status,exit_code:$exit_code,
          duration_ms:$duration_ms,input_bytes:$input_bytes,
          timed_out:$timed_out,output_exceeded:$output_exceeded,
          message:(if $message == "" then null else $message end)}')" || return 1
    printf '%s\n' "$record" >&"$_MAINFRAME_INVOKE_AUDIT_FD" || return 1
    _mainframe_invoke_audit_target_is_current
}

_mainframe_invoke_base64_fd() {
    local fd="$1"
    [[ "$fd" =~ ^[0-9]+$ ]] || return 1
    /usr/bin/base64 <&"$fd" | /usr/bin/tr -d '\n'
}

_mainframe_invoke_emit_envelope() {
    local ok="$1" status="$2" exit_code="$3" timed_out="$4"
    local output_exceeded="$5" duration_ms="$6" stdout_fd="$7"
    local stderr_fd="$8" message="${9:-}"

    # Keep the potentially 1 MiB captures off argv and out of shell variables.
    # jq reads their canonical base64 encodings from inherited anonymous FDs.
    "$_MAINFRAME_INVOKE_JQ" -cn \
        --rawfile stdout_b64 <(
            [[ -z "$stdout_fd" ]] || _mainframe_invoke_base64_fd "$stdout_fd"
        ) \
        --rawfile stderr_b64 <(
            [[ -z "$stderr_fd" ]] || _mainframe_invoke_base64_fd "$stderr_fd"
        ) \
        --argjson ok "$ok" \
        --arg status "$status" \
        --arg canonical_id "${_MAINFRAME_INVOKE_CANONICAL_ID:-}" \
        --arg name "${_MAINFRAME_INVOKE_NAME:-}" \
        --arg owner "${_MAINFRAME_INVOKE_OWNER:-}" \
        --arg audit_id "$_MAINFRAME_INVOKE_AUDIT_ID" \
        --arg message "$message" \
        --argjson exit_code "$exit_code" \
        --argjson timed_out "$timed_out" \
        --argjson output_exceeded "$output_exceeded" \
        --argjson duration_ms "$duration_ms" \
        '{schema_version:1,ok:$ok,status:$status,canonical_id:$canonical_id,
          name:(if $name == "" then null else $name end),
          owner:(if $owner == "" then null else $owner end),
          exit_code:$exit_code,timed_out:$timed_out,
          output_exceeded:$output_exceeded,duration_ms:$duration_ms,
          audit_id:$audit_id,stdout_b64:$stdout_b64,stderr_b64:$stderr_b64,
          error:(if $message == "" then null else $message end)}'
}

_mainframe_invoke_fail() {
    local exit_code="$1" status="$2" message="$3"

    if ! _mainframe_invoke_audit "$status" "$exit_code" 0 false false "$message"; then
        status="audit_error"
        message="the invocation audit trail became unavailable"
        exit_code=74
    fi
    if [[ "$_MAINFRAME_INVOKE_FORMAT" == "broker-json-v1" ]]; then
        _mainframe_invoke_emit_envelope false "$status" "$exit_code" \
            false false 0 "" "" "$message"
    else
        _mainframe_invoke_error_text "$message"
    fi
    return "$exit_code"
}

_mainframe_invoke_platform() {
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin) printf 'macos\n' ;;
        Linux) printf 'linux\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_invoke_read_version() {
    local version_file="$1" version

    _mainframe_invoke_path_is_exact "$version_file" || return 1
    [[ -f "$version_file" && ! -L "$version_file" &&
       -r "$version_file" ]] || return 1
    version="$("$_MAINFRAME_INVOKE_JQ" -Rse -r '
        . as $raw |
        (if ($raw | endswith("\n")) then $raw[0:-1] else $raw end) as $value |
        if (($value | contains("\n") | not) and
            ($value | contains("\r") | not) and
            ($value | test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)([-+][A-Za-z0-9.-]+)?$")))
        then $value
        else error("malformed VERSION") end
    ' "$version_file" 2>/dev/null)" || return 1
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

_mainframe_invoke_read_stdin() {
    local dd_path=/bin/dd captured
    [[ -x "$dd_path" ]] || dd_path=/usr/bin/dd
    [[ -x "$dd_path" ]] || return 1
    # Base64 is safe in a Bash variable and preserves every caller byte,
    # including trailing newlines and raw NULs that jq must reject.  Raw input
    # travels only through pipes; SIGKILL cannot strand a secret pathname.
    captured="$(
        set -o pipefail
        "$dd_path" bs=1 count=$((_MAINFRAME_INVOKE_INPUT_LIMIT + 1)) 2>/dev/null |
            /usr/bin/base64 | /usr/bin/tr -d '\n'
    )" || return 1
    [[ "$captured" =~ ^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$ ]] || return 1
    _MAINFRAME_INVOKE_INPUT_B64="$captured"
}

_mainframe_invoke_base64_decode() {
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin) /usr/bin/base64 -D ;;
        Linux) /usr/bin/base64 -d ;;
        *) return 1 ;;
    esac
}

_mainframe_invoke_prepare_input() {
    local input_source="$1"

    if [[ "$input_source" == - ]]; then
        _mainframe_invoke_read_stdin || return 1
    else
        _MAINFRAME_INVOKE_INPUT_B64="$(printf '%s' "$input_source" | \
            /usr/bin/base64 | /usr/bin/tr -d '\n')" || return 1
    fi

    _MAINFRAME_INVOKE_INPUT_BYTES="$(printf '%s' "$_MAINFRAME_INVOKE_INPUT_B64" | \
        _mainframe_invoke_base64_decode | LC_ALL=C /usr/bin/wc -c | \
        /usr/bin/tr -d '[:space:]')" || return 1
    [[ "$_MAINFRAME_INVOKE_INPUT_BYTES" =~ ^[0-9]+$ ]]
}

_mainframe_invoke_jq_input() {
    printf '%s' "$_MAINFRAME_INVOKE_INPUT_B64" | \
        _mainframe_invoke_base64_decode | "$_MAINFRAME_INVOKE_JQ" "$@"
}

_mainframe_invoke_input_has_unique_fields() {
    # jq's normal object parser intentionally keeps the last duplicate key.
    # The streaming form exposes each occurrence before reduction. Because the
    # reviewed schema permits only top-level strings and string arrays, one
    # scalar event or array index zero uniquely marks each property occurrence.
    _mainframe_invoke_jq_input -e --stream '
        reduce inputs as $event ({};
          if (($event | length) == 2 and
              ($event[0] | type) == "array" and
              ($event[0] | length) >= 1 and
              ((($event[0] | length) == 1) or
               $event[0][1] == 0 or
               (($event[0][1] | type) == "string")))
          then
            .[($event[0][0] | tojson)] =
              ((.[($event[0][0] | tojson)] // 0) + 1)
          else . end)
        | all(.[]; . == 1)
    ' >/dev/null 2>&1
}

_mainframe_invoke_extract_argv() {
    local shape_count index field mode property_type value value_count value_index
    local value_source
    local omitted_scalar=false
    _MAINFRAME_INVOKE_ARGV=()

    shape_count="$("$_MAINFRAME_INVOKE_JQ" -r '.call_shape.arguments | length' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")" || return 1
    [[ "$shape_count" =~ ^[0-9]+$ ]] || return 1

    for ((index=0; index<shape_count; index++)); do
        field="$("$_MAINFRAME_INVOKE_JQ" -r \
            --argjson index "$index" '.call_shape.arguments[$index].field' \
            <<<"$_MAINFRAME_INVOKE_EXPORT")" || return 1
        mode="$("$_MAINFRAME_INVOKE_JQ" -r \
            --argjson index "$index" '.call_shape.arguments[$index].mode' \
            <<<"$_MAINFRAME_INVOKE_EXPORT")" || return 1
        property_type="$("$_MAINFRAME_INVOKE_JQ" -r --arg field "$field" \
            '.input_schema.properties[$field].type' \
            <<<"$_MAINFRAME_INVOKE_EXPORT")" || return 1

        if _mainframe_invoke_jq_input -e --arg field "$field" \
            'has($field)' >/dev/null; then
            value_source=input
        elif "$_MAINFRAME_INVOKE_JQ" -e --arg field "$field" \
            '.input_schema.properties[$field] | has("default")' \
            >/dev/null <<<"$_MAINFRAME_INVOKE_EXPORT"; then
            value_source=default
        else
            if [[ "$mode" == "scalar" ]]; then
                omitted_scalar=true
            fi
            continue
        fi

        if [[ "$omitted_scalar" == "true" ]]; then
            return 2
        fi

        case "$mode:$property_type" in
            scalar:string)
                if [[ "$value_source" == input ]]; then
                    IFS= read -r -d '' value < <(
                        _mainframe_invoke_jq_input -j --arg field "$field" \
                            '.[$field], "\u0000"'
                    ) || return 1
                else
                    IFS= read -r -d '' value < <(
                        "$_MAINFRAME_INVOKE_JQ" -j --arg field "$field" \
                            '.input_schema.properties[$field].default, "\u0000"' \
                            <<<"$_MAINFRAME_INVOKE_EXPORT"
                    ) || return 1
                fi
                _MAINFRAME_INVOKE_ARGV+=("$value")
                ;;
            spread:array)
                if [[ "$value_source" == input ]]; then
                    value_count="$(_mainframe_invoke_jq_input -r --arg field "$field" \
                        '.[$field] | length')" || return 1
                else
                    value_count="$("$_MAINFRAME_INVOKE_JQ" -r --arg field "$field" \
                        '.input_schema.properties[$field].default | length' \
                        <<<"$_MAINFRAME_INVOKE_EXPORT")" || return 1
                fi
                [[ "$value_count" =~ ^[0-9]+$ ]] || return 1
                for ((value_index=0; value_index<value_count; value_index++)); do
                    if [[ "$value_source" == input ]]; then
                        IFS= read -r -d '' value < <(
                            _mainframe_invoke_jq_input -j --arg field "$field" \
                                --argjson index "$value_index" \
                                '.[$field][$index], "\u0000"'
                        ) || return 1
                    else
                        IFS= read -r -d '' value < <(
                            "$_MAINFRAME_INVOKE_JQ" -j --arg field "$field" \
                                --argjson index "$value_index" \
                                '.input_schema.properties[$field].default[$index], "\u0000"' \
                                <<<"$_MAINFRAME_INVOKE_EXPORT"
                        ) || return 1
                    fi
                    _MAINFRAME_INVOKE_ARGV+=("$value")
                done
                ;;
            *) return 1 ;;
        esac
    done
}

# Create a regular capture object so the kernel file-size limit remains
# available, but unlink its only pathname before any function output can be
# written. Separate read/write opens keep the reader at offset zero for exact
# raw/base64 rendering after the child exits.
_mainframe_invoke_open_capture() {
    local read_variable="$1" write_variable="$2"
    local path read_fd write_fd

    path="$(/usr/bin/mktemp \
        "${TMPDIR:-/tmp}/mainframe-invoke-capture.XXXXXX")" || return 1
    /bin/chmod 600 "$path" || {
        /bin/rm -f -- "$path" 2>/dev/null || true
        return 1
    }
    exec {read_fd}<"$path" || {
        /bin/rm -f -- "$path" 2>/dev/null || true
        return 1
    }
    exec {write_fd}>"$path" || {
        exec {read_fd}<&- 2>/dev/null || true
        /bin/rm -f -- "$path" 2>/dev/null || true
        return 1
    }
    /bin/rm -f -- "$path" 2>/dev/null || {
        exec {read_fd}<&- 2>/dev/null || true
        exec {write_fd}>&- 2>/dev/null || true
        return 1
    }
    printf -v "$read_variable" '%s' "$read_fd"
    printf -v "$write_variable" '%s' "$write_fd"
}

_mainframe_invoke_close_capture_fd() {
    local variable="$1" fd="${!1:-}"
    if [[ "$fd" =~ ^[0-9]+$ ]]; then
        exec {fd}>&- 2>/dev/null || return 1
    fi
    printf -v "$variable" '%s' ""
}

_mainframe_invoke_capture_size() {
    local fd="$1" size
    [[ "$fd" =~ ^[0-9]+$ ]] || return 1
    case "$_MAINFRAME_INVOKE_KERNEL" in
        Darwin)
            size="$("$_MAINFRAME_INVOKE_STAT" -f '%z' "/dev/fd/$fd" 2>/dev/null)" || return 1
            ;;
        Linux)
            # /proc/self/fd entries are symlinks. GNU stat does not
            # dereference them by default, so without -L an empty capture is
            # misreported as the non-zero length of its link target.
            size="$("$_MAINFRAME_INVOKE_STAT" -L -c '%s' "/proc/self/fd/$fd" 2>/dev/null)" || return 1
            ;;
        *) return 1 ;;
    esac
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$size"
}

_mainframe_invoke_replace_capture_text() {
    local stream="$1" text="$2" read_variable write_variable old_fd new_write
    case "$stream" in
        stdout)
            read_variable=_MAINFRAME_INVOKE_RUN_STDOUT_READ_FD
            write_variable=_MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD
            ;;
        stderr)
            read_variable=_MAINFRAME_INVOKE_RUN_STDERR_READ_FD
            write_variable=_MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD
            ;;
        *) return 1 ;;
    esac
    old_fd="${!read_variable:-}"
    if [[ "$old_fd" =~ ^[0-9]+$ ]]; then
        exec {old_fd}<&- 2>/dev/null || return 1
    fi
    printf -v "$read_variable" '%s' ""
    _mainframe_invoke_open_capture "$read_variable" "$write_variable" || return 1
    new_write="${!write_variable}"
    printf '%s' "$text" >&"$new_write" || return 1
    _mainframe_invoke_close_capture_fd "$write_variable"
}

_mainframe_invoke_run() {
    local module_file="$1" timeout_ms="$2" output_limit="$3"
    local child_pid start_seconds deadline_seconds stdout_read stdout_write
    local stderr_read stderr_write
    local stdout_bytes stderr_bytes combined_bytes exit_code=0
    local timed_out=false output_exceeded=false restore_errexit=false
    local descendant_survived=false result_mismatch=false
    local child_script

    [[ "$module_file" == "lib/${_MAINFRAME_INVOKE_OWNER}.sh" ]] || return 70

    _mainframe_invoke_open_capture \
        _MAINFRAME_INVOKE_RUN_STDOUT_READ_FD \
        _MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD || return 70
    _mainframe_invoke_open_capture \
        _MAINFRAME_INVOKE_RUN_STDERR_READ_FD \
        _MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD || return 70
    stdout_read="$_MAINFRAME_INVOKE_RUN_STDOUT_READ_FD"
    stdout_write="$_MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD"
    stderr_read="$_MAINFRAME_INVOKE_RUN_STDERR_READ_FD"
    stderr_write="$_MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD"

    child_script='
mainframe_root=$1
mainframe_function=$2
mainframe_jq=$3
mainframe_file_blocks=$4
shift 4
function jq {
    "$mainframe_jq" "$@"
}
# A flooding Bash builtin receives SIGXFSZ in this shell. Convert that signal
# to the documented status so the supervisor cannot leak a job notification
# outside broker-json-v1.
if ! trap "exit 153" XFSZ; then
    printf "invocation denied: output signal handler could not be installed\n" >&2
    exit 126
fi
if ! ulimit -f "$mainframe_file_blocks"; then
    printf "invocation denied: output resource limit could not be installed\n" >&2
    exit 126
fi
if ! source "$mainframe_root/lib/common.sh"; then
    printf "invocation denied: MAINFRAME initialization failed\n" >&2
    exit 126
fi
if ! declare -F -- "$mainframe_function" >/dev/null 2>&1; then
    printf "invocation denied: canonical function is not declared\n" >&2
    exit 126
fi
"$mainframe_function" "$@"
'

    local file_limit_blocks=$(((output_limit + 511) / 512))
    start_seconds=$SECONDS
    deadline_seconds=$((start_seconds + ((timeout_ms + 999) / 1000)))

    # Job control gives the child its own process group on both supported
    # platforms, allowing timeout/output denial to terminate descendants too.
    set -m
    /usr/bin/env -i \
        HOME="${HOME:-}" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-}" \
        TMPDIR="${TMPDIR:-/tmp}" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        LC_ALL=C \
        NO_COLOR=1 \
        TERM=dumb \
        MAINFRAME_ROOT="$MAINFRAME_ROOT" \
        MAINFRAME_CONFIG=/dev/null \
        MAINFRAME_LIBS="core,${_MAINFRAME_INVOKE_OWNER}" \
        MAINFRAME_OUTPUT=json \
        MAINFRAME_CANONICAL_INVOKE=1 \
        "$BASH" --noprofile --norc -p -c "$child_script" \
        mainframe-invoke "$MAINFRAME_ROOT" "$_MAINFRAME_INVOKE_NAME" \
        "$_MAINFRAME_INVOKE_JQ" \
        "$file_limit_blocks" \
        "${_MAINFRAME_INVOKE_ARGV[@]}" \
        1>&"$stdout_write" 2>&"$stderr_write" &
    child_pid=$!
    _MAINFRAME_INVOKE_ACTIVE_PID="$child_pid"
    set +m
    # Only the child retains the writers. The anonymous readers remain at
    # offset zero in this supervisor for exact final rendering.
    _mainframe_invoke_close_capture_fd \
        _MAINFRAME_INVOKE_RUN_STDOUT_WRITE_FD || return 70
    _mainframe_invoke_close_capture_fd \
        _MAINFRAME_INVOKE_RUN_STDERR_WRITE_FD || return 70

    while kill -0 "$child_pid" 2>/dev/null; do
        stdout_bytes="$(_mainframe_invoke_capture_size "$stdout_read")" || return 70
        stderr_bytes="$(_mainframe_invoke_capture_size "$stderr_read")" || return 70
        combined_bytes=$((stdout_bytes + stderr_bytes))
        if (( combined_bytes > output_limit )); then
            output_exceeded=true
            _mainframe_invoke_kill_group "$child_pid"
            break
        fi
        if (( SECONDS >= deadline_seconds )); then
            timed_out=true
            _mainframe_invoke_kill_group "$child_pid"
            break
        fi
        /bin/sleep 0.05
    done

    [[ $- != *e* ]] || { restore_errexit=true; set +e; }
    wait "$child_pid" 2>/dev/null
    exit_code=$?
    [[ "$restore_errexit" != "true" ]] || set -e

    if _mainframe_invoke_group_exists "$child_pid"; then
        descendant_survived=true
        _mainframe_invoke_kill_group "$child_pid"
    fi
    _MAINFRAME_INVOKE_ACTIVE_PID=""

    stdout_bytes="$(_mainframe_invoke_capture_size "$stdout_read")" || return 70
    stderr_bytes="$(_mainframe_invoke_capture_size "$stderr_read")" || return 70
    combined_bytes=$((stdout_bytes + stderr_bytes))
    (( combined_bytes <= output_limit )) || output_exceeded=true
    # SIGXFSZ is 25 on supported macOS/Linux hosts. The protected child exits
    # as 128+signal when the kernel-enforced file bound fires before polling.
    (( exit_code != 153 )) || output_exceeded=true
    if (( stdout_bytes > 0 )) &&
       [[ "$_MAINFRAME_INVOKE_RESULT_KIND" != stdout ]]; then
        result_mismatch=true
    fi

    if [[ "$timed_out" == "true" ]]; then
        exit_code=124
        _MAINFRAME_INVOKE_RUN_STATUS=timeout
    elif [[ "$output_exceeded" == "true" ]]; then
        exit_code=74
        _MAINFRAME_INVOKE_RUN_STATUS=output_limit
        _mainframe_invoke_replace_capture_text stdout "" || return 70
        _mainframe_invoke_replace_capture_text stderr \
            "$(printf 'invocation output exceeded the reviewed %s-byte limit\n' \
                "$output_limit")"$'\n' || return 70
    elif [[ "$descendant_survived" == "true" ]]; then
        exit_code=70
        _MAINFRAME_INVOKE_RUN_STATUS=broker_error
        _mainframe_invoke_replace_capture_text stdout "" || return 70
        _mainframe_invoke_replace_capture_text stderr \
            $'invocation denied: function left a descendant process running\n' || return 70
    elif [[ "$result_mismatch" == "true" ]]; then
        exit_code=70
        _MAINFRAME_INVOKE_RUN_STATUS=broker_error
        _mainframe_invoke_replace_capture_text stdout "" || return 70
        _mainframe_invoke_replace_capture_text stderr \
            $'invocation denied: stdout contradicts the reviewed result contract\n' || return 70
    elif (( exit_code == 0 )); then
        _MAINFRAME_INVOKE_RUN_STATUS=success
    else
        _MAINFRAME_INVOKE_RUN_STATUS=function_error
    fi

    _MAINFRAME_INVOKE_RUN_EXIT_CODE=$exit_code
    _MAINFRAME_INVOKE_RUN_TIMED_OUT=$timed_out
    _MAINFRAME_INVOKE_RUN_OUTPUT_EXCEEDED=$output_exceeded
    _MAINFRAME_INVOKE_RUN_DURATION_MS=$(((SECONDS - start_seconds) * 1000))
    return 0
}

_mainframe_invoke_main() {
    local input_source="" canonical_id="${1:-}"
    local invocation_index="$MAINFRAME_ROOT/INVOCATION_INDEX.json"
    local version_file="$MAINFRAME_ROOT/VERSION"
    local common_file="$MAINFRAME_ROOT/lib/common.sh"
    local platform module_file release_version
    local timeout_ms output_limit extract_status

    _MAINFRAME_INVOKE_PROFILE=stable-core
    _MAINFRAME_INVOKE_FORMAT=raw
    _MAINFRAME_INVOKE_CALLER=cli
    _MAINFRAME_INVOKE_CANONICAL_ID="$canonical_id"
    _MAINFRAME_INVOKE_NAME=""
    _MAINFRAME_INVOKE_OWNER=""
    _MAINFRAME_INVOKE_RESULT_KIND=""
    _MAINFRAME_INVOKE_INPUT_BYTES=0

    case "$canonical_id" in
        -h|--help|'')
            _mainframe_invoke_usage
            [[ -n "$canonical_id" ]] && return 0 || return 64
            ;;
    esac
    shift

    while (( $# > 0 )); do
        case "$1" in
            --input-json)
                (( $# >= 2 )) || { _mainframe_invoke_usage >&2; return 64; }
                [[ -z "$input_source" ]] || { _mainframe_invoke_usage >&2; return 64; }
                input_source="$2"
                shift 2
                ;;
            --input-json=*)
                [[ -z "$input_source" ]] || { _mainframe_invoke_usage >&2; return 64; }
                input_source="${1#*=}"
                shift
                ;;
            --profile)
                (( $# >= 2 )) || { _mainframe_invoke_usage >&2; return 64; }
                _MAINFRAME_INVOKE_PROFILE="$2"
                shift 2
                ;;
            --profile=*)
                _MAINFRAME_INVOKE_PROFILE="${1#*=}"
                shift
                ;;
            --format)
                (( $# >= 2 )) || { _mainframe_invoke_usage >&2; return 64; }
                _MAINFRAME_INVOKE_FORMAT="$2"
                shift 2
                ;;
            --format=*)
                _MAINFRAME_INVOKE_FORMAT="${1#*=}"
                shift
                ;;
            --caller)
                (( $# >= 2 )) || { _mainframe_invoke_usage >&2; return 64; }
                _MAINFRAME_INVOKE_CALLER="$2"
                shift 2
                ;;
            --caller=*)
                _MAINFRAME_INVOKE_CALLER="${1#*=}"
                shift
                ;;
            -h|--help)
                _mainframe_invoke_usage
                return 0
                ;;
            *)
                _mainframe_invoke_usage >&2
                return 64
                ;;
        esac
    done

    case "$_MAINFRAME_INVOKE_FORMAT" in raw|broker-json-v1) ;; *) return 64 ;; esac
    [[ "$_MAINFRAME_INVOKE_PROFILE" == stable-core ]] || return 64
    [[ "$_MAINFRAME_INVOKE_CALLER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || return 64
    [[ -n "$input_source" ]] || { _mainframe_invoke_usage >&2; return 64; }
    _mainframe_invoke_install_cleanup_traps

    _MAINFRAME_INVOKE_JQ="${_MAINFRAME_CLI_JQ:-}"
    if [[ "$_MAINFRAME_INVOKE_JQ" != /* || ! -f "$_MAINFRAME_INVOKE_JQ" ||
          -L "$_MAINFRAME_INVOKE_JQ" || ! -x "$_MAINFRAME_INVOKE_JQ" ]]; then
        _mainframe_invoke_error_text "the trusted jq binding is unavailable"
        return 69
    fi
    readonly _MAINFRAME_INVOKE_JQ

    _MAINFRAME_INVOKE_AUDIT_ID="inv-$(/bin/date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null)-$$-$RANDOM"
    readonly _MAINFRAME_INVOKE_AUDIT_ID
    if ! _mainframe_invoke_open_audit; then
        _mainframe_invoke_error_text "a private append-only audit trail is unavailable"
        return 74
    fi

    if ! _mainframe_invoke_prepare_input "$input_source"; then
        _mainframe_invoke_fail 65 invalid_input "could not read the JSON request"
        return $?
    fi
    if (( _MAINFRAME_INVOKE_INPUT_BYTES > _MAINFRAME_INVOKE_INPUT_LIMIT )); then
        _mainframe_invoke_fail 65 invalid_input "JSON request exceeds 32768 bytes"
        return $?
    fi
    if ! _mainframe_invoke_input_has_unique_fields; then
        _mainframe_invoke_fail 65 invalid_input \
            "JSON request contains duplicate or unsupported object fields"
        return $?
    fi

    if [[ ! "$canonical_id" =~ ^mf:[a-z][a-z0-9-]*:[a-zA-Z0-9_-]+:[a-z_][a-z0-9_]*$ ]]; then
        _mainframe_invoke_fail 126 invalid_id "canonical ID is malformed"
        return $?
    fi
    if ! _mainframe_invoke_trust_file_is_safe "$invocation_index"; then
        _mainframe_invoke_fail 126 invalid_manifest \
            "the canonical invocation index is missing or unsafe"
        return $?
    fi
    if ! _mainframe_invoke_trust_file_is_safe "$common_file"; then
        _mainframe_invoke_fail 126 invalid_owner \
            "the canonical runtime loader is missing or unsafe"
        return $?
    fi
    release_version="$(_mainframe_invoke_read_version "$version_file")" || {
        _mainframe_invoke_fail 126 invalid_manifest \
            "VERSION must contain exactly one canonical release version"
        return $?
    }
    if ! "$_MAINFRAME_INVOKE_JQ" -e \
        --argjson contract_count "$_MAINFRAME_INVOKE_CONTRACT_COUNT" \
        --arg release_version "$release_version" '
        type == "object" and
        keys == ["contract_count", "contracts", "manifest_version", "modules",
                 "name_index", "profile", "schema_version", "version"] and
        .schema_version == 1 and .manifest_version == 1 and
        (.version | type == "string" and . == $release_version) and
        .profile == "stable-core" and
        .contract_count == $contract_count and
        (.contracts | type == "object") and
        ((.contracts | length) == .contract_count) and
        (.name_index | type == "object") and
        ((.name_index | length) == .contract_count) and
        (.modules | type == "object" and length > 0) and
        all(.contracts | to_entries[];
          (.key | test("^mf:[a-z][a-z0-9-]*:[a-zA-Z0-9_-]+:[a-z_][a-z0-9_]*$")) and
          (.value | type == "object" and
            keys == ["bash_identifier", "call_shape", "capabilities",
                     "contract_status", "effects", "input_schema", "name",
                     "output_limit", "owner", "platforms", "profiles",
                     "result", "timeout_ms"])) and
        all(.name_index | to_entries[];
          (.key | test("^[a-z_][a-z0-9_]*$")) and
          (.value | test("^mf:[a-z][a-z0-9-]*:[a-zA-Z0-9_-]+:[a-z_][a-z0-9_]*$"))) and
        all(.modules | to_entries[];
          .key as $owner |
          ($owner | test("^[a-zA-Z0-9_-]+$")) and
          (.value | type == "object" and keys == ["file"] and
            .file == ("lib/" + $owner + ".sh")))
    ' "$invocation_index" >/dev/null 2>&1; then
        _mainframe_invoke_fail 126 invalid_manifest \
            "the canonical invocation index is malformed"
        return $?
    fi

    _MAINFRAME_INVOKE_EXPORT="$("$_MAINFRAME_INVOKE_JQ" -ce \
        --arg id "$canonical_id" '.contracts[$id] // empty' \
        "$invocation_index" 2>/dev/null)" || {
        _mainframe_invoke_fail 126 unknown_id "canonical ID is not registered"
        return $?
    }
    [[ -n "$_MAINFRAME_INVOKE_EXPORT" ]] || {
        _mainframe_invoke_fail 126 unknown_id "canonical ID is not registered"
        return $?
    }

    _MAINFRAME_INVOKE_NAME="$("$_MAINFRAME_INVOKE_JQ" -r '.name' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")"
    _MAINFRAME_INVOKE_OWNER="$("$_MAINFRAME_INVOKE_JQ" -r '.owner' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")"
    [[ "$_MAINFRAME_INVOKE_NAME" =~ ^[a-z_][a-z0-9_]*$ &&
       "$_MAINFRAME_INVOKE_OWNER" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        _mainframe_invoke_fail 126 invalid_contract \
            "invocation index owner or function name is unsafe"
        return $?
    }
    if ! "$_MAINFRAME_INVOKE_JQ" -e --arg id "$canonical_id" \
        --arg name "$_MAINFRAME_INVOKE_NAME" \
        --arg profile "$_MAINFRAME_INVOKE_PROFILE" '
        . as $export |
        .input_schema as $schema |
        .contract_status == "reviewed" and .bash_identifier == true and
        (.profiles | type == "array" and index($profile) != null) and
        (.effects | type == "array" and length == 1 and
          all(.[]; . == "pure" or . == "read")) and
        (.capabilities == []) and
		(.result | type == "object" and keys == ["kind"] and
		  (.kind == "stdout" or .kind == "exit" or .kind == "none")) and
        ($schema | type == "object" and
          keys == ["additionalProperties", "properties", "required", "type"]) and
        $schema.type == "object" and
        $schema.additionalProperties == false and
        ($schema.properties | type == "object") and
        ($schema.required as $required |
          ($required | type == "array") and
          all($required[]; type == "string" and
            test("^[a-z][a-z0-9_]{0,63}$")) and
          (($required | length) == ($required | unique | length)) and
          (($required - ($schema.properties | keys)) | length == 0)) and
        all($schema.properties | to_entries[];
          (.key | type == "string" and
            test("^[a-z][a-z0-9_]{0,63}$")) and
          (.key as $field | .value as $property |
            ($property.type == "string" and
              (($property | keys - ["default", "enum", "type"] | length) == 0) and
              (($schema.required | index($field)) != null or
                ($property | has("default"))) and
              (($property | has("default") | not) or
                (($property.default | type) == "string" and
                 ($property.default | contains("\u0000") | not))) and
              (($property | has("enum") | not) or
                (($property.enum | type) == "array" and
                 ($property.enum | length) > 0 and
                 ($property.enum | length) == ($property.enum | unique | length) and
                 all($property.enum[];
                   type == "string" and (contains("\u0000") | not)) and
                 (($property | has("default") | not) or
                   ($property.enum | index($property.default) != null))))) or
            ($property.type == "array" and
              (($property | keys - ["default", "items", "type"] | length) == 0) and
              ($property.items == {"type":"string"}) and
              (($schema.required | index($field)) != null or
                ($property | has("default"))) and
              (($property | has("default") | not) or
               (($property.default | type) == "array" and
                all($property.default[];
                  type == "string" and (contains("\u0000") | not))))))) and
        (.call_shape | type == "object" and keys == ["arguments", "kind"]) and
        (.call_shape.kind == "argv") and
        (.call_shape.arguments | type == "array" and length <= 64) and
        ([.call_shape.arguments[].field] as $fields |
          ($fields | length) == ($fields | unique | length) and
          (($fields | sort) == ($schema.properties | keys | sort))) and
        all(.call_shape.arguments[];
          (. | type == "object" and keys == ["field", "mode"]) and
          (.field | type == "string" and
            test("^[a-z][a-z0-9_]{0,63}$")) and
          (($schema.properties[.field].type == "string" and
            .mode == "scalar") or
           ($schema.properties[.field].type == "array" and
            .mode == "spread"))) and
        (.call_shape.arguments as $arguments |
          all(range(0; ($arguments | length)); . as $index |
            ($arguments[$index].mode != "spread") or
            $index == (($arguments | length) - 1)) and
          all(range(0; ($arguments | length)); . as $index |
            if ($arguments[$index].mode == "scalar" and
                ($schema.required | index($arguments[$index].field)) != null)
            then all(range(0; $index); . as $prior |
              ($arguments[$prior].mode != "scalar") or
              (($schema.required | index($arguments[$prior].field)) != null))
            else true end)) and
        (.timeout_ms | type == "number") and
        (.output_limit | type == "number")
    ' >/dev/null <<<"$_MAINFRAME_INVOKE_EXPORT"; then
        _mainframe_invoke_fail 126 unreviewed_contract \
            "export lacks a reviewed read/pure invocation contract"
        return $?
    fi
    _MAINFRAME_INVOKE_RESULT_KIND="$("$_MAINFRAME_INVOKE_JQ" -r '.result.kind' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")"
    module_file="$("$_MAINFRAME_INVOKE_JQ" -er --arg id "$canonical_id" \
        --arg name "$_MAINFRAME_INVOKE_NAME" \
        --arg owner "$_MAINFRAME_INVOKE_OWNER" '
        if .name_index[$name] == $id and
           .contracts[$id].owner == $owner and
           (.modules[$owner] | type == "object") and
           (.modules[$owner] | keys == ["file"]) and
           (.modules[$owner].file | type == "string")
        then .modules[$owner].file
        else error("invocation owner parity mismatch") end
    ' "$invocation_index" 2>/dev/null)" || {
        _mainframe_invoke_fail 126 owner_mismatch \
            "invocation index owner parity check failed"
        return $?
    }

    platform="$(_mainframe_invoke_platform)" || {
        _mainframe_invoke_fail 126 unsupported_platform "host platform is unsupported"
        return $?
    }
    if ! "$_MAINFRAME_INVOKE_JQ" -e --arg platform "$platform" \
        '.platforms | type == "array" and index($platform) != null' \
        >/dev/null <<<"$_MAINFRAME_INVOKE_EXPORT"; then
        _mainframe_invoke_fail 126 unsupported_platform "export is unavailable on this host"
        return $?
    fi

    timeout_ms="$("$_MAINFRAME_INVOKE_JQ" -r '.timeout_ms' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")"
    output_limit="$("$_MAINFRAME_INVOKE_JQ" -r '.output_limit' \
        <<<"$_MAINFRAME_INVOKE_EXPORT")"
    if [[ ! "$timeout_ms" =~ ^[0-9]+$ || ! "$output_limit" =~ ^[0-9]+$ ]] ||
       (( timeout_ms < 1 || timeout_ms > _MAINFRAME_INVOKE_MAX_TIMEOUT_MS ||
          output_limit < 1 || output_limit > _MAINFRAME_INVOKE_MAX_OUTPUT_LIMIT )); then
        _mainframe_invoke_fail 126 invalid_contract "contract bounds are invalid"
        return $?
    fi

    if ! _mainframe_invoke_jq_input -e --argjson schema \
        "$("$_MAINFRAME_INVOKE_JQ" -c '.input_schema' <<<"$_MAINFRAME_INVOKE_EXPORT")" '
        type == "object" and
        ($schema.type == "object") and
        ($schema.additionalProperties == false) and
        ($schema.properties | type == "object") and
        (($schema.required // []) | type == "array") and
        (($schema.required // []) - keys | length == 0) and
        (keys - ($schema.properties | keys) | length == 0) and
        all(to_entries[];
          . as $entry | $schema.properties[$entry.key] as $property |
          ($property.type == "string" and
            ($entry.value | type == "string") and
            ($entry.value | contains("\u0000") | not) and
            (($property | has("enum") | not) or
             ($property.enum | index($entry.value) != null))) or
          ($property.type == "array" and
            $property.items.type == "string" and
            ($entry.value | type == "array") and
            all($entry.value[];
              type == "string" and (contains("\u0000") | not))))
    ' >/dev/null 2>&1; then
        _mainframe_invoke_fail 65 invalid_input "JSON request does not match the closed input schema"
        return $?
    fi

    if _mainframe_invoke_extract_argv; then
        extract_status=0
    else
        extract_status=$?
    fi
    if (( extract_status == 2 )); then
        _mainframe_invoke_fail 65 invalid_input "JSON request creates a positional argument gap"
        return $?
    elif (( extract_status != 0 )); then
        _mainframe_invoke_fail 126 invalid_contract \
            "invocation contract call shape is invalid"
        return $?
    fi

    if [[ "$module_file" != "lib/${_MAINFRAME_INVOKE_OWNER}.sh" ]] ||
       ! _mainframe_invoke_trust_file_is_safe \
            "$MAINFRAME_ROOT/$module_file"; then
        _mainframe_invoke_fail 126 invalid_owner "canonical owner module is missing or unsafe"
        return $?
    fi

    if ! _mainframe_invoke_run "$module_file" "$timeout_ms" "$output_limit"; then
        _mainframe_invoke_fail 70 broker_error "could not create the bounded execution runtime"
        return $?
    fi

    if ! _mainframe_invoke_audit "$_MAINFRAME_INVOKE_RUN_STATUS" \
        "$_MAINFRAME_INVOKE_RUN_EXIT_CODE" "$_MAINFRAME_INVOKE_RUN_DURATION_MS" \
        "$_MAINFRAME_INVOKE_RUN_TIMED_OUT" \
        "$_MAINFRAME_INVOKE_RUN_OUTPUT_EXCEEDED"; then
        _MAINFRAME_INVOKE_RUN_STATUS=audit_error
        _MAINFRAME_INVOKE_RUN_EXIT_CODE=74
        _mainframe_invoke_replace_capture_text stdout "" || return 70
        _mainframe_invoke_replace_capture_text stderr \
            $'invocation audit trail became unavailable\n' || return 70
    fi

    if [[ "$_MAINFRAME_INVOKE_FORMAT" == broker-json-v1 ]]; then
        _mainframe_invoke_emit_envelope \
            "$([[ "$_MAINFRAME_INVOKE_RUN_STATUS" == success ]] && echo true || echo false)" \
            "$_MAINFRAME_INVOKE_RUN_STATUS" \
            "$_MAINFRAME_INVOKE_RUN_EXIT_CODE" \
            "$_MAINFRAME_INVOKE_RUN_TIMED_OUT" \
            "$_MAINFRAME_INVOKE_RUN_OUTPUT_EXCEEDED" \
            "$_MAINFRAME_INVOKE_RUN_DURATION_MS" \
            "$_MAINFRAME_INVOKE_RUN_STDOUT_READ_FD" \
            "$_MAINFRAME_INVOKE_RUN_STDERR_READ_FD"
    else
        /bin/cat <&"$_MAINFRAME_INVOKE_RUN_STDOUT_READ_FD"
        /bin/cat <&"$_MAINFRAME_INVOKE_RUN_STDERR_READ_FD" >&2
    fi

    _mainframe_invoke_cleanup_files
    return "$_MAINFRAME_INVOKE_RUN_EXIT_CODE"
}

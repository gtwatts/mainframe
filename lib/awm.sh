#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/awm.sh - Agent Working Memory (AWM)
# =============================================================================
# Description: Canonical Agent Working Memory facade for persistent session
#              state, discovery logging, handoff preparation, retrieval, and
#              context packing for finite-context agents.
# Version: 2.0.0
# Requires: Bash 4.4+
# =============================================================================

[[ -n "${_MAINFRAME_AWM_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_AWM_LOADED=1

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${SCRIPT_DIR}/json.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

AWM_ROOT="${AWM_ROOT:-${HOME}/.mainframe/awm}"
[[ "$AWM_ROOT" == "/" ]] || AWM_ROOT="${AWM_ROOT%/}"
AWM_SCHEMA_VERSION="${AWM_SCHEMA_VERSION:-2}"
AWM_MAX_FILE_SIZE="${AWM_MAX_FILE_SIZE:-65536}"
AWM_MAX_LOG_ENTRIES="${AWM_MAX_LOG_ENTRIES:-100}"
AWM_COMPRESS_AGE="${AWM_COMPRESS_AGE:-3600}"
AWM_CHARS_PER_TOKEN="${AWM_CHARS_PER_TOKEN:-4}"
AWM_LOCK_TIMEOUT="${AWM_LOCK_TIMEOUT:-5}"
AWM_FIND_DEFAULT_LIMIT="${AWM_FIND_DEFAULT_LIMIT:-10}"
AWM_CONTEXT_DEFAULT_TOKENS="${AWM_CONTEXT_DEFAULT_TOKENS:-4000}"
AWM_CONTEXT_DISCOVERY_LIMIT="${AWM_CONTEXT_DISCOVERY_LIMIT:-12}"
AWM_CONTEXT_LOG_LIMIT="${AWM_CONTEXT_LOG_LIMIT:-8}"
AWM_LOG_KEEP_RECENT="${AWM_LOG_KEEP_RECENT:-50}"
AWM_COMPAT_WARNINGS="${AWM_COMPAT_WARNINGS:-1}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -g _AWM_SESSION_ID=""
declare -g _AWM_SESSION_DIR=""
declare -g _AWM_NAMESPACE=""
declare -g _AWM_ACTIVE_BACKEND="${AWM_BACKEND:-file}"
declare -g _AWM_V2_INITIALIZED=0
declare -g _AWM_EMBEDDINGS_ATTEMPTED=0
declare -g _AWM_STRICT_JQ=""
declare -gi _AWM_PROJECT_MUTATION_DEPTH=0
declare -gA _AWM_DEPRECATION_WARNED=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_awm_log() {
    if declare -F _mainframe_log >/dev/null 2>&1; then
        _mainframe_log "awm" "$@"
    else
        local level="$1"
        shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[awm] %s: %s\n' "$level" "$*" >&2
        :
    fi
}

_awm_epoch() {
    local ts
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

_awm_timestamp() {
    local ts
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s.000000' "$ts"
    else
        date '+%s.%N' 2>/dev/null || date +%s
    fi
}

_awm_iso_timestamp() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
    fi
}

_awm_gen_session_id() {
    local id epoch
    id=$(od -An -tx1 -N6 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 12 ]]; then
        epoch=$(_awm_epoch)
        printf '%04x%04x%04x' "$$" "$RANDOM" "$((epoch % 65535))"
        return
    fi
    printf '%s' "${id:0:12}"
}

_awm_json_escape() {
    json_escape "$@"
}

_awm_sanitize_key() {
    local raw="$1"
    printf '%s' "${raw//[^a-zA-Z0-9_.:-]/_}"
}

_awm_sanitize_name() {
    local raw="$1"
    printf '%s' "${raw//[^a-zA-Z0-9_-]/_}"
}

_awm_validate_component() {
    local value="${1:-}"
    local label="${2:-component}"
    local quiet="${3:-0}"

    if [[ -z "$value" || ${#value} -gt 128 || "$value" == "." || "$value" == ".." || \
          ! "$value" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.:-]*$ ]]; then
        [[ "$quiet" == "1" ]] || _awm_log error "invalid ${label}: use 1-128 letters, digits, _, ., :, or - without path separators"
        return 1
    fi

    return 0
}

_awm_validate_storage_component() {
    local value="${1:-}"
    local label="${2:-storage key}"
    local maximum="${3:-128}"

    if [[ -z "$value" || ${#value} -gt maximum || \
          "$value" == "." || "$value" == ".." || \
          ! "$value" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
        _awm_log error "invalid ${label}: sanitized storage component must be 1-${maximum} ASCII characters"
        return 1
    fi
    return 0
}

_awm_validate_session_id() {
    _awm_validate_component "${1:-}" "session id" "${2:-0}"
}

_awm_validate_checkpoint_name() {
    _awm_validate_component "${1:-}" "checkpoint name" "${2:-0}"
}

_awm_parse_uint() {
    local value="${1:-}"
    local label="${2:-value}"
    local maximum="${3:-2147483647}"
    local normalized

    if [[ ! "$value" =~ ^[0-9]+$ || ${#value} -gt 10 ]]; then
        _awm_log error "${label} must be a non-negative integer"
        return 1
    fi
    normalized=$((10#$value))
    if (( normalized > maximum )); then
        _awm_log error "${label} exceeds maximum ${maximum}"
        return 1
    fi
    builtin printf '%d' "$normalized"
}

_awm_validate_importance() {
    local importance="${1:-}"

    case "$importance" in
        low|normal|high|critical) return 0 ;;
        *)
            _awm_log error "importance must be low, normal, high, or critical"
            return 1
            ;;
    esac
}

_awm_validate_root() {
    local root="${AWM_ROOT:-}"
    local current="/" rest component

    [[ "$root" == "/" ]] || root="${root%/}"
    if [[ -z "$root" || "$root" != /* || "$root" == "/" || \
          "$root" =~ [[:cntrl:]] || \
          "$root" == *'//'* || "$root" == *'/./'* || "$root" == */. || \
          "$root" == *'/../'* || "$root" == */.. ]]; then
        _awm_log error "AWM_ROOT must be an absolute, normalized, dedicated directory"
        return 1
    fi

    # Check the entire ancestry, not only components below AWM_ROOT. Otherwise
    # a custom root beneath a symbolic-link ancestor can be redirected before
    # the private 0700 storage boundary is established.
    rest="${root#/}"
    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"
        if [[ "$component" == "$rest" ]]; then
            rest=""
        else
            rest="${rest#*/}"
        fi
        [[ -n "$component" && "$component" != "." && "$component" != ".." ]] || return 1
        current="${current%/}/${component}"
        if [[ -L "$current" ]]; then
            _awm_log error "AWM_ROOT ancestry contains a symbolic link: $current"
            return 1
        fi
    done

    AWM_ROOT="$root"
    return 0
}

_awm_path_is_internal() {
    local path="$1"
    local root="${AWM_ROOT%/}"

    _awm_validate_root >/dev/null 2>&1 || return 1
    [[ "$path" == "$root" || "$path" == "$root/"* ]]
}

_awm_reject_symlink_components() {
    local path="$1"
    local root="${AWM_ROOT%/}"
    local current rest component

    if ! _awm_path_is_internal "$path"; then
        _awm_log error "AWM path escaped AWM_ROOT"
        return 1
    fi

    current="$root"
    if [[ -L "$current" ]]; then
        _awm_log error "AWM storage path contains a symbolic link: $current"
        return 1
    fi

    rest="${path#"$root"}"
    rest="${rest#/}"
    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"
        if [[ "$component" == "$rest" ]]; then
            rest=""
        else
            rest="${rest#*/}"
        fi
        if [[ -z "$component" || "$component" == "." || "$component" == ".." ]]; then
            _awm_log error "AWM path contains an unsafe component"
            return 1
        fi
        current="${current}/${component}"
        if [[ -L "$current" ]]; then
            _awm_log error "AWM storage path contains a symbolic link: $current"
            return 1
        fi
    done

    return 0
}

_awm_secure_directory() {
    local dir="$1"
    local root="${AWM_ROOT%/}"
    local current rest component

    _awm_reject_symlink_components "$dir" || return 1
    (umask 077; mkdir -p -- "$dir") || return 1
    _awm_reject_symlink_components "$dir" || return 1

    current="$root"
    chmod 700 "$current" 2>/dev/null || return 1
    rest="${dir#"$root"}"
    rest="${rest#/}"
    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"
        if [[ "$component" == "$rest" ]]; then
            rest=""
        else
            rest="${rest#*/}"
        fi
        current="${current}/${component}"
        chmod 700 "$current" 2>/dev/null || return 1
    done

    return 0
}

_awm_secure_session_tree() {
    local dir="$1"
    local symlink

    _awm_reject_symlink_components "$dir" || return 1
    [[ -d "$dir" ]] || return 1
    symlink=$(find "$dir" -type l -print -quit 2>/dev/null)
    if [[ -n "$symlink" ]]; then
        _awm_log error "AWM session contains a symbolic link: $symlink"
        return 1
    fi

    find "$dir" -type d -exec chmod 700 {} + 2>/dev/null || return 1
    find "$dir" -type f -exec chmod 600 {} + 2>/dev/null || return 1
    return 0
}

_awm_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

_awm_tags_json() {
    local csv="${1:-}"
    local tags_json="["
    local first=1
    local tag remaining="$csv"

    [[ -z "$csv" ]] && {
        printf '[]'
        return 0
    }

    # Parameter expansion, rather than an unquoted `for`, keeps wildcard tags
    # literal and cannot disclose names from the caller's current directory.
    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == *,* ]]; then
            tag="${remaining%%,*}"
            remaining="${remaining#*,}"
        else
            tag="$remaining"
            remaining=""
        fi
        tag=$(_awm_trim "$tag")
        [[ -z "$tag" ]] && continue
        [[ $first -eq 1 ]] || tags_json+=","
        first=0
        tags_json+="\"$(_awm_json_escape "$tag")\""
    done
    tags_json+="]"
    printf '%s' "$tags_json"
}

_awm_current_agent() {
    builtin printf '%s' "${MAINFRAME_AGENT_NAME:-${_MAINFRAME_AGENT_NAME:-${_AWM_AGENT_ID:-${USER:-unknown}}}}"
}

_awm_validate_current_agent() {
    local agent
    local LC_ALL=C

    agent=$(_awm_current_agent)
    if [[ -z "$agent" || ${#agent} -gt 128 || "$agent" =~ [[:cntrl:]] ]]; then
        _awm_log error "source agent must be a non-empty label of at most 128 bytes without control characters"
        return 1
    fi
    return 0
}

_awm_find_session_dir() {
    local sid="$1"
    local candidate namespace_dir namespace

    _awm_validate_session_id "$sid" 1 || return 1
    _awm_validate_root >/dev/null 2>&1 || return 1

    if [[ "$sid" == "$_AWM_SESSION_ID" && -n "$_AWM_SESSION_DIR" && \
          -f "$_AWM_SESSION_DIR/manifest.json" && ! -L "$_AWM_SESSION_DIR/manifest.json" ]] && \
       _awm_reject_symlink_components "$_AWM_SESSION_DIR/manifest.json"; then
        printf '%s' "$_AWM_SESSION_DIR"
        return 0
    fi

    candidate="${AWM_ROOT}/sessions/${sid}"
    if [[ -f "${candidate}/manifest.json" && ! -L "${candidate}/manifest.json" ]] && \
       _awm_reject_symlink_components "${candidate}/manifest.json"; then
        printf '%s' "$candidate"
        return 0
    fi

    for candidate in "${AWM_ROOT}/sessions"/*/"${sid}"; do
        namespace_dir="${candidate%/"$sid"}"
        namespace="${namespace_dir##*/}"
        _awm_validate_component "$namespace" "namespace" 1 || continue
        [[ -f "${candidate}/manifest.json" && ! -L "${candidate}/manifest.json" ]] || continue
        _awm_reject_symlink_components "${candidate}/manifest.json" || continue
        printf '%s' "$candidate"
        return 0
    done

    return 1
}

# The physical projects namespace is authoritative even if a manifest is
# missing or tampered. A projects namespace recorded in a manifest is an
# independent second signal so copied or misplaced project sessions also fail
# closed at generic-session boundaries.
_awm_session_is_project_reserved() {
    local sid="$1"
    local physical namespace=""

    _awm_validate_session_id "$sid" 1 || return 1
    _awm_validate_root >/dev/null 2>&1 || return 1
    physical="${AWM_ROOT}/sessions/projects/${sid}"
    if [[ -e "$physical" || -L "$physical" ]]; then
        return 0
    fi
    namespace=$(_awm_manifest_field "$sid" namespace 2>/dev/null || true)
    [[ "$namespace" == "projects" ]]
}

_awm_require_project_mutation_authorization() {
    local sid="${1:-$_AWM_SESSION_ID}"

    [[ -n "$sid" ]] || return 0
    if _awm_session_is_project_reserved "$sid" && \
       (( ${_AWM_PROJECT_MUTATION_DEPTH:-0} < 1 )); then
        _awm_log error "awm project: writes require the atomic project mutation boundary"
        return 1
    fi
    return 0
}

_awm_session_dir() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir

    _awm_validate_session_id "$sid" || return 1
    _awm_validate_root || return 1

    dir=$(_awm_find_session_dir "$sid") || true
    if [[ -n "$dir" ]]; then
        printf '%s' "$dir"
        return 0
    fi

    if [[ -n "$_AWM_NAMESPACE" ]]; then
        _awm_validate_component "$_AWM_NAMESPACE" "namespace" || return 1
        printf '%s/sessions/%s/%s' "$AWM_ROOT" "$_AWM_NAMESPACE" "$sid"
    else
        printf '%s/sessions/%s' "$AWM_ROOT" "$sid"
    fi
}

_awm_session_exists() {
    local sid="$1"
    _awm_validate_session_id "$sid" 1 || return 1
    [[ -n "$(_awm_find_session_dir "$sid" 2>/dev/null)" ]]
}

_awm_manifest_path() {
    local sid="${1:-$_AWM_SESSION_ID}"
    printf '%s/manifest.json' "$(_awm_session_dir "$sid")"
}

_awm_discoveries_file() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir
    dir=$(_awm_session_dir "$sid")
    if [[ -f "${dir}/discoveries.jsonl" ]]; then
        printf '%s/discoveries.jsonl' "$dir"
    else
        printf '%s/logs/discoveries.jsonl' "$dir"
    fi
}

_awm_discoveries_compat_file() {
    local sid="${1:-$_AWM_SESSION_ID}"
    printf '%s/logs/discoveries.jsonl' "$(_awm_session_dir "$sid")"
}

_awm_category_index_path() {
    local sid="${1:-$_AWM_SESSION_ID}"
    printf '%s/index/categories.json' "$(_awm_session_dir "$sid")"
}

_awm_progress_index_file() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local task="$2"
    printf '%s/index/progress/%s.json' "$(_awm_session_dir "$sid")" "$(_awm_sanitize_key "$task")"
}

_awm_journal_file() {
    local sid="${1:-$_AWM_SESSION_ID}"
    printf '%s/journal/events.jsonl' "$(_awm_session_dir "$sid")"
}

_awm_handoff_dir() {
    local sid="${1:-$_AWM_SESSION_ID}"
    printf '%s/handoffs' "$(_awm_session_dir "$sid")"
}

_awm_line_count() {
    local file="$1"
    [[ -f "$file" ]] || {
        printf '0'
        return 0
    }
    wc -l < "$file" 2>/dev/null | tr -d ' '
}

_awm_file_size() {
    local file="$1"
    [[ -f "$file" ]] || {
        printf '0'
        return 0
    }
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%z "$file" 2>/dev/null || printf '0'
    else
        stat -c%s "$file" 2>/dev/null || printf '0'
    fi
}

# Bound each caller-supplied durable payload before any AWM write begins. The
# limit is byte-based so multibyte input cannot bypass it, and parsing the
# configuration through the strict integer helper prevents arithmetic input
# from becoming shell code.
_awm_require_payload_size() {
    local label="$1"
    local value="${2:-}"
    local maximum bytes
    local LC_ALL=C

    maximum=$(_awm_parse_uint "$AWM_MAX_FILE_SIZE" \
        "AWM_MAX_FILE_SIZE" 1073741824) || return 1
    (( maximum > 0 )) || {
        _awm_log error "AWM_MAX_FILE_SIZE must be greater than zero"
        return 1
    }
    bytes=${#value}
    [[ "$bytes" =~ ^[0-9]+$ ]] || {
        _awm_log error "could not determine ${label} byte size safely"
        return 1
    }
    if (( bytes > maximum )); then
        _awm_log error "${label} exceeds AWM_MAX_FILE_SIZE (${bytes} > ${maximum} bytes)"
        return 1
    fi
    return 0
}

# Compute a content identity without consulting the caller's PATH.  AWM uses
# this only for consistency checks between a private checkpoint value and its
# sidecar; it does not elevate legacy memory into an authority source.
_awm_sha256_file() {
    local file="$1" output digest

    [[ -f "$file" && ! -L "$file" ]] || return 1
    if [[ -x /usr/bin/sha256sum ]]; then
        output=$(/usr/bin/sha256sum -- "$file") || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /bin/sha256sum ]]; then
        output=$(/bin/sha256sum -- "$file") || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /usr/bin/shasum ]]; then
        output=$(/usr/bin/shasum -a 256 -- "$file") || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /usr/bin/openssl ]]; then
        output=$(/usr/bin/openssl dgst -sha256 "$file") || return 1
        digest="${output##* }"
    else
        _awm_log error "AWM checkpoint integrity requires a fixed SHA-256 tool"
        return 1
    fi
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$digest"
}

_awm_path_mode() {
    local path="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%Lp "$path" 2>/dev/null
    else
        stat -c%a "$path" 2>/dev/null
    fi
}

# Linux user namespaces expose an unmapped host UID as the kernel overflow UID
# (normally 65534).  Codex's bubblewrap sandbox maps only the invoking account,
# so the host-root-owned /usr/bin/jq remains immutable but no longer appears to
# be owned by numeric UID 0 inside the sandbox.  Prove that host UID 0 is
# genuinely absent from the current namespace before accepting that narrow
# representation; ordinary namespaces and package-manager jq paths do not use
# this exception.
_awm_uid_map_excludes_host_root() {
    local map_file="${1:-/proc/self/uid_map}"
    local inside outside length extra saw_mapping=0

    [[ -f "$map_file" && ! -L "$map_file" && -r "$map_file" ]] || return 1
    while read -r inside outside length extra; do
        [[ -z "${extra:-}" && "$inside" =~ ^[0-9]+$ &&
           "$outside" =~ ^[0-9]+$ && "$length" =~ ^[0-9]+$ &&
           ${#inside} -le 10 && ${#outside} -le 10 && ${#length} -le 10 ]] ||
            return 1
        (( 10#$length > 0 )) || return 1
        saw_mapping=1
        # UID-map ranges are non-negative, so host UID 0 is mapped exactly
        # when a non-empty range begins at outside UID 0.
        (( 10#$outside != 0 )) || return 1
    done <"$map_file"
    (( saw_mapping == 1 ))
}

_awm_strict_jq_owner_is_trusted() {
    local owner="$1" candidate="$2"

    [[ "$owner" =~ ^[0-9]+$ ]] || return 1
    if [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]]; then
        return 0
    fi
    [[ "$owner" -eq 65534 ]] || return 1
    case "$candidate" in
        /usr/bin/jq|/bin/jq) ;;
        *) return 1 ;;
    esac
    _awm_uid_map_excludes_host_root /proc/self/uid_map
}

# Resolve the semantic parser from a closed set of fixed installations.  The
# caller's PATH is never consulted: checkpoint sidecars are a trust boundary,
# and the pure-Bash JSON helpers intentionally are not a duplicate-key-aware
# parser.  AWM fails closed when no authenticated jq is available.
_awm_strict_jq_path() {
    local candidate parent canonical_parent result owner mode numeric
    local -a candidates=()

    [[ -z "${_AWM_STRICT_JQ:-}" ]] || {
        printf '%s' "$_AWM_STRICT_JQ"
        return 0
    }
    [[ -z "${_MAINFRAME_CLI_JQ:-}" ]] || candidates+=("$_MAINFRAME_CLI_JQ")
    candidates+=(/usr/bin/jq /bin/jq)

    for candidate in "${candidates[@]}"; do
        [[ "$candidate" == /* && -f "$candidate" && ! -L "$candidate" &&
           -x "$candidate" ]] || continue
        case "$candidate" in
            /usr/bin/jq|/bin/jq|/usr/local/bin/jq|/opt/local/bin/jq|\
            /opt/homebrew/Cellar/*/bin/jq|/usr/local/Cellar/*/bin/jq|\
            /home/linuxbrew/.linuxbrew/Cellar/*/bin/jq|/nix/store/*/bin/jq) ;;
            *) continue ;;
        esac
        parent="${candidate%/*}"
        canonical_parent="$(builtin cd -- "$parent" 2>/dev/null && builtin pwd -P)" || continue
        [[ "$candidate" == "${canonical_parent%/}/${candidate##*/}" ]] || continue
        if [[ -x /usr/bin/stat ]]; then
            result="$(/usr/bin/stat -c '%u %a' "$candidate" 2>/dev/null ||
                /usr/bin/stat -f '%u %Mp%Lp' "$candidate" 2>/dev/null)" || continue
        elif [[ -x /bin/stat ]]; then
            result="$(/bin/stat -c '%u %a' "$candidate" 2>/dev/null ||
                /bin/stat -f '%u %Mp%Lp' "$candidate" 2>/dev/null)" || continue
        else
            continue
        fi
        [[ "$result" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || continue
        read -r owner mode <<<"$result"
        [[ ${#mode} -eq 4 && "$mode" == 0* ]] && mode="${mode#0}"
        _awm_strict_jq_owner_is_trusted "$owner" "$candidate" || continue
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
           (numeric & 0100) != 0 )) || continue
        _AWM_STRICT_JQ="$candidate"
        printf '%s' "$candidate"
        return 0
    done

    _awm_log error "AWM checkpoint validation requires a trusted fixed jq"
    return 1
}

_awm_strict_jq() {
    local jq_path
    jq_path="$(_awm_strict_jq_path)" || return 1
    "$jq_path" "$@"
}

_awm_atomic_write() {
    local target="$1"
    local content="$2"
    local parent_dir="${target%/*}"
    local tmpfile

    [[ "$parent_dir" != "$target" ]] || return 1
    _awm_secure_directory "$parent_dir" || return 1
    _awm_reject_symlink_components "$target" || return 1
    [[ ! -L "$target" ]] || return 1
    tmpfile=$( (umask 077; mktemp "${target}.tmp.XXXXXX") ) || return 1

    if printf '%s' "$content" > "$tmpfile" 2>/dev/null; then
        chmod 600 "$tmpfile" 2>/dev/null || {
            rm -f -- "$tmpfile" 2>/dev/null
            return 1
        }
        if mv -f -- "$tmpfile" "$target" 2>/dev/null; then
            chmod 600 "$target" 2>/dev/null || return 1
            return 0
        fi
    fi

    rm -f -- "$tmpfile" 2>/dev/null
    return 1
}

_awm_append_unlocked() {
    local target="$1"
    local content="$2"
    local parent_dir="${target%/*}"
    [[ "$parent_dir" != "$target" ]] || return 1
    _awm_secure_directory "$parent_dir" || return 1
    _awm_reject_symlink_components "$target" || return 1
    [[ ! -L "$target" ]] || return 1
    if [[ -e "$target" ]]; then
        [[ -f "$target" ]] || return 1
        chmod 600 "$target" 2>/dev/null || return 1
    fi
    (umask 077; printf '%s\n' "$content" >> "$target") || return 1
    chmod 600 "$target" 2>/dev/null
}

_awm_lock_strategy() {
    # Deterministic race tests can exercise the portable fallback without
    # exposing a production environment switch that would let two entrypoints
    # select incompatible lock mechanisms for the same AWM root.
    if [[ "${_MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS:-0}" == "1" && \
          -n "${BATS_TEST_FILENAME:-}" && -n "${BATS_TEST_TMPDIR:-}" ]]; then
        printf 'mkdir'
    elif _awm_lock_tool flock >/dev/null; then
        printf 'flock'
    elif _awm_lock_tool lockf >/dev/null; then
        # macOS ships BSD lockf. Its descriptor mode keeps the kernel lock on
        # fd 9 after the helper exits, and the kernel releases it on SIGKILL.
        printf 'lockf'
    else
        printf 'mkdir'
    fi
}

# AWM state can be reached from the protected CLI, Pi, or a sourced user shell.
# Select the same fixed system lock binary in every entrypoint; an ambient PATH
# must never make two processes use incompatible lock mechanisms for one root.
_awm_lock_tool() {
    local tool="$1"
    local candidate

    case "$tool" in
        flock)
            for candidate in /usr/bin/flock /bin/flock; do
                [[ -f "$candidate" && -x "$candidate" ]] || continue
                printf '%s' "$candidate"
                return 0
            done
            ;;
        lockf)
            for candidate in /usr/bin/lockf /bin/lockf; do
                [[ -f "$candidate" && -x "$candidate" ]] || continue
                printf '%s' "$candidate"
                return 0
            done
            ;;
    esac
    return 1
}

_awm_release_mkdir_lock() {
    local lock_dir="$1"
    local owner_file="$2"
    local owner_tmp="$3"
    local attempt

    rm -f -- "$owner_tmp" "$owner_file" 2>/dev/null || true
    for ((attempt = 0; attempt < 20; attempt++)); do
        rmdir -- "$lock_dir" 2>/dev/null && return 0
        [[ -d "$lock_dir" ]] || return 0
        sleep 0.01
    done
    return 0
}

_awm_with_lock() {
    local lock_name="$1"
    shift
    local strategy lock_tool parent_dir timeout
    strategy=$(_awm_lock_strategy)
    parent_dir="${lock_name%/*}"
    timeout=$(_awm_parse_uint "${AWM_LOCK_TIMEOUT:-5}" "lock timeout" 3600) || return 1
    (( timeout > 0 )) || timeout=1

    [[ "$parent_dir" != "$lock_name" ]] || return 1
    _awm_secure_directory "$parent_dir" || return 1
    _awm_reject_symlink_components "$lock_name" || return 1
    [[ ! -L "$lock_name" ]] || return 1

    if [[ "$strategy" == "flock" ]]; then
        lock_tool=$(_awm_lock_tool flock) || return 1
        (
            umask 077
            exec 9>"$lock_name" || exit 1
            chmod 600 "$lock_name" 2>/dev/null || exit 1
            "$lock_tool" -w "$timeout" 9 || exit 97
            "$@"
        )
        return $?
    fi

    if [[ "$strategy" == "lockf" ]]; then
        lock_tool=$(_awm_lock_tool lockf) || return 1
        (
            umask 077
            exec 9>"$lock_name" || exit 1
            chmod 600 "$lock_name" 2>/dev/null || exit 1
            "$lock_tool" -s -t "$timeout" 9 >/dev/null 2>&1 || exit 97
            "$@"
        )
        return $?
    fi

    local lock_dir="${lock_name}.dir"
    local start_seconds="$SECONDS"

    _awm_reject_symlink_components "$lock_dir" || return 1
    [[ ! -L "$lock_dir" ]] || return 1

    while ! (umask 077; mkdir -- "$lock_dir") 2>/dev/null; do
        if (( SECONDS - start_seconds >= timeout )); then
            _awm_log error \
                "AWM lock timed out without flock/lockf; refusing unsafe stale-lock recovery: $lock_dir"
            return 97
        fi
        sleep 0.05
    done
    chmod 700 "$lock_dir" 2>/dev/null || {
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    }

    (
        local owner_pid="${BASHPID:-$$}"
        local owner_epoch
        local owner_file="${lock_dir}/owner"
        local owner_tmp="${lock_dir}/owner.${owner_pid}.tmp"
        owner_epoch=$(_awm_epoch)
        trap '_awm_release_mkdir_lock "$lock_dir" "$owner_file" "$owner_tmp"' EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        umask 077
        printf 'pid=%s\nepoch=%s\n' "$owner_pid" "$owner_epoch" > "$owner_tmp" || exit 1
        mv -- "$owner_tmp" "$owner_file" || exit 1
        chmod 600 "$owner_file" 2>/dev/null || exit 1
        "$@"
    )
    local rc=$?
    return $rc
}

_awm_locked_atomic_write() {
    local target="$1"
    local content="$2"
    _awm_with_lock "${target}.lock" _awm_atomic_write "$target" "$content"
}

_awm_locked_append() {
    local target="$1"
    local content="$2"
    _awm_with_lock "${target}.lock" _awm_append_unlocked "$target" "$content"
}

_awm_manifest_field() {
    local sid="$1"
    local field="$2"
    local manifest
    manifest=$(_awm_manifest_path "$sid")
    [[ -f "$manifest" ]] || return 1
    sed -n "s/.*\"${field}\":\"\\([^\"]*\\)\".*/\\1/p" "$manifest" | head -n 1
}

_awm_manifest_number_field() {
    local sid="$1"
    local field="$2"
    local manifest
    manifest=$(_awm_manifest_path "$sid")
    [[ -f "$manifest" ]] || return 1
    sed -n "s/.*\"${field}\":\\([0-9][0-9]*\\).*/\\1/p" "$manifest" | head -n 1
}

_awm_build_manifest() {
    local session_id="$1"
    local name="$2"
    local parent_session="$3"
    local status="$4"
    local namespace="$5"
    local model="$6"
    local backend="$7"
    local created_at="$8"
    local created_epoch="$9"
    local updated_at="${10}"
    local updated_epoch="${11}"

    printf '{"schema_version":%s,"session_id":"%s","name":"%s","created_at":"%s","created_epoch":%s,"updated_at":"%s","updated_epoch":%s,"parent_session":"%s","status":"%s","namespace":"%s","model":"%s","backend":"%s"}' \
        "$AWM_SCHEMA_VERSION" \
        "$session_id" \
        "$(_awm_json_escape "${name:-unnamed}")" \
        "$created_at" \
        "$created_epoch" \
        "$updated_at" \
        "$updated_epoch" \
        "$(_awm_json_escape "$parent_session")" \
        "$(_awm_json_escape "$status")" \
        "$(_awm_json_escape "$namespace")" \
        "$(_awm_json_escape "$model")" \
        "$(_awm_json_escape "$backend")"
}

_awm_update_manifest_unlocked() {
    local sid="$1"
    local requested_status="${2:-}"
    local now iso created_at created_epoch name parent namespace model backend manifest
    local current_status manifest_path

    _awm_validate_session_id "$sid" || return 1
    manifest_path=$(_awm_manifest_path "$sid") || return 1
    current_status=$(_awm_manifest_field "$sid" status)

    # Project completion is monotonic. Supported project operations already
    # hold the mapping lifecycle lock before this inner manifest lock, but this
    # compare-and-swap also prevents a missed stale updater from resurrecting a
    # completed project session.
    if _awm_session_is_project_reserved "$sid" && \
       [[ "$current_status" == "completed" && \
          "${requested_status:-$current_status}" != "completed" ]]; then
        _awm_log error "awm project: a completed project session cannot be reactivated"
        return 1
    fi

    local status="${requested_status:-$current_status}"
    now=$(_awm_epoch)
    iso=$(_awm_iso_timestamp)
    created_at="${3:-$(_awm_manifest_field "$sid" created_at)}"
    created_epoch="${4:-$(_awm_manifest_number_field "$sid" created_epoch)}"
    name="${5:-$(_awm_manifest_field "$sid" name)}"
    parent="${6:-$(_awm_manifest_field "$sid" parent_session)}"
    namespace="${7:-$(_awm_manifest_field "$sid" namespace)}"
    model="${8:-$(_awm_manifest_field "$sid" model)}"
    backend="${9:-$(_awm_manifest_field "$sid" backend)}"

    [[ -z "$created_at" ]] && created_at="$iso"
    [[ -z "$created_epoch" ]] && created_epoch="$now"
    [[ -z "$backend" ]] && backend="${_AWM_ACTIVE_BACKEND:-file}"

    manifest=$(_awm_build_manifest \
        "$sid" \
        "$name" \
        "$parent" \
        "$status" \
        "$namespace" \
        "${model:-}" \
        "$backend" \
        "$created_at" \
        "$created_epoch" \
        "$iso" \
        "$now")

    _awm_atomic_write "$manifest_path" "$manifest"
}

_awm_update_manifest() {
    local sid="$1"
    shift || true
    local manifest_path

    _awm_validate_session_id "$sid" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1
    manifest_path=$(_awm_manifest_path "$sid") || return 1
    _awm_with_lock "${manifest_path}.lock" \
        _awm_update_manifest_unlocked "$sid" "$@"
}

_awm_ensure_session_layout() {
    local sid="$1"
    local dir
    _awm_validate_session_id "$sid" || return 1
    dir=$(_awm_session_dir "$sid") || return 1

    _awm_secure_directory "${dir}/logs" || return 1
    _awm_secure_directory "${dir}/data" || return 1
    _awm_secure_directory "${dir}/checkpoints" || return 1
    _awm_secure_directory "${dir}/handoffs" || return 1
    _awm_secure_directory "${dir}/index/progress" || return 1
    _awm_secure_directory "${dir}/journal" || return 1
    _awm_secure_session_tree "$dir" || return 1

    [[ -f "${dir}/discoveries.jsonl" ]] || _awm_atomic_write "${dir}/discoveries.jsonl" ''
    [[ -f "${dir}/logs/discoveries.jsonl" ]] || _awm_atomic_write "${dir}/logs/discoveries.jsonl" ''
    [[ -f "${dir}/logs/index.json" ]] || _awm_atomic_write "${dir}/logs/index.json" '{"categories":[]}'
    [[ -f "${dir}/index/categories.json" ]] || _awm_atomic_write "${dir}/index/categories.json" '[]'
    [[ -f "${dir}/journal/events.jsonl" ]] || _awm_atomic_write "${dir}/journal/events.jsonl" ''
    _awm_secure_session_tree "$dir"
}

_awm_journal_write() {
    local sid="$1"
    local event_kind="$2"
    local payload_json="$3"
    local entry

    _awm_validate_session_id "$sid" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1
    # `${payload_json:-{}}` is parsed as the expansion `${payload_json:-{}`
    # followed by a literal `}`.  When payload_json is set, that silently
    # appends an extra closing brace and corrupts every JSONL journal event.
    [[ -n "$payload_json" ]] || payload_json='{}'
    entry=$(printf '{"timestamp":"%s","kind":"%s","session_id":"%s","payload":%s}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_json_escape "$event_kind")" \
        "$sid" \
        "$payload_json")

    _awm_locked_append "$(_awm_journal_file "$sid")" "$entry"
}

_awm_update_category_index_unlocked() {
    local sid="$1"
    local category="$2"
    local logs_index category_index existing categories_json

    logs_index="$(_awm_session_dir "$sid")/logs/index.json"
    category_index=$(_awm_category_index_path "$sid")

    existing=$(tr -d '[:space:]' <"$category_index" 2>/dev/null || printf '[]')
    [[ -n "$existing" ]] || existing='[]'
    if [[ "$existing" != *"\"${category}\""* ]]; then
        categories_json="${existing%]}"
        if [[ "$categories_json" == "[" ]]; then
            categories_json+="\"$(_awm_json_escape "$category")\"]"
        else
            categories_json+=",\"$(_awm_json_escape "$category")\"]"
        fi
        _awm_atomic_write "$category_index" "$categories_json" || return 1
        _awm_atomic_write "$logs_index" "{\"categories\":${categories_json}}" || return 1
    fi
    return 0
}

_awm_update_category_index() {
    local sid="$1"
    local category="$2"
    local transaction_lock

    _awm_validate_session_id "$sid" || return 1
    _awm_validate_component "$category" "log category" || return 1
    transaction_lock="$(_awm_session_dir "$sid")/index/categories.transaction.lock"
    _awm_with_lock "$transaction_lock" _awm_update_category_index_unlocked "$sid" "$category"
}

_awm_read_recent_lines() {
    local file="$1"
    local count="$2"
    [[ -f "$file" ]] || return 0
    tail -n "$count" "$file" 2>/dev/null
}

_awm_record_log_entry() {
    local sid="$1"
    local category="$2"
    local message="$3"
    local importance="$4"
    local tags_csv="$5"
    local log_file entry tags_json

    log_file="$(_awm_session_dir "$sid")/logs/${category}.jsonl"
    tags_json=$(_awm_tags_json "$tags_csv")

    entry=$(printf '{"timestamp":"%s","ts":%s,"kind":"log","category":"%s","importance":"%s","tags":%s,"source_agent":"%s","session_id":"%s","msg":"%s"}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_timestamp)" \
        "$(_awm_json_escape "$category")" \
        "$(_awm_json_escape "$importance")" \
        "$tags_json" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$sid" \
        "$(_awm_json_escape "$message")")

    _awm_with_lock "${log_file}.lock" _awm_append_log_entry_unlocked \
        "$log_file" "$entry" "$category" "$sid" || return 1
    _awm_update_category_index "$sid" "$category" || return 1
    _awm_journal_write "$sid" "log" "$entry" || return 1
    return 0
}

_awm_record_discovery_entry() {
    local sid="$1"
    local insight="$2"
    local importance="$3"
    local tags_csv="$4"
    local entry tags_json root_file compat_file

    root_file=$(_awm_discoveries_file "$sid")
    compat_file=$(_awm_discoveries_compat_file "$sid")
    tags_json=$(_awm_tags_json "$tags_csv")

    entry=$(printf '{"timestamp":"%s","ts":%s,"kind":"discovery","importance":"%s","tags":%s,"source_agent":"%s","session_id":"%s","discovery":"%s","msg":"%s"}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_timestamp)" \
        "$(_awm_json_escape "$importance")" \
        "$tags_json" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$sid" \
        "$(_awm_json_escape "$insight")" \
        "$(_awm_json_escape "$insight")")

    _awm_locked_append "$root_file" "$entry" || return 1
    if [[ "$compat_file" != "$root_file" ]]; then
        _awm_locked_append "$compat_file" "$entry" || return 1
    fi
    _awm_update_category_index "$sid" "discoveries" || return 1
    _awm_journal_write "$sid" "discovery" "$entry" || return 1
    return 0
}

_awm_build_checkpoint_meta() {
    local sid="$1"
    local key="$2"
    local value="$3"
    local importance="$4"
    local tags_csv="$5"
    local ttl="$6"
    local file="$7"
    local source_agent="${8:-$(_awm_current_agent)}"
    local created_at="${9:-$(_awm_iso_timestamp)}"
    local created_epoch="${10:-$(_awm_epoch)}"
    local preview tags_json safe_key value_sha256 expires_at_epoch raw

    safe_key=$(_awm_sanitize_key "$key")
    preview="${value:0:256}"
    tags_json=$(_awm_tags_json "$tags_csv")
    value_sha256=$(_awm_sha256_file "$file") || return 1
    [[ "$created_epoch" =~ ^[0-9]+$ ]] || return 1
    if (( ttl > 0 )); then
        expires_at_epoch=$((created_epoch + ttl))
    else
        expires_at_epoch=null
    fi

    raw=$(printf '{"schema_version":1,"timestamp":"%s","created_epoch":%s,"kind":"checkpoint","importance":"%s","tags":%s,"source_agent":"%s","session_id":"%s","storage_key":"%s","key":"%s","preview":"%s","ttl":%s,"trust_label":"untrusted_legacy","authoritative":false,"provenance":{"source":"legacy_awm_v2","run_id":null,"call_id":null,"evidence_id":null,"input_digest":null},"retention":{"ttl_seconds":%s,"expires_at_epoch":%s},"value_sha256":"%s"}' \
        "$created_at" \
        "$created_epoch" \
        "$(_awm_json_escape "$importance")" \
        "$tags_json" \
        "$(_awm_json_escape "$source_agent")" \
        "$sid" \
        "$safe_key" \
        "$(_awm_json_escape "$key")" \
        "$(_awm_json_escape "$preview")" \
        "${ttl:-0}" \
        "${ttl:-0}" \
        "$expires_at_epoch" \
        "$value_sha256") || return 1
    # Store one canonical representation.  On read, byte equality with the
    # parser's canonical form exposes duplicate keys and ambiguous encodings
    # before any selected field is trusted.
    printf '%s' "$raw" | _awm_strict_jq -cS .
}

_awm_record_checkpoint_meta() {
    local sid="$1"
    local key="$2"
    local value="$3"
    local importance="$4"
    local tags_csv="$5"
    local ttl="$6"
    local file="$7"
    local entry index_file meta_file safe_key

    safe_key=$(_awm_sanitize_key "$key")
    entry=$(_awm_build_checkpoint_meta \
        "$sid" "$key" "$value" "$importance" "$tags_csv" "$ttl" "$file") || return 1

    index_file="$(_awm_session_dir "$sid")/logs/checkpoints.jsonl"
    meta_file="$(_awm_session_dir "$sid")/index/${safe_key}.json"

    _awm_locked_append "$index_file" "$entry" || return 1
    _awm_locked_atomic_write "$meta_file" "$entry" || return 1
    _awm_update_category_index "$sid" "checkpoints" || return 1
    _awm_journal_write "$sid" "checkpoint" "$entry" || return 1
    return 0
}

_awm_checkpoint_write_unlocked() {
    local sid="$1" key="$2" value="$3" importance="$4" tags="$5" ttl="$6" file="$7"

    _awm_atomic_write "$file" "$value" || return 1
    _awm_record_checkpoint_meta \
        "$sid" "$key" "$value" "$importance" "$tags" "$ttl" "$file"
}

# Validate the complete legacy sidecar/value binding before retrieval.  Return
# 0 for a current value, 2 for expired retention, and 3 for malformed/tampered
# metadata or a value digest mismatch.  Legacy memory always remains explicitly
# non-authorizing even when this consistency check succeeds.
_awm_checkpoint_metadata() {
    local sid="$1" safe_key="$2" file="$3"
    local meta_file content canonical fields
    local ttl expires_at_epoch expected_sha actual_sha now

    meta_file="$(_awm_session_dir "$sid")/index/${safe_key}.json" || return 3
    [[ -f "$meta_file" && ! -L "$meta_file" ]] || return 3
    _awm_reject_symlink_components "$meta_file" >/dev/null 2>&1 || return 3
    content=$(<"$meta_file") || return 3
    canonical=$(printf '%s' "$content" | _awm_strict_jq -cS . 2>/dev/null) || return 3
    [[ "$content" == "$canonical" ]] || return 3
    fields=$(printf '%s' "$content" | _awm_strict_jq -er \
        --arg sid "$sid" --arg storage "$safe_key" '
        def exact_keys($expected): type == "object" and keys == $expected;
        def valid:
          exact_keys(["authoritative", "created_epoch", "importance", "key",
                      "kind", "preview", "provenance", "retention",
                      "schema_version", "session_id", "source_agent",
                      "storage_key", "tags", "timestamp", "trust_label",
                      "ttl", "value_sha256"]) and
          .schema_version == 1 and .kind == "checkpoint" and
          (.timestamp | type == "string" and length > 0 and length <= 64) and
          (.created_epoch | type == "number" and . >= 0 and floor == .) and
          (.importance == "low" or .importance == "normal" or
           .importance == "high" or .importance == "critical") and
          (.tags | type == "array" and all(.[]; type == "string")) and
          (.source_agent | type == "string" and length > 0 and length <= 128) and
          .session_id == $sid and .storage_key == $storage and
          (.key | type == "string" and length > 0 and length <= 128 and
           gsub("[^a-zA-Z0-9_.:-]"; "_") == $storage) and
          (.preview | type == "string") and
          (.ttl | type == "number" and . >= 0 and . <= 2147483647 and floor == .) and
          .trust_label == "untrusted_legacy" and .authoritative == false and
          (.provenance |
            exact_keys(["call_id", "evidence_id", "input_digest", "run_id", "source"]) and
            .source == "legacy_awm_v2" and .run_id == null and .call_id == null and
            .evidence_id == null and .input_digest == null) and
          (.retention |
            exact_keys(["expires_at_epoch", "ttl_seconds"]) and
            (.ttl_seconds | type == "number" and . >= 0 and . <= 2147483647 and floor == .)) and
          .retention.ttl_seconds == .ttl and
          ((.ttl == 0 and .retention.expires_at_epoch == null) or
           (.ttl > 0 and
            (.retention.expires_at_epoch | type == "number" and floor == .) and
            .retention.expires_at_epoch == (.created_epoch + .ttl))) and
          (.value_sha256 | type == "string" and test("^[0-9a-f]{64}$"));
        if valid then
          [.retention.ttl_seconds,
           (if .retention.expires_at_epoch == null then "null"
            else (.retention.expires_at_epoch | tostring) end),
           .value_sha256] | @tsv
        else error("invalid checkpoint sidecar") end
        ' 2>/dev/null) || return 3
    IFS=$'\t' read -r ttl expires_at_epoch expected_sha <<<"$fields"
    [[ "$ttl" =~ ^[0-9]+$ &&
       ( "$expires_at_epoch" == null || "$expires_at_epoch" =~ ^[0-9]+$ ) &&
       "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || return 3
    actual_sha=$(_awm_sha256_file "$file") || return 3
    [[ "$actual_sha" == "$expected_sha" ]] || return 3
    if [[ "$expires_at_epoch" != null ]]; then
        now=$(_awm_epoch)
        [[ "$now" =~ ^[0-9]+$ ]] || return 3
        (( now < expires_at_epoch )) || return 2
    fi
    printf '%s' "$content"
}

_awm_snapshot_checkpoint() {
    local sid="$1"
    local checkpoint_name="$2"
    local dir checkpoint_dir snapshot

    _awm_validate_session_id "$sid" || return 1
    _awm_validate_checkpoint_name "$checkpoint_name" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1

    dir=$(_awm_find_session_dir "$sid") || {
        _awm_log error "awm_checkpoint: session not found: $sid"
        return 1
    }
    [[ -d "$dir" ]] || {
        _awm_log error "awm_checkpoint: session not found: $sid"
        return 1
    }
    _awm_ensure_session_layout "$sid" || return 1

    checkpoint_dir="${dir}/checkpoints/${checkpoint_name}"
    _awm_secure_directory "${checkpoint_dir}/data" || return 1
    if [[ -d "${dir}/data" ]]; then
        cp -R "${dir}/data/." "${checkpoint_dir}/data/" 2>/dev/null || true
    fi

    snapshot=$(printf '{"session_id":"%s","checkpoint":"%s","created_at":"%s","kind":"snapshot"}' \
        "$sid" \
        "$(_awm_json_escape "$checkpoint_name")" \
        "$(_awm_iso_timestamp)")

    _awm_locked_atomic_write "${checkpoint_dir}/snapshot.json" "$snapshot" || return 1
    _awm_secure_session_tree "$dir" || return 1
    _awm_journal_write "$sid" "snapshot" "$snapshot"
}

_awm_with_session() {
    local sid="$1"
    shift
    local previous_sid="$_AWM_SESSION_ID"
    local previous_dir="$_AWM_SESSION_DIR"
    local dir

    _awm_validate_session_id "$sid" || return 1
    dir=$(_awm_find_session_dir "$sid") || {
        _awm_log error "AWM session not found: $sid"
        return 1
    }
    _AWM_SESSION_ID="$sid"
    _AWM_SESSION_DIR="$dir"
    "$@"
    local rc=$?
    _AWM_SESSION_ID="$previous_sid"
    _AWM_SESSION_DIR="$previous_dir"
    return $rc
}

_awm_deprecate() {
    local symbol="$1"
    local replacement="$2"
    [[ "${AWM_COMPAT_WARNINGS:-1}" == "1" ]] || return 0
    [[ -n "${_AWM_DEPRECATION_WARNED[$symbol]:-}" ]] && return 0
    _AWM_DEPRECATION_WARNED["$symbol"]=1
    _awm_log warn "${symbol} is deprecated; use ${replacement}"
}

_awm_list_log_categories() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local index
    index=$(_awm_category_index_path "$sid")
    if [[ -f "$index" ]]; then
        while IFS= read -r category || [[ -n "$category" ]]; do
            [[ -n "$category" ]] && printf '%s\n' "$category"
        done < <(tr -d '[]"' < "$index" | tr ',' '\n' | sed '/^$/d')
        return 0
    fi

    local file
    for file in "$(_awm_session_dir "$sid")/logs/"*.jsonl; do
        [[ -f "$file" ]] || continue
        basename "$file" .jsonl
    done | sort -u
}

_awm_search_score() {
    local query="$1"
    local haystack="$2"
    local score=0
    local query_lc haystack_lc token

    query_lc=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')
    haystack_lc=$(printf '%s' "$haystack" | tr '[:upper:]' '[:lower:]')

    [[ -z "$query_lc" ]] && {
        printf '1'
        return 0
    }

    if [[ "$haystack_lc" == *"$query_lc"* ]]; then
        score=$((score + 50))
    fi

    for token in $query_lc; do
        [[ ${#token} -lt 2 ]] && continue
        if [[ "$haystack_lc" == *"$token"* ]]; then
            score=$((score + 10))
        fi
    done

    printf '%s' "$score"
}

_awm_try_load_embeddings() {
    [[ $_AWM_EMBEDDINGS_ATTEMPTED -eq 1 ]] && return 0
    _AWM_EMBEDDINGS_ATTEMPTED=1

    if declare -F embed_text >/dev/null 2>&1 && declare -F embed_similarity >/dev/null 2>&1; then
        return 0
    fi

    [[ "${MAINFRAME_AWM_FIND_EMBEDDINGS:-0}" == "1" ]] || return 0
    [[ -f "${SCRIPT_DIR}/embeddings.sh" ]] || return 0

    # shellcheck source=./embeddings.sh
    source "${SCRIPT_DIR}/embeddings.sh" 2>/dev/null || true
}

_awm_rerank_results_with_embeddings() {
    local query="$1"
    local input_file="$2"
    local output_file="$3"

    _awm_try_load_embeddings
    if ! declare -F embed_text >/dev/null 2>&1 || ! declare -F embed_similarity >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        cp "$input_file" "$output_file"
        return 0
    fi

    local query_vec
    query_vec=$(embed_text "$query" "${MAINFRAME_EMBED_PROVIDER:-local}" 2>/dev/null || true)
    if [[ -z "$query_vec" ]]; then
        cp "$input_file" "$output_file"
        return 0
    fi

    : > "$output_file"
    while IFS=$'\t' read -r score payload; do
        [[ -n "$payload" ]] || continue
        local preview cand_vec similarity semantic_score
        preview=$(printf '%s' "$payload" | jq -r '.preview // .msg // .discovery // .value // ""' 2>/dev/null || true)
        [[ -n "$preview" ]] || preview=$(printf '%s' "$payload" | jq -r '.title // ""' 2>/dev/null || true)
        cand_vec=$(embed_text "$preview" "${MAINFRAME_EMBED_PROVIDER:-local}" 2>/dev/null || true)
        if [[ -n "$cand_vec" ]]; then
            similarity=$(embed_similarity "$query_vec" "$cand_vec" 2>/dev/null || printf '0')
            semantic_score=$(awk -v base="$score" -v sim="$similarity" 'BEGIN { printf "%.6f", base + (sim * 25.0) }')
        else
            semantic_score="$score"
        fi
        printf '%s\t%s\n' "$semantic_score" "$payload" >> "$output_file"
    done < "$input_file"
}

_awm_select_top_results() {
    local input_file="$1"
    local limit="$2"
    local sorted_file
    sorted_file="$(mktemp "${TMPDIR:-/tmp}/awm-find-sort.XXXXXX")"

    _awm_rerank_results_with_embeddings "${3:-}" "$input_file" "$sorted_file"

    printf '['
    local first=1
    while IFS=$'\t' read -r _ payload; do
        [[ -n "$payload" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        first=0
        printf '%s' "$payload"
    done < <(sort -t $'\t' -k1,1nr "$sorted_file" | head -n "$limit")
    printf ']'

    rm -f "$sorted_file" 2>/dev/null
}

# Hidden control-plane reads cannot place raw search candidates in named
# files. This fixed lexical-only selector consumes an already-unlinked read FD;
# generic AWM keeps the existing optional embedding reranker above.
_awm_select_top_results_fd() {
    local input_fd="$1" limit="$2" first=1 payload
    [[ "$input_fd" =~ ^[0-9]+$ && "$limit" =~ ^[0-9]+$ ]] || return 1
    printf '['
    while IFS=$'\t' read -r _ payload; do
        [[ -n "$payload" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        first=0
        printf '%s' "$payload"
    done < <(sort -t $'\t' -k1,1nr <&"$input_fd" | head -n "$limit")
    printf ']'
}

_awm_progress_summary_json() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir file first=1 result="{"
    dir="$(_awm_session_dir "$sid")/index/progress"
    [[ -d "$dir" ]] || {
        printf '{}'
        return 0
    }

    for file in "$dir"/*.json; do
        [[ -f "$file" ]] || continue
        local task current total status entry
        entry=$(<"$file")
        task=$(sed -n 's/.*"task":"\([^"]*\)".*/\1/p' <<<"$entry" | head -n 1)
        current=$(sed -n 's/.*"current":\([0-9][0-9]*\).*/\1/p' <<<"$entry" | head -n 1)
        total=$(sed -n 's/.*"total":\([0-9][0-9]*\).*/\1/p' <<<"$entry" | head -n 1)
        status=$(sed -n 's/.*"status":"\([^"]*\)".*/\1/p' <<<"$entry" | head -n 1)
        [[ $first -eq 1 ]] || result+=","
        first=0
        result+="\"$(_awm_json_escape "$task")\":{\"current\":${current:-0},\"total\":${total:-0},\"status\":\"$(_awm_json_escape "$status")\"}"
    done
    result+="}"
    printf '%s' "$result"
}

_awm_build_prompt_context() {
    local task="$1"
    local discoveries="$2"
    local progress="$3"
    local checkpoints="$4"
    local logs="$5"
    local related="$6"
    local summary="$7"

    printf 'Task: %s\n\n' "$task"
    printf 'Discoveries:\n%s\n\n' "$discoveries"
    printf 'Current Progress:\n%s\n\n' "$progress"
    printf 'Relevant Checkpoints:\n%s\n\n' "$checkpoints"
    printf 'Recent Logs:\n%s\n\n' "$logs"
    printf 'Related Matches:\n%s\n\n' "$related"
    printf 'Summary:\n%s\n' "$summary"
}

_awm_string_bytes() {
    local value="${1:-}"
    local LC_ALL=C

    # Bash string length is a byte count in the C locale. Keeping this pure
    # avoids ambient command/function overrides at this arithmetic boundary.
    builtin printf '%d' "${#value}"
}

_awm_tokens_for_chars() {
    local chars="$1"
    printf '%d' "$(((chars + AWM_CHARS_PER_TOKEN - 1) / AWM_CHARS_PER_TOKEN))"
}

_awm_render_context_json() {
    local task="$1" requested_tokens="$2" max_chars="$3"
    local discoveries="$4" progress="$5" checkpoints="$6" logs="$7"
    local related="$8" summary="$9" truncated="${10}"
    local actual_chars="${11}" actual_tokens="${12}"

    printf '{"task":"%s","session_id":"%s","max_tokens":%s,"provenance":{"schema_version":%s,"namespace":"%s","backend":"%s","source_agent":"%s"},"budget":{"requested_tokens":%s,"chars_per_token":%s,"max_chars":%s,"actual_chars":%s,"actual_tokens":%s,"truncated":%s},"discoveries":%s,"progress":%s,"checkpoints":%s,"logs":%s,"related":%s,"summary":%s}' \
        "$(_awm_json_escape "$task")" \
        "$_AWM_SESSION_ID" \
        "$requested_tokens" \
        "$AWM_SCHEMA_VERSION" \
        "$(_awm_json_escape "${_AWM_NAMESPACE:-}")" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-file}")" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$requested_tokens" \
        "$AWM_CHARS_PER_TOKEN" \
        "$max_chars" \
        "$actual_chars" \
        "$actual_tokens" \
        "$truncated" \
        "$discoveries" \
        "$progress" \
        "$checkpoints" \
        "$logs" \
        "$related" \
        "$summary"
}

_awm_finalize_context_json() {
    local task="$1" requested_tokens="$2" max_chars="$3"
    local discoveries="$4" progress="$5" checkpoints="$6" logs="$7"
    local related="$8" summary="$9" truncated="${10}"
    local actual_chars=0 actual_tokens=0 next_chars next_tokens document iteration

    for ((iteration = 0; iteration < 6; iteration++)); do
        document=$(_awm_render_context_json \
            "$task" "$requested_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated" "$actual_chars" "$actual_tokens")
        next_chars=$(_awm_string_bytes "$document")
        next_tokens=$(_awm_tokens_for_chars "$next_chars")
        if [[ "$next_chars" -eq "$actual_chars" && "$next_tokens" -eq "$actual_tokens" ]]; then
            printf '%s' "$document"
            return 0
        fi
        actual_chars="$next_chars"
        actual_tokens="$next_tokens"
    done

    document=$(_awm_render_context_json \
        "$task" "$requested_tokens" "$max_chars" \
        "$discoveries" "$progress" "$checkpoints" "$logs" \
        "$related" "$summary" "$truncated" "$actual_chars" "$actual_tokens")
    printf '%s' "$document"
}

_awm_render_context_prompt() {
    local task="$1" requested_tokens="$2" max_chars="$3"
    local discoveries="$4" progress="$5" checkpoints="$6" logs="$7"
    local related="$8" summary="$9" truncated="${10}"
    local actual_chars="${11}" actual_tokens="${12}"

    printf 'Task: %s\n' "$task"
    printf 'Session ID: %s\n' "$_AWM_SESSION_ID"
    printf 'Provenance: schema_version=%s namespace=%s backend=%s source_agent=%s\n' \
        "$AWM_SCHEMA_VERSION" \
        "${_AWM_NAMESPACE:-}" \
        "${_AWM_ACTIVE_BACKEND:-file}" \
        "$(_awm_current_agent)"
    printf 'Budget: requested_tokens=%s chars_per_token=%s max_chars=%s actual_chars=%s actual_tokens=%s truncated=%s\n\n' \
        "$requested_tokens" "$AWM_CHARS_PER_TOKEN" "$max_chars" \
        "$actual_chars" "$actual_tokens" "$truncated"
    printf 'Discoveries:\n%s\n\n' "$discoveries"
    printf 'Current Progress:\n%s\n\n' "$progress"
    printf 'Relevant Checkpoints:\n%s\n\n' "$checkpoints"
    printf 'Recent Logs:\n%s\n\n' "$logs"
    printf 'Related Matches:\n%s\n\n' "$related"
    printf 'Summary:\n%s\n' "$summary"
}

_awm_finalize_context_prompt() {
    local task="$1" requested_tokens="$2" max_chars="$3"
    local discoveries="$4" progress="$5" checkpoints="$6" logs="$7"
    local related="$8" summary="$9" truncated="${10}"
    local actual_chars=0 actual_tokens=0 next_chars next_tokens document iteration

    for ((iteration = 0; iteration < 6; iteration++)); do
        document=$(_awm_render_context_prompt \
            "$task" "$requested_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated" "$actual_chars" "$actual_tokens")
        next_chars=$(_awm_string_bytes "$document")
        next_tokens=$(_awm_tokens_for_chars "$next_chars")
        if [[ "$next_chars" -eq "$actual_chars" && "$next_tokens" -eq "$actual_tokens" ]]; then
            printf '%s' "$document"
            return 0
        fi
        actual_chars="$next_chars"
        actual_tokens="$next_tokens"
    done

    document=$(_awm_render_context_prompt \
        "$task" "$requested_tokens" "$max_chars" \
        "$discoveries" "$progress" "$checkpoints" "$logs" \
        "$related" "$summary" "$truncated" "$actual_chars" "$actual_tokens")
    printf '%s' "$document"
}

_awm_finalize_context_document() {
    local format="$1"
    shift
    if [[ "$format" == "prompt" ]]; then
        _awm_finalize_context_prompt "$@"
    else
        _awm_finalize_context_json "$@"
    fi
}

_awm_compact_critical_discoveries() {
    local file line discovery source_agent result="[" first=1 count=0
    file=$(_awm_discoveries_file "$_AWM_SESSION_ID")
    [[ -f "$file" ]] || {
        printf '[]'
        return 0
    }

    while IFS= read -r line; do
        [[ "$line" == *'"importance":"critical"'* ]] || continue
        discovery=$(sed -n 's/.*"discovery":"\([^"]*\)".*/\1/p' <<<"$line" | head -n 1)
        source_agent=$(sed -n 's/.*"source_agent":"\([^"]*\)".*/\1/p' <<<"$line" | head -n 1)
        [[ -n "$discovery" ]] || continue
        discovery="${discovery:0:384}"
        [[ $first -eq 1 ]] || result+=","
        first=0
        result+="{\"importance\":\"critical\",\"source_agent\":\"$(_awm_json_escape "$source_agent")\",\"discovery\":\"$(_awm_json_escape "$discovery")\"}"
        count=$((count + 1))
        [[ $count -ge 3 ]] && break
    done < "$file"
    result+="]"
    printf '%s' "$result"
}

# =============================================================================
# SESSION LIFECYCLE
# =============================================================================

# Create a private file-backed AWM session and print its session ID.
# Usage: awm_init [NAME] [--parent ID] [--namespace NS] [--model MODEL] [--backend BACKEND]
awm_init() {
    local name=""
    local parent_session=""
    local namespace="${_AWM_NAMESPACE:-}"
    local model="${MAINFRAME_MODEL:-}"
    local backend="${AWM_BACKEND:-file}"
    local normalized_namespace

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parent)
                parent_session="${2:-}"
                shift 2
                ;;
            --namespace)
                namespace="${2:-}"
                shift 2
                ;;
            --model)
                model="${2:-}"
                shift 2
                ;;
            --backend)
                backend="${2:-file}"
                shift 2
                ;;
            --*)
                _awm_log warn "awm_init: ignoring unknown option $1"
                shift
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$parent_session" ]]; then
                    parent_session="$1"
                fi
                shift
                ;;
        esac
    done

    _awm_require_payload_size "session name" "${name:-unnamed}" || return 1
    _awm_require_payload_size "session namespace" "$namespace" || return 1
    _awm_require_payload_size "session model" "${model:-}" || return 1
    _awm_require_payload_size "session backend" "$backend" || return 1

    [[ -z "$backend" ]] && backend="file"
    if [[ "$backend" == "auto" ]]; then
        _AWM_ACTIVE_BACKEND="auto"
    else
        _AWM_ACTIVE_BACKEND="$backend"
    fi

    normalized_namespace=$(_awm_sanitize_name "$namespace")
    if [[ "$normalized_namespace" == "projects" && \
          ${_AWM_PROJECT_MUTATION_DEPTH:-0} -lt 1 ]]; then
        _awm_log error "awm_init: the projects namespace requires explicit project initialization"
        return 1
    fi

    if [[ -n "$namespace" ]]; then
        awm_namespace "$namespace"
    fi

    if [[ -n "$parent_session" ]]; then
        _awm_validate_session_id "$parent_session" || return 1
        _awm_find_session_dir "$parent_session" >/dev/null || {
            _awm_log error "awm_init: parent session not found: $parent_session"
            return 1
        }
        if _awm_session_is_project_reserved "$parent_session"; then
            _awm_log error "awm_init: project memory cannot be inherited through a generic session"
            return 1
        fi
    fi

    local session_id dir now now_iso manifest
    session_id=$(_awm_gen_session_id)
    dir=$(_awm_session_dir "$session_id") || return 1
    now=$(_awm_epoch)
    now_iso=$(_awm_iso_timestamp)

    _awm_secure_directory "$dir" || {
        _awm_log error "awm_init: failed to create session directory"
        return 1
    }

    _AWM_SESSION_ID="$session_id"
    _AWM_SESSION_DIR="$dir"
    _awm_ensure_session_layout "$session_id" || return 1

    manifest=$(_awm_build_manifest \
        "$session_id" \
        "${name:-unnamed}" \
        "${parent_session:-}" \
        "active" \
        "${_AWM_NAMESPACE:-}" \
        "${model:-}" \
        "$backend" \
        "$now_iso" \
        "$now" \
        "$now_iso" \
        "$now")

    _awm_locked_atomic_write "${dir}/manifest.json" "$manifest" || return 1
    _awm_journal_write "$session_id" "init" "{\"name\":\"$(_awm_json_escape "${name:-unnamed}")\",\"backend\":\"$(_awm_json_escape "$backend")\"}"

    if [[ -n "$parent_session" ]]; then
        _awm_inherit "$parent_session" "$session_id" || return 1
    fi

    printf '%s' "$session_id"
}

# Resume an existing AWM session after validating and safely migrating it.
# Usage: awm_resume SESSION_ID
awm_resume() {
    local session_id="$1"
    local dir namespace

    _awm_validate_session_id "$session_id" || return 1
    _awm_require_project_mutation_authorization "$session_id" || return 1

    dir=$(_awm_find_session_dir "$session_id") || {
        _awm_log error "awm_resume: session not found: $session_id"
        return 1
    }

    _AWM_SESSION_ID="$session_id"
    _AWM_SESSION_DIR="$dir"
    if ! awm_migrate "$session_id" >/dev/null; then
        _AWM_SESSION_ID=""
        _AWM_SESSION_DIR=""
        _awm_log error "awm_resume: session failed safety migration: $session_id"
        return 1
    fi

    namespace=$(_awm_manifest_field "$session_id" namespace)
    if [[ -n "$namespace" ]] && ! _awm_validate_component "$namespace" "namespace"; then
        _AWM_SESSION_ID=""
        _AWM_SESSION_DIR=""
        return 1
    fi
    _AWM_NAMESPACE="${namespace:-}"
    _AWM_ACTIVE_BACKEND="$(_awm_manifest_field "$session_id" backend)"
    [[ -z "$_AWM_ACTIVE_BACKEND" ]] && _AWM_ACTIVE_BACKEND="file"

    return 0
}

# Resolve one physical project directory to a stable private identity. The
# canonical path itself is never persisted in the project-session index; only
# its SHA-256 digest is stored under the already-private AWM_ROOT.
_awm_project_identity() {
    local project="${1:-.}"
    local canonical digest

    [[ -d "$project" ]] || {
        _awm_log error "awm project: directory not found: $project"
        return 1
    }
    canonical=$(cd -- "$project" 2>/dev/null && pwd -P) || {
        _awm_log error "awm project: could not resolve directory: $project"
        return 1
    }
    if [[ -z "$canonical" || "$canonical" != /* || \
          "$canonical" =~ [[:cntrl:]] ]]; then
        _awm_log error "awm project: canonical path is unsafe"
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        digest=$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        digest=$(printf '%s' "$canonical" | openssl dgst -sha256 | awk '{print $NF}')
    else
        _awm_log error "awm project: SHA-256 tool required (sha256sum, shasum, or openssl)"
        return 1
    fi
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || {
        _awm_log error "awm project: SHA-256 identity generation failed"
        return 1
    }
    printf '%s\t%s\n' "$canonical" "$digest"
}

# Return success only for a complete, same-version MAINFRAME managed block.
# A lone marker must not turn an arbitrary ancestor into a memory boundary.
_awm_project_file_has_managed_block() {
    local file="$1"
    local line version="" state="outside" count=0
    local begin_re='^<!-- MAINFRAME:BEGIN v([0-9]+) -->$'

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $begin_re ]]; then
            [[ "$state" == "outside" ]] || return 2
            version="${BASH_REMATCH[1]}"
            state="inside"
            continue
        fi
        if [[ "$line" == "<!-- MAINFRAME:BEGIN "* ]]; then
            return 2
        fi
        if [[ "$line" == "<!-- MAINFRAME:END "* ]]; then
            [[ "$state" == "inside" && \
               "$line" == "<!-- MAINFRAME:END v${version} -->" ]] || return 2
            count=$((count + 1))
            version=""
            state="outside"
        fi
    done < "$file"

    [[ "$state" == "outside" ]] || return 2
    case "$count" in
        0) return 1 ;;
        1) return 0 ;;
        *) return 2 ;;
    esac
}

# Return success when a physical directory contains a regular, non-symlinked
# instruction file with a complete MAINFRAME-managed activation block.
# Onboarding writes one at the selected project root, so it is also a portable
# root marker for non-Git projects without persisting the private path in AWM.
_awm_project_has_managed_root() {
    local root="$1"
    local candidate component marker_status parent rel rest
    local found=false
    local -a candidates=(
        "AGENTS.md"
        "CLAUDE.md"
        "GEMINI.md"
        ".github/copilot-instructions.md"
        ".cursor/rules/mainframe.mdc"
        ".aiassistant/rules/mainframe.md"
        ".junie/guidelines.md"
    )

    for rel in "${candidates[@]}"; do
        candidate="$root/$rel"
        parent="$root"
        rest="${rel%/*}"
        if [[ "$rest" != "$rel" ]]; then
            while [[ -n "$rest" ]]; do
                component="${rest%%/*}"
                if [[ "$component" == "$rest" ]]; then
                    rest=""
                else
                    rest="${rest#*/}"
                fi
                parent="$parent/$component"
                if [[ -L "$parent" ]]; then
                    _awm_log error "awm project: managed root marker path is a symbolic link"
                    return 2
                fi
                if [[ -e "$parent" && ! -d "$parent" ]]; then
                    _awm_log error "awm project: managed root marker parent is not a directory"
                    return 2
                fi
            done
        fi
        if [[ -L "$candidate" ]]; then
            _awm_log error "awm project: managed root marker path is a symbolic link"
            return 2
        fi
        if [[ -e "$candidate" && ! -f "$candidate" ]]; then
            _awm_log error "awm project: managed root marker is not a regular file"
            return 2
        fi
        [[ -f "$candidate" ]] || continue
        if _awm_project_file_has_managed_block "$candidate"; then
            found=true
        else
            marker_status=$?
            if [[ "$marker_status" -eq 2 ]]; then
                _awm_log error "awm project: managed root marker is malformed"
                return 2
            fi
        fi
    done

    [[ "$found" == "true" ]]
}

# Find the nearest lexical Git sentinel without following a symbolic link. Git
# remains authoritative when it is installed. On a release installation where
# Git is absent, the validated sentinel directory is a conservative traversal
# ceiling so managed project memory still works without a hidden dependency.
_awm_project_nearest_git_sentinel() {
    local discovered="$1"
    local parent sentinel

    while :; do
        sentinel="$discovered/.git"
        if [[ -e "$sentinel" || -L "$sentinel" ]]; then
            if [[ -L "$sentinel" || ( ! -d "$sentinel" && ! -f "$sentinel" ) ]]; then
                _awm_log error "awm project: Git sentinel is unsafe"
                return 2
            fi
            printf '%s\n' "$discovered"
            return 0
        fi
        [[ "$discovered" != "/" ]] || break
        parent="${discovered%/*}"
        [[ -n "$parent" ]] || parent="/"
        [[ "$parent" != "$discovered" ]] || break
        discovered="$parent"
    done

    return 1
}

# Treat an existing private project mapping as a fallback root signal. This
# preserves continuity if a managed instruction block is intentionally removed
# after onboarding. The first valid marker or mapping encountered is the
# nearest opted-in boundary; unsafe mapping evidence is never skipped.
# Unsafe mapping evidence is never skipped in favor of an outer root.
_awm_project_has_existing_mapping() {
    local project="$1"
    local canonical digest mapping sid mode

    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 2
    [[ -n "$canonical" && -n "$digest" ]] || return 2
    mapping=$(_awm_project_mapping_file "$digest") || return 2
    if [[ ! -e "$mapping" && ! -L "$mapping" ]]; then
        return 1
    fi
    sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest") || return 2
    _awm_validate_session_id "$sid" 1 || return 2
    mode=$(_awm_path_mode "$AWM_ROOT/projects")
    [[ "$mode" == "700" ]] || {
        _awm_log error "awm project: private mapping directory must have mode 700"
        return 2
    }
    return 0
}

# Resolve an agent's current working directory to its durable project root.
# This is deliberately opt-in at the CLI boundary: callers that pass an exact
# --project path keep exact-directory identity. Managed onboarding uses the
# discovery mode so a coding agent can move through subdirectories without
# silently fragmenting one repository's memory.
#
# Resolution order:
#   1. the nearest managed root or valid private mapping at or below the current
#      Git worktree boundary,
#   2. the Git worktree root (nested repositories stay distinct), and
#   3. the exact canonical directory outside Git as a compatibility fallback.
_awm_project_discover_root() {
    local project="${1:-.}"
    local canonical digest git_bin git_root="" git_sentinel=""
    local discovered discovered_digest parent marker_status mapping_status sentinel_status

    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    [[ -n "$canonical" && -n "$digest" ]] || return 1

    if git_sentinel=$(_awm_project_nearest_git_sentinel "$canonical"); then
        :
    else
        sentinel_status=$?
        [[ "$sentinel_status" -eq 1 ]] || return 1
        git_sentinel=""
    fi

    git_bin=$(type -P git 2>/dev/null || true)
    if [[ -n "$git_bin" && -x "$git_bin" ]]; then
        git_root=$(
            unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
            unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
            unset GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_PREFIX
            unset GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL
            unset GIT_CONFIG_NOSYSTEM
            unset GIT_TRACE GIT_TRACE_PACK_ACCESS GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE
            unset GIT_TRACE_SETUP GIT_TRACE_SHALLOW GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA
            unset GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF GIT_TRACE2_BRIEF
            unset GIT_TRACE2_CONFIG_PARAMS GIT_TRACE2_ENV_VARS GIT_TRACE2_DST_DEBUG
            unset GIT_TRACE_FSMONITOR GIT_TRACE_REFS
            GIT_CONFIG_COUNT=0 GIT_OPTIONAL_LOCKS=0 "$git_bin" -C "$canonical" \
                rev-parse --show-toplevel 2>/dev/null
        ) || git_root=""
        if [[ -n "$git_root" ]]; then
            IFS=$'\t' read -r discovered discovered_digest < <(
                _awm_project_identity "$git_root"
            ) || return 1
            [[ -n "$discovered" && -n "$discovered_digest" ]] || return 1
            if [[ "$canonical" != "$discovered" && \
                  "$canonical" != "$discovered/"* ]]; then
                _awm_log error "awm project: discovered Git root is not an ancestor"
                return 1
            fi
            if [[ -z "$git_sentinel" || "$discovered" != "$git_sentinel" ]]; then
                _awm_log error "awm project: discovered Git root does not match its worktree sentinel"
                return 1
            fi
            git_root="$discovered"
        fi
    fi
    if [[ -z "$git_root" && -n "$git_sentinel" ]]; then
        if [[ -z "$git_bin" ]]; then
            git_root="$git_sentinel"
        else
            _awm_log error "awm project: Git worktree root could not be resolved safely"
            return 1
        fi
    fi

    # A managed subproject is a narrower boundary than its enclosing worktree.
    # Search only as far as the Git root so a nested repository can never
    # inherit an outer repository's project memory.
    discovered="$canonical"
    while :; do
        # A filesystem-root mapping or marker must never capture every
        # otherwise-unmarked project on the machine.
        if [[ "$discovered" == "/" && "$canonical" != "/" ]]; then
            break
        fi
        if _awm_project_has_managed_root "$discovered"; then
            printf '%s\n' "$discovered"
            return 0
        else
            marker_status=$?
            [[ "$marker_status" -eq 1 ]] || return 1
        fi
        if _awm_project_has_existing_mapping "$discovered"; then
            printf '%s\n' "$discovered"
            return 0
        else
            mapping_status=$?
            [[ "$mapping_status" -eq 1 ]] || return 1
        fi
        if [[ -n "$git_root" && "$discovered" == "$git_root" ]]; then
            break
        fi
        [[ "$discovered" != "/" ]] || break
        parent="${discovered%/*}"
        [[ -n "$parent" ]] || parent="/"
        [[ "$parent" != "$discovered" ]] || break
        discovered="$parent"
    done

    if [[ -n "$git_root" ]]; then
        printf '%s\n' "$git_root"
        return 0
    fi
    printf '%s\n' "$canonical"
}

_awm_project_mapping_file() {
    local digest="$1"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    _awm_validate_root || return 1
    printf '%s/projects/%s.json' "$AWM_ROOT" "$digest"
}

_awm_project_read_mapping_unlocked() {
    local mapping="$1"
    local expected_digest="$2"
    local content schema digest sid mode

    [[ -f "$mapping" && ! -L "$mapping" ]] || {
        _awm_log error "awm project: private mapping is missing or unsafe"
        return 1
    }
    _awm_reject_symlink_components "$mapping" || return 1
    mode=$(_awm_path_mode "$mapping")
    [[ "$mode" == "600" ]] || {
        _awm_log error "awm project: private mapping must have mode 600"
        return 1
    }
    content=$(<"$mapping") || return 1
    json_valid "$content" || {
        _awm_log error "awm project: private mapping is malformed"
        return 1
    }
    schema=$(json_get "$content" schema_version) || schema=""
    digest=$(json_get "$content" project_sha256) || digest=""
    sid=$(json_get "$content" session_id) || sid=""
    if [[ "$schema" != "1" || "$digest" != "$expected_digest" ]] || \
       ! _awm_validate_session_id "$sid" 1; then
        _awm_log error "awm project: private mapping failed identity validation"
        return 1
    fi
    printf '%s' "$sid"
}

_awm_project_create_mapping_unlocked() {
    local mapping="$1"
    local digest="$2"
    local name="${3:-project-${digest:0:12}}"
    local sid document previous_depth rc

    previous_depth="${_AWM_PROJECT_MUTATION_DEPTH:-0}"
    _AWM_PROJECT_MUTATION_DEPTH=$((previous_depth + 1))
    if sid=$(awm_init "$name" --namespace projects --backend file); then
        rc=0
    else
        rc=$?
    fi
    _AWM_PROJECT_MUTATION_DEPTH="$previous_depth"
    (( rc == 0 )) || return "$rc"
    _awm_validate_session_id "$sid" 1 || return 1
    document=$(printf \
        '{"schema_version":1,"project_sha256":"%s","session_id":"%s","created_at":"%s"}' \
        "$digest" "$sid" "$(_awm_iso_timestamp)")
    _awm_atomic_write "$mapping" "$document" || return 1
    printf '%s' "$sid"
}

_awm_project_expected_session_dir() {
    local sid="$1"
    _awm_validate_session_id "$sid" 1 || return 1
    _awm_validate_root || return 1
    printf '%s/sessions/projects/%s' "$AWM_ROOT" "$sid"
}

# Bind an existing project session for inspection without locking, migrating,
# chmodding, creating layout, or otherwise mutating durable state. Project
# mappings are atomically replaced, so a validated lockless read observes
# either the old complete document or the new complete document.
_awm_project_bind_expected_readonly() {
    local sid="$1"
    local expected_dir manifest content schema manifest_sid namespace backend status
    local mode path unsafe normalized_schema

    expected_dir=$(_awm_project_expected_session_dir "$sid") || return 1
    manifest="$expected_dir/manifest.json"
    [[ -d "$expected_dir" && ! -L "$expected_dir" && \
       -f "$manifest" && ! -L "$manifest" ]] || {
        _awm_log error "awm project: mapped session storage is missing or unsafe"
        return 1
    }
    _awm_reject_symlink_components "$manifest" || return 1

    for path in \
        "$AWM_ROOT" \
        "$AWM_ROOT/projects" \
        "$AWM_ROOT/sessions" \
        "$AWM_ROOT/sessions/projects" \
        "$expected_dir"; do
        [[ -d "$path" && ! -L "$path" ]] || {
            _awm_log error "awm project: private session directory is missing or unsafe"
            return 1
        }
        mode=$(_awm_path_mode "$path")
        [[ "$mode" == "700" ]] || {
            _awm_log error "awm project: private session directories must have mode 700"
            return 1
        }
    done

    unsafe=$(find "$expected_dir" -type l -print -quit 2>/dev/null) || return 1
    [[ -z "$unsafe" ]] || {
        _awm_log error "awm project: private session tree contains a symbolic link"
        return 1
    }
    unsafe=$(find "$expected_dir" ! -type d ! -type f ! -type l -print -quit 2>/dev/null) || \
        return 1
    [[ -z "$unsafe" ]] || {
        _awm_log error "awm project: private session tree contains a special file"
        return 1
    }

    while IFS= read -r -d '' path; do
        mode=$(_awm_path_mode "$path")
        [[ "$mode" == "700" ]] || {
            _awm_log error "awm project: private session directories must have mode 700"
            return 1
        }
    done < <(find "$expected_dir" -type d -print0 2>/dev/null)
    while IFS= read -r -d '' path; do
        mode=$(_awm_path_mode "$path")
        [[ "$mode" == "600" ]] || {
            _awm_log error "awm project: private session files must have mode 600"
            return 1
        }
    done < <(find "$expected_dir" -type f -print0 2>/dev/null)

    content=$(<"$manifest") || return 1
    json_valid "$content" || {
        _awm_log error "awm project: mapped session manifest is malformed"
        return 1
    }
    schema=$(json_get "$content" schema_version) || schema=""
    manifest_sid=$(json_get "$content" session_id) || manifest_sid=""
    namespace=$(json_get "$content" namespace) || namespace=""
    backend=$(json_get "$content" backend) || backend=""
    status=$(json_get "$content" status) || status=""
    [[ "$schema" =~ ^[0-9]+$ && "$AWM_SCHEMA_VERSION" =~ ^[0-9]+$ ]] || {
        _awm_log error "awm project: mapped session schema is invalid"
        return 1
    }
    normalized_schema=$((10#$schema))
    if (( normalized_schema < 1 || normalized_schema > 10#$AWM_SCHEMA_VERSION )); then
        _awm_log error "awm project: mapped session schema is unsupported"
        return 1
    fi
    if [[ "$manifest_sid" != "$sid" || "$namespace" != "projects" || \
          "$backend" != "file" ]]; then
        _awm_log error "awm project: mapped session identity is invalid"
        return 1
    fi
    case "$status" in
        active|completed) ;;
        *)
            _awm_log error "awm project: mapped session has invalid status"
            return 1
            ;;
    esac

    _AWM_SESSION_ID="$sid"
    _AWM_SESSION_DIR="$expected_dir"
    _AWM_NAMESPACE="projects"
    _AWM_ACTIVE_BACKEND="file"
    return 0
}

_awm_project_validate_ensure_expectation() {
    local expected_state="${1:-}"
    local expected_sid="${2:-}"

    case "$expected_state" in
        ""|unmapped|completed) ;;
        *)
            _awm_log error "awm project: invalid expected initialization state"
            return 2
            ;;
    esac
    case "$expected_state" in
        "")
            [[ -z "$expected_sid" ]] || {
                _awm_log error "awm project: a session identity requires an expected state"
                return 2
            }
            ;;
        unmapped)
            [[ -z "$expected_sid" ]] || {
                _awm_log error "awm project: unmapped initialization cannot expect a session identity"
                return 2
            }
            ;;
        completed)
            if [[ -z "$expected_sid" ]] || \
               ! _awm_validate_session_id "$expected_sid" 1; then
                _awm_log error "awm project: completed initialization requires a valid expected session identity"
                return 2
            fi
            ;;
    esac

    return 0
}

_awm_project_ensure_unlocked() {
    local mapping="$1"
    local digest="$2"
    local name="$3"
    local expected_state="${4:-}"
    local expected_sid="${5:-}"
    local sid status expected_session_dir

    _awm_project_validate_ensure_expectation \
        "$expected_state" "$expected_sid" || return $?

    if [[ "$expected_state" == "unmapped" && ( -e "$mapping" || -L "$mapping" ) ]]; then
        _awm_log error "awm project: initialization state changed before confirmation completed"
        return 75
    fi
    if [[ "$expected_state" == "completed" && ( ! -e "$mapping" && ! -L "$mapping" ) ]]; then
        _awm_log error "awm project: initialization state changed before confirmation completed"
        return 75
    fi

    if [[ -e "$mapping" || -L "$mapping" ]]; then
        sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest") || return 1
        if [[ "$expected_state" == "completed" && "$sid" != "$expected_sid" ]]; then
            _awm_log error "awm project: initialization session changed before confirmation completed"
            return 75
        fi
        expected_session_dir=$(_awm_project_expected_session_dir "$sid") || return 1
        if [[ ! -d "$expected_session_dir" || -L "$expected_session_dir" ]]; then
            if [[ "$expected_state" == "completed" ]]; then
                _awm_log error "awm project: initialization state changed before confirmation completed"
                return 75
            fi
            _awm_log error "awm project: mapped session storage is missing or unsafe"
            return 1
        fi
        _awm_project_bind_expected_readonly "$sid" || return 1
        status=$(_awm_manifest_field "$sid" status)
        if [[ -n "$expected_state" && "$status" != "$expected_state" ]]; then
            _awm_log error "awm project: initialization state changed before confirmation completed"
            return 75
        fi
        case "$status" in
            active)
                printf '%s' "$sid"
                return 0
                ;;
            completed)
                ;;
            *)
                _awm_log error "awm project: mapped session has invalid status"
                return 1
                ;;
        esac
    fi

    _awm_project_create_mapping_unlocked "$mapping" "$digest" "$name"
}

# Create or resume the one active private AWM session associated with a
# physical project. Concurrent callers serialize on the project identity and
# all receive the same session id.
# Optional EXPECTED_STATE and EXPECTED_SID bind a confirmation to the exact
# unmapped/completed state observed before the user approved initialization.
# Usage: awm_project_ensure [PROJECT] [NAME] [EXPECTED_STATE] [EXPECTED_SID]
awm_project_ensure() {
    local project="${1:-.}"
    local name="${2:-}"
    local expected_state="${3:-}"
    local expected_sid="${4:-}"
    local canonical digest mapping result sid mapped_sid rc effective_name

    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    [[ -n "$canonical" && -n "$digest" ]] || return 1
    effective_name="${name:-project-${digest:0:12}}"
    _awm_project_validate_ensure_expectation \
        "$expected_state" "$expected_sid" || return $?
    # Preflight the same durable init fields before the lifecycle lock creates
    # its private parent directory. Recheck remains inside awm_init while the
    # lock is held so a changed configuration still fails closed.
    _awm_require_payload_size "session name" "$effective_name" || return 1
    _awm_require_payload_size "session namespace" "projects" || return 1
    _awm_require_payload_size "session model" "${MAINFRAME_MODEL:-}" || return 1
    _awm_require_payload_size "session backend" "file" || return 1
    mapping=$(_awm_project_mapping_file "$digest") || return 1
    if result=$(_awm_with_lock "${mapping}.lock" \
        _awm_project_ensure_unlocked "$mapping" "$digest" "$name" \
        "$expected_state" "$expected_sid"); then
        :
    else
        rc=$?
        return "$rc"
    fi
    sid="${result##*$'\n'}"
    _awm_validate_session_id "$sid" 1 || return 1
    mapped_sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest") || return 1
    if [[ "$mapped_sid" != "$sid" ]]; then
        _awm_log error "awm project: project mapping changed after initialization"
        return 75
    fi
    _awm_project_bind_expected_readonly "$sid" || return 1
    printf '%s\n' "$sid"
}

# Resolve an existing project mapping without locking, migration, repair, or
# any durable-state write.
# Usage: awm_project_session [PROJECT]
awm_project_session() {
    local project="${1:-.}"
    local canonical digest mapping sid

    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    [[ -n "$canonical" && -n "$digest" ]] || return 1
    mapping=$(_awm_project_mapping_file "$digest") || return 1
    if [[ ! -e "$mapping" && ! -L "$mapping" ]]; then
        _awm_log error "awm project: project has no mapped session"
        return 1
    fi
    sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest") || return 1
    _awm_validate_session_id "$sid" 1 || return 1
    _awm_project_bind_expected_readonly "$sid" || return 1
    printf '%s\n' "$sid"
}

# Report the private project binding plus the canonical AWM session status.
# Usage: awm_project_status [PROJECT]
awm_project_status() {
    local project="${1:-.}"
    local canonical digest mapping sid status_json

    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    [[ -n "$canonical" && -n "$digest" ]] || return 1
    mapping=$(_awm_project_mapping_file "$digest") || return 1
    if [[ ! -e "$mapping" && ! -L "$mapping" ]]; then
        printf '{"schema_version":1,"status":"unmapped","project_sha256":"%s"}\n' \
            "$digest"
        return 1
    fi
    if ! awm_project_session "$canonical" >/dev/null 2>&1; then
        printf '{"schema_version":1,"status":"invalid","project_sha256":"%s"}\n' \
            "$digest"
        return 1
    fi
    sid="$_AWM_SESSION_ID"
    _awm_validate_session_id "$sid" 1 || return 1
    if ! status_json=$(awm_status "$sid"); then
        printf '{"schema_version":1,"status":"invalid","project_sha256":"%s"}\n' \
            "$digest"
        return 1
    fi
    printf \
        '{"schema_version":1,"status":"mapped","project_sha256":"%s","session_id":"%s","private":true,"session":%s}\n' \
        "$digest" "$sid" "$status_json"
}

_awm_project_dispatch_mutation() {
    local action="$1"
    shift

    case "$action" in
        checkpoint) awm_checkpoint "$@" ;;
        discovery) awm_discovery "$@" ;;
        progress) awm_progress "$@" ;;
        handoff_prepare) awm_handoff_prepare "$@" ;;
        close) awm_close ;;
        *)
            _awm_log error "awm project: unsupported mutation action: $action"
            return 2
            ;;
    esac
}

_awm_project_mutate_bound_unlocked() {
    local mapping="$1"
    local digest="$2"
    local expected_sid="$3"
    local action="$4"
    shift 4
    local sid status previous_depth rc

    sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest") || return 1
    _awm_validate_session_id "$sid" 1 || return 1
    if [[ -n "$expected_sid" && "$sid" != "$expected_sid" ]]; then
        _awm_log error "awm project: mutation session changed before confirmation completed"
        return 75
    fi
    _awm_project_bind_expected_readonly "$sid" || return 1
    status=$(_awm_manifest_field "$sid" status)
    if [[ "$status" != "active" ]]; then
        if [[ -n "$expected_sid" ]]; then
            _awm_log error "awm project: mutation state changed before confirmation completed"
            return 75
        fi
        _awm_log error "awm project: mutation requires the currently mapped session to be active"
        return 1
    fi

    previous_depth="${_AWM_PROJECT_MUTATION_DEPTH:-0}"
    _AWM_PROJECT_MUTATION_DEPTH=$((previous_depth + 1))
    if _awm_project_dispatch_mutation "$action" "$@"; then
        rc=0
    else
        rc=$?
    fi
    _AWM_PROJECT_MUTATION_DEPTH="$previous_depth"
    return "$rc"
}

_awm_project_mutate_unlocked() {
    local mapping="$1"
    local digest="$2"
    local action="$3"
    shift 3
    _awm_project_mutate_bound_unlocked "$mapping" "$digest" "" "$action" "$@"
}

_awm_project_mutate_expected_unlocked() {
    local mapping="$1"
    local digest="$2"
    local expected_sid="$3"
    local action="$4"
    shift 4
    _awm_project_mutate_bound_unlocked \
        "$mapping" "$digest" "$expected_sid" "$action" "$@"
}

_awm_project_mutate_transaction() {
    local project="$1"
    local action="$2"
    local expected_sid="$3"
    shift 3
    local canonical digest mapping rc

    case "$action" in
        checkpoint|discovery|progress|handoff_prepare|close) ;;
        *)
            _awm_log error "awm project: unsupported mutation action: $action"
            return 2
            ;;
    esac
    if [[ -n "$expected_sid" ]] && ! _awm_validate_session_id "$expected_sid" 1; then
        _awm_log error "awm project: invalid expected mutation session identity"
        return 2
    fi
    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    [[ -n "$canonical" && -n "$digest" ]] || return 1
    mapping=$(_awm_project_mapping_file "$digest") || return 1
    if [[ ! -e "$mapping" && ! -L "$mapping" ]]; then
        _awm_log error "awm project: project has no mapped session"
        [[ -z "$expected_sid" ]] && return 1 || return 75
    fi
    if _awm_with_lock "${mapping}.lock" \
        _awm_project_mutate_expected_unlocked \
        "$mapping" "$digest" "$expected_sid" "$action" "$@"; then
        return 0
    else
        rc=$?
        return "$rc"
    fi
}

# Serialize a project write, close, or handoff against renewal on the same
# project identity. The mapping and active-state checks happen while holding
# the same lock as awm_project_ensure, so a stale process cannot write into or
# reactivate a completed/replaced project session.
# Internal lifecycle dispatcher used by the validated project CLI.
# Usage: _awm_project_mutate PROJECT ACTION [ARGS...]
_awm_project_mutate() {
    local project="${1:-.}"
    local action="${2:-}"
    shift 2 || true
    _awm_project_mutate_transaction "$project" "$action" "" "$@"
}

# Bind a confirmed destructive lifecycle action to the exact active project
# session that the human reviewed. This is intentionally internal and closed
# to `close`; Pi uses it after presenting its confirmation UI.
_awm_project_mutate_expected() {
    local project="${1:-.}"
    local action="${2:-}"
    local expected_sid="${3:-}"
    shift 3 || true

    [[ "$action" == "close" ]] || {
        _awm_log error "awm project: confirmed mutation supports close only"
        return 2
    }
    _awm_validate_session_id "$expected_sid" 1 || {
        _awm_log error "awm project: confirmed close requires an expected session identity"
        return 2
    }
    _awm_project_mutate_transaction \
        "$project" "$action" "$expected_sid" "$@"
}

# Mark the active session completed and optionally export it as Markdown.
# Usage: awm_close [--export PATH]
awm_close() {
    local export_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --export)
                export_path="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log warn "awm_close: no active session"
        return 0
    fi
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    _awm_update_manifest "$_AWM_SESSION_ID" "completed" || return 1
    _awm_journal_write "$_AWM_SESSION_ID" "close" '{"status":"completed"}'
    [[ -n "$export_path" ]] && awm_export "$export_path" >/dev/null
    _AWM_SESSION_ID=""
    _AWM_SESSION_DIR=""
    return 0
}

_awm_inherit() {
    local parent_id="$1"
    local child_id="$2"
    local parent_dir child_dir parent_disc

    _awm_validate_session_id "$parent_id" || return 1
    _awm_validate_session_id "$child_id" || return 1
    _awm_require_project_mutation_authorization "$parent_id" || return 1
    _awm_require_project_mutation_authorization "$child_id" || return 1
    parent_dir=$(_awm_find_session_dir "$parent_id") || {
        _awm_log warn "_awm_inherit: parent session not found: $parent_id"
        return 1
    }
    child_dir=$(_awm_session_dir "$child_id") || return 1
    _awm_secure_session_tree "$parent_dir" || return 1
    _awm_ensure_session_layout "$child_id" || return 1

    parent_disc=$(_awm_discoveries_file "$parent_id")
    if [[ -f "$parent_disc" ]]; then
        cp -f "$parent_disc" "${child_dir}/logs/inherited_discoveries.jsonl" 2>/dev/null || true
    fi

    if [[ -d "${parent_dir}/data" ]]; then
        cp -R "${parent_dir}/data/." "${child_dir}/data/" 2>/dev/null || true
    fi

    _awm_secure_session_tree "$child_dir" || return 1
    _awm_journal_write "$child_id" "inherit" "{\"parent_session\":\"$(_awm_json_escape "$parent_id")\"}"
    return 0
}

# Select the organizational namespace used for subsequently created sessions.
# Usage: awm_namespace NAME
awm_namespace() {
    local ns="${1:-}"
    if [[ -z "$ns" ]]; then
        _AWM_NAMESPACE=""
    else
        _AWM_NAMESPACE="$(_awm_sanitize_name "$ns")"
    fi
}

awm_team_namespace() {
    local team_name="${CLAUDE_AGENT_TEAM_NAME:-}"
    local team_dir

    if [[ -z "$team_name" && -d "${HOME}/.claude/teams" ]]; then
        for team_dir in "${HOME}/.claude/teams"/*/; do
            [[ -d "$team_dir" ]] || continue
            team_name="${team_dir%/}"
            team_name="${team_name##*/}"
            break
        done
    fi

    [[ -n "$team_name" ]] || return 1
    awm_namespace "team-${team_name}"
    return 0
}

# =============================================================================
# CORE WRITE FUNCTIONS
# =============================================================================

# Store durable key/value state or create a named session snapshot.
# Usage: awm_checkpoint KEY VALUE [--importance LEVEL] [--tags CSV] [--ttl SEC]
awm_checkpoint() {
    if [[ $# -eq 2 ]] && _awm_session_exists "$1"; then
        _awm_require_payload_size "snapshot name" "$2" || return 1
        _awm_snapshot_checkpoint "$1" "$2"
        return $?
    fi

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_checkpoint: no active session"
        return 1
    fi
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    (( $# >= 2 )) || {
        _awm_log error "awm_checkpoint: key and value required"
        return 1
    }
    local key="$1"
    local value="$2"
    local importance="normal"
    local tags=""
    local ttl="0"
    local safe_key dir file
    shift 2

    while (( $# > 0 )); do
        case "$1" in
            --importance|--tags|--ttl)
                (( $# >= 2 )) || {
                    _awm_log error "awm_checkpoint: $1 requires a value"
                    return 1
                }
                case "$1" in
                    --importance) importance="$2" ;;
                    --tags) tags="$2" ;;
                    --ttl) ttl="$2" ;;
                esac
                shift 2
                ;;
            *)
                _awm_log error "awm_checkpoint: unknown option $1"
                return 1
                ;;
        esac
    done

    [[ -n "$key" ]] || {
        _awm_log error "awm_checkpoint: key required"
        return 1
    }
    _awm_require_payload_size "checkpoint key" "$key" || return 1
    _awm_require_payload_size "checkpoint value" "$value" || return 1
    _awm_validate_importance "$importance" || return 1
    _awm_require_payload_size "checkpoint tags" "$tags" || return 1
    ttl=$(_awm_parse_uint "$ttl" "checkpoint TTL" 315360000) || return 1

    safe_key=$(_awm_sanitize_key "$key")
    _awm_validate_storage_component "$safe_key" "checkpoint key" 128 || return 1
    if [[ "$safe_key" == *.lock ]]; then
        _awm_log error "awm_checkpoint: checkpoint keys ending in .lock are reserved"
        return 1
    fi
    _awm_validate_current_agent || return 1
    dir=$(_awm_session_dir)
    file="${dir}/data/${safe_key}"

    _awm_with_lock "${dir}/index/data.${safe_key}.lock" \
        _awm_checkpoint_write_unlocked \
        "$_AWM_SESSION_ID" "$key" "$value" "$importance" "$tags" "$ttl" "$file" || return 1
    _awm_update_manifest "$_AWM_SESSION_ID" "active" >/dev/null 2>&1 || true
    return 0
}

# Append a structured, attributed entry to a session log category.
# Usage: awm_log CATEGORY MESSAGE [--importance LEVEL] [--tags CSV]
awm_log() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_log: no active session"
        return 1
    fi
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    (( $# >= 2 )) || {
        _awm_log error "awm_log: category and message required"
        return 1
    }
    local category="$1"
    local message="$2"
    local importance="normal"
    local tags=""
    local safe_category
    shift 2

    while (( $# > 0 )); do
        case "$1" in
            --importance|--tags)
                (( $# >= 2 )) || {
                    _awm_log error "awm_log: $1 requires a value"
                    return 1
                }
                case "$1" in
                    --importance) importance="$2" ;;
                    --tags) tags="$2" ;;
                esac
                shift 2
                ;;
            *)
                _awm_log error "awm_log: unknown option $1"
                return 1
                ;;
        esac
    done

    [[ -n "$category" && -n "$message" ]] || {
        _awm_log error "awm_log: category and message required"
        return 1
    }
    _awm_require_payload_size "log category" "$category" || return 1
    _awm_require_payload_size "log message" "$message" || return 1
    _awm_validate_importance "$importance" || return 1
    _awm_require_payload_size "log tags" "$tags" || return 1

    safe_category=$(_awm_sanitize_name "$category")
    _awm_validate_storage_component "$safe_category" "log category" 128 || return 1
    _awm_validate_current_agent || return 1
    _awm_record_log_entry "$_AWM_SESSION_ID" "$safe_category" "$message" "$importance" "$tags" || return 1
    return 0
}

# Record task progress history and its latest structured state.
# Usage: awm_progress TASK CURRENT/TOTAL [STATUS]
awm_progress() {
    local task_id="${1:-}"
    local progress="${2:-}"
    local status_msg="${3:-}"
    local current total entry progress_file latest_file safe_task progress_checkpoint_key

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_progress: no active session"
        return 1
    fi
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    [[ -n "$task_id" && -n "$progress" ]] || {
        _awm_log error "awm_progress: task and progress required"
        return 1
    }
    _awm_require_payload_size "progress task" "$task_id" || return 1
    _awm_require_payload_size "progress value" "$progress" || return 1
    _awm_require_payload_size "progress status" "$status_msg" || return 1

    [[ "$progress" == */* ]] || {
        _awm_log error "awm_progress: progress must be current/total"
        return 1
    }
    current="${progress%/*}"
    total="${progress#*/}"
    current=$(_awm_parse_uint "$current" "progress current" 1000000000) || return 1
    total=$(_awm_parse_uint "$total" "progress total" 1000000000) || return 1
    safe_task=$(_awm_sanitize_key "$task_id")
    progress_checkpoint_key=$(_awm_sanitize_key "progress:${task_id}")
    _awm_validate_storage_component "$safe_task" "progress task" 128 || return 1
    _awm_validate_storage_component \
        "$progress_checkpoint_key" "progress checkpoint key" 128 || return 1
    _awm_validate_current_agent || return 1

    entry=$(printf '{"timestamp":"%s","ts":%s,"kind":"progress","task":"%s","importance":"high","tags":[],"source_agent":"%s","session_id":"%s","current":%s,"total":%s,"status":"%s"}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_timestamp)" \
        "$(_awm_json_escape "$task_id")" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$_AWM_SESSION_ID" \
        "$current" \
        "$total" \
        "$(_awm_json_escape "$status_msg")")

    progress_file="$(_awm_session_dir)/logs/progress.jsonl"
    latest_file=$(_awm_progress_index_file "$_AWM_SESSION_ID" "$task_id")

    _awm_locked_append "$progress_file" "$entry" || return 1
    _awm_locked_atomic_write "$latest_file" "$entry" || return 1
    _awm_update_category_index "$_AWM_SESSION_ID" "progress" || return 1
    _awm_journal_write "$_AWM_SESSION_ID" "progress" "$entry" || return 1
    awm_checkpoint "progress:${task_id}" "${current}/${total}" --importance high >/dev/null || return 1
    return 0
}

# Preserve an attributed high-signal finding for later agents and handoffs.
# Usage: awm_discovery TEXT [--importance LEVEL] [--tags CSV]
awm_discovery() {
    local insight="${1:-}"
    shift || true

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_discovery: no active session"
        return 1
    fi
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    [[ -n "$insight" ]] || {
        _awm_log error "awm_discovery: insight text required"
        return 1
    }
    _awm_require_payload_size "discovery" "$insight" || return 1

    local importance="high"
    local tags=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --importance)
                (( $# >= 2 )) || {
                    _awm_log error "awm_discovery: --importance requires a value"
                    return 1
                }
                importance="$2"
                shift 2
                ;;
            --tags)
                (( $# >= 2 )) || {
                    _awm_log error "awm_discovery: --tags requires a value"
                    return 1
                }
                tags="$2"
                shift 2
                ;;
            *)
                _awm_log error "awm_discovery: unknown option $1"
                return 1
                ;;
        esac
    done

    _awm_validate_importance "$importance" || return 1
    _awm_require_payload_size "discovery tags" "$tags" || return 1
    _awm_validate_current_agent || return 1

    _awm_record_discovery_entry "$_AWM_SESSION_ID" "$insight" "$importance" "$tags" || return 1
    _awm_update_manifest "$_AWM_SESSION_ID" "active" >/dev/null 2>&1 || true
    return 0
}

# =============================================================================
# CORE READ FUNCTIONS
# =============================================================================

# Retrieve checkpointed state from the active or explicitly named session.
# Usage: awm_get [SESSION_ID] KEY [DEFAULT]
awm_get() {
    local sid=""
    local key default safe_key dir file result metadata_rc

    if [[ $# -ge 2 ]] && _awm_session_exists "$1"; then
        sid="$1"
        shift
    fi

    key="${1:-}"
    default="${2:-}"

    if [[ -n "$sid" ]]; then
        dir=$(_awm_session_dir "$sid")
    elif [[ -n "$_AWM_SESSION_ID" ]]; then
        dir=$(_awm_session_dir)
    else
        printf '%s' "$default"
        return 1
    fi

    safe_key=$(_awm_sanitize_key "$key")
    _awm_validate_storage_component "$safe_key" "checkpoint key" 128 || {
        printf '%s' "$default"
        return 1
    }
    if [[ "$safe_key" == *.lock ]]; then
        printf '%s' "$default"
        return 1
    fi
    file="${dir}/data/${safe_key}"

    if [[ -f "$file" ]]; then
        if _awm_checkpoint_metadata "${sid:-$_AWM_SESSION_ID}" "$safe_key" "$file" \
            >/dev/null; then
            metadata_rc=0
        else
            metadata_rc=$?
        fi
        if (( metadata_rc != 0 )); then
            if (( metadata_rc == 2 )); then
                _awm_log warn "awm_get: checkpoint retention expired"
            else
                _awm_log error "awm_get: checkpoint metadata/value binding is invalid"
            fi
            printf '%s' "$default"
            return 1
        fi
        result=$(<"$file")
        printf '%s' "$result"
        return 0
    fi

    printf '%s' "$default"
    return 1
}

# Return the most recent entries in a log category as a JSON array.
# Usage: awm_recent CATEGORY [COUNT] [SESSION_ID]
awm_recent() {
    local category="${1:-}"
    local count="${2:-10}"
    local sid="${3:-$_AWM_SESSION_ID}"
    local safe_cat log_file lines

    [[ -n "$sid" ]] || {
        printf '[]'
        return 1
    }
    count=$(_awm_parse_uint "$count" "recent entry count" 1000000) || return 1

    safe_cat=$(_awm_sanitize_name "$category")
    _awm_validate_storage_component "$safe_cat" "log category" 128 || {
        printf '[]'
        return 1
    }
    if [[ "$safe_cat" == "discoveries" ]]; then
        log_file=$(_awm_discoveries_file "$sid")
    else
        log_file="$(_awm_session_dir "$sid")/logs/${safe_cat}.jsonl"
    fi

    [[ -f "$log_file" ]] || {
        printf '[]'
        return 0
    }

    mapfile -t lines < <(_awm_read_recent_lines "$log_file" "$count")
    printf '['
    local first=1
    local idx
    for ((idx=${#lines[@]}-1; idx>=0; idx--)); do
        [[ -n "${lines[$idx]}" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        first=0
        printf '%s' "${lines[$idx]}"
    done
    printf ']'
}

# Return a structured overview of the active AWM session.
# Usage: awm_summary [--tokens N]
awm_summary() {
    local max_tokens=0
    local sid="$_AWM_SESSION_ID"
    local dir discoveries progress checkpoints categories token_estimate

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tokens)
                max_tokens="${2:-0}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -n "$sid" ]] || {
        printf '{"error":"no active session"}'
        return 1
    }
    max_tokens=$(_awm_parse_uint "$max_tokens" "summary token budget" 1000000) || return 1

    dir=$(_awm_session_dir)
    discoveries=$(awm_recent "discoveries" "$AWM_CONTEXT_DISCOVERY_LIMIT")
    progress=$(_awm_progress_summary_json "$sid")

    checkpoints="{"
    local first=1 file key value escaped_key escaped_val
    for file in "${dir}/data"/*; do
        [[ -f "$file" ]] || continue
        [[ "${file##*/}" != *.lock ]] || continue
        key="${file##*/}"
        value=$(head -c 256 "$file")
        [[ $first -eq 1 ]] || checkpoints+=","
        first=0
        escaped_key=$(_awm_json_escape "$key")
        escaped_val=$(_awm_json_escape "$value")
        checkpoints+="\"${escaped_key}\":\"${escaped_val}\""
    done
    checkpoints+="}"

    categories="["
    first=1
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        [[ $first -eq 1 ]] || categories+=","
        first=0
        categories+="\"$(_awm_json_escape "$key")\""
    done < <(_awm_list_log_categories "$sid")
    categories+="]"

    token_estimate=$(awm_token_estimate 2>/dev/null || printf '0')

    printf '{"session_id":"%s","schema_version":%s,"status":"%s","namespace":"%s","backend":"%s","token_estimate":%s,"discoveries":%s,"progress":%s,"checkpoints":%s,"categories":%s,"max_tokens":%s}' \
        "$sid" \
        "${AWM_SCHEMA_VERSION}" \
        "$(_awm_json_escape "$(_awm_manifest_field "$sid" status)")" \
        "$(_awm_json_escape "${_AWM_NAMESPACE:-$(_awm_manifest_field "$sid" namespace)}")" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-$(_awm_manifest_field "$sid" backend)}")" \
        "$token_estimate" \
        "$discoveries" \
        "$progress" \
        "$checkpoints" \
        "$categories" \
        "${max_tokens:-0}"
}

# Search discoveries, checkpoints, and logs with deterministic ranking.
# Usage: awm_find QUERY [--kind KIND] [--limit N] [--session ID]
awm_find() {
    local query=""
    local kind="mixed"
    local limit="$AWM_FIND_DEFAULT_LIMIT"
    local sid="$_AWM_SESSION_ID"
    local tmpfile dir disc_file log_file file category content score payload preview key value
    local metadata ttl expires_at_epoch anonymous=false read_fd='' write_fd='' entries=0

    query="${1:-}"
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kind)
                kind="${2:-mixed}"
                shift 2
                ;;
            --limit)
                limit="${2:-$AWM_FIND_DEFAULT_LIMIT}"
                shift 2
                ;;
            --session)
                sid="${2:-$sid}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -n "$sid" ]] || {
        printf '[]'
        return 1
    }
    _awm_validate_session_id "$sid" || return 1
    limit=$(_awm_parse_uint "$limit" "find result limit" 100000) || return 1
    (( limit > 0 )) || {
        _awm_log error "awm_find: result limit must be greater than zero"
        return 1
    }

    dir=$(_awm_session_dir "$sid")
    if [[ "${AWM_ANONYMOUS_READS:-0}" == 1 ]]; then
        anonymous=true
        tmpfile="$(umask 077; mktemp "${TMPDIR:-/tmp}/awm-find.XXXXXX")" || return 1
        [[ -f "$tmpfile" && ! -L "$tmpfile" && -O "$tmpfile" ]] || return 1
        chmod 600 "$tmpfile" 2>/dev/null || { rm -f -- "$tmpfile"; return 1; }
        exec {read_fd}< "$tmpfile" || { rm -f -- "$tmpfile"; return 1; }
        exec {write_fd}> "$tmpfile" || {
            exec {read_fd}<&-
            rm -f -- "$tmpfile"
            return 1
        }
        # Both independent descriptors are open while the file is empty. Raw
        # candidates are written only after the pathname has been removed.
        rm -f -- "$tmpfile" || {
            exec {read_fd}<&-
            exec {write_fd}>&-
            return 1
        }
        tmpfile=''
    else
        tmpfile="$(mktemp "${TMPDIR:-/tmp}/awm-find.XXXXXX")"
    fi

    if [[ "$kind" == "mixed" || "$kind" == "discovery" ]]; then
        disc_file=$(_awm_discoveries_file "$sid")
        if [[ -f "$disc_file" ]]; then
            while IFS= read -r content; do
                [[ -n "$content" ]] || continue
                score=$(_awm_search_score "$query" "$content")
                [[ "$content" == *'"importance":"critical"'* ]] && score=$((score + 20))
                if [[ $score -gt 0 ]]; then
                    preview=$(sed -n 's/.*"discovery":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
                    payload=$(printf '{"kind":"discovery","score":%s,"title":"discovery","preview":"%s","source":"discoveries","session_id":"%s","entry":%s}' \
                        "$score" \
                        "$(_awm_json_escape "$preview")" \
                        "$sid" \
                        "$content")
                    if [[ "$anonymous" == true ]]; then
                        printf '%s\t%s\n' "$score" "$payload" >&"$write_fd"
                    else
                        printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
                    fi
                    entries=$((entries + 1))
                fi
            done < "$disc_file"
        fi
    fi

    if [[ "$kind" == "mixed" || "$kind" == "checkpoint" ]]; then
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            [[ "${file##*/}" != *.lock ]] || continue
            key="${file##*/}"
            metadata=$(_awm_checkpoint_metadata "$sid" "$key" "$file" 2>/dev/null) || continue
            ttl=$(printf '%s' "$metadata" | _awm_strict_jq -er \
                '.retention.ttl_seconds' 2>/dev/null) || continue
            expires_at_epoch=$(printf '%s' "$metadata" | _awm_strict_jq -r \
                'if .retention.expires_at_epoch == null then "null"
                 else (.retention.expires_at_epoch | tostring) end' 2>/dev/null) || continue
            value=$(head -c 512 "$file")
            content="${key} ${value}"
            score=$(_awm_search_score "$query" "$content")
            if [[ $score -gt 0 ]]; then
                payload=$(printf '{"kind":"checkpoint","score":%s,"title":"%s","preview":"%s","source":"data/%s","session_id":"%s","key":"%s","trust_label":"untrusted_legacy","authoritative":false,"provenance":{"source":"legacy_awm_v2","run_id":null,"call_id":null,"evidence_id":null,"input_digest":null},"retention":{"ttl_seconds":%s,"expires_at_epoch":%s}}' \
                    "$score" \
                    "$(_awm_json_escape "$key")" \
                    "$(_awm_json_escape "$value")" \
                    "$(_awm_json_escape "$key")" \
                    "$sid" \
                    "$(_awm_json_escape "$key")" \
                    "$ttl" \
                    "$expires_at_epoch")
                if [[ "$anonymous" == true ]]; then
                    printf '%s\t%s\n' "$score" "$payload" >&"$write_fd"
                else
                    printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
                fi
                entries=$((entries + 1))
            fi
        done
    fi

    if [[ "$kind" == "mixed" || "$kind" == "log" ]]; then
        for log_file in "${dir}/logs/"*.jsonl; do
            [[ -f "$log_file" ]] || continue
            category=$(basename "$log_file" .jsonl)
            [[ "$category" == "discoveries" ]] && continue
            while IFS= read -r content; do
                [[ -n "$content" ]] || continue
                score=$(_awm_search_score "$query" "${category} ${content}")
                [[ "$content" == *'"importance":"critical"'* ]] && score=$((score + 10))
                if [[ $score -gt 0 ]]; then
                    preview=$(sed -n 's/.*"msg":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
                    [[ -n "$preview" ]] || preview="$content"
                    payload=$(printf '{"kind":"log","score":%s,"title":"%s","preview":"%s","source":"logs/%s.jsonl","session_id":"%s","category":"%s","entry":%s}' \
                        "$score" \
                        "$(_awm_json_escape "$category")" \
                        "$(_awm_json_escape "${preview:0:256}")" \
                        "$(_awm_json_escape "$category")" \
                        "$sid" \
                        "$(_awm_json_escape "$category")" \
                        "$content")
                    if [[ "$anonymous" == true ]]; then
                        printf '%s\t%s\n' "$score" "$payload" >&"$write_fd"
                    else
                        printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
                    fi
                    entries=$((entries + 1))
                fi
            done < "$log_file"
        done
    fi

    if (( entries == 0 )); then
        if [[ "$anonymous" == true ]]; then
            exec {read_fd}<&-
            exec {write_fd}>&-
        else
            rm -f "$tmpfile" 2>/dev/null
        fi
        printf '[]'
        return 0
    fi

    if [[ "$anonymous" == true ]]; then
        exec {write_fd}>&-
        _awm_select_top_results_fd "$read_fd" "$limit"
        exec {read_fd}<&-
    else
        _awm_select_top_results "$tmpfile" "$limit" "$query"
        rm -f "$tmpfile" 2>/dev/null
    fi
}

# Build task-specific AWM context in JSON or prompt format.
# Usage: awm_context_for TASK [--tokens N] [--format json|prompt] [--include LIST]
awm_context_for() {
    local task="${1:-subtask}"
    shift || true
    local max_tokens=0
    local format="json"
    local include="discoveries,progress,checkpoints,logs"
    local discoveries='[]'
    local progress='{}'
    local checkpoints='[]'
    local logs='[]'
    local related='[]'
    local summary='{}'
    local max_chars document actual_chars truncated=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tokens)
                max_tokens="${2:-0}"
                shift 2
                ;;
            --format)
                format="${2:-json}"
                shift 2
                ;;
            --include)
                include="${2:-$include}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -n "$_AWM_SESSION_ID" ]] || {
        printf '{"error":"no active session"}'
        return 1
    }

    max_tokens=$(_awm_parse_uint "$max_tokens" "context token budget" 1000000) || return 1
    AWM_CHARS_PER_TOKEN=$(_awm_parse_uint "$AWM_CHARS_PER_TOKEN" "characters per token" 1024) || return 1
    if [[ "$AWM_CHARS_PER_TOKEN" -eq 0 ]]; then
        _awm_log error "characters per token must be greater than zero"
        return 1
    fi
    if [[ "$max_tokens" -eq 0 ]]; then
        if declare -F awm_budget_remaining >/dev/null 2>&1; then
            max_tokens=$(awm_budget_remaining 2>/dev/null || printf '%s' "$AWM_CONTEXT_DEFAULT_TOKENS")
        else
            max_tokens="$AWM_CONTEXT_DEFAULT_TOKENS"
        fi
        max_tokens=$(_awm_parse_uint "$max_tokens" "context token budget" 1000000) || return 1
        if [[ "$max_tokens" -eq 0 ]]; then
            max_tokens=$(_awm_parse_uint "$AWM_CONTEXT_DEFAULT_TOKENS" "default context token budget" 1000000) || return 1
        fi
    fi
    case "$format" in
        json|prompt) ;;
        *)
            _awm_log error "awm_context_for: format must be json or prompt"
            return 1
            ;;
    esac
    max_chars=$((max_tokens * AWM_CHARS_PER_TOKEN))

    if [[ "$include" == *discoveries* ]]; then
        discoveries=$(awm_recent "discoveries" "$AWM_CONTEXT_DISCOVERY_LIMIT")
    fi
    if [[ "$include" == *progress* ]]; then
        progress=$(_awm_progress_summary_json "$_AWM_SESSION_ID")
    fi
    if [[ "$include" == *checkpoints* ]]; then
        checkpoints=$(awm_find "$task" --kind checkpoint --limit 6)
    fi
    if [[ "$include" == *logs* ]]; then
        logs=$(awm_find "$task" --kind log --limit "$AWM_CONTEXT_LOG_LIMIT")
    fi
    related=$(awm_find "$task" --kind mixed --limit 6)
    summary=$(awm_summary --tokens "$max_tokens")

    document=$(_awm_finalize_context_document "$format" \
        "$task" "$max_tokens" "$max_chars" \
        "$discoveries" "$progress" "$checkpoints" "$logs" \
        "$related" "$summary" false)
    actual_chars=$(_awm_string_bytes "$document")

    if (( actual_chars > max_chars )); then
        truncated=true
        summary='{}'
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        logs='[]'
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        related='[]'
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        checkpoints='[]'
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        progress='{}'
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        discoveries=$(_awm_compact_critical_discoveries)
        document=$(_awm_finalize_context_document "$format" \
            "$task" "$max_tokens" "$max_chars" \
            "$discoveries" "$progress" "$checkpoints" "$logs" \
            "$related" "$summary" "$truncated")
        actual_chars=$(_awm_string_bytes "$document")
    fi
    if (( actual_chars > max_chars )); then
        _awm_log error "awm_context_for: token budget is too small for required identity and critical provenance"
        return 1
    fi

    printf '%s' "$document"
}

# =============================================================================
# MANAGEMENT AND INSPECTION
# =============================================================================

# Report structured counts and status for an AWM session.
# Usage: awm_status [SESSION_ID]
awm_status() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir discoveries_count handoff_count checkpoint_count log_count token_estimate manifest status namespace backend schema_version

    [[ -n "$sid" ]] || {
        printf '{"error":"no active session"}'
        return 1
    }

    dir=$(_awm_session_dir "$sid")
    manifest=$(_awm_manifest_path "$sid")
    status=$(_awm_manifest_field "$sid" status)
    namespace=$(_awm_manifest_field "$sid" namespace)
    backend=$(_awm_manifest_field "$sid" backend)
    schema_version=$(_awm_manifest_number_field "$sid" schema_version)
    [[ -z "$schema_version" ]] && schema_version=1

    discoveries_count=$(_awm_line_count "$(_awm_discoveries_file "$sid")")
    handoff_count=$(find "${dir}/handoffs" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    checkpoint_count=$(find "${dir}/data" -type f ! -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')
    log_count=$(find "${dir}/logs" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
    token_estimate=$(if [[ "$sid" == "$_AWM_SESSION_ID" ]]; then awm_token_estimate 2>/dev/null; else _awm_with_session "$sid" awm_token_estimate 2>/dev/null; fi)

    printf '{"session_id":"%s","schema_version":%s,"status":"%s","namespace":"%s","backend":"%s","manifest":"%s","discoveries":%s,"checkpoints":%s,"handoffs":%s,"logs":%s,"token_estimate":%s}' \
        "$sid" \
        "$schema_version" \
        "$(_awm_json_escape "$status")" \
        "$(_awm_json_escape "$namespace")" \
        "$(_awm_json_escape "${backend:-file}")" \
        "$(_awm_json_escape "$manifest")" \
        "$discoveries_count" \
        "${checkpoint_count:-0}" \
        "${handoff_count:-0}" \
        "${log_count:-0}" \
        "${token_estimate:-0}"
}

# Diagnose AWM layout, schema, privacy modes, symlinks, locks, and backend.
# Usage: awm_doctor [SESSION_ID]
awm_doctor() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir manifest issues="[" first=1 schema_version layout_ok=1
    local private_modes=1 symlink_free=1 path mode symlink

    _awm_validate_session_id "$sid" || {
        printf '{"error":"no active session"}'
        return 1
    }

    dir=$(_awm_session_dir "$sid") || return 1
    manifest=$(_awm_manifest_path "$sid")
    schema_version=$(_awm_manifest_number_field "$sid" schema_version)
    [[ -z "$schema_version" ]] && schema_version=1

    for required in "$manifest" "${dir}/data" "${dir}/logs" "${dir}/checkpoints" "${dir}/handoffs" "${dir}/index" "${dir}/journal"; do
        if [[ ! -e "$required" ]]; then
            layout_ok=0
            [[ $first -eq 1 ]] || issues+=","
            first=0
            issues+="\"missing:${required}\""
        fi
    done
    if [[ "$schema_version" -lt "$AWM_SCHEMA_VERSION" ]]; then
        [[ $first -eq 1 ]] || issues+=","
        first=0
        issues+="\"schema_outdated:${schema_version}\""
    fi

    if [[ -d "$dir" ]]; then
        symlink=$(find "$dir" -type l -print -quit 2>/dev/null)
        if [[ -n "$symlink" ]]; then
            symlink_free=0
            [[ $first -eq 1 ]] || issues+=","
            first=0
            issues+="\"symlink_present:$(_awm_json_escape "$symlink")\""
        fi
        for path in "${AWM_ROOT%/}" "${AWM_ROOT%/}/sessions" "${dir%/*}"; do
            [[ -d "$path" ]] || continue
            mode=$(_awm_path_mode "$path")
            if [[ "$mode" != "700" ]]; then
                private_modes=0
                break
            fi
        done
        while [[ $private_modes -eq 1 ]] && IFS= read -r path; do
            [[ -n "$path" ]] || continue
            mode=$(_awm_path_mode "$path")
            if [[ "$mode" != "700" ]]; then
                private_modes=0
                break
            fi
        done < <(find "$dir" -type d -print 2>/dev/null)
        if [[ $private_modes -eq 1 ]]; then
            while IFS= read -r path; do
                [[ -n "$path" ]] || continue
                mode=$(_awm_path_mode "$path")
                if [[ "$mode" != "600" ]]; then
                    private_modes=0
                    break
                fi
            done < <(find "$dir" -type f -print 2>/dev/null)
        fi
        if [[ $private_modes -eq 0 ]]; then
            [[ $first -eq 1 ]] || issues+=","
            first=0
            issues+='"non_private_mode"'
        fi
    fi
    issues+="]"

    printf '{"session_id":"%s","schema_version":%s,"expected_schema":%s,"layout_ok":%s,"private_modes":%s,"symlink_free":%s,"lock_strategy":"%s","backend":"%s","issues":%s}' \
        "$sid" \
        "$schema_version" \
        "$AWM_SCHEMA_VERSION" \
        "$([[ $layout_ok -eq 1 ]] && echo true || echo false)" \
        "$([[ $private_modes -eq 1 ]] && echo true || echo false)" \
        "$([[ $symlink_free -eq 1 ]] && echo true || echo false)" \
        "$(_awm_lock_strategy)" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-$(_awm_manifest_field "$sid" backend)}")" \
        "$issues"
}

# Upgrade legacy AWM layout and permissions without rewriting current sessions.
# Usage: awm_migrate SESSION_ID | --all
awm_migrate() {
    local target="${1:-$_AWM_SESSION_ID}"
    local sid count=0

    if [[ "$target" == "--all" ]]; then
        while IFS= read -r sid; do
            [[ -n "$sid" ]] || continue
            _awm_session_is_project_reserved "$sid" && continue
            awm_migrate "$sid" >/dev/null || return 1
            count=$((count + 1))
        done < <(awm_list_sessions)
        printf '%s' "$count"
        return 0
    fi

    _awm_validate_session_id "$target" || return 1
    _awm_require_project_mutation_authorization "$target" || return 1

    local dir manifest manifest_content name parent status namespace model backend created_at created_epoch
    local discoveries_old discoveries_new schema_before migration_changed=0 required
    dir=$(_awm_find_session_dir "$target") || {
        _awm_log error "awm_migrate: session not found: $target"
        return 1
    }
    _AWM_SESSION_DIR="$dir"

    manifest="${dir}/manifest.json"
    schema_before=$(_awm_manifest_number_field "$target" schema_version)
    manifest_content=$(<"$manifest")
    if [[ "${schema_before:-0}" -ne "$AWM_SCHEMA_VERSION" || \
          "$manifest_content" != *'"backend":'* || \
          "$manifest_content" != *'"namespace":'* ]]; then
        migration_changed=1
    fi
    for required in "${dir}/handoffs" "${dir}/index" "${dir}/journal" "${dir}/discoveries.jsonl"; do
        [[ -e "$required" ]] || migration_changed=1
    done

    _awm_ensure_session_layout "$target" || return 1
    name=$(_awm_manifest_field "$target" name)
    parent=$(_awm_manifest_field "$target" parent_session)
    status=$(_awm_manifest_field "$target" status)
    namespace=$(_awm_manifest_field "$target" namespace)
    model=$(_awm_manifest_field "$target" model)
    backend=$(_awm_manifest_field "$target" backend)
    created_at=$(_awm_manifest_field "$target" created_at)
    created_epoch=$(_awm_manifest_number_field "$target" created_epoch)
    [[ -n "$status" ]] || status="active"
    [[ -n "$backend" ]] || backend="file"
    if [[ -n "$namespace" ]]; then
        _awm_validate_component "$namespace" "namespace" || return 1
    fi

    discoveries_old="${dir}/logs/discoveries.jsonl"
    discoveries_new="${dir}/discoveries.jsonl"
    if [[ ! -s "$discoveries_new" && -s "$discoveries_old" ]]; then
        cp -f "$discoveries_old" "$discoveries_new" 2>/dev/null || true
        migration_changed=1
    elif [[ ! -s "$discoveries_old" && -s "$discoveries_new" ]]; then
        cp -f "$discoveries_new" "$discoveries_old" 2>/dev/null || true
        migration_changed=1
    fi
    _awm_secure_session_tree "$dir" || return 1

    if [[ $migration_changed -eq 1 ]]; then
        _awm_update_manifest "$target" "$status" "$created_at" "$created_epoch" "$name" "$parent" "$namespace" "$model" "$backend" || return 1
        _awm_journal_write "$target" "migrate" "{\"schema_version\":${AWM_SCHEMA_VERSION}}"
    fi
    printf '%s' "$target"
}

# Rotate oversized non-discovery logs for a durable AWM session.
# Usage: awm_compress [SESSION_ID]
awm_compress() {
    local session_id="${1:-$_AWM_SESSION_ID}"
    local dir log_file category

    [[ -n "$session_id" ]] || {
        _awm_log error "awm_compress: no session specified"
        return 1
    }
    _awm_require_project_mutation_authorization "$session_id" || return 1

    dir=$(_awm_session_dir "$session_id")
    for log_file in "${dir}/logs/"*.jsonl; do
        [[ -f "$log_file" ]] || continue
        category=$(basename "$log_file" .jsonl)
        [[ "$category" == "discoveries" ]] && continue
        _awm_compress_log "$category" "$session_id"
    done
    return 0
}

_awm_compress_log_unlocked() {
    local category="$1"
    local session_id="${2:-$_AWM_SESSION_ID}"
    local dir log_file line_count archive_count keep max_entries
    local tmpfile archive_tmp archive_file

    dir=$(_awm_session_dir "$session_id")
    log_file="${dir}/logs/${category}.jsonl"
    [[ -f "$log_file" ]] || return 0

    max_entries=$(_awm_parse_uint "$AWM_MAX_LOG_ENTRIES" "maximum log entries" 1000000) || return 1
    keep=$(_awm_parse_uint "${AWM_LOG_KEEP_RECENT:-50}" "recent log entries to keep" 1000000) || return 1
    line_count=$(_awm_line_count "$log_file")
    if (( line_count <= max_entries )); then
        return 0
    fi

    (( keep > line_count )) && keep="$line_count"
    archive_count=$((line_count - keep))
    (( archive_count > 0 )) || return 0
    archive_file="${dir}/logs/${category}.archive.jsonl"
    _awm_reject_symlink_components "$log_file" || return 1
    [[ ! -L "$log_file" && ! -L "$archive_file" ]] || return 1
    [[ ! -e "$archive_file" ]] || chmod 600 "$archive_file" 2>/dev/null || return 1
    tmpfile=$( (umask 077; mktemp "${log_file}.tmp.XXXXXX") ) || return 1
    archive_tmp=$( (umask 077; mktemp "${archive_file}.tmp.XXXXXX") ) || {
        rm -f -- "$tmpfile" 2>/dev/null
        return 1
    }

    # Write the archive first from a de-duplicated merge. If the process dies
    # before the active log is replaced, retrying the rotation remains
    # idempotent; if it dies earlier, the original active log is untouched.
    if ! (umask 077; {
        [[ ! -f "$archive_file" ]] || cat "$archive_file"
        head -n "$archive_count" "$log_file"
    } | awk '!seen[$0]++' > "$archive_tmp"); then
        rm -f -- "$tmpfile" "$archive_tmp" 2>/dev/null
        return 1
    fi
    if ! tail -n "$keep" "$log_file" > "$tmpfile"; then
        rm -f -- "$tmpfile" "$archive_tmp" 2>/dev/null
        return 1
    fi
    chmod 600 "$archive_tmp" "$tmpfile" 2>/dev/null || {
        rm -f -- "$tmpfile" "$archive_tmp" 2>/dev/null
        return 1
    }
    mv -f -- "$archive_tmp" "$archive_file" || {
        rm -f -- "$tmpfile" "$archive_tmp" 2>/dev/null
        return 1
    }
    mv -f -- "$tmpfile" "$log_file" || {
        rm -f -- "$tmpfile" 2>/dev/null
        return 1
    }
    chmod 600 "$archive_file" "$log_file" 2>/dev/null || return 1
    _awm_journal_write "$session_id" "compress" "{\"category\":\"$(_awm_json_escape "$category")\",\"archived\":${archive_count}}" || return 1
}

_awm_append_log_entry_unlocked() {
    local log_file="$1"
    local entry="$2"
    local category="$3"
    local session_id="$4"

    _awm_append_unlocked "$log_file" "$entry" || return 1
    if [[ "$category" != "progress" && "$category" != "discoveries" ]]; then
        _awm_compress_log_unlocked "$category" "$session_id" || return 1
    fi
}

_awm_compress_log() {
    local category="$1"
    local session_id="${2:-$_AWM_SESSION_ID}"
    local log_file

    _awm_validate_session_id "$session_id" || return 1
    _awm_require_project_mutation_authorization "$session_id" || return 1
    _awm_validate_component "$category" "log category" || return 1
    log_file="$(_awm_session_dir "$session_id")/logs/${category}.jsonl"
    _awm_with_lock "${log_file}.lock" _awm_compress_log_unlocked "$category" "$session_id"
}

# Export the active session as a private Markdown file.
# Usage: awm_export [PATH]
awm_export() {
    local output_file="${1:-}"
    local dir disc_file file key value

    [[ -n "$_AWM_SESSION_ID" ]] || {
        _awm_log error "awm_export: no active session"
        return 1
    }
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    dir=$(_awm_session_dir)
    [[ -n "$output_file" ]] || output_file="${dir}/export.md"
    disc_file=$(_awm_discoveries_file)

    if [[ -L "$output_file" ]]; then
        _awm_log error "awm_export: refusing symbolic-link target"
        return 1
    fi
    if [[ -e "$output_file" ]]; then
        [[ -f "$output_file" ]] || return 1
        chmod 600 "$output_file" 2>/dev/null || return 1
    fi

    (umask 077; {
        printf '# AWM Session Export\n\n'
        printf '- Session ID: `%s`\n' "$_AWM_SESSION_ID"
        printf '- Exported: `%s`\n' "$(_awm_iso_timestamp)"
        printf '- Schema Version: `%s`\n\n' "$AWM_SCHEMA_VERSION"

        printf '## Status\n\n'
        awm_status
        printf '\n\n'

        printf '## Discoveries\n\n'
        if [[ -f "$disc_file" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                if [[ "$line" =~ \"discovery\":\"([^\"]+)\" ]]; then
                    printf '- %s\n' "${BASH_REMATCH[1]}"
                fi
            done < "$disc_file"
        fi
        printf '\n'

        printf '## Checkpoints\n\n'
        printf '| Key | Value |\n|---|---|\n'
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            [[ "${file##*/}" != *.lock ]] || continue
            key="${file##*/}"
            value=$(head -c 120 "$file" | tr '\n' ' ')
            printf '| %s | %s |\n' "$key" "$value"
        done
        printf '\n'

        printf '## Summary\n\n'
        awm_summary
        printf '\n'
    } > "$output_file") || return 1
    chmod 600 "$output_file" 2>/dev/null || return 1

    printf '%s' "$output_file"
}

awm_inherit() {
    local parent_session="$1"
    local name="${2:-child}"
    awm_init "$name" --parent "$parent_session"
}

awm_token_estimate() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir total_bytes=0 file

    [[ -n "$sid" ]] || {
        printf '0'
        return 1
    }

    local chars_per_token
    chars_per_token=$(_awm_parse_uint "$AWM_CHARS_PER_TOKEN" "characters per token" 1024) || return 1
    (( chars_per_token > 0 )) || return 1
    dir=$(_awm_session_dir "$sid")

    for file in "${dir}/data/"* "${dir}/logs/"*.jsonl "${dir}/discoveries.jsonl"; do
        [[ -f "$file" ]] || continue
        [[ "$file" != "${dir}/data/"*.lock ]] || continue
        total_bytes=$((total_bytes + $(_awm_file_size "$file")))
    done

    printf '%d' "$((total_bytes / chars_per_token))"
}

awm_estimate_read() {
    local operation="${1:-}"
    shift || true
    local bytes=0 dir file category count key chars_per_token default_tokens

    [[ -n "$_AWM_SESSION_ID" ]] || {
        printf '0'
        return 1
    }

    chars_per_token=$(_awm_parse_uint "$AWM_CHARS_PER_TOKEN" "characters per token" 1024) || return 1
    (( chars_per_token > 0 )) || return 1
    dir=$(_awm_session_dir)

    case "$operation" in
        summary)
            bytes=$(_awm_file_size "$(_awm_discoveries_file)")
            for file in "${dir}/data/"*; do
                [[ -f "$file" ]] || continue
                [[ "${file##*/}" != *.lock ]] || continue
                bytes=$((bytes + $(head -c 256 "$file" | wc -c | tr -d ' ')))
            done
            ;;
        recent)
            category="${1:-log}"
            count="${2:-10}"
            count=$(_awm_parse_uint "$count" "estimated recent entry count" 1000000) || return 1
            file="${dir}/logs/$(_awm_sanitize_name "$category").jsonl"
            if [[ "$category" == "discoveries" ]]; then
                file="$(_awm_discoveries_file)"
            fi
            if [[ -f "$file" ]]; then
                local total_size line_count avg_line
                total_size=$(_awm_file_size "$file")
                line_count=$(_awm_line_count "$file")
                [[ $line_count -eq 0 ]] && line_count=1
                avg_line=$((total_size / line_count))
                bytes=$((avg_line * count))
            fi
            ;;
        get)
            key="$(_awm_sanitize_key "${1:-}")"
            file="${dir}/data/${key}"
            bytes=$(_awm_file_size "$file")
            ;;
        context_for)
            default_tokens=$(_awm_parse_uint "$AWM_CONTEXT_DEFAULT_TOKENS" "default context token budget" 1000000) || return 1
            bytes=$((default_tokens * chars_per_token))
            ;;
    esac

    printf '%d' "$((bytes / chars_per_token))"
}

awm_list() {
    local filter_status=""
    local exclude_namespace=""
    local as_json=0
    local session_dir manifest id content name status created_at namespace first=1

    _awm_validate_root || return 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                filter_status="${2:-}"
                shift 2
                ;;
            --active)
                filter_status="active"
                shift
                ;;
            --completed)
                filter_status="completed"
                shift
                ;;
            --exclude-namespace)
                [[ $# -ge 2 ]] || {
                    _awm_log error "awm_list: --exclude-namespace requires a value"
                    return 2
                }
                exclude_namespace="$2"
                _awm_validate_component "$exclude_namespace" "excluded namespace" || return 2
                shift 2
                ;;
            --json)
                as_json=1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $as_json -eq 1 ]]; then
        printf '['
    fi

    for session_dir in "${AWM_ROOT}/sessions/"* "${AWM_ROOT}/sessions/"*/*; do
        [[ -d "$session_dir" && ! -L "$session_dir" ]] || continue
        manifest="${session_dir}/manifest.json"
        [[ -f "$manifest" && ! -L "$manifest" ]] || continue
        _awm_reject_symlink_components "$manifest" || continue

        id="${session_dir##*/}"
        _awm_validate_session_id "$id" 1 || continue
        content=$(<"$manifest")
        name=$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        status=$(sed -n 's/.*"status":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        created_at=$(sed -n 's/.*"created_at":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        namespace=$(sed -n 's/.*"namespace":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)

        if [[ -n "$exclude_namespace" ]]; then
            if [[ "$exclude_namespace" == "projects" ]] && _awm_session_is_project_reserved "$id"; then
                continue
            fi
            if [[ "$namespace" == "$exclude_namespace" ]]; then
                continue
            fi
        fi

        if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
            continue
        fi

        if [[ $as_json -eq 1 ]]; then
            [[ $first -eq 1 ]] || printf ','
            first=0
            printf '{"session_id":"%s","name":"%s","status":"%s","created_at":"%s","namespace":"%s"}' \
                "$id" \
                "$(_awm_json_escape "$name")" \
                "$(_awm_json_escape "$status")" \
                "$(_awm_json_escape "$created_at")" \
                "$(_awm_json_escape "$namespace")"
        else
            printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$status" "$created_at"
        fi
    done

    [[ $as_json -eq 1 ]] && printf ']'
    return 0
}

awm_list_sessions() {
    awm_list | while IFS=$'\t' read -r sid _; do
        [[ -n "$sid" ]] && printf '%s\n' "$sid"
    done
}

awm_cleanup() {
    local max_days="7"
    local now max_seconds cleaned=0 session_dir manifest content created_epoch age

    if [[ $# -gt 0 ]]; then
        case "$1" in
            --older-than)
                max_days="${2:-7}"
                ;;
            *)
                max_days="$1"
                ;;
        esac
    fi

    max_days=$(_awm_parse_uint "$max_days" "cleanup age in days" 36500) || return 1
    _awm_validate_root || return 1
    now=$(_awm_epoch)
    max_seconds=$((max_days * 86400))

    for session_dir in "${AWM_ROOT}/sessions/"* "${AWM_ROOT}/sessions/"*/*; do
        [[ -d "$session_dir" && ! -L "$session_dir" ]] || continue
        manifest="${session_dir}/manifest.json"
        [[ -f "$manifest" && ! -L "$manifest" ]] || continue
        _awm_validate_session_id "${session_dir##*/}" 1 || continue
        _awm_session_is_project_reserved "${session_dir##*/}" && continue
        _awm_reject_symlink_components "$manifest" || continue
        content=$(<"$manifest")
        [[ "$content" == *'"status":"completed"'* ]] || continue
        created_epoch=$(sed -n 's/.*"created_epoch":\([0-9][0-9]*\).*/\1/p' <<<"$content" | head -n 1)
        [[ -n "$created_epoch" ]] || continue
        age=$((now - created_epoch))
        if [[ $age -gt $max_seconds ]]; then
            rm -rf -- "$session_dir"
            cleaned=$((cleaned + 1))
        fi
    done

    printf '%d' "$cleaned"
}

awm_check_limits() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir total_size=0 max_size tokens max_tokens file

    [[ -n "$sid" ]] || return 0
    dir=$(_awm_session_dir "$sid")

    for file in "${dir}/data/"* "${dir}/logs/"*.jsonl "${dir}/discoveries.jsonl"; do
        [[ -f "$file" ]] || continue
        [[ "$file" != "${dir}/data/"*.lock ]] || continue
        total_size=$((total_size + $(_awm_file_size "$file")))
    done

    max_size=$((10 * 1024 * 1024))
    tokens=$(if [[ "$sid" == "$_AWM_SESSION_ID" ]]; then awm_token_estimate; else _awm_with_session "$sid" awm_token_estimate; fi)
    max_tokens=50000

    [[ $total_size -le $max_size && ${tokens:-0} -le $max_tokens ]]
}

# =============================================================================
# HANDOFFS
# =============================================================================

_awm_render_handoff_json() {
    local target="$1" handoff_id="$2" created_at="$3"
    local requested_tokens="$4" max_chars="$5" budget_remaining="$6"
    local status_json="$7" open_questions="$8" context="$9"
    local truncated="${10}" actual_chars="${11}" actual_tokens="${12}"

    printf '{"type":"handoff","handoff_id":"%s","created_at":"%s","parent_session":"%s","parent_agent":"%s","target_agent":"%s","budget_remaining":%s,"provenance":{"schema_version":%s,"namespace":"%s","backend":"%s"},"budget":{"requested_tokens":%s,"chars_per_token":%s,"max_chars":%s,"actual_chars":%s,"actual_tokens":%s,"truncated":%s},"status":%s,"open_questions":%s,"context":%s}' \
        "$(_awm_json_escape "$handoff_id")" \
        "$(_awm_json_escape "$created_at")" \
        "$(_awm_json_escape "$_AWM_SESSION_ID")" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$(_awm_json_escape "$target")" \
        "$budget_remaining" \
        "$AWM_SCHEMA_VERSION" \
        "$(_awm_json_escape "${_AWM_NAMESPACE:-}")" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-file}")" \
        "$requested_tokens" \
        "$AWM_CHARS_PER_TOKEN" \
        "$max_chars" \
        "$actual_chars" \
        "$actual_tokens" \
        "$truncated" \
        "$status_json" \
        "$open_questions" \
        "$context"
}

_awm_finalize_handoff_json() {
    local target="$1" handoff_id="$2" created_at="$3"
    local requested_tokens="$4" max_chars="$5" budget_remaining="$6"
    local status_json="$7" open_questions="$8" context="$9" truncated="${10}"
    local actual_chars=0 actual_tokens=0 next_chars next_tokens document iteration

    for ((iteration = 0; iteration < 6; iteration++)); do
        document=$(_awm_render_handoff_json \
            "$target" "$handoff_id" "$created_at" \
            "$requested_tokens" "$max_chars" "$budget_remaining" \
            "$status_json" "$open_questions" "$context" "$truncated" \
            "$actual_chars" "$actual_tokens")
        next_chars=$(_awm_string_bytes "$document")
        next_tokens=$(_awm_tokens_for_chars "$next_chars")
        if [[ "$next_chars" -eq "$actual_chars" && "$next_tokens" -eq "$actual_tokens" ]]; then
            printf '%s' "$document"
            return 0
        fi
        actual_chars="$next_chars"
        actual_tokens="$next_tokens"
    done

    _awm_render_handoff_json \
        "$target" "$handoff_id" "$created_at" \
        "$requested_tokens" "$max_chars" "$budget_remaining" \
        "$status_json" "$open_questions" "$context" "$truncated" \
        "$actual_chars" "$actual_tokens"
}

# Prepare a budget-aware AWM handoff package for a receiving agent.
# Usage: awm_handoff_prepare TARGET [--tokens N] [--format json|prompt]
awm_handoff_prepare() {
    local target="${1:-}"
    shift || true
    local max_tokens=0
    local format="json"
    local context open_questions handoff_id handoff_file package budget_remaining status_json
    local max_chars context_tokens candidate_chars reduction truncated=false nested_truncated=false

    [[ -n "$target" ]] || {
        _awm_log error "awm_handoff_prepare: target agent required"
        return 1
    }
    _awm_require_payload_size "handoff target" "$target" || return 1

    [[ -n "$_AWM_SESSION_ID" ]] || {
        _awm_log error "awm_handoff_prepare: no active session"
        return 1
    }
    _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tokens)
                max_tokens="${2:-0}"
                shift 2
                ;;
            --format)
                format="${2:-json}"
                shift 2
                ;;
            *)
                _awm_log error "awm_handoff_prepare: unknown option $1"
                return 1
                ;;
        esac
    done

    max_tokens=$(_awm_parse_uint "$max_tokens" "handoff token budget" 1000000) || return 1
    if (( max_tokens == 0 )); then
        if declare -F awm_budget_remaining >/dev/null 2>&1; then
            max_tokens=$(awm_budget_remaining 2>/dev/null || printf '%s' "$AWM_CONTEXT_DEFAULT_TOKENS")
        else
            max_tokens="$AWM_CONTEXT_DEFAULT_TOKENS"
        fi
    fi

    max_tokens=$(_awm_parse_uint "$max_tokens" "handoff token budget" 1000000) || return 1
    (( max_tokens > 0 )) || {
        _awm_log error "awm_handoff_prepare: token budget must be greater than zero"
        return 1
    }
    AWM_CHARS_PER_TOKEN=$(_awm_parse_uint "$AWM_CHARS_PER_TOKEN" "AWM_CHARS_PER_TOKEN" 64) || return 1
    (( AWM_CHARS_PER_TOKEN > 0 )) || {
        _awm_log error "awm_handoff_prepare: AWM_CHARS_PER_TOKEN must be greater than zero"
        return 1
    }
    case "$format" in
        json|prompt) ;;
        *)
            _awm_log error "awm_handoff_prepare: format must be json or prompt"
            return 1
            ;;
    esac
    _awm_validate_current_agent || return 1
    handoff_id="handoff_$(_awm_epoch)_$(_awm_sanitize_name "$target")"
    _awm_validate_storage_component \
        "${handoff_id}.json" "handoff file name" 128 || return 1

    max_chars=$((max_tokens * AWM_CHARS_PER_TOKEN))

    open_questions=$(awm_recent "questions" 10)
    budget_remaining=$(if declare -F awm_budget_remaining >/dev/null 2>&1; then awm_budget_remaining 2>/dev/null; else printf '%s' "$max_tokens"; fi)
    budget_remaining=$(_awm_parse_uint "${budget_remaining:-0}" "remaining token budget" 1000000) || budget_remaining=0
    status_json=$(awm_status)
    handoff_file="$(_awm_handoff_dir)/${handoff_id}.json"
    context_tokens="$max_tokens"

    # Start with the complete package. If it does not fit, remove derivative
    # status/question summaries and deterministically shrink the nested context.
    # Identity, provenance, and critical discoveries are protected by
    # awm_context_for itself; if those cannot fit, fail without persisting a
    # misleading partial handoff.
    context=$(awm_context_for "$target" --tokens "$context_tokens" --format json) || return 1
    [[ "$context" == *'"truncated":true'* ]] && nested_truncated=true
    [[ "$nested_truncated" == "true" ]] && truncated=true
    package=$(_awm_finalize_handoff_json \
        "$target" "$handoff_id" "$(_awm_iso_timestamp)" \
        "$max_tokens" "$max_chars" "$budget_remaining" \
        "$status_json" "$open_questions" "$context" "$truncated")
    candidate_chars=$(_awm_string_bytes "$package")

    if (( candidate_chars > max_chars )); then
        truncated=true
        status_json='{}'
        open_questions='[]'
        while (( context_tokens > 0 )); do
            context=$(awm_context_for "$target" --tokens "$context_tokens" --format json 2>/dev/null) || {
                context_tokens=$((context_tokens - 1))
                continue
            }
            package=$(_awm_finalize_handoff_json \
                "$target" "$handoff_id" "$(_awm_iso_timestamp)" \
                "$max_tokens" "$max_chars" "$budget_remaining" \
                "$status_json" "$open_questions" "$context" "$truncated")
            candidate_chars=$(_awm_string_bytes "$package")
            (( candidate_chars <= max_chars )) && break
            reduction=$(((candidate_chars - max_chars + AWM_CHARS_PER_TOKEN - 1) / AWM_CHARS_PER_TOKEN))
            (( reduction < 1 )) && reduction=1
            if (( reduction >= context_tokens )); then
                context_tokens=$((context_tokens - 1))
            else
                context_tokens=$((context_tokens - reduction))
            fi
        done
    fi

    candidate_chars=$(_awm_string_bytes "$package")
    if (( candidate_chars > max_chars )); then
        _awm_log error "awm_handoff_prepare: required identity and provenance exceed the handoff budget"
        return 1
    fi
    _awm_require_payload_size "handoff package" "$package" || return 1

    _awm_locked_atomic_write "$handoff_file" "$package" || return 1
    _awm_journal_write "$_AWM_SESSION_ID" "handoff" "$package" || return 1

    if [[ "$format" == "prompt" ]]; then
        printf 'Handoff to %s\n\n%s\n' "$target" "$package"
    else
        printf '%s' "$package"
    fi
}

# Accept an AWM handoff and initialize its context as active state.
# Usage: awm_handoff_accept HANDOFF_JSON
awm_handoff_accept() {
    local handoff_json="$1"
    local parent_session target_agent namespace session_name parent_namespace

    [[ -n "$handoff_json" ]] || {
        _awm_log error "awm_handoff_accept: handoff package required"
        return 1
    }
    _awm_require_payload_size "handoff package" "$handoff_json" || return 1
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi

    json_valid "$handoff_json" || {
        _awm_log error "awm_handoff_accept: invalid handoff JSON"
        return 1
    }

    parent_session=$(json_get "$handoff_json" parent_session 2>/dev/null || true)
    target_agent=$(json_get "$handoff_json" target_agent 2>/dev/null || true)
    [[ -n "$parent_session" ]] && _awm_validate_session_id "$parent_session" || {
        _awm_log error "awm_handoff_accept: valid parent_session required"
        return 1
    }
    _awm_find_session_dir "$parent_session" >/dev/null || {
        _awm_log error "awm_handoff_accept: parent session not found"
        return 1
    }
    parent_namespace=$(_awm_manifest_field "$parent_session" namespace)
    if _awm_session_is_project_reserved "$parent_session"; then
        _awm_log error "awm_handoff_accept: project memory cannot be inherited through a generic handoff"
        return 1
    fi
    namespace="$parent_namespace"
    session_name="${target_agent:-handoff}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        if [[ -n "$namespace" ]]; then
            awm_namespace "$namespace"
        fi
        awm_init "$session_name" --parent "$parent_session" >/dev/null
    fi

    awm_checkpoint "handoff_parent_session" "$parent_session" --importance high >/dev/null || return 1
    awm_checkpoint "handoff_target_agent" "${target_agent:-}" --importance high >/dev/null || return 1
    awm_checkpoint "handoff_context" "$handoff_json" --importance critical >/dev/null || return 1
    awm_log "handoff" "accepted handoff from ${parent_session:-unknown}" --importance high >/dev/null || return 1
    _awm_journal_write "$_AWM_SESSION_ID" "handoff_accept" \
        "{\"parent_session\":\"$(_awm_json_escape "$parent_session")\"}" || return 1
    printf '%s' "$_AWM_SESSION_ID"
}

# =============================================================================
# COMPATIBILITY WRAPPERS
# =============================================================================

awm_set() {
    local sid="$1"
    local key="$2"
    local value="${3:-}"
    _awm_validate_session_id "$sid" || return 1
    _awm_with_session "$sid" awm_checkpoint "$key" "$value"
}

awm_append() {
    local sid="$1"
    local key="$2"
    local value="$3"
    local file safe_key

    _awm_validate_session_id "$sid" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1
    _awm_require_payload_size "append key" "$key" || return 1
    _awm_require_payload_size "append value" "$value" || return 1
    _awm_find_session_dir "$sid" >/dev/null || {
        _awm_log error "awm_append: session not found: $sid"
        return 1
    }
    [[ -n "$key" ]] || return 1
    safe_key=$(_awm_sanitize_key "$key")
    _awm_validate_storage_component "$safe_key" "append key" 128 || return 1
    file="$(_awm_session_dir "$sid")/data/${safe_key}"
    _awm_locked_append "$file" "$value"
}

awm_unset() {
    local sid="$1"
    local key="$2"
    local dir file safe_key
    _awm_validate_session_id "$sid" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1
    dir=$(_awm_find_session_dir "$sid") || {
        _awm_log error "awm_unset: session not found: $sid"
        return 1
    }
    [[ -n "$key" ]] || return 1
    safe_key=$(_awm_sanitize_key "$key")
    _awm_validate_storage_component "$safe_key" "unset key" 128 || return 1
    file="${dir}/data/${safe_key}"
    _awm_reject_symlink_components "$file" || return 1
    [[ ! -L "$file" ]] || return 1
    rm -f -- "$file"
}

awm_get_checkpoint() {
    local sid="$1"
    local checkpoint_name="$2"
    local dir file
    _awm_validate_session_id "$sid" || return 1
    _awm_validate_checkpoint_name "$checkpoint_name" || return 1
    dir=$(_awm_find_session_dir "$sid") || return 1
    file="${dir}/checkpoints/${checkpoint_name}/snapshot.json"
    _awm_reject_symlink_components "$file" || return 1
    [[ ! -L "$file" ]] || return 1
    [[ -f "$file" ]] || return 1
    cat "$file"
}

awm_destroy() {
    local sid="$1"
    local dir
    _awm_validate_session_id "$sid" || return 1
    _awm_require_project_mutation_authorization "$sid" || return 1
    dir=$(_awm_find_session_dir "$sid") || {
        _awm_log error "awm_destroy: session not found: $sid"
        return 1
    }
    _awm_reject_symlink_components "${dir}/manifest.json" || return 1
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    rm -rf -- "$dir" || return 1
    if [[ "$_AWM_SESSION_ID" == "$sid" ]]; then
        _AWM_SESSION_ID=""
        _AWM_SESSION_DIR=""
    fi
    return 0
}

# =============================================================================
# V2 INTEGRATION LAYER
# =============================================================================

awm_v2_init() {
    local model="${1:-auto}"
    local lib_dir="${BASH_SOURCE%/*}"

    [[ $_AWM_V2_INITIALIZED -eq 1 ]] && return 0
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi

    if [[ -z "${_AWM_STORAGE_LOADED:-}" && -f "${lib_dir}/awm_storage.sh" ]]; then
        # shellcheck source=./awm_storage.sh
        if declare -F lazy_load_library >/dev/null 2>&1; then
            lazy_load_library awm_storage || _awm_log warn "awm_v2_init: failed to load awm_storage.sh"
        else
            source "${lib_dir}/awm_storage.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_storage.sh"
        fi
    fi
    if [[ -z "${_AWM_STREAM_LOADED:-}" && -f "${lib_dir}/awm_stream.sh" ]]; then
        # shellcheck source=./awm_stream.sh
        if declare -F lazy_load_library >/dev/null 2>&1; then
            lazy_load_library awm_stream || _awm_log warn "awm_v2_init: failed to load awm_stream.sh"
        else
            source "${lib_dir}/awm_stream.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_stream.sh"
        fi
    fi
    if [[ -z "${_AWM_TIERS_LOADED:-}" && -f "${lib_dir}/awm_tiers.sh" ]]; then
        # shellcheck source=./awm_tiers.sh
        if declare -F lazy_load_library >/dev/null 2>&1; then
            lazy_load_library awm_tiers || _awm_log warn "awm_v2_init: failed to load awm_tiers.sh"
        else
            source "${lib_dir}/awm_tiers.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_tiers.sh"
        fi
    fi

    if declare -F awm_storage_init >/dev/null 2>&1; then
        if [[ "${_AWM_ACTIVE_BACKEND:-file}" == "auto" ]]; then
            awm_storage_init >/dev/null 2>&1 || true
        else
            MAINFRAME_STORAGE="${_AWM_ACTIVE_BACKEND:-file}" awm_storage_init >/dev/null 2>&1 || true
        fi
    fi
    declare -F awm_tier_init >/dev/null 2>&1 && awm_tier_init >/dev/null 2>&1 || true
    declare -F awm_budget_init >/dev/null 2>&1 && awm_budget_init "$model" >/dev/null 2>&1 || true

    _AWM_V2_INITIALIZED=1
    return 0
}

awm_v2_status() {
    _awm_deprecate "awm_v2_status" "awm_status"
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init

    local storage_status='{}'
    local tier_stats='{}'
    local budget_summary='{}'

    declare -F awm_storage_status >/dev/null 2>&1 && storage_status=$(awm_storage_status 2>/dev/null || printf '{}')
    declare -F awm_tier_stats >/dev/null 2>&1 && tier_stats=$(awm_tier_stats 2>/dev/null || printf '{}')
    declare -F awm_budget_summary >/dev/null 2>&1 && budget_summary=$(awm_budget_summary 2>/dev/null || printf '{}')

    printf '{"status":%s,"storage":%s,"tiers":%s,"budget":%s}' \
        "$(awm_status 2>/dev/null || printf '{}')" \
        "$storage_status" \
        "$tier_stats" \
        "$budget_summary"
}

awm_checkpoint_v2() {
    local key="$1"
    local value="$2"
    local importance="${3:-normal}"
    local safe_key
    _awm_deprecate "awm_checkpoint_v2" "awm_checkpoint"
    _awm_require_payload_size "checkpoint key" "$key" || return 1
    _awm_require_payload_size "checkpoint value" "$value" || return 1
    _awm_validate_importance "$importance" || return 1
    safe_key=$(_awm_sanitize_key "$key")
    _awm_validate_storage_component "$safe_key" "checkpoint key" 128 || return 1
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init

    if declare -F awm_tier_write >/dev/null 2>&1; then
        awm_tier_write "$key" "$value" "$importance" >/dev/null 2>&1 || true
    fi

    awm_checkpoint "$key" "$value" --importance "$importance"
}

awm_get_v2() {
    local key="$1"
    local default="${2:-}"
    local promote="${3:-true}"
    local result
    _awm_deprecate "awm_get_v2" "awm_get"
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init

    if declare -F awm_tier_read >/dev/null 2>&1; then
        result=$(awm_tier_read "$key" "" "$promote" 2>/dev/null || true)
        if [[ -n "$result" ]]; then
            if [[ "$result" == ptr://awm/* ]] && declare -F awm_pointer_resolve >/dev/null 2>&1; then
                awm_pointer_resolve "$result"
            else
                printf '%s' "$result"
            fi
            return 0
        fi
    fi

    awm_get "$key" "$default"
}

awm_context_v2() {
    local max_tokens="${1:-0}"
    local include_cold="${2:-false}"
    _awm_deprecate "awm_context_v2" "awm_context_for"
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init

    if [[ "$include_cold" == "true" ]]; then
        awm_context_for "continuation" --tokens "${max_tokens:-0}" --include discoveries,progress,checkpoints,logs
    else
        awm_context_for "continuation" --tokens "${max_tokens:-0}" --include discoveries,progress,checkpoints
    fi
}

awm_recovery_checkpoint() {
    _awm_deprecate "awm_recovery_checkpoint" "awm_checkpoint"
    if [[ -n "$_AWM_SESSION_ID" ]]; then
        _awm_require_project_mutation_authorization "$_AWM_SESSION_ID" || return 1
    fi
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init
    if declare -F awm_tier_checkpoint >/dev/null 2>&1 && [[ -n "$_AWM_SESSION_ID" ]]; then
        awm_tier_checkpoint "$_AWM_SESSION_ID" >/dev/null 2>&1 || true
    fi
    [[ -n "$_AWM_SESSION_ID" ]] && _awm_snapshot_checkpoint "$_AWM_SESSION_ID" "recovery_$(date +%s)"
}

awm_recovery_restore() {
    local session_id="$1"
    _awm_deprecate "awm_recovery_restore" "awm_resume"
    _awm_validate_session_id "$session_id" || return 1
    _awm_require_project_mutation_authorization "$session_id" || return 1
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init
    awm_resume "$session_id" >/dev/null || return 1
    if declare -F awm_tier_recover >/dev/null 2>&1; then
        awm_tier_recover "$session_id"
    else
        printf '0'
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_AWM_EXPORTS=(
    awm_init
    awm_resume
    awm_project_ensure
    awm_project_session
    awm_project_status
    awm_close
    awm_namespace
    awm_team_namespace
    awm_checkpoint
    awm_log
    awm_progress
    awm_discovery
    awm_get
    awm_recent
    awm_summary
    awm_context_for
    awm_find
    awm_handoff_prepare
    awm_handoff_accept
    awm_status
    awm_doctor
    awm_migrate
    awm_compress
    awm_export
    awm_inherit
    awm_token_estimate
    awm_estimate_read
    awm_list
    awm_cleanup
    awm_check_limits
    awm_set
    awm_append
    awm_unset
    awm_get_checkpoint
    awm_destroy
    awm_list_sessions
    awm_v2_init
    awm_v2_status
    awm_checkpoint_v2
    awm_get_v2
    awm_context_v2
    awm_recovery_checkpoint
    awm_recovery_restore
)

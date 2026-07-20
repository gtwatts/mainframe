#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/awm.sh - Agent Working Memory (AWM)
# =============================================================================
# Description: Canonical Agent Working Memory facade for persistent session
#              state, discovery logging, handoff preparation, retrieval, and
#              context packing for finite-context agents.
# Version: 2.0.0
# Requires: Bash 4.0+
# =============================================================================

[[ -n "${_MAINFRAME_AWM_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_AWM_LOADED=1

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${SCRIPT_DIR}/json.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

AWM_ROOT="${AWM_ROOT:-${HOME}/.mainframe/awm}"
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
    local id
    id=$(od -An -tx1 -N6 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 12 ]]; then
        printf '%04x%04x%04x' "$$" "$RANDOM" "$((_awm_epoch % 65535))"
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
    local tag
    local IFS=','

    [[ -z "$csv" ]] && {
        printf '[]'
        return 0
    }

    for tag in $csv; do
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
    printf '%s' "${MAINFRAME_AGENT_NAME:-${_MAINFRAME_AGENT_NAME:-${_AWM_AGENT_ID:-${USER:-unknown}}}}"
}

_awm_find_session_dir() {
    local sid="$1"
    local candidate

    [[ -z "$sid" ]] && return 1

    if [[ "$sid" == "$_AWM_SESSION_ID" && -n "$_AWM_SESSION_DIR" && -f "$_AWM_SESSION_DIR/manifest.json" ]]; then
        printf '%s' "$_AWM_SESSION_DIR"
        return 0
    fi

    candidate="${AWM_ROOT}/sessions/${sid}"
    if [[ -f "${candidate}/manifest.json" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    for candidate in "${AWM_ROOT}/sessions"/*/"${sid}"; do
        [[ -f "${candidate}/manifest.json" ]] || continue
        printf '%s' "$candidate"
        return 0
    done

    return 1
}

_awm_session_dir() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir

    [[ -z "$sid" ]] && return 1

    dir=$(_awm_find_session_dir "$sid") || true
    if [[ -n "$dir" ]]; then
        printf '%s' "$dir"
        return 0
    fi

    if [[ -n "$_AWM_NAMESPACE" ]]; then
        printf '%s/sessions/%s/%s' "$AWM_ROOT" "$_AWM_NAMESPACE" "$sid"
    else
        printf '%s/sessions/%s' "$AWM_ROOT" "$sid"
    fi
}

_awm_session_exists() {
    local sid="$1"
    [[ -n "$sid" ]] || return 1
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

_awm_atomic_write() {
    local target="$1"
    local content="$2"
    local parent_dir="${target%/*}"
    local tmpfile="${target}.tmp.$$"

    [[ "$parent_dir" != "$target" ]] && mkdir -p "$parent_dir" 2>/dev/null

    if printf '%s' "$content" > "$tmpfile" 2>/dev/null; then
        mv -f "$tmpfile" "$target" 2>/dev/null && return 0
    fi

    rm -f "$tmpfile" 2>/dev/null
    return 1
}

_awm_append_unlocked() {
    local target="$1"
    local content="$2"
    local parent_dir="${target%/*}"
    [[ "$parent_dir" != "$target" ]] && mkdir -p "$parent_dir" 2>/dev/null
    printf '%s\n' "$content" >> "$target"
}

_awm_lock_strategy() {
    if [[ "${AWM_FORCE_MKDIR_LOCKS:-0}" == "1" ]]; then
        printf 'mkdir'
    elif command -v flock >/dev/null 2>&1; then
        printf 'flock'
    else
        printf 'mkdir'
    fi
}

_awm_with_lock() {
    local lock_name="$1"
    shift
    local strategy
    strategy=$(_awm_lock_strategy)

    if [[ "$strategy" == "flock" ]]; then
        (
            exec 9>"$lock_name" || exit 1
            flock -w "${AWM_LOCK_TIMEOUT}" 9 || exit 97
            "$@"
        )
        return $?
    fi

    local lock_dir="${lock_name}.dir"
    local start now
    start=$(_awm_epoch)

    while ! mkdir "$lock_dir" 2>/dev/null; do
        now=$(_awm_epoch)
        if [[ $((now - start)) -ge ${AWM_LOCK_TIMEOUT:-5} ]]; then
            return 97
        fi
        sleep 0.05
    done

    "$@"
    local rc=$?
    rmdir "$lock_dir" 2>/dev/null || true
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

_awm_update_manifest() {
    local sid="$1"
    local status="${2:-$(_awm_manifest_field "$sid" status)}"
    local now iso created_at created_epoch name parent namespace model backend manifest

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

    _awm_locked_atomic_write "$(_awm_manifest_path "$sid")" "$manifest"
}

_awm_ensure_session_layout() {
    local sid="$1"
    local dir
    dir=$(_awm_session_dir "$sid")

    mkdir -p \
        "${dir}/logs" \
        "${dir}/data" \
        "${dir}/checkpoints" \
        "${dir}/handoffs" \
        "${dir}/index" \
        "${dir}/index/progress" \
        "${dir}/journal" || return 1

    [[ -f "${dir}/discoveries.jsonl" ]] || : > "${dir}/discoveries.jsonl"
    [[ -f "${dir}/logs/discoveries.jsonl" ]] || : > "${dir}/logs/discoveries.jsonl"
    [[ -f "${dir}/logs/index.json" ]] || _awm_atomic_write "${dir}/logs/index.json" '{"categories":[]}'
    [[ -f "${dir}/index/categories.json" ]] || _awm_atomic_write "${dir}/index/categories.json" '[]'
    [[ -f "${dir}/journal/events.jsonl" ]] || : > "${dir}/journal/events.jsonl"
}

_awm_journal_write() {
    local sid="$1"
    local event_kind="$2"
    local payload_json="$3"
    local entry

    entry=$(printf '{"timestamp":"%s","kind":"%s","session_id":"%s","payload":%s}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_json_escape "$event_kind")" \
        "$sid" \
        "${payload_json:-{}}")

    _awm_locked_append "$(_awm_journal_file "$sid")" "$entry"
}

_awm_update_category_index() {
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
        _awm_locked_atomic_write "$category_index" "$categories_json"
        _awm_locked_atomic_write "$logs_index" "{\"categories\":${categories_json}}"
    fi
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

    _awm_locked_append "$log_file" "$entry" || return 1
    _awm_update_category_index "$sid" "$category"
    _awm_journal_write "$sid" "log" "$entry"
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
    _awm_update_category_index "$sid" "discoveries"
    _awm_journal_write "$sid" "discovery" "$entry"
    return 0
}

_awm_record_checkpoint_meta() {
    local sid="$1"
    local key="$2"
    local value="$3"
    local importance="$4"
    local tags_csv="$5"
    local ttl="$6"
    local preview entry tags_json index_file meta_file safe_key

    safe_key=$(_awm_sanitize_key "$key")
    preview="${value:0:256}"
    tags_json=$(_awm_tags_json "$tags_csv")
    entry=$(printf '{"timestamp":"%s","ts":%s,"kind":"checkpoint","importance":"%s","tags":%s,"source_agent":"%s","session_id":"%s","key":"%s","preview":"%s","ttl":%s}' \
        "$(_awm_iso_timestamp)" \
        "$(_awm_timestamp)" \
        "$(_awm_json_escape "$importance")" \
        "$tags_json" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$sid" \
        "$(_awm_json_escape "$key")" \
        "$(_awm_json_escape "$preview")" \
        "${ttl:-0}")

    index_file="$(_awm_session_dir "$sid")/logs/checkpoints.jsonl"
    meta_file="$(_awm_session_dir "$sid")/index/${safe_key}.json"

    _awm_locked_append "$index_file" "$entry" || return 1
    _awm_locked_atomic_write "$meta_file" "$entry" || return 1
    _awm_update_category_index "$sid" "checkpoints"
    _awm_journal_write "$sid" "checkpoint" "$entry"
    return 0
}

_awm_snapshot_checkpoint() {
    local sid="$1"
    local checkpoint_name="$2"
    local dir checkpoint_dir snapshot

    [[ -n "$checkpoint_name" ]] || {
        _awm_log error "awm_checkpoint: checkpoint name required"
        return 1
    }

    dir=$(_awm_session_dir "$sid")
    [[ -d "$dir" ]] || {
        _awm_log error "awm_checkpoint: session not found: $sid"
        return 1
    }

    checkpoint_dir="${dir}/checkpoints/${checkpoint_name}"
    mkdir -p "${checkpoint_dir}/data" || return 1
    if [[ -d "${dir}/data" ]]; then
        cp -R "${dir}/data/." "${checkpoint_dir}/data/" 2>/dev/null || true
    fi

    snapshot=$(printf '{"session_id":"%s","checkpoint":"%s","created_at":"%s","kind":"snapshot"}' \
        "$sid" \
        "$(_awm_json_escape "$checkpoint_name")" \
        "$(_awm_iso_timestamp)")

    _awm_locked_atomic_write "${checkpoint_dir}/snapshot.json" "$snapshot" || return 1
    _awm_journal_write "$sid" "snapshot" "$snapshot"
}

_awm_parse_log_options() {
    local default_importance="$1"
    shift
    local category="$1"
    local message="$2"
    shift 2
    local importance="$default_importance"
    local tags=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --importance)
                importance="${2:-$importance}"
                shift 2
                ;;
            --tags)
                tags="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    printf '%s\t%s\t%s\t%s' "$category" "$message" "$importance" "$tags"
}

_awm_parse_checkpoint_options() {
    local key="$1"
    local value="$2"
    shift 2
    local importance="normal"
    local tags=""
    local ttl="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --importance)
                importance="${2:-$importance}"
                shift 2
                ;;
            --tags)
                tags="${2:-}"
                shift 2
                ;;
            --ttl)
                ttl="${2:-0}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    printf '%s\t%s\t%s\t%s\t%s' "$key" "$value" "$importance" "$tags" "$ttl"
}

_awm_with_session() {
    local sid="$1"
    shift
    local previous_sid="$_AWM_SESSION_ID"
    local previous_dir="$_AWM_SESSION_DIR"

    _AWM_SESSION_ID="$sid"
    _AWM_SESSION_DIR="$(_awm_session_dir "$sid")"
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

# =============================================================================
# SESSION LIFECYCLE
# =============================================================================

awm_init() {
    local name=""
    local parent_session=""
    local namespace="${_AWM_NAMESPACE:-}"
    local model="${MAINFRAME_MODEL:-}"
    local backend="${AWM_BACKEND:-file}"

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

    [[ -z "$backend" ]] && backend="file"
    if [[ "$backend" == "auto" ]]; then
        _AWM_ACTIVE_BACKEND="auto"
    else
        _AWM_ACTIVE_BACKEND="$backend"
    fi

    if [[ -n "$namespace" ]]; then
        awm_namespace "$namespace"
    fi

    local session_id dir now now_iso manifest
    session_id=$(_awm_gen_session_id)
    dir=$(_awm_session_dir "$session_id")
    now=$(_awm_epoch)
    now_iso=$(_awm_iso_timestamp)

    mkdir -p "$dir" || {
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
        _awm_inherit "$parent_session" "$session_id"
    fi

    printf '%s' "$session_id"
}

awm_resume() {
    local session_id="$1"
    local dir namespace

    if [[ -z "$session_id" ]]; then
        _awm_log error "awm_resume: session_id required"
        return 1
    fi

    dir=$(_awm_find_session_dir "$session_id") || {
        _awm_log error "awm_resume: session not found: $session_id"
        return 1
    }

    _AWM_SESSION_ID="$session_id"
    _AWM_SESSION_DIR="$dir"
    awm_migrate "$session_id" >/dev/null 2>&1 || true

    namespace=$(_awm_manifest_field "$session_id" namespace)
    _AWM_NAMESPACE="${namespace:-}"
    _AWM_ACTIVE_BACKEND="$(_awm_manifest_field "$session_id" backend)"
    [[ -z "$_AWM_ACTIVE_BACKEND" ]] && _AWM_ACTIVE_BACKEND="file"

    return 0
}

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

    parent_dir=$(_awm_find_session_dir "$parent_id") || {
        _awm_log warn "_awm_inherit: parent session not found: $parent_id"
        return 1
    }
    child_dir=$(_awm_session_dir "$child_id")

    parent_disc=$(_awm_discoveries_file "$parent_id")
    if [[ -f "$parent_disc" ]]; then
        cp -f "$parent_disc" "${child_dir}/logs/inherited_discoveries.jsonl" 2>/dev/null || true
    fi

    if [[ -d "${parent_dir}/data" ]]; then
        cp -R "${parent_dir}/data/." "${child_dir}/data/" 2>/dev/null || true
    fi

    _awm_journal_write "$child_id" "inherit" "{\"parent_session\":\"$(_awm_json_escape "$parent_id")\"}"
    return 0
}

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

awm_checkpoint() {
    if [[ $# -eq 2 ]] && _awm_session_exists "$1"; then
        _awm_snapshot_checkpoint "$1" "$2"
        return $?
    fi

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_checkpoint: no active session"
        return 1
    fi

    local parsed key value importance tags ttl safe_key dir file
    parsed=$(_awm_parse_checkpoint_options "$@")
    key="${parsed%%$'\t'*}"
    parsed="${parsed#*$'\t'}"
    value="${parsed%%$'\t'*}"
    parsed="${parsed#*$'\t'}"
    importance="${parsed%%$'\t'*}"
    parsed="${parsed#*$'\t'}"
    tags="${parsed%%$'\t'*}"
    ttl="${parsed##*$'\t'}"

    [[ -n "$key" ]] || {
        _awm_log error "awm_checkpoint: key required"
        return 1
    }

    safe_key=$(_awm_sanitize_key "$key")
    dir=$(_awm_session_dir)
    file="${dir}/data/${safe_key}"

    _awm_locked_atomic_write "$file" "$value" || return 1
    _awm_record_checkpoint_meta "$_AWM_SESSION_ID" "$key" "$value" "$importance" "$tags" "$ttl" || return 1
    _awm_update_manifest "$_AWM_SESSION_ID" "active" >/dev/null 2>&1 || true
    return 0
}

awm_log() {
    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_log: no active session"
        return 1
    fi

    local parsed category message importance tags safe_category log_file count
    parsed=$(_awm_parse_log_options "normal" "$@")
    category="${parsed%%$'\t'*}"
    parsed="${parsed#*$'\t'}"
    message="${parsed%%$'\t'*}"
    parsed="${parsed#*$'\t'}"
    importance="${parsed%%$'\t'*}"
    tags="${parsed##*$'\t'}"

    [[ -n "$category" && -n "$message" ]] || {
        _awm_log error "awm_log: category and message required"
        return 1
    }

    safe_category=$(_awm_sanitize_name "$category")
    _awm_record_log_entry "$_AWM_SESSION_ID" "$safe_category" "$message" "$importance" "$tags" || return 1

    log_file="$(_awm_session_dir)/logs/${safe_category}.jsonl"
    count=$(_awm_line_count "$log_file")
    if [[ "$safe_category" != "progress" && "$safe_category" != "discoveries" && $count -gt $AWM_MAX_LOG_ENTRIES ]]; then
        _awm_compress_log "$safe_category" "$_AWM_SESSION_ID"
    fi
    return 0
}

awm_progress() {
    local task_id="$1"
    local progress="$2"
    local status_msg="${3:-}"
    local current total entry progress_file latest_file

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_progress: no active session"
        return 1
    fi

    [[ -n "$task_id" && -n "$progress" ]] || {
        _awm_log error "awm_progress: task and progress required"
        return 1
    }

    current="${progress%/*}"
    total="${progress#*/}"
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0

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
    _awm_update_category_index "$_AWM_SESSION_ID" "progress"
    _awm_journal_write "$_AWM_SESSION_ID" "progress" "$entry"
    awm_checkpoint "progress:${task_id}" "${current}/${total}" --importance high >/dev/null
    return 0
}

awm_discovery() {
    local insight="$1"
    shift || true

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_discovery: no active session"
        return 1
    fi

    [[ -n "$insight" ]] || {
        _awm_log error "awm_discovery: insight text required"
        return 1
    }

    local importance="high"
    local tags=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --importance)
                importance="${2:-high}"
                shift 2
                ;;
            --tags)
                tags="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    _awm_record_discovery_entry "$_AWM_SESSION_ID" "$insight" "$importance" "$tags" || return 1
    _awm_update_manifest "$_AWM_SESSION_ID" "active" >/dev/null 2>&1 || true
    return 0
}

# =============================================================================
# CORE READ FUNCTIONS
# =============================================================================

awm_get() {
    local sid=""
    local key default safe_key dir file result

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
    file="${dir}/data/${safe_key}"

    if [[ -f "$file" ]]; then
        result=$(<"$file")
        printf '%s' "$result"
        return 0
    fi

    printf '%s' "$default"
    return 1
}

awm_recent() {
    local category="$1"
    local count="${2:-10}"
    local sid="${3:-$_AWM_SESSION_ID}"
    local safe_cat log_file lines

    [[ -n "$sid" ]] || {
        printf '[]'
        return 1
    }

    safe_cat=$(_awm_sanitize_name "$category")
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

    dir=$(_awm_session_dir)
    discoveries=$(awm_recent "discoveries" "$AWM_CONTEXT_DISCOVERY_LIMIT")
    progress=$(_awm_progress_summary_json "$sid")

    checkpoints="{"
    local first=1 file key value escaped_key escaped_val
    for file in "${dir}/data"/*; do
        [[ -f "$file" ]] || continue
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

awm_find() {
    local query=""
    local kind="mixed"
    local limit="$AWM_FIND_DEFAULT_LIMIT"
    local sid="$_AWM_SESSION_ID"
    local tmpfile reranked_file dir disc_file log_file file category content score payload preview key value

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

    dir=$(_awm_session_dir "$sid")
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/awm-find.XXXXXX")"

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
                    printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
                fi
            done < "$disc_file"
        fi
    fi

    if [[ "$kind" == "mixed" || "$kind" == "checkpoint" ]]; then
        for file in "${dir}/data"/*; do
            [[ -f "$file" ]] || continue
            key="${file##*/}"
            value=$(head -c 512 "$file")
            content="${key} ${value}"
            score=$(_awm_search_score "$query" "$content")
            if [[ $score -gt 0 ]]; then
                payload=$(printf '{"kind":"checkpoint","score":%s,"title":"%s","preview":"%s","source":"data/%s","session_id":"%s","key":"%s"}' \
                    "$score" \
                    "$(_awm_json_escape "$key")" \
                    "$(_awm_json_escape "$value")" \
                    "$(_awm_json_escape "$key")" \
                    "$sid" \
                    "$(_awm_json_escape "$key")")
                printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
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
                    printf '%s\t%s\n' "$score" "$payload" >> "$tmpfile"
                fi
            done < "$log_file"
        done
    fi

    if [[ ! -s "$tmpfile" ]]; then
        rm -f "$tmpfile" 2>/dev/null
        printf '[]'
        return 0
    fi

    _awm_select_top_results "$tmpfile" "$limit" "$query"
    rm -f "$tmpfile" 2>/dev/null
}

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

    if [[ "$max_tokens" -eq 0 ]]; then
        if declare -F awm_budget_remaining >/dev/null 2>&1; then
            max_tokens=$(awm_budget_remaining 2>/dev/null || printf '%s' "$AWM_CONTEXT_DEFAULT_TOKENS")
        else
            max_tokens="$AWM_CONTEXT_DEFAULT_TOKENS"
        fi
    fi

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

    if [[ "$format" == "prompt" ]]; then
        _awm_build_prompt_context "$task" "$discoveries" "$progress" "$checkpoints" "$logs" "$related" "$summary"
        return 0
    fi

    printf '{"task":"%s","session_id":"%s","max_tokens":%s,"discoveries":%s,"progress":%s,"checkpoints":%s,"logs":%s,"related":%s,"summary":%s}' \
        "$(_awm_json_escape "$task")" \
        "$_AWM_SESSION_ID" \
        "$max_tokens" \
        "$discoveries" \
        "$progress" \
        "$checkpoints" \
        "$logs" \
        "$related" \
        "$summary"
}

# =============================================================================
# MANAGEMENT AND INSPECTION
# =============================================================================

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
    checkpoint_count=$(find "${dir}/data" -type f 2>/dev/null | wc -l | tr -d ' ')
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

awm_doctor() {
    local sid="${1:-$_AWM_SESSION_ID}"
    local dir manifest issues="[" first=1 schema_version layout_ok=1

    [[ -n "$sid" ]] || {
        printf '{"error":"no active session"}'
        return 1
    }

    dir=$(_awm_session_dir "$sid")
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
    issues+="]"

    printf '{"session_id":"%s","schema_version":%s,"expected_schema":%s,"layout_ok":%s,"lock_strategy":"%s","backend":"%s","issues":%s}' \
        "$sid" \
        "$schema_version" \
        "$AWM_SCHEMA_VERSION" \
        "$([[ $layout_ok -eq 1 ]] && echo true || echo false)" \
        "$(_awm_lock_strategy)" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-$(_awm_manifest_field "$sid" backend)}")" \
        "$issues"
}

awm_migrate() {
    local target="${1:-$_AWM_SESSION_ID}"
    local sid count=0

    if [[ "$target" == "--all" ]]; then
        while IFS= read -r sid; do
            [[ -n "$sid" ]] || continue
            awm_migrate "$sid" >/dev/null || return 1
            count=$((count + 1))
        done < <(awm_list_sessions)
        printf '%s' "$count"
        return 0
    fi

    [[ -n "$target" ]] || {
        _awm_log error "awm_migrate: session_id or --all required"
        return 1
    }

    local dir manifest name parent status namespace model backend created_at created_epoch discoveries_old discoveries_new
    dir=$(_awm_find_session_dir "$target") || {
        _awm_log error "awm_migrate: session not found: $target"
        return 1
    }
    _AWM_SESSION_DIR="$dir"

    _awm_ensure_session_layout "$target" || return 1
    manifest="${dir}/manifest.json"
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

    discoveries_old="${dir}/logs/discoveries.jsonl"
    discoveries_new="${dir}/discoveries.jsonl"
    if [[ ! -s "$discoveries_new" && -f "$discoveries_old" ]]; then
        cp -f "$discoveries_old" "$discoveries_new" 2>/dev/null || true
    elif [[ ! -s "$discoveries_old" && -f "$discoveries_new" ]]; then
        cp -f "$discoveries_new" "$discoveries_old" 2>/dev/null || true
    fi

    _awm_update_manifest "$target" "$status" "$created_at" "$created_epoch" "$name" "$parent" "$namespace" "$model" "$backend" || return 1
    _awm_journal_write "$target" "migrate" "{\"schema_version\":${AWM_SCHEMA_VERSION}}"
    printf '%s' "$target"
}

awm_compress() {
    local session_id="${1:-$_AWM_SESSION_ID}"
    local dir log_file category

    [[ -n "$session_id" ]] || {
        _awm_log error "awm_compress: no session specified"
        return 1
    }

    dir=$(_awm_session_dir "$session_id")
    for log_file in "${dir}/logs/"*.jsonl; do
        [[ -f "$log_file" ]] || continue
        category=$(basename "$log_file" .jsonl)
        [[ "$category" == "discoveries" ]] && continue
        _awm_compress_log "$category" "$session_id"
    done
    return 0
}

_awm_compress_log() {
    local category="$1"
    local session_id="${2:-$_AWM_SESSION_ID}"
    local dir log_file line_count archive_count keep tmpfile archive_file

    dir=$(_awm_session_dir "$session_id")
    log_file="${dir}/logs/${category}.jsonl"
    [[ -f "$log_file" ]] || return 0

    line_count=$(_awm_line_count "$log_file")
    if [[ $line_count -le $AWM_MAX_LOG_ENTRIES ]]; then
        return 0
    fi

    keep="${AWM_LOG_KEEP_RECENT:-50}"
    [[ $keep -gt $line_count ]] && keep="$line_count"
    archive_count=$((line_count - keep))
    archive_file="${dir}/logs/${category}.archive.jsonl"
    tmpfile="${log_file}.tmp.$$"

    head -n "$archive_count" "$log_file" >> "$archive_file"
    tail -n "$keep" "$log_file" > "$tmpfile"
    mv -f "$tmpfile" "$log_file"
    _awm_journal_write "$session_id" "compress" "{\"category\":\"$(_awm_json_escape "$category")\",\"archived\":${archive_count}}"
}

awm_export() {
    local output_file="${1:-}"
    local dir disc_file file key value

    [[ -n "$_AWM_SESSION_ID" ]] || {
        _awm_log error "awm_export: no active session"
        return 1
    }

    dir=$(_awm_session_dir)
    [[ -n "$output_file" ]] || output_file="${dir}/export.md"
    disc_file=$(_awm_discoveries_file)

    {
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
            key="${file##*/}"
            value=$(head -c 120 "$file" | tr '\n' ' ')
            printf '| %s | %s |\n' "$key" "$value"
        done
        printf '\n'

        printf '## Summary\n\n'
        awm_summary
        printf '\n'
    } > "$output_file"

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

    dir=$(_awm_session_dir "$sid")

    for file in "${dir}/data/"* "${dir}/logs/"*.jsonl "${dir}/discoveries.jsonl"; do
        [[ -f "$file" ]] || continue
        total_bytes=$((total_bytes + $(_awm_file_size "$file")))
    done

    printf '%d' "$((total_bytes / AWM_CHARS_PER_TOKEN))"
}

awm_estimate_read() {
    local operation="$1"
    shift || true
    local bytes=0 dir file category count key

    [[ -n "$_AWM_SESSION_ID" ]] || {
        printf '0'
        return 1
    }

    dir=$(_awm_session_dir)

    case "$operation" in
        summary)
            bytes=$(_awm_file_size "$(_awm_discoveries_file)")
            for file in "${dir}/data/"*; do
                [[ -f "$file" ]] || continue
                bytes=$((bytes + $(head -c 256 "$file" | wc -c | tr -d ' ')))
            done
            ;;
        recent)
            category="${1:-log}"
            count="${2:-10}"
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
            bytes=$((AWM_CONTEXT_DEFAULT_TOKENS * AWM_CHARS_PER_TOKEN))
            ;;
    esac

    printf '%d' "$((bytes / AWM_CHARS_PER_TOKEN))"
}

awm_list() {
    local filter_status=""
    local as_json=0
    local session_dir manifest id content name status created_at namespace first=1

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
        [[ -d "$session_dir" ]] || continue
        manifest="${session_dir}/manifest.json"
        [[ -f "$manifest" ]] || continue

        id="${session_dir##*/}"
        content=$(<"$manifest")
        name=$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        status=$(sed -n 's/.*"status":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        created_at=$(sed -n 's/.*"created_at":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)
        namespace=$(sed -n 's/.*"namespace":"\([^"]*\)".*/\1/p' <<<"$content" | head -n 1)

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

    now=$(_awm_epoch)
    max_seconds=$((max_days * 86400))

    for session_dir in "${AWM_ROOT}/sessions/"* "${AWM_ROOT}/sessions/"*/*; do
        [[ -d "$session_dir" ]] || continue
        manifest="${session_dir}/manifest.json"
        [[ -f "$manifest" ]] || continue
        content=$(<"$manifest")
        [[ "$content" == *'"status":"completed"'* ]] || continue
        created_epoch=$(sed -n 's/.*"created_epoch":\([0-9][0-9]*\).*/\1/p' <<<"$content" | head -n 1)
        [[ -n "$created_epoch" ]] || continue
        age=$((now - created_epoch))
        if [[ $age -gt $max_seconds ]]; then
            rm -rf "$session_dir"
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

awm_handoff_prepare() {
    local target="$1"
    shift || true
    local max_tokens=0
    local format="json"
    local context open_questions handoff_id handoff_file package budget_remaining status_json

    [[ -n "$_AWM_SESSION_ID" ]] || {
        _awm_log error "awm_handoff_prepare: no active session"
        return 1
    }

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
                shift
                ;;
        esac
    done

    if [[ "$max_tokens" -eq 0 ]]; then
        if declare -F awm_budget_remaining >/dev/null 2>&1; then
            max_tokens=$(awm_budget_remaining 2>/dev/null || printf '%s' "$AWM_CONTEXT_DEFAULT_TOKENS")
        else
            max_tokens="$AWM_CONTEXT_DEFAULT_TOKENS"
        fi
    fi

    context=$(awm_context_for "$target" --tokens "$max_tokens" --format json)
    open_questions=$(awm_recent "questions" 10)
    budget_remaining=$(if declare -F awm_budget_remaining >/dev/null 2>&1; then awm_budget_remaining 2>/dev/null; else printf '%s' "$max_tokens"; fi)
    status_json=$(awm_status)
    handoff_id="handoff_$(_awm_epoch)_$(_awm_sanitize_name "$target")"
    handoff_file="$(_awm_handoff_dir)/${handoff_id}.json"

    package=$(printf '{"type":"handoff","handoff_id":"%s","created_at":"%s","parent_session":"%s","parent_agent":"%s","target_agent":"%s","budget_remaining":%s,"provenance":{"schema_version":%s,"namespace":"%s","backend":"%s"},"status":%s,"open_questions":%s,"context":%s}' \
        "$(_awm_json_escape "$handoff_id")" \
        "$(_awm_iso_timestamp)" \
        "$_AWM_SESSION_ID" \
        "$(_awm_json_escape "$(_awm_current_agent)")" \
        "$(_awm_json_escape "$target")" \
        "${budget_remaining:-0}" \
        "$AWM_SCHEMA_VERSION" \
        "$(_awm_json_escape "${_AWM_NAMESPACE:-}")" \
        "$(_awm_json_escape "${_AWM_ACTIVE_BACKEND:-file}")" \
        "$status_json" \
        "$open_questions" \
        "$context")

    _awm_locked_atomic_write "$handoff_file" "$package" || return 1
    _awm_journal_write "$_AWM_SESSION_ID" "handoff" "$package"

    if [[ "$format" == "prompt" ]]; then
        printf 'Handoff to %s\n\n%s\n' "$target" "$package"
    else
        printf '%s' "$package"
    fi
}

awm_handoff_accept() {
    local handoff_json="$1"
    local parent_session target_agent namespace session_name

    [[ -n "$handoff_json" ]] || {
        _awm_log error "awm_handoff_accept: handoff package required"
        return 1
    }

    parent_session=$(sed -n 's/.*"parent_session":"\([^"]*\)".*/\1/p' <<<"$handoff_json" | head -n 1)
    target_agent=$(sed -n 's/.*"target_agent":"\([^"]*\)".*/\1/p' <<<"$handoff_json" | head -n 1)
    namespace=$(sed -n 's/.*"namespace":"\([^"]*\)".*/\1/p' <<<"$handoff_json" | head -n 1)
    session_name="${target_agent:-handoff}"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        if [[ -n "$namespace" ]]; then
            awm_namespace "$namespace"
        fi
        awm_init "$session_name" --parent "$parent_session" >/dev/null
    fi

    awm_checkpoint "handoff_parent_session" "$parent_session" --importance high >/dev/null
    awm_checkpoint "handoff_target_agent" "${target_agent:-}" --importance high >/dev/null
    awm_checkpoint "handoff_context" "$handoff_json" --importance critical >/dev/null
    awm_log "handoff" "accepted handoff from ${parent_session:-unknown}" --importance high >/dev/null
    _awm_journal_write "$_AWM_SESSION_ID" "handoff_accept" "{\"parent_session\":\"$(_awm_json_escape "$parent_session")\"}"
    printf '%s' "$_AWM_SESSION_ID"
}

# =============================================================================
# COMPATIBILITY WRAPPERS
# =============================================================================

awm_set() {
    local sid="$1"
    local key="$2"
    local value="${3:-}"
    _awm_with_session "$sid" awm_checkpoint "$key" "$value"
}

awm_append() {
    local sid="$1"
    local key="$2"
    local value="$3"
    local file

    file="$(_awm_session_dir "$sid")/data/$(_awm_sanitize_key "$key")"
    _awm_locked_append "$file" "$value"
}

awm_unset() {
    local sid="$1"
    local key="$2"
    rm -f "$(_awm_session_dir "$sid")/data/$(_awm_sanitize_key "$key")"
}

awm_get_checkpoint() {
    local sid="$1"
    local checkpoint_name="$2"
    local file="$(_awm_session_dir "$sid")/checkpoints/${checkpoint_name}/snapshot.json"
    [[ -f "$file" ]] || return 1
    cat "$file"
}

awm_destroy() {
    local sid="$1"
    local dir
    dir=$(_awm_session_dir "$sid")
    rm -rf "$dir" || return 1
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

    if [[ -z "${_AWM_STORAGE_LOADED:-}" && -f "${lib_dir}/awm_storage.sh" ]]; then
        # shellcheck source=./awm_storage.sh
        source "${lib_dir}/awm_storage.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_storage.sh"
    fi
    if [[ -z "${_AWM_STREAM_LOADED:-}" && -f "${lib_dir}/awm_stream.sh" ]]; then
        # shellcheck source=./awm_stream.sh
        source "${lib_dir}/awm_stream.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_stream.sh"
    fi
    if [[ -z "${_AWM_TIERS_LOADED:-}" && -f "${lib_dir}/awm_tiers.sh" ]]; then
        # shellcheck source=./awm_tiers.sh
        source "${lib_dir}/awm_tiers.sh" 2>/dev/null || _awm_log warn "awm_v2_init: failed to load awm_tiers.sh"
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
    _awm_deprecate "awm_checkpoint_v2" "awm_checkpoint"
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
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init

    if [[ "$include_cold" == "true" ]]; then
        awm_context_for "continuation" --tokens "${max_tokens:-0}" --include discoveries,progress,checkpoints,logs
    else
        awm_context_for "continuation" --tokens "${max_tokens:-0}" --include discoveries,progress,checkpoints
    fi
}

awm_recovery_checkpoint() {
    _awm_deprecate "awm_recovery_checkpoint" "awm_checkpoint"
    [[ $_AWM_V2_INITIALIZED -eq 0 ]] && awm_v2_init
    if declare -F awm_tier_checkpoint >/dev/null 2>&1 && [[ -n "$_AWM_SESSION_ID" ]]; then
        awm_tier_checkpoint "$_AWM_SESSION_ID" >/dev/null 2>&1 || true
    fi
    [[ -n "$_AWM_SESSION_ID" ]] && _awm_snapshot_checkpoint "$_AWM_SESSION_ID" "recovery_$(date +%s)"
}

awm_recovery_restore() {
    local session_id="$1"
    _awm_deprecate "awm_recovery_restore" "awm_resume"
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

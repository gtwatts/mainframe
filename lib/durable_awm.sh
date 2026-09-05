#!/usr/bin/env bash
# Fixed Bash adapter for the kernel-owned project-memory protocol.
# Hidden grammar constants:
#   __kernel-project-memory-observer-v1 --format project-memory-observation-json-v1 --caller control-plane
#   __kernel-project-memory-executor-v1 --input-json - --format project-memory-executor-json-v1 --caller control-plane
#
# Public callers select one of six reviewed operations. They cannot select a
# storage root, executable, durable identity, policy outcome, or Evidence.
# The hidden boundary receives canonical identity on FD197, a kernel-owned
# liveness capability on FD198, and may write handoff bytes only to FD196.

[[ -n "${_MAINFRAME_DURABLE_AWM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DURABLE_AWM_LOADED=1

readonly _MAINFRAME_PROJECT_MEMORY_ENSURE='mainframe.project_memory.ensure.v1'
readonly _MAINFRAME_PROJECT_MEMORY_CHECKPOINT='mainframe.project_memory.checkpoint.v1'
readonly _MAINFRAME_PROJECT_MEMORY_DISCOVERY='mainframe.project_memory.discovery.v1'
readonly _MAINFRAME_PROJECT_MEMORY_PROGRESS='mainframe.project_memory.progress.v1'
readonly _MAINFRAME_PROJECT_MEMORY_CLOSE='mainframe.project_memory.close.v1'
readonly _MAINFRAME_PROJECT_MEMORY_HANDOFF='mainframe.project_memory.handoff.v1'
readonly _MAINFRAME_PROJECT_MEMORY_SESSION='mainframe.project_memory.session.v1'
readonly _MAINFRAME_PROJECT_MEMORY_STATUS='mainframe.project_memory.status.v1'
readonly _MAINFRAME_PROJECT_MEMORY_GET='mainframe.project_memory.get.v1'
readonly _MAINFRAME_PROJECT_MEMORY_SUMMARY='mainframe.project_memory.summary.v1'
readonly _MAINFRAME_PROJECT_MEMORY_CONTEXT='mainframe.project_memory.context.v1'
readonly _MAINFRAME_PROJECT_MEMORY_FIND='mainframe.project_memory.find.v1'

_mainframe_durable_awm_tool_is_read() {
    case "${1:-}" in
        "$_MAINFRAME_PROJECT_MEMORY_SESSION"|\
        "$_MAINFRAME_PROJECT_MEMORY_STATUS"|\
        "$_MAINFRAME_PROJECT_MEMORY_GET"|\
        "$_MAINFRAME_PROJECT_MEMORY_SUMMARY"|\
        "$_MAINFRAME_PROJECT_MEMORY_CONTEXT"|\
        "$_MAINFRAME_PROJECT_MEMORY_FIND") return 0 ;;
        *) return 1 ;;
    esac
}

_mainframe_durable_awm_start_liveness_guardian() {
    local descriptor="${1:-}"
    [[ "$descriptor" == 198 && -p /dev/fd/198 ]] || return 126
    (
        trap '' HUP TERM
        if IFS= read -r -n 1 _mainframe_awm_liveness_byte <&198; then
            exit 0
        fi
        kill -TERM -- "-$$" 2>/dev/null || true
        /bin/sleep 0.25
        kill -KILL -- "-$$" 2>/dev/null || true
    ) </dev/null >/dev/null 2>&1 &
}

_mainframe_durable_awm_sha256_stream() {
    local output digest
    if [[ -x /usr/bin/sha256sum ]]; then
        output=$(/usr/bin/sha256sum) || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /bin/sha256sum ]]; then
        output=$(/bin/sha256sum) || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /usr/bin/shasum ]]; then
        output=$(/usr/bin/shasum -a 256) || return 1
        digest="${output%%[[:space:]]*}"
    elif [[ -x /usr/bin/openssl ]]; then
        output=$(/usr/bin/openssl dgst -sha256) || return 1
        digest="${output##* }"
    else
        return 1
    fi
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$digest"
}

_mainframe_durable_awm_sha256_text() {
    builtin printf '%s' "$1" | _mainframe_durable_awm_sha256_stream
}

_mainframe_durable_awm_bytes() {
    local count
    count=$(LC_ALL=C builtin printf '%s' "$1" | /usr/bin/wc -c) || return 1
    count="${count//[[:space:]]/}"
    [[ "$count" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$count"
}

_mainframe_durable_awm_jq() {
    local jq_path
    jq_path="$(_awm_strict_jq_path 2>/dev/null)" || return 1
    "$jq_path" "$@"
}

# Canonical equality makes duplicate keys, alternate number spellings, and
# ambiguous whitespace fail closed. Python emits both hidden documents in
# this exact form, so normalization is never accepted at the trust boundary.
_mainframe_durable_awm_require_canonical_json() {
    local raw="$1" canonical
    canonical=$(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -ceS '.') || return 1
    [[ "$raw" == "$canonical" ]]
}

_mainframe_durable_awm_mapping_is_exact() {
    local raw="$1" streamed_keys
    builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
        type == "object" and
        (keys == ["created_at","project_sha256","schema_version","session_id"]) and
        .schema_version == 1 and
        (.created_at | type == "string") and
        (.project_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.session_id | type == "string" and test("^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}$"))
    ' >/dev/null || return 1
    # jq's streaming form retains duplicate object members. Require each
    # top-level leaf exactly once even though the semantic parser keeps only
    # the final duplicate value.
    streamed_keys=$(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq --stream -r '
        select(length == 2 and (.[0] | length) == 1) | .[0][0]
    ' | LC_ALL=C /usr/bin/sort) || return 1
    [[ "$streamed_keys" == $'created_at\nproject_sha256\nschema_version\nsession_id' ]]
}

_mainframe_durable_awm_manifest_identity_is_exact() {
    local raw="$1" streamed_keys
    builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
        type == "object" and
        (.schema_version | type == "number") and
        (.session_id | type == "string") and
        .namespace == "projects" and .backend == "file" and
        (.status == "active" or .status == "completed")
    ' >/dev/null || return 1
    streamed_keys=$(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq --stream -r '
        select(length == 2 and (.[0] | length) == 1 and
          (.[0][0] == "schema_version" or .[0][0] == "session_id" or
           .[0][0] == "namespace" or .[0][0] == "backend" or .[0][0] == "status")) |
        .[0][0]
    ' | LC_ALL=C /usr/bin/sort) || return 1
    [[ "$streamed_keys" == $'backend\nnamespace\nschema_version\nsession_id\nstatus' ]]
}

_mainframe_durable_awm_prepare_hidden_root() {
    local root="${XDG_STATE_HOME:-}" owner_mode owner mode numeric
    [[ -z "${AWM_ROOT+x}" && "$root" == /* && "$root" != / &&
       -d "$root" && ! -L "$root" ]] || return 126
    owner_mode="$(_mainframe_cli_owner_mode "$root" 2>/dev/null || true)"
    read -r owner mode <<<"$owner_mode"
    [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] || return 126
    numeric=$((8#$mode))
    [[ "$owner" -eq "$EUID" ]] || return 126
    (( (numeric & 0077) == 0 )) || return 126
    export AWM_ROOT="${root%/}/awm"
    export MAINFRAME_QUIET=1 AWM_COMPAT_WARNINGS=0
    # shellcheck source=lib/awm.sh
    source "$MAINFRAME_ROOT/lib/awm.sh"
}

_mainframe_durable_awm_state_digest() {
    local mapping="$1" sid="$2" session_dir manifest path relative file_digest
    session_dir="$AWM_ROOT/sessions/projects/$sid"
    manifest="$session_dir/manifest.json"
    [[ -f "$mapping" && ! -L "$mapping" && -f "$manifest" && ! -L "$manifest" ]] || return 1
    {
        file_digest=$(_awm_sha256_file "$mapping") || exit 1
        builtin printf 'mapping\t%s\t%s\n' "$(_awm_string_bytes "$(<"$mapping")")" "$file_digest"
        while IFS= read -r path; do
            [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || exit 1
            relative="${path#"$session_dir"/}"
            file_digest=$(_awm_sha256_file "$path") || exit 1
            builtin printf '%s\t%s\t%s\n' \
                "$relative" "$(_awm_string_bytes "$(<"$path")")" "$file_digest"
        done < <(/usr/bin/find "$session_dir" -type f -print | LC_ALL=C /usr/bin/sort)
    } | _mainframe_durable_awm_sha256_stream
}

# Prints five unit-separator-delimited fields. Canonical project paths reject
# control bytes, so an empty session field cannot collapse during Bash IFS
# splitting as it would with adjacent tabs.
_mainframe_durable_awm_observe_fields() {
    local project="$1" canonical digest mapping raw sid validated_sid session_dir manifest manifest_raw
    local status state_digest synthetic
    IFS=$'\t' read -r canonical digest < <(_awm_project_identity "$project") || return 1
    mapping="$AWM_ROOT/projects/$digest.json"
    if [[ ! -e "$mapping" && ! -L "$mapping" ]]; then
        builtin printf 'absent\037\037%s\037%s\037%s\n' \
            '0000000000000000000000000000000000000000000000000000000000000000' \
            "$mapping" "$canonical"
        return 0
    fi
    synthetic="${digest:0:12}"
    if [[ ! -f "$mapping" || -L "$mapping" ]]; then
        state_digest=$(_awm_sha256_file "$mapping" 2>/dev/null || builtin printf '%064d' 0)
        builtin printf 'invalid\037%s\037%s\037%s\037%s\n' \
            "$synthetic" "$state_digest" "$mapping" "$canonical"
        return 0
    fi
    raw=$(<"$mapping") || return 1
    if ! _mainframe_durable_awm_mapping_is_exact "$raw" ||
       [[ $(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -r '.project_sha256') != "$digest" ]]; then
        state_digest=$(_awm_sha256_file "$mapping") || return 1
        builtin printf 'invalid\037%s\037%s\037%s\037%s\n' \
            "$synthetic" "$state_digest" "$mapping" "$canonical"
        return 0
    fi
    sid=$(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -r '.session_id') || return 1
    validated_sid=$(_awm_project_read_mapping_unlocked "$mapping" "$digest" 2>/dev/null || true)
    if [[ "$validated_sid" != "$sid" ]]; then
        state_digest=$(_awm_sha256_file "$mapping") || return 1
        builtin printf 'invalid\037%s\037%s\037%s\037%s\n' \
            "$synthetic" "$state_digest" "$mapping" "$canonical"
        return 0
    fi
    session_dir="$AWM_ROOT/sessions/projects/$sid"
    manifest="$session_dir/manifest.json"
    if [[ ! -f "$manifest" || -L "$manifest" ]]; then
        state_digest=$(_awm_sha256_file "$mapping") || return 1
        builtin printf 'invalid\037%s\037%s\037%s\037%s\n' "$sid" "$state_digest" "$mapping" "$canonical"
        return 0
    fi
    manifest_raw=$(<"$manifest") || return 1
    if ! _mainframe_durable_awm_manifest_identity_is_exact "$manifest_raw" ||
       [[ $(builtin printf '%s' "$manifest_raw" | _mainframe_durable_awm_jq -r '.session_id') != "$sid" ]] ||
       ! _awm_project_bind_expected_readonly "$sid" >/dev/null 2>&1; then
        state_digest=$(_awm_sha256_file "$mapping") || return 1
        builtin printf 'invalid\037%s\037%s\037%s\037%s\n' "$sid" "$state_digest" "$mapping" "$canonical"
        return 0
    fi
    status=$(builtin printf '%s' "$manifest_raw" | _mainframe_durable_awm_jq -r '.status') || return 1
    state_digest=$(_mainframe_durable_awm_state_digest "$mapping" "$sid") || return 1
    [[ "$status" == active ]] && status=active || status=closed
    builtin printf '%s\037%s\037%s\037%s\037%s\n' \
        "$status" "$sid" "$state_digest" "$mapping" "$canonical"
}

_mainframe_durable_awm_hidden_observer() {
    local fields state sid state_digest mapping canonical project_digest
    _mainframe_durable_awm_prepare_hidden_root || return $?
    fields=$(_mainframe_durable_awm_observe_fields .) || return 1
    IFS=$'\037' read -r state sid state_digest mapping canonical <<<"$fields"
    project_digest=$(_mainframe_durable_awm_sha256_text "$canonical") || return 1
    # shellcheck disable=SC2016 # jq variables, not shell variables.
    _mainframe_durable_awm_jq -cnS \
        --arg project_digest "$project_digest" \
        --arg mapping_state "$state" \
        --arg session_id "$sid" \
        --arg state_digest "$state_digest" '
        {
          schema_version: 1,
          project_digest: $project_digest,
          mapping_state: $mapping_state,
          session_id: (if $session_id == "" then null else $session_id end),
          state_digest: $state_digest
        }
    '
}

_mainframe_durable_awm_input_is_exact() {
    local tool="$1" raw="$2"
    _mainframe_durable_awm_require_canonical_json "$raw" || return 1
    case "$tool" in
        "$_MAINFRAME_PROJECT_MEMORY_SESSION"|"$_MAINFRAME_PROJECT_MEMORY_STATUS")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e \
                'type == "object" and keys == []' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_GET")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys == ["default","key"] and
                (.key | type == "string" and utf8bytelength >= 1 and utf8bytelength <= 1024) and
                (.default | type == "string" and utf8bytelength <= 24576)
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_SUMMARY")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys == ["max_tokens"] and
                (.max_tokens | type == "number" and floor == . and . >= 0 and . <= 1000000)
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_CONTEXT")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys == ["include","max_tokens","render_format","task"] and
                (.task | type == "string" and utf8bytelength >= 1 and utf8bytelength <= 1024) and
                (.include | type == "string" and utf8bytelength >= 1 and utf8bytelength <= 4096) and
                (.render_format == "json" or .render_format == "prompt") and
                (.max_tokens | type == "number" and floor == . and . >= 0 and . <= 1000000)
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_FIND")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys == ["kind","limit","query"] and
                (.query | type == "string" and utf8bytelength >= 1 and utf8bytelength <= 1024) and
                (.kind == "discovery" or .kind == "checkpoint" or .kind == "log" or .kind == "mixed") and
                (.limit | type == "number" and floor == . and . >= 1 and . <= 100000)
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_ENSURE")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and ((keys == []) or (keys == ["name"])) and
                ((has("name") | not) or (.name | type == "string"))
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_CHECKPOINT")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys ==
                  ["expected_session_id","importance","key","tags","ttl_seconds","value"] and
                (.expected_session_id | type == "string") and (.key | type == "string") and
                (.value | type == "string") and (.importance | type == "string") and
                (.tags | type == "array" and all(.[]; type == "string")) and
                (.ttl_seconds | type == "number")
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_DISCOVERY")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys ==
                  ["expected_session_id","importance","tags","value"] and
                (.expected_session_id | type == "string") and (.value | type == "string") and
                (.importance | type == "string") and
                (.tags | type == "array" and all(.[]; type == "string"))
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_PROGRESS")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys ==
                  ["current","expected_session_id","status","task","total"] and
                (.expected_session_id | type == "string") and (.task | type == "string") and
                (.status | type == "string") and (.current | type == "number") and
                (.total | type == "number")
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_CLOSE")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys == ["expected_session_id"] and
                (.expected_session_id | type == "string")
            ' >/dev/null
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_HANDOFF")
            builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
                type == "object" and keys ==
                  ["expected_session_id","max_tokens","render_format","target"] and
                (.expected_session_id | type == "string") and (.target | type == "string") and
                (.max_tokens | type == "number") and (.render_format | type == "string")
            ' >/dev/null
            ;;
        *) return 1 ;;
    esac
}

_mainframe_durable_awm_identity_is_exact() {
    local raw="$1" tool="$2"
    _mainframe_durable_awm_require_canonical_json "$raw" || return 1
    # shellcheck disable=SC2016 # jq variables, not shell variables.
    builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e --arg tool "$tool" '
        type == "object" and keys == [
          "actor","call_id","decision_id","evidence_id","expires_at","handoff_id",
          "input_digest","memory_id","memory_op_id","observation","policy",
          "project_digest","retention_class","run_id","schema_version","timeout_at",
          "tool","workspace"
        ] and .schema_version == 1 and .tool == $tool and
        (.observation | type == "object" and keys ==
          ["mapping_state","project_digest","session_id","state_digest"])
    ' >/dev/null || return 1
    if _mainframe_durable_awm_tool_is_read "$tool"; then
        builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -e '
            .memory_id == null and .handoff_id == null and
            .retention_class == "session" and .expires_at == null and
            (.observation.mapping_state == "absent" or
             .observation.mapping_state == "active" or
             .observation.mapping_state == "closed" or
             .observation.mapping_state == "invalid") and
            (if .observation.mapping_state == "absent" then
               .observation.session_id == null
             else
               (.observation.session_id | type == "string" and
                test("^[0-9a-f]{12}$"))
             end)
        ' >/dev/null || return 1
    fi
    return 0
}

_mainframe_durable_awm_tags_csv() {
    local raw="$1"
    # The public compatibility grammar defines tags as comma-separated. Reject
    # values that cannot round-trip through that existing representation.
    builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -er '
        if any(.tags[]; contains(","))
        then error("tag is not AWM-compatible") else (.tags | join(",")) end
    '
}

_mainframe_durable_awm_receipt() {
    local identity="$1" input="$2" outcome="$3" sid="$4" before="$5" after="$6"
    local transient="$7" record_type="$8" tool expected key recipient raw_value
    local key_sha value_sha value_bytes recipient_sha
    tool=$(builtin printf '%s' "$identity" | _mainframe_durable_awm_jq -r '.tool') || return 1
    expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id // empty') || return 1
    key='' recipient='' raw_value=''
    case "$tool" in
        "$_MAINFRAME_PROJECT_MEMORY_SESSION"|\
        "$_MAINFRAME_PROJECT_MEMORY_STATUS"|\
        "$_MAINFRAME_PROJECT_MEMORY_SUMMARY")
            raw_value="$transient"
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_GET")
            key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.key') || return 1
            raw_value="$transient"
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_CONTEXT")
            key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.task') || return 1
            raw_value="$transient"
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_FIND")
            key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.query') || return 1
            raw_value="$transient"
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_CHECKPOINT")
            key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.key') || return 1
            raw_value=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.value') || return 1
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_DISCOVERY")
            raw_value=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.value') || return 1
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_PROGRESS")
            key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.task') || return 1
            raw_value=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -cS \
                '{current:.current,status:.status,total:.total}') || return 1
            ;;
        "$_MAINFRAME_PROJECT_MEMORY_HANDOFF")
            recipient=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.target') || return 1
            raw_value="$transient"
            ;;
    esac
    key_sha=''; recipient_sha=''
    [[ -z "$key" ]] || key_sha=$(_mainframe_durable_awm_sha256_text "$key") || return 1
    [[ -z "$recipient" ]] || recipient_sha=$(_mainframe_durable_awm_sha256_text "$recipient") || return 1
    value_sha=$(_mainframe_durable_awm_sha256_text "$raw_value") || return 1
    value_bytes=$(_mainframe_durable_awm_bytes "$raw_value") || return 1
    # shellcheck disable=SC2016 # jq variables, not shell variables.
    _mainframe_durable_awm_jq -cnS \
        --argjson identity "$identity" --arg outcome "$outcome" \
        --arg expected "$expected" --arg sid "$sid" --arg record_type "$record_type" \
        --arg key_sha "$key_sha" --arg value_sha "$value_sha" \
        --argjson value_bytes "$value_bytes" --arg recipient_sha "$recipient_sha" \
        --arg before "$before" --arg after "$after" '
        {
          schema_version:1,
          memory_op_id:$identity.memory_op_id,
          memory_id:$identity.memory_id,
          handoff_id:$identity.handoff_id,
          run_id:$identity.run_id,
          call_id:$identity.call_id,
          decision_id:$identity.decision_id,
          evidence_id:$identity.evidence_id,
          tool:$identity.tool,
          input_digest:$identity.input_digest,
          actor:$identity.actor,
          workspace:$identity.workspace,
          policy:$identity.policy,
          project_digest:$identity.project_digest,
          expected_session_id:(if $expected == "" then null else $expected end),
          session_id:(if $sid == "" then null else $sid end),
          outcome:$outcome,
          idempotency_key:$identity.memory_op_id,
          record_type:$record_type,
          key_sha256:(if $key_sha == "" then null else $key_sha end),
          value_sha256:$value_sha,
          value_bytes:$value_bytes,
          recipient_sha256:(if $recipient_sha == "" then null else $recipient_sha end),
          retention_class:$identity.retention_class,
          expires_at:$identity.expires_at,
          state_digest_before:$before,
          state_digest_after:$after,
          observed_mapping_state:$identity.observation.mapping_state,
          observed_session_id:$identity.observation.session_id,
          observed_state_digest:$identity.observation.state_digest,
          trust_label:"kernel_bound",
          authoritative:false
        }
    '
}

# Preserve exact trailing newlines while keeping read output in memory. The
# appended record separator is removed after command substitution has already
# performed its normal trailing-newline trimming.
_mainframe_durable_awm_capture_output() {
    local destination="$1"
    shift
    local captured rc
    if captured="$("$@"; rc=$?; builtin printf '\036'; exit "$rc")"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$captured" == *$'\036' ]] || return 1
    captured="${captured%$'\036'}"
    builtin printf -v "$destination" '%s' "$captured"
    return "$rc"
}

_mainframe_durable_awm_read_session() {
    builtin printf '%s\n' "$1"
}

_mainframe_durable_awm_read_get() {
    local sid="$1" key="$2" default="$3" safe_key dir file metadata_rc
    safe_key=$(_awm_sanitize_key "$key") || return 1
    _awm_validate_storage_component "$safe_key" "checkpoint key" 128 || return 1
    [[ "$safe_key" != *.lock ]] || return 1
    dir=$(_awm_session_dir "$sid") || return 1
    file="$dir/data/$safe_key"
    if [[ ! -e "$file" && ! -L "$file" ]]; then
        builtin printf '%s' "$default"
        return 0
    fi
    [[ -f "$file" && ! -L "$file" ]] || return 1
    if _awm_checkpoint_metadata "$sid" "$safe_key" "$file" >/dev/null 2>&1; then
        metadata_rc=0
    else
        metadata_rc=$?
    fi
    (( metadata_rc == 0 )) || return 1
    /bin/cat -- "$file"
}

_mainframe_durable_awm_read_context() {
    local task="$1" tokens="$2" format="$3" include="$4"
    AWM_CHARS_PER_TOKEN=4 awm_context_for "$task" \
        --tokens "$tokens" --format "$format" --include "$include"
}

_mainframe_durable_awm_read_find() {
    local query="$1" kind="$2" limit="$3"
    AWM_ANONYMOUS_READS=1 awm_find "$query" --kind "$kind" --limit "$limit"
}

_mainframe_durable_awm_apply_locked() {
    local tool="$1" identity="$2" input="$3" mapping="$4" project_digest="$5"
    local observed_state observed_sid observed_digest fields state sid before after canonical
    local name expected key value importance tags ttl task current total status target tokens format include
    local query kind limit default is_read=false receipt_before
    local transient='' outcome=succeeded error_code='' record_type rc receipt transient_sha transient_bytes
    observed_state=$(builtin printf '%s' "$identity" | _mainframe_durable_awm_jq -r '.observation.mapping_state') || return 1
    observed_sid=$(builtin printf '%s' "$identity" | _mainframe_durable_awm_jq -r '.observation.session_id // empty') || return 1
    observed_digest=$(builtin printf '%s' "$identity" | _mainframe_durable_awm_jq -r '.observation.state_digest') || return 1
    _mainframe_durable_awm_tool_is_read "$tool" && is_read=true
    receipt_before="$observed_digest"
    fields=$(_mainframe_durable_awm_observe_fields .) || return 1
    IFS=$'\037' read -r state sid before mapping canonical <<<"$fields"
    if [[ "$state" != "$observed_state" || "$sid" != "$observed_sid" ||
          "$before" != "$observed_digest" ]]; then
        outcome=recovery_required
        error_code=recovery_required
        if [[ "$is_read" == true ]]; then
            sid="$observed_sid"
        else
            sid="${sid:-${observed_sid:-${project_digest:0:12}}}"
        fi
        after="$before"
    elif [[ "$state" == invalid || ( "$state" == absent && "$is_read" == true ) ||
            ( "$state" == closed && "$is_read" != true ) ]]; then
        outcome=recovery_required
        error_code=recovery_required
        if [[ "$is_read" == true ]]; then
            sid="$observed_sid"
        else
            sid="${sid:-${project_digest:0:12}}"
        fi
        after="$before"
    else
        if [[ "$is_read" == true ]]; then
            _awm_project_bind_expected_readonly "$sid" || return 1
        fi
        case "$tool" in
            "$_MAINFRAME_PROJECT_MEMORY_SESSION")
                if _mainframe_durable_awm_capture_output transient \
                    _mainframe_durable_awm_read_session "$sid"; then rc=0; else rc=$?; fi
                record_type=project_session
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_STATUS")
                if _mainframe_durable_awm_capture_output transient \
                    awm_project_status .; then rc=0; else rc=$?; fi
                record_type=project_status
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_GET")
                key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.key') || return 1
                default=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.default') || return 1
                if _mainframe_durable_awm_capture_output transient \
                    _mainframe_durable_awm_read_get "$sid" "$key" "$default"; then rc=0; else rc=$?; fi
                record_type=project_get
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_SUMMARY")
                tokens=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.max_tokens') || return 1
                if _mainframe_durable_awm_capture_output transient \
                    awm_summary --tokens "$tokens"; then rc=0; else rc=$?; fi
                record_type=project_summary
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_CONTEXT")
                task=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.task') || return 1
                tokens=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.max_tokens') || return 1
                format=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.render_format') || return 1
                include=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.include') || return 1
                if _mainframe_durable_awm_capture_output transient \
                    _mainframe_durable_awm_read_context "$task" "$tokens" "$format" "$include"; then rc=0; else rc=$?; fi
                record_type=project_context
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_FIND")
                query=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.query') || return 1
                kind=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.kind') || return 1
                limit=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.limit') || return 1
                if _mainframe_durable_awm_capture_output transient \
                    _mainframe_durable_awm_read_find "$query" "$kind" "$limit"; then rc=0; else rc=$?; fi
                record_type=project_find
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_ENSURE")
                name=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.name // empty') || return 1
                if [[ "$state" == absent ]]; then
                    if sid=$(_awm_project_ensure_unlocked "$mapping" "$project_digest" "$name" unmapped ''); then rc=0; else rc=$?; fi
                else
                    if sid=$(_awm_project_ensure_unlocked "$mapping" "$project_digest" "$name" '' ''); then rc=0; else rc=$?; fi
                fi
                record_type=session_ensure
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_CHECKPOINT")
                expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id') || return 1
                key=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.key') || return 1
                value=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.value') || return 1
                importance=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.importance') || return 1
                tags=$(_mainframe_durable_awm_tags_csv "$input") || return 1
                ttl=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.ttl_seconds') || return 1
                if _awm_project_mutate_expected_unlocked "$mapping" "$project_digest" "$expected" \
                    checkpoint "$key" "$value" --importance "$importance" --tags "$tags" --ttl "$ttl"; then rc=0; else rc=$?; fi
                sid="$expected" record_type=checkpoint
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_DISCOVERY")
                expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id') || return 1
                value=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.value') || return 1
                importance=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.importance') || return 1
                tags=$(_mainframe_durable_awm_tags_csv "$input") || return 1
                if _awm_project_mutate_expected_unlocked "$mapping" "$project_digest" "$expected" \
                    discovery "$value" --importance "$importance" --tags "$tags"; then rc=0; else rc=$?; fi
                sid="$expected" record_type=discovery
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_PROGRESS")
                expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id') || return 1
                task=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.task') || return 1
                current=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.current') || return 1
                total=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.total') || return 1
                status=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.status') || return 1
                if _awm_project_mutate_expected_unlocked "$mapping" "$project_digest" "$expected" \
                    progress "$task" "$current/$total" "$status"; then rc=0; else rc=$?; fi
                sid="$expected" record_type=progress
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_CLOSE")
                expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id') || return 1
                if _awm_project_mutate_expected_unlocked "$mapping" "$project_digest" "$expected" close; then rc=0; else rc=$?; fi
                sid="$expected" record_type=session_close
                ;;
            "$_MAINFRAME_PROJECT_MEMORY_HANDOFF")
                expected=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.expected_session_id') || return 1
                target=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.target') || return 1
                tokens=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.max_tokens') || return 1
                format=$(builtin printf '%s' "$input" | _mainframe_durable_awm_jq -r '.render_format') || return 1
                if transient=$(_awm_project_mutate_expected_unlocked "$mapping" "$project_digest" "$expected" \
                    handoff_prepare "$target" --tokens "$tokens" --format "$format"); then rc=0; else rc=$?; fi
                sid="$expected" record_type=handoff
                ;;
            *) return 1 ;;
        esac
        if (( rc != 0 )); then
            outcome=failed
            if [[ "$is_read" == true ]]; then
                error_code=awm_read_failed
            else
                error_code=awm_mutation_failed
            fi
        fi
        fields=$(_mainframe_durable_awm_observe_fields .) || return 1
        IFS=$'\037' read -r state _ after mapping canonical <<<"$fields"
        if [[ "$is_read" == true && "$after" != "$before" ]]; then
            outcome=recovery_required
            error_code=recovery_required
            transient=''
        fi
    fi
    [[ -n "${record_type:-}" ]] || {
        case "$tool" in
            "$_MAINFRAME_PROJECT_MEMORY_ENSURE") record_type=session_ensure ;;
            "$_MAINFRAME_PROJECT_MEMORY_CHECKPOINT") record_type=checkpoint ;;
            "$_MAINFRAME_PROJECT_MEMORY_DISCOVERY") record_type=discovery ;;
            "$_MAINFRAME_PROJECT_MEMORY_PROGRESS") record_type=progress ;;
            "$_MAINFRAME_PROJECT_MEMORY_CLOSE") record_type=session_close ;;
            "$_MAINFRAME_PROJECT_MEMORY_HANDOFF") record_type=handoff ;;
            "$_MAINFRAME_PROJECT_MEMORY_SESSION") record_type=project_session ;;
            "$_MAINFRAME_PROJECT_MEMORY_STATUS") record_type=project_status ;;
            "$_MAINFRAME_PROJECT_MEMORY_GET") record_type=project_get ;;
            "$_MAINFRAME_PROJECT_MEMORY_SUMMARY") record_type=project_summary ;;
            "$_MAINFRAME_PROJECT_MEMORY_CONTEXT") record_type=project_context ;;
            "$_MAINFRAME_PROJECT_MEMORY_FIND") record_type=project_find ;;
        esac
    }
    if [[ "$outcome" != succeeded ]]; then transient=''; fi
    transient_bytes=$(_mainframe_durable_awm_bytes "$transient") || return 1
    (( transient_bytes <= 32768 )) || return 1
    transient_sha=$(_mainframe_durable_awm_sha256_text "$transient") || return 1
    receipt=$(_mainframe_durable_awm_receipt \
        "$identity" "$input" "$outcome" "$sid" "$receipt_before" "$after" "$transient" "$record_type") || return 1
    if [[ -n "$transient" ]]; then
        builtin printf '%s' "$transient" >&196 || return 1
    fi
    exec 196>&-
    # shellcheck disable=SC2016 # jq variables, not shell variables.
    _mainframe_durable_awm_jq -cnS \
        --arg outcome "$outcome" --argjson receipt "$receipt" \
        --arg error_code "$error_code" --argjson transient_bytes "$transient_bytes" \
        --arg transient_sha "$transient_sha" '
        {
          schema_version:1,
          outcome:$outcome,
          receipt:$receipt,
          error_code:(if $error_code == "" then null else $error_code end),
          transient_bytes:$transient_bytes,
          transient_sha256:$transient_sha
        }
    '
}

_mainframe_durable_awm_hidden_executor() {
    local tool="$1" identity input fields state sid digest mapping canonical project_digest
    [[ -w /dev/fd/196 && -r /dev/fd/197 && -r /dev/fd/198 ]] || return 126
    _mainframe_durable_awm_start_liveness_guardian 198 || return $?
    exec 198<&-
    _mainframe_durable_awm_prepare_hidden_root || return $?
    identity=$(/bin/cat <&197) || return 1
    exec 197<&-
    input=$(/bin/cat) || return 1
    (( $(_mainframe_durable_awm_bytes "$identity") <= 16384 )) || return 1
    (( $(_mainframe_durable_awm_bytes "$input") <= 32768 )) || return 1
    _mainframe_durable_awm_identity_is_exact "$identity" "$tool" || return 1
    _mainframe_durable_awm_input_is_exact "$tool" "$input" || return 1
    project_digest=$(builtin printf '%s' "$identity" | _mainframe_durable_awm_jq -r '.project_digest') || return 1
    [[ "$project_digest" == "$(_mainframe_durable_awm_sha256_text "$(pwd -P)")" ]] || return 1
    fields=$(_mainframe_durable_awm_observe_fields .) || return 1
    IFS=$'\037' read -r state sid digest mapping canonical <<<"$fields"
    _awm_with_lock "${mapping}.lock" _mainframe_durable_awm_apply_locked \
        "$tool" "$identity" "$input" "$mapping" "$project_digest"
}

_mainframe_durable_awm_owner_mode() {
    local path="$1" result
    result=$(/usr/bin/stat -c '%u %a' "$path" 2>/dev/null ||
        /usr/bin/stat -f '%u %Mp%Lp' "$path" 2>/dev/null) || return 1
    [[ "$result" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    printf '%s\n' "$result"
}

_mainframe_durable_awm_forwarded_state() {
    local state="${XDG_STATE_HOME:-}" owner_mode owner mode numeric
    [[ "$state" == /* && -d "$state" && ! -L "$state" ]] || return 1
    owner_mode=$(_mainframe_durable_awm_owner_mode "$state") || return 1
    read -r owner mode <<<"$owner_mode"
    numeric=$((8#$mode))
    [[ "$owner" -eq "$EUID" ]] && (( (numeric & 0077) == 0 )) || return 1
    printf '%s' "$state"
}

_mainframe_durable_awm_default_state() {
    # Match the kernel's fixed system-Python trust anchor. The CLI resolver may
    # return a versioned canonical path; its spelling must not select storage.
    local python=/usr/bin/python3 home
    [[ -x "$python" ]] || python=/bin/python3
    [[ -x "$python" ]] || return 1
    home=$("$python" -I -S -B -c \
        'import os,pwd; print(pwd.getpwuid(os.geteuid()).pw_dir, end="")') || return 1
    [[ "$home" == /* && "$home" != / && "$home" != *$'\n'* ]] || return 1
    printf '%s/.local/state' "${home%/}"
}

_mainframe_durable_awm_storage_root() {
    local state
    state=$(_mainframe_durable_awm_forwarded_state 2>/dev/null ||
        _mainframe_durable_awm_default_state) || return 1
    printf '%s/mainframe/.mainframe-control-plane-runtime/project-memory-adapter-state/awm' \
        "${state%/}"
}

_mainframe_durable_awm_existing_storage_is_private() {
    local root="$1" state_path current owner_mode owner mode numeric
    [[ "$root" == /* && "$root" != / && -d "$root" && ! -L "$root" ]] || return 1
    state_path="${root%/project-memory-adapter-state/awm}"
    [[ "$state_path" != "$root" ]] || return 1
    for current in \
        "$state_path" \
        "$state_path/project-memory-adapter-state" \
        "$root"; do
        [[ -d "$current" && ! -L "$current" ]] || return 1
        owner_mode=$(_mainframe_durable_awm_owner_mode "$current") || return 1
        read -r owner mode <<<"$owner_mode"
        [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
        numeric=$((8#$mode))
        [[ "$owner" -eq "$EUID" ]] && (( (numeric & 0077) == 0 )) || return 1
    done
}

# Root discovery is presentation-only, but it must inspect the same fixed
# private mapping tree as the kernel adapter. Ambient AWM_ROOT and HOME never
# select this path. An unsafe existing tree is an error rather than a signal to
# skip inward mapping evidence and silently choose another project identity.
_mainframe_durable_awm_discover_root() (
    local project="${1:-.}" root
    root=$(_mainframe_durable_awm_storage_root) || return 1
    if [[ -e "$root" || -L "$root" ]]; then
        _mainframe_durable_awm_existing_storage_is_private "$root" || return 1
    fi
    AWM_ROOT="$root"
    export AWM_ROOT
    _awm_project_discover_root "$project"
)

_mainframe_durable_awm_expected_session() {
    local canonical="$1" project_digest="$2" root mapping raw sid
    root=$(_mainframe_durable_awm_storage_root) || return 1
    _mainframe_durable_awm_existing_storage_is_private "$root" || return 1
    mapping="${root%/}/projects/${project_digest}.json"
    [[ -f "$mapping" && ! -L "$mapping" ]] || return 1
    raw=$(<"$mapping") || return 1
    _mainframe_durable_awm_mapping_is_exact "$raw" || return 1
    [[ $(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -r '.project_sha256') == "$project_digest" ]] || return 1
    sid=$(builtin printf '%s' "$raw" | _mainframe_durable_awm_jq -r '.session_id') || return 1
    [[ "$sid" =~ ^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}$ ]] || return 1
    printf '%s' "$sid"
}

_mainframe_durable_awm_tags_json() {
    local csv="$1" tag first=true result='['
    [[ -n "$csv" ]] || { builtin printf '[]'; return 0; }
    local -a tags=()
    IFS=',' read -r -a tags <<<"$csv"
    for tag in "${tags[@]}"; do
        [[ -n "$tag" ]] || return 2
        if [[ "$first" == true ]]; then first=false; else result+=','; fi
        result+='"'"$(_awm_json_escape "$tag")"'"'
    done
    result+=']'
    builtin printf '%s' "$result"
}

_mainframe_durable_awm_exec_public() {
    local launcher="$1" canonical="$2" tool="$3" input="$4" correlation="$5"
    local state owner_mode owner mode numeric
    local -a environment=(
        /usr/bin/env -i
        "USER=${USER:-}"
        "LOGNAME=${LOGNAME:-}"
        TMPDIR=/tmp
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        LC_ALL=C
        NO_COLOR=1
        TERM=dumb
    )
    state=$(_mainframe_durable_awm_forwarded_state 2>/dev/null || true)
    [[ -z "$state" ]] || environment+=("XDG_STATE_HOME=$state")
    builtin cd -- "$canonical" || return 1
    exec 0< <(builtin printf '%s' "$input")
    exec "${environment[@]}" "$launcher" project-memory-invoke \
        --tool-id "$tool" --input-json - \
        --client-correlation-id "$correlation" --format awm-compatible-v1
}

_mainframe_durable_awm_public_mutation() {
    local action="$1" project="$2"
    shift 2
    local canonical project_digest sid tool input correlation epoch
    local name key value importance tags ttl task progress current total status target tokens format
    local tags_json
    IFS=$'\t' read -r canonical project_digest < <(_awm_project_identity "$project") || return 1
    case "$action" in
        ensure)
            name="${1:-}"
            tool="$_MAINFRAME_PROJECT_MEMORY_ENSURE"
            if [[ -n "$name" ]]; then
                input='{"name":"'"$(_awm_json_escape "$name")"'"}'
            else
                input='{}'
            fi
            ;;
        checkpoint)
            sid=$(_mainframe_durable_awm_expected_session "$canonical" "$project_digest") || {
                echo 'Project memory mutation denied: durable session identity is unavailable' >&2
                return 69
            }
            key="$1" value="$2" importance=normal tags='' ttl=0; shift 2
            while (( $# > 0 )); do
                case "$1" in
                    --importance) importance="$2" ;;
                    --tags) tags="$2" ;;
                    --ttl) ttl=$((10#$2)) ;;
                esac
                shift 2
            done
            tags_json=$(_mainframe_durable_awm_tags_json "$tags") || return 2
            tool="$_MAINFRAME_PROJECT_MEMORY_CHECKPOINT"
            input='{"expected_session_id":"'"$sid"'","importance":"'"$importance"'","key":"'"$(_awm_json_escape "$key")"'","tags":'"$tags_json"',"ttl_seconds":'"$ttl"',"value":"'"$(_awm_json_escape "$value")"'"}'
            ;;
        discovery)
            sid=$(_mainframe_durable_awm_expected_session "$canonical" "$project_digest") || return 69
            value="$1" importance=high tags=''; shift
            while (( $# > 0 )); do
                case "$1" in --importance) importance="$2" ;; --tags) tags="$2" ;; esac
                shift 2
            done
            tags_json=$(_mainframe_durable_awm_tags_json "$tags") || return 2
            tool="$_MAINFRAME_PROJECT_MEMORY_DISCOVERY"
            input='{"expected_session_id":"'"$sid"'","importance":"'"$importance"'","tags":'"$tags_json"',"value":"'"$(_awm_json_escape "$value")"'"}'
            ;;
        progress)
            sid=$(_mainframe_durable_awm_expected_session "$canonical" "$project_digest") || return 69
            task="$1" progress="$2" status="${3:-}"
            current=$((10#${progress%/*})) total=$((10#${progress#*/}))
            tool="$_MAINFRAME_PROJECT_MEMORY_PROGRESS"
            input='{"current":'"$current"',"expected_session_id":"'"$sid"'","status":"'"$(_awm_json_escape "$status")"'","task":"'"$(_awm_json_escape "$task")"'","total":'"$total"'}'
            ;;
        close)
            sid=$(_mainframe_durable_awm_expected_session "$canonical" "$project_digest") || return 69
            tool="$_MAINFRAME_PROJECT_MEMORY_CLOSE"
            input='{"expected_session_id":"'"$sid"'"}'
            ;;
        handoff)
            sid=$(_mainframe_durable_awm_expected_session "$canonical" "$project_digest") || return 69
            target="$1" tokens=0 format=json; shift
            while (( $# > 0 )); do
                case "$1" in --tokens) tokens=$((10#$2)) ;; --format) format="$2" ;; esac
                shift 2
            done
            tool="$_MAINFRAME_PROJECT_MEMORY_HANDOFF"
            input='{"expected_session_id":"'"$sid"'","max_tokens":'"$tokens"',"render_format":"'"$format"'","target":"'"$(_awm_json_escape "$target")"'"}'
            ;;
        *) return 64 ;;
    esac
    epoch=$(/bin/date -u '+%s' 2>/dev/null) || return 70
    correlation="client-memory-${epoch}-$$-$RANDOM"
    _mainframe_durable_awm_exec_public \
        "$MAINFRAME_ROOT/control_plane/mainframe-control-plane" \
        "$canonical" "$tool" "$input" "$correlation"
}

_mainframe_durable_awm_public_read() {
    local action="$1" project="$2"
    shift 2
    local canonical project_digest tool input correlation epoch
    local key default tokens task format include query kind limit
    IFS=$'\t' read -r canonical project_digest < <(_awm_project_identity "$project") || return 1
    case "$action" in
        session)
            tool="$_MAINFRAME_PROJECT_MEMORY_SESSION"
            input='{}'
            ;;
        status)
            tool="$_MAINFRAME_PROJECT_MEMORY_STATUS"
            input='{}'
            ;;
        get)
            key="$1" default="${2:-}"
            tool="$_MAINFRAME_PROJECT_MEMORY_GET"
            input='{"default":"'"$(_awm_json_escape "$default")"'","key":"'"$(_awm_json_escape "$key")"'"}'
            ;;
        summary)
            tokens=0
            while (( $# > 0 )); do
                case "$1" in --tokens) tokens=$((10#$2)) ;; esac
                shift 2
            done
            tool="$_MAINFRAME_PROJECT_MEMORY_SUMMARY"
            input='{"max_tokens":'"$tokens"'}'
            ;;
        context)
            task="$1" tokens=0 format=json include='discoveries,progress,checkpoints,logs'
            shift
            while (( $# > 0 )); do
                case "$1" in
                    --tokens) tokens=$((10#$2)) ;;
                    --format) format="$2" ;;
                    --include) include="$2" ;;
                esac
                shift 2
            done
            tool="$_MAINFRAME_PROJECT_MEMORY_CONTEXT"
            input='{"include":"'"$(_awm_json_escape "$include")"'","max_tokens":'"$tokens"',"render_format":"'"$format"'","task":"'"$(_awm_json_escape "$task")"'"}'
            ;;
        find)
            query="$1" kind=mixed limit=10
            shift
            while (( $# > 0 )); do
                case "$1" in --kind) kind="$2" ;; --limit) limit=$((10#$2)) ;; esac
                shift 2
            done
            tool="$_MAINFRAME_PROJECT_MEMORY_FIND"
            input='{"kind":"'"$kind"'","limit":'"$limit"',"query":"'"$(_awm_json_escape "$query")"'"}'
            ;;
        *) return 64 ;;
    esac
    epoch=$(/bin/date -u '+%s' 2>/dev/null) || return 70
    correlation="client-memory-read-${epoch}-$$-$RANDOM"
    _mainframe_durable_awm_exec_public \
        "$MAINFRAME_ROOT/control_plane/mainframe-control-plane" \
        "$canonical" "$tool" "$input" "$correlation"
}

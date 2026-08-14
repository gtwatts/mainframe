#!/usr/bin/env bats
# Deterministic project-AWM lifecycle races. These tests exercise the public
# CLI for agent-visible operations and use the core mapping lock only as a
# test barrier; they never inject executable hooks into production code.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"

    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-awm-project-atomic.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    HOME="$TEST_ROOT/home"
    AWM_ROOT="$TEST_ROOT/awm"
    MAINFRAME_CONFIG="$TEST_ROOT/mainframe-config"
    TEST_PROJECT="$TEST_ROOT/project"
    SECOND_PROJECT="$TEST_ROOT/second-project"
    BARRIER_ROOT="$TEST_ROOT/barriers"

    mkdir -p -- "$HOME" "$TEST_PROJECT" "$SECOND_PROJECT" "$BARRIER_ROOT"
    unset MAINFRAME_AWM_SESSION AWM_SESSION_ID _AWM_SESSION_ID
    export HOME AWM_ROOT MAINFRAME_CONFIG BASH_BIN

    ACTIVE_PIDS=()
    BARRIER_GO=""
    HELD_DATA_LOCK=""
}

teardown() {
    local barrier pid

    # Release a test barrier or deliberately held data lock before terminating
    # workers, so a failed assertion cannot leave a lock waiter behind.
    if [[ -d "${BARRIER_ROOT:-}" ]]; then
        while IFS= read -r -d '' barrier; do
            : > "$barrier/go"
        done < <(find "$BARRIER_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    if [[ -n "${HELD_DATA_LOCK:-}" && -d "$HELD_DATA_LOCK" ]]; then
        rmdir -- "$HELD_DATA_LOCK" 2>/dev/null || true
    fi

    for pid in "${ACTIVE_PIDS[@]:-}"; do
        terminate_process_tree "$pid"
    done
    for pid in "${ACTIVE_PIDS[@]:-}"; do
        wait "$pid" 2>/dev/null || true
    done

    if [[ -n "${TEST_ROOT:-}" && "$TEST_ROOT" != "/" &&
          "${TEST_ROOT##*/}" == mainframe-awm-project-atomic.* ]]; then
        rm -rf -- "$TEST_ROOT"
    fi
}

mf() {
    env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$MAINFRAME_BIN" "$@"
}

mf_native() {
    env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$MAINFRAME_BIN" "$@"
}

assert_sid_only() {
    local value="$1"
    [[ "$value" =~ ^[a-f0-9]{12}$ ]]
    [[ "$value" != *$'\n'* ]]
}

manifest_for_sid() {
    local sid="$1"
    printf '%s/sessions/projects/%s/manifest.json\n' "$AWM_ROOT" "$sid"
}

mapping_file() {
    local matches count
    matches="$(find "$AWM_ROOT/projects" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null | LC_ALL=C sort)"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    [[ "$count" == "1" ]] || {
        printf 'expected exactly one project mapping, found %s:\n%s\n' "$count" "$matches" >&2
        return 1
    }
    printf '%s\n' "$matches"
}

mapping_sid() {
    jq -r '.session_id' "$(mapping_file)"
}

session_manifest_count() {
    if [[ ! -d "$AWM_ROOT/sessions" ]]; then
        printf '0\n'
        return 0
    fi
    find "$AWM_ROOT/sessions" -type f -name manifest.json -print |
        wc -l | tr -d '[:space:]'
}

storage_content_fingerprint() {
    local store="${1:-$AWM_ROOT}"
    local path relative mode digest
    if [[ ! -e "$store" ]]; then
        printf '<absent>\n'
        return 0
    fi
    while IFS= read -r path; do
        relative="${path#"$store"/}"
        mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")"
        if [[ -f "$path" && ! -L "$path" ]]; then
            digest="$(cksum "$path" | awk '{print $1 ":" $2}')"
            printf 'file\t%s\t%s\t%s\n' "$relative" "$mode" "$digest"
        elif [[ -d "$path" && ! -L "$path" ]]; then
            printf 'dir\t%s\t%s\n' "$relative" "$mode"
        elif [[ -L "$path" ]]; then
            printf 'link\t%s\t%s\t%s\n' "$relative" "$mode" "$(readlink "$path")"
        else
            printf 'special\t%s\t%s\n' "$relative" "$mode"
        fi
    done < <(find "$store" -mindepth 1 -print | LC_ALL=C sort)
}

wait_for_file() {
    local path="$1"
    local attempt
    for ((attempt = 0; attempt < 1000; attempt++)); do
        [[ -e "$path" ]] && return 0
        sleep 0.01
    done
    printf 'timed out waiting for file: %s\n' "$path" >&2
    return 1
}

process_tree_has_sleep() {
    local root_pid="$1"
    local depth parent child command
    local -a frontier=("$root_pid")
    local -a next=()

    command -v pgrep >/dev/null 2>&1 || return 1
    for depth in 1 2 3 4 5 6; do
        next=()
        for parent in "${frontier[@]}"; do
            while IFS= read -r child; do
                [[ -n "$child" ]] || continue
                command="$(ps -o comm= -p "$child" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                case "$command" in
                    sleep|*/sleep) return 0 ;;
                esac
                next+=("$child")
            done < <(pgrep -P "$parent" 2>/dev/null || true)
        done
        (( ${#next[@]} > 0 )) || return 1
        frontier=("${next[@]}")
    done
    return 1
}

wait_for_lock_wait() {
    local pid="$1"
    local attempt
    for ((attempt = 0; attempt < 1000; attempt++)); do
        kill -0 "$pid" 2>/dev/null || return 1
        process_tree_has_sleep "$pid" && return 0
        sleep 0.01
    done
    printf 'process %s never entered the deterministic lock wait\n' "$pid" >&2
    return 1
}

terminate_process_tree() {
    local pid="${1:-}"
    local child
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    while IFS= read -r child; do
        [[ -n "$child" ]] || continue
        terminate_process_tree "$child"
    done < <(pgrep -P "$pid" 2>/dev/null || true)
    kill "$pid" 2>/dev/null || true
}

hold_data_lock() {
    local sid="$1"
    local key="$2"
    HELD_DATA_LOCK="$AWM_ROOT/sessions/projects/$sid/index/data.${key}.lock.dir"
    mkdir -- "$HELD_DATA_LOCK"
    chmod 700 "$HELD_DATA_LOCK"
}

release_data_lock() {
    [[ -n "$HELD_DATA_LOCK" ]]
    rmdir -- "$HELD_DATA_LOCK"
    HELD_DATA_LOCK=""
}

start_checkpoint_writer() {
    local key="$1"
    local value="$2"
    local label="$3"
    WRITER_STARTED="$TEST_ROOT/${label}.started"
    WRITER_STDOUT="$TEST_ROOT/${label}.stdout"
    WRITER_STDERR="$TEST_ROOT/${label}.stderr"

    (
        : > "$WRITER_STARTED"
        exec env \
            HOME="$HOME" \
            AWM_ROOT="$AWM_ROOT" \
            AWM_BACKEND=file \
            _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
            AWM_LOCK_TIMEOUT=20 \
            MAINFRAME_BASH="$BASH_BIN" \
            MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
            MAINFRAME_LIBS=awm \
            "$MAINFRAME_BIN" awm project checkpoint \
                --project "$TEST_PROJECT" "$key" "$value"
    ) >"$WRITER_STDOUT" 2>"$WRITER_STDERR" &
    WRITER_PID=$!
    ACTIVE_PIDS+=("$WRITER_PID")
    wait_for_file "$WRITER_STARTED"
}

start_project_close() {
    local label="$1"
    CLOSE_STARTED="$TEST_ROOT/${label}.started"
    CLOSE_STDOUT="$TEST_ROOT/${label}.stdout"
    CLOSE_STDERR="$TEST_ROOT/${label}.stderr"

    (
        : > "$CLOSE_STARTED"
        exec env \
            HOME="$HOME" \
            AWM_ROOT="$AWM_ROOT" \
            AWM_BACKEND=file \
            _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
            AWM_LOCK_TIMEOUT=20 \
            MAINFRAME_BASH="$BASH_BIN" \
            MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
            MAINFRAME_LIBS=awm \
            "$MAINFRAME_BIN" awm project close --project "$TEST_PROJECT"
    ) >"$CLOSE_STDOUT" 2>"$CLOSE_STDERR" &
    CLOSE_PID=$!
    ACTIVE_PIDS+=("$CLOSE_PID")
    wait_for_file "$CLOSE_STARTED"
}

start_project_mutation() {
    local label="$1"
    shift
    MUTATION_STARTED="$TEST_ROOT/${label}.started"
    MUTATION_STDOUT="$TEST_ROOT/${label}.stdout"
    MUTATION_STDERR="$TEST_ROOT/${label}.stderr"

    (
        : > "$MUTATION_STARTED"
        exec env \
            HOME="$HOME" \
            AWM_ROOT="$AWM_ROOT" \
            AWM_BACKEND=file \
            _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
            AWM_LOCK_TIMEOUT=20 \
            MAINFRAME_BASH="$BASH_BIN" \
            MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
            MAINFRAME_LIBS=awm \
            "$MAINFRAME_BIN" awm project "$@"
    ) >"$MUTATION_STDOUT" 2>"$MUTATION_STDERR" &
    MUTATION_PID=$!
    ACTIVE_PIDS+=("$MUTATION_PID")
    wait_for_file "$MUTATION_STARTED"
}

# Hold the canonical project mapping lock, optionally close the old session,
# and optionally renew it before releasing the lock. Production code supplies
# the lock and mutation primitives; the ready/go files are test-owned only.
start_mapping_barrier() {
    local mode="$1"
    local old_sid="$2"
    local label="$3"
    local barrier="$BARRIER_ROOT/$label"
    mkdir -p -- "$barrier"
    BARRIER_READY="$barrier/ready"
    BARRIER_GO="$barrier/go"
    BARRIER_STDOUT="$barrier/stdout"
    BARRIER_STDERR="$barrier/stderr"

    env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            set -euo pipefail
            source "$1/lib/awm.sh"
            project=$2
            old_sid=$3
            mode=$4
            ready=$5
            go=$6

            IFS=$'"'"'\t'"'"' read -r canonical digest < <(_awm_project_identity "$project")
            mapping=$(_awm_project_mapping_file "$digest")

            barrier_mutation() {
                local attempt
                : > "$ready"
                for ((attempt = 0; attempt < 2000; attempt++)); do
                    [[ -e "$go" ]] && break
                    sleep 0.01
                done
                [[ -e "$go" ]] || return 98

                case "$mode" in
                    hold)
                        return 0
                        ;;
                    close)
                        _awm_project_mutate_unlocked "$mapping" "$digest" close
                        ;;
                    renew)
                        _awm_project_mutate_unlocked "$mapping" "$digest" close
                        _awm_project_ensure_unlocked \
                            "$mapping" "$digest" atomic-renewal completed "$old_sid"
                        ;;
                    *)
                        return 2
                        ;;
                esac
            }

            _awm_with_lock "${mapping}.lock" barrier_mutation
        ' _ "$PROJECT_ROOT" "$TEST_PROJECT" "$old_sid" "$mode" \
            "$BARRIER_READY" "$BARRIER_GO" \
        >"$BARRIER_STDOUT" 2>"$BARRIER_STDERR" &
    BARRIER_PID=$!
    ACTIVE_PIDS+=("$BARRIER_PID")
    wait_for_file "$BARRIER_READY"
}

release_mapping_barrier() {
    : > "$BARRIER_GO"
    BARRIER_GO=""
}

wait_for_pid() {
    local pid="$1"
    local __result="$2"
    local rc
    if wait "$pid"; then
        rc=0
    else
        rc=$?
    fi
    printf -v "$__result" '%s' "$rc"
}

@test "public project close waits for an in-flight checkpoint transaction" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    local key="writer-wins"
    hold_data_lock "$sid" "$key"
    start_checkpoint_writer "$key" "committed-before-close" writer-wins
    wait_for_lock_wait "$WRITER_PID"

    start_project_close close-contender
    local close_was_blocked=false
    if wait_for_lock_wait "$CLOSE_PID"; then
        close_was_blocked=true
    fi

    release_data_lock
    local writer_rc close_rc
    wait_for_pid "$WRITER_PID" writer_rc
    wait_for_pid "$CLOSE_PID" close_rc

    [[ "$close_was_blocked" == "true" ]]
    [[ "$writer_rc" -eq 0 ]]
    [[ "$close_rc" -eq 0 ]]
    [[ ! -s "$WRITER_STDERR" ]]
    [[ ! -s "$CLOSE_STDERR" ]]
    [[ "$(<"$AWM_ROOT/sessions/projects/$sid/data/$key")" == "committed-before-close" ]]
    run jq -e '.status == "completed" and .namespace == "projects"' "$(manifest_for_sid "$sid")"
    [[ "$status" -eq 0 ]]
    [[ "$(mapping_sid)" == "$sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "close that wins the project lock makes a queued checkpoint refuse without reactivation" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    local key="close-wins"
    hold_data_lock "$sid" "$key"
    start_mapping_barrier close "$sid" close-wins-barrier
    start_checkpoint_writer "$key" "must-not-be-written" close-wins-writer
    wait_for_lock_wait "$WRITER_PID"

    release_mapping_barrier
    local barrier_rc writer_rc
    wait_for_pid "$BARRIER_PID" barrier_rc
    release_data_lock
    wait_for_pid "$WRITER_PID" writer_rc

    [[ "$barrier_rc" -eq 0 ]]
    [[ "$writer_rc" -ne 0 ]]
    [[ ! -e "$AWM_ROOT/sessions/projects/$sid/data/$key" ]]
    ! grep -R -F -- "$key" "$AWM_ROOT/sessions/projects/$sid" >/dev/null 2>&1
    run jq -e '.status == "completed" and .namespace == "projects"' "$(manifest_for_sid "$sid")"
    [[ "$status" -eq 0 ]]
    [[ "$(mapping_sid)" == "$sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "renewal that wins the project lock redirects a queued checkpoint only to the new SID" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local old_sid="$output"
    assert_sid_only "$old_sid"

    local key="renewal-wins"
    hold_data_lock "$old_sid" "$key"
    start_mapping_barrier renew "$old_sid" renewal-wins-barrier
    start_checkpoint_writer "$key" "new-session-only" renewal-wins-writer
    wait_for_lock_wait "$WRITER_PID"

    release_mapping_barrier
    local barrier_rc writer_rc
    wait_for_pid "$BARRIER_PID" barrier_rc
    local new_sid
    new_sid="$(<"$BARRIER_STDOUT")"
    assert_sid_only "$new_sid"
    [[ "$new_sid" != "$old_sid" ]]

    release_data_lock
    wait_for_pid "$WRITER_PID" writer_rc

    [[ "$barrier_rc" -eq 0 ]]
    [[ "$writer_rc" -eq 0 ]]
    [[ ! -s "$WRITER_STDERR" ]]
    [[ "$(mapping_sid)" == "$new_sid" ]]
    [[ ! -e "$AWM_ROOT/sessions/projects/$old_sid/data/$key" ]]
    ! grep -R -F -- "$key" "$AWM_ROOT/sessions/projects/$old_sid" >/dev/null 2>&1
    [[ "$(<"$AWM_ROOT/sessions/projects/$new_sid/data/$key")" == "new-session-only" ]]
    run jq -e '.status == "completed"' "$(manifest_for_sid "$old_sid")"
    [[ "$status" -eq 0 ]]
    run jq -e '.status == "active"' "$(manifest_for_sid "$new_sid")"
    [[ "$status" -eq 0 ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "close that wins the project lock rejects every queued public mutation family" {
    local action sid marker barrier_rc mutation_rc mutation_waited session_dir
    local -a args=()

    for action in discovery progress handoff; do
        run mf awm project ensure --project "$TEST_PROJECT"
        [[ "$status" -eq 0 ]]
        sid="$output"
        assert_sid_only "$sid"
        marker="queued-${action}-must-not-write"
        session_dir="$AWM_ROOT/sessions/projects/$sid"

        start_mapping_barrier close "$sid" "${action}-close-barrier"
        case "$action" in
            discovery)
                args=(discovery --project "$TEST_PROJECT" "$marker" --importance critical)
                ;;
            progress)
                args=(progress --project "$TEST_PROJECT" "$marker" 1/2 pending)
                ;;
            handoff)
                args=(handoff prepare --project "$TEST_PROJECT" "$marker" --tokens 512 --format json)
                ;;
        esac
        start_project_mutation "${action}-queued-writer" "${args[@]}"
        mutation_waited=false
        if wait_for_lock_wait "$MUTATION_PID"; then
            mutation_waited=true
        fi

        release_mapping_barrier
        wait_for_pid "$BARRIER_PID" barrier_rc
        wait_for_pid "$MUTATION_PID" mutation_rc

        [[ "$mutation_waited" == "true" ]]
        [[ "$barrier_rc" -eq 0 ]]
        [[ "$mutation_rc" -ne 0 ]]
        [[ ! -s "$MUTATION_STDOUT" ]]
        ! grep -R -F -- "$marker" "$session_dir" >/dev/null 2>&1
        run jq -e '.status == "completed" and .namespace == "projects"' \
            "$(manifest_for_sid "$sid")"
        [[ "$status" -eq 0 ]]
        [[ "$(mapping_sid)" == "$sid" ]]
    done

    [[ "$(session_manifest_count)" == "3" ]]
}

@test "native selected lock supports nested public project write and close transactions" {
    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/awm.sh"
            _awm_lock_strategy
        ' _ "$PROJECT_ROOT"
    [[ "$status" -eq 0 ]]
    case "$output" in
        flock|lockf|mkdir) ;;
        *) printf 'unexpected native lock strategy: %s\n' "$output" >&2; false ;;
    esac
    local native_strategy="$output"

    run mf_native awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"
    run mf_native awm project checkpoint --project "$TEST_PROJECT" \
        native-lock "nested-${native_strategy}"
    [[ "$status" -eq 0 ]]
    run mf_native awm project close --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]

    [[ "$(<"$AWM_ROOT/sessions/projects/$sid/data/native-lock")" == "nested-${native_strategy}" ]]
    run jq -e '.status == "completed"' "$(manifest_for_sid "$sid")"
    [[ "$status" -eq 0 ]]
    [[ "$(mapping_sid)" == "$sid" ]]
}

@test "confirmed ensure returns rc75 when the completed SID changes before execution" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local confirmed_sid="$output"
    assert_sid_only "$confirmed_sid"

    run mf awm project close --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    run jq -e '.status == "completed"' "$(manifest_for_sid "$confirmed_sid")"
    [[ "$status" -eq 0 ]]

    # A different actor renews the completed binding after the caller observed
    # and confirmed that exact completed SID.
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local replacement_sid="$output"
    assert_sid_only "$replacement_sid"
    [[ "$replacement_sid" != "$confirmed_sid" ]]
    local before after
    before="$(storage_content_fingerprint)"

    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/awm.sh"
            awm_project_ensure "$2" stale-confirmation completed "$3"
        ' _ "$PROJECT_ROOT" "$TEST_PROJECT" "$confirmed_sid"
    [[ "$status" -eq 75 ]]
    [[ "$output" == *"changed before confirmation completed"* ]]

    after="$(storage_content_fingerprint)"
    [[ "$after" == "$before" ]]
    [[ "$(mapping_sid)" == "$replacement_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
    run jq -e '.status == "completed"' "$(manifest_for_sid "$confirmed_sid")"
    [[ "$status" -eq 0 ]]
    run jq -e '.status == "active"' "$(manifest_for_sid "$replacement_sid")"
    [[ "$status" -eq 0 ]]
}

@test "confirmed close returns rc75 when the active SID or state changes before execution" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local confirmed_sid="$output"
    assert_sid_only "$confirmed_sid"

    # The exact confirmed session is completed by another actor before the
    # confirmation-bound close reaches the mapping lock.
    run mf awm project close --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local before after
    before="$(storage_content_fingerprint)"
    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/awm.sh"
            _awm_project_mutate_expected "$2" close "$3"
        ' _ "$PROJECT_ROOT" "$TEST_PROJECT" "$confirmed_sid"
    [[ "$status" -eq 75 ]]
    after="$(storage_content_fingerprint)"
    [[ "$after" == "$before" ]]

    # A renewal then changes the mapping as well. The stale confirmation still
    # refuses and cannot close the replacement session.
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local replacement_sid="$output"
    assert_sid_only "$replacement_sid"
    [[ "$replacement_sid" != "$confirmed_sid" ]]
    before="$(storage_content_fingerprint)"
    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/awm.sh"
            _awm_project_mutate_expected "$2" close "$3"
        ' _ "$PROJECT_ROOT" "$TEST_PROJECT" "$confirmed_sid"
    [[ "$status" -eq 75 ]]
    after="$(storage_content_fingerprint)"
    [[ "$after" == "$before" ]]
    [[ "$(mapping_sid)" == "$replacement_sid" ]]
    run jq -e '.status == "completed"' "$(manifest_for_sid "$confirmed_sid")"
    [[ "$status" -eq 0 ]]
    run jq -e '.status == "active"' "$(manifest_for_sid "$replacement_sid")"
    [[ "$status" -eq 0 ]]
}

@test "direct legacy mutators cannot alter or disclose a completed project session" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"
    run mf awm project checkpoint --project "$TEST_PROJECT" seed-key seed-value
    [[ "$status" -eq 0 ]]
    run mf awm project close --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]

    local action case_root export_path before after
    local direct_failures=""
    for action in snapshot append unset destroy migrate compress export; do
        case_root="$TEST_ROOT/direct-${action}/awm"
        mkdir -p -- "${case_root%/*}"
        cp -R -- "$AWM_ROOT" "$case_root"
        export_path="$TEST_ROOT/direct-${action}/forbidden-export.md"
        before="$(storage_content_fingerprint "$case_root")"

        run env \
            HOME="$HOME" \
            AWM_ROOT="$case_root" \
            AWM_BACKEND=file \
            _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
            AWM_LOCK_TIMEOUT=20 \
            MAINFRAME_ROOT="$PROJECT_ROOT" \
            "$BASH_BIN" --noprofile --norc -p -c '
                source "$1/lib/awm.sh"
                action=$2
                sid=$3
                export_path=$4
                case "$action" in
                    snapshot) awm_checkpoint "$sid" forbidden-snapshot ;;
                    append) awm_append "$sid" forbidden-append forbidden-value ;;
                    unset) awm_unset "$sid" seed-key ;;
                    destroy) awm_destroy "$sid" ;;
                    migrate) awm_migrate "$sid" ;;
                    compress) awm_compress "$sid" ;;
                    export)
                        _awm_project_bind_expected_readonly "$sid"
                        awm_export "$export_path"
                        ;;
                    *) exit 2 ;;
                esac
            ' _ "$PROJECT_ROOT" "$action" "$sid" "$export_path"
        if [[ "$status" -eq 0 ]]; then
            direct_failures+=" ${action}:returned-zero"
        fi
        if [[ -e "$export_path" ]]; then
            direct_failures+=" ${action}:created-export"
        fi

        after="$(storage_content_fingerprint "$case_root")"
        if [[ "$after" != "$before" ]]; then
            direct_failures+=" ${action}:changed-storage"
        fi
        if [[ ! -f "$case_root/sessions/projects/$sid/manifest.json" ]]; then
            direct_failures+=" ${action}:removed-session"
        elif ! jq -e '.status == "completed" and .namespace == "projects"' \
            "$case_root/sessions/projects/$sid/manifest.json" >/dev/null; then
            direct_failures+=" ${action}:changed-manifest"
        fi
        if [[ ! -f "$case_root/sessions/projects/$sid/data/seed-key" ]]; then
            direct_failures+=" ${action}:removed-seed"
        elif [[ "$(<"$case_root/sessions/projects/$sid/data/seed-key")" != "seed-value" ]]; then
            direct_failures+=" ${action}:changed-seed"
        fi
    done

    if [[ -n "$direct_failures" ]]; then
        printf 'completed-project direct mutator failures:%s\n' "$direct_failures" >&2
        false
    fi
}

@test "generic cleanup preserves completed project sessions and their mappings" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"
    run mf awm project checkpoint --project "$TEST_PROJECT" cleanup-seed preserve-me
    [[ "$status" -eq 0 ]]
    run mf awm project close --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]

    # Make the completed session unambiguously old enough for a zero-day
    # generic cleanup. Project sessions remain lifecycle-managed by their
    # private mapping and are never generic cleanup candidates.
    local manifest tmp before after
    manifest="$(manifest_for_sid "$sid")"
    tmp="$manifest.old"
    jq -c '.created_epoch = 1' "$manifest" > "$tmp"
    chmod 600 "$tmp"
    mv -- "$tmp" "$manifest"
    before="$(storage_content_fingerprint)"

    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=20 \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/awm.sh"
            awm_cleanup 0
        ' _ "$PROJECT_ROOT"
    [[ "$status" -eq 0 ]]
    if [[ "$output" != "0" ]]; then
        printf 'generic cleanup unexpectedly removed %s completed project session(s)\n' \
            "$output" >&2
        false
    fi

    after="$(storage_content_fingerprint)"
    [[ "$after" == "$before" ]]
    [[ "$(mapping_sid)" == "$sid" ]]
    [[ "$(<"$AWM_ROOT/sessions/projects/$sid/data/cleanup-seed")" == "preserve-me" ]]
    run jq -e '.status == "completed" and .namespace == "projects"' "$manifest"
    [[ "$status" -eq 0 ]]
}

@test "project mutation propagates rc97 on mapping-lock timeout without invoking the write" {
    run mf awm project ensure --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    start_mapping_barrier hold "$sid" timeout-barrier
    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 \
        AWM_LOCK_TIMEOUT=1 \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$MAINFRAME_BIN" awm project checkpoint \
            --project "$TEST_PROJECT" timeout-key timeout-value
    [[ "$status" -eq 97 ]]
    [[ ! -e "$AWM_ROOT/sessions/projects/$sid/data/timeout-key" ]]
    ! grep -R -F -- timeout-key "$AWM_ROOT/sessions/projects/$sid" >/dev/null 2>&1

    release_mapping_barrier
    local barrier_rc
    wait_for_pid "$BARRIER_PID" barrier_rc
    [[ "$barrier_rc" -eq 0 ]]
    run jq -e '.status == "active"' "$(manifest_for_sid "$sid")"
    [[ "$status" -eq 0 ]]
    [[ "$(mapping_sid)" == "$sid" ]]
}

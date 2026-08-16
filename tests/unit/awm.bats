#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/awm.bats - Agent Working Memory Unit Tests
# =============================================================================

# Load bats helpers
load "${BATS_TEST_DIRNAME}/../bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../bats-assert/load.bash"

# Test setup - load MAINFRAME
setup() {
    # Source the library
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "${MAINFRAME_ROOT}/lib/awm.sh"

    # Use temp directory for all AWM storage
    local physical_test_tmp
    physical_test_tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    export AWM_ROOT="${physical_test_tmp}/awm_test"
    mkdir -p "$AWM_ROOT"

    # Reset state
    _AWM_SESSION_ID=""
    _AWM_NAMESPACE=""
}

path_mode() {
    local path="$1"

    if stat -c '%a' "$path" >/dev/null 2>&1; then
        stat -c '%a' "$path"
    else
        stat -f '%Lp' "$path"
    fi
}

assert_private_awm_tree() {
    local root="$1"
    local path mode
    local problems=""

    while IFS= read -r path; do
        mode=$(path_mode "$path")
        if [[ "$mode" != "700" ]]; then
            problems+="directory mode ${mode}: ${path}"$'\n'
        fi
    done < <(find "$root" -type d -print)

    while IFS= read -r path; do
        mode=$(path_mode "$path")
        if [[ "$mode" != "600" ]]; then
            problems+="file mode ${mode}: ${path}"$'\n'
        fi
    done < <(find "$root" -type f -print)

    if [[ -n "$problems" ]]; then
        printf 'AWM tree contains non-private paths:\n%s' "$problems" >&2
        return 1
    fi
}

awm_tree_fingerprint() {
    local root="$1"
    local path relative mode checksum bytes

    while IFS= read -r path; do
        relative="${path#"$root"/}"
        mode=$(path_mode "$path")
        if [[ -L "$path" ]]; then
            printf 'link\t%s\t%s\t%s\n' "$relative" "$mode" "$(readlink "$path")"
        elif [[ -d "$path" ]]; then
            printf 'dir\t%s\t%s\n' "$relative" "$mode"
        elif [[ -f "$path" ]]; then
            read -r checksum bytes _ < <(cksum "$path")
            printf 'file\t%s\t%s\t%s:%s\n' \
                "$relative" "$mode" "$checksum" "$bytes"
        else
            printf 'special\t%s\t%s\n' "$relative" "$mode"
        fi
    done < <(find "$root" -mindepth 1 -print | LC_ALL=C sort)
}

arithmetic_payload_for_marker() {
    local marker="$1"
    printf 'BASH_VERSINFO[$(printf marker > "%s")0]' "$marker"
}

wait_for_worker_barrier() {
    local barrier_dir="$1"
    local expected="$2"
    local attempt ready worker

    for ((attempt = 0; attempt < 500; attempt++)); do
        ready=0
        for ((worker = 1; worker <= expected; worker++)); do
            [[ -f "${barrier_dir}/${worker}.ready" ]] && ready=$((ready + 1))
        done
        [[ "$ready" -eq "$expected" ]] && return 0
        sleep 0.02
    done

    printf 'worker barrier timed out: %s/%s ready\n' "$ready" "$expected" >&2
    return 1
}

# Cleanup after each test
teardown() {
    # Close any active session
    awm_close 2>/dev/null || true

    # Remove test data
    rm -rf "${BATS_TEST_TMPDIR}/awm_test" 2>/dev/null || true
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Initialize session and capture ID properly (avoiding subshell loss)
init_session() {
    local name="${1:-test}"
    local parent="${2:-}"

    # Call awm_init and let it set _AWM_SESSION_ID directly
    if [[ -n "$parent" ]]; then
        awm_init "$name" "$parent" > /dev/null
    else
        awm_init "$name" > /dev/null
    fi

    # Return the session ID
    printf '%s' "$_AWM_SESSION_ID"
}

# =============================================================================
# SESSION MANAGEMENT TESTS
# =============================================================================

@test "awm_init creates session with ID" {
    awm_init "test-session" > /dev/null

    [ -n "$_AWM_SESSION_ID" ]
    [ ${#_AWM_SESSION_ID} -eq 12 ]  # 12 character hex ID
}

@test "awm_init creates session directory structure" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"

    [ -d "${AWM_ROOT}/sessions/${sid}" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/logs" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/data" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/checkpoints" ]
    [ -f "${AWM_ROOT}/sessions/${sid}/manifest.json" ]
}

@test "awm_init creates valid manifest" {
    awm_init "my-test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    local manifest="${AWM_ROOT}/sessions/${sid}/manifest.json"
    [ -f "$manifest" ]

    # Check JSON structure
    local content
    content=$(<"$manifest")
    [[ "$content" == *'"session_id":"'${sid}'"'* ]]
    [[ "$content" == *'"name":"my-test"'* ]]
    [[ "$content" == *'"status":"active"'* ]]
    [[ "$content" == *'"schema_version":2'* ]]
}

@test "awm_init supports namespace model backend and canonical layout" {
    awm_init "memory-task" --namespace "team red" --model "gpt-4o" --backend file > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/team_red/${sid}"
    local manifest
    manifest=$(<"${dir}/manifest.json")

    [ -d "${dir}/handoffs" ]
    [ -d "${dir}/index" ]
    [ -d "${dir}/journal" ]
    [ -f "${dir}/discoveries.jsonl" ]
    [[ "$manifest" == *'"namespace":"team_red"'* ]]
    [[ "$manifest" == *'"model":"gpt-4o"'* ]]
    [[ "$manifest" == *'"backend":"file"'* ]]
}

@test "awm_init with parent inherits data" {
    # Create parent session with discovery
    awm_init "parent" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    awm_discovery "important finding"
    awm_close

    # Create child session with parent
    awm_init "child" "$parent_sid" > /dev/null
    local child_sid="$_AWM_SESSION_ID"

    # Check inheritance file exists
    [ -f "${AWM_ROOT}/sessions/${child_sid}/logs/inherited_discoveries.jsonl" ]
}

@test "awm_init refuses to inherit a project-memory session" {
    local project_dir="$BATS_TEST_TMPDIR/inherit-project"
    mkdir -p "$project_dir"
    awm_project_ensure "$project_dir" "private-project" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    _awm_project_mutate "$project_dir" checkpoint \
        "project-secret" "must-not-copy" > /dev/null
    _awm_project_mutate "$project_dir" close
    _AWM_SESSION_ID=""
    _AWM_SESSION_DIR=""
    _AWM_NAMESPACE=""

    local before after
    before=$(find "$AWM_ROOT/sessions" -type f -name manifest.json | wc -l | tr -d ' ')
    run awm_init "ordinary-child" --parent "$parent_sid"
    assert_failure
    after=$(find "$AWM_ROOT/sessions" -type f -name manifest.json | wc -l | tr -d ' ')

    [ "$after" -eq "$before" ]
}

@test "awm_handoff_accept cannot clone project memory into a generic session" {
    local project_dir="$BATS_TEST_TMPDIR/handoff-project"
    mkdir -p "$project_dir"
    awm_project_ensure "$project_dir" "private-project" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    _awm_project_mutate "$project_dir" checkpoint \
        "project-secret" "must-not-copy" > /dev/null
    _awm_project_mutate "$project_dir" close
    _AWM_SESSION_ID=""
    _AWM_SESSION_DIR=""
    _AWM_NAMESPACE=""

    local before after handoff
    before=$(find "$AWM_ROOT/sessions" -type f -name manifest.json | wc -l | tr -d ' ')
    handoff=$(printf '{"parent_session":"%s","target_agent":"ordinary","namespace":"ordinary"}' "$parent_sid")
    run awm_handoff_accept "$handoff"
    assert_failure
    after=$(find "$AWM_ROOT/sessions" -type f -name manifest.json | wc -l | tr -d ' ')

    [ "$after" -eq "$before" ]
}

@test "awm_resume restores existing session" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"
    awm_close

    [ -z "$_AWM_SESSION_ID" ]

    # Call directly (not via run) to preserve shell variable
    awm_resume "$sid"
    local status=$?

    [ "$status" -eq 0 ]
    [ "$_AWM_SESSION_ID" = "$sid" ]
}

@test "awm_resume fails for nonexistent session" {
    run awm_resume "nonexistent123"
    assert_failure
}

@test "awm_close marks session as completed" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"
    awm_close

    local manifest="${AWM_ROOT}/sessions/${sid}/manifest.json"
    local content
    content=$(<"$manifest")
    [[ "$content" == *'"status":"completed"'* ]]
}

@test "awm_close clears active session" {
    awm_init "test-session" > /dev/null
    [ -n "$_AWM_SESSION_ID" ]

    awm_close
    [ -z "$_AWM_SESSION_ID" ]
}

# =============================================================================
# NAMESPACE TESTS
# =============================================================================

@test "awm_namespace sets namespace" {
    awm_namespace "code-reviewer"
    [ "$_AWM_NAMESPACE" = "code-reviewer" ]
}

@test "awm_namespace affects session directory" {
    awm_namespace "agent1"
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    [ -d "${AWM_ROOT}/sessions/agent1/${sid}" ]
}

@test "awm_namespace clears with empty argument" {
    awm_namespace "something"
    awm_namespace ""
    [ -z "$_AWM_NAMESPACE" ]
}

# =============================================================================
# PATH CONFINEMENT TESTS
# =============================================================================

@test "awm_destroy rejects traversal and cannot delete outside AWM_ROOT" {
    local victim="${BATS_TEST_TMPDIR}/destroy-victim"
    mkdir -p "$victim"
    printf 'preserve me\n' > "${victim}/marker"

    run awm_destroy "../../destroy-victim"
    assert_failure
    [ -f "${victim}/marker" ]
}

@test "awm_destroy removes only the requested valid session" {
    awm_init "destroy-target" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local sibling="${AWM_ROOT}/sessions/${sid}-sibling"
    mkdir -p "$sibling"
    printf 'preserve me\n' > "${sibling}/marker"

    run awm_destroy "$sid"
    assert_success
    [ ! -e "${AWM_ROOT}/sessions/${sid}" ]
    [ -f "${sibling}/marker" ]
}

@test "awm_migrate rejects a traversal session id before touching an external layout" {
    local victim="${BATS_TEST_TMPDIR}/external-session"
    mkdir -p "$victim"
    printf '{"session_id":"external","status":"active"}' > "${victim}/manifest.json"

    run awm_migrate "../../external-session"
    assert_failure
    [ ! -e "${victim}/handoffs" ]
    [ ! -e "${victim}/journal" ]
    [[ "$(<"${victim}/manifest.json")" == '{"session_id":"external","status":"active"}' ]]
}

@test "snapshot checkpoint rejects a traversal component before writing outside the session" {
    awm_init "checkpoint-confinement" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local victim="${BATS_TEST_TMPDIR}/checkpoint-victim"
    mkdir -p "$victim"
    printf 'preserve me\n' > "${victim}/marker"

    run awm_checkpoint "$sid" "../../../../checkpoint-victim"
    assert_failure
    [ -f "${victim}/marker" ]
    [ ! -e "${victim}/data" ]
    [ ! -e "${victim}/snapshot.json" ]
}

@test "awm_get_checkpoint rejects a traversal component before reading outside the session" {
    awm_init "checkpoint-read-confinement" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local victim="${BATS_TEST_TMPDIR}/checkpoint-read-victim"
    mkdir -p "$victim"
    printf 'outside-session-secret\n' > "${victim}/snapshot.json"

    run awm_get_checkpoint "$sid" "../../../../checkpoint-read-victim"
    assert_failure
    [[ "$output" != *"outside-session-secret"* ]]
}

@test "awm_resume rejects a session directory symlink" {
    local victim="${BATS_TEST_TMPDIR}/symlink-session-victim"
    local sid="linked123abcd"
    mkdir -p "$victim" "${AWM_ROOT}/sessions"
    printf '{"schema_version":2,"session_id":"%s","status":"active","namespace":"","backend":"file"}' \
        "$sid" > "${victim}/manifest.json"
    ln -s "$victim" "${AWM_ROOT}/sessions/${sid}"

    run awm_resume "$sid"
    assert_failure
    [ -f "${victim}/manifest.json" ]
    [ ! -e "${victim}/handoffs" ]
}

@test "awm_checkpoint rejects a symlink target without changing its referent" {
    awm_init "symlink-write" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local victim="${BATS_TEST_TMPDIR}/symlink-write-victim"
    printf 'preserve me\n' > "$victim"
    ln -s "$victim" "${AWM_ROOT}/sessions/${sid}/data/linked_key"

    run awm_checkpoint linked_key replacement
    assert_failure
    [[ "$(<"$victim")" == "preserve me" ]]
}

@test "awm_init rejects a symbolic-link AWM_ROOT" {
    local victim="${BATS_TEST_TMPDIR}/symlink-root-victim"
    mkdir -p "$victim"
    export AWM_ROOT="${BATS_TEST_TMPDIR}/linked-awm-root"
    ln -s "$victim" "$AWM_ROOT"

    run awm_init "must-not-create"
    assert_failure
    [ ! -e "${victim}/sessions" ]
}

@test "awm_init rejects a relative AWM_ROOT before creating storage" {
    local workdir="${BATS_TEST_TMPDIR}/relative-root-workdir"
    mkdir -p "$workdir"

    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" AWM_ROOT="relative-awm" \
        "$BASH" -c '
            cd "$1"
            source "$2/lib/awm.sh"
            awm_init "relative-root-must-fail"
        ' _ "$workdir" "$MAINFRAME_ROOT"

    assert_failure
    [ ! -e "${workdir}/relative-awm" ]
}

@test "awm_init rejects an AWM_ROOT with a symbolic-link ancestor" {
    local physical_test_tmp
    physical_test_tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    local physical_parent="${physical_test_tmp}/physical-root-parent"
    local linked_parent="${physical_test_tmp}/linked-root-parent"
    mkdir -p "$physical_parent"
    ln -s "$physical_parent" "$linked_parent"

    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" AWM_ROOT="${linked_parent}/awm" \
        "$BASH" -c '
            source "$1/lib/awm.sh"
            awm_init "ancestor-link-must-fail"
        ' _ "$MAINFRAME_ROOT"

    assert_failure
    [ ! -e "${physical_parent}/awm" ]
}

@test "awm creates private directories and files under a permissive caller umask" {
    local previous_umask permissive_umask
    previous_umask=$(umask)
    umask 022
    permissive_umask=$(umask)

    awm_init "private-session" --namespace "private-team" > /dev/null
    awm_checkpoint "current_phase" "testing" --importance high
    awm_discovery "private discovery" --importance critical
    awm_log "decisions" "private decision" --importance high
    awm_progress "privacy" "1/2" "checking modes"
    awm_handoff_prepare "reviewer" --tokens 500 > /dev/null

    [ "$(umask)" = "$permissive_umask" ]
    umask "$previous_umask"
    assert_private_awm_tree "$AWM_ROOT"
}

# =============================================================================
# LOGGING TESTS
# =============================================================================

@test "awm_log writes to category file" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "task" "starting the work"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/task.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/task.jsonl")
    [[ "$content" == *'"msg":"starting the work"'* ]]
}

@test "awm_log appends multiple entries" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "progress" "step 1"
    awm_log "progress" "step 2"
    awm_log "progress" "step 3"

    local count
    count=$(wc -l < "${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl")
    [ "$count" -eq 3 ]
}

@test "awm_log escapes special characters" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "notes" 'has "quotes" and backslash'

    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/notes.jsonl")
    # Should contain escaped content - JSON uses "msg" field
    [[ "$content" == *'"msg":'* ]]
}

@test "awm_progress writes to progress category" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_progress "task1" "50/100"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl")
    [[ "$content" == *'"task":"task1"'* ]]
    [[ "$content" == *'"current":50'* ]]
    [[ "$content" == *'"total":100'* ]]
}

@test "awm_discovery writes to discoveries log" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_discovery "API has rate limit of 100/min"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/discoveries.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/discoveries.jsonl")
    [[ "$content" == *'"discovery":"API has rate limit of 100/min"'* ]]
}

# =============================================================================
# CHECKPOINT TESTS
# =============================================================================

@test "awm_checkpoint creates checkpoint file" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_checkpoint "before-refactor" "state1"

    # Checkpoints are stored in data/ directory
    [ -f "${AWM_ROOT}/sessions/${sid}/data/before-refactor" ]
}

@test "awm_checkpoint writes value correctly" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_checkpoint "mykey" 'task:migrate,progress:47'

    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/data/mykey")
    [[ "$content" == *"migrate"* ]]
}

@test "awm_checkpoint records metadata for importance tags and ttl" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_checkpoint "api_response" '{"ok":true}' --importance critical --tags auth,api --ttl 60

    local meta
    meta=$(<"${AWM_ROOT}/sessions/${sid}/logs/checkpoints.jsonl")
    [[ "$meta" == *'"kind":"checkpoint"'* ]]
    [[ "$meta" == *'"importance":"critical"'* ]]
    [[ "$meta" == *'"ttl":60'* ]]
    [[ "$meta" == *'"key":"api_response"'* ]]
}

@test "AWM_MAX_FILE_SIZE counts UTF-8 bytes and rejects before checkpoint artifacts" {
    awm_init "payload-byte-limit" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"
    export AWM_MAX_FILE_SIZE=4

    run awm_checkpoint "u" "ππ"
    assert_success
    [ "$(LC_ALL=C wc -c < "${dir}/data/u" | tr -d '[:space:]')" -eq 4 ]

    local before
    before=$(awm_tree_fingerprint "$dir")

    run awm_checkpoint "v" "ππx"
    assert_failure
    [[ "$output" == *"checkpoint value exceeds AWM_MAX_FILE_SIZE (5 > 4 bytes)"* ]]
    [ ! -e "${dir}/data/v" ]
    [ ! -e "${dir}/index/v.json" ]
    ! grep -q '"key":"v"' "${dir}/logs/checkpoints.jsonl"
    ! grep -q '"key":"v"' "${dir}/journal/events.jsonl"
    [ "$(awm_tree_fingerprint "$dir")" = "$before" ]
}

@test "AWM_MAX_FILE_SIZE rejects durable mutation payloads without partial writes" {
    awm_init "payload-write-limit" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"
    export AWM_MAX_FILE_SIZE=4

    run awm_log "log" "12345"
    assert_failure
    [ ! -e "${dir}/logs/log.jsonl" ]

    run awm_discovery "12345"
    assert_failure
    [ ! -s "${dir}/discoveries.jsonl" ]
    [ ! -s "${dir}/logs/discoveries.jsonl" ]

    run awm_append "$sid" "app" "12345"
    assert_failure
    [ ! -e "${dir}/data/app" ]

    [ "$(tr -d '[:space:]' < "${dir}/index/categories.json")" = "[]" ]
    ! grep -q '12345' "${dir}/journal/events.jsonl"
}

@test "AWM_MAX_FILE_SIZE rejects arithmetic input without execution or session artifacts" {
    local marker="${BATS_TEST_TMPDIR}/awm-file-size-arithmetic-marker"
    local payload invalid before
    payload=$(arithmetic_payload_for_marker "$marker")
    local -a invalid_limits=(
        ""
        "0"
        "-1"
        "+4"
        "1.5"
        "4x"
        " 4"
        "1073741825"
        "$payload"
    )

    before=$(awm_tree_fingerprint "$AWM_ROOT")
    for invalid in "${invalid_limits[@]}"; do
        export AWM_MAX_FILE_SIZE="$invalid"

        run awm_init "payload-config-safety"

        assert_failure
        [[ "$output" == *"AWM_MAX_FILE_SIZE"* ]]
        [ "$(awm_tree_fingerprint "$AWM_ROOT")" = "$before" ]
    done
    [ ! -e "$marker" ]
    [ ! -d "${AWM_ROOT}/sessions" ]
}

@test "AWM_MAX_FILE_SIZE also preflights snapshots and first project initialization" {
    awm_init "payload-preflight" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local session_dir="${AWM_ROOT}/sessions/${sid}"
    local before
    before=$(awm_tree_fingerprint "$session_dir")
    export AWM_MAX_FILE_SIZE=1

    run awm_checkpoint "$sid" "snapshot"
    assert_failure
    [[ "$output" == *"snapshot name exceeds AWM_MAX_FILE_SIZE"* ]]
    [ "$(awm_tree_fingerprint "$session_dir")" = "$before" ]

    awm_close > /dev/null
    rm -rf -- "$AWM_ROOT"
    mkdir -p "$AWM_ROOT"
    local project="${BATS_TEST_TMPDIR}/payload-preflight-project"
    mkdir -p "$project"
    before=$(awm_tree_fingerprint "$AWM_ROOT")

    run awm_project_ensure "$project" "project-name"
    assert_failure
    [[ "$output" == *"session name exceeds AWM_MAX_FILE_SIZE"* ]]
    [ "$(awm_tree_fingerprint "$AWM_ROOT")" = "$before" ]
}

@test "AWM payload parsing preserves tabs and keeps wildcard tags literal" {
    awm_init "payload-structure" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"
    local tabbed=$'ok\t12345678901'
    export AWM_MAX_FILE_SIZE=10

    run awm_checkpoint "tab_ckpt" "$tabbed"
    assert_failure
    [[ "$output" == *"checkpoint value exceeds AWM_MAX_FILE_SIZE (14 > 10 bytes)"* ]]
    [ ! -e "${dir}/data/tab_ckpt" ]

    run awm_log "tab_log" "$tabbed"
    assert_failure
    [[ "$output" == *"log message exceeds AWM_MAX_FILE_SIZE (14 > 10 bytes)"* ]]
    [ ! -e "${dir}/logs/tab_log.jsonl" ]

    export AWM_MAX_FILE_SIZE=65536
    awm_checkpoint "literal_tag" "value" --tags '*'
    local metadata
    metadata=$(<"${dir}/logs/checkpoints.jsonl")
    [[ "$metadata" == *'"tags":["*"]'* ]]
}

@test "AWM byte counting ignores an ambient wc function without evaluating its output" {
    awm_init "payload-byte-counter" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local marker="${BATS_TEST_TMPDIR}/awm-wc-arithmetic-marker"
    export AWM_MAX_FILE_SIZE=1

    wc() {
        arithmetic_payload_for_marker "$marker"
    }

    run awm_checkpoint "k" "abc"

    assert_failure
    [[ "$output" == *"checkpoint value exceeds AWM_MAX_FILE_SIZE (3 > 1 bytes)"* ]]
    [ ! -e "$marker" ]
    [ ! -e "${AWM_ROOT}/sessions/${sid}/data/k" ]
}

@test "AWM rejects noncanonical importance before durable writes" {
    awm_init "importance-validation" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"

    run awm_checkpoint "invalid_importance" "value" --importance medium
    assert_failure
    [[ "$output" == *"importance must be low, normal, high, or critical"* ]]
    [ ! -e "${dir}/data/invalid_importance" ]

    run awm_log "invalid_importance" "value" --importance $'high\textra'
    assert_failure
    [ ! -e "${dir}/logs/invalid_importance.jsonl" ]

    run awm_discovery "value" --importance urgent
    assert_failure
    [ ! -s "${dir}/discoveries.jsonl" ]
}

@test "AWM preflights every path-derived write component" {
    awm_init "storage-component-validation" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"
    local long_component long_task before
    printf -v long_component '%*s' 129 ''
    long_component=${long_component// /x}
    printf -v long_task '%*s' 120 ''
    long_task=${long_task// /t}
    before=$(awm_tree_fingerprint "$dir")

    run awm_checkpoint "$long_component" "value"
    assert_failure
    run awm_log "$long_component" "value"
    assert_failure
    run awm_append "$sid" "$long_component" "value"
    assert_failure
    run awm_progress "$long_task" "1/2" "working"
    assert_failure
    run awm_handoff_prepare "$long_component" --tokens 256
    assert_failure

    [ "$(awm_tree_fingerprint "$dir")" = "$before" ]
}

@test "AWM rejects oversized source attribution before durable writes" {
    awm_init "source-agent-validation" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"
    local before
    printf -v MAINFRAME_AGENT_NAME '%*s' 129 ''
    MAINFRAME_AGENT_NAME=${MAINFRAME_AGENT_NAME// /a}
    export MAINFRAME_AGENT_NAME
    before=$(awm_tree_fingerprint "$dir")

    run awm_checkpoint "key" "value"
    assert_failure
    run awm_log "events" "value"
    assert_failure
    run awm_discovery "value"
    assert_failure
    run awm_progress "task" "1/2" "value"
    assert_failure
    run awm_handoff_prepare "reviewer" --tokens 256
    assert_failure

    [ "$(awm_tree_fingerprint "$dir")" = "$before" ]
}

@test "AWM payload limits ignore a shadowed printf function" {
    awm_init "payload-printf-counter" > /dev/null
    local sid="$_AWM_SESSION_ID"
    export AWM_MAX_FILE_SIZE=1

    shadowed_printf_checkpoint() {
        printf() {
            if [[ "${FUNCNAME[1]:-}" == "_awm_string_bytes" ]]; then
                builtin printf '0'
            else
                builtin printf "$@"
            fi
        }
        awm_checkpoint "k" "abc"
    }

    run shadowed_printf_checkpoint

    assert_failure
    [ ! -e "${AWM_ROOT}/sessions/${sid}/data/k" ]
}

@test "AWM keeps lock artifacts out of user checkpoint memory" {
    awm_init "lock-isolation" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local dir="${AWM_ROOT}/sessions/${sid}"

    awm_checkpoint "state" "value"
    [ ! -e "${dir}/data/state.lock" ]
    printf '' > "${dir}/data/legacy.lock"
    chmod 600 "${dir}/data/legacy.lock"

    run awm_summary
    assert_success
    [[ "$output" == *'"state":"value"'* ]]
    [[ "$output" != *'legacy.lock'* ]]

    run awm_find "legacy" --kind checkpoint --limit 5
    assert_success
    [[ "$output" == "[]" ]]

    run awm_status
    assert_success
    [[ "$output" == *'"checkpoints":1'* ]]

    run awm_checkpoint "reserved.lock" "must-not-write"
    assert_failure
    run awm_get "legacy.lock"
    assert_failure
}

@test "awm_get retrieves checkpointed data" {
    awm_init "test" > /dev/null

    awm_checkpoint "setting" "enabled"

    run awm_get "setting"
    assert_success
    [[ "$output" == *"enabled"* ]]
}

@test "awm_get returns empty for missing key" {
    awm_init "test" > /dev/null

    run awm_get "nonexistent"
    # Should succeed but output empty or fail gracefully
    [ -z "$output" ] || [ "$status" -ne 0 ]
}

# =============================================================================
# DATA RETRIEVAL TESTS
# =============================================================================

@test "awm_recent returns last N entries" {
    awm_init "test" > /dev/null

    awm_log "events" "event1"
    awm_log "events" "event2"
    awm_log "events" "event3"
    awm_log "events" "event4"
    awm_log "events" "event5"

    run awm_recent "events" 3
    assert_success

    # Should include most recent entries
    [[ "$output" == *"event"* ]]
}

@test "awm_summary returns session overview" {
    awm_init "test-summary" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "tasks" "task1"
    awm_discovery "found something"
    awm_checkpoint "state" "value"

    run awm_summary
    assert_success

    # Should contain session info
    [ -n "$output" ]
}

@test "awm_find searches discoveries checkpoints and logs" {
    awm_init "searchable" > /dev/null

    awm_discovery "Database uses PostgreSQL 15"
    awm_checkpoint "database_engine" "postgres"
    awm_log "decisions" "picked postgres for transactions"

    run awm_find "postgres" --kind mixed --limit 5
    assert_success
    [[ "$output" == *'"kind":"discovery"'* ]]
    [[ "$output" == *'"kind":"checkpoint"'* ]]
    [[ "$output" == *'"kind":"log"'* ]]
}

@test "awm_list shows available sessions" {
    # Create multiple sessions
    awm_init "session1" > /dev/null
    local sid1="$_AWM_SESSION_ID"
    awm_close

    awm_init "session2" > /dev/null
    local sid2="$_AWM_SESSION_ID"
    awm_close

    run awm_list
    assert_success

    # Should list sessions
    [ -n "$output" ]
}

# =============================================================================
# TOKEN ESTIMATION TESTS
# =============================================================================

@test "awm_token_estimate returns number for session" {
    awm_init "test" > /dev/null

    # Add some data
    awm_checkpoint "key1" "value1"
    awm_log "info" "some log message"

    run awm_token_estimate
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]  # Should be a number
}

@test "awm_token_estimate scales with content" {
    awm_init "test" > /dev/null

    local est1
    awm_checkpoint "small" "x"
    est1=$(awm_token_estimate)

    # Add more data
    awm_checkpoint "large" "$(printf 'x%.0s' {1..1000})"
    local est2
    est2=$(awm_token_estimate)

    [ "$est2" -gt "$est1" ]
}

@test "awm_estimate_read estimates session read cost" {
    awm_init "test" > /dev/null

    awm_log "data" "some content here"
    awm_discovery "a discovery"
    awm_checkpoint "key" "value"

    run awm_estimate_read "summary"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]  # Should be a number
}

# =============================================================================
# COMPRESSION TESTS
# =============================================================================

@test "awm_compress handles empty session" {
    awm_init "test" > /dev/null

    run awm_compress
    # Should succeed even with nothing to compress
    assert_success
}

@test "awm_check_limits returns status" {
    awm_init "test" > /dev/null

    run awm_check_limits
    assert_success
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

@test "awm_cleanup removes old sessions" {
    # Create a session and close it
    awm_init "old-session" > /dev/null
    awm_close

    # Run cleanup (may or may not delete depending on age)
    run awm_cleanup 0
    assert_success
}

# =============================================================================
# NUMERIC INPUT SAFETY TESTS
# =============================================================================

@test "awm_cleanup rejects arithmetic expressions without executing them" {
    local marker="${BATS_TEST_TMPDIR}/cleanup-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")

    run awm_cleanup "$payload"

    assert_failure
    [ ! -e "$marker" ]
}

@test "awm_estimate_read rejects arithmetic expressions without executing them" {
    local marker="${BATS_TEST_TMPDIR}/estimate-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")
    awm_init "estimate-input-safety" > /dev/null
    awm_log "data" "content used to reach the read estimate arithmetic"

    run awm_estimate_read recent data "$payload"

    assert_failure
    [ ! -e "$marker" ]
}

@test "awm_context_for rejects arithmetic expressions without executing them" {
    local marker="${BATS_TEST_TMPDIR}/context-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")
    awm_init "context-input-safety" > /dev/null

    run awm_context_for "input safety" --tokens "$payload"

    assert_failure
    [ ! -e "$marker" ]
}

@test "awm_handoff_prepare rejects arithmetic expressions without executing them" {
    local marker="${BATS_TEST_TMPDIR}/handoff-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")
    awm_init "handoff-input-safety" > /dev/null

    run awm_handoff_prepare "reviewer" --tokens "$payload"

    assert_failure
    [ ! -e "$marker" ]
}

@test "awm_migrate upgrades legacy session layout and schema" {
    local sid="legacy123abcd"
    local dir="${AWM_ROOT}/sessions/${sid}"
    mkdir -p "${dir}/logs" "${dir}/data"
    printf '{"session_id":"%s","name":"legacy","created_at":"2026-03-11T00:00:00-0400","created_epoch":1773201600,"status":"active","namespace":"","parent_session":""}' "$sid" > "${dir}/manifest.json"
    printf '{"ts":1,"discovery":"old discovery"}\n' > "${dir}/logs/discoveries.jsonl"
    chmod 0755 "$AWM_ROOT" "${AWM_ROOT}/sessions" "$dir" "${dir}/logs" "${dir}/data"
    chmod 0644 "${dir}/manifest.json" "${dir}/logs/discoveries.jsonl"

    run awm_migrate "$sid"
    assert_success
    [[ "$output" == "$sid" ]]
    [ -d "${dir}/handoffs" ]
    [ -d "${dir}/index" ]
    [ -d "${dir}/journal" ]
    [ -f "${dir}/discoveries.jsonl" ]
    [[ $(<"${dir}/manifest.json") == *'"schema_version":2'* ]]
    assert_private_awm_tree "$AWM_ROOT"
}

@test "awm_resume does not append migration events for a current session" {
    awm_init "current-schema" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local journal="${AWM_ROOT}/sessions/${sid}/journal/events.jsonl"
    awm_close
    local before
    before=$(wc -l < "$journal" | tr -d ' ')

    awm_resume "$sid"
    local after
    after=$(wc -l < "$journal" | tr -d ' ')

    [ "$after" -eq "$before" ]
}

@test "AWM journal is strict JSONL after every durable transition" {
    awm_init "strict-journal" > /dev/null
    local sid="$_AWM_SESSION_ID"
    local journal="${AWM_ROOT}/sessions/${sid}/journal/events.jsonl"
    local line count=0

    awm_checkpoint "source_fact" "one exact fact"
    awm_discovery "one exact discovery"
    awm_handoff_prepare "reviewer" --tokens 256 > /dev/null

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        run /usr/bin/python3 -I -S -B -c \
            'import json,sys; value=json.loads(sys.argv[1]); assert isinstance(value,dict); assert isinstance(value.get("kind"),str); assert isinstance(value.get("payload"),dict)' \
            "$line"
        assert_success
        count=$((count + 1))
    done < "$journal"

    [ "$count" -ge 4 ]
}

# =============================================================================
# CONTEXT INHERITANCE TESTS
# =============================================================================

@test "awm_context_for generates context package" {
    awm_init "parent-task" > /dev/null

    awm_discovery "API uses Bearer tokens"
    awm_discovery "Rate limit is 100/min"
    awm_checkpoint "current_file" "src/auth.ts"

    run awm_context_for "child-task"
    assert_success
    [ -n "$output" ]
}

@test "awm_context_for supports prompt format and related matches" {
    awm_init "handoff-parent" > /dev/null
    awm_discovery "JWT refresh tokens are enabled" --importance critical
    awm_checkpoint "open_questions" '["Should we rotate secrets?"]'
    awm_log "decisions" "Need auth hardening for JWT rotation"

    run awm_context_for "JWT hardening" --tokens 1200 --format prompt --include discoveries,progress,checkpoints,logs
    assert_success
    [[ "$output" == *"Task: JWT hardening"* ]]
    [[ "$output" == *"Discoveries:"* ]]
    [[ "$output" == *"Related Matches:"* ]]
}

@test "awm_inherit loads parent context" {
    # Create parent with data
    awm_init "parent" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    awm_discovery "important info"
    awm_close

    # Create child that inherits
    awm_init "child" "$parent_sid" > /dev/null
    local child_sid="$_AWM_SESSION_ID"

    # Child should have inherited discoveries
    [ -f "${AWM_ROOT}/sessions/${child_sid}/logs/inherited_discoveries.jsonl" ]
}

@test "awm_export writes to export directory" {
    awm_init "test" > /dev/null

    run awm_export "result.txt"
    assert_success
}

@test "awm_handoff_prepare and accept preserve provenance" {
    awm_init "parent" --namespace "blue-team" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    awm_discovery "Found critical issue in auth middleware" --importance critical
    awm_checkpoint "open_questions" '["How should rotation work?"]'

    run awm_handoff_prepare "review-agent" --tokens 1500
    assert_success
    [[ "$output" == *'"type":"handoff"'* ]]
    [[ "$output" == *'"parent_session":"'"${parent_sid}"'"'* ]]
    [[ "$output" == *'"target_agent":"review-agent"'* ]]

    _AWM_SESSION_ID=""
    _AWM_SESSION_DIR=""
    _AWM_NAMESPACE=""
    local forged_handoff="${output/\"namespace\":\"blue-team\"/\"namespace\":\"attacker\"}"
    run awm_handoff_accept "$forged_handoff"
    assert_success
    local child_sid="$output"
    [ -f "${AWM_ROOT}/sessions/blue-team/${child_sid}/manifest.json" ]
    [ ! -e "${AWM_ROOT}/sessions/attacker/${child_sid}" ]
    [ "$(<"${AWM_ROOT}/sessions/blue-team/${child_sid}/data/open_questions")" = '["How should rotation work?"]' ]
}

@test "awm_status and awm_doctor report canonical health" {
    awm_init "status-check" > /dev/null
    awm_log "decisions" "picked postgres"
    awm_discovery "Critical finding" --importance critical

    run awm_status
    assert_success
    [[ "$output" == *'"schema_version":2'* ]]
    [[ "$output" == *'"discoveries":1'* ]]

    run awm_doctor
    assert_success
    [[ "$output" == *'"layout_ok":true'* ]]
    [[ "$output" == *'"private_modes":true'* ]]
    [[ "$output" == *'"symlink_free":true'* ]]
    [[ "$output" == *'"expected_schema":2'* ]]
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "awm_log without active session fails gracefully" {
    _AWM_SESSION_ID=""

    run awm_log "test" "message"
    assert_failure
}

@test "awm_checkpoint without active session fails" {
    _AWM_SESSION_ID=""

    run awm_checkpoint "key" "value"
    assert_failure
}

@test "awm_discovery without active session fails" {
    _AWM_SESSION_ID=""

    run awm_discovery "content"
    assert_failure
}

@test "multiple simultaneous sessions are isolated" {
    awm_namespace "agent1"
    awm_init "task1" > /dev/null
    local sid1="$_AWM_SESSION_ID"
    awm_discovery "agent1 finding"
    awm_close

    awm_namespace "agent2"
    awm_init "task2" > /dev/null
    local sid2="$_AWM_SESSION_ID"
    awm_discovery "agent2 finding"
    awm_close

    # Sessions should be in different directories
    [ -d "${AWM_ROOT}/sessions/agent1/${sid1}" ]
    [ -d "${AWM_ROOT}/sessions/agent2/${sid2}" ]

    # Discoveries should be separate
    local agent1_disc="${AWM_ROOT}/sessions/agent1/${sid1}/logs/discoveries.jsonl"
    local agent2_disc="${AWM_ROOT}/sessions/agent2/${sid2}/logs/discoveries.jsonl"

    [[ $(<"$agent1_disc") == *"agent1 finding"* ]]
    [[ $(<"$agent2_disc") == *"agent2 finding"* ]]
}

@test "awm handles special characters in session names" {
    awm_init "test with spaces" > /dev/null

    [ -n "$_AWM_SESSION_ID" ]
    [ -d "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}" ]
}

@test "awm handles very long content" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    # Generate long content
    local long_content
    long_content=$(printf 'x%.0s' {1..1000})

    run awm_log "data" "$long_content"
    assert_success

    # Verify it was written
    [ -f "${AWM_ROOT}/sessions/${sid}/logs/data.jsonl" ]
}

# =============================================================================
# CONCURRENT ACCESS TESTS (Basic)
# =============================================================================

@test "awm_log handles rapid successive writes" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    # Write many entries quickly
    for i in {1..20}; do
        awm_log "rapid" "entry $i"
    done

    local count
    count=$(wc -l < "${AWM_ROOT}/sessions/${sid}/logs/rapid.jsonl")
    [ "$count" -eq 20 ]
}

@test "awm_log handles mkdir lock fallback" {
    export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
    awm_init "fallback-locks" > /dev/null
    local sid="$_AWM_SESSION_ID"

    for i in {1..10}; do
        awm_log "fallback" "entry $i"
    done

    local count
    count=$(wc -l < "${AWM_ROOT}/sessions/${sid}/logs/fallback.jsonl")
    [ "$count" -eq 10 ]
    unset _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS
}

@test "parallel category writers retain every category in both indexes" {
    local worker_count=32
    local barrier_dir="${BATS_TEST_TMPDIR}/category-index-barrier"
    local session_dir category_index logs_index category_json logs_json
    local barrier_failed=0 failures=0 missing=""
    local i pid stderr_file
    local pids=()

    export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
    export AWM_LOCK_TIMEOUT=30
    awm_init "parallel-category-index" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    mkdir -p "${barrier_dir}/output"

    for ((i = 1; i <= worker_count; i++)); do
        "$BASH" -c '
            export MAINFRAME_ROOT="$1"
            export AWM_ROOT="$2"
            export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
            export AWM_LOCK_TIMEOUT=30
            source "$MAINFRAME_ROOT/lib/awm.sh"
            _AWM_SESSION_ID="$3"
            _AWM_SESSION_DIR="$4"
            : > "$5/$6.ready"
            for ((attempt = 0; attempt < 1000; attempt++)); do
                [[ -f "$5/go" ]] && break
                sleep 0.01
            done
            [[ -f "$5/go" ]] || exit 98
            awm_log "category_$6" "message_$6"
        ' _ "$MAINFRAME_ROOT" "$AWM_ROOT" "$sid" "$session_dir" "$barrier_dir" "$i" \
            > "${barrier_dir}/output/${i}.stdout" \
            2> "${barrier_dir}/output/${i}.stderr" &
        pids+=("$!")
    done

    wait_for_worker_barrier "$barrier_dir" "$worker_count" || barrier_failed=1
    : > "${barrier_dir}/go"
    for ((i = 0; i < ${#pids[@]}; i++)); do
        pid="${pids[$i]}"
        if wait "$pid"; then
            :
        else
            printf 'category worker %s exited %s\n' "$((i + 1))" "$?" >&2
            failures=$((failures + 1))
        fi
    done

    if [[ "$failures" -ne 0 ]]; then
        for stderr_file in "${barrier_dir}/output/"*.stderr; do
            [[ -s "$stderr_file" ]] || continue
            printf '%s:\n' "$stderr_file" >&2
            sed -n '1,40p' "$stderr_file" >&2
        done
    fi
    [ "$barrier_failed" -eq 0 ]
    [ "$failures" -eq 0 ]

    category_index="${session_dir}/index/categories.json"
    logs_index="${session_dir}/logs/index.json"
    category_json=$(tr -d '[:space:]' < "$category_index")
    logs_json=$(tr -d '[:space:]' < "$logs_index")
    for ((i = 1; i <= worker_count; i++)); do
        if [[ "$category_json" != *"\"category_${i}\""* ]]; then
            missing+=" index/categories.json:category_${i}"
        fi
        if [[ "$logs_json" != *"\"category_${i}\""* ]]; then
            missing+=" logs/index.json:category_${i}"
        fi
    done
    [[ -z "$missing" ]] || printf 'missing indexed categories:%s\n' "$missing" >&2
    [ -z "$missing" ]
}

@test "parallel log compression retains every acknowledged entry exactly once" {
    local worker_count=40
    local barrier_dir="${BATS_TEST_TMPDIR}/compression-barrier"
    local session_dir active_log archive_log combined_log
    local barrier_failed=0 failures=0 total_lines unique_messages
    local i pid stderr_file
    local pids=()

    export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
    export AWM_LOCK_TIMEOUT=30
    export AWM_MAX_LOG_ENTRIES=4
    export AWM_LOG_KEEP_RECENT=2
    awm_init "parallel-compression" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    mkdir -p "${barrier_dir}/output"

    for ((i = 1; i <= worker_count; i++)); do
        "$BASH" -c '
            export MAINFRAME_ROOT="$1"
            export AWM_ROOT="$2"
            export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
            export AWM_LOCK_TIMEOUT=30
            export AWM_MAX_LOG_ENTRIES=4
            export AWM_LOG_KEEP_RECENT=2
            source "$MAINFRAME_ROOT/lib/awm.sh"
            _AWM_SESSION_ID="$3"
            _AWM_SESSION_DIR="$4"
            : > "$5/$6.ready"
            for ((attempt = 0; attempt < 1000; attempt++)); do
                [[ -f "$5/go" ]] && break
                sleep 0.01
            done
            [[ -f "$5/go" ]] || exit 98
            awm_log "compression_race" "message_$6"
        ' _ "$MAINFRAME_ROOT" "$AWM_ROOT" "$sid" "$session_dir" "$barrier_dir" "$i" \
            > "${barrier_dir}/output/${i}.stdout" \
            2> "${barrier_dir}/output/${i}.stderr" &
        pids+=("$!")
    done

    wait_for_worker_barrier "$barrier_dir" "$worker_count" || barrier_failed=1
    : > "${barrier_dir}/go"
    for ((i = 0; i < ${#pids[@]}; i++)); do
        pid="${pids[$i]}"
        if wait "$pid"; then
            :
        else
            printf 'compression worker %s exited %s\n' "$((i + 1))" "$?" >&2
            failures=$((failures + 1))
        fi
    done

    if [[ "$failures" -ne 0 ]]; then
        for stderr_file in "${barrier_dir}/output/"*.stderr; do
            [[ -s "$stderr_file" ]] || continue
            printf '%s:\n' "$stderr_file" >&2
            sed -n '1,40p' "$stderr_file" >&2
        done
    fi
    [ "$barrier_failed" -eq 0 ]
    [ "$failures" -eq 0 ]

    active_log="${session_dir}/logs/compression_race.jsonl"
    archive_log="${session_dir}/logs/compression_race.archive.jsonl"
    combined_log="${BATS_TEST_TMPDIR}/compression-combined.jsonl"
    : > "$combined_log"
    [[ ! -f "$active_log" ]] || sed -n '/./p' "$active_log" >> "$combined_log"
    [[ ! -f "$archive_log" ]] || sed -n '/./p' "$archive_log" >> "$combined_log"
    total_lines=$(wc -l < "$combined_log" | tr -d ' ')
    unique_messages=$(sed -n 's/.*"msg":"\(message_[0-9][0-9]*\)".*/\1/p' "$combined_log" | sort -u | wc -l | tr -d ' ')

    [ "$total_lines" -eq "$worker_count" ]
    [ "$unique_messages" -eq "$worker_count" ]
}

@test "mkdir lock fallback fails closed after a crashed owner" {
    local ready_file="${BATS_TEST_TMPDIR}/stale-owner-ready"
    local session_dir lock_name

    export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
    export AWM_LOCK_TIMEOUT=1
    awm_init "stale-lock-owner" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    lock_name="${session_dir}/logs/stale_owner.jsonl.lock"

    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" AWM_ROOT="$AWM_ROOT" \
        _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1 AWM_LOCK_TIMEOUT=2 \
        "$BASH" -c '
            source "$1/lib/awm.sh"
            crash_after_lock() {
                : > "$1"
                kill -9 "$$" "${BASHPID:-$$}"
            }
            _awm_with_lock "$2" crash_after_lock "$3"
        ' _ "$MAINFRAME_ROOT" "$lock_name" "$ready_file"

    assert_failure
    [ -f "$ready_file" ]
    [ -d "${lock_name}.dir" ]

    run awm_log "stale_owner" "write after crashed lock owner"
    assert_failure
    [[ "$output" == *"refusing unsafe stale-lock recovery"* ]]
    [ -d "${lock_name}.dir" ]
    [ ! -f "${session_dir}/logs/stale_owner.jsonl" ]
}

@test "mkdir lock fallback fails closed on an orphaned reclaim marker" {
    local session_dir lock_name lock_dir

    export _MAINFRAME_AWM_TEST_FORCE_MKDIR_LOCKS=1
    export AWM_LOCK_TIMEOUT=1
    awm_init "stale-reclaimer" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    lock_name="${session_dir}/logs/stale_reclaimer.jsonl.lock"
    lock_dir="${lock_name}.dir"

    (umask 077; mkdir -- "$lock_dir")
    printf 'pid=999999999\nepoch=1\n' > "${lock_dir}/owner"
    : > "${lock_dir}/.reclaim"
    chmod 700 "$lock_dir"
    chmod 600 "${lock_dir}/owner" "${lock_dir}/.reclaim"
    touch -t 200001010000 "${lock_dir}/.reclaim"

    run awm_log "stale_reclaimer" "must not be written"
    assert_failure
    [[ "$output" == *"refusing unsafe stale-lock recovery"* ]]
    [ -d "$lock_dir" ]
    [ -f "${lock_dir}/.reclaim" ]
    [ ! -f "${session_dir}/logs/stale_reclaimer.jsonl" ]
}

@test "lockf lock is kernel-released when its holder is killed" {
    local ready_file="${BATS_TEST_TMPDIR}/lockf-killed-ready"
    local acquired_file="${BATS_TEST_TMPDIR}/lockf-reacquired"
    local session_dir lock_name

    [[ "$(_awm_lock_strategy)" == "lockf" ]] || skip "BSD lockf is not the selected kernel lock"
    export AWM_LOCK_TIMEOUT=2
    awm_init "lockf-killed-owner" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    lock_name="${session_dir}/logs/lockf_killed.jsonl.lock"

    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" AWM_ROOT="$AWM_ROOT" \
        AWM_LOCK_TIMEOUT=2 "$BASH" -c '
            source "$1/lib/awm.sh"
            crash_with_kernel_lock() {
                : > "$1"
                kill -9 "${BASHPID:-$$}"
            }
            _awm_with_lock "$2" crash_with_kernel_lock "$3"
        ' _ "$MAINFRAME_ROOT" "$lock_name" "$ready_file"

    assert_failure
    [ -f "$ready_file" ]
    [ ! -d "${lock_name}.dir" ]

    reacquire_after_kill() {
        : > "$1"
    }
    run _awm_with_lock "$lock_name" reacquire_after_kill "$acquired_file"
    assert_success
    [ -f "$acquired_file" ]
    [ ! -d "${lock_name}.dir" ]
    [ "$(stat -f '%Lp' "$lock_name" 2>/dev/null || stat -c '%a' "$lock_name")" = "600" ]
}

@test "lockf contention times out without invoking the waiting callback" {
    local ready_file="${BATS_TEST_TMPDIR}/lockf-contention-ready"
    local forbidden_file="${BATS_TEST_TMPDIR}/lockf-contention-forbidden"
    local session_dir lock_name holder_pid attempt

    [[ "$(_awm_lock_strategy)" == "lockf" ]] || skip "BSD lockf is not the selected kernel lock"
    awm_init "lockf-contention" > /dev/null
    local sid="$_AWM_SESSION_ID"
    session_dir=$(_awm_find_session_dir "$sid")
    lock_name="${session_dir}/logs/lockf_contention.jsonl.lock"

    env MAINFRAME_ROOT="$MAINFRAME_ROOT" AWM_ROOT="$AWM_ROOT" \
        AWM_LOCK_TIMEOUT=5 "$BASH" -c '
            source "$1/lib/awm.sh"
            hold_kernel_lock() {
                : > "$1"
                sleep 2
            }
            _awm_with_lock "$2" hold_kernel_lock "$3"
        ' _ "$MAINFRAME_ROOT" "$lock_name" "$ready_file" &
    holder_pid=$!
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -f "$ready_file" ]] && break
        sleep 0.01
    done
    [ -f "$ready_file" ]

    must_not_run() {
        : > "$1"
    }
    export AWM_LOCK_TIMEOUT=1
    run _awm_with_lock "$lock_name" must_not_run "$forbidden_file"
    [ "$status" -eq 97 ]
    [ ! -f "$forbidden_file" ]
    wait "$holder_pid"
}

# =============================================================================
# FUNCTION EXISTENCE TESTS
# =============================================================================

@test "all AWM functions are declared" {
    source "${MAINFRAME_ROOT}/lib/awm.sh"

    # Check key functions exist
    declare -F awm_init >/dev/null
    declare -F awm_close >/dev/null
    declare -F awm_resume >/dev/null
    declare -F awm_log >/dev/null
    declare -F awm_discovery >/dev/null
    declare -F awm_checkpoint >/dev/null
    declare -F awm_get >/dev/null
    declare -F awm_recent >/dev/null
    declare -F awm_summary >/dev/null
    declare -F awm_token_estimate >/dev/null
    declare -F awm_find >/dev/null
    declare -F awm_handoff_prepare >/dev/null
    declare -F awm_handoff_accept >/dev/null
    declare -F awm_status >/dev/null
    declare -F awm_doctor >/dev/null
    declare -F awm_migrate >/dev/null
}

#!/usr/bin/env bats
# Project-scoped AWM is now a durable kernel authority boundary. Historical
# direct-storage cases remain explicitly skipped as the removed legacy
# contract; current mutation and read routes stay active.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"

    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-awm-project.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    HOME="$TEST_ROOT/home"
    AWM_ROOT="$TEST_ROOT/awm"
    XDG_STATE_HOME="$TEST_ROOT/state"
    MAINFRAME_CONFIG="$TEST_ROOT/mainframe-config"
    PROJECT_ONE="$TEST_ROOT/projects/one"
    PROJECT_TWO="$TEST_ROOT/projects/two"
    PROJECT_CONCURRENT="$TEST_ROOT/projects/concurrent"

    mkdir -p -- "$HOME" "$PROJECT_ONE/subdir" "$PROJECT_TWO" "$PROJECT_CONCURRENT"
    mkdir -m 0700 -- "$XDG_STATE_HOME"
    unset MAINFRAME_AWM_SESSION AWM_SESSION_ID _AWM_SESSION_ID
    export HOME AWM_ROOT XDG_STATE_HOME MAINFRAME_CONFIG BASH_BIN

    case "$BATS_TEST_DESCRIPTION" in
        "project authority gate routes every mutation without ambient AWM storage"|\
        "discover-root rejects a symlinked parent for a nested activation marker"|\
        "discover-root fails closed when a Git sentinel cannot be resolved"|\
        "discover-root uses a validated Git sentinel when Git is not installed"|\
        "generic AWM init cannot create the reserved projects namespace"|\
        "dry project status and session lookup never invent a mapping"|\
        "discover-root status from a nested Git directory remains write-free when unmapped"|\
        "discover-root non-Git fallback remains exact and write-free when unmapped"|\
        "a control-character project path is rejected before private-state writes"|\
        "an ambient control-character AWM root is ignored before durable reads")
            ;;
        *)
            skip "legacy direct-storage contract removed; durable route is covered separately"
            ;;
    esac
}

teardown() {
    # TEST_ROOT is created by mktemp for this test and then resolved physically.
    # Refuse cleanup if either invariant was lost.
    if [[ -n "${TEST_ROOT:-}" && "$TEST_ROOT" != "/" && \
          "${TEST_ROOT##*/}" == mainframe-awm-project.* ]]; then
        rm -rf -- "$TEST_ROOT"
    fi
}

mf() {
    env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        XDG_STATE_HOME="$XDG_STATE_HOME" \
        AWM_BACKEND=file \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$MAINFRAME_BIN" "$@"
}

mf_with_backend() {
    local backend="$1"
    shift
    env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND="$backend" \
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

session_manifest_for_sid() {
    local sid="$1"
    [[ -d "$AWM_ROOT/sessions" ]] || return 0
    find "$AWM_ROOT/sessions" -type f -path "*/${sid}/manifest.json" -print
}

session_manifest_count() {
    if [[ ! -d "$AWM_ROOT/sessions" ]]; then
        printf '0\n'
        return 0
    fi
    find "$AWM_ROOT/sessions" -type f -name manifest.json -print |
        wc -l | tr -d '[:space:]'
}

mapping_files_for_sid() {
    local sid="$1"
    local candidate

    [[ -d "$AWM_ROOT" ]] || return 0
    while IFS= read -r -d '' candidate; do
        case "$candidate" in
            "$AWM_ROOT"/sessions/*) continue ;;
        esac
        if grep -F -- "$sid" "$candidate" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
        fi
    done < <(find "$AWM_ROOT" -type f -print0)
}

mapping_file_for_sid() {
    local sid="$1"
    local matches count

    matches="$(mapping_files_for_sid "$sid")"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    [[ "$count" == "1" ]] || {
        printf 'expected one project mapping for %s; found %s:\n%s\n' \
            "$sid" "$count" "$matches" >&2
        return 1
    }
    printf '%s\n' "$matches"
}

mode_of() {
    local path="$1"
    stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null
}

assert_private_storage_tree() {
    local path mode

    while IFS= read -r -d '' path; do
        mode="$(mode_of "$path")"
        [[ "$mode" == "700" ]] || {
            printf 'expected directory mode 700, got %s: %s\n' "$mode" "$path" >&2
            return 1
        }
    done < <(find "$AWM_ROOT" -type d -print0)

    while IFS= read -r -d '' path; do
        mode="$(mode_of "$path")"
        [[ "$mode" == "600" ]] || {
            printf 'expected file mode 600, got %s: %s\n' "$mode" "$path" >&2
            return 1
        }
    done < <(find "$AWM_ROOT" -type f -print0)

    [[ -z "$(find "$AWM_ROOT" -type l -print -quit)" ]]
}

storage_snapshot() {
    if [[ ! -e "$AWM_ROOT" ]]; then
        printf '<absent>\n'
        return 0
    fi
    find "$AWM_ROOT" -mindepth 1 -print | LC_ALL=C sort
}

storage_fingerprint() {
    local path relative mode mtime digest
    if [[ ! -e "$AWM_ROOT" ]]; then
        printf '<absent>\n'
        return 0
    fi
    while IFS= read -r path; do
        relative="${path#"$AWM_ROOT"/}"
        mode="$(mode_of "$path")"
        if [[ "$OSTYPE" == darwin* ]]; then
            mtime="$(stat -f '%m' "$path")"
        else
            mtime="$(stat -c '%Y' "$path")"
        fi
        if [[ -f "$path" && ! -L "$path" ]]; then
            digest="$(cksum "$path" | awk '{print $1 ":" $2}')"
            printf 'file\t%s\t%s\t%s\t%s\n' "$relative" "$mode" "$mtime" "$digest"
        elif [[ -d "$path" && ! -L "$path" ]]; then
            printf 'dir\t%s\t%s\t%s\n' "$relative" "$mode" "$mtime"
        elif [[ -L "$path" ]]; then
            printf 'link\t%s\t%s\t%s\t%s\n' \
                "$relative" "$mode" "$mtime" "$(readlink "$path")"
        else
            printf 'special\t%s\t%s\t%s\n' "$relative" "$mode" "$mtime"
        fi
    done < <(find "$AWM_ROOT" -mindepth 1 -print | LC_ALL=C sort)
}

@test "project authority gate routes every mutation without ambient AWM storage" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    assert_sid_only "$output"
    run mf awm project checkpoint --project "$PROJECT_ONE" key value
    [[ "$status" -eq 0 ]]
    run mf awm project discovery --project "$PROJECT_ONE" finding
    [[ "$status" -eq 0 ]]
    run mf awm project progress --project "$PROJECT_ONE" task 1/2
    [[ "$status" -eq 0 ]]
    run mf awm project handoff prepare --project "$PROJECT_ONE" reviewer --tokens 256
    [[ "$status" -eq 0 ]]
    run mf awm project close --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ ! -e "$AWM_ROOT" ]]
}

@test "project ensure creates and resumes exactly one private file-backed session" {
    # Project sessions are deliberately file-backed even if an ambient backend
    # preference asks for an external service.
    run mf_with_backend redis awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    assert_sid_only "$output"
    local sid="$output"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]
    assert_sid_only "$output"
    [[ "$(session_manifest_count)" == "1" ]]

    local manifest
    manifest="$(session_manifest_for_sid "$sid")"
    [[ -f "$manifest" ]]
    grep -F -- "\"session_id\":\"$sid\"" "$manifest" >/dev/null
    grep -F -- '"backend":"file"' "$manifest" >/dev/null
    mapping_file_for_sid "$sid" >/dev/null

    run mf awm project session --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]
    assert_sid_only "$output"

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"session_id":"'"$sid"'"'* ]]
}

@test "project operations resume across independent CLI processes without an injected SID" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    run mf awm project checkpoint --project "$PROJECT_ONE" lifecycle-key lifecycle-value \
        --importance high
    [[ "$status" -eq 0 ]]

    run mf awm project get --project "$PROJECT_ONE" lifecycle-key
    [[ "$status" -eq 0 ]]
    [[ "$output" == "lifecycle-value" ]]

    run mf awm project discovery --project "$PROJECT_ONE" \
        "project lifecycle discovery survives process boundaries" --importance critical
    [[ "$status" -eq 0 ]]

    run mf awm project context --project "$PROJECT_ONE" lifecycle-key \
        --tokens 2048 --format json --include discoveries,checkpoints
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"session_id":"'"$sid"'"'* ]]
    [[ "$output" == *"lifecycle-value"* ]]
    [[ "$output" == *"project lifecycle discovery survives process boundaries"* ]]

    run mf awm project handoff prepare --project "$PROJECT_ONE" reviewer \
        --tokens 2048 --format json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"type":"handoff"'* ]]
    [[ "$output" == *'"parent_session":"'"$sid"'"'* ]]
    [[ "$output" == *'"target_agent":"reviewer"'* ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "canonical physical project aliases resolve to one session" {
    local project_alias="$TEST_ROOT/project-alias"
    ln -s -- "$PROJECT_ONE" "$project_alias"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    run mf awm project ensure --project "$PROJECT_ONE/subdir/.."
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]

    run mf awm project ensure --project "$project_alias"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
    [[ "$(mapping_files_for_sid "$sid" | wc -l | tr -d '[:space:]')" == "1" ]]
}

@test "discover-root keeps root and nested Git worktree commands in one session" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    git -C "$PROJECT_ONE" init -q

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root
    [[ "$status" -eq 0 ]]
    local root_sid="$output"
    assert_sid_only "$root_sid"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$root_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
    [[ "$(mapping_files_for_sid "$root_sid" | wc -l | tr -d '[:space:]')" == "1" ]]
}

@test "discover-root keeps a nested Git repository distinct" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local nested_repo="$PROJECT_ONE/subdir/nested-repository"
    mkdir -p -- "$nested_repo"
    git -C "$PROJECT_ONE" init -q
    git -C "$nested_repo" init -q

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    local outer_sid="$output"
    assert_sid_only "$outer_sid"

    run mf awm project ensure --project "$nested_repo" --discover-root
    [[ "$status" -eq 0 ]]
    local nested_sid="$output"
    assert_sid_only "$nested_sid"
    [[ "$nested_sid" != "$outer_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "discover-root keeps linked Git worktrees as distinct physical projects" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local linked_worktree="$PROJECT_TWO/linked-worktree"
    git -C "$PROJECT_ONE" init -q
    printf 'tracked\n' > "$PROJECT_ONE/tracked.txt"
    git -C "$PROJECT_ONE" add tracked.txt
    git -C "$PROJECT_ONE" -c user.name=MAINFRAME -c user.email=mainframe@example.invalid \
        commit -q -m initial
    git -C "$PROJECT_ONE" worktree add -q -b linked-proof "$linked_worktree"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    local primary_sid="$output"

    run mf awm project ensure --project "$linked_worktree" --discover-root
    [[ "$status" -eq 0 ]]
    local linked_sid="$output"
    [[ "$linked_sid" != "$primary_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "discover-root follows a non-Git MAINFRAME onboarding root" {
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$PROJECT_ONE/AGENTS.md"

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root
    [[ "$status" -eq 0 ]]
    local root_sid="$output"
    assert_sid_only "$root_sid"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$root_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "discover-root preserves a non-Git project through its private mapping after marker removal" {
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$PROJECT_ONE/AGENTS.md"
    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    local root_sid="$output"
    rm -- "$PROJECT_ONE/AGENTS.md"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$root_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "discover-root prefers an onboarded monorepo subproject over the outer Git root" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local app_root="$PROJECT_ONE/packages/app"
    local app_nested="$app_root/src/components"
    mkdir -p -- "$app_nested"
    git -C "$PROJECT_ONE" init -q
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$app_root/AGENTS.md"

    run mf awm project ensure --project "$app_root"
    [[ "$status" -eq 0 ]]
    local app_sid="$output"
    assert_sid_only "$app_sid"

    run mf awm project ensure --project "$app_nested" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$app_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "discover-root preserves a mapped monorepo subproject after marker removal" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local app_root="$PROJECT_ONE/packages/app"
    local app_nested="$app_root/src/components"
    mkdir -p -- "$app_nested"
    git -C "$PROJECT_ONE" init -q
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$app_root/AGENTS.md"

    run mf awm project ensure --project "$app_nested" --discover-root
    [[ "$status" -eq 0 ]]
    local app_sid="$output"
    rm -- "$app_root/AGENTS.md"

    run mf awm project ensure --project "$app_nested" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$app_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "discover-root keeps a nearer mapped subproject ahead of an outer managed marker" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local app_root="$PROJECT_ONE/packages/app"
    local app_nested="$app_root/src/components"
    mkdir -p -- "$app_nested"
    git -C "$PROJECT_ONE" init -q
    printf '<!-- MAINFRAME:BEGIN v1 -->\nouter\n<!-- MAINFRAME:END v1 -->\n' \
        > "$PROJECT_ONE/AGENTS.md"
    printf '<!-- MAINFRAME:BEGIN v1 -->\napp\n<!-- MAINFRAME:END v1 -->\n' \
        > "$app_root/AGENTS.md"

    run mf awm project ensure --project "$app_nested" --discover-root
    [[ "$status" -eq 0 ]]
    local app_sid="$output"
    rm -- "$app_root/AGENTS.md"

    run mf awm project ensure --project "$app_nested" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$app_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "discover-root rejects incomplete and symlinked managed markers" {
    local symlink_project="$PROJECT_TWO/linked-marker"
    local real_marker="$TEST_ROOT/foreign-managed-block"
    mkdir -p -- "$symlink_project/child"
    printf '<!-- MAINFRAME:BEGIN v1 -->\n' > "$PROJECT_ONE/AGENTS.md"
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$real_marker"
    ln -s -- "$real_marker" "$symlink_project/AGENTS.md"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"managed root marker is malformed"* ]]
    [[ "$(session_manifest_count)" == "1" ]]

    run mf awm project ensure --project "$symlink_project"
    [[ "$status" -eq 0 ]]
    run mf awm project ensure --project "$symlink_project/child" --discover-root
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"managed root marker path is a symbolic link"* ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "discover-root rejects a symlinked parent for a nested activation marker" {
    local real_cursor="$TEST_ROOT/foreign-cursor"
    local before after
    mkdir -p -- "$real_cursor/rules" "$PROJECT_ONE/subdir"
    printf '<!-- MAINFRAME:BEGIN v1 -->\nmanaged\n<!-- MAINFRAME:END v1 -->\n' \
        > "$real_cursor/rules/mainframe.mdc"
    ln -s -- "$real_cursor" "$PROJECT_ONE/.cursor"
    before="$(storage_snapshot)"

    run mf awm project status --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"managed root marker path is a symbolic link"* ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
}

@test "discover-root ignores ambient Git directory and worktree overrides" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    local poison_repo="$PROJECT_TWO/poison"
    local trace_file="$TEST_ROOT/ambient-git-trace.log"
    mkdir -p -- "$poison_repo"
    git -C "$PROJECT_ONE" init -q
    git -C "$poison_repo" init -q

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root
    [[ "$status" -eq 0 ]]
    local root_sid="$output"

    run env GIT_DIR="$poison_repo/.git" GIT_WORK_TREE="$poison_repo" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree \
        GIT_CONFIG_VALUE_0="$poison_repo" GIT_TRACE="$trace_file" \
        HOME="$HOME" AWM_ROOT="$AWM_ROOT" AWM_BACKEND=file \
        MAINFRAME_BASH="$BASH_BIN" MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm "$MAINFRAME_BIN" awm project ensure \
        --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$root_sid" ]]
    [[ "$(session_manifest_count)" == "1" ]]
    [[ ! -e "$trace_file" ]]
}

@test "discover-root fails closed when a Git sentinel cannot be resolved" {
    mkdir -p -- "$PROJECT_ONE/.git"
    local before after
    before="$(storage_snapshot)"

    run mf awm project status --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Git worktree root could not be resolved safely"* ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
}

@test "discover-root uses a validated Git sentinel when Git is not installed" {
    command -v git >/dev/null 2>&1 || skip "git is required to prepare the fixture"
    git -C "$PROJECT_ONE" init -q
    local before after
    before="$(storage_snapshot)"

    run env \
        HOME="$HOME" \
        AWM_ROOT="$AWM_ROOT" \
        AWM_BACKEND=file \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$BASH_BIN" --noprofile --norc -c '
            source "$1/lib/common.sh" >/dev/null 2>&1
            type() {
                if [[ "${1:-}" == "-P" && "${2:-}" == "git" ]]; then
                    return 1
                fi
                builtin type "$@"
            }
            _awm_project_discover_root "$2"
        ' _ "$PROJECT_ROOT" "$PROJECT_ONE/subdir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$PROJECT_ONE" ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
}

@test "explicit nested project identity remains distinct without discover-root" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    git -C "$PROJECT_ONE" init -q

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local root_sid="$output"
    assert_sid_only "$root_sid"

    run mf awm project ensure --project "$PROJECT_ONE/subdir"
    [[ "$status" -eq 0 ]]
    local nested_sid="$output"
    assert_sid_only "$nested_sid"
    [[ "$nested_sid" != "$root_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "discover-root rejects duplicate flags before AWM writes" {
    local before after
    before="$(storage_snapshot)"

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root --discover-root
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--discover-root may be passed only once"* ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
}

@test "project actions reject equals-style common options before AWM writes" {
    local action flag
    local -a args=()

    for action in checkpoint discovery progress get summary context find handoff; do
        case "$action" in
            checkpoint|progress|summary|find) flag="--project=$PROJECT_ONE" ;;
            *) flag="--discover-root=true" ;;
        esac
        case "$action" in
            checkpoint) args=(checkpoint "$flag" key value) ;;
            discovery) args=(discovery "$flag" finding) ;;
            progress) args=(progress "$flag" task 1/1) ;;
            get) args=(get "$flag" key) ;;
            summary) args=(summary "$flag") ;;
            context) args=(context "$flag" task) ;;
            find) args=(find "$flag" query) ;;
            handoff) args=(handoff "$flag" prepare next-agent) ;;
        esac

        run mf awm project "${args[@]}"
        [[ "$status" -eq 2 ]]
        [[ "$output" == *"--project must be passed as"* || \
           "$output" == *"--discover-root does not take a value"* ]]
        [[ "$(session_manifest_count)" == "0" ]]
    done
}

@test "project actions validate their grammar before ensuring a mapping" {
    local action
    local -a args=()

    for action in checkpoint discovery progress get summary context find handoff; do
        case "$action" in
            checkpoint) args=(checkpoint --project "$PROJECT_ONE" only-key) ;;
            discovery) args=(discovery --project "$PROJECT_ONE") ;;
            progress) args=(progress --project "$PROJECT_ONE" task) ;;
            get) args=(get --project "$PROJECT_ONE" key default extra) ;;
            summary) args=(summary --project "$PROJECT_ONE" --unknown) ;;
            context) args=(context --project "$PROJECT_ONE") ;;
            find) args=(find --project "$PROJECT_ONE" query --session foreign) ;;
            handoff) args=(handoff prepare --project "$PROJECT_ONE") ;;
        esac

        run mf awm project "${args[@]}"
        [[ "$status" -eq 2 ]]
        [[ "$(session_manifest_count)" == "0" ]]
    done
}

@test "project actions reject invalid option values before ensuring a mapping" {
    local action
    local -a args=()

    for action in ensure checkpoint discovery progress summary context find handoff; do
        case "$action" in
            ensure) args=(ensure --project "$PROJECT_ONE" --name --bogus) ;;
            checkpoint) args=(checkpoint --project "$PROJECT_ONE" key value --importance --bogus) ;;
            discovery) args=(discovery --project "$PROJECT_ONE" finding --tags --bogus) ;;
            progress) args=(progress --project "$PROJECT_ONE" task one/two) ;;
            summary) args=(summary --project "$PROJECT_ONE" --tokens --bogus) ;;
            context) args=(context --project "$PROJECT_ONE" task --format yaml) ;;
            find) args=(find --project "$PROJECT_ONE" query --limit 0) ;;
            handoff) args=(handoff prepare --project "$PROJECT_ONE" next-agent --tokens 0) ;;
        esac

        run mf awm project "${args[@]}"
        [[ "$status" -eq 2 ]]
        [[ "$(session_manifest_count)" == "0" ]]
    done

    run mf awm project checkpoint --project "$PROJECT_ONE" key value --importance medium
    [[ "$status" -eq 2 ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "end of options cannot retroactively authorize earlier flag-looking data" {
    run mf awm project checkpoint --project "$PROJECT_ONE" --typo value --
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"-- must appear before action data"* ]]
    [[ "$(session_manifest_count)" == "0" ]]

    run mf awm project discovery --project "$PROJECT_ONE" prepare --
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"-- must appear before action data"* ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "project actions accept flag-looking data only after end of options" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    assert_sid_only "$output"

    run mf awm project checkpoint --project "$PROJECT_ONE" -- --project --discover-root
    [[ "$status" -eq 0 ]]

    run mf awm project get --project "$PROJECT_ONE" -- --project
    [[ "$status" -eq 0 ]]
    [[ "$output" == "--discover-root" ]]

    run mf awm project handoff prepare --project "$PROJECT_ONE" -- --next-agent
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"target_agent":"--next-agent"'* ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "a project mapping cannot resolve to a same-ID session in another namespace" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local project_manifest project_session duplicate_session duplicate_tmp
    assert_sid_only "$sid"
    run mf awm project checkpoint --project "$PROJECT_ONE" scope-key project-value
    [[ "$status" -eq 0 ]]
    project_manifest="$(session_manifest_for_sid "$sid")"
    project_session="${project_manifest%/manifest.json}"
    duplicate_session="$AWM_ROOT/sessions/$sid"
    cp -R -- "$project_session" "$duplicate_session"
    duplicate_tmp="$duplicate_session/manifest.json.tmp"
    jq -c '.namespace = "" | .name = "wrong-namespace"' \
        "$duplicate_session/manifest.json" > "$duplicate_tmp"
    chmod 600 "$duplicate_tmp"
    mv -- "$duplicate_tmp" "$duplicate_session/manifest.json"
    find "$duplicate_session" -type d -exec chmod 700 {} +
    find "$duplicate_session" -type f -exec chmod 600 {} +
    printf 'wrong-namespace-value' > "$duplicate_session/data/scope-key"
    chmod 600 "$duplicate_session/data/scope-key"

    run mf awm project get --project "$PROJECT_ONE" scope-key
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project-value" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    run jq -e '
      .session_id == $sid and
      .session.namespace == "projects" and
      .session.backend == "file"
    ' --arg sid "$sid" <<< "$output"
    [[ "$status" -eq 0 ]]
}

@test "generic AWM init cannot create the reserved projects namespace" {
    local before after
    before="$(storage_snapshot)"

    run mf awm init forbidden-project-session --namespace projects
    [[ "$status" -ne 0 ]]

    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "generic AWM list --json never enumerates project sessions" {
    run mf awm init ordinary-session
    [[ "$status" -eq 0 ]]
    local ordinary_sid="$output"
    assert_sid_only "$ordinary_sid"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local project_sid="$output"
    assert_sid_only "$project_sid"

    run mf awm list --json
    [[ "$status" -eq 0 ]]
    run jq -e --arg ordinary "$ordinary_sid" --arg project "$project_sid" '
      length == 1 and
      .[0].session_id == $ordinary and
      .[0].namespace == "" and
      all(.[]; .session_id != $project and .namespace != "projects")
    ' <<< "$output"
    [[ "$status" -eq 0 ]]
}

@test "generic AWM routes quarantine physically reserved project sessions with corrupt manifests" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local manifest original variant temp
    assert_sid_only "$sid"

    run mf awm project checkpoint --project "$PROJECT_ONE" project-secret project-value
    [[ "$status" -eq 0 ]]
    manifest="$AWM_ROOT/sessions/projects/$sid/manifest.json"
    original=$(<"$manifest")

    for variant in wrong missing malformed absent; do
        case "$variant" in
            wrong)
                temp="$manifest.tmp"
                jq -c '.namespace = "ordinary"' <<<"$original" > "$temp"
                chmod 600 "$temp"
                mv -- "$temp" "$manifest"
                ;;
            missing)
                temp="$manifest.tmp"
                jq -c 'del(.namespace)' <<<"$original" > "$temp"
                chmod 600 "$temp"
                mv -- "$temp" "$manifest"
                ;;
            malformed)
                printf '{malformed\n' > "$manifest"
                chmod 600 "$manifest"
                ;;
            absent)
                rm -f -- "$manifest"
                ;;
        esac

        run mf awm list --json
        [[ "$status" -eq 0 ]]
        [[ "$output" != *"$sid"* ]]

        run mf awm get --session "$sid" project-secret
        [[ "$status" -ne 0 ]]
        [[ "$output" != *"project-value"* ]]

        printf '%s\n' "$original" > "$manifest"
        chmod 600 "$manifest"
    done
}

@test "generic AWM SID routes cannot resume or read a project session" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local route before after
    local -a args=()
    assert_sid_only "$sid"

    run mf awm project checkpoint --project "$PROJECT_ONE" project-secret project-value
    [[ "$status" -eq 0 ]]

    for route in resume get summary context find handoff status doctor inspect; do
        case "$route" in
            resume) args=(resume "$sid") ;;
            get) args=(get --session "$sid" project-secret) ;;
            summary) args=(summary --session "$sid" --tokens 256) ;;
            context) args=(context --session "$sid" "project task" --tokens 256 --format json) ;;
            find) args=(find --session "$sid" project --kind mixed --limit 5) ;;
            handoff) args=(handoff prepare --session "$sid" next-agent --tokens 256 --format json) ;;
            status) args=(status --session "$sid") ;;
            doctor) args=(doctor --session "$sid") ;;
            inspect) args=(inspect "$sid") ;;
        esac

        before="$(storage_fingerprint)"
        run mf awm "${args[@]}"
        [[ "$status" -ne 0 ]]
        [[ "$output" != *"project-value"* ]]
        after="$(storage_fingerprint)"
        [[ "$after" == "$before" ]]
    done

    run mf awm project get --project "$PROJECT_ONE" project-secret
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project-value" ]]
}

@test "generic AWM checkpoint and export cannot mutate or disclose a project session" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local export_path="$TEST_ROOT/project-export.md"
    local before after
    assert_sid_only "$sid"

    run mf awm project checkpoint --project "$PROJECT_ONE" project-secret project-value
    [[ "$status" -eq 0 ]]

    before="$(storage_fingerprint)"
    run mf awm checkpoint --session "$sid" generic-write forbidden
    [[ "$status" -ne 0 ]]
    [[ ! -e "$AWM_ROOT/sessions/projects/$sid/data/generic-write" ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]

    before="$(storage_fingerprint)"
    run mf awm export --session "$sid" "$export_path"
    [[ "$status" -ne 0 ]]
    [[ ! -e "$export_path" ]]
    [[ "$output" != *"project-value"* ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]

    run mf awm project get --project "$PROJECT_ONE" generic-write missing
    [[ "$status" -eq 1 ]]
    [[ "$output" == "missing" ]]
}

@test "generic AWM migrate cannot target project sessions" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local before after
    assert_sid_only "$sid"

    before="$(storage_fingerprint)"
    run mf awm migrate "$sid"
    [[ "$status" -ne 0 ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]

    run mf awm migrate --all
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]
}

@test "generic AWM resume and checkpoint cannot renew a completed project session" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local manifest completed_tmp before after
    assert_sid_only "$sid"
    manifest="$(session_manifest_for_sid "$sid")"
    completed_tmp="$manifest.completed"
    jq -c '.status = "completed"' "$manifest" > "$completed_tmp"
    chmod 600 "$completed_tmp"
    mv -- "$completed_tmp" "$manifest"

    before="$(storage_fingerprint)"
    run mf awm resume "$sid"
    [[ "$status" -ne 0 ]]
    [[ "$output" != "$sid" ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]

    run mf awm checkpoint --session "$sid" completed-write forbidden
    [[ "$status" -ne 0 ]]
    [[ ! -e "$AWM_ROOT/sessions/projects/$sid/data/completed-write" ]]
    after="$(storage_fingerprint)"
    [[ "$after" == "$before" ]]

    run jq -e '.status == "completed" and .namespace == "projects"' "$manifest"
    [[ "$status" -eq 0 ]]
    [[ "$(session_manifest_count)" == "1" ]]
}

@test "concurrent project ensures converge on exactly one SID" {
    local output_dir="$TEST_ROOT/concurrent-output"
    mkdir -p -- "$output_dir"

    run "$BASH_BIN" --noprofile --norc -c '
        set -u
        home=$1
        awm_root=$2
        config=$3
        mainframe_bin=$4
        project=$5
        bash_bin=$6
        output_dir=$7
        pids=()
        failed=0

        for ((i = 1; i <= 12; i++)); do
            env HOME="$home" AWM_ROOT="$awm_root" AWM_BACKEND=file \
                MAINFRAME_BASH="$bash_bin" MAINFRAME_CONFIG="$config" \
                MAINFRAME_LIBS=awm \
                "$mainframe_bin" awm project ensure --project "$project" \
                >"$output_dir/sid.$i" 2>"$output_dir/stderr.$i" &
            pids+=("$!")
        done
        for pid in "${pids[@]}"; do
            wait "$pid" || failed=1
        done
        if (( failed != 0 )); then
            for file in "$output_dir"/stderr.*; do
                [[ ! -s "$file" ]] || printf "%s:\n%s\n" "$file" "$(< "$file")" >&2
            done
            exit 1
        fi
        for ((i = 1; i <= 12; i++)); do
            [[ ! -s "$output_dir/stderr.$i" ]] || {
                printf "unexpected stderr from ensure %d:\n%s\n" \
                    "$i" "$(< "$output_dir/stderr.$i")" >&2
                exit 1
            }
            printf "%s\n" "$(< "$output_dir/sid.$i")"
        done
    ' _ "$HOME" "$AWM_ROOT" "$MAINFRAME_CONFIG" "$MAINFRAME_BIN" \
        "$PROJECT_CONCURRENT" "$BASH_BIN" "$output_dir"

    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d '[:space:]')" == "12" ]]
    local unique_sids
    unique_sids="$(printf '%s\n' "$output" | LC_ALL=C sort -u)"
    assert_sid_only "$unique_sids"
    [[ "$(session_manifest_count)" == "1" ]]
    mapping_file_for_sid "$unique_sids" >/dev/null
}

@test "dry project status and session lookup never invent a mapping" {
    local before after_status after_session
    before="$(storage_snapshot)"

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -eq 75 ]]
    [[ -z "$output" ]]
    [[ "$output" != *"MAINFRAME AWM"* ]]
    [[ "$output" != *"Usage:"* ]]
    [[ ! "$output" =~ ^[a-f0-9]{12}$ ]]
    after_status="$(storage_snapshot)"
    [[ "$after_status" == "$before" ]]

    run mf awm project session --project "$PROJECT_ONE"
    [[ "$status" -eq 75 ]]
    [[ -z "$output" ]]
    [[ "$output" != *"MAINFRAME AWM"* ]]
    [[ "$output" != *"Usage:"* ]]
    [[ ! "$output" =~ ^[a-f0-9]{12}$ ]]
    after_session="$(storage_snapshot)"
    [[ "$after_session" == "$before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "mapped project session and status are read-only and never repair layout" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local journal before after_session after_status
    journal="$AWM_ROOT/sessions/projects/$sid/journal/events.jsonl"
    [[ -f "$journal" ]]
    rm -- "$journal"
    before="$(storage_fingerprint)"
    sleep 1

    run mf awm project session --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]
    [[ ! -e "$journal" ]]
    after_session="$(storage_fingerprint)"
    [[ "$after_session" == "$before" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"status":"mapped"'* ]]
    [[ "$output" == *'"session_id":"'"$sid"'"'* ]]
    [[ ! -e "$journal" ]]
    after_status="$(storage_fingerprint)"
    [[ "$after_status" == "$before" ]]
}

@test "discover-root status from a nested Git directory remains write-free when unmapped" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    git -C "$PROJECT_ONE" init -q
    local before after
    before="$(storage_snapshot)"

    run mf awm project status --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 75 ]]
    [[ -z "$output" ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "discover-root non-Git fallback remains exact and write-free when unmapped" {
    local before after exact_output
    before="$(storage_snapshot)"

    run mf awm project status --project "$PROJECT_ONE/subdir"
    [[ "$status" -ne 0 ]]
    exact_output="$output"

    run mf awm project status --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -ne 0 ]]
    [[ "$output" == "$exact_output" ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "discover-root never lets a filesystem-root mapping capture an unmarked project" {
    run mf awm project ensure --project /
    [[ "$status" -eq 0 ]]
    local filesystem_sid="$output"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -eq 0 ]]
    [[ "$output" != "$filesystem_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "a control-character project path is rejected before private-state writes" {
    local unsafe_project="$TEST_ROOT/projects/control"$'\033'"path"
    local before after
    mkdir -p -- "$unsafe_project"
    before="$(storage_snapshot)"

    run mf awm project ensure --project "$unsafe_project"
    [[ "$status" -ne 0 ]]
    after="$(storage_snapshot)"
    [[ "$after" == "$before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
}

@test "an ambient control-character AWM root is ignored before durable reads" {
    local unsafe_root="$TEST_ROOT/awm"$'\t'"unsafe"

    run env \
        HOME="$HOME" \
        AWM_ROOT="$unsafe_root" \
        XDG_STATE_HOME="$XDG_STATE_HOME" \
        AWM_BACKEND=file \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_CONFIG="$MAINFRAME_CONFIG" \
        MAINFRAME_LIBS=awm \
        "$MAINFRAME_BIN" awm project status --project "$PROJECT_ONE"
    [[ "$status" -eq 75 ]]
    [[ -z "$output" ]]
    [[ ! -e "$unsafe_root" ]]
}

@test "default project binding never persists the canonical project path" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    assert_sid_only "$output"

    # The private index is keyed by a digest. Default session metadata uses
    # the same digest prefix, so moving a diagnostics bundle cannot disclose
    # the user's source-tree location.
    run grep -R -F -- "$PROJECT_ONE" "$AWM_ROOT"
    [[ "$status" -eq 1 ]]
    [[ -z "$output" ]]
}

@test "a completed mapped session is replaced once and then resumed" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local completed_sid="$output"
    assert_sid_only "$completed_sid"

    local completed_manifest completed_tmp
    completed_manifest="$(session_manifest_for_sid "$completed_sid")"
    completed_tmp="$completed_manifest.completed"
    jq -c '.status = "completed"' "$completed_manifest" > "$completed_tmp"
    chmod 600 "$completed_tmp"
    mv -- "$completed_tmp" "$completed_manifest"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local replacement_sid="$output"
    assert_sid_only "$replacement_sid"
    [[ "$replacement_sid" != "$completed_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$replacement_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
}

@test "project mappings and AWM storage retain private portable modes" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    assert_sid_only "$sid"

    run mf awm project checkpoint --project "$PROJECT_ONE" private-key private-value
    [[ "$status" -eq 0 ]]
    run mf awm project discovery --project "$PROJECT_ONE" "private discovery"
    [[ "$status" -eq 0 ]]
    run mf awm project handoff prepare --project "$PROJECT_ONE" reviewer --tokens 1024
    [[ "$status" -eq 0 ]]

    mapping_file_for_sid "$sid" >/dev/null
    assert_private_storage_tree
}

@test "a symlinked project mapping fails closed without replacing the session" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping saved_mapping attacker_file before_sessions
    mapping="$(mapping_file_for_sid "$sid")"
    saved_mapping="$TEST_ROOT/saved-project-mapping"
    attacker_file="$TEST_ROOT/attacker-controlled"
    before_sessions="$(session_manifest_count)"

    mv -- "$mapping" "$saved_mapping"
    printf 'attacker-content\n' > "$attacker_file"
    ln -s -- "$attacker_file" "$mapping"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ -L "$mapping" ]]
    [[ "$(< "$attacker_file")" == "attacker-content" ]]
    [[ "$(session_manifest_count)" == "$before_sessions" ]]
    [[ -f "$saved_mapping" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'"status":"invalid"'* ]]
    [[ "$(< "$attacker_file")" == "attacker-content" ]]
}

@test "discover-root fails closed on a symlinked Git-root mapping from a descendant" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    git -C "$PROJECT_ONE" init -q

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping saved_mapping attacker_file before_sessions
    mapping="$(mapping_file_for_sid "$sid")"
    saved_mapping="$TEST_ROOT/saved-discovered-mapping"
    attacker_file="$TEST_ROOT/discovered-attacker-controlled"
    before_sessions="$(session_manifest_count)"
    mv -- "$mapping" "$saved_mapping"
    printf 'attacker-content\n' > "$attacker_file"
    ln -s -- "$attacker_file" "$mapping"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -ne 0 ]]
    [[ -L "$mapping" ]]
    [[ "$(< "$attacker_file")" == "attacker-content" ]]
    [[ "$(session_manifest_count)" == "$before_sessions" ]]
    [[ -f "$saved_mapping" ]]
}

@test "symlinked mapped session storage fails closed without replacement" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping mapping_before manifest session_dir saved_session attacker_dir
    mapping="$(mapping_file_for_sid "$sid")"
    mapping_before="$(< "$mapping")"
    manifest="$(session_manifest_for_sid "$sid")"
    session_dir="${manifest%/manifest.json}"
    saved_session="$TEST_ROOT/saved-session"
    attacker_dir="$TEST_ROOT/attacker-session"
    mkdir -p -- "$attacker_dir"
    printf 'attacker-content\n' > "$attacker_dir/marker"
    mv -- "$session_dir" "$saved_session"
    ln -s -- "$attacker_dir" "$session_dir"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ -L "$session_dir" ]]
    [[ "$(< "$attacker_dir/marker")" == "attacker-content" ]]
    [[ "$(< "$mapping")" == "$mapping_before" ]]
    [[ "$(session_manifest_count)" == "0" ]]
    [[ -f "$saved_session/manifest.json" ]]
}

@test "a malformed project mapping fails closed without repair or a new session" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping before_sessions
    mapping="$(mapping_file_for_sid "$sid")"
    before_sessions="$(session_manifest_count)"
    printf '{"session_id":"../../escape","project":"malformed"}\n' > "$mapping"
    chmod 600 "$mapping"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$(< "$mapping")" == '{"session_id":"../../escape","project":"malformed"}' ]]
    [[ "$(session_manifest_count)" == "$before_sessions" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'"status":"invalid"'* ]]
    [[ "$output" != *'"status":"unmapped"'* ]]
    [[ "$(< "$mapping")" == '{"session_id":"../../escape","project":"malformed"}' ]]
}

@test "discover-root fails closed on a malformed Git-root mapping" {
    command -v git >/dev/null 2>&1 || skip "git is required"
    git -C "$PROJECT_ONE" init -q

    run mf awm project ensure --project "$PROJECT_ONE" --discover-root
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping before_sessions
    mapping="$(mapping_file_for_sid "$sid")"
    before_sessions="$(session_manifest_count)"
    printf '{"session_id":"../../escape","project":"malformed"}\n' > "$mapping"
    chmod 600 "$mapping"

    run mf awm project ensure --project "$PROJECT_ONE/subdir" --discover-root
    [[ "$status" -ne 0 ]]
    [[ "$(< "$mapping")" == '{"session_id":"../../escape","project":"malformed"}' ]]
    [[ "$(session_manifest_count)" == "$before_sessions" ]]
}

@test "an over-permissive project mapping fails closed without chmod repair" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local mapping before_sessions
    mapping="$(mapping_file_for_sid "$sid")"
    before_sessions="$(session_manifest_count)"
    chmod 644 "$mapping"

    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$(mode_of "$mapping")" == "644" ]]
    [[ "$(session_manifest_count)" == "$before_sessions" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'"status":"invalid"'* ]]
    [[ "$(mode_of "$mapping")" == "644" ]]
}

@test "dry project lookup rejects non-private session files without chmod repair" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local sid="$output"
    local manifest="$AWM_ROOT/sessions/projects/$sid/manifest.json"
    chmod 644 "$manifest"

    run mf awm project session --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$(mode_of "$manifest")" == "644" ]]

    run mf awm project status --project "$PROJECT_ONE"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'"status":"invalid"'* ]]
    [[ "$(mode_of "$manifest")" == "644" ]]
}

@test "unrelated canonical projects receive different sessions" {
    run mf awm project ensure --project "$PROJECT_ONE"
    [[ "$status" -eq 0 ]]
    local first_sid="$output"
    assert_sid_only "$first_sid"

    run mf awm project ensure --project "$PROJECT_TWO"
    [[ "$status" -eq 0 ]]
    local second_sid="$output"
    assert_sid_only "$second_sid"

    [[ "$first_sid" != "$second_sid" ]]
    [[ "$(session_manifest_count)" == "2" ]]
    mapping_file_for_sid "$first_sid" >/dev/null
    mapping_file_for_sid "$second_sid" >/dev/null
}

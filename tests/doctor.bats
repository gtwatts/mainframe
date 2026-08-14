#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    if ! "$BASH_BIN" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))'; then
        skip "Bash 4.4+ is required"
    fi
    command -v jq >/dev/null || skip "jq is required for mainframe doctor"

    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-doctor.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    RUNTIME_ROOT="$TEST_ROOT/runtime"
    TEST_HOME="$TEST_ROOT/home"
    PAYLOAD_LIST="$TEST_ROOT/release-payload-files.txt"
    mkdir -p "$RUNTIME_ROOT" "$TEST_HOME"

    # Exercise the same files that ship in the release rather than allowing
    # adjacent checkout-only state to make doctor appear healthier.
    # shellcheck source=scripts/dev/release-payload.sh
    source "$PROJECT_ROOT/scripts/dev/release-payload.sh"
    mainframe_release_payload_files "$PROJECT_ROOT" > "$PAYLOAD_LIST"
    while IFS= read -r relative; do
        mkdir -p "$RUNTIME_ROOT/$(dirname "$relative")"
        cp -p "$PROJECT_ROOT/$relative" "$RUNTIME_ROOT/$relative"
    done < "$PAYLOAD_LIST"
}

teardown() {
    if [[ -n "${TEST_ROOT:-}" && "$TEST_ROOT" != / &&
          "${TEST_ROOT##*/}" == mainframe-doctor.* ]]; then
        rm -rf -- "$TEST_ROOT"
    fi
}

mode_of() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

tree_fingerprint() {
    local root="$1" path relative mode digest target
    if [[ ! -e "$root" ]]; then
        printf '<absent>\n'
        return 0
    fi
    while IFS= read -r path; do
        relative="${path#"$root"/}"
        [[ "$path" != "$root" ]] || relative=.
        mode="$(mode_of "$path")"
        if [[ -L "$path" ]]; then
            target="$(readlink "$path")"
            printf 'link\t%s\t%s\t%s\n' "$relative" "$mode" "$target"
        elif [[ -d "$path" ]]; then
            printf 'dir\t%s\t%s\n' "$relative" "$mode"
        elif [[ -f "$path" ]]; then
            digest="$(cksum "$path" | awk '{print $1 ":" $2}')"
            printf 'file\t%s\t%s\t%s\n' "$relative" "$mode" "$digest"
        else
            printf 'special\t%s\t%s\n' "$relative" "$mode"
        fi
    done < <(find "$root" -print | LC_ALL=C sort)
}

run_doctor() {
    run env \
        HOME="$TEST_HOME" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        "$BASH_BIN" --noprofile --norc -p \
        "$RUNTIME_ROOT/bin/mainframe" doctor
}

assert_complete_report() {
    [[ "$output" == *"MAINFRAME_ROOT:"* ]]
    [[ "$output" == *"Bash version:"* ]]
    [[ "$output" == *"OS:"* ]]
    [[ "$output" == *"Libraries:"* ]]
    [[ "$output" == *"Functions:"* ]]
    [[ "$output" == *"Runtime loaded:"* ]]
    [[ "$output" == *"common.sh:"* ]]
    [[ "$output" == *"Agent gateway:"* ]]
    [[ "$output" == *"Status:"* ]]
}

assert_doctor_read_only() {
    local runtime_before="$1" home_before="$2"
    [[ "$(tree_fingerprint "$RUNTIME_ROOT")" == "$runtime_before" ]]
    [[ "$(tree_fingerprint "$TEST_HOME")" == "$home_before" ]]
}

@test "doctor completes a healthy release-runtime report without mutation" {
    local runtime_before home_before
    runtime_before="$(tree_fingerprint "$RUNTIME_ROOT")"
    home_before="$(tree_fingerprint "$TEST_HOME")"

    run_doctor

    [[ "$status" -eq 0 ]]
    assert_complete_report
    [[ "$output" == *"Libraries:      Loaded (OK)"* ]]
    [[ "$output" == *"Agent gateway:  Ready (OK)"* ]]
    [[ "$output" == *"Status: All checks passed!"* ]]
    assert_doctor_read_only "$runtime_before" "$home_before"
}

@test "doctor reports a missing gateway and continues through its final summary" {
    local runtime_before home_before
    rm "$RUNTIME_ROOT/hooks/agent-gateway.sh"
    runtime_before="$(tree_fingerprint "$RUNTIME_ROOT")"
    home_before="$(tree_fingerprint "$TEST_HOME")"

    run_doctor

    [[ "$status" -eq 1 ]]
    assert_complete_report
    [[ "$output" == *"Functions:"*"registry functions"* ]]
    [[ "$output" == *"common.sh:      Found (OK)"* ]]
    [[ "$output" == *"Agent gateway:  NOT READY"* ]]
    [[ "$output" == *"Status: 1 issue(s) found"* ]]
    assert_doctor_read_only "$runtime_before" "$home_before"
}

@test "doctor reports an unavailable registry and still checks the gateway" {
    local runtime_before home_before
    rm "$RUNTIME_ROOT/FUNCTIONS.json"
    runtime_before="$(tree_fingerprint "$RUNTIME_ROOT")"
    home_before="$(tree_fingerprint "$TEST_HOME")"

    run_doctor

    [[ "$status" -eq 1 ]]
    assert_complete_report
    [[ "$output" == *"Functions:      REGISTRY UNAVAILABLE (ERROR)"* ]]
    [[ "$output" == *"Runtime loaded:"* ]]
    [[ "$output" == *"Agent gateway:  Ready (OK)"* ]]
    [[ "$output" == *"Status: 1 issue(s) found"* ]]
    assert_doctor_read_only "$runtime_before" "$home_before"
}

@test "doctor aggregates independent library registry and gateway failures" {
    local runtime_before home_before
    printf '\nunset -f json_object\n' >> "$RUNTIME_ROOT/lib/common.sh"
    rm "$RUNTIME_ROOT/FUNCTIONS.json" "$RUNTIME_ROOT/hooks/agent-gateway.sh"
    runtime_before="$(tree_fingerprint "$RUNTIME_ROOT")"
    home_before="$(tree_fingerprint "$TEST_HOME")"

    run_doctor

    [[ "$status" -eq 1 ]]
    assert_complete_report
    [[ "$output" == *"Libraries:      NOT LOADED (ERROR)"* ]]
    [[ "$output" == *"Functions:      REGISTRY UNAVAILABLE (ERROR)"* ]]
    [[ "$output" == *"common.sh:      Found (OK)"* ]]
    [[ "$output" == *"Agent gateway:  NOT READY"* ]]
    [[ "$output" == *"Status: 3 issue(s) found"* ]]
    assert_doctor_read_only "$runtime_before" "$home_before"
}

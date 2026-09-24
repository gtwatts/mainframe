#!/usr/bin/env bats

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    PROJECT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
}

copy_release_payload() {
    local destination="$1" payload_list="$2"

    # shellcheck source=../scripts/dev/release-payload.sh
    source "$PROJECT_ROOT/scripts/dev/release-payload.sh"
    mainframe_release_payload_files "$PROJECT_ROOT" > "$payload_list"
    mkdir -p "$destination"
    (cd "$PROJECT_ROOT" && tar -cf - -T "$payload_list") |
        (cd "$destination" && tar -xf -)
}

@test "release readiness excludes historical Pi certificates from current coverage" {
    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" release readiness --json

    [[ "$status" -eq 2 ]]
    jq -e '
      .schema_version == 1 and
      .kind == "mainframe-release-readiness" and
      .scope == "offline-checked-in-evidence-only" and
      .mainframe_version == $version and
      .overall == {
        ready: false,
        status: "NOT_READY",
        reason: "external CI and distribution state are not proven by this offline report"
      } and
      .checked_in_contracts.readable_and_valid == true and
      .checked_in_contracts.pi.certified_platforms == [] and
      .checked_in_contracts.pi.missing_advertised_platforms ==
        ["Darwin-arm64-none", "Darwin-x86_64-none", "Linux-x86_64-glibc"] and
      .checked_in_contracts.pi.complete_for_advertised_platforms == false and
      .checked_in_contracts.workflow_definition == "present-not-execution-proof" and
      .external_state == {
        exact_candidate_ci: "UNVERIFIED",
        public_immutable_release: "UNVERIFIED",
        homebrew_tap: "UNVERIFIED"
      } and
      (.next_actions[0].command == "scripts/dev/release-candidate.sh --check") and
      .checked_in_contracts.pi.exact_certifications == [] and
      (.checked_in_contracts.pi.historical_certifications | length == 2) and
      all(.checked_in_contracts.pi.historical_certifications[];
        .mainframe_version == "10.2.0" and
        .scope == "historical-only-not-current-release-proof") and
      .checked_in_contracts.pi.local_runtime_verification ==
        "not-inspected-use-in-session-mainframe-doctor"
    ' --arg version "$PROJECT_VERSION" <<< "$output"
}

@test "installed payload treats the repository-only workflow as absent, never failed or green" {
    local runtime payload_list

    runtime="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-readiness-archive.XXXXXX")"
    payload_list="$runtime/payload.txt"
    copy_release_payload "$runtime/root" "$payload_list"

    run "$BASH_BIN" "$runtime/root/bin/mainframe" release readiness --json
    rm -rf -- "$runtime"

    [[ "$status" -eq 2 ]]
    jq -e '
      .overall.ready == false and
      .checked_in_contracts.workflow_definition ==
        "not-shipped-not-execution-proof" and
      .external_state.exact_candidate_ci == "UNVERIFIED"
    ' <<< "$output"
}

@test "release readiness rejects overclaimed Pi certifications" {
    local runtime payload_list compatibility original temporary

    runtime="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-readiness-overclaim.XXXXXX")"
    payload_list="$runtime/payload.txt"
    copy_release_payload "$runtime/root" "$payload_list"
    compatibility="$runtime/root/config/pi-compatibility.json"
    original="$runtime/original.json"
    temporary="$runtime/compatibility.json"
    cp "$compatibility" "$original"

    jq --arg version "$PROJECT_VERSION" \
        '.certifications[0].mainframe_version = $version |
         .certifications[0].platforms += ["Plan9-amd64-none"]' \
        "$original" > "$temporary"
    mv "$temporary" "$compatibility"
    run "$BASH_BIN" "$runtime/root/bin/mainframe" release readiness --json
    [[ "$status" -eq 1 ]]
    jq -e '
      .overall.status == "INSPECTION_BLOCKED" and
      (.overall.message | contains("outside the advertised release contract"))
    ' <<< "$output"

    jq '.certifications[0].capabilities.agent_bash_gate = "not-observable"' \
        "$original" > "$temporary"
    mv "$temporary" "$compatibility"
    run "$BASH_BIN" "$runtime/root/bin/mainframe" release readiness --json
    rm -rf -- "$runtime"

    [[ "$status" -eq 1 ]]
    jq -e '
      .overall.status == "INSPECTION_BLOCKED" and
      (.overall.message | contains("compatibility contract is malformed"))
    ' <<< "$output"
}

@test "release readiness counts only exact current-version certificates in a mixed fixture" {
    local runtime payload_list compatibility temporary
    runtime="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-readiness-mixed.XXXXXX")"
    payload_list="$runtime/payload.txt"
    copy_release_payload "$runtime/root" "$payload_list"
    compatibility="$runtime/root/config/pi-compatibility.json"
    temporary="$runtime/compatibility.json"
    # This synthetic fixture tests selection, not certificate issuance.
    jq --arg version "$PROJECT_VERSION" \
        '.certifications[0].mainframe_version = $version' \
        "$compatibility" > "$temporary"
    mv "$temporary" "$compatibility"

    run "$BASH_BIN" "$runtime/root/bin/mainframe" release readiness --json
    rm -rf -- "$runtime"

    [[ "$status" -eq 2 ]]
    jq -e --arg version "$PROJECT_VERSION" '
      .overall.ready == false and
      .checked_in_contracts.pi.certified_platforms == ["Darwin-arm64-none"] and
      (.checked_in_contracts.pi.exact_certifications | length == 1) and
      .checked_in_contracts.pi.exact_certifications[0].mainframe_version == $version and
      (.checked_in_contracts.pi.historical_certifications | length == 1) and
      .checked_in_contracts.pi.historical_certifications[0].mainframe_version == "10.2.0" and
      .external_state.exact_candidate_ci == "UNVERIFIED"
    ' <<< "$output"
}

@test "release readiness rejects future and malformed certificate versions" {
    local runtime payload_list compatibility original temporary candidate_version
    runtime="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-readiness-version.XXXXXX")"
    payload_list="$runtime/payload.txt"
    copy_release_payload "$runtime/root" "$payload_list"
    compatibility="$runtime/root/config/pi-compatibility.json"
    original="$runtime/original.json"
    temporary="$runtime/compatibility.json"
    cp "$compatibility" "$original"
    for candidate_version in 999999.0.0 10.02.0 not-a-version; do
        jq --arg version "$candidate_version" \
            '.certifications[0].mainframe_version = $version' \
            "$original" > "$temporary"
        mv "$temporary" "$compatibility"
        run "$BASH_BIN" "$runtime/root/bin/mainframe" release readiness --json
        [[ "$status" -eq 1 ]]
        jq -e '.overall.status == "INSPECTION_BLOCKED"' <<< "$output"
    done
    rm -rf -- "$runtime"
}

@test "release readiness help and text output state the offline boundary" {
    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" release --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage: mainframe release readiness [--json]"* ]]
    [[ "$output" == *"workflow definition is never treated as a successful CI"* ]]

    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" release readiness
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Overall: NOT_READY"* ]]
    [[ "$output" == *"Linux-x86_64-glibc"* ]]
    [[ "$output" == *"Exact-candidate CI: UNVERIFIED"* ]]
    [[ "$output" == *"Public immutable release: UNVERIFIED"* ]]
    [[ "$output" == *"Homebrew tap: UNVERIFIED"* ]]
    [[ "$output" == *"Historical Pi certifications (not current release proof): 2"* ]]
    [[ "$output" == *"Local Pi runtime: not inspected"* ]]
}

@test "release readiness rejects malformed invocation before inspection" {
    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" release readiness --json --json
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--json may be passed only once"* ]]

    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" release publish
    [[ "$status" -eq 64 ]]
    [[ "$output" == *"Unknown release command: publish"* ]]
}

@test "top-level help exposes the read-only release report" {
    run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"release     Report publication readiness; local verification is separate"* ]]
    [[ "$output" == *"Only Pi is in active product scope"* ]]
}

@test "bash and zsh completion expose only the bounded release report surface" {
    run bash -c '
      source "$1"
      COMP_WORDS=(mainframe release "")
      COMP_CWORD=2
      _mainframe_completions
      printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'help\nreadiness' ]]

    run bash -c '
      source "$1"
      COMP_WORDS=(mainframe release readiness --j)
      COMP_CWORD=3
      _mainframe_completions
      printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "--json" ]]

    if command -v zsh >/dev/null 2>&1; then
        run zsh -f -c '
          compdef() { :; }
          source "$1"
          _arguments() { printf "%s\n" "$@"; }
          words=(mainframe release readiness "")
          CURRENT=4
          _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *'--json[emit one machine-readable readiness object]'* ]]
    fi
}

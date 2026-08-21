#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    CERTIFIER="$PROJECT_ROOT/scripts/dev/certify-shell-onboarding.sh"
    SCHEMA="$PROJECT_ROOT/scripts/dev/shell-onboarding-evidence.schema.json"
    VALIDATOR="$PROJECT_ROOT/scripts/dev/native-host/validate-evidence.py"
    WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        shasum -a 256 "$file" | awk '{print $1}'
    fi
}

extract_decline_driver() {
    python3 - "$CERTIFIER" "$1" <<'PYEOF'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
begin = "# MAINFRAME_SHELL_ONBOARDING_PTY_DRIVER_BEGIN\n"
end = "# MAINFRAME_SHELL_ONBOARDING_PTY_DRIVER_END\n"
if source.count(begin) != 1 or source.count(end) != 1:
    raise SystemExit("interactive decline driver markers are not unique")
payload = source.split(begin, 1)[1].split(end, 1)[0]
Path(sys.argv[2]).write_text(payload, encoding="utf-8")
PYEOF
}

@test "shell onboarding certifier documents its proof boundary" {
    run "$BASH_BIN" -n "$CERTIFIER"
    [[ "$status" -eq 0 ]]

    run "$BASH_BIN" "$CERTIFIER" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"exact checksum-adjacent release archive"* ]]
    [[ "$output" == *"installed payload identity"* ]]
    [[ "$output" == *"explicit-consent"* ]]
    [[ "$output" == *"does not"*"native host"*"loaded"* ]]
    [[ "$output" == *"--output"*"path-free JSON certificate"* ]]
    [[ "$output" == *"codex, claude-code, copilot, gemini"* ]]
}

@test "interactive decline waits for the exact consent prompt before sending input" {
    local driver="$BATS_TEST_TMPDIR/decline-driver.py"
    local fake_shell="$BATS_TEST_TMPDIR/prompt-shell"
    extract_decline_driver "$driver"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'EOF'
printf '%s\n' 'zsh compinit: insecure directories, run compaudit for list.'
printf '%s' 'Ignore insecure directories and continue [y] or abort compinit [n]? '
IFS= read -r completion_answer || exit 84
printf '\nCOMPINIT_ANSWER=%s\n' "$completion_answer"
[[ "$completion_answer" == y ]] || exit 85
wrong_prompt='Apply these MAINFRAME-managed project changes and enable the gemini shell gate? [y/N] '
printf '%s' "$wrong_prompt"
if IFS= read -r -t 0.2 early_answer; then
    printf '\nEARLY_INPUT=%s\n' "$early_answer"
    exit 86
fi
printf '\nNEAR_MISS_IGNORED\n'
printf '%s' 'Apply these MAINFRAME-managed project changes and enable the codex shell '
/bin/sleep 0.05
printf '%s' 'gate? [y/N] '
IFS= read -r answer || exit 87
printf '\nANSWER=%s\n' "$answer"
[[ "$answer" == n ]] || exit 88
printf 'onboarding declined; no changes were made\n'
exit 2
EOF
    } > "$fake_shell"
    chmod 700 "$fake_shell"

    run env ONBOARD_HOST=codex \
        python3 "$driver" "$fake_shell" zsh ignored-command

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"COMPINIT_ANSWER=y"* ]]
    [[ "$output" == *"NEAR_MISS_IGNORED"* ]]
    [[ "$output" != *"EARLY_INPUT="* ]]
    [[ "$output" == *"ANSWER=n"* ]]
    [[ "$output" == *"onboarding declined; no changes were made"* ]]
}

@test "interactive decline refuses a child exit without the exact consent prompt" {
    local driver="$BATS_TEST_TMPDIR/decline-driver.py"
    local fake_shell="$BATS_TEST_TMPDIR/no-prompt-shell"
    extract_decline_driver "$driver"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'EOF'
printf 'startup completed without a consent prompt\n'
exit 2
EOF
    } > "$fake_shell"
    chmod 700 "$fake_shell"

    run env ONBOARD_HOST=codex \
        python3 "$driver" "$fake_shell" zsh ignored-command

    [[ "$status" -eq 125 ]]
    [[ "$output" == *"startup completed without a consent prompt"* ]]
    [[ "$output" == *"exact onboarding consent prompt was not observed"* ]]
}

@test "shell onboarding evidence schema is closed path-free and platform strict" {
    local evidence="$BATS_TEST_TMPDIR/shell-onboarding.json"
    jq -n '{
      schema_version: 1,
      certification: "shell-onboarding-certified",
      version: "10.2.0",
      archive_sha256: ("a" * 64),
      host: "codex",
      shell: "bash",
      os: "Darwin",
      arch: "arm64",
      system_libc: "none",
      installed_payload: "exact",
      runtime_load: "unverified",
      private_paths_embedded: false
    }' > "$evidence"

    run python3 "$VALIDATOR" "$SCHEMA" "$evidence"
    [[ "$status" -eq 0 ]]

    jq '.private_path = "/Users/private/project"' "$evidence" > "$evidence.extra"
    run python3 "$VALIDATOR" "$SCHEMA" "$evidence.extra"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unexpected keys"*"private_path"* ]]

    jq '.system_libc = "glibc"' "$evidence" > "$evidence.invalid-platform"
    run python3 "$VALIDATOR" "$SCHEMA" "$evidence.invalid-platform"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no anyOf alternative matched"* ]]
}

@test "shell onboarding evidence output refuses existing files and symlinks" {
    local output_dir="$BATS_TEST_TMPDIR/output-safety"
    local evidence="$output_dir/evidence.json"
    local target="$output_dir/target.json"
    mkdir -p "$output_dir"
    printf 'keep-me\n' > "$evidence"

    run "$BASH_BIN" "$CERTIFIER" codex \
        --archive "$output_dir/missing.tar.gz" --output "$evidence"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--output already exists"* ]]
    [[ "$(< "$evidence")" == "keep-me" ]]

    rm "$evidence"
    printf 'target\n' > "$target"
    ln -s "$target" "$evidence"
    run "$BASH_BIN" "$CERTIFIER" codex \
        --archive "$output_dir/missing.tar.gz" --output "$evidence"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--output already exists"* ]]
    [[ "$(< "$target")" == "target" ]]

    rm "$evidence"
    run "$BASH_BIN" "$CERTIFIER" codex \
        --archive "$output_dir/missing.tar.gz" --output "$evidence"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"archive is not a regular file"* ]]
    [[ ! -e "$evidence" && ! -L "$evidence" ]]
}

@test "direct shell onboarding refuses translated execution before optional dependencies" {
    local fixture_root="$BATS_TEST_TMPDIR/direct-shell-native-admission"
    local fixture_native="$fixture_root/scripts/dev/native-host"
    local minimal_bin="$fixture_root/minimal-bin"
    local version archive digest evidence tool target sha_tool
    mkdir -p "$fixture_native" "$minimal_bin" "$fixture_root/assets" "$fixture_root/dist"
    cp "$CERTIFIER" "$fixture_root/scripts/dev/certify-shell-onboarding.sh"
    cat > "$fixture_native/assert-runner-platform.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$#" -eq 1 && "$1" == --observe-native ]] || exit 64
printf 'Release runner is translated under Rosetta; native evidence is required\n' >&2
exit 73
EOF
    chmod 700 "$fixture_native/assert-runner-platform.sh"

    version="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    archive="$fixture_root/assets/mainframe-$version.tar.gz"
    evidence="$fixture_root/dist/shell-onboarding.json"
    : > "$archive"
    digest="$(sha256_file "$archive")"
    printf '%s  %s\n' "$digest" "$(basename "$archive")" > "$archive.sha256"

    ln -s "$BASH_BIN" "$minimal_bin/bash"
    for tool in dirname basename awk; do
        target="$(command -v "$tool")"
        [[ "$target" == /* ]]
        ln -s "$target" "$minimal_bin/$tool"
    done
    if command -v sha256sum >/dev/null 2>&1; then
        sha_tool="$(command -v sha256sum)"
    else
        sha_tool="$(command -v shasum)"
    fi
    ln -s "$sha_tool" "$minimal_bin/${sha_tool##*/}"

    run env \
        PATH="$minimal_bin" \
        BASH="$BASH_BIN" \
        MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$fixture_root/scripts/dev/certify-shell-onboarding.sh" codex \
        --archive "$archive" --shell bash --output "$evidence"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"translated under Rosetta"* ]]
    [[ "$output" != *"jq is required"* ]]
    [[ ! -e "$evidence" && ! -L "$evidence" ]]
}

@test "shell onboarding certifier covers installed identity consent privacy rollback and AWM" {
    for contract in \
        'candidate bootstrap differs from the certifier checkout' \
        'installed payload content differs from the exact archive' \
        'installed payload mode differs from the exact archive' \
        'release receipt does not exactly bind the installed archive' \
        'installed payload does not exactly match the archive plus its receipt' \
        'bash_login_profile="$home/.bash_profile"' \
        '# >>> MAINFRAME BASH LOGIN >>>' \
        'fresh_bash_nonlogin()' \
        '"$shell_bin" -ic "$command_text"' \
        'grep -Fxc "$EXPECTED_BIN"' \
        'mainframe invoke mf:std:pure-string:to_lower' \
        '--format broker-json-v1' \
        '.stdout_b64 == \"aGVsbG8gYWdlbnQK\"' \
        'broker contract failed in the fresh login shell' \
        'broker contract failed in an interactive non-login Bash shell' \
        'SOURCE_ROOT="$root"' \
        'onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --dry-run' \
        'unapproved onboarding changed the project' \
        'noninteractive onboarding without --yes did not exit 2' \
        'interactive decline did not exit 2' \
        'onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --yes' \
        'AWM project session:  RECORDED \([0-9a-f]{12}; non-authoritative\)' \
        'AWM project reads:    READY (durable control-plane; non-authoritative data)' \
        'repeat onboarding was not idempotent' \
        'mainframe protect status' \
        'Host runtime load:' \
        'gateway audit disclosed raw command text' \
        'state_home="$home/.local/state"' \
        'awm_root="$state_home/mainframe/.mainframe-control-plane-runtime/project-memory-adapter-state/awm"' \
        'chmod 700 "$home" "$home/.local" "$config_home" "$state_home"' \
        'certifier private runtime root is unsafe' \
        'dry-run changed AWM state' \
        'unapproved onboarding changed AWM state' \
        'declined onboarding changed AWM state' \
        'cd "$ONBOARD_NESTED"' \
        'mainframe awm project context --project . --discover-root "<current task>" --tokens 1200 --format prompt' \
        'If a required project-memory mutation or read route is unavailable, fail closed: stop and request human direction.' \
        'mainframe awm project ensure --project . --discover-root' \
        'mainframe awm project checkpoint --project . --discover-root' \
        'mainframe work "onboarding verification" --project . --tokens 1200 --format prompt' \
        'Context budget: ' \
        'AWM context exceeded its complete-document token budget' \
        'project AWM mapping disclosed the project path' \
        '.namespace == "projects" and .backend == "file"' \
        'AWM proof did not cross three fresh shell processes' \
        'deactivate "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --enforce --dry-run' \
        'rollback changed foreign project instructions' \
        'rollback changed foreign enforcement semantics'; do
        run grep -F -- "$contract" "$CERTIFIER"
        [[ "$status" -eq 0 ]]
    done

    run grep -F 'AWM_PROOF_SESSION' "$CERTIFIER"
    [[ "$status" -ne 0 ]]

    run grep -F -- '--noprofile --rcfile' "$CERTIFIER"
    [[ "$status" -ne 0 ]]

    run grep -Fc '"$shell_bin" -lic "$command_text"' "$CERTIFIER"
    [[ "$status" -eq 0 ]]
    [[ "$output" -ge 2 ]]
}

@test "shell onboarding certifier isolates file transport and strictly verifies its receipt" {
    run grep -Fc 'MAINFRAME_INTERNAL_TESTING=1' "$CERTIFIER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1" ]]

    for contract in \
        'MAINFRAME_RELEASE_BASE_URL="file://$release_root"' \
        'bootstrap_fixture_marker="$home/.mainframe-bootstrap-internal-test-mode"' \
        'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' \
        'chmod 600 "$bootstrap_fixture_marker"' \
        '--internal-test-fixture' \
        '--release-version "$version"' \
        'receipt_name=.mainframe-install-receipt.json' \
        'release receipt mode is not 600' \
        'keys == ["archive_sha256", "bin_dir", "cli_link", "install_dir",' \
        '.install_method == "release-archive"' \
        '.archive_sha256 == $archive_sha256' \
        '.manifest_sha256 == $manifest_sha256' \
        '.install_dir == $install_dir' \
        '.bin_dir == $bin_dir' \
        '.cli_link == $cli_link' \
        'expected_file_names = set(expected_files) | {receipt_name}'; do
        run grep -F -- "$contract" "$CERTIFIER"
        [[ "$status" -eq 0 ]]
    done
}

@test "real current release archive completes exact shell onboarding certification when available" {
    local version archive evidence expected_sha
    version="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    archive="$PROJECT_ROOT/dist/mainframe-${version}.tar.gz"
    evidence="$BATS_TEST_TMPDIR/real-current-shell-onboarding.json"

    [[ -f "$archive" && ! -L "$archive" && -f "$archive.sha256" ]] || \
        skip "canonical current release archive is not built"
    "$BASH_BIN" -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1 || skip "Bash 4.4+ is required"
    for required in curl jq python3 tar; do
        command -v "$required" >/dev/null 2>&1 || skip "$required is required"
    done

    expected_sha="$(sha256_file "$archive")"
    run env MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$CERTIFIER" codex \
        --archive "$archive" --shell bash --output "$evidence"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"shell-onboarding-certified"* ]]
    python3 "$VALIDATOR" "$SCHEMA" "$evidence"
    jq -e \
        --arg version "$version" \
        --arg archive_sha256 "$expected_sha" '
          .certification == "shell-onboarding-certified" and
          .version == $version and
          .archive_sha256 == $archive_sha256 and
          .host == "codex" and .shell == "bash" and
          .installed_payload == "exact" and
          .runtime_load == "unverified"
        ' "$evidence" >/dev/null
}

@test "shell onboarding certifier rejects non-canonical and multi-record checksums" {
    local test_dir archive asset digest
    test_dir="$BATS_TEST_TMPDIR/checksum-contract"
    mkdir -p "$test_dir"
    asset="mainframe-$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION").tar.gz"
    archive="$test_dir/$asset"
    : > "$archive"
    digest="$(sha256_file "$archive")"

    printf '%s %s\n' "$digest" "$asset" > "$archive.sha256"
    run "$BASH_BIN" "$CERTIFIER" codex --archive "$archive" --shell bash
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"checksum must be the canonical"* ]]

    printf '%s  %s\n%s  %s\n' "$digest" "$asset" "$digest" "$asset" \
        > "$archive.sha256"
    run "$BASH_BIN" "$CERTIFIER" codex --archive "$archive" --shell bash
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"checksum must contain exactly one record"* ]]
}

@test "shell onboarding certifier validates a narrow physical cleanup target" {
    run grep -F 'tmp_parent="$(cd -- "$tmp_parent" && pwd -P)"' "$CERTIFIER"
    [[ "$status" -eq 0 ]]
    run grep -F '"$cleanup_name" == mainframe-shell-onboard.*' "$CERTIFIER"
    [[ "$status" -eq 0 ]]
    run grep -F 'shell-onboarding certification refused unsafe cleanup target' "$CERTIFIER"
    [[ "$status" -eq 0 ]]
}

@test "release workflow gates on all twenty-four advertised platform shell-host lanes" {
    local lane release_lane
    lane="$(sed -n '/^  shell-onboarding:/,/^  test-bindings:/p' "$WORKFLOW")"
    release_lane="$(sed -n '/^  release-build:/,/^  release-publish:/p' "$WORKFLOW")"

    [[ "$lane" == *'runs-on: ${{ matrix.target.runner }}'* ]]
    [[ "$lane" == *'runner: macos-15'* ]]
    [[ "$lane" == *'runner: macos-15-intel'* ]]
    [[ "$lane" == *'runner: ubuntu-24.04'* ]]
    [[ "$lane" == *'id: Darwin-arm64-none'* ]]
    [[ "$lane" == *'id: Darwin-x86_64-none'* ]]
    [[ "$lane" == *'id: Linux-x86_64-glibc'* ]]
    [[ "$lane" != *'ubuntu-latest'* ]]
    [[ "$lane" != *'macos-latest'* ]]
    [[ "$lane" == *'host: [codex, claude-code, copilot, gemini]'* ]]
    [[ "$lane" == *'shell: [bash, zsh]'* ]]
    [[ "$lane" == *'sudo apt-get install -y jq zsh'* ]]
    [[ "$lane" == *'scripts/dev/native-host/assert-runner-platform.sh'* ]]
    [[ "$lane" == *'proof_source="$(mktemp -d "${RUNNER_TEMP}/mainframe-shell-onboarding-source.XXXXXX")"'* ]]
    [[ "$lane" == *'tar -xzf "$archive" -C "$proof_source"'* ]]
    [[ "$lane" == *'"$MAINFRAME_BASH" "$proof_source/scripts/dev/certify-shell-onboarding.sh"'* ]]
    [[ "$lane" == *'python3 "$proof_source/scripts/dev/native-host/validate-evidence.py"'* ]]
    [[ "$lane" == *'--shell "${{ matrix.shell }}"'* ]]
    [[ "$lane" == *'--output "$EVIDENCE_PATH"'* ]]
    [[ "$lane" == *'shell-onboarding-evidence/${{ matrix.host }}-${{ matrix.target.id }}-${{ matrix.shell }}.json'* ]]
    [[ "$lane" == *'Upload shell-onboarding evidence'* ]]
    [[ "$lane" == *'scripts/dev/certify-shell-onboarding.sh'* ]]
    [[ "$release_lane" == *'shell-onboarding'* ]]
    [[ "$release_lane" == *'Download shell-onboarding evidence'* ]]
    [[ "$release_lane" == *'test "${#shell_onboarding_evidence[@]}" -eq 24'* ]]
    [[ "$release_lane" == *'.archive_sha256 == $archive_sha'* ]]
    [[ "$release_lane" != *'release_evidence_inputs+=(--shell'* ]]
}

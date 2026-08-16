#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    PROJECT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"

    if ! "$BASH_BIN" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))'; then
        skip "Bash 4.4+ is required"
    fi
    command -v jq >/dev/null || skip "jq is required for mainframe doctor"

    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-release-archive.XXXXXX")"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    RELEASE_SOURCE="$TEST_DIR/source"
    EXTRACTED_DIR="$TEST_DIR/extracted"
    TAMPERED_DIR="$TEST_DIR/tampered"
    MISSING_DIR="$TEST_DIR/missing"
    TEST_HOME="$TEST_DIR/home"
    TEST_BIN="$TEST_HOME/.local/bin"
    FAKE_BIN="$TEST_DIR/fake-bin"
    GIT_MARKER="$TEST_DIR/git-was-called"
    TAMPER_EXEC_MARKER="$TEST_DIR/tampered-payload-executed"
    TEST_PATH="$FAKE_BIN:$(dirname "$BASH_BIN"):$TEST_BIN:$PATH"

    mkdir -p "$RELEASE_SOURCE" "$EXTRACTED_DIR" "$TEST_HOME" "$FAKE_BIN"
    # Expand the marker path when the generated stub runs, not while writing it.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "git called\n" > "${MAINFRAME_TEST_GIT_MARKER:?}"' \
        'exit 97' > "$FAKE_BIN/git"
    chmod +x "$FAKE_BIN/git"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

sha256_file() {
    local file="$1"

    if command -v sha256sum >/dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

checksum_matches() {
    local archive="$1"
    local checksum="$2"
    local expected actual

    expected="$(awk 'NF && $1 !~ /^#/ { print $1; exit }' "$checksum")"
    actual="$(sha256_file "$archive")"
    [[ -n "$expected" && "$actual" == "$expected" ]]
}

mutate_sbom_runtime_contract() {
    local input="$1"
    local output="$2"
    local reference="$3"
    local field="$4"
    local replacement="$5"

    python3 - "$input" "$output" "$reference" "$field" "$replacement" <<'PYEOF'
import copy
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
reference, field, replacement = sys.argv[3:]
document = json.loads(source.read_text(encoding="utf-8"))
components = document["components"]
component = next(item for item in components if item.get("bom-ref") == reference)

if field == "duplicate":
    components.append(copy.deepcopy(component))
elif field.startswith("property:"):
    property_name = field.removeprefix("property:")
    sbom_property = next(
        item for item in component["properties"] if item.get("name") == property_name
    )
    sbom_property["value"] = replacement
else:
    component[field] = replacement

target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PYEOF
}

create_release_source() {
    local path payload_list="$TEST_DIR/release-payload-files.txt"

    # Copy the canonical file inventory instead of whole roots. Developer
    # checkouts may contain large ignored artifacts (notably native-host
    # node_modules) that the release inventory intentionally excludes.
    # Keeping this fixture byte-scoped makes it representative of a clean
    # checkout and avoids multi-minute copies of non-release data.
    # shellcheck source=scripts/dev/release-payload.sh
    source "$PROJECT_ROOT/scripts/dev/release-payload.sh"
    mainframe_release_payload_files "$PROJECT_ROOT" > "$payload_list" || return 1
    while IFS= read -r path; do
        mkdir -p "$RELEASE_SOURCE/$(dirname "$path")"
        cp -p "$PROJECT_ROOT/$path" "$RELEASE_SOURCE/$path"
    done < "$payload_list"

    # One assertion proves an adjacent repository-only tree is excluded from
    # the archive; the demo contents themselves are not release inputs.
    mkdir -p "$RELEASE_SOURCE/demos"
    printf 'repository-only fixture\n' > "$RELEASE_SOURCE/demos/not-shipped.txt"

    # These sentinels exercise the narrower agent-impact release boundary.
    # Public conformance inputs ship, while adjacent evals, test fixtures,
    # private assignment material, and raw run artifacts remain repository-only.
    mkdir -p \
        "$RELEASE_SOURCE/evals/agent-impact/private" \
        "$RELEASE_SOURCE/evals/agent-impact/runs" \
        "$RELEASE_SOURCE/tests"
    printf 'repository-only eval\n' > "$RELEASE_SOURCE/evals/not-shipped.txt"
    printf 'held-out assignment\n' \
        > "$RELEASE_SOURCE/evals/agent-impact/private/held-out.json"
    printf 'raw run\n' > "$RELEASE_SOURCE/evals/agent-impact/runs/not-shipped.json"
    printf 'test fixture\n' > "$RELEASE_SOURCE/tests/not-shipped.txt"
}

@test "release preflight verifies every canonical generated surface" {
    local release_script="$PROJECT_ROOT/scripts/dev/release.sh"

    run "$BASH_BIN" -n "$release_script"
    [[ "$status" -eq 0 ]]
    grep -F 'scripts/sync-version.sh" --check' "$release_script" >/dev/null
    grep -F 'scripts/generate-manifest.py" --verify' "$release_script" >/dev/null
    grep -F 'scripts/check-owner-parity.py"' "$release_script" >/dev/null
    grep -F 'scripts/export-gate-rules.py" --check' "$release_script" >/dev/null
}

@test "release archive is identical across source trees with different mtimes" {
    create_release_source

    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]
    local archive="$RELEASE_SOURCE/dist/mainframe-${PROJECT_VERSION}.tar.gz"
    local first_digest
    first_digest="$(sha256_file "$archive")"

    # Reproducibility must survive a fresh checkout whose file mtimes differ.
    find "$RELEASE_SOURCE" -type f ! -path "$RELEASE_SOURCE/dist/*" \
        -exec touch -t 202001020304.05 {} +
    rm -rf -- "$RELEASE_SOURCE/dist"

    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(sha256_file "$archive")" == "$first_digest" ]]
}

@test "release archive builder stages normal outputs in an explicit safe directory" {
    local output_dir="$TEST_DIR/candidate-output"
    local linked_output="$TEST_DIR/linked-candidate-output"
    local archive

    create_release_source
    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh" \
        --output-dir "$output_dir"

    [[ "$status" -eq 0 ]]
    archive="$output_dir/mainframe-${PROJECT_VERSION}.tar.gz"
    [[ -f "$archive" ]]
    [[ -f "${archive}.sha256" ]]
    [[ -f "$output_dir/mainframe-${PROJECT_VERSION}.sbom.json" ]]
    [[ ! -e "$RELEASE_SOURCE/dist" ]]
    checksum_matches "$archive" "${archive}.sha256"

    ln -s "$output_dir" "$linked_output"
    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh" \
        --output-dir "$linked_output"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output directory must be absent or a non-symlink directory"* ]]
}

@test "extracted release archive runs shipped agent-impact fixture conformance" {
    create_release_source

    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]

    local archive="$RELEASE_SOURCE/dist/mainframe-${PROJECT_VERSION}.tar.gz"
    local archive_manifest="$TEST_DIR/agent-impact-archive.manifest"
    local conformance_root="$TEST_DIR/extracted-agent-impact"
    tar -tzf "$archive" > "$archive_manifest"

    grep -Fxq 'scripts/dev/agent-impact.py' "$archive_manifest"
    grep -Fxq 'scripts/dev/agent-impact-preregister.py' "$archive_manifest"
    grep -Fxq 'scripts/dev/agent-impact-runtime-preflight.py' "$archive_manifest"
    grep -Fxq 'scripts/dev/certify-installed-awm-handoff.py' "$archive_manifest"
    grep -Fxq 'scripts/dev/run-agent-impact-awm-fixture.py' "$archive_manifest"
    grep -Fxq 'scripts/dev/agent-impact-awm-receipt.py' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/live-study.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/preregistration.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/pi-ollama-preflight-spec.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/pi-ollama-preflight-receipt.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/pi-ollama-arm-contract.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/pi-ollama-adapter-request.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/pi-ollama-adapter-result.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/installed-awm-handoff-private.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/installed-awm-handoff-evidence.schema.json' \
        "$archive_manifest"
    grep -Fxq 'evals/agent-impact/awm-transition-raw.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/awm-transition-receipt.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/awm-transition-public.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/neutral-continuation.schema.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/suites/conformance-v1.json' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/runners/fake-runner.py' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/runners/pi-awm-transition-driver.mjs' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/runners/pi-ollama-adapter.py' "$archive_manifest"
    grep -Fxq 'evals/agent-impact/runners/pi-ollama-adapter.manifest.json' \
        "$archive_manifest"
    grep -Fxq 'docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md' "$archive_manifest"
    run grep -Eq '^evals/(not-shipped\.txt|agent-impact/(private|runs)(/|$))' \
        "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Eq '^tests(/|$)' "$archive_manifest"
    [[ "$status" -ne 0 ]]

    tar -xzf "$archive" -C "$EXTRACTED_DIR"
    mkdir -p "$conformance_root"
    local harness="$EXTRACTED_DIR/scripts/dev/agent-impact.py"
    local preregister="$EXTRACTED_DIR/scripts/dev/agent-impact-preregister.py"
    local runtime_preflight="$EXTRACTED_DIR/scripts/dev/agent-impact-runtime-preflight.py"
    local installed_handoff="$EXTRACTED_DIR/scripts/dev/certify-installed-awm-handoff.py"
    local awm_fixture="$EXTRACTED_DIR/scripts/dev/run-agent-impact-awm-fixture.py"
    local awm_receipt="$EXTRACTED_DIR/scripts/dev/agent-impact-awm-receipt.py"
    local awm_driver="$EXTRACTED_DIR/evals/agent-impact/runners/pi-awm-transition-driver.mjs"
    local runner="$EXTRACTED_DIR/evals/agent-impact/runners/fake-runner.py"
    local nested_python nested_jq nested_tmp nested_path

    [[ -x "$harness" ]]
    [[ -x "$preregister" ]]
    [[ -x "$runtime_preflight" ]]
    [[ -x "$installed_handoff" ]]
    [[ -x "$awm_fixture" ]]
    [[ -x "$awm_receipt" ]]
    [[ -x "$awm_driver" ]]
    [[ -x "$runner" ]]
    run python3 "$preregister" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'{prepare,verify}'* ]]
    [[ "$output" != *'{prepare,verify,run}'* ]]
    run python3 -I -S -B "$runtime_preflight" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'{prepare,verify}'* ]]
    [[ "$output" != *'{prepare,verify,run}'* ]]
    [[ "$output" != *'--run'* ]]
    [[ "$output" != *'--probe'* ]]
    [[ "$output" != *'--list'* ]]
    [[ "$output" != *'--start'* ]]
    [[ "$output" != *'--pull'* ]]
    run python3 -I -S -B "$runtime_preflight" prepare --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--spec'* ]]
    [[ "$output" == *'--arm-contract'* ]]
    [[ "$output" == *'--output'* ]]
    run python3 -I -S -B "$runtime_preflight" verify --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--spec'* ]]
    [[ "$output" == *'--arm-contract'* ]]
    [[ "$output" == *'--receipt'* ]]
    local forbidden_action
    for forbidden_action in run probe list start pull; do
        run python3 -I -S -B "$runtime_preflight" "$forbidden_action"
        [[ "$status" -eq 2 ]]
    done
    run python3 -I -S -B "$installed_handoff" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'{run,verify}'* ]]
    run python3 -I -S -B "$installed_handoff" run --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--archive'* ]]
    [[ "$output" == *'--checksum'* ]]
    [[ "$output" == *'--shell'* ]]
    [[ "$output" == *'--private-output'* ]]
    [[ "$output" == *'--output'* ]]
    run python3 -I -S -B "$installed_handoff" verify --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--archive'* ]]
    [[ "$output" == *'--checksum'* ]]
    [[ "$output" == *'--shell'* ]]
    [[ "$output" == *'--private-evidence'* ]]
    [[ "$output" == *'--evidence'* ]]
    nested_python="$(command -v python3)"
    nested_jq="$(command -v jq)"
    nested_tmp="$TEST_DIR/extracted-preflight-tmp"
    nested_path="$(dirname "$BASH_BIN"):$(dirname "$nested_python"):$(dirname "$nested_jq"):/usr/bin:/bin:/usr/sbin:/sbin"
    mkdir -p "$nested_tmp"
    chmod 700 "$nested_tmp"
    run env -i \
        HOME="$TEST_HOME" \
        TMPDIR="$nested_tmp" \
        LC_ALL=C \
        PATH="$nested_path" \
        PYTHON_BIN="$nested_python" \
        MAINFRAME_TEST_PREFLIGHT_PROJECT_ROOT="$EXTRACTED_DIR" \
        BATS_TEST_SHELL="$BASH_BIN" \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/tests/bats/bin/bats" \
        --formatter tap \
        --print-output-on-failure \
        --filter '^happy prepare and verify bind the complete offline runtime without invoking it$' \
        "$PROJECT_ROOT/tests/agent_impact_runtime_preflight.bats"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ok 1 happy prepare and verify bind the complete offline runtime without invoking it"* ]]
    run python3 "$awm_fixture" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--opaque-arm-id'* ]]
    run python3 "$awm_receipt" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'{prepare,verify}'* ]]
    run python3 "$harness" prepare \
        --seed shipped-conformance \
        --replicates 1 \
        --output "$conformance_root/plan.json" \
        --assignments-output "$conformance_root/assignments.json"
    [[ "$status" -eq 0 ]]

    run python3 "$harness" run --fixture \
        --plan "$conformance_root/plan.json" \
        --assignments "$conformance_root/assignments.json" \
        --runner "$runner" \
        --output-dir "$conformance_root/run" \
        --evidence "$conformance_root/evidence.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"fixture protocol run complete: 1 pair(s)"* ]]

    run python3 "$harness" verify \
        --plan "$conformance_root/plan.json" \
        --assignments "$conformance_root/assignments.json" \
        --runner "$runner" \
        --output-dir "$conformance_root/run" \
        --evidence "$conformance_root/evidence.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent impact not measured"* ]]
}

@test "release metadata fails closed on a missing root or symbolic-link payload" {
    create_release_source

    mv "$RELEASE_SOURCE/docs" "$RELEASE_SOURCE/docs.missing"
    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/generate-sbom.sh" \
        --output-dir "$TEST_DIR/missing-metadata"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"required release payload is missing: docs"* ]]

    mv "$RELEASE_SOURCE/docs.missing" "$RELEASE_SOURCE/docs"
    mv "$RELEASE_SOURCE/README.md" "$RELEASE_SOURCE/README.real"
    ln -s README.real "$RELEASE_SOURCE/README.md"
    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/generate-sbom.sh" \
        --output-dir "$TEST_DIR/symlink-metadata"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release payload must not contain symbolic links"* ]]
}

@test "release archive fails closed when inventory generation fails after output" {
    create_release_source
    cat >> "$RELEASE_SOURCE/scripts/dev/release-payload.sh" <<'BASH'

# Regression fixture: a process-substitution consumer would accept VERSION and
# hide this producer failure, yielding a partial archive.
mainframe_release_payload_files() {
    printf '%s\n' VERSION
    return 73
}
BASH

    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release payload inventory failed"* ]]
    [[ ! -e "$RELEASE_SOURCE/dist/mainframe-${PROJECT_VERSION}.tar.gz" ]]
}

@test "release SBOM is deterministic and compatible with attestation" {
    create_release_source
    local first="$TEST_DIR/sbom-first"
    local second="$TEST_DIR/sbom-second"
    mkdir -p "$first" "$second"

    run env SOURCE_DATE_EPOCH=0 \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/generate-sbom.sh" --output-dir "$first"
    [[ "$status" -eq 0 ]]
    run python3 "$RELEASE_SOURCE/scripts/dev/validate-release-sbom.py" \
        "$first/sbom.json" "$PROJECT_VERSION"
    [[ "$status" -eq 0 ]]

    run env SOURCE_DATE_EPOCH=0 \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/generate-sbom.sh" --output-dir "$second"
    [[ "$status" -eq 0 ]]
    cmp -s "$first/sbom.json" "$second/sbom.json"
    jq -e '
        .bomFormat == "CycloneDX" and
        .specVersion == "1.5" and
        (.serialNumber | test("^urn:uuid:[0-9a-f-]{36}$"))
    ' "$first/sbom.json" >/dev/null
}

@test "release SBOM validator rejects runtime contract drift" {
    create_release_source
    local valid_dir="$TEST_DIR/sbom-runtime-contract"
    local valid_sbom="$valid_dir/sbom.json"
    local invalid_sbom="$TEST_DIR/invalid-runtime-sbom.json"
    local case_spec reference field replacement expected
    mkdir -p "$valid_dir"

    run env SOURCE_DATE_EPOCH=0 \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/generate-sbom.sh" \
        --output-dir "$valid_dir"
    [[ "$status" -eq 0 ]]

    local cases=(
        "runtime:bash|version|4.3|runtime:bash version must be '4.4'"
        "runtime:bash|property:mainframe:version-constraint|>=4.0|runtime:bash property 'mainframe:version-constraint' must be '>=4.4'"
        "runtime:python|version|3.11|runtime:python version must be '3.9'"
        "runtime:python|property:mainframe:version-constraint|>=3.10|runtime:python property 'mainframe:version-constraint' must be '>=3.9 for Pi diagnosis and lifecycle'"
        "runtime:python|property:mainframe:managed-host-version-constraint|>=3.11|runtime:python property 'mainframe:managed-host-version-constraint' must be '>=3.10'"
        "runtime:python|property:mainframe:requirement|required only for managed-host install and remove|runtime:python property 'mainframe:requirement' must be 'Pi diagnosis/lifecycle and managed-host install, remove, and restore'"
        "runtime:jq|property:mainframe:requirement|optional|runtime:jq property 'mainframe:requirement' must be 'required for agent enforcement and full metadata support'"
        "runtime:bash|duplicate|unused|exactly one runtime:bash component is required"
    )

    for case_spec in "${cases[@]}"; do
        IFS='|' read -r reference field replacement expected <<< "$case_spec"
        mutate_sbom_runtime_contract \
            "$valid_sbom" "$invalid_sbom" "$reference" "$field" "$replacement"

        run python3 "$RELEASE_SOURCE/scripts/dev/validate-release-sbom.py" \
            "$invalid_sbom" "$PROJECT_VERSION"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"$expected"* ]]
    done
}

install_from_extracted_tree() {
    local install_dir="$1"
    local home_dir="$2"
    local bin_dir="$3"

    env \
        HOME="$home_dir" \
        XDG_CONFIG_HOME="$home_dir/.config" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_DIR" \
        PATH="$TEST_PATH" \
        MAINFRAME_TEST_GIT_MARKER="$GIT_MARKER" \
        MAINFRAME_TAMPER_EXEC_MARKER="$TAMPER_EXEC_MARKER" \
        MAINFRAME_REPO=https://network-access.invalid/mainframe.git \
        MAINFRAME_INSTALL_DIR="$install_dir" \
        MAINFRAME_BIN_DIR="$bin_dir" \
        "$BASH_BIN" --noprofile --norc -p "$install_dir/install.sh" \
            --no-shell --no-claude --no-ai-discovery
}

hook_command_from_tree() {
    local tree="$1"
    local host="$2"

    env -i HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_ROOT="$tree" \
        "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1/lib/activate.sh"; _mainframe_enforce_command_for "$2"' \
        _ "$tree" "$host"
}

@test "release archive installs offline and detects archive or payload tampering" {
    create_release_source

    run "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]

    local archive="$RELEASE_SOURCE/dist/mainframe-${PROJECT_VERSION}.tar.gz"
    local archive_checksum="${archive}.sha256"
    local archive_manifest="$TEST_DIR/archive.manifest"
    [[ -f "$archive" ]]
    [[ -f "$archive_checksum" ]]
    [[ -f "$RELEASE_SOURCE/dist/mainframe-${PROJECT_VERSION}.sbom.json" ]]
    checksum_matches "$archive" "$archive_checksum"

    tar -tzf "$archive" > "$archive_manifest"
    local required
    for required in \
        mainframe package.json bin/mainframe scripts/data/json-to-csv \
        lib/onboard.sh lib/host_runtime.sh lib/host_lifecycle.sh lib/pi.sh \
        config/pi-compatibility.json \
        security/gate-rules.json security/gate-normalizer.mjs \
        skills/pi/SKILL.md skills/pi/extensions/mainframe.ts \
        completions/mainframe.bash completions/mainframe.zsh \
        hooks/dispatcher.sh hooks/agent-gateway.sh \
        scripts/dev/certify-shell-onboarding.sh \
        scripts/dev/shell-onboarding-evidence.schema.json \
        scripts/dev/certify-installed-awm-handoff.py \
        evals/agent-impact/installed-awm-handoff-private.schema.json \
        evals/agent-impact/installed-awm-handoff-evidence.schema.json \
        scripts/dev/certify-native-host.sh \
        scripts/dev/native-host/certify-claude.sh \
        scripts/dev/native-host/certify-codex.sh \
        scripts/dev/native-host/certify-copilot.sh \
        scripts/dev/native-host/package-lock.json \
        scripts/dev/native-host/hosts.json \
        scripts/dev/native-host/evidence.schema.json \
        scripts/dev/native-host/claude-evidence.schema.json \
        scripts/dev/native-host/codex-evidence.schema.json \
        scripts/dev/native-host/copilot-evidence.schema.json \
        scripts/dev/native-host/claude-messages-server.py \
        scripts/dev/native-host/codex-responses-server.py \
        scripts/dev/native-host/copilot-chat-completions-server.py \
        scripts/dev/native-host/hash-package-tree.mjs \
        scripts/dev/native-host/hash-package-tree.py \
        scripts/dev/native-host/acquire-managed-package.py \
        scripts/dev/native-host/extract-managed-package.py \
        scripts/dev/native-host/managed-host-fs.py \
        scripts/dev/native-host/safe-extract.py \
        scripts/dev/native-host/validate-evidence.py \
        scripts/dev/native-host/validate-native-executable.py \
        scripts/dev/native-host/build-release-evidence.py \
        scripts/dev/native-host/certifier-inputs.json \
        scripts/dev/native-host/release-evidence.schema.json \
        scripts/dev/native-host/fixtures/claude-destroy.messages.json \
        scripts/dev/native-host/fixtures/codex-destroy.responses.json \
        scripts/dev/native-host/fixtures/copilot-destroy.chat-completions.json \
        scripts/dev/native-host/fixtures/gemini-destroy.responses.jsonl \
        packaging/homebrew/Formula/mainframe.rb.in \
        install.sh uninstall.sh scripts/upgrade-release.sh SHA256SUMS sbom.json \
        README.md INSTALL.md SECURITY.md LICENSE \
        docs/AGENT_GATEWAY.md docs/MANAGED_HOST_PAYLOADS.md \
        docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md \
        docs/ONBOARDING.md docs/reference/README.md; do
        grep -Fxq "$required" "$archive_manifest"
    done
    run grep -Eq '(^|/)demos(/|$)' "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Eq '^docs/research(/|$)' "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Fxq 'docs/MAINFRAME_Technical_Report.md' "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Fxq 'docs/VALUE_PROOF.md' "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Eq '(^|/)node_modules(/|$)' "$archive_manifest"
    [[ "$status" -ne 0 ]]
    run grep -Eq '(^|/)__pycache__(/|$)|\.py[co]$' "$archive_manifest"
    [[ "$status" -ne 0 ]]

    tar -xzf "$archive" -C "$EXTRACTED_DIR"
    cp -R "$EXTRACTED_DIR" "$TAMPERED_DIR"
    cp -R "$EXTRACTED_DIR" "$MISSING_DIR"

    run install_from_extracted_tree "$EXTRACTED_DIR" "$TEST_HOME" "$TEST_BIN"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Checksums verified"* ]]
    [[ ! -e "$GIT_MARKER" ]]

    # The archive install intentionally skips live shell mutation. Prepare the
    # disposable HOME explicitly before asking doctor for a fully ready shell
    # identity, and keep any ambient installed Mainframe out of selection.
    local installed_path="$TEST_BIN:$(dirname "$BASH_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
    run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
        PATH="$installed_path" MAINFRAME_ROOT="$EXTRACTED_DIR" \
        "$TEST_BIN/mainframe" shell repair --shell all --yes
    [[ "$status" -eq 0 ]]

    run env HOME="$TEST_HOME" PATH="$installed_path" \
        MAINFRAME_ROOT="$EXTRACTED_DIR" "$TEST_BIN/mainframe" version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v${PROJECT_VERSION}"* ]]
    [[ "$output" == *"MAINFRAME_ROOT:  $EXTRACTED_DIR"* ]]

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        "$TEST_BIN/mainframe" host restore --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host restore HOST --quarantine-id"* ]]
    [[ "$output" == *"strictly offline"* ]]

    run env HOME="$TEST_HOME" PATH="$installed_path" \
        MAINFRAME_ROOT="$EXTRACTED_DIR" "$TEST_BIN/mainframe" doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Status: All checks passed!"* ]]

    local proof_project="$TEST_DIR/installed-proof"
    local proof_gateway_audit="$TEST_DIR/proof-gateway.jsonl"
    local proof_invoke_audit="$TEST_DIR/proof-invocations.jsonl"
    local proof_xdg_state="$TEST_DIR/proof-xdg-state"
    local proof_xdg_config="$TEST_DIR/proof-xdg-config"
    local proof_home_before proof_home_after
    mkdir -p "$proof_project"
    proof_home_before="$(find "$TEST_HOME" -mindepth 1 -print | LC_ALL=C sort)"
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        XDG_STATE_HOME="$proof_xdg_state" \
        XDG_CONFIG_HOME="$proof_xdg_config" \
        MAINFRAME_PI_AGENT_DIR="$TEST_HOME/.pi/agent" \
        MAINFRAME_AGENT_AUDIT_LOG="$proof_gateway_audit" \
        MAINFRAME_INVOKE_AUDIT_LOG="$proof_invoke_audit" \
        "$TEST_BIN/mainframe" setup --project "$proof_project" --proof
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Install health:     PASS"* ]]
    [[ "$output" == *"Reviewed invocation: PASS"*"output=hello agent"* ]]
    [[ "$output" == *"Shell policy:       PASS"*"canary not executed"* ]]
    [[ "$output" == *"Next safe command:"* ]]
    [[ "$output" == *"Live host protection: UNVERIFIED"* ]]
    [[ ! -e "$proof_gateway_audit" ]]
    [[ ! -e "$proof_invoke_audit" ]]
    [[ ! -e "$proof_xdg_state" ]]
    [[ ! -e "$proof_xdg_config" ]]
    [[ -z "$(find "$proof_project" -mindepth 1 -print -quit)" ]]
    proof_home_after="$(find "$TEST_HOME" -mindepth 1 -print | LC_ALL=C sort)"
    [[ "$proof_home_after" == "$proof_home_before" ]]

    local onboarded_project="$TEST_DIR/installed-onboarding"
    local onboard_audit="$TEST_DIR/installed-onboarding-audit.jsonl"
    mkdir -p "$onboarded_project"
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$onboard_audit" \
        "$TEST_BIN/mainframe" onboard --host codex \
        --project "$onboarded_project" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run complete"* ]]
    [[ ! -e "$onboarded_project/AGENTS.md" ]]
    [[ ! -e "$onboard_audit" ]]

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$onboard_audit" \
        "$TEST_BIN/mainframe" onboard --host codex \
        --project "$onboarded_project"
    [[ "$status" -eq 2 ]]
    [[ ! -e "$onboarded_project/AGENTS.md" ]]
    [[ ! -e "$onboard_audit" ]]

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$onboard_audit" \
        "$TEST_BIN/mainframe" onboard --host codex \
        --project "$onboarded_project" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Project configuration: READY"* ]]
    [[ "$output" == *"Host runtime load:     UNVERIFIED"* ]]
    [[ -f "$onboarded_project/AGENTS.md" ]]
    [[ -f "$onboarded_project/.codex/hooks.json" ]]
    [[ -f "$onboard_audit" ]]

    local activated_project="$TEST_DIR/installed-activation"
    mkdir -p "$activated_project"
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        "$TEST_BIN/mainframe" activate all \
        --project "$activated_project" --enforce
    [[ "$status" -eq 0 ]]
    local codex_hook claude_hook copilot_hook gemini_hook
    codex_hook="$(hook_command_from_tree "$EXTRACTED_DIR" codex)"
    claude_hook="$(hook_command_from_tree "$EXTRACTED_DIR" claude-code)"
    copilot_hook="$(hook_command_from_tree "$EXTRACTED_DIR" copilot)"
    gemini_hook="$(hook_command_from_tree "$EXTRACTED_DIR" gemini)"
    [[ -n "$codex_hook" && -n "$claude_hook" && -n "$copilot_hook" && -n "$gemini_hook" ]]
    jq -e --arg command "$codex_hook" '
        [.hooks.PreToolUse[]
          | select(.matcher == "Bash")
          | .hooks[]
          | select(.command == $command)
        ] | length == 1
    ' "$activated_project/.codex/hooks.json" >/dev/null
    jq -e --arg command "$claude_hook" '
        [.hooks.PreToolUse[]
          | select(.matcher == "Bash")
          | .hooks[]
          | select(.command == $command)
        ] | length == 1
    ' "$activated_project/.claude/settings.json" >/dev/null
    jq -e --arg command "$copilot_hook" '
        [.hooks.preToolUse[]
          | select(.matcher == "bash")
          | select(.bash == $command)
        ] | length == 1
    ' "$activated_project/.github/hooks/mainframe.json" >/dev/null
    jq -e --arg command "$gemini_hook" '
        [.hooks.BeforeTool[]
          | select(.matcher == "run_shell_command")
          | .hooks[]
          | select(.command == $command)
        ] | length == 1
    ' "$activated_project/.gemini/settings.json" >/dev/null

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        "$TEST_BIN/mainframe" protect status --project "$activated_project"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Static readiness: READY"* ]]
    [[ "$output" == *"Runtime load: UNVERIFIED"* ]]

    local gateway_payload gateway_audit="$TEST_DIR/installed-gateway.jsonl"
    gateway_payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"terraform destroy -auto-approve"}}'
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$gateway_audit" \
        bash --noprofile --norc -c \
        'printf "%s" "$1" | "$2" agent-hook --format claude' \
        _ "$gateway_payload" "$TEST_BIN/mainframe"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"terraform-destroy"* ]]
    jq -e '.details | index("decision=deny")' "$gateway_audit" >/dev/null

    gateway_payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}'
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$gateway_audit" \
        bash --noprofile --norc -c \
        'printf "%s" "$1" | "$2" agent-hook --format codex' \
        _ "$gateway_payload" "$TEST_BIN/mainframe"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"git-reset-hard"* ]]

    gateway_payload='{"toolName":"bash","toolArgs":"{\"command\":\"npm publish\"}"}'
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$gateway_audit" \
        bash --noprofile --norc -c \
        'printf "%s" "$1" | "$2" agent-hook --format copilot' \
        _ "$gateway_payload" "$TEST_BIN/mainframe"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"npm-publish"* ]]

    gateway_payload='{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"terraform destroy -auto-approve"}}'
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" \
        MAINFRAME_AGENT_AUDIT_LOG="$gateway_audit" \
        bash --noprofile --norc -c \
        'printf "%s" "$1" | "$2" agent-hook --format gemini' \
        _ "$gateway_payload" "$TEST_BIN/mainframe"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"terraform-destroy"* ]]

    for host in claude codex copilot gemini; do
        jq -e --arg host "$host" \
            'select(.details | index("host=" + $host)) | .details | index("decision=deny")' \
            "$gateway_audit" >/dev/null
    done

    # Put an execution sentinel at the start of the installed launcher. The
    # internal manifest must reject it before any payload code can run.
    local tampered_launcher="$TAMPERED_DIR/bin/mainframe"
    local tampered_tmp="$TEST_DIR/tampered-launcher"
    {
        IFS= read -r first_line < "$tampered_launcher"
        printf '%s\n' "$first_line"
        printf '%s\n' 'printf "tampered payload executed\n" > "${MAINFRAME_TAMPER_EXEC_MARKER:?}"'
        tail -n +2 "$tampered_launcher"
    } > "$tampered_tmp"
    mv "$tampered_tmp" "$tampered_launcher"
    chmod +x "$tampered_launcher"
    run install_from_extracted_tree \
        "$TAMPERED_DIR" "$TEST_DIR/tampered-home" "$TEST_DIR/tampered-bin"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Checksum verification failed"* ]]
    [[ ! -e "$TAMPER_EXEC_MARKER" ]]
    [[ ! -e "$GIT_MARKER" ]]

    mv "$MISSING_DIR/docs/AGENT_GATEWAY.md" "$MISSING_DIR/docs/AGENT_GATEWAY.md.removed"
    run install_from_extracted_tree \
        "$MISSING_DIR" "$TEST_DIR/missing-home" "$TEST_DIR/missing-bin"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MISSING: docs/AGENT_GATEWAY.md"* ]]
    [[ "$output" == *"Checksum verification failed"* ]]
    [[ ! -e "$GIT_MARKER" ]]

    printf 'archive tampered\n' >> "$archive"
    run checksum_matches "$archive" "$archive_checksum"
    [[ "$status" -ne 0 ]]
}

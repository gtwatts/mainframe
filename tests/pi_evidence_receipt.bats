#!/usr/bin/env bats

setup() {
    TEMPLATE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    PROJECT_ROOT="$BATS_TEST_TMPDIR/source"
    mkdir -p \
        "$PROJECT_ROOT/.github/scripts" \
        "$PROJECT_ROOT/.github/schemas" \
        "$PROJECT_ROOT/config" \
        "$PROJECT_ROOT/scripts/dev/native-host" \
        "$PROJECT_ROOT/tests"
    cp "$TEMPLATE_ROOT/VERSION" "$PROJECT_ROOT/VERSION"
    cp "$TEMPLATE_ROOT/config/pi-compatibility.json" "$PROJECT_ROOT/config/"
    cp "$TEMPLATE_ROOT/.github/pi-evidence-contract.json" "$PROJECT_ROOT/.github/"
    cp "$TEMPLATE_ROOT/.github/schemas/pi-release-evidence.schema.json" \
        "$PROJECT_ROOT/.github/schemas/"
    cp "$TEMPLATE_ROOT/.github/schemas/pi-cell-evidence.schema.json" \
        "$PROJECT_ROOT/.github/schemas/"
    cp "$TEMPLATE_ROOT/.github/scripts/build-pi-release-evidence.py" \
        "$PROJECT_ROOT/.github/scripts/"
    cp "$TEMPLATE_ROOT/.github/scripts/build-pi-cell-evidence.py" \
        "$PROJECT_ROOT/.github/scripts/"
    printf '%s\n' \
        '#!/usr/bin/env python3' \
        'import hashlib, json, stat, sys' \
        'from pathlib import Path' \
        'path = Path(sys.argv[1])' \
        'arch = {"arm64":"arm64", "x86_64":"x86_64"}[sys.argv[3]]' \
        'raw = path.read_bytes()' \
        'format_name = "elf" if sys.argv[2] == "Linux" else "mach-o"' \
        'value = {"architectures":[arch],"format":format_name,"mode":f"{stat.S_IMODE(path.stat().st_mode):04o}","path":str(path),"sha256":hashlib.sha256(raw).hexdigest(),"size_bytes":len(raw),"type":"file"}' \
        'print(json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")))' \
        > "$PROJECT_ROOT/scripts/dev/native-host/validate-native-executable.py"
    cp \
        "$TEMPLATE_ROOT/tests/pi_integration.bats" \
        "$TEMPLATE_ROOT/tests/pi_install.bats" \
        "$TEMPLATE_ROOT/tests/pi_compatibility_manifest.bats" \
        "$PROJECT_ROOT/tests/"
    GENERATOR="$PROJECT_ROOT/.github/scripts/build-pi-release-evidence.py"
    CONTRACT="$PROJECT_ROOT/.github/pi-evidence-contract.json"
    SCHEMA="$PROJECT_ROOT/.github/schemas/pi-release-evidence.schema.json"
    CELL_SCHEMA="$PROJECT_ROOT/.github/schemas/pi-cell-evidence.schema.json"
    CELL_GENERATOR="$PROJECT_ROOT/.github/scripts/build-pi-cell-evidence.py"
    ARCHIVE="$BATS_TEST_TMPDIR/mainframe-10.2.0.tar.gz"
    ARTIFACTS="$BATS_TEST_TMPDIR/artifacts"
    DURABLE_CELLS="$BATS_TEST_TMPDIR/durable-cells"
    RECEIPT="$BATS_TEST_TMPDIR/mainframe-10.2.0.pi-evidence.json"
    printf 'fixture archive bytes\n' > "$ARCHIVE"
    mkdir -p "$ARTIFACTS"
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.name "Mainframe Evidence Test"
    git -C "$PROJECT_ROOT" config user.email "evidence-test@example.invalid"
    git -C "$PROJECT_ROOT" add .
    git -C "$PROJECT_ROOT" commit -qm "fixture source"
    git -C "$PROJECT_ROOT" tag v10.2.0
    TAG_COMMIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    TAG_REF_SHA="$(git -C "$PROJECT_ROOT" rev-parse refs/tags/v10.2.0)"
    build_fixture_artifacts
}

build_fixture_artifacts() {
    local test_sha archive_sha pi_id platform_id suffix
    test_sha="$(python3 \
        "$TEMPLATE_ROOT/scripts/dev/native-host/hash-package-tree.py" \
        "$PROJECT_ROOT" tests)"
    archive_sha="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

    for pi_id in fork-0.84.2 upstream-0.73.1; do
        local package_name package_version npm_integrity package_root runtime_root integrity_file
        package_name="$(jq -er --arg id "$pi_id" \
            '.pi_versions[] | select(.id == $id) | .package' "$CONTRACT")"
        package_version="$(jq -er --arg id "$pi_id" \
            '.pi_versions[] | select(.id == $id) | .version' "$CONTRACT")"
        npm_integrity="$(jq -er --arg id "$pi_id" \
            '.pi_versions[] | select(.id == $id) | .npm_integrity' "$CONTRACT")"
        runtime_root="$BATS_TEST_TMPDIR/pi-runtime-$pi_id/node_modules"
        package_root="$runtime_root/$package_name"
        mkdir -p "$package_root/bin" "$runtime_root/.bin"
        printf '{"name":"%s","version":"%s"}\n' \
            "$package_name" "$package_version" > "$package_root/package.json"
        printf '#!/usr/bin/env node\n' > "$package_root/bin/pi.js"
        chmod 755 "$package_root/bin/pi.js"
        ln -s "../${package_name}/bin/pi.js" "$runtime_root/.bin/pi"
        for platform_id in \
            Darwin-arm64-none Darwin-x86_64-none Linux-x86_64-glibc; do
            suffix="${pi_id}-${platform_id}"
            local platform_os platform_arch node_bin node_binding node_binding_sha
            platform_os="${platform_id%%-*}"
            platform_arch="${platform_id#*-}"
            platform_arch="${platform_arch%%-*}"
            local node_process_arch
            node_process_arch=arm64
            [[ "$platform_arch" == x86_64 ]] && node_process_arch=x64
            node_bin="$BATS_TEST_TMPDIR/node-$platform_arch/node"
            mkdir -p "$(dirname "$node_bin")"
            printf '%s\n' \
                '#!/bin/sh' \
                '[ "$1" = "-p" ] && [ "$2" = "process.arch" ] || exit 64' \
                "printf '%s\\n' '$node_process_arch'" \
                > "$node_bin"
            chmod 755 "$node_bin"
            node_binding="$ARTIFACTS/pi-node-pre-${suffix}.json"
            python3 "$CELL_GENERATOR" snapshot-node \
                --repo-root "$PROJECT_ROOT" \
                --node-executable "$node_bin" \
                --expected-os "$platform_os" \
                --expected-arch "$platform_arch" \
                --output "$node_binding" >/dev/null
            node_binding_sha="$(shasum -a 256 "$node_binding" | awk '{print $1}')"
            integrity_file="$BATS_TEST_TMPDIR/pi-npm-integrity-${suffix}.txt"
            printf '%s\n' "$npm_integrity" > "$integrity_file"
            printf '%s\n' "$archive_sha" > \
                "$ARTIFACTS/pi-candidate-${suffix}.sha256"
            printf '%s\n' "$test_sha" > \
                "$ARTIFACTS/pi-tests-${suffix}.sha256"
            python3 - \
                "$CONTRACT" \
                "$PROJECT_ROOT" \
                "$ARTIFACTS/pi-candidate-${suffix}.tap" \
                "$pi_id" <<'PY'
import json
import pathlib
import re
import sys

contract = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
root = pathlib.Path(sys.argv[2])
output = pathlib.Path(sys.argv[3])
pi_id = sys.argv[4]
names = []
for relative in contract["test_paths"]:
    text = (root / relative).read_text(encoding="utf-8")
    pattern = r'(?m)^\s*' + '@' + r'test\s+"([^"]+)"\s*\{\s*$'
    names.extend(re.findall(pattern, text))
pi_record = next(record for record in contract["pi_versions"] if record["id"] == pi_id)
lines = [f"1..{len(names)}"]
for number, name in enumerate(names, start=1):
    if pi_record["expected_skip"] and name == pi_record["expected_skip"]["test"]:
        lines.append(f"ok {number} {name} # skip {pi_record['expected_skip']['reason']}")
    else:
        lines.append(f"ok {number} {name}")
output.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
            local runtime_snapshot runtime_snapshot_sha
            runtime_snapshot="$ARTIFACTS/pi-runtime-pre-${suffix}.json"
            python3 "$CELL_GENERATOR" snapshot-runtime \
                --pi-package-root "$package_root" \
                --pi-runtime-root "$runtime_root" \
                --pi-install-prefix "$BATS_TEST_TMPDIR/pi-runtime-$pi_id" \
                --expected-package "$package_name" \
                --expected-version "$package_version" \
                --output "$runtime_snapshot" >/dev/null
            runtime_snapshot_sha="$(shasum -a 256 "$runtime_snapshot" | awk '{print $1}')"
            MAINFRAME_PI_CELL_TEST_MODE=1 python3 "$CELL_GENERATOR" create \
                --contract "$CONTRACT" \
                --schema "$CELL_SCHEMA" \
                --repo-root "$PROJECT_ROOT" \
                --archive "$ARCHIVE" \
                --pi-package-root "$package_root" \
                --pi-runtime-root "$runtime_root" \
                --pi-install-prefix "$BATS_TEST_TMPDIR/pi-runtime-$pi_id" \
                --pre-test-runtime-snapshot "$runtime_snapshot" \
                --pre-test-runtime-snapshot-sha256 "$runtime_snapshot_sha" \
                --node-executable "$node_bin" \
                --expected-node-arch "$platform_arch" \
                --pre-test-node-binding "$node_binding" \
                --pre-test-node-binding-sha256 "$node_binding_sha" \
                --npm-integrity-file "$integrity_file" \
                --archive-binding "$ARTIFACTS/pi-candidate-${suffix}.sha256" \
                --test-binding "$ARTIFACTS/pi-tests-${suffix}.sha256" \
                --tap "$ARTIFACTS/pi-candidate-${suffix}.tap" \
                --repository gtwatts/mainframe \
                --version 10.2.0 \
                --source-ref refs/tags/v10.2.0 \
                --source-ref-sha "$TAG_REF_SHA" \
                --source-commit-sha "$TAG_COMMIT_SHA" \
                --workflow-run-id 12345 \
                --workflow-run-attempt 1 \
                --observed-platform "$platform_id" \
                --output "$ARTIFACTS/pi-cell-${suffix}.json" >/dev/null
        done
    done
}

create_receipt() {
    MAINFRAME_PI_CELL_TEST_MODE=1 python3 "$GENERATOR" create \
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha "$TAG_COMMIT_SHA" \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1 \
        --artifacts-dir "$ARTIFACTS" \
        --output "${1:-$RECEIPT}"
}

verify_receipt() {
    local -a arguments=(
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha "$TAG_COMMIT_SHA" \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1
    )
    if [[ -z "${VERIFY_WITHOUT_ARTIFACTS:-}" ]]; then
        arguments+=(--artifacts-dir "$ARTIFACTS")
    else
        arguments+=(--summary-only)
    fi
    arguments+=(--evidence "${1:-$RECEIPT}")
    MAINFRAME_PI_CELL_TEST_MODE=1 python3 "$GENERATOR" verify "${arguments[@]}"
}

stage_durable_cells() {
    mkdir -p "$DURABLE_CELLS"
    cp "$ARTIFACTS"/pi-cell-*.json "$DURABLE_CELLS/"
}

verify_durable_cells() {
    MAINFRAME_PI_CELL_TEST_MODE=1 python3 "$GENERATOR" verify \
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha "$TAG_COMMIT_SHA" \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1 \
        --cell-receipts-dir "$DURABLE_CELLS" \
        --evidence "${1:-$RECEIPT}"
}

@test "Pi release receipt creates canonical exact six-cell evidence and verifies" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi release evidence created: $RECEIPT" ]]

    run verify_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi release evidence and raw artifacts valid" ]]

    run python3 "$TEMPLATE_ROOT/scripts/dev/native-host/validate-evidence.py" \
        "$SCHEMA" "$RECEIPT"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .kind == "mainframe-pi-exact-candidate-evidence" and
      .claim_scope == "exact-candidate-pi-integration-conformance-only" and
      (.matrix | length) == 6 and
      .summary == {
        matrix_rows: 6, passed_rows: 6, failed_rows: 0,
        planned_tests: 264, ok: 264, executed: 261, not_ok: 0, skipped: 3
      } and
      ([.matrix[] | select(.compatibility.support == "certified")] | length) == 1 and
      ([.matrix[] | select(.compatibility.support == "limited")] | length) == 1 and
      ([.matrix[] | select(.compatibility.support == "unverified")] | length) == 4 and
      ([.matrix[] | select(
        .observation.runtime_proof.result == "unchanged" and
        .observation.runtime_proof.pre_test == .observation.runtime_proof.post_test and
        .observation.runtime_proof.post_test.package_tree_sha256 ==
          .observation.package_tree_sha256 and
        .observation.runtime_proof.post_test.runtime_tree_sha256 ==
          .observation.runtime_tree_sha256
      )] | length) == 6 and
      ([.matrix[] | select(
        .observation.node_runtime.algorithm ==
          "MAINFRAME-NATIVE-EXECUTABLE-BINDING-V1" and
        .observation.node_runtime.pre_test == .observation.node_runtime.post_test and
        .observation.node_runtime.pre_test.expected_arch == .platform.arch and
        .observation.node_runtime.pre_test.observed_process_arch == .platform.arch and
        .observation.node_runtime.executable_unchanged == true and
        .observation.node_runtime.process_arch_unchanged == true and
        .observation.node_runtime.result == "unchanged" and
        (.observation.node_runtime.pre_test.executable | has("path") | not) and
        .artifacts.node_binding.name ==
          ("pi-node-pre-" + (.id | sub("@"; "-")) + ".json") and
        .artifacts.node_binding.file_sha256 ==
          .observation.node_runtime.pre_test_binding.file_sha256
      )] | length) == 6 and
      ([.matrix[] | select(.pi.id == "fork-0.84.2") | .result.skipped] | add) == 0 and
      ([.matrix[] | select(.pi.id == "upstream-0.73.1") | .result.skipped] | add) == 3
    ' "$RECEIPT"
    [[ "$status" -eq 0 ]]
}

@test "Pi release receipt is reproducible and create refuses to overwrite" {
    local second="$BATS_TEST_TMPDIR/second.pi-evidence.json"
    run create_receipt
    [[ "$status" -eq 0 ]]
    run create_receipt "$second"
    [[ "$status" -eq 0 ]]
    run cmp "$RECEIPT" "$second"
    [[ "$status" -eq 0 ]]

    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output must be absent"* ]]
}

@test "Pi release receipt rejects TAP result, name, order, and skip drift" {
    local tap="$ARTIFACTS/pi-candidate-fork-0.84.2-Linux-x86_64-glibc.tap"
    local backup="$BATS_TEST_TMPDIR/tap.backup"
    cp "$tap" "$backup"
    sed 's/^ok 2 /not ok 2 /' "$tap" > "$BATS_TEST_TMPDIR/tap.mutated"
    mv "$BATS_TEST_TMPDIR/tap.mutated" "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failing tests"* ]]
    cp "$backup" "$tap"

    sed 's/^ok 2 /ok 2 wrong-test-name /' "$tap" > "$BATS_TEST_TMPDIR/tap.mutated"
    mv "$BATS_TEST_TMPDIR/tap.mutated" "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"test names or numbers"* ]]
    cp "$backup" "$tap"

    tap="$ARTIFACTS/pi-candidate-upstream-0.73.1-Darwin-arm64-none.tap"
    sed 's/# skip this Pi version/# skip wrong reason/' "$tap" > \
        "$BATS_TEST_TMPDIR/tap.mutated"
    mv "$BATS_TEST_TMPDIR/tap.mutated" "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"skip details"* ]]
}

@test "Pi release receipt rejects hidden TAP failures bailouts and reordered records" {
    local tap="$ARTIFACTS/pi-candidate-fork-0.84.2-Linux-x86_64-glibc.tap"
    local backup="$BATS_TEST_TMPDIR/tap.strict.backup"
    cp "$tap" "$backup"

    printf '  not ok 999 hidden failure\n' >> "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"malformed failure record"* ]]
    cp "$backup" "$tap"

    printf '  Bail out! hidden bailout\n' >> "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"bailout"* ]]
    cp "$backup" "$tap"

    printf '\357\273\277not ok 999 hidden failure\n' >> "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"contains a BOM"* ]]
    cp "$backup" "$tap"

    printf '\302\23331mnot ok 999 hidden failure\302\2330m\n' >> "$tap"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unsafe Unicode control character"* ]]
    cp "$backup" "$tap"

    python3 - "$tap" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
lines[1], lines[2] = lines[2], lines[1]
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"incomplete or out of order"* ]]
}

@test "Pi release receipt rejects missing, extra, symlinked, hard-linked, and mismatched inputs" {
    local binding="$ARTIFACTS/pi-tests-fork-0.84.2-Darwin-arm64-none.sha256"
    local saved="$BATS_TEST_TMPDIR/binding.saved"
    mv "$binding" "$saved"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"artifact inventory differs"* ]]
    mv "$saved" "$binding"

    printf 'extra\n' > "$ARTIFACTS/unexpected.txt"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"artifact inventory differs"* ]]
    rm "$ARTIFACTS/unexpected.txt"

    mv "$binding" "$saved"
    ln -s "$saved" "$binding"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"regular non-symlink"* ]]
    rm "$binding"
    mv "$saved" "$binding"

    ln "$binding" "$BATS_TEST_TMPDIR/hard-link"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"hard-linked"* ]]
    rm "$BATS_TEST_TMPDIR/hard-link"

    printf '%064d\n' 0 > "$binding"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"test binding does not match source tree"* ]]
}

@test "Pi release receipt rejects a copied receipt mislabeled as another platform cell" {
    local source_cell="$ARTIFACTS/pi-cell-fork-0.84.2-Darwin-arm64-none.json"
    local target_cell="$ARTIFACTS/pi-cell-fork-0.84.2-Linux-x86_64-glibc.json"
    cp "$source_cell" "$target_cell"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"receipt identity does not match"* ]]
}

@test "Pi release receipt rejects pre-test runtime snapshot drift" {
    local snapshot="$ARTIFACTS/pi-runtime-pre-fork-0.84.2-Linux-x86_64-glibc.json"
    jq -cS '.runtime_tree_sha256 = ("0" * 64)' "$snapshot" > "$BATS_TEST_TMPDIR/snapshot"
    mv "$BATS_TEST_TMPDIR/snapshot" "$snapshot"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"runtime snapshot"* || "$output" == *"runtime proof"* ]]
}

@test "Pi release receipt rejects pre-test Node binding tamper" {
    local binding="$ARTIFACTS/pi-node-pre-fork-0.84.2-Linux-x86_64-glibc.json"
    jq -cS '.executable.sha256 = ("0" * 64)' "$binding" > \
        "$BATS_TEST_TMPDIR/node-binding-tampered.json"
    mv "$BATS_TEST_TMPDIR/node-binding-tampered.json" "$binding"
    chmod 600 "$binding"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Node pre/post proof does not match"* ]]
}

@test "Pi release receipt rejects duplicate keys, noncanonical bytes, and source identity drift" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    local duplicate="$BATS_TEST_TMPDIR/duplicate.json"
    printf '{"schema_version":1,"schema_version":1}\n' > "$duplicate"
    run verify_receipt "$duplicate"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate key"* ]]

    local noncanonical="$BATS_TEST_TMPDIR/noncanonical.json"
    jq . "$RECEIPT" > "$noncanonical"
    run verify_receipt "$noncanonical"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not canonical sorted-key JSON"* ]]

    run python3 "$GENERATOR" verify \
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha cccccccccccccccccccccccccccccccccccccccc \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1 \
        --evidence "$RECEIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"HEAD/tag commit does not match"* ]]
}

@test "Pi release receipt requires explicit summary mode and derives binding hashes" {
    run create_receipt
    [[ "$status" -eq 0 ]]

    VERIFY_WITHOUT_ARTIFACTS=1 run verify_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi release evidence summary valid; raw artifacts not reverified" ]]

    run python3 "$GENERATOR" verify \
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha "$TAG_COMMIT_SHA" \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1 \
        --evidence "$RECEIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"requires exactly one of --artifacts-dir"* ]]

    local tampered="$BATS_TEST_TMPDIR/tampered-binding.json"
    jq -cS '.matrix[0].artifacts.archive_binding.file_sha256 = ("0" * 64)' \
        "$RECEIPT" > "$tampered"
    run verify_receipt "$tampered"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"digest is not derivable from its binding"* ]]

    local tampered_snapshot="$BATS_TEST_TMPDIR/tampered-snapshot-binding.json"
    jq -cS '
      .matrix[0].observation.runtime_proof.pre_test_snapshot.file_sha256 = ("0" * 64) |
      .matrix[0].artifacts.runtime_snapshot.file_sha256 = ("0" * 64)
    ' "$RECEIPT" > "$tampered_snapshot"
    VERIFY_WITHOUT_ARTIFACTS=1 run verify_receipt "$tampered_snapshot"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"runtime snapshot digest is not derivable"* ]]
}

@test "Pi release receipt verifies six durable cell receipts without raw TAP" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    stage_durable_cells

    run verify_durable_cells
    [[ "$status" -eq 0 ]]
    [[ "$output" == \
        "Pi release evidence and six durable cell receipts valid; raw TAP not reverified" ]]

    printf 'unrelated immutable release asset\n' > "$DURABLE_CELLS/mainframe.rb"
    run verify_durable_cells
    [[ "$status" -eq 0 ]]

    run python3 "$GENERATOR" verify \
        --contract "$CONTRACT" \
        --schema "$SCHEMA" \
        --cell-schema "$CELL_SCHEMA" \
        --repo-root "$PROJECT_ROOT" \
        --archive "$ARCHIVE" \
        --repository gtwatts/mainframe \
        --version 10.2.0 \
        --tag v10.2.0 \
        --tag-ref-sha "$TAG_REF_SHA" \
        --tag-commit-sha "$TAG_COMMIT_SHA" \
        --workflow-run-id 12345 \
        --workflow-run-attempt 1 \
        --cell-receipts-dir "$DURABLE_CELLS" \
        --summary-only \
        --evidence "$RECEIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"requires exactly one"* ]]
}

@test "durable Pi cell verification rejects missing extra symlinked and hard-linked receipts" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    stage_durable_cells
    local cell="$DURABLE_CELLS/pi-cell-fork-0.84.2-Darwin-arm64-none.json"
    local saved="$BATS_TEST_TMPDIR/durable-cell.saved"

    mv "$cell" "$saved"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"receipt inventory differs"* ]]
    mv "$saved" "$cell"

    printf '{}\n' > "$DURABLE_CELLS/pi-cell-unexpected.json"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"receipt inventory differs"* ]]
    rm "$DURABLE_CELLS/pi-cell-unexpected.json"

    mv "$cell" "$saved"
    ln -s "$saved" "$cell"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"durable Pi cell receipt"* ]]
    rm "$cell"
    mv "$saved" "$cell"

    ln "$cell" "$BATS_TEST_TMPDIR/durable-cell-hard-link"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must not be hard-linked"* ]]
}

@test "durable Pi cell verification rejects canonical digest and transitive identity drift" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    stage_durable_cells
    local cell="$DURABLE_CELLS/pi-cell-fork-0.84.2-Darwin-arm64-none.json"
    local tampered="$BATS_TEST_TMPDIR/tampered-durable-cell.json"
    local rebound="$BATS_TEST_TMPDIR/rebound.pi-evidence.json"

    jq -cS '.limitations[0] = "tampered"' "$cell" > "$tampered"
    mv "$tampered" "$cell"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"digest does not match aggregate"* ]]

    cp "$ARTIFACTS/pi-cell-fork-0.84.2-Darwin-arm64-none.json" "$cell"
    jq -cS '.cell_id = "fork-0.84.2@Linux-x86_64-glibc"' "$cell" > "$tampered"
    mv "$tampered" "$cell"
    local cell_sha
    cell_sha="$(shasum -a 256 "$cell" | awk '{print $1}')"
    jq -cS --arg sha "$cell_sha" \
        '.matrix[] |= if .id == "fork-0.84.2@Darwin-arm64-none" then
          .artifacts.cell_receipt.file_sha256 = $sha else . end' \
        "$RECEIPT" > "$rebound"
    run verify_durable_cells "$rebound"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"content does not match aggregate"* ]]
}

@test "durable Pi cell verification rejects duplicate noncanonical schema and source-run drift" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    stage_durable_cells
    local cell="$DURABLE_CELLS/pi-cell-fork-0.84.2-Darwin-arm64-none.json"
    local original="$BATS_TEST_TMPDIR/original-durable-cell.json"
    local changed="$BATS_TEST_TMPDIR/changed-durable-cell.json"
    local rebound="$BATS_TEST_TMPDIR/rebound-run.pi-evidence.json"
    cp "$cell" "$original"

    printf '{"schema_version":1,"schema_version":1}\n' > "$cell"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate key"* ]]

    cp "$original" "$cell"
    jq . "$cell" > "$changed"
    mv "$changed" "$cell"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not canonical JSON"* ]]

    cp "$original" "$cell"
    jq -cS '.unexpected = true' "$cell" > "$changed"
    mv "$changed" "$cell"
    run verify_durable_cells
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected keys"* ]]

    cp "$original" "$cell"
    jq -cS '.source.workflow_run_id = "99999"' "$cell" > "$changed"
    mv "$changed" "$cell"
    local cell_sha
    cell_sha="$(shasum -a 256 "$cell" | awk '{print $1}')"
    jq -cS --arg sha "$cell_sha" \
        '.matrix[] |= if .id == "fork-0.84.2@Darwin-arm64-none" then
          .artifacts.cell_receipt.file_sha256 = $sha else . end' \
        "$RECEIPT" > "$rebound"
    run verify_durable_cells "$rebound"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"content does not match aggregate"* ]]
}

@test "Pi release receipt binds certification and source bytes to Mainframe version" {
    python3 - "$PROJECT_ROOT/config/pi-compatibility.json" <<'PY'
from pathlib import Path
import json
import sys
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["mainframe_version"] = "99.9.9"
for record in value["certifications"]:
    record["mainframe_version"] = "99.9.9"
path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
PY
    git -C "$PROJECT_ROOT" add config/pi-compatibility.json
    git -C "$PROJECT_ROOT" commit -qm "foreign compatibility version"
    git -C "$PROJECT_ROOT" tag -f v10.2.0 >/dev/null
    TAG_COMMIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    TAG_REF_SHA="$(git -C "$PROJECT_ROOT" rev-parse refs/tags/v10.2.0)"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"manifest Mainframe version does not match"* ]]
}

@test "Pi release receipt rejects dirty source evidence inputs" {
    printf '\n# uncommitted source drift\n' >> "$PROJECT_ROOT/tests/pi_integration.bats"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"source evidence inputs are untracked or differ"* ]]
}

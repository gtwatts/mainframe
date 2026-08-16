#!/usr/bin/env bats

setup() {
    TEMPLATE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    PROJECT_ROOT="$BATS_TEST_TMPDIR/source"
    mkdir -p \
        "$PROJECT_ROOT/.github/scripts" \
        "$PROJECT_ROOT/.github/schemas" \
        "$PROJECT_ROOT/config" \
        "$PROJECT_ROOT/scripts/dev/native-host" \
        "$PROJECT_ROOT/tests" \
        "$BATS_TEST_TMPDIR/node-fixture" \
        "$BATS_TEST_TMPDIR/pi-runtime/node_modules/@earendil-works/pi-coding-agent/bin" \
        "$BATS_TEST_TMPDIR/pi-runtime/node_modules/.bin"
    cp "$TEMPLATE_ROOT/VERSION" "$PROJECT_ROOT/VERSION"
    cp "$TEMPLATE_ROOT/config/pi-compatibility.json" "$PROJECT_ROOT/config/"
    cp "$TEMPLATE_ROOT/.github/pi-evidence-contract.json" "$PROJECT_ROOT/.github/"
    cp "$TEMPLATE_ROOT/.github/schemas/pi-cell-evidence.schema.json" \
        "$PROJECT_ROOT/.github/schemas/"
    cp "$TEMPLATE_ROOT/.github/scripts/build-pi-cell-evidence.py" \
        "$PROJECT_ROOT/.github/scripts/"
    printf '%s\n' \
        '#!/usr/bin/env python3' \
        'import hashlib, json, stat, sys' \
        'from pathlib import Path' \
        'path = Path(sys.argv[1])' \
        'raw = path.read_bytes()' \
        'value = {"architectures":["x86_64"],"format":"elf","mode":f"{stat.S_IMODE(path.stat().st_mode):04o}","path":str(path),"sha256":hashlib.sha256(raw).hexdigest(),"size_bytes":len(raw),"type":"file"}' \
        'print(json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")))' \
        > "$PROJECT_ROOT/scripts/dev/native-host/validate-native-executable.py"
    cp \
        "$TEMPLATE_ROOT/tests/pi_integration.bats" \
        "$TEMPLATE_ROOT/tests/pi_install.bats" \
        "$TEMPLATE_ROOT/tests/pi_project_awm.bats" \
        "$TEMPLATE_ROOT/tests/pi_compatibility_manifest.bats" \
        "$PROJECT_ROOT/tests/"

    GENERATOR="$PROJECT_ROOT/.github/scripts/build-pi-cell-evidence.py"
    CONTRACT="$PROJECT_ROOT/.github/pi-evidence-contract.json"
    SCHEMA="$PROJECT_ROOT/.github/schemas/pi-cell-evidence.schema.json"
    ARCHIVE="$BATS_TEST_TMPDIR/mainframe-10.2.0.tar.gz"
    INSTALL_PREFIX="$BATS_TEST_TMPDIR/pi-runtime"
    RUNTIME_ROOT="$BATS_TEST_TMPDIR/pi-runtime/node_modules"
    PACKAGE_ROOT="$RUNTIME_ROOT/@earendil-works/pi-coding-agent"
    INTEGRITY_FILE="$BATS_TEST_TMPDIR/npm-integrity.txt"
    PLATFORM_ID="Linux-x86_64-glibc"
    PI_ID="fork-0.84.1"
    SUFFIX="$PI_ID-$PLATFORM_ID"
    ARCHIVE_BINDING="$BATS_TEST_TMPDIR/pi-candidate-$SUFFIX.sha256"
    TEST_BINDING="$BATS_TEST_TMPDIR/pi-tests-$SUFFIX.sha256"
    TAP="$BATS_TEST_TMPDIR/pi-candidate-$SUFFIX.tap"
    RECEIPT="$BATS_TEST_TMPDIR/pi-cell-$SUFFIX.json"
    PRE_TEST_SNAPSHOT="$BATS_TEST_TMPDIR/pi-runtime-pre-$SUFFIX.json"
    NODE_BIN="$BATS_TEST_TMPDIR/node-fixture/node"
    PRE_TEST_NODE_BINDING="$BATS_TEST_TMPDIR/pi-node-pre-$SUFFIX.json"

    printf 'fixture archive bytes\n' > "$ARCHIVE"
    printf '%s\n' \
        'sha512-ncAqFrG+iybuPGOhMiZoEHkEzTpJgz3guYD32pD+M7ucc0WeHmauP6wa7qwP8V/KWvsZDVNa5XGsdZ7fkC7w7A==' \
        > "$INTEGRITY_FILE"
    printf '%s\n' \
        '{"name":"@earendil-works/pi-coding-agent","version":"0.84.1"}' \
        > "$PACKAGE_ROOT/package.json"
    printf '#!/usr/bin/env node\n' > "$PACKAGE_ROOT/bin/pi.js"
    chmod 755 "$PACKAGE_ROOT/bin/pi.js"
    ln -s ../@earendil-works/pi-coding-agent/bin/pi.js "$RUNTIME_ROOT/.bin/pi"
    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$1" = "-p" ] && [ "$2" = "process.arch" ] || exit 64' \
        'printf "x64\\n"' \
        > "$NODE_BIN"
    chmod 755 "$NODE_BIN"

    git -C "$PROJECT_ROOT" init -q -b main
    git -C "$PROJECT_ROOT" config user.name "Mainframe Cell Evidence Test"
    git -C "$PROJECT_ROOT" config user.email "cell-evidence@example.invalid"
    git -C "$PROJECT_ROOT" add .
    git -C "$PROJECT_ROOT" commit -qm "fixture source"
    SOURCE_REF="refs/heads/main"
    SOURCE_COMMIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    SOURCE_REF_SHA="$(git -C "$PROJECT_ROOT" rev-parse "$SOURCE_REF")"
    build_raw_artifacts
    build_pre_test_snapshot
    build_pre_test_node_binding
}

build_pre_test_snapshot() {
    python3 "$GENERATOR" snapshot-runtime \
        --pi-package-root "$PACKAGE_ROOT" \
        --pi-runtime-root "$RUNTIME_ROOT" \
        --pi-install-prefix "$INSTALL_PREFIX" \
        --expected-package '@earendil-works/pi-coding-agent' \
        --expected-version 0.84.1 \
        --output "$PRE_TEST_SNAPSHOT"
    PRE_TEST_SNAPSHOT_SHA="$(shasum -a 256 "$PRE_TEST_SNAPSHOT" | awk '{print $1}')"
}

build_pre_test_node_binding() {
    python3 "$GENERATOR" snapshot-node \
        --repo-root "$PROJECT_ROOT" \
        --node-executable "$NODE_BIN" \
        --expected-os Linux \
        --expected-arch x86_64 \
        --output "$PRE_TEST_NODE_BINDING"
    PRE_TEST_NODE_BINDING_SHA="$(shasum -a 256 "$PRE_TEST_NODE_BINDING" | awk '{print $1}')"
}

build_raw_artifacts() {
    local archive_sha tests_sha
    archive_sha="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    tests_sha="$(python3 \
        "$TEMPLATE_ROOT/scripts/dev/native-host/hash-package-tree.py" \
        "$PROJECT_ROOT" tests)"
    printf '%s\n' "$archive_sha" > "$ARCHIVE_BINDING"
    printf '%s\n' "$tests_sha" > "$TEST_BINDING"
    python3 - "$CONTRACT" "$PROJECT_ROOT" "$TAP" <<'PY'
import json
from pathlib import Path
import re
import sys

contract = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])
names = []
for relative in contract["test_paths"]:
    source = (root / relative).read_text(encoding="utf-8")
    names.extend(re.findall(r'(?m)^\s*@test\s+"([^"]+)"\s*\{\s*$', source))
lines = [f"1..{len(names)}"]
lines.extend(f"ok {number} {name}" for number, name in enumerate(names, start=1))
Path(sys.argv[3]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

cell_arguments() {
    CELL_ARGUMENTS=(
        --contract "$CONTRACT"
        --schema "$SCHEMA"
        --repo-root "$PROJECT_ROOT"
        --archive "$ARCHIVE"
        --pi-package-root "$PACKAGE_ROOT"
        --pi-runtime-root "$RUNTIME_ROOT"
        --pi-install-prefix "$INSTALL_PREFIX"
        --pre-test-runtime-snapshot "$PRE_TEST_SNAPSHOT"
        --pre-test-runtime-snapshot-sha256 "$PRE_TEST_SNAPSHOT_SHA"
        --node-executable "$NODE_BIN"
        --expected-node-arch x86_64
        --pre-test-node-binding "$PRE_TEST_NODE_BINDING"
        --pre-test-node-binding-sha256 "$PRE_TEST_NODE_BINDING_SHA"
        --npm-integrity-file "$INTEGRITY_FILE"
        --archive-binding "$ARCHIVE_BINDING"
        --test-binding "$TEST_BINDING"
        --tap "$TAP"
        --repository gtwatts/mainframe
        --version 10.2.0
        --source-ref "$SOURCE_REF"
        --source-ref-sha "$SOURCE_REF_SHA"
        --source-commit-sha "$SOURCE_COMMIT_SHA"
        --workflow-run-id 12345
        --workflow-run-attempt 1
        --observed-platform "$PLATFORM_ID"
    )
}

create_receipt() {
    cell_arguments
    MAINFRAME_PI_CELL_TEST_MODE=1 \
        python3 "$GENERATOR" create "${CELL_ARGUMENTS[@]}" \
        --output "${1:-$RECEIPT}"
}

verify_receipt() {
    cell_arguments
    MAINFRAME_PI_CELL_TEST_MODE=1 \
        python3 "$GENERATOR" verify "${CELL_ARGUMENTS[@]}" \
        --evidence "${1:-$RECEIPT}"
}

@test "Pi cell receipt creates and verifies a canonical bounded single-cell record" {
    run create_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi cell evidence created: $RECEIPT" ]]

    run verify_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi cell evidence and raw artifacts valid" ]]

    run python3 "$TEMPLATE_ROOT/scripts/dev/native-host/validate-evidence.py" \
        "$SCHEMA" "$RECEIPT"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .kind == "mainframe-pi-exact-candidate-cell-evidence" and
      .claim_scope == "exact-candidate-single-cell-pi-integration-conformance-only" and
      .cell_id == "fork-0.84.1@Linux-x86_64-glibc" and
      .host.observation_mode == "test-override" and
      .host.test_override == "Linux-x86_64-glibc" and
      .pi.package == "@earendil-works/pi-coding-agent" and
      .pi.version == "0.84.1" and
      (.pi.package_json_sha256 | test("^[0-9a-f]{64}$")) and
      (.pi.package_tree_sha256 | test("^[0-9a-f]{64}$")) and
      (.pi.runtime_tree_sha256 | test("^[0-9a-f]{64}$")) and
      .pi.runtime_root_name == "node_modules" and
      .pi.runtime_entry == ".bin/pi" and
      .runtime_proof.algorithm == "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1" and
      .runtime_proof.pre_test == .runtime_proof.post_test and
      .runtime_proof.post_test.package_tree_sha256 == .pi.package_tree_sha256 and
      .runtime_proof.post_test.runtime_tree_sha256 == .pi.runtime_tree_sha256 and
      .runtime_proof.package_unchanged == true and
      .runtime_proof.runtime_unchanged == true and
      .runtime_proof.result == "unchanged" and
      .runtime_proof.pre_test_snapshot.name ==
        "pi-runtime-pre-fork-0.84.1-Linux-x86_64-glibc.json" and
      .compatibility.support == "unverified" and
      .compatibility.runtime_state == "COMPATIBILITY_UNVERIFIED" and
      .result == {
        status: "pass", plan: 45, ok: 45, executed: 45,
        not_ok: 0, skipped: 0, skip_details: []
      } and
      (.source.files | length) == 10 and
      .artifacts.archive_binding.binding_value == .mainframe.archive_sha256 and
      .artifacts.test_binding.binding_value == .tests.source_tree_sha256 and
      .artifacts.tap.binding_value == null
    ' "$RECEIPT"
    [[ "$status" -eq 0 ]]

    run python3 - "$RECEIPT" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
expected = json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n"
raise SystemExit(0 if path.read_text(encoding="utf-8") == expected else 1)
PY
    [[ "$status" -eq 0 ]]
}

@test "Pi receipt binds a path-free unchanged Node executable and process architecture" {
    local executable_sha changed_receipt changed_arch_receipt
    executable_sha="$(shasum -a 256 "$NODE_BIN" | awk '{print $1}')"

    run create_receipt
    [[ "$status" -eq 0 ]]
    run python3 "$TEMPLATE_ROOT/scripts/dev/native-host/validate-evidence.py" \
        "$SCHEMA" "$RECEIPT"
    [[ "$status" -eq 0 ]]
    run jq -e '
      .node_runtime == {
        algorithm: "MAINFRAME-NATIVE-EXECUTABLE-BINDING-V1",
        pre_test_binding: {
          name: "pi-node-pre-fork-0.84.1-Linux-x86_64-glibc.json",
          file_sha256: $binding_sha
        },
        pre_test: {
          expected_arch: "x86_64",
          observed_process_arch: "x86_64",
          executable: {
            architectures: ["x86_64"], basename: "node", format: "elf",
            mode: "0755", sha256: $executable_sha,
            size_bytes: $executable_size, type: "file"
          }
        },
        post_test: {
          expected_arch: "x86_64",
          observed_process_arch: "x86_64",
          executable: {
            architectures: ["x86_64"], basename: "node", format: "elf",
            mode: "0755", sha256: $executable_sha,
            size_bytes: $executable_size, type: "file"
          }
        },
        executable_unchanged: true,
        process_arch_unchanged: true,
        result: "unchanged"
      } and
      .node_runtime.pre_test == .node_runtime.post_test and
      ([.node_runtime | .. | objects | has("path")] | any | not) and
      .node_runtime.pre_test.expected_arch == .host.platform.arch and
      .node_runtime.pre_test.observed_process_arch == .host.platform.arch
    ' \
        --arg binding_sha "$PRE_TEST_NODE_BINDING_SHA" \
        --arg executable_sha "$executable_sha" \
        --argjson executable_size "$(wc -c < "$NODE_BIN" | tr -d '[:space:]')" \
        "$RECEIPT"
    [[ "$status" -eq 0 ]]

    printf '# post-test executable identity drift\n' >> "$NODE_BIN"
    changed_receipt="$BATS_TEST_TMPDIR/node-executable-drift.json"
    run create_receipt "$changed_receipt"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Node executable or process architecture changed after Pi tests"* ]]
    [[ ! -e "$changed_receipt" && ! -L "$changed_receipt" ]]

    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$1" = "-p" ] && [ "$2" = "process.arch" ] || exit 64' \
        'printf "arm64\\n"' \
        > "$NODE_BIN"
    changed_arch_receipt="$BATS_TEST_TMPDIR/node-process-arch-drift.json"
    run create_receipt "$changed_arch_receipt"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"process.arch does not match the expected matrix architecture"* ]]
    [[ ! -e "$changed_arch_receipt" && ! -L "$changed_arch_receipt" ]]
}

@test "Pi cell receipt is reproducible, no-clobber, and test override is gated" {
    local second="$BATS_TEST_TMPDIR/second.json"
    run create_receipt
    [[ "$status" -eq 0 ]]
    run create_receipt "$second"
    [[ "$status" -eq 0 ]]
    run cmp "$RECEIPT" "$second"
    [[ "$status" -eq 0 ]]

    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output must be absent"* ]]

    cell_arguments
    run env -u MAINFRAME_PI_CELL_TEST_MODE \
        python3 "$GENERATOR" verify "${CELL_ARGUMENTS[@]}" --evidence "$RECEIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"test-only"* ]]
}

@test "Pi cell receipt rejects package identity, integrity, and binding drift" {
    printf '%s\n' '{"name":"@earendil-works/pi-coding-agent","version":"9.9.9"}' \
        > "$PACKAGE_ROOT/package.json"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"package.json identity"* ]]

    printf '%s\n' \
        '{"name":"@earendil-works/pi-coding-agent","version":"0.84.1"}' \
        > "$PACKAGE_ROOT/package.json"
    printf '%s\n' 'sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==' \
        > "$INTEGRITY_FILE"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"npm integrity input does not match"* ]]

    printf '%s\n' \
        'sha512-ncAqFrG+iybuPGOhMiZoEHkEzTpJgz3guYD32pD+M7ucc0WeHmauP6wa7qwP8V/KWvsZDVNa5XGsdZ7fkC7w7A==' \
        > "$INTEGRITY_FILE"
    printf '%064d\n' 0 > "$ARCHIVE_BINDING"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive binding does not match"* ]]
}

@test "Pi cell receipt binds the package bytes and executable dependency graph" {
    run create_receipt
    [[ "$status" -eq 0 ]]

    printf 'dependency bytes\n' > "$RUNTIME_ROOT/runtime-dependency.js"
    local second="$BATS_TEST_TMPDIR/runtime-drift.json"
    run create_receipt "$second"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"runtime tree changed between pre-test snapshot and post-test evidence"* ]]

    rm "$RUNTIME_ROOT/runtime-dependency.js"
    chmod 600 "$PACKAGE_ROOT/package.json"
    local mode_drift="$BATS_TEST_TMPDIR/mode-drift.json"
    run create_receipt "$mode_drift"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"package tree changed between pre-test snapshot and post-test evidence"* ]]

    chmod 644 "$PACKAGE_ROOT/package.json"
    printf 'mutated package bytes\n' >> "$PACKAGE_ROOT/bin/pi.js"
    local third="$BATS_TEST_TMPDIR/package-drift.json"
    run create_receipt "$third"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"package tree changed between pre-test snapshot and post-test evidence"* ]]
}

@test "Pi cell receipt rejects pre-test snapshot substitution and tampering" {
    PRE_TEST_SNAPSHOT_SHA="$(printf '%064d' 0)"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"snapshot digest does not match"* ]]

    PRE_TEST_SNAPSHOT_SHA="$(shasum -a 256 "$PRE_TEST_SNAPSHOT" | awk '{print $1}')"
    printf ' ' >> "$PRE_TEST_SNAPSHOT"
    PRE_TEST_SNAPSHOT_SHA="$(shasum -a 256 "$PRE_TEST_SNAPSHOT" | awk '{print $1}')"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not strict UTF-8 JSON"* || "$output" == *"not canonical"* ]]
}

@test "Pi cell receipt rejects escaping dependency links and non-file runtime entries" {
    mkdir -p "$BATS_TEST_TMPDIR/external-runtime"
    printf 'external dependency\n' > "$BATS_TEST_TMPDIR/external-runtime/module.js"
    ln -s "$BATS_TEST_TMPDIR/external-runtime/module.js" \
        "$RUNTIME_ROOT/escaped-module.js"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"symlink escapes the runtime tree"* ]]
    rm "$RUNTIME_ROOT/escaped-module.js"

    rm "$RUNTIME_ROOT/.bin/pi"
    mkdir "$RUNTIME_ROOT/.bin/pi"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must be a regular file or symlink"* ]]

    rmdir "$RUNTIME_ROOT/.bin/pi"
    cp "$PACKAGE_ROOT/bin/pi.js" "$RUNTIME_ROOT/.bin/pi"
    chmod 644 "$RUNTIME_ROOT/.bin/pi"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must resolve to a regular executable"* ]]
}

@test "Pi runtime snapshot rejects symlinked package ancestors" {
    mv "$RUNTIME_ROOT/@earendil-works" "$RUNTIME_ROOT/real-scope"
    ln -s real-scope "$RUNTIME_ROOT/@earendil-works"
    local linked_snapshot="$BATS_TEST_TMPDIR/linked-snapshot.json"
    run python3 "$GENERATOR" snapshot-runtime \
        --pi-package-root "$PACKAGE_ROOT" \
        --pi-runtime-root "$RUNTIME_ROOT" \
        --pi-install-prefix "$INSTALL_PREFIX" \
        --expected-package '@earendil-works/pi-coding-agent' \
        --expected-version 0.84.1 \
        --output "$linked_snapshot"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"package ancestor must be a real directory"* ]]
}

@test "Pi runtime snapshot rejects symlinked install prefix and runtime ancestors" {
    local real_prefix="$BATS_TEST_TMPDIR/real-prefix"
    local linked_prefix="$BATS_TEST_TMPDIR/linked-prefix"
    local linked_snapshot="$BATS_TEST_TMPDIR/linked-prefix-snapshot.json"
    mv "$INSTALL_PREFIX" "$real_prefix"
    ln -s "$real_prefix" "$linked_prefix"
    run python3 "$GENERATOR" snapshot-runtime \
        --pi-package-root "$linked_prefix/node_modules/@earendil-works/pi-coding-agent" \
        --pi-runtime-root "$linked_prefix/node_modules" \
        --pi-install-prefix "$linked_prefix" \
        --expected-package '@earendil-works/pi-coding-agent' \
        --expected-version 0.84.1 \
        --output "$linked_snapshot"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"pi-install-prefix must be a real directory"* ]]
}

@test "native host observation ignores PATH-shadowed uname and getconf" {
    local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nprintf "Bogus\\n"\n' > "$fake_bin/uname"
    printf '#!/bin/sh\nprintf "Bogus\\n"\n' > "$fake_bin/getconf"
    chmod 755 "$fake_bin/uname" "$fake_bin/getconf"
    run env PATH="$fake_bin:$PATH" python3 - "$GENERATOR" "$CONTRACT" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("pi_cell_evidence", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
contract = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
platform, observation = module.observe_platform(None, contract["platforms"])
assert observation["observation_mode"] == "native"
assert observation["commands"]["uname_system"] != "Bogus"
assert observation["commands"]["uname_machine"] != "Bogus"
assert platform["os"] == observation["commands"]["uname_system"]
PY
    [[ "$status" -eq 0 ]]
}

@test "native Pi observation rejects translated and mixed Darwin identities before receipt work" {
    run python3 - "$GENERATOR" "$CONTRACT" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import sys

generator, contract_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("pi_cell_native_admission", generator)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
contract = json.loads(contract_path.read_text(encoding="utf-8"))


class FakeSysctl:
    def __init__(self, *, result=0, value=0, size=None, error_number=0):
        self.result = result
        self.value = value
        self.size = size
        self.error_number = error_number
        self.argtypes = None
        self.restype = None

    def __call__(self, _name, value_pointer, size_pointer, _new_value, _new_size):
        value_pointer._obj.value = self.value
        if self.size is not None:
            size_pointer._obj.value = self.size
        module.ctypes.set_errno(self.error_number)
        return self.result


class FakeLibc:
    def __init__(self, probe):
        self.sysctlbyname = probe


def direct_probe(*, result=0, value=0, size=None, error_number=0):
    probe = FakeSysctl(
        result=result, value=value, size=size, error_number=error_number
    )
    module.ctypes.CDLL = lambda *_args, **_kwargs: FakeLibc(probe)
    return module._darwin_sysctl_int("sysctl.proc_translated")


assert direct_probe(value=0) == 0
assert direct_probe(value=1) == 1
assert direct_probe(result=-1, error_number=module.errno.ENOENT) is None
for call in (
    lambda: direct_probe(value=2),
    lambda: direct_probe(value=0, size=1),
):
    try:
        call()
    except module.EvidenceError as error:
        assert "malformed" in str(error)
    else:
        raise AssertionError("malformed Darwin sysctl result was accepted")
try:
    direct_probe(result=-1, error_number=5)
except module.EvidenceError as error:
    assert "errno 5" in str(error)
else:
    raise AssertionError("failed Darwin sysctl result was accepted")


class FakeStringSysctl:
    def __init__(self, payload, *, first_result=0, second_result=0, error_number=0, second_size=None):
        self.payload = payload
        self.first_result = first_result
        self.second_result = second_result
        self.error_number = error_number
        self.second_size = second_size
        self.argtypes = None
        self.restype = None
        self.calls = 0

    def __call__(self, _name, value_pointer, size_pointer, _new_value, _new_size):
        self.calls += 1
        module.ctypes.set_errno(self.error_number)
        if self.calls == 1:
            if self.first_result == 0:
                size_pointer._obj.value = len(self.payload)
            return self.first_result
        if self.second_result == 0:
            module.ctypes.memmove(value_pointer, self.payload, len(self.payload))
            size_pointer._obj.value = self.second_size or len(self.payload)
        return self.second_result


def direct_string_probe(payload, **kwargs):
    probe = FakeStringSysctl(payload, **kwargs)
    module.ctypes.CDLL = lambda *_args, **_kwargs: FakeLibc(probe)
    return module._darwin_sysctl_string("machdep.cpu.brand_string")


assert direct_string_probe(b"Intel(R) Xeon(R)\0") == "Intel(R) Xeon(R)"
assert direct_string_probe(b"ignored\0", first_result=-1, error_number=module.errno.ENOENT) is None
for call in (
    lambda: direct_string_probe(b""),
    lambda: direct_string_probe(b"Intel without terminator"),
    lambda: direct_string_probe(b"Intel\0", second_size=3),
    lambda: direct_string_probe(b"Intel\0", second_result=-1, error_number=5),
):
    try:
        call()
    except module.EvidenceError:
        pass
    else:
        raise AssertionError("malformed Darwin string sysctl result was accepted")


def set_native_state(translated, arm64_capable, cpu_brand=None):
    values = {
        "sysctl.proc_translated": translated,
        "hw.optional.arm64": arm64_capable,
    }
    module._darwin_sysctl_int = lambda name: values[name]
    module._darwin_sysctl_string = lambda name: (
        cpu_brand if name == "machdep.cpu.brand_string" else None
    )


def require_rejects(architecture: str, fragment: str) -> None:
    try:
        module._require_native_darwin(architecture)
    except module.EvidenceError as error:
        assert fragment in str(error), (fragment, str(error))
    else:
        raise AssertionError(f"native observation accepted identity requiring {fragment!r}")


set_native_state(0, 1)
module._require_native_darwin("arm64")
set_native_state(None, None, "Intel(R) Xeon(R)")
module._require_native_darwin("x86_64")
set_native_state(None, None, "Apple M4")
require_rejects("x86_64", "native Darwin Intel hardware")
set_native_state(None, None)
require_rejects("x86_64", "native Darwin Intel hardware")
set_native_state(None, 0)
module._require_native_darwin("x86_64")
set_native_state(1, 1)
require_rejects("x86_64", "Rosetta")
set_native_state(None, 1)
require_rejects("x86_64", "Apple Silicon")
set_native_state(None, 1)
require_rejects("arm64", "native Darwin arm64 execution")


def malformed_probe(_name):
    raise module.EvidenceError("Darwin native-state probe is malformed")


module._darwin_sysctl_int = malformed_probe
require_rejects("arm64", "malformed")


def failed_probe(_name):
    raise module.EvidenceError("Darwin native-state probe failed with errno 5")


module._darwin_sysctl_int = failed_probe
require_rejects("arm64", "errno 5")

commands = {
    (module.TRUSTED_UNAME, "-s"): "Darwin",
    (module.TRUSTED_UNAME, "-m"): "arm64",
    (module.TRUSTED_GETCONF, "LONG_BIT"): "64",
}
module.command_output = lambda command, *arguments: commands[(command, *arguments)]
set_native_state(0, 1)
platform, observation = module.observe_platform(None, contract["platforms"])
assert platform["id"] == "Darwin-arm64-none"
assert observation["observation_mode"] == "native"

def forbidden_probe(_name):
    raise AssertionError("test override unexpectedly invoked native admission")


module._darwin_sysctl_int = forbidden_probe
module.command_output = lambda *_arguments: (_ for _ in ()).throw(
    AssertionError("test override unexpectedly invoked native host commands")
)
os.environ["MAINFRAME_PI_CELL_TEST_MODE"] = "1"
platform, observation = module.observe_platform(
    "Linux-x86_64-glibc", contract["platforms"]
)
assert platform["id"] == "Linux-x86_64-glibc"
assert observation["observation_mode"] == "test-override"
assert observation["test_override"] == "Linux-x86_64-glibc"
PY
    [[ "$status" -eq 0 ]]
}

@test "cell source binding ignores PATH-shadowed Git and hostile Git environment" {
    local fake_bin="$BATS_TEST_TMPDIR/fake-git-bin"
    local clean_receipt="$BATS_TEST_TMPDIR/clean-git-cell.json"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nexit 99\n' > "$fake_bin/git"
    chmod 755 "$fake_bin/git"
    cell_arguments
    run env \
        MAINFRAME_PI_CELL_TEST_MODE=1 \
        PATH="$fake_bin:$PATH" \
        GIT_DIR="$BATS_TEST_TMPDIR/hostile-git-dir" \
        GIT_WORK_TREE="$BATS_TEST_TMPDIR/hostile-git-tree" \
        python3 "$GENERATOR" create "${CELL_ARGUMENTS[@]}" --output "$clean_receipt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi cell evidence created: $clean_receipt" ]]
}

@test "Pi cell receipt rejects TAP failures, name drift, and unexpected skips" {
    sed 's/^ok 2 /not ok 2 /' "$TAP" > "$BATS_TEST_TMPDIR/tap-mutated"
    mv "$BATS_TEST_TMPDIR/tap-mutated" "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failing tests"* ]]

    build_raw_artifacts
    sed 's/^ok 2 /ok 2 wrong-test-name /' "$TAP" > "$BATS_TEST_TMPDIR/tap-mutated"
    mv "$BATS_TEST_TMPDIR/tap-mutated" "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"names or numbers"* ]]

    build_raw_artifacts
    sed 's/^ok 2 \(.*\)$/ok 2 \1 # skip not-contracted/' "$TAP" > "$BATS_TEST_TMPDIR/tap-mutated"
    mv "$BATS_TEST_TMPDIR/tap-mutated" "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"skip details"* ]]

    build_raw_artifacts
    printf '\033[31mnot ok 999 hidden failure\033[0m\n' >> "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unsafe control character"* ]]

    build_raw_artifacts
    printf '\357\273\277Bail out! hidden bailout\n' >> "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"contains a BOM"* ]]

    build_raw_artifacts
    printf '\302\23331mnot ok 999 hidden failure\302\2330m\n' >> "$TAP"
    run create_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unsafe Unicode control character"* ]]
}

@test "Pi cell receipt rejects source, receipt canonicalization, and raw artifact drift" {
    run create_receipt
    [[ "$status" -eq 0 ]]

    printf '\n# drift\n' >> "$PROJECT_ROOT/tests/pi_integration.bats"
    run verify_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"differ from the bound Git commit"* ]]
    git -C "$PROJECT_ROOT" checkout -q -- tests/pi_integration.bats

    local pretty="$BATS_TEST_TMPDIR/pretty.json"
    jq . "$RECEIPT" > "$pretty"
    run verify_receipt "$pretty"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not canonical sorted-key JSON"* ]]

    printf 'tamper\n' >> "$TAP"
    run verify_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not match source and raw artifacts"* ]]
}

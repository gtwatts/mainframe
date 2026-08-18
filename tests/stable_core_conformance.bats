#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    RUNTIME_ROOT="${MAINFRAME_CONFORMANCE_RUNTIME_ROOT:-$PROJECT_ROOT}"
    [[ -d "$RUNTIME_ROOT" && ! -L "$RUNTIME_ROOT" ]] || {
        printf '%s\n' "stable-core runtime root is not a real directory: $RUNTIME_ROOT" >&2
        return 1
    }
    RUNTIME_ROOT="$(cd "$RUNTIME_ROOT" && pwd -P)"
}

require_full_runtime_or_skip() {
    local reason="$1"
    if [[ "${MAINFRAME_REQUIRE_FULL_STABLE_CORE:-0}" == "1" ]]; then
        printf '%s\n' "$reason" >&2
        return 1
    fi
    skip "$reason"
}

@test "built Node package is prepared as a separate conformance prerequisite" {
    if ! command -v bun >/dev/null 2>&1; then
        require_full_runtime_or_skip "Bun is required for the full Node adapter gate"
    fi

    run bun run --cwd "$PROJECT_ROOT/bindings/nodejs" build

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ -s "$PROJECT_ROOT/bindings/nodejs/dist/index.js" ]]
    [[ -s "$PROJECT_ROOT/bindings/nodejs/dist/index.d.ts" ]]

    failing_bun="$BATS_TEST_TMPDIR/failing-bun"
    printf '%s\n' '#!/bin/sh' 'exit 97' > "$failing_bun"
    chmod 700 "$failing_bun"

    run env MAINFRAME_CONFORMANCE_BUN="$failing_bun" \
        python3 "$PROJECT_ROOT/tests/stable_core_conformance.py" \
        --runtime-root "$RUNTIME_ROOT" \
        --adapters node \
        --require-adapters node

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"fresh Node binding build failed"* ]]
    [[ "$output" != *"adapter_ok name=node"* ]]
}

@test "portable stable-core adapters preserve reviewed result contracts byte-for-byte" {
    run python3 "$PROJECT_ROOT/tests/stable_core_conformance.py" \
        --runtime-root "$RUNTIME_ROOT" \
        --adapters cli,node,python,mcp \
        --require-adapters cli,python

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"corpus_ok contracts=26 cases=28 edge_bytes=empty,whitespace,unicode locale="* ]]
    [[ "$output" == *"runtime_ok root=$RUNTIME_ROOT source_clients=$PROJECT_ROOT"* ]]
    [[ "$output" == *"adapter_ok name=cli cases=28"* ]]
    [[ "$output" == *"adapter_ok name=python cases=28"* ]]
    if [[ "$output" == *"node_build_ok provenance=current-run-private"* ]]; then
        if [[ "$output" == *"adapter_ok name=node cases=28"* ]]; then
            [[ "$output" == *"adapter_ok name=node cases=28"* ]]
        else
            [[ "$output" == *"adapter_skip name=node reason=runtime-unavailable"* ]]
        fi
    else
        [[ "$output" == *"adapter_skip name=node reason=runtime-unavailable"* ]]
    fi
    [[ "$output" == *"stable_core_conformance=PASS contracts=26 cases=28"* ]]
}

@test "explicit MCP SDK discovery timeout fails closed without a traceback" {
    run python3 - "$PROJECT_ROOT/tests/stable_core_conformance.py" <<'PY'
import os
import runpy
import subprocess
import sys

module = runpy.run_path(sys.argv[1])
timeout_error = subprocess.TimeoutExpired

def raise_timeout(*args, **kwargs):
    raise timeout_error(args[0], kwargs["timeout"])

module["subprocess"].run = raise_timeout
os.environ["MAINFRAME_MCP_PYTHON"] = sys.executable
try:
    module["_find_mcp_python"]()
except module["ConformanceFailure"] as error:
    assert str(error) == "MAINFRAME_MCP_PYTHON SDK discovery timed out"
else:
    raise AssertionError("MCP SDK discovery timeout was accepted")
print("mcp_sdk_timeout=controlled")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "mcp_sdk_timeout=controlled" ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "implicit MCP SDK discovery timeout falls through to the next interpreter" {
    run python3 - "$PROJECT_ROOT/tests/stable_core_conformance.py" \
        "$BATS_TEST_TMPDIR" <<'PY'
import os
import runpy
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

module = runpy.run_path(sys.argv[1])
calls = []
fake_root = Path(sys.argv[2]) / "source"
first_candidate = fake_root / "mcp" / ".venv" / "bin" / "python"
first_candidate.parent.mkdir(parents=True)
first_candidate.write_bytes(b"#!/bin/sh\nexit 0\n")
first_candidate.chmod(0o700)
find_mcp_python = module["_find_mcp_python"]
find_mcp_python.__globals__["SOURCE_ROOT"] = fake_root

def timeout_then_pass(argv, **kwargs):
    calls.append(argv)
    if len(calls) == 1:
        raise subprocess.TimeoutExpired(argv, kwargs["timeout"])
    return SimpleNamespace(returncode=0)

module["subprocess"].run = timeout_then_pass
os.environ.pop("MAINFRAME_MCP_PYTHON", None)
selected = find_mcp_python()
assert selected == sys.executable
assert len(calls) == 2
assert all(argv[1:3] == ["-I", "-c"] for argv in calls)
assert "PathFinder.find_spec('mcp.server'" in calls[0][3]
assert "from mcp" not in calls[0][3]
print("mcp_sdk_timeout=fallback")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "mcp_sdk_timeout=fallback" ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "explicit Pi adapter executable is resolved without ambient PATH discovery" {
    run python3 - "$PROJECT_ROOT/tests/stable_core_conformance.py" \
        "$BATS_TEST_TMPDIR" <<'PY'
import runpy
import sys
from pathlib import Path

module = runpy.run_path(sys.argv[1])
fixture = Path(sys.argv[2]) / "explicit-pi" / "bin" / "pi"
fixture.parent.mkdir(parents=True)
fixture.write_bytes(b"#!/bin/sh\nexit 0\n")
fixture.chmod(0o700)

selected = module["_find_pi_executable"]({"MAINFRAME_PI_BIN": str(fixture)})
assert selected == str(fixture.resolve())

try:
    module["_find_pi_executable"]({"MAINFRAME_PI_BIN": "relative/pi"})
except module["ConformanceFailure"] as error:
    assert str(error) == "MAINFRAME_PI_BIN must be an absolute path"
else:
    raise AssertionError("relative explicit Pi executable was accepted")

for value in ("~/bin/pi", "~missing-mainframe-user/bin/pi"):
    try:
        module["_find_pi_executable"]({"MAINFRAME_PI_BIN": value})
    except module["ConformanceFailure"] as error:
        assert str(error) == "MAINFRAME_PI_BIN must be an absolute path"
    else:
        raise AssertionError(f"home-relative explicit Pi executable was accepted: {value}")

print("pi_explicit_runtime=bound")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "pi_explicit_runtime=bound" ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "Pi full-adapter gate requires every first-party adapter with no skips" {
    if [[ ! -x "${MAINFRAME_PI_BIN:-}" ]] && ! command -v pi >/dev/null 2>&1; then
        require_full_runtime_or_skip "Pi is required for the full first-party adapter gate"
    fi
    [[ -s "$PROJECT_ROOT/bindings/nodejs/dist/index.js" ]]

    run python3 "$PROJECT_ROOT/tests/stable_core_conformance.py" \
        --runtime-root "$RUNTIME_ROOT" \
        --adapters cli,node,python,mcp,pi \
        --require-adapters cli,node,python,mcp,pi

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"node_build_ok provenance=current-run-private"* ]]
    [[ "$output" == *"adapter_ok name=cli cases=28"* ]]
    [[ "$output" == *"adapter_ok name=node cases=28 client=built-node-package runtime=node"* ]]
    [[ "$output" == *"adapter_ok name=python cases=28"* ]]
    [[ "$output" == *"adapter_ok name=mcp cases=28 transport=stdio dispatch=server"* ]]
    [[ "$output" == *"adapter_ok name=pi cases=28 extension=runtime-root loader=installed-pi"* ]]
    [[ "$output" == *"stable_core_conformance=PASS contracts=26 cases=28 adapters=cli,node,python,mcp,pi skipped=none"* ]]
}

@test "CI has an explicit Ubuntu exact-candidate five-adapter gate" {
    local workflow lane release_header node_package node_lock
    workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    node_package="$PROJECT_ROOT/bindings/nodejs/package.json"
    node_lock="$PROJECT_ROOT/bindings/nodejs/bun.lock"
    lane="$(sed -n \
        '/^  stable-core-conformance-linux:/,/^  archive-cross-platform:/p' \
        "$workflow")"
    release_header="$(sed -n '/^  release-build:/,/^    steps:/p' "$workflow")"

    [[ -s "$node_lock" ]]
    run git -C "$PROJECT_ROOT" check-ignore --quiet bindings/nodejs/bun.lock
    [[ "$status" -ne 0 ]]
    run jq -er '.devDependencies["bun-types"]' "$node_package"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1.2.20" ]]
    grep -Fq '"bun-types": "1.2.20"' "$node_lock"

    [[ "$lane" == *'runs-on: ubuntu-24.04'* ]]
    [[ "$lane" == *'test "$(uname -s)" = Linux'* ]]
    [[ "$lane" == *'test "$(uname -m)" = x86_64'* ]]
    [[ "$lane" == *"getconf GNU_LIBC_VERSION | grep -Eq '^glibc [0-9]'"* ]]
    [[ "$lane" == *'node-version: '\''22.23.2'\'''* ]]
    [[ "$lane" == *'bun-version: '\''1.2.20'\'''* ]]
    [[ "$lane" == *"version: '0.11.32'"* ]]
    [[ "$lane" == *'test -s "$node_lock"'* ]]
    [[ "$lane" == *'test ! -L "$node_lock"'* ]]
    [[ "$lane" == *'git ls-files --error-unmatch bindings/nodejs/bun.lock'* ]]
    [[ "$lane" == *'node_lock_sha_before='* ]]
    [[ "$lane" == *'bun install --frozen-lockfile --ignore-scripts'* ]]
    [[ "$lane" == *'node_lock_sha_after='* ]]
    [[ "$lane" == *'test "$node_lock_sha_after" = "$node_lock_sha_before"'* ]]
    [[ "$lane" == *'git diff --exit-code -- bindings/nodejs/bun.lock'* ]]
    [[ "$lane" == *'uv sync --locked --no-install-project --group dev'* ]]
    [[ "$lane" == *'cd "$RUNNER_TEMP"'* ]]
    [[ "$lane" == *'"$GITHUB_WORKSPACE/mcp/.venv/bin/python" -c'* ]]
    [[ "$lane" == *'from mcp.server import Server'* ]]
    [[ "$lane" == *"PI_PACKAGE: '@earendil-works/pi-coding-agent'"* ]]
    [[ "$lane" == *"PI_VERSION: '0.84.2'"* ]]
    [[ "$lane" == *'npm_config_ignore_scripts=true'* ]]
    [[ "$lane" == *'scripts/dev/release-candidate.sh'*'--prepare --output-dir'* ]]
    [[ "$lane" == *'scripts/dev/release-candidate.sh'*'--check --output-dir'* ]]
    [[ "$lane" == *'scripts/dev/native-host/safe-extract.py "$archive" "$candidate_root"'* ]]
    [[ "$lane" == *'test -f "$candidate_root/skills/pi/extensions/mainframe.ts"'* ]]
    [[ "$lane" == *'for shell_name in bash zsh; do'* ]]
    [[ "$lane" == *'certify-shell-onboarding.sh'*'--archive "$MAINFRAME_LINUX_ARCHIVE"'* ]]
    [[ "$lane" == *'mf:std:validation:validate_int'* ]]
    [[ "$lane" == *'min_arithmetic_payload=denied_without_execution'* ||
       "$lane" == *"printf '%s_arithmetic_payload=denied_without_execution"* ]]
    [[ "$lane" == *'MAINFRAME_REQUIRE_FULL_STABLE_CORE: '\''1'\'''* ]]
    [[ "$lane" == *'--runtime-root "$MAINFRAME_LINUX_CANDIDATE_ROOT"'* ]]
    [[ "$lane" == *'--require-adapters cli,node,python,mcp,pi'* ]]
    [[ "$lane" == *'tests/stable_core_conformance.bats'* ]]
    [[ "$lane" == *'linux-exact-candidate-conformance.sha256'* ]]
    [[ "$lane" == *'test "$(wc -l < linux-exact-candidate-conformance.sha256'*'-eq 7'* ]]
    [[ "$lane" == *'sha256sum -c linux-exact-candidate-conformance.sha256'* ]]
    [[ "$lane" == *'name: linux-exact-candidate-conformance'* ]]
    [[ "$release_header" == *'stable-core-conformance-linux'* ]]
}

#!/usr/bin/env bats

# Distribution-boundary acceptance tests for the unpublished mainframe-mcp
# candidate. All wheels, sdists, installs, and runtime archives live below the
# Bats temporary directory unless CI supplies previously built artifacts.

setup_file() {
    local repo_root work package_dir runtime_archive wheel sdist rebuilt_wheel
    local -a uv_offline

    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    work="$BATS_FILE_TMPDIR/mainframe-mcp-package"
    package_dir="$work/package-artifacts"
    mkdir -p "$package_dir" "$work/rebuilt" "$work/runtime" "$work/outside"

    # Local callers can require offline builds. uvx is always exercised
    # offline; a fresh package install may populate the dependency cache unless
    # CI supplies the hash-verified wheelhouse.
    uv_offline=()
    if [[ "${MAINFRAME_MCP_TEST_OFFLINE:-0}" == "1" ]]; then
        uv_offline=(--offline)
    fi
    install_offline=()
    if [[ "${MAINFRAME_MCP_INSTALL_OFFLINE:-0}" == "1" ]]; then
        install_offline=(--offline)
    fi
    if [[ -n "${MAINFRAME_MCP_UVX_WHEELHOUSE:-}" ]]; then
        [[ -d "$MAINFRAME_MCP_UVX_WHEELHOUSE" ]]
        install_offline=(
            --offline --no-index --find-links "$MAINFRAME_MCP_UVX_WHEELHOUSE"
        )
    fi

    if [[ -n "${MAINFRAME_MCP_RUNTIME_ARCHIVE:-}" ]]; then
        runtime_archive="$MAINFRAME_MCP_RUNTIME_ARCHIVE"
        [[ -f "$runtime_archive" && ! -L "$runtime_archive" ]]
    else
        mkdir -p "$work/runtime-artifacts"
        SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
            bash "$repo_root/scripts/build-release-archive.sh" \
                --output-dir "$work/runtime-artifacts" >/dev/null
        runtime_archive="$work/runtime-artifacts/mainframe-10.2.0.tar.gz"
    fi
    [[ -f "$runtime_archive" && ! -L "$runtime_archive" ]]

    if [[ -n "${MAINFRAME_MCP_PACKAGE_ARTIFACT_DIR:-}" ]]; then
        python3 - "$MAINFRAME_MCP_PACKAGE_ARTIFACT_DIR" "$package_dir" <<'PY'
from pathlib import Path
import shutil
import sys

source, destination = map(Path, sys.argv[1:])
expected = {
    "mainframe_mcp-10.2.0-py3-none-any.whl",
    "mainframe_mcp-10.2.0.tar.gz",
}
observed = {path.name for path in source.glob("mainframe_mcp-10.2.0*")}
if observed != expected:
    raise SystemExit(f"unexpected downloaded package artifacts: {sorted(observed)!r}")
for name in sorted(expected):
    candidate = source / name
    if candidate.is_symlink() or not candidate.is_file():
        raise SystemExit(f"package artifact is not a regular file: {candidate}")
    shutil.copyfile(candidate, destination / name)
PY
    else
        builder_args=()
        if [[ ${#uv_offline[@]} -gt 0 ]]; then
            builder_args+=(--offline)
        fi
        UV_NO_PROGRESS=1 python3 \
            "$repo_root/.github/scripts/build-mcp-package.py" \
            --source "$repo_root/mcp" \
            --runtime-archive "$runtime_archive" \
            --output-dir "$package_dir" \
            "${builder_args[@]}"
    fi

    wheel="$package_dir/mainframe_mcp-10.2.0-py3-none-any.whl"
    sdist="$package_dir/mainframe_mcp-10.2.0.tar.gz"
    [[ -f "$wheel" && ! -L "$wheel" ]]
    [[ -f "$sdist" && ! -L "$sdist" ]]

    UV_NO_PROGRESS=1 uv build "${uv_offline[@]}" --no-sources --wheel \
        --out-dir "$work/rebuilt" "$sdist"
    rebuilt_wheel="$work/rebuilt/mainframe_mcp-10.2.0-py3-none-any.whl"
    [[ -f "$rebuilt_wheel" && ! -L "$rebuilt_wheel" ]]

    python3 "$repo_root/scripts/dev/native-host/safe-extract.py" \
        "$runtime_archive" "$work/runtime"

    UV_NO_PROGRESS=1 uv venv --python "$(command -v python3)" "$work/venv"
    UV_NO_PROGRESS=1 uv export --locked --project "$repo_root/mcp" \
        --no-dev --no-emit-project --no-hashes \
        --output-file "$work/constraints.txt"
    UV_NO_PROGRESS=1 uv pip install "${install_offline[@]}" --no-config \
        --python "$work/venv/bin/python" \
        --constraints "$work/constraints.txt" "$wheel"

    UV_NO_PROGRESS=1 uv venv --python "$(command -v python3)" \
        "$work/sdist-venv"
    UV_NO_PROGRESS=1 uv pip install "${install_offline[@]}" --no-config \
        --python "$work/sdist-venv/bin/python" \
        --constraints "$work/constraints.txt" "$rebuilt_wheel"

    {
        printf 'export MF_PACKAGE_REPO=%q\n' "$repo_root"
        printf 'export MF_PACKAGE_WORK=%q\n' "$work"
        printf 'export MF_PACKAGE_WHEEL=%q\n' "$wheel"
        printf 'export MF_PACKAGE_SDIST=%q\n' "$sdist"
        printf 'export MF_PACKAGE_REBUILT_WHEEL=%q\n' "$rebuilt_wheel"
        printf 'export MF_PACKAGE_RUNTIME_ARCHIVE=%q\n' "$runtime_archive"
        printf 'export MF_PACKAGE_RUNTIME=%q\n' "$work/runtime"
        printf 'export MF_PACKAGE_PYTHON=%q\n' "$work/venv/bin/python"
        printf 'export MF_PACKAGE_BIN=%q\n' "$work/venv/bin"
        printf 'export MF_PACKAGE_SDIST_BIN=%q\n' "$work/sdist-venv/bin"
        printf 'export MF_PACKAGE_OUTSIDE=%q\n' "$work/outside"
    } > "$work/fixture.env"
}

setup() {
    # shellcheck disable=SC1091 # Created by setup_file in the Bats temp root.
    source "$BATS_FILE_TMPDIR/mainframe-mcp-package/fixture.env"
}

@test "wheel and sdist contain only the isolated adapter package" {
    run python3 - "$MF_PACKAGE_WHEEL" "$MF_PACKAGE_SDIST" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile
import zipfile

wheel_path, sdist_path = sys.argv[1:]
for path in (wheel_path, sdist_path):
    if path.endswith(".whl"):
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
        prefix = ""
    else:
        with tarfile.open(path, "r:gz") as archive:
            names = archive.getnames()
        prefix = "mainframe_mcp-10.2.0/"

    assert names and len(names) == len(set(names)), (path, names)
    for raw_name in names:
        name = raw_name.rstrip("/")
        assert name
        pure = PurePosixPath(name)
        assert not pure.is_absolute() and ".." not in pure.parts
        relative = name.removeprefix(prefix)
        parts = PurePosixPath(relative).parts
        lowered = relative.lower()
        assert not relative.startswith("mcp/"), relative
        assert not relative.startswith("tests/"), relative
        assert not relative.startswith(("lib/", "config/")), relative
        if relative.startswith("bin/"):
            assert relative in {
                "bin/mainframe-mcp", "bin/mainframe-mcp-server"
            }, relative
        assert relative not in {
            "FUNCTIONS.json", "FUNCTIONS.lsp.json", "MANIFEST.json",
            "INVOCATION_INDEX.json", "SHA256SUMS", "VERSION",
        }, relative
        assert not any(part in {
            "__pycache__", ".pytest_cache", ".ruff_cache", ".venv", "dist",
        } for part in parts), relative
        assert not lowered.endswith((".pyc", ".pyo")), relative

with zipfile.ZipFile(wheel_path) as archive:
    roots = {name.split("/", 1)[0] for name in archive.namelist()}
    wheel_files = set(archive.namelist())
assert roots == {
    "mainframe_mcp",
    "mainframe_mcp-10.2.0.data",
    "mainframe_mcp-10.2.0.dist-info",
}, roots
assert {
    "mainframe_mcp-10.2.0.data/scripts/mainframe-mcp",
    "mainframe_mcp-10.2.0.data/scripts/mainframe-mcp-server",
}.issubset(wheel_files)

with tarfile.open(sdist_path, "r:gz") as archive:
    files = {member.name for member in archive if member.isfile()}
assert files == {
    "mainframe_mcp-10.2.0/build_backend.py",
    "mainframe_mcp-10.2.0/PKG-INFO",
    "mainframe_mcp-10.2.0/README.md",
    "mainframe_mcp-10.2.0/bin/mainframe-mcp",
    "mainframe_mcp-10.2.0/bin/mainframe-mcp-server",
    "mainframe_mcp-10.2.0/pyproject.toml",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/__init__.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/__main__.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/_runtime_release.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/_version.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/authorization.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/cli.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/executor.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/runtime_root.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/server.py",
    "mainframe_mcp-10.2.0/src/mainframe_mcp/tool_registry.py",
}, sorted(files)
PY
    [ "$status" -eq 0 ]
}

@test "ordinary wheel and sdist builds fail without an exact runtime binding" {
    output_dir="$MF_PACKAGE_WORK/unbound-sdist-build"
    wheel_output_dir="$MF_PACKAGE_WORK/unbound-wheel-build"
    mkdir "$output_dir" "$wheel_output_dir"
    run env UV_NO_PROGRESS=1 uv build --offline --no-sources \
        --out-dir "$output_dir" "$MF_PACKAGE_REPO/mcp"
    [ "$status" -ne 0 ]
    [[ "$output" == *'runtime-bound candidate builder'* ]]
    [ -z "$(find "$output_dir" -mindepth 1 ! -name .gitignore -print -quit)" ]

    run env UV_NO_PROGRESS=1 uv build --offline --no-sources --wheel \
        --out-dir "$wheel_output_dir" "$MF_PACKAGE_REPO/mcp"
    [ "$status" -ne 0 ]
    [[ "$output" == *'runtime-bound candidate builder'* ]]
    [ -z "$(find "$wheel_output_dir" -mindepth 1 ! -name .gitignore -print -quit)" ]
}

@test "bound builder rejects oversized and overpopulated runtime archives" {
    oversized="$MF_PACKAGE_WORK/oversized-runtime.tar.gz"
    crowded="$MF_PACKAGE_WORK/crowded-runtime.tar.gz"
    run python3 - "$oversized" "$crowded" <<'PY'
from pathlib import Path
import sys
import tarfile

oversized, crowded = map(Path, sys.argv[1:])
with oversized.open("wb") as output:
    output.truncate((256 * 1024 * 1024) + 1)
with tarfile.open(crowded, "w:gz") as archive:
    for index in range(10_001):
        member = tarfile.TarInfo(f"d{index:05d}/")
        member.type = tarfile.DIRTYPE
        member.mode = 0o755
        archive.addfile(member)
PY
    [ "$status" -eq 0 ]

    run python3 "$MF_PACKAGE_REPO/.github/scripts/build-mcp-package.py" \
        --source "$MF_PACKAGE_REPO/mcp" \
        --runtime-archive "$oversized" \
        --output-dir "$MF_PACKAGE_WORK/oversized-output" --offline
    [ "$status" -ne 0 ]
    [[ "$output" == *'compressed size limit'* ]]

    run python3 "$MF_PACKAGE_REPO/.github/scripts/build-mcp-package.py" \
        --source "$MF_PACKAGE_REPO/mcp" \
        --runtime-archive "$crowded" \
        --output-dir "$MF_PACKAGE_WORK/crowded-output" --offline
    [ "$status" -ne 0 ]
    [[ "$output" == *'too many members'* ]]
}

@test "distribution metadata, dependency, and console scripts are exact" {
    run python3 - "$MF_PACKAGE_WHEEL" "$MF_PACKAGE_SDIST" <<'PY'
from email.parser import BytesParser
from email.policy import compat32
import sys
import tarfile
import zipfile

wheel_path, sdist_path = sys.argv[1:]
with zipfile.ZipFile(wheel_path) as archive:
    metadata = BytesParser(policy=compat32).parsebytes(
        archive.read("mainframe_mcp-10.2.0.dist-info/METADATA")
    )
    names = set(archive.namelist())

assert metadata["Name"] == "mainframe-mcp"
assert metadata["Version"] == "10.2.0"
assert metadata["Summary"] == "Fail-closed stable-core MCP adapter for MAINFRAME"
assert metadata["Requires-Python"] == ">=3.10, <3.15"
assert metadata.get_all("Requires-Dist") == ["mcp==1.26.0"]
assert metadata["License-Expression"] == "MIT"

assert "mainframe_mcp-10.2.0.dist-info/entry_points.txt" not in names
assert {
    "mainframe_mcp-10.2.0.data/scripts/mainframe-mcp",
    "mainframe_mcp-10.2.0.data/scripts/mainframe-mcp-server",
}.issubset(names)

with tarfile.open(sdist_path, "r:gz") as archive:
    member = archive.getmember("mainframe_mcp-10.2.0/PKG-INFO")
    package_info = BytesParser(policy=compat32).parse(
        archive.extractfile(member), headersonly=True
    )
assert package_info["Name"] == metadata["Name"]
assert package_info["Version"] == metadata["Version"]
assert package_info["Requires-Python"] == metadata["Requires-Python"]
assert package_info.get_all("Requires-Dist") == ["mcp==1.26.0"]
PY
    [ "$status" -eq 0 ]
}

@test "wheel rebuilt from sdist is payload-equivalent and independently installable" {
    run python3 - "$MF_PACKAGE_WHEEL" "$MF_PACKAGE_REBUILT_WHEEL" <<'PY'
import sys
import zipfile

def contents(path):
    with zipfile.ZipFile(path) as archive:
        result = {}
        for name in archive.namelist():
            if name.endswith("/") or name.endswith(".dist-info/RECORD"):
                continue
            content = archive.read(name)
            if name.endswith(".dist-info/WHEEL"):
                content = b"\n".join(
                    line for line in content.splitlines()
                    if not line.startswith(b"Generator: ")
                )
            result[name] = content
        return result

assert contents(sys.argv[1]) == contents(sys.argv[2])
PY
    [ "$status" -eq 0 ]

    run env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER \
        "$MF_PACKAGE_SDIST_BIN/mainframe-mcp" --version
    [ "$status" -eq 0 ]
    [ "$output" = "mainframe-mcp 10.2.0" ]
}

@test "fresh non-editable install runs both consoles and python module outside source" {
    run "$MF_PACKAGE_PYTHON" - "$MF_PACKAGE_REPO" <<'PY'
from importlib import metadata
from pathlib import Path
import sys

repository = Path(sys.argv[1])
distribution = metadata.distribution("mainframe-mcp")
package = Path(distribution.locate_file("mainframe_mcp")).resolve()
assert package.is_dir()
assert repository.resolve() not in package.parents
assert str(repository.resolve()) not in sys.path
assert not any(
    repository.resolve() in Path(entry).resolve().parents
    for entry in sys.path if entry
)
PY
    [ "$status" -eq 0 ]

    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp" --version' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_BIN"
    [ "$status" -eq 0 ]
    [ "$output" = "mainframe-mcp 10.2.0" ]

    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp-server" --version' \
        _ "$MF_PACKAGE_REPO" "$MF_PACKAGE_BIN"
    [ "$status" -eq 0 ]
    [ "$output" = "mainframe-mcp 10.2.0" ]

    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2" -I -m mainframe_mcp --version' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_PYTHON"
    [ "$status" -eq 0 ]
    [ "$output" = "mainframe-mcp 10.2.0" ]
}

@test "check binds the installed runner to the exact extracted runtime" {
    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp" --mainframe-root "$3" --check' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_BIN" "$MF_PACKAGE_RUNTIME"
    [ "$status" -eq 0 ]
    check_json="$output"

    run python3 - "$check_json" "$MF_PACKAGE_RUNTIME" <<'PY'
import json
from pathlib import Path
import re
import sys

payload = json.loads(sys.argv[1])
assert set(payload) == {
    "brokered", "functions_sha256", "integrity", "inventory_sha256",
    "manifest_sha256", "ok",
    "root", "runner_version", "runtime_version", "source", "tier",
    "tool_count",
}
assert payload["ok"] is True and payload["brokered"] is True
assert payload["runner_version"] == payload["runtime_version"] == "10.2.0"
assert payload["root"] == str(Path(sys.argv[2]).resolve())
assert payload["source"] == "command-line"
assert payload["integrity"] == "package-bound-sha256-inventory"
assert payload["tier"] == "stable-core" and payload["tool_count"] == 26
assert re.fullmatch(r"[0-9a-f]{64}", payload["functions_sha256"])
assert re.fullmatch(r"[0-9a-f]{64}", payload["inventory_sha256"])
assert re.fullmatch(r"[0-9a-f]{64}", payload["manifest_sha256"])
PY
    [ "$status" -eq 0 ]

    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2" -I -m mainframe_mcp --mainframe-root "$3" --check' \
        _ "$MF_PACKAGE_REPO" "$MF_PACKAGE_PYTHON" "$MF_PACKAGE_RUNTIME"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"tier":"stable-core"'* ]]
    [[ "$output" == *'"tool_count":26'* ]]

    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp" --mainframe-root "$3" --check' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_SDIST_BIN" "$MF_PACKAGE_RUNTIME"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"integrity":"package-bound-sha256-inventory"'* ]]
    [[ "$output" == *'"tool_count":26'* ]]

    alternate="$MF_PACKAGE_WORK/self-signed-alternate-runtime"
    run python3 - "$MF_PACKAGE_RUNTIME" "$alternate" <<'PY'
from hashlib import sha256
from pathlib import Path
import shutil
import sys

source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination)
(destination / "lib/common.sh").write_text("# self-consistent alternate\n", encoding="utf-8")
inventory = destination / "SHA256SUMS"
lines = inventory.read_text(encoding="ascii").splitlines()
records = []
for line in lines[1:]:
    if not line:
        continue
    relative = line[66:]
    records.append(f"{sha256((destination / relative).read_bytes()).hexdigest()}  {relative}")
inventory.write_text(lines[0] + "\n" + "\n".join(records) + "\n", encoding="ascii")
PY
    [ "$status" -eq 0 ]

    counterfeit_stdout="$MF_PACKAGE_WORK/counterfeit.stdout"
    counterfeit_stderr="$MF_PACKAGE_WORK/counterfeit.stderr"
    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp" --mainframe-root "$3" --check >"$4" 2>"$5"' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_BIN" "$alternate" \
        "$counterfeit_stdout" "$counterfeit_stderr"
    [ "$status" -eq 78 ]
    [ ! -s "$counterfeit_stdout" ]
    grep -Fq 'release binding' "$counterfeit_stderr"

    bypass_stdout="$MF_PACKAGE_WORK/dev-bypass.stdout"
    bypass_stderr="$MF_PACKAGE_WORK/dev-bypass.stderr"
    run bash -c 'cd "$1" && env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER "$2/mainframe-mcp" --mainframe-root "$3" --allow-development-root --check >"$4" 2>"$5"' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_BIN" "$MF_PACKAGE_RUNTIME" \
        "$bypass_stdout" "$bypass_stderr"
    [ "$status" -eq 78 ]
    [ ! -s "$bypass_stdout" ]
    grep -Fq 'release-bound' "$bypass_stderr"
}

@test "real stdio exposes exactly 26 brokered tools and denies unknown external and write calls" {
    run python3 - "$MF_PACKAGE_BIN/mainframe-mcp" "$MF_PACKAGE_RUNTIME" \
        "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_WORK" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

command, runtime, outside, work = sys.argv[1:]
hostile_bin = Path(work) / "hostile-bin"
hostile_bin.mkdir(exist_ok=True)
markers = []
for name in ("bash", "jq", "python3"):
    marker = Path(work) / f"hostile-{name}-ran"
    shim = hostile_bin / name
    shim.write_text(f"#!/bin/sh\n: > {str(marker)!r}\nexit 91\n", encoding="utf-8")
    shim.chmod(0o755)
    markers.append(marker)
write_marker = Path(work) / "write-tool-ran"

def request(identifier, method, params):
    return {"jsonrpc": "2.0", "id": identifier, "method": method, "params": params}

messages = [
    request(1, "initialize", {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "mainframe-package-test", "version": "1"},
    }),
    {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
    request(2, "tools/list", {}),
    request(3, "tools/call", {
        "name": "mainframe_json_get",
        "arguments": {"json": "{\"name\":\"Ada\"}", "key": "name"},
    }),
    request(4, "tools/call", {
        "name": "mainframe_definitely_unknown", "arguments": {},
    }),
    request(5, "tools/call", {"name": "mainframe_ls", "arguments": {}}),
    request(6, "tools/call", {
        "name": "mainframe_ensure_dir", "arguments": {"dir": str(write_marker)},
    }),
]
environment = os.environ.copy()
for key in ("PYTHONHOME", "PYTHONINSPECT", "PYTHONPATH", "PYTHONSTARTUP", "MAINFRAME_MCP_TIER"):
    environment.pop(key, None)
environment.update({"PATH": str(hostile_bin), "PYTHONUNBUFFERED": "1"})
process = subprocess.run(
    [command, "--mainframe-root", runtime],
    input="".join(json.dumps(item, separators=(",", ":")) + "\n" for item in messages),
    text=True,
    capture_output=True,
    cwd=outside,
    env=environment,
    timeout=120,
    check=False,
)
assert process.returncode == 0, (process.returncode, process.stderr)
assert "Traceback" not in process.stderr
for denied_name in (
    "mainframe_definitely_unknown", "mainframe_ls", "mainframe_ensure_dir"
):
    assert denied_name in process.stderr, process.stderr
responses = {}
for line in process.stdout.splitlines():
    message = json.loads(line)
    if message.get("id") is not None:
        assert message["id"] not in responses
        responses[message["id"]] = message
assert set(responses) == {1, 2, 3, 4, 5, 6}, responses
assert responses[1]["result"]["serverInfo"]["name"] == "mainframe-mcp-server"

expected = {
    "mainframe_array_contains", "mainframe_array_join", "mainframe_is_empty",
    "mainframe_is_numeric", "mainframe_json_array", "mainframe_json_escape",
    "mainframe_json_get", "mainframe_json_merge", "mainframe_json_object",
    "mainframe_json_string", "mainframe_json_valid", "mainframe_output_json",
    "mainframe_output_success", "mainframe_path_sanitize", "mainframe_to_lower",
    "mainframe_to_upper", "mainframe_trim_left", "mainframe_trim_right",
    "mainframe_usop_error_validation", "mainframe_validate_email",
    "mainframe_validate_int", "mainframe_validate_json", "mainframe_validate_path",
    "mainframe_validate_regex", "mainframe_validate_semver", "mainframe_validate_url",
}
tools = responses[2]["result"]["tools"]
assert len(tools) == 26
assert {tool["name"] for tool in tools} == expected
assert all(tool["inputSchema"].get("additionalProperties") is False for tool in tools)
valid = responses[3]["result"]
assert valid.get("isError", False) is False, (valid, process.stderr)
assert valid["content"][0]["text"].strip() == "Ada"
for identifier in (4, 5, 6):
    assert responses[identifier]["result"]["isError"] is True, responses[identifier]
assert not write_marker.exists()
assert not any(marker.exists() for marker in markers)
PY
    [ "$status" -eq 0 ]
}

@test "invalid mismatched and legacy-policy startup failures keep stdout empty" {
    mismatch="$MF_PACKAGE_WORK/mismatched-runtime"
    mkdir -p "$mismatch"
    run python3 "$MF_PACKAGE_REPO/scripts/dev/native-host/safe-extract.py" \
        "$MF_PACKAGE_RUNTIME_ARCHIVE" \
        "$mismatch"
    [ "$status" -eq 0 ]
    run python3 - "$mismatch/VERSION" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text("10.2.1\n", encoding="ascii")
PY
    [ "$status" -eq 0 ]

    invalid="$MF_PACKAGE_WORK/does-not-exist"
    for mode in invalid mismatch legacy; do
        stdout_file="$MF_PACKAGE_WORK/$mode.stdout"
        stderr_file="$MF_PACKAGE_WORK/$mode.stderr"
        case "$mode" in
            invalid)
                argv=("$MF_PACKAGE_BIN/mainframe-mcp" --mainframe-root "$invalid")
                tier=unset
                ;;
            mismatch)
                argv=("$MF_PACKAGE_BIN/mainframe-mcp" --mainframe-root "$mismatch")
                tier=unset
                ;;
            legacy)
                argv=("$MF_PACKAGE_BIN/mainframe-mcp" --mainframe-root "$MF_PACKAGE_RUNTIME")
                tier=stable-core
                ;;
        esac
        set +e
        if [[ "$tier" == unset ]]; then
            (
                cd "$MF_PACKAGE_OUTSIDE"
                env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER \
                    "${argv[@]}" </dev/null >"$stdout_file" 2>"$stderr_file"
            )
        else
            (
                cd "$MF_PACKAGE_OUTSIDE"
                env -u PYTHONPATH -u PYTHONHOME MAINFRAME_MCP_TIER="$tier" \
                    "${argv[@]}" </dev/null >"$stdout_file" 2>"$stderr_file"
            )
        fi
        command_status=$?
        set -e
        [ "$command_status" -eq 78 ]
        [ ! -s "$stdout_file" ]
        [ -s "$stderr_file" ]
        [ "$(wc -l < "$stderr_file" | tr -d '[:space:]')" -eq 1 ]
    done

    run env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER \
        "$MF_PACKAGE_BIN/mainframe-mcp" --tier stable-core
    [ "$status" -eq 2 ]
}

@test "hostile PYTHONPATH and local mcp shadows fail closed without import execution" {
    run python3 - "$MF_PACKAGE_BIN/mainframe-mcp" "$MF_PACKAGE_RUNTIME" \
        "$MF_PACKAGE_WORK" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

command, runtime, work = sys.argv[1:]
work = Path(work)
for label, use_pythonpath in (("pythonpath", True), ("working-directory", False)):
    shadow_root = work / f"shadow-{label}"
    shadow_package = shadow_root / "mcp"
    shadow_package.mkdir(parents=True, exist_ok=True)
    marker = work / f"shadow-{label}-imported"
    (shadow_package / "__init__.py").write_text(
        f"from pathlib import Path\nPath({str(marker)!r}).touch()\n"
        "raise RuntimeError('hostile mcp shadow imported')\n",
        encoding="utf-8",
    )
    site_marker = work / f"sitecustomize-{label}-imported"
    (shadow_root / "sitecustomize.py").write_text(
        f"from pathlib import Path\nPath({str(site_marker)!r}).touch()\n",
        encoding="utf-8",
    )
    adapter_marker = work / f"adapter-{label}-imported"
    adapter_shadow = shadow_root / "mainframe_mcp"
    adapter_shadow.mkdir()
    (adapter_shadow / "__init__.py").write_text(
        f"from pathlib import Path\nPath({str(adapter_marker)!r}).touch()\n",
        encoding="utf-8",
    )
    environment = os.environ.copy()
    for key in ("PYTHONHOME", "PYTHONINSPECT", "PYTHONPATH", "PYTHONSTARTUP", "MAINFRAME_MCP_TIER"):
        environment.pop(key, None)
    if use_pythonpath:
        environment["PYTHONPATH"] = str(shadow_root)
    process = subprocess.run(
        [command, "--mainframe-root", runtime, "--check"],
        text=True,
        capture_output=True,
        cwd=work if use_pythonpath else shadow_root,
        env=environment,
        timeout=30,
        check=False,
    )
    assert process.returncode == 0, (label, process.stdout, process.stderr)
    status = __import__("json").loads(process.stdout)
    assert status["tier"] == "stable-core" and status["tool_count"] == 26
    assert process.stderr == "", (label, process.stderr)
    for candidate in (marker, site_marker, adapter_marker):
        assert not candidate.exists(), f"hostile {label} import executed: {candidate}"
PY
    [ "$status" -eq 0 ]
}

@test "local wheel runs through uvx offline when the installed uv supports it" {
    if ! uvx --help 2>&1 | grep -q -- '--offline'; then
        skip "installed uvx does not support --offline"
    fi

    stdout_file="$MF_PACKAGE_WORK/uvx.stdout"
    stderr_file="$MF_PACKAGE_WORK/uvx.stderr"
    run bash -c 'cd "$1" && args=(--offline --no-config --no-sources --isolated --constraints "$3" --from "$2"); if [[ -n "$6" ]]; then args+=(--no-index --find-links "$6"); fi; env -u PYTHONPATH -u PYTHONHOME -u MAINFRAME_MCP_TIER UV_NO_PROGRESS=1 uvx "${args[@]}" mainframe-mcp --version >"$4" 2>"$5"' \
        _ "$MF_PACKAGE_OUTSIDE" "$MF_PACKAGE_WHEEL" \
        "$MF_PACKAGE_WORK/constraints.txt" "$stdout_file" "$stderr_file" \
        "${MAINFRAME_MCP_UVX_WHEELHOUSE:-}"
    if [ "$status" -ne 0 ] && \
        grep -Fq 'network was disabled' "$stderr_file" && \
        grep -Fq 'needs to be downloaded from a registry' "$stderr_file"; then
        if [[ "${MAINFRAME_MCP_REQUIRE_UVX_OFFLINE:-0}" != "1" ]]; then
            skip "uvx offline is supported, but its local dependency cache is incomplete"
        fi
    fi
    [ "$status" -eq 0 ]
    [ "$(cat "$stdout_file")" = "mainframe-mcp 10.2.0" ]
}

@test "uv tool public-bin symlink reaches the isolated environment launcher" {
    local tool_dir tool_bin stdout_file stderr_file marker
    local -a args
    tool_dir="$MF_PACKAGE_WORK/uv-tool-dir"
    tool_bin="$MF_PACKAGE_WORK/uv-tool-bin"
    stdout_file="$MF_PACKAGE_WORK/uv-tool.stdout"
    stderr_file="$MF_PACKAGE_WORK/uv-tool.stderr"
    marker="$MF_PACKAGE_WORK/uv-tool-sitecustomize-ran"
    mkdir -p "$tool_bin" "$MF_PACKAGE_WORK/uv-tool-shadow" \
        "$MF_PACKAGE_WORK/uv-tool-path"
    python3 - "$marker" "$MF_PACKAGE_WORK/uv-tool-shadow/sitecustomize.py" <<'PY'
from pathlib import Path
import sys

marker, destination = sys.argv[1:]
Path(destination).write_text(
    f"from pathlib import Path\nPath({marker!r}).touch()\n",
    encoding="utf-8",
)
PY
    cat > "$MF_PACKAGE_WORK/uv-tool-path/readlink" <<EOF
#!/bin/sh
: > "$MF_PACKAGE_WORK/uv-tool-hostile-readlink-ran"
exec /usr/bin/readlink "\$@"
EOF
    chmod 755 "$MF_PACKAGE_WORK/uv-tool-path/readlink"

    args=(
        --offline --no-config --no-sources
        --constraints "$MF_PACKAGE_WORK/constraints.txt"
    )
    if [[ -n "${MAINFRAME_MCP_UVX_WHEELHOUSE:-}" ]]; then
        args+=(--no-index --find-links "$MAINFRAME_MCP_UVX_WHEELHOUSE")
    fi
    run env UV_TOOL_DIR="$tool_dir" UV_TOOL_BIN_DIR="$tool_bin" \
        UV_NO_PROGRESS=1 uv tool install "${args[@]}" "$MF_PACKAGE_WHEEL"
    if [ "$status" -ne 0 ] && \
        [[ "$output" == *'network was disabled'* ]] && \
        [[ "$output" == *'needs to be downloaded from a registry'* ]]; then
        if [[ "${MAINFRAME_MCP_REQUIRE_UVX_OFFLINE:-0}" != "1" ]]; then
            skip "uv tool offline dependency cache is incomplete"
        fi
    fi
    [ "$status" -eq 0 ]
    [ -L "$tool_bin/mainframe-mcp" ]

    run env -u PYTHONHOME -u MAINFRAME_MCP_TIER \
        PATH="$MF_PACKAGE_WORK/uv-tool-path:$PATH" \
        PYTHONPATH="$MF_PACKAGE_WORK/uv-tool-shadow" \
        "$tool_bin/mainframe-mcp" --version
    [ "$status" -eq 0 ]
    [ "$output" = "mainframe-mcp 10.2.0" ]
    [ ! -e "$marker" ]
    [ ! -e "$MF_PACKAGE_WORK/uv-tool-hostile-readlink-ran" ]
}

@test "pipx persistently installs runs and removes the wheel offline" {
    local require_pipx pipx_command python_command pipx_home pipx_bin pipx_man
    local pipx_shared pipx_user_home install_backend uv_cache_dir install_output
    local install_status valid_status invalid_status
    local list_json empty_list_json valid_stdout valid_stderr
    local invalid_stdout invalid_stderr
    local hostile_root hostile_bin hostile_markers venv_python
    local -a pipx_environment installer_environment install_arguments

    require_pipx="${MAINFRAME_MCP_REQUIRE_PIPX_OFFLINE:-0}"
    if ! pipx_command="$(command -v pipx)"; then
        if [[ "$require_pipx" != "1" ]]; then
            skip "pipx is not installed"
        fi
        echo "MAINFRAME_MCP_REQUIRE_PIPX_OFFLINE=1 but pipx is unavailable" >&2
        return 1
    fi
    if ! "$pipx_command" install --help 2>&1 | grep -q -- '--backend'; then
        if [[ "$require_pipx" != "1" ]]; then
            skip "installed pipx lacks an explicitly selectable offline backend"
        fi
        echo "required pipx does not expose --backend" >&2
        return 1
    fi

    python_command="$(command -v python3)"
    pipx_home="$MF_PACKAGE_WORK/pipx-home"
    pipx_bin="$MF_PACKAGE_WORK/pipx-bin"
    pipx_man="$MF_PACKAGE_WORK/pipx-man"
    pipx_shared="$MF_PACKAGE_WORK/pipx-shared"
    pipx_user_home="$MF_PACKAGE_WORK/pipx-user-home"
    mkdir -p "$pipx_home" "$pipx_bin" "$pipx_man" "$pipx_shared" \
        "$pipx_user_home"

    pipx_environment=(
        "HOME=$pipx_user_home"
        "XDG_CACHE_HOME=$pipx_user_home/.cache"
        "XDG_CONFIG_HOME=$pipx_user_home/.config"
        "XDG_DATA_HOME=$pipx_user_home/.local/share"
        "PIPX_HOME=$pipx_home"
        "PIPX_BIN_DIR=$pipx_bin"
        "PIPX_MAN_DIR=$pipx_man"
        "PIPX_SHARED_LIBS=$pipx_shared"
        "PIPX_DEFAULT_PYTHON=$python_command"
        "PIPX_FETCH_PYTHON=never"
        "PIPX_DISABLE_SHARED_LIBS_AUTO_UPGRADE=1"
        "PIPX_USE_EMOJI=0"
    )
    installer_environment=(
        "PIP_CONFIG_FILE=/dev/null"
        "PIP_DISABLE_PIP_VERSION_CHECK=1"
    )
    install_arguments=(
        install --skip-maintenance --python "$python_command"
    )

    if [[ -n "${MAINFRAME_MCP_UVX_WHEELHOUSE:-}" ]]; then
        # CI supplies a hash-verified wheelhouse containing exactly the locked
        # candidates. The pip backend is forced to that directory twice (env
        # and argv), so pipx cannot consult an index or ambient pip config.
        install_backend=pip
        pipx_environment+=("PIPX_DEFAULT_BACKEND=pip")
        installer_environment+=(
            "PIP_NO_INDEX=1"
            "PIP_FIND_LINKS=$MAINFRAME_MCP_UVX_WHEELHOUSE"
        )
        install_arguments+=(
            --backend pip
            --pip-args "--no-index --find-links=$MAINFRAME_MCP_UVX_WHEELHOUSE --constraint=$MF_PACKAGE_WORK/constraints.txt --disable-pip-version-check"
        )
    else
        # A developer run may reuse uv's existing package cache, but it is
        # still prohibited from reaching the network. An incomplete cache is
        # the only install failure that may skip when CI requirement mode is
        # not enabled.
        if ! command -v uv >/dev/null 2>&1; then
            if [[ "$require_pipx" != "1" ]]; then
                skip "pipx offline install needs uv or the CI wheelhouse"
            fi
            echo "required pipx offline install has no uv backend" >&2
            return 1
        fi
        install_backend=uv
        uv_cache_dir="$(UV_NO_CONFIG=1 uv cache dir)"
        pipx_environment+=("PIPX_DEFAULT_BACKEND=uv")
        installer_environment+=(
            "UV_CACHE_DIR=$uv_cache_dir"
            "UV_OFFLINE=1"
            "UV_NO_CONFIG=1"
            "UV_NO_PROGRESS=1"
        )
        install_arguments+=(--backend uv)
    fi

    run env "${pipx_environment[@]}" "${installer_environment[@]}" \
        "$pipx_command" "${install_arguments[@]}" "$MF_PACKAGE_WHEEL"
    install_status=$status
    install_output=$output
    if [[ "$install_status" -ne 0 && "$require_pipx" != "1" && \
        -z "${MAINFRAME_MCP_UVX_WHEELHOUSE:-}" ]] && \
        printf '%s\n' "$install_output" | \
            grep -Eiq 'offline|cache|network was disabled|needs to be downloaded|not found'; then
        skip "pipx is present, but its offline uv dependency cache is incomplete"
    fi
    if [[ "$install_status" -ne 0 ]]; then
        printf '%s\n' "$install_output" >&2
        return "$install_status"
    fi

    [ -L "$pipx_bin/mainframe-mcp" ]
    [ -L "$pipx_bin/mainframe-mcp-server" ]
    [ -x "$pipx_bin/mainframe-mcp" ]
    [ -x "$pipx_bin/mainframe-mcp-server" ]
    [ ! -e "$pipx_bin/mcp" ]
    venv_python="$pipx_home/venvs/mainframe-mcp/bin/python"
    [ -x "$venv_python" ]

    list_json="$MF_PACKAGE_WORK/pipx-list.json"
    run env "${pipx_environment[@]}" "$pipx_command" list \
        --skip-maintenance --json
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" > "$list_json"
    run python3 - "$list_json" "$install_backend" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["pipx_spec_version"] == "0.1"
assert set(payload["venvs"]) == {"mainframe-mcp"}
metadata = payload["venvs"]["mainframe-mcp"]["metadata"]
package = metadata["main_package"]
assert metadata["backend"] == sys.argv[2]
assert package["package"] == "mainframe-mcp"
assert package["package_version"] == "10.2.0"
assert package["apps"] == ["mainframe-mcp", "mainframe-mcp-server"]
assert package["include_dependencies"] is False
PY
    [ "$status" -eq 0 ]

    # Prove the isolated environment contains upstream `mcp` 1.26.0 and the
    # adapter under separate top-level names. This catches a distribution that
    # accidentally vendors or shadows the SDK even if its shim still starts.
    run "$venv_python" -I - "$pipx_home/venvs/mainframe-mcp" <<'PY'
from importlib import metadata
from pathlib import Path
import sys

environment = Path(sys.argv[1]).resolve()
import mcp
import mainframe_mcp

mcp_distribution = metadata.distribution("mcp")
adapter_distribution = metadata.distribution("mainframe-mcp")
assert mcp_distribution.version == "1.26.0"
assert adapter_distribution.version == "10.2.0"
mcp_origin = Path(mcp.__file__).resolve()
adapter_origin = Path(mainframe_mcp.__file__).resolve()
assert environment in mcp_origin.parents
assert environment in adapter_origin.parents
assert mcp_origin.parent.name == "mcp"
assert adapter_origin.parent.name == "mainframe_mcp"
assert mcp_origin != adapter_origin
adapter_roots = {
    path.parts[0] for path in (adapter_distribution.files or ()) if path.parts
}
mcp_roots = {
    path.parts[0] for path in (mcp_distribution.files or ()) if path.parts
}
assert "mcp" not in adapter_roots
assert "mainframe_mcp" not in mcp_roots
PY
    [ "$status" -eq 0 ]

    hostile_root="$MF_PACKAGE_WORK/pipx-hostile-cwd"
    hostile_bin="$MF_PACKAGE_WORK/pipx-hostile-bin"
    hostile_markers="$MF_PACKAGE_WORK/pipx-hostile-markers"
    mkdir -p "$hostile_root/mcp" "$hostile_root/mainframe_mcp" \
        "$hostile_bin" "$hostile_markers"
    run python3 - "$hostile_root" "$hostile_bin" "$hostile_markers" <<'PY'
from pathlib import Path
import sys

root, hostile_bin, markers = map(Path, sys.argv[1:])
for package in ("mcp", "mainframe_mcp"):
    (root / package / "__init__.py").write_text(
        "from pathlib import Path\n"
        f"Path({str(markers / (package + '-imported'))!r}).touch()\n"
        "raise RuntimeError('hostile package imported')\n",
        encoding="utf-8",
    )
(root / "sitecustomize.py").write_text(
    "from pathlib import Path\n"
    f"Path({str(markers / 'sitecustomize-imported')!r}).touch()\n",
    encoding="utf-8",
)
(root / "startup.py").write_text(
    "from pathlib import Path\n"
    f"Path({str(markers / 'startup-imported')!r}).touch()\n",
    encoding="utf-8",
)
for command in ("python", "python3", "readlink"):
    marker = markers / f"hostile-{command}-ran"
    destination = hostile_bin / command
    destination.write_text(
        f"#!/bin/sh\n: > {str(marker)!r}\nexit 91\n",
        encoding="utf-8",
    )
    destination.chmod(0o755)
PY
    [ "$status" -eq 0 ]

    valid_stdout="$MF_PACKAGE_WORK/pipx-valid.stdout"
    valid_stderr="$MF_PACKAGE_WORK/pipx-valid.stderr"
    run bash -c '
        cd "$1" || exit
        /usr/bin/env -u MAINFRAME_MCP_TIER \
            HOME="$2" PATH="$3" PYTHONHOME="$1" PYTHONINSPECT=1 \
            PYTHONPATH="$1" PYTHONSTARTUP="$1/startup.py" \
            "$4" --mainframe-root "$5" --check >"$6" 2>"$7"
    ' _ "$hostile_root" "$pipx_user_home" "$hostile_bin" \
        "$pipx_bin/mainframe-mcp" "$MF_PACKAGE_RUNTIME" \
        "$valid_stdout" "$valid_stderr"
    valid_status=$status
    [ "$valid_status" -eq 0 ]
    [ ! -s "$valid_stderr" ]
    [ "$(wc -l < "$valid_stdout" | tr -d '[:space:]')" -eq 1 ]
    run python3 - "$valid_stdout" "$MF_PACKAGE_RUNTIME" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["ok"] is True and payload["brokered"] is True
assert payload["runner_version"] == payload["runtime_version"] == "10.2.0"
assert payload["root"] == str(Path(sys.argv[2]).resolve())
assert payload["integrity"] == "package-bound-sha256-inventory"
assert payload["tier"] == "stable-core" and payload["tool_count"] == 26
PY
    [ "$status" -eq 0 ]
    [ -z "$(find "$hostile_markers" -mindepth 1 -print -quit)" ]

    # A strict-runtime failure must not emit a byte that an MCP client could
    # misread as protocol output.
    invalid_stdout="$MF_PACKAGE_WORK/pipx-invalid.stdout"
    invalid_stderr="$MF_PACKAGE_WORK/pipx-invalid.stderr"
    run bash -c '
        cd "$1" || exit
        /usr/bin/env -u MAINFRAME_MCP_TIER \
            HOME="$2" PATH="$3" PYTHONHOME="$1" PYTHONPATH="$1" \
            "$4" --mainframe-root "$5" --check >"$6" 2>"$7"
    ' _ "$hostile_root" "$pipx_user_home" "$hostile_bin" \
        "$pipx_bin/mainframe-mcp" "$MF_PACKAGE_OUTSIDE" \
        "$invalid_stdout" "$invalid_stderr"
    invalid_status=$status
    [ "$invalid_status" -eq 78 ]
    [ ! -s "$invalid_stdout" ]
    [ "$(wc -l < "$invalid_stderr" | tr -d '[:space:]')" -eq 1 ]
    grep -Fq 'mainframe-mcp: configuration error:' "$invalid_stderr"
    [ -z "$(find "$hostile_markers" -mindepth 1 -print -quit)" ]

    run env "${pipx_environment[@]}" "$pipx_command" uninstall \
        --skip-maintenance mainframe-mcp
    [ "$status" -eq 0 ]
    [ ! -d "$pipx_home/venvs/mainframe-mcp" ]
    [ ! -e "$pipx_bin/mainframe-mcp" ]
    [ ! -L "$pipx_bin/mainframe-mcp" ]
    [ ! -e "$pipx_bin/mainframe-mcp-server" ]
    [ ! -L "$pipx_bin/mainframe-mcp-server" ]

    empty_list_json="$MF_PACKAGE_WORK/pipx-empty-list.json"
    env "${pipx_environment[@]}" "$pipx_command" list \
        --skip-maintenance --quiet --json >"$empty_list_json" 2>/dev/null
    run python3 - "$empty_list_json" <<'PY'
import json
from pathlib import Path
import sys
assert json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["venvs"] == {}
PY
    [ "$status" -eq 0 ]
}

@test "workflow separates unprivileged build and execution from tag-only attestation" {
    run python3 - "$MF_PACKAGE_REPO/.github/workflows/test.yml" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def job(name):
    match = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        text,
    )
    assert match, f"missing workflow job {name}"
    return match.group(1)

build = job("mcp-package-build")
test = job("mcp-package-test")
attest = job("mcp-package-attestation")
identity = job("release-tag-identity")
release = job("release-build")

for name, block in (("build", build), ("test", test)):
    assert "permissions:\n      contents: read" in block, name
    assert "persist-credentials: false" in block, name
    assert "actions/checkout@11d5960a326750d5838078e36cf38b85af677262" in block, name
    assert "actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065" in block, name
    assert "astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b" in block, name
    assert "version: '0.11.32'" in block, name
    assert "id-token: write" not in block, name
    assert "attestations: write" not in block, name
    assert "contents: write" not in block, name
    assert "uv publish" not in block and "twine upload" not in block, name

assert "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02" in build
assert "scripts/dev/release.sh --prepare" in build
assert ".github/scripts/build-mcp-package.py" in build
assert build.index("scripts/dev/release.sh --prepare") < build.index("build-mcp-package.py")

assert "needs: mcp-package-build" in test
assert "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093" in test
assert "merge-multiple: true" in test
assert "Install modern Bash (macOS)" in test
assert "if: matrix.os == 'macos-latest'" in test
assert 'MAINFRAME_BASH=$(brew --prefix bash)/bin/bash' in test
assert "tests/mcp_package.bats" in test
assert "MAINFRAME_MCP_PACKAGE_ARTIFACT_DIR:" in test
assert "MAINFRAME_MCP_RUNTIME_ARCHIVE:" in test
assert "MAINFRAME_MCP_REQUIRE_UVX_OFFLINE: '1'" in test
assert "MAINFRAME_MCP_REQUIRE_PIPX_OFFLINE: '1'" in test
assert "MAINFRAME_MCP_UVX_WHEELHOUSE:" in test
assert "pip download" in test and "--require-hashes" in test

assert "startsWith(github.ref, 'refs/tags/v')" in attest
assert "needs: [mcp-package-build, mcp-package-test, release-tag-identity]" in attest
assert "id-token: write" in attest and "attestations: write" in attest
assert "actions/download-artifact@" in attest
assert "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093" in attest
assert "merge-multiple: true" in attest
assert "actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d" in attest
assert "actions/checkout@" not in attest
assert re.search(r"(?m)^      - name: .*\n        run:", attest) is None
assert "mainframe-mcp" in attest

assert "permissions:\n      contents: read" in identity
assert "id-token: write" not in identity and "attestations: write" not in identity
assert "persist-credentials: false" in identity
assert "fetch-depth: 0" in identity
assert 'test "${{ github.event.created }}" = true' in identity
assert 'test "$GITHUB_REF" = "refs/tags/v$version"' in identity
assert 'git merge-base --is-ancestor "$tag_commit" refs/remotes/origin/main' in identity

needs = re.search(r"(?m)^    needs: \[(.*?)\]$", release)
assert needs and "mcp-package-attestation" in needs.group(1).split(", ")
assert "release-tag-identity" in needs.group(1).split(", ")
assert "artifact-ids: ${{ needs.mcp-package-attestation.outputs.candidate_artifact_id }}" in release
assert "merge-multiple: true" in release
assert "name: mainframe-mcp-candidate-${{ github.sha }}" not in release
verify_candidate = "Verify exact MCP release candidate"
verify_provenance = "Verify exact MCP package provenance"
stage_assets = "Stage provenance-verified MCP release assets"
for step_name in (verify_candidate, verify_provenance, stage_assets):
    assert step_name in release
assert release.index(verify_candidate) < release.index(verify_provenance)
assert release.index(verify_provenance) < release.index(stage_assets)
assert "MCP-tested runtime differs from release runtime" in release
assert "EXPECTED_RUNTIME_INVENTORY_SHA256" in release
assert not re.search(r"(?m)^\s+(uv publish|twine upload)\b", text)
PY
    [ "$status" -eq 0 ]
}

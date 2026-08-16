#!/usr/bin/env bats

# Exact installed-candidate AWM handoff mechanism canary. The shared fixture
# builds one temporary release archive and runs each shell once; every test
# thereafter verifies or adversarially mutates those private local records.

setup_file() {
    local repo_root work python_bin bash_bin archive checksum proof_source
    local version shell_name cell_root private_output public_output

    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    work="$BATS_FILE_TMPDIR/mainframe-installed-awm-handoff"
    mkdir -p "$work"
    work="$(cd "$work" && pwd -P)"
    chmod 700 "$work"
    # Keep the canary's Python-floor proof separate from the release builder's
    # independently reviewed Python 3.10+ runtime selection.
    python_bin="${MAINFRAME_CANARY_PYTHON:-$(command -v python3)}"
    bash_bin="${MAINFRAME_BASH:-$(command -v bash)}"
    [[ -x "$python_bin" && -x "$bash_bin" ]]

    if [[ "${MAINFRAME_INSTALLED_AWM_SKIP_DYNAMIC_SETUP:-0}" == "1" ]]; then
        {
            printf 'export CANARY_REPO=%q\n' "$repo_root"
            printf 'export CANARY_WORK=%q\n' "$work"
            printf 'export CANARY_PYTHON=%q\n' "$python_bin"
            printf 'export CANARY_BASH=%q\n' "$bash_bin"
            printf 'export CANARY_DYNAMIC_READY=0\n'
        } > "$work/fixture.env"
        return 0
    fi

    for required in \
        scripts/dev/certify-installed-awm-handoff.py \
        evals/agent-impact/installed-awm-handoff-private.schema.json \
        evals/agent-impact/installed-awm-handoff-evidence.schema.json \
        docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md; do
        [[ -f "$repo_root/$required" && ! -L "$repo_root/$required" ]]
    done

    if [[ -n "${MAINFRAME_INSTALLED_AWM_TEST_ARCHIVE:-}" ]]; then
        archive="$MAINFRAME_INSTALLED_AWM_TEST_ARCHIVE"
        checksum="${MAINFRAME_INSTALLED_AWM_TEST_CHECKSUM:?checksum is required with a supplied archive}"
        [[ "$archive" == /* && "$checksum" == /* ]]
        [[ -f "$archive" && ! -L "$archive" ]]
        [[ -f "$checksum" && ! -L "$checksum" ]]
    else
        mkdir -p "$work/release"
        SOURCE_DATE_EPOCH=0 MAINFRAME_BASH="$bash_bin" \
            "$bash_bin" --noprofile --norc -p \
            "$repo_root/scripts/build-release-archive.sh" \
            --output-dir "$work/release" >/dev/null
        version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
        archive="$work/release/mainframe-${version}.tar.gz"
        checksum="${archive}.sha256"
    fi

    proof_source="$work/extracted-candidate"
    mkdir -p "$proof_source"
    "$python_bin" -I -S -B \
        "$repo_root/scripts/dev/native-host/safe-extract.py" \
        "$archive" "$proof_source"
    [[ -x "$proof_source/scripts/dev/certify-installed-awm-handoff.py" ]]

    mkdir -p "$work/caller-home" "$work/tmp"
    chmod 700 "$work/caller-home" "$work/tmp"
    for shell_name in bash zsh; do
        if ! command -v "$shell_name" >/dev/null 2>&1; then
            continue
        fi
        cell_root="$work/$shell_name"
        mkdir -p "$cell_root"
        chmod 700 "$cell_root"
        private_output="$cell_root/private.json"
        public_output="$cell_root/public.json"
        HOME="$work/caller-home" TMPDIR="$work/tmp" \
            "$python_bin" -I -S -B \
            "$proof_source/scripts/dev/certify-installed-awm-handoff.py" run \
            --archive "$archive" \
            --checksum "$checksum" \
            --shell "$shell_name" \
            --private-output "$private_output" \
            --output "$public_output"
    done

    {
        printf 'export CANARY_REPO=%q\n' "$repo_root"
        printf 'export CANARY_WORK=%q\n' "$work"
        printf 'export CANARY_PYTHON=%q\n' "$python_bin"
        printf 'export CANARY_BASH=%q\n' "$bash_bin"
        printf 'export CANARY_ARCHIVE=%q\n' "$archive"
        printf 'export CANARY_CHECKSUM=%q\n' "$checksum"
        printf 'export CANARY_SOURCE=%q\n' "$proof_source"
        printf 'export CANARY_DYNAMIC_READY=1\n'
    } > "$work/fixture.env"
}

setup() {
    # shellcheck disable=SC1091 # Created by setup_file in the Bats file root.
    source "$BATS_FILE_TMPDIR/mainframe-installed-awm-handoff/fixture.env"
    CANARY_TOOL="$CANARY_SOURCE/scripts/dev/certify-installed-awm-handoff.py"
    CANARY_PRIVATE_SCHEMA="$CANARY_SOURCE/evals/agent-impact/installed-awm-handoff-private.schema.json"
    CANARY_PUBLIC_SCHEMA="$CANARY_SOURCE/evals/agent-impact/installed-awm-handoff-evidence.schema.json"
    TEST_DIR="$(mktemp -d "$BATS_TEST_TMPDIR/case.XXXXXX")"
    chmod 700 "$TEST_DIR"
    mkdir -p "$TEST_DIR/home" "$TEST_DIR/tmp"
    chmod 700 "$TEST_DIR/home" "$TEST_DIR/tmp"
}

require_dynamic() {
    [[ "${CANARY_DYNAMIC_READY:-0}" == "1" ]] || \
        skip "dynamic installed-candidate setup was explicitly disabled"
}

mode_of() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

sha256_of() {
    "$CANARY_PYTHON" -I -S -B - "$1" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys
print(sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

canary() {
    HOME="$TEST_DIR/home" TMPDIR="$TEST_DIR/tmp" \
        "$CANARY_PYTHON" -I -S -B "$CANARY_TOOL" "$@"
}

verify_cell() {
    local shell_name="$1"
    canary verify \
        --archive "$CANARY_ARCHIVE" \
        --checksum "$CANARY_CHECKSUM" \
        --shell "$shell_name" \
        --private-evidence "$CANARY_WORK/$shell_name/private.json" \
        --evidence "$CANARY_WORK/$shell_name/public.json"
}

mutate_private() {
    local source="$1" destination="$2" mutation="$3"
    "$CANARY_PYTHON" -I -S -B - \
        "$source" "$destination" "$mutation" <<'PY'
import json
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
mutation = sys.argv[3]
value = json.loads(source.read_text(encoding="utf-8"))
if mutation == "process-order":
    value["processes"][0]["sequence"] = 2
elif mutation == "duplicate-pid":
    value["processes"][1]["pid"] = value["processes"][0]["pid"]
elif mutation == "source-count":
    value["measurements"]["source_fact_occurrences_treatment"] = 2
elif mutation == "envelope-parity":
    value["measurements"]["neutral_envelopes_equal"] = False
elif mutation == "final-tree":
    value["measurements"]["final_trees_equal"] = False
elif mutation == "score":
    value["measurements"]["treatment_score"] = 99
elif mutation == "provider-count":
    value["execution"]["certifier_issued_provider_requests"] = 1
elif mutation == "platform":
    value["platform"]["id"] = (
        "Darwin-arm64-none"
        if value["platform"]["id"] == "Linux-x86_64-glibc"
        else "Linux-x86_64-glibc"
    )
elif mutation == "shell-version-path":
    value["shell"]["version"] = "/opt/secret-runtime"
elif mutation == "relocated-shell-output":
    source_path = Path(value["processes"][0]["stdout"]["path"])
    relocated = source_path.parents[1] / "rogue-shell.stdout"
    relocated.write_bytes(source_path.read_bytes())
    relocated.chmod(0o600)
    value["processes"][0]["stdout"]["path"] = str(relocated)
elif mutation == "aliased-awm-snapshot":
    value["mechanisms"]["treatment"]["awm_after_ensure"] = dict(
        value["mechanisms"]["treatment"]["awm_before"]
    )
elif mutation == "handoff-stdout-unbound":
    from hashlib import sha256
    record = value["processes"][3]
    stdout_path = Path(record["stdout"]["path"])
    payload = ("CANARY_PID={}\n".format(record["pid"])).encode("ascii")
    stdout_path.write_bytes(payload)
    stdout_path.chmod(0o600)
    record["stdout"]["size_bytes"] = len(payload)
    record["stdout"]["sha256"] = sha256(payload).hexdigest()
elif mutation == "handoff-stdout-unbound":
    record = value["processes"][3]
    stdout_path = Path(record["stdout"]["path"])
    payload = ("CANARY_PID={}\n".format(record["pid"])).encode("ascii")
    stdout_path.write_bytes(payload)
    stdout_path.chmod(0o600)
    from hashlib import sha256
    record["stdout"]["size_bytes"] = len(payload)
    record["stdout"]["sha256"] = sha256(payload).hexdigest()
else:
    raise SystemExit("unknown private mutation: " + mutation)
payload = json.dumps(
    value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    allow_nan=False,
).encode("ascii") + b"\n"
destination.write_bytes(payload)
destination.chmod(0o600)
PY
}

mutate_public() {
    local source="$1" destination="$2" mutation="$3"
    "$CANARY_PYTHON" -I -S -B - \
        "$source" "$destination" "$mutation" <<'PY'
import json
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
mutation = sys.argv[3]
value = json.loads(source.read_text(encoding="utf-8"))
if mutation == "claim":
    value["claim_scope"] = "agent-benefit-proven"
elif mutation == "extra-key":
    value["private_path"] = "/tmp/private"
elif mutation == "absolute-value":
    value["shell"]["version"] = "/tmp/private-shell"
elif mutation == "archive":
    value["candidate"]["archive_sha256"] = "0" * 64
elif mutation == "execution":
    value["execution"]["certifier_started_live_agent_sessions"] = 1
else:
    raise SystemExit("unknown public mutation: " + mutation)
payload = json.dumps(
    value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    allow_nan=False,
).encode("ascii") + b"\n"
destination.write_bytes(payload)
destination.chmod(0o644)
PY
}

mutate_private_in_place() {
    local target="$1" mutation="$2"
    "$CANARY_PYTHON" -I -S -B - "$target" "$mutation" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
mutation = sys.argv[2]
value = json.loads(path.read_text(encoding="utf-8"))
if mutation == "process-order":
    value["processes"][0]["sequence"] = 2
elif mutation == "duplicate-pid":
    value["processes"][1]["pid"] = value["processes"][0]["pid"]
elif mutation == "source-count":
    value["measurements"]["source_fact_occurrences_treatment"] = 2
elif mutation == "envelope-parity":
    value["measurements"]["neutral_envelopes_equal"] = False
elif mutation == "final-tree":
    value["measurements"]["final_trees_equal"] = False
elif mutation == "score":
    value["measurements"]["treatment_score"] = 99
elif mutation == "provider-count":
    value["execution"]["certifier_issued_provider_requests"] = 1
elif mutation == "platform":
    value["platform"]["id"] = (
        "Darwin-arm64-none"
        if value["platform"]["id"] == "Linux-x86_64-glibc"
        else "Linux-x86_64-glibc"
    )
elif mutation == "shell-version-path":
    value["shell"]["version"] = "/opt/secret-runtime"
elif mutation == "relocated-shell-output":
    source_path = Path(value["processes"][0]["stdout"]["path"])
    relocated = source_path.parents[1] / "rogue-shell.stdout"
    relocated.write_bytes(source_path.read_bytes())
    relocated.chmod(0o600)
    value["processes"][0]["stdout"]["path"] = str(relocated)
elif mutation == "aliased-awm-snapshot":
    value["mechanisms"]["treatment"]["awm_after_ensure"] = dict(
        value["mechanisms"]["treatment"]["awm_before"]
    )
elif mutation == "handoff-stdout-unbound":
    from hashlib import sha256
    record = value["processes"][3]
    stdout_path = Path(record["stdout"]["path"])
    payload = ("CANARY_PID={}\n".format(record["pid"])).encode("ascii")
    stdout_path.write_bytes(payload)
    stdout_path.chmod(0o600)
    record["stdout"]["size_bytes"] = len(payload)
    record["stdout"]["sha256"] = sha256(payload).hexdigest()
else:
    raise SystemExit("unknown private mutation: " + mutation)
payload = json.dumps(
    value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    allow_nan=False,
).encode("ascii") + b"\n"
path.write_bytes(payload)
path.chmod(0o600)
PY
}

tree_identity() {
    "$CANARY_PYTHON" -I -S -B - "$1" <<'PY'
from hashlib import sha256
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
digest = sha256(b"MAINFRAME-TEST-NO-WRITE-V1\0")
for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
    metadata = path.lstat()
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(relative + b"\0")
    digest.update(str(stat.S_IMODE(metadata.st_mode)).encode("ascii") + b"\0")
    digest.update(str(metadata.st_mtime_ns).encode("ascii") + b"\0")
    if path.is_symlink():
        digest.update(b"L\0" + os.readlink(path).encode("utf-8"))
    elif path.is_file():
        payload = path.read_bytes()
        digest.update(b"F\0" + str(len(payload)).encode("ascii") + b"\0" + payload)
    elif path.is_dir():
        digest.update(b"D\0")
    else:
        digest.update(b"S\0")
print(digest.hexdigest())
PY
}

@test "CLI schemas and documentation close the exact mechanism-only contract" {
    local tool="$CANARY_REPO/scripts/dev/certify-installed-awm-handoff.py"
    local private_schema="$CANARY_REPO/evals/agent-impact/installed-awm-handoff-private.schema.json"
    local public_schema="$CANARY_REPO/evals/agent-impact/installed-awm-handoff-evidence.schema.json"
    local doc="$CANARY_REPO/docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md"

    run "$CANARY_PYTHON" -I -S -B "$tool" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'{run,verify}'* ]]
    run "$CANARY_PYTHON" -I -S -B "$tool" run --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--archive'* ]]
    [[ "$output" == *'--checksum'* ]]
    [[ "$output" == *'--shell'* ]]
    [[ "$output" == *'--private-output'* ]]
    [[ "$output" == *'--output'* ]]
    run "$CANARY_PYTHON" -I -S -B "$tool" verify --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'--private-evidence'* ]]
    [[ "$output" == *'--evidence'* ]]
    [[ "$output" == *'--shell'* ]]

    run "$CANARY_PYTHON" -I -S -B - \
        "$tool" "$private_schema" "$public_schema" "$doc" <<'PY'
import ast
import json
from pathlib import Path
import sys

tool_path, private_path, public_path, doc_path = map(Path, sys.argv[1:])
ast.parse(tool_path.read_text(encoding="utf-8"))
private = json.loads(private_path.read_text(encoding="utf-8"))
public = json.loads(public_path.read_text(encoding="utf-8"))
doc = doc_path.read_text(encoding="utf-8")
claim = "installed-candidate-awm-handoff-mechanism-conformance-only"
assert private["properties"]["claim_scope"]["const"] == claim
assert public["properties"]["claim_scope"]["const"] == claim
assert private["additionalProperties"] is False
assert public["additionalProperties"] is False
assert len(private["required"]) == len(set(private["required"])) == 13
assert len(public["required"]) == len(set(public["required"])) == 13
assert public["$defs"]["mechanism"]["properties"]["control"]["const"] == (
    "native-bounded-continuation"
)
assert public["$defs"]["mechanism"]["properties"]["treatment"]["const"] == (
    "installed-mainframe-project-awm-handoff"
)
non_claims = public["$defs"]["nonClaims"]["properties"]
assert private["$defs"]["candidate"]["properties"]["installed_payload"]["const"] == (
    "authenticated-release-files-private-staging"
)
assert public["$defs"]["candidate"]["properties"]["installed_payload"]["const"] == (
    "authenticated-release-files-private-staging"
)
assert non_claims["mainframe_benefit"]["const"] == "not-measured"
assert non_claims["agent_quality"]["const"] == "not-measured"
assert non_claims["developer_productivity"]["const"] == "not-measured"
assert non_claims["real_provider_inference"]["const"] == "not-run"
assert non_claims["same_local_account_isolation"]["const"] == "not-established"
assert claim in doc
assert "It does not inspect the machine process table" in doc
assert "does not authorize a provider run" in doc
PY
    [[ "$status" -eq 0 ]]
}

@test "native architecture helpers reject translation, mixed hosts, binary mismatch, and binding drift" {
    local tool="$CANARY_REPO/scripts/dev/certify-installed-awm-handoff.py"

    run "$CANARY_PYTHON" -I -S -B - "$tool" "$TEST_DIR" <<'PY'
import ctypes
import errno
import importlib.util
from pathlib import Path
import struct
import sys

tool, root = map(Path, sys.argv[1:])
tool = tool.resolve(strict=True)
root = root.resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_native_architecture", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def expect_refusal(callback, expected):
    try:
        callback()
    except module.CanaryError as error:
        message = str(error)
        assert expected in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("expected refusal containing: " + expected)


class FakeSysctl:
    def __init__(self, result, value=0, size=None, error_number=0):
        self.result = result
        self.value = value
        self.size = ctypes.sizeof(ctypes.c_int) if size is None else size
        self.error_number = error_number
        self.argtypes = None
        self.restype = None

    def __call__(self, _name, value_pointer, size_pointer, _new, _new_size):
        ctypes.cast(value_pointer, ctypes.POINTER(ctypes.c_int))[0] = self.value
        ctypes.cast(size_pointer, ctypes.POINTER(ctypes.c_size_t))[0] = self.size
        ctypes.set_errno(self.error_number)
        return self.result


class FakeLibc:
    def __init__(self, probe):
        self.sysctlbyname = probe


real_cdll = module.ctypes.CDLL
try:
    probe = FakeSysctl(0, value=1)
    module.ctypes.CDLL = lambda *_args, **_kwargs: FakeLibc(probe)
    assert module._darwin_sysctl_int("sysctl.proc_translated") == 1
    assert probe.argtypes is not None
    assert probe.restype is ctypes.c_int

    probe = FakeSysctl(-1, error_number=errno.ENOENT)
    module.ctypes.CDLL = lambda *_args, **_kwargs: FakeLibc(probe)
    assert module._darwin_sysctl_int("sysctl.proc_translated") is None

    probe = FakeSysctl(0, value=2)
    module.ctypes.CDLL = lambda *_args, **_kwargs: FakeLibc(probe)
    expect_refusal(
        lambda: module._darwin_sysctl_int("sysctl.proc_translated"),
        "Darwin native-state probe sysctl.proc_translated is malformed")
finally:
    module.ctypes.CDLL = real_cdll


real_system = module.platform.system
real_machine = module.platform.machine
real_probe = module._darwin_sysctl_int
try:
    module.platform.system = lambda: "Darwin"
    module.platform.machine = lambda: "x86_64"
    module._darwin_sysctl_int = lambda name: {
        "sysctl.proc_translated": 1,
        "hw.optional.arm64": 1,
    }[name]
    expect_refusal(module.current_platform, "translated under Rosetta")

    module._darwin_sysctl_int = lambda name: {
        "sysctl.proc_translated": 0,
        "hw.optional.arm64": 1,
    }[name]
    expect_refusal(
        module.current_platform,
        "x86_64 process is running on Apple Silicon")

    module._darwin_sysctl_int = lambda name: {
        "sysctl.proc_translated": None,
        "hw.optional.arm64": 0,
    }[name]
    assert module.current_platform() == {
        "id": "Darwin-x86_64-none", "os": "Darwin",
        "architecture": "x86_64", "system_libc": "none",
    }

    module.platform.machine = lambda: "arm64"
    module._darwin_sysctl_int = lambda name: {
        "sysctl.proc_translated": 0,
        "hw.optional.arm64": 1,
    }[name]
    assert module.current_platform() == {
        "id": "Darwin-arm64-none", "os": "Darwin",
        "architecture": "arm64", "system_libc": "none",
    }
finally:
    module.platform.system = real_system
    module.platform.machine = real_machine
    module._darwin_sysctl_int = real_probe


def elf(machine):
    value = bytearray(64)
    value[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<H", value, 16, 2)
    struct.pack_into("<H", value, 18, machine)
    struct.pack_into("<I", value, 20, 1)
    struct.pack_into("<H", value, 52, 64)
    struct.pack_into("<H", value, 54, 56)
    struct.pack_into("<H", value, 58, 64)
    return bytes(value)


def macho(cpu_type):
    return struct.pack(
        "<IIIIIIII", 0xFEEDFACF, cpu_type, 0, 2, 0, 0, 0, 0)


def universal_macho(cpu_types):
    table_size = 8 + 20 * len(cpu_types)
    slices = [macho(cpu_type) for cpu_type in cpu_types]
    table = [struct.pack(">II", 0xCAFEBABE, len(cpu_types))]
    offset = table_size
    for cpu_type, payload in zip(cpu_types, slices):
        table.append(struct.pack(">IIIII", cpu_type, 0, offset, len(payload), 0))
        offset += len(payload)
    return b"".join(table + slices)


CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C
thin_x86 = macho(CPU_X86_64)
thin_arm = macho(CPU_ARM64)
fat_x86 = universal_macho([CPU_X86_64])
fat_both = universal_macho([CPU_X86_64, CPU_ARM64])
elf_x86 = elf(62)
elf_arm = elf(183)

crossing_slice = struct.pack(
    "<IIIIIIII", 0xFEEDFACF, CPU_X86_64, 0, 2, 1, 64, 0, 0)
fat_crossing = b"".join((
    struct.pack(">II", 0xCAFEBABE, 1),
    struct.pack(">IIIII", CPU_X86_64, 0, 28, len(crossing_slice), 0),
    crossing_slice,
    b"\0" * 64,
))
fat_duplicate = b"".join((
    struct.pack(">II", 0xCAFEBABE, 2),
    struct.pack(">IIIII", CPU_X86_64, 0, 48, len(thin_x86), 0),
    struct.pack(">IIIII", CPU_X86_64, 0, 48, len(thin_x86), 0),
    thin_x86,
))
elf_bad_program_table = bytearray(elf_x86)
struct.pack_into("<Q", elf_bad_program_table, 32, 4096)
struct.pack_into("<H", elf_bad_program_table, 56, 1)

assert module.binary_identity(thin_x86, "thin x86") == ("mach-o", {"x86_64"})
assert module.binary_identity(thin_arm, "thin arm") == ("mach-o", {"arm64"})
assert module.binary_identity(fat_x86, "fat x86") == (
    "mach-o-universal", {"x86_64"})
assert module.binary_identity(fat_both, "fat universal") == (
    "mach-o-universal", {"x86_64", "arm64"})
assert module.binary_identity(elf_x86, "ELF x86") == ("elf", {"x86_64"})
assert module.binary_identity(elf_arm, "ELF arm") == ("elf", {"arm64"})
expect_refusal(
    lambda: module.binary_identity(fat_crossing, "crossing universal"),
    "crossing universal has invalid Mach-O load-command bounds")
expect_refusal(
    lambda: module.binary_identity(fat_duplicate, "duplicate universal"),
    "duplicate universal has overlapping universal Mach-O slices")
expect_refusal(
    lambda: module.binary_identity(bytes(elf_bad_program_table), "bounded ELF"),
    "bounded ELF has invalid ELF program-header bounds")

darwin_arm = {
    "id": "Darwin-arm64-none", "os": "Darwin",
    "architecture": "arm64", "system_libc": "none",
}
linux_x86 = {
    "id": "Linux-x86_64-glibc", "os": "Linux",
    "architecture": "x86_64", "system_libc": "glibc",
}
assert module.require_observed_executable_architecture(
    {"payload": thin_arm}, darwin_arm, "thin shell") == {
        "format": "mach-o", "architectures": ["arm64"], "selected": "arm64",
    }
assert module.require_observed_executable_architecture(
    {"payload": fat_both}, darwin_arm, "universal shell") == {
        "format": "mach-o-universal",
        "architectures": ["arm64", "x86_64"], "selected": "arm64",
    }
assert module.require_observed_executable_architecture(
    {"payload": elf_x86}, linux_x86, "Linux shell") == {
        "format": "elf", "architectures": ["x86_64"], "selected": "x86_64",
    }
expect_refusal(
    lambda: module.require_observed_executable_architecture(
        {"payload": thin_x86}, darwin_arm, "thin shell"),
    "thin shell does not contain the native arm64 architecture")
expect_refusal(
    lambda: module.require_observed_executable_architecture(
        {"payload": fat_x86}, darwin_arm, "universal shell"),
    "universal shell does not contain the native arm64 architecture")
expect_refusal(
    lambda: module.require_observed_executable_architecture(
        {"payload": elf_arm}, linux_x86, "Linux shell"),
    "Linux shell does not contain the native x86_64 architecture")

binary = root / "native-shell"
binary.write_bytes(elf_x86)
binary.chmod(0o700)
binding = module.bind_native_executable(
    binary, linux_x86, "selected shell")
assert module.bind_native_executable(
    binary, linux_x86, "selected shell", binding) == binding
for accepted_mode in (0o755, 0o555, 0o700):
    binary.chmod(accepted_mode)
    module.bind_native_executable(binary, linux_x86, "selected shell")
for rejected_mode in (0o720, 0o702):
    binary.chmod(rejected_mode)
    expect_refusal(
        lambda: module.bind_native_executable(
            binary, linux_x86, "selected shell"),
        "selected shell must not be group- or other-writable")
binary.chmod(0o700)
changed = bytearray(elf_x86)
changed[-1] = 1
binary.write_bytes(bytes(changed))
binary.chmod(0o700)
expect_refusal(
    lambda: module.bind_native_executable(
        binary, linux_x86, "selected shell", binding),
    "selected shell changed after native-architecture admission")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"translated under Rosetta"* ]]
    [[ "$output" == *"x86_64 process is running on Apple Silicon"* ]]
    [[ "$output" == *"thin shell does not contain the native arm64 architecture"* ]]
    [[ "$output" == *"universal shell does not contain the native arm64 architecture"* ]]
    [[ "$output" == *"Linux shell does not contain the native x86_64 architecture"* ]]
    [[ "$output" == *"crossing universal has invalid Mach-O load-command bounds"* ]]
    [[ "$output" == *"duplicate universal has overlapping universal Mach-O slices"* ]]
    [[ "$output" == *"bounded ELF has invalid ELF program-header bounds"* ]]
    [[ "$output" == *"selected shell must not be group- or other-writable"* ]]
    [[ "$output" == *"selected shell changed after native-architecture admission"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "Bash and zsh run plus read-only verify bind one exact installed archive" {
    require_dynamic
    local archive_sha shell_name cells=0
    archive_sha="$(sha256_of "$CANARY_ARCHIVE")"

    for shell_name in bash zsh; do
        [[ -f "$CANARY_WORK/$shell_name/public.json" ]] || continue
        cells=$((cells + 1))
        run verify_cell "$shell_name"
        [[ "$status" -eq 0 ]]
        [[ "$(mode_of "$CANARY_WORK/$shell_name/private.json")" == 600 ]]
        [[ "$(mode_of "$CANARY_WORK/$shell_name/public.json")" == 644 ]]
        run "$CANARY_PYTHON" -I -S -B - \
            "$CANARY_WORK/$shell_name/private.json" \
            "$CANARY_WORK/$shell_name/public.json" \
            "$archive_sha" "$shell_name" <<'PY'
import json
from pathlib import Path
import re
import sys

private = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
public = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
archive_sha, shell_name = sys.argv[3:]
assert set(public) == {
    "schema_version", "kind", "claim_scope", "status", "candidate",
    "platform", "shell", "protocol", "mechanism", "parity", "integrity",
    "execution", "non_claims",
}
assert set(private) == {
    "schema_version", "kind", "claim_scope", "candidate", "platform",
    "shell", "protocol", "processes", "mechanisms", "artifacts",
    "measurements", "execution", "public_projection_sha256",
}
assert public["kind"] == "mainframe-installed-awm-handoff-evidence"
assert public["status"] == "passed"
assert public["candidate"]["archive_sha256"] == archive_sha
assert public["candidate"]["installed_payload"] == (
    "authenticated-release-files-private-staging"
)
assert private["candidate"]["installed_payload"] == (
    "authenticated-release-files-private-staging"
)
assert public["shell"]["name"] == shell_name
assert private["shell"]["name"] == shell_name
assert private["candidate"]["archive"]["sha256"] == archive_sha

def visit(value):
    if isinstance(value, dict):
        lowered = [key.lower() for key in value]
        assert not any(
            key in {"path", "paths"} or key.startswith("path_")
            or key.endswith(("_path", "_paths")) for key in lowered
        )
        for child in value.values():
            visit(child)
    elif isinstance(value, list):
        for child in value:
            visit(child)
    elif isinstance(value, str):
        assert not value.startswith("/")
        assert re.match(r"^[A-Za-z]:[\\/]", value) is None

visit(public)
PY
        [[ "$status" -eq 0 ]]
    done
    [[ "$cells" -eq 2 ]]
}

@test "private record proves four ordered shells, bounded equal envelopes, and 100/100 parity" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_WORK/bash/private.json" \
        "$CANARY_WORK/bash/public.json" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

private = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
public = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
processes = private["processes"]
assert [item["sequence"] for item in processes] == [1, 2, 3, 4]
assert [item["operation"] for item in processes] == [
    "ensure", "checkpoint", "discovery", "handoff",
]
assert len({item["pid"] for item in processes}) == 4
assert all(item["exit_code"] == 0 for item in processes)
for item in processes:
    for stream in ("stdout", "stderr"):
        binding = item[stream]
        path = Path(binding["path"])
        payload = path.read_bytes()
        assert path.is_file() and not path.is_symlink()
        assert len(payload) == binding["size_bytes"]
        assert sha256(payload).hexdigest() == binding["sha256"]

control = Path(private["mechanisms"]["control"]["neutral_envelope"]["path"])
treatment = Path(private["mechanisms"]["treatment"]["neutral_envelope"]["path"])
assert control.read_bytes() == treatment.read_bytes()
assert 0 < len(control.read_bytes()) <= 4096
measurements = private["measurements"]
assert measurements["source_fact_occurrences_control"] == 1
assert measurements["source_fact_occurrences_treatment"] == 1
assert measurements["neutral_envelopes_equal"] is True
assert measurements["control_score"] == measurements["treatment_score"] == 100
assert measurements["control_tests_passed"] == 4
assert measurements["treatment_tests_passed"] == 4
assert measurements["tests_total"] == 4
assert measurements["score_delta"] == 0
assert measurements["outcome"] == "tie"
assert measurements["final_trees_equal"] is True
assert private["artifacts"]["control_workspace_final"]["sha256"] == (
    private["artifacts"]["treatment_workspace_final"]["sha256"]
)
execution = private["execution"]
assert execution["fresh_login_shell_processes"] == 4
assert execution["fake_transport_processes"] == 3
assert execution["grader_processes"] == 2
assert execution["certifier_started_top_level_processes"] == 9
assert all(execution[key] == 0 for key in (
    "certifier_started_live_agent_sessions",
    "certifier_started_provider_sessions",
    "certifier_issued_provider_requests",
    "certifier_started_pi_sessions",
    "certifier_started_ollama_sessions",
    "certifier_network_api_calls",
))
assert public["mechanism"]["mainframe_runtime_exercised"] is True
assert public["mechanism"]["mainframe_awm_exercised"] is True
assert public["parity"]["final_trees_equal"] is True
assert public["non_claims"]["mainframe_benefit"] == "not-measured"
assert public["non_claims"]["same_local_account_isolation"] == "not-established"
PY
    [[ "$status" -eq 0 ]]
}

@test "run refuses no-clobber violations and unsafe output filesystem shapes" {
    require_dynamic
    local case_root private_output public_output target

    case_root="$TEST_DIR/existing-private"
    mkdir "$case_root" && chmod 700 "$case_root"
    private_output="$case_root/private.json"
    public_output="$case_root/public.json"
    printf 'sentinel\n' > "$private_output"
    chmod 600 "$private_output"
    run canary run --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-output "$private_output" --output "$public_output"
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$private_output")" == sentinel ]]
    [[ ! -e "$public_output" ]]

    case_root="$TEST_DIR/symlink-output"
    mkdir "$case_root" && chmod 700 "$case_root"
    target="$case_root/target"
    printf 'sentinel\n' > "$target" && chmod 600 "$target"
    ln -s "$target" "$case_root/private.json"
    run canary run --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-output "$case_root/private.json" \
        --output "$case_root/public.json"
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$target")" == sentinel ]]

    case_root="$TEST_DIR/fifo-output"
    mkdir "$case_root" && chmod 700 "$case_root"
    mkfifo "$case_root/private.json"
    run canary run --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-output "$case_root/private.json" \
        --output "$case_root/public.json"
    [[ "$status" -ne 0 ]]

    case_root="$TEST_DIR/public-parent/private"
    mkdir -p "$case_root"
    chmod 700 "$case_root"
    run canary run --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-output "$case_root/private.json" \
        --output "$TEST_DIR/missing-parent/public.json"
    [[ "$status" -ne 0 ]]
    [[ ! -e "$case_root/private.json" ]]

    case_root="$TEST_DIR/world-readable-private"
    mkdir "$case_root" && chmod 755 "$case_root"
    run canary run --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-output "$case_root/private.json" \
        --output "$case_root/public.json"
    [[ "$status" -ne 0 ]]
    [[ ! -e "$case_root/private.json" ]]
}

@test "archive, checksum, selected-shell, and platform identity tampering fail closed" {
    require_dynamic
    local tamper_root archive checksum private_copy
    tamper_root="$TEST_DIR/tampered-release"
    mkdir "$tamper_root" && chmod 700 "$tamper_root"
    archive="$tamper_root/${CANARY_ARCHIVE##*/}"
    checksum="${archive}.sha256"
    cp "$CANARY_ARCHIVE" "$archive"
    cp "$CANARY_CHECKSUM" "$checksum"
    printf 'tamper\n' >> "$archive"
    run canary run --archive "$archive" --checksum "$checksum" --shell bash \
        --private-output "$tamper_root/private.json" \
        --output "$tamper_root/public.json"
    [[ "$status" -ne 0 ]]

    # Authenticate archive A, atomically substitute archive B, and prove the
    # same-descriptor inventory refuses the stale binding.
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$tamper_root/raced.tar.gz" <<'PY'
import importlib.util
import os
from pathlib import Path
import shutil
import sys

tool, source, target = map(Path, sys.argv[1:])
tool = tool.resolve(strict=True)
source = source.resolve(strict=True)
target = target.parent.resolve(strict=True) / target.name
spec = importlib.util.spec_from_file_location("installed_awm_canary", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
shutil.copy2(source, target)
binding = module.file_binding(target, "race archive", module.MAX_ARCHIVE_BYTES)
replacement = target.with_name("raced-replacement.tar.gz")
shutil.copy2(source, replacement)
with replacement.open("ab") as stream:
    stream.write(b"tamper")
os.replace(replacement, target)
try:
    module.archive_inventory(target, expected_binding=binding)
except module.CanaryError as error:
    assert "changed between binding and inspection" in str(error)
else:
    raise AssertionError("archive pathname swap was accepted")
PY
    [[ "$status" -eq 0 ]]

    # Mutating the already-open archive after authentication cannot change
    # what gets parsed: inventory consumes the immutable authenticated bytes.
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" <<'PY'
import importlib.util
from pathlib import Path
import sys

tool, source = map(Path, sys.argv[1:])
tool = tool.resolve(strict=True)
source = source.resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_canary", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
real_bytes_io = module.io.BytesIO
mutated = False
def observing_bytes_io(payload):
    global mutated
    mutated = True
    # The parser receives its private immutable payload; changing a separate
    # copy cannot affect it and there is no descriptor reread seam.
    changed_copy = bytearray(payload)
    if changed_copy:
        changed_copy[-1] ^= 1
    return real_bytes_io(payload)
module.io.BytesIO = observing_bytes_io
binding = module.file_binding(source, "archive", module.MAX_ARCHIVE_BYTES)
inventory = module.archive_inventory(source, expected_binding=binding)
assert mutated and inventory
assert not hasattr(module, "_archive_parse_descriptor")
PY
    [[ "$status" -eq 0 ]]

    # Force the pre-open pathname to become a FIFO. O_NONBLOCK and post-open
    # fstat validation must refuse promptly instead of waiting for a writer.
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$tamper_root/raced-fifo-input" <<'PY'
import importlib.util
import os
from pathlib import Path
import signal
import sys

tool, target = map(Path, sys.argv[1:])
tool = tool.resolve(strict=True)
target = target.parent.resolve(strict=True) / target.name
target.write_bytes(b"regular")
spec = importlib.util.spec_from_file_location("installed_awm_canary", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
real_open = module.os.open
swapped = False
def racing_open(path, flags, *args, **kwargs):
    global swapped
    if Path(path).name == target.name and kwargs.get("dir_fd") is not None and not swapped:
        swapped = True
        target.unlink()
        os.mkfifo(target)
    return real_open(path, flags, *args, **kwargs)
module.os.open = racing_open
signal.alarm(2)
try:
    module.open_regular(target, "raced FIFO", 1024)
except module.CanaryError:
    pass
else:
    raise AssertionError("raced FIFO was accepted")
finally:
    signal.alarm(0)
PY
    [[ "$status" -eq 0 ]]
    [[ ! -e "$tamper_root/private.json" ]]

    cp "$CANARY_ARCHIVE" "$archive"
    {
        cat "$CANARY_CHECKSUM"
        cat "$CANARY_CHECKSUM"
    } > "$checksum"
    run canary run --archive "$archive" --checksum "$checksum" --shell bash \
        --private-output "$tamper_root/private.json" \
        --output "$tamper_root/public.json"
    [[ "$status" -ne 0 ]]

    rm -f "$archive" "$checksum"
    ln -s "$CANARY_ARCHIVE" "$archive"
    cp "$CANARY_CHECKSUM" "$checksum"
    run canary run --archive "$archive" --checksum "$checksum" --shell bash \
        --private-output "$tamper_root/private.json" \
        --output "$tamper_root/public.json"
    [[ "$status" -ne 0 ]]

    run canary verify --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell zsh --private-evidence "$CANARY_WORK/bash/private.json" \
        --evidence "$CANARY_WORK/bash/public.json"
    [[ "$status" -ne 0 ]]

    private_copy="$TEST_DIR/platform-private-backup.json"
    cp -p "$CANARY_WORK/bash/private.json" "$private_copy"
    mutate_private_in_place "$CANARY_WORK/bash/private.json" platform
    run canary verify --archive "$CANARY_ARCHIVE" --checksum "$CANARY_CHECKSUM" \
        --shell bash --private-evidence "$CANARY_WORK/bash/private.json" \
        --evidence "$CANARY_WORK/bash/public.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"private platform differs"* ]]
    cp -p "$private_copy" "$CANARY_WORK/bash/private.json"
}

@test "private semantic tampering rejects order, multiplicity, envelope, score, tree, and execution drift" {
    require_dynamic
    local mutation private_path backup expected handoff_stdout handoff_stdout_backup
    private_path="$CANARY_WORK/bash/private.json"
    backup="$TEST_DIR/private-backup.json"
    cp -p "$private_path" "$backup"
    handoff_stdout="$CANARY_WORK/bash/private.json.data/artifacts/shell-4-handoff.stdout"
    handoff_stdout_backup="$TEST_DIR/handoff-stdout-backup"
    cp -p "$handoff_stdout" "$handoff_stdout_backup"
    run verify_cell bash
    [[ "$status" -eq 0 ]]
    for mutation in \
        process-order duplicate-pid source-count envelope-parity \
        final-tree score provider-count shell-version-path \
        relocated-shell-output aliased-awm-snapshot handoff-stdout-unbound; do
        cp -p "$backup" "$private_path"
        mutate_private_in_place "$private_path" "$mutation"
        run canary verify \
            --archive "$CANARY_ARCHIVE" \
            --checksum "$CANARY_CHECKSUM" \
            --shell bash \
            --private-evidence "$private_path" \
            --evidence "$CANARY_WORK/bash/public.json"
        [[ "$status" -ne 0 ]]
        [[ "$output" != *"private run data is not adjacent"* ]]
        cp -p "$handoff_stdout_backup" "$handoff_stdout"
    done
    cp -p "$backup" "$private_path"
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "public tampering fails while clean verify starts no poisoned runtime and writes no byte" {
    require_dynamic
    local mutation public_copy poison marker before after command_name
    for mutation in claim extra-key absolute-value archive execution; do
        public_copy="$TEST_DIR/public-${mutation}.json"
        mutate_public "$CANARY_WORK/bash/public.json" "$public_copy" "$mutation"
        run canary verify \
            --archive "$CANARY_ARCHIVE" \
            --checksum "$CANARY_CHECKSUM" \
            --shell bash \
            --private-evidence "$CANARY_WORK/bash/private.json" \
            --evidence "$public_copy"
        [[ "$status" -ne 0 ]]
    done

    poison="$TEST_DIR/poison"
    marker="$TEST_DIR/subprocess-started"
    mkdir "$poison" && chmod 700 "$poison"
    for command_name in bash zsh mainframe pi ollama curl wget nc git; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "%s\n" "$0" >> "${CANARY_VERIFY_MARKER:?}"' \
            'exit 97' > "$poison/$command_name"
        chmod 700 "$poison/$command_name"
    done
    before="$(tree_identity "$CANARY_WORK")"
    run env \
        HOME="$TEST_DIR/home" \
        TMPDIR="$TEST_DIR/tmp" \
        PATH="$poison:/usr/bin:/bin" \
        CANARY_VERIFY_MARKER="$marker" \
        "$CANARY_PYTHON" -I -S -B "$CANARY_TOOL" verify \
        --archive "$CANARY_ARCHIVE" \
        --checksum "$CANARY_CHECKSUM" \
        --shell bash \
        --private-evidence "$CANARY_WORK/bash/private.json" \
        --evidence "$CANARY_WORK/bash/public.json"
    [[ "$status" -eq 0 ]]
    after="$(tree_identity "$CANARY_WORK")"
    [[ "$after" == "$before" ]]
    [[ ! -e "$marker" ]]
}

@test "verify rejects a PID token embedded in a non-PID output line" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$CANARY_WORK/bash/private.json" "$CANARY_WORK/bash/public.json" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

tool, archive, checksum, private_path, public_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_pid_spoof", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

private_bytes = private_path.read_bytes()
private_mode = stat.S_IMODE(private_path.stat().st_mode)
private = json.loads(private_bytes.decode("utf-8"))
record = private["processes"][1]
stdout_path = Path(record["stdout"]["path"])
stdout_bytes = stdout_path.read_bytes()
stdout_mode = stat.S_IMODE(stdout_path.stat().st_mode)
exact_line = ("CANARY_PID={}\n".format(record["pid"])).encode("ascii")
spoofed_line = ("X-CANARY_PID={}\n".format(record["pid"])).encode("ascii")
assert stdout_bytes.count(exact_line) == 1

try:
    spoofed = stdout_bytes.replace(exact_line, spoofed_line, 1)
    stdout_path.write_bytes(spoofed)
    os.chmod(str(stdout_path), stdout_mode)
    record["stdout"] = module.file_binding(
        stdout_path, "spoofed shell stdout", module.MAX_OUTPUT_BYTES, "0600")
    private["public_projection_sha256"] = module.sha256_bytes(
        module.canonical_bytes(module.public_projection(private)))
    private_path.write_bytes(module.canonical_bytes(private) + b"\n")
    os.chmod(str(private_path), private_mode)
    try:
        module.verify_canary(archive, checksum, "bash", private_path, public_path)
    except module.CanaryError as error:
        message = str(error)
        assert "shell output does not bind its exact process identity" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("a PID token embedded in a non-PID line was accepted")
finally:
    stdout_path.write_bytes(stdout_bytes)
    os.chmod(str(stdout_path), stdout_mode)
    private_path.write_bytes(private_bytes)
    os.chmod(str(private_path), private_mode)
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"shell output does not bind its exact process identity"* ]]
    [[ "$output" != *"Traceback"* ]]
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "verify binds private and public evidence bytes across parse-to-ledger races" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$CANARY_WORK/bash/private.json" "$CANARY_WORK/bash/public.json" <<'PY'
import importlib.util
import os
from pathlib import Path
import stat
import sys

tool, archive, checksum, private_path, public_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_evidence_race", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def raced_payload(payload):
    needle = b"installed-candidate-awm-handoff-mechanism-conformance-only"
    offset = payload.find(needle)
    assert offset >= 0
    changed = bytearray(payload)
    changed[offset] = ord("x")
    return bytes(changed)

def require_race_refusal(target, parse_label, expected):
    original = target.read_bytes()
    original_mode = stat.S_IMODE(target.stat().st_mode)
    replacement = raced_payload(original)
    assert len(replacement) == len(original) and replacement != original
    real_parse = module.parse_json
    state = {"swapped": False}

    def swapping_parse(payload, label):
        value = real_parse(payload, label)
        if not state["swapped"] and label == parse_label:
            target.write_bytes(replacement)
            os.chmod(str(target), original_mode)
            state["swapped"] = True
        return value

    module.parse_json = swapping_parse
    try:
        try:
            module.verify_canary(archive, checksum, "bash", private_path, public_path)
        except module.CanaryError as error:
            message = str(error)
            assert expected in message, message
            print("REFUSED: " + message)
        else:
            raise AssertionError("{} parse-to-ledger swap was accepted".format(target.name))
        assert state["swapped"], "the deterministic parse-to-ledger hook did not run"
    finally:
        module.parse_json = real_parse
        target.write_bytes(original)
        os.chmod(str(target), original_mode)

require_race_refusal(
    private_path, "private evidence", "private evidence changed during replay")
require_race_refusal(
    public_path, "public evidence", "public evidence changed during verification")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"private evidence changed during replay"* ]]
    [[ "$output" == *"public evidence changed during verification"* ]]
    [[ "$output" != *"Traceback"* ]]
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "verify requires the installed profile-discovery route and CLI link to remain present" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$CANARY_WORK/bash/private.json" "$CANARY_WORK/bash/public.json" <<'PY'
import importlib.util
import os
from pathlib import Path
import stat
import sys

tool, archive, checksum, private_path, public_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_route_presence", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
state_root = private_path.parent / (private_path.name + ".data")

profile = state_root / "home" / ".bashrc"
profile_bytes = profile.read_bytes()
profile_mode = stat.S_IMODE(profile.stat().st_mode)
try:
    profile.unlink()
    try:
        module.verify_canary(archive, checksum, "bash", private_path, public_path)
    except module.CanaryError as error:
        message = str(error)
        assert "isolated shell profile differs" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("verification accepted a missing isolated shell profile")
finally:
    profile.write_bytes(profile_bytes)
    os.chmod(str(profile), profile_mode)

cli_link = state_root / "home" / ".local" / "bin" / "mainframe"
link_target = os.readlink(str(cli_link))
try:
    cli_link.unlink()
    try:
        module.verify_canary(archive, checksum, "bash", private_path, public_path)
    except module.CanaryError as error:
        message = str(error)
        assert "installed CLI link differs" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("verification accepted a missing installed CLI link")
finally:
    if cli_link.exists() or cli_link.is_symlink():
        cli_link.unlink()
    os.symlink(link_target, str(cli_link))
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"isolated shell profile differs"* ]]
    [[ "$output" == *"installed CLI link differs"* ]]
    [[ "$output" != *"Traceback"* ]]
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "verify rejects hidden checkpoint and discovery state in earlier AWM snapshots" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$CANARY_WORK/bash/private.json" "$CANARY_WORK/bash/public.json" \
        "$TEST_DIR/stage-backups" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import sys

tool, archive, checksum, private_path, public_path, backup_root = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_stage_state", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
backup_root.mkdir(mode=0o700)
private_bytes = private_path.read_bytes()
private_mode = stat.S_IMODE(private_path.stat().st_mode)
state_root = private_path.parent / (private_path.name + ".data")
snapshot_root = state_root / "snapshots" / "awm"

def store_private(value):
    value["public_projection_sha256"] = module.sha256_bytes(
        module.canonical_bytes(module.public_projection(value)))
    private_path.write_bytes(module.canonical_bytes(value) + b"\n")
    os.chmod(str(private_path), private_mode)

def one_session(snapshot):
    sessions = [item for item in (snapshot / "sessions" / "projects").iterdir()
                if item.is_dir() and not item.is_symlink()]
    assert len(sessions) == 1
    return sessions[0]

def require_stage_refusal(target_name, source_name, binding_name, hidden_log, expected):
    target = snapshot_root / target_name
    source = snapshot_root / source_name
    backup = backup_root / target_name
    original_digest = module.private_tree_sha256(target)
    shutil.copytree(str(target), str(backup), copy_function=shutil.copy2)
    try:
        shutil.rmtree(str(target))
        shutil.copytree(str(source), str(target), copy_function=shutil.copy2)
        log_path = one_session(target) / hidden_log
        assert log_path.read_bytes(), "the future-stage fixture log must start non-empty"
        log_mode = stat.S_IMODE(log_path.stat().st_mode)
        log_path.write_bytes(b"")
        os.chmod(str(log_path), log_mode)
        private = json.loads(private_bytes.decode("utf-8"))
        private["mechanisms"]["treatment"][binding_name]["sha256"] = \
            module.private_tree_sha256(target)
        store_private(private)
        try:
            module.verify_canary(archive, checksum, "bash", private_path, public_path)
        except module.CanaryError as error:
            message = str(error)
            assert expected in message, message
            print("REFUSED: " + message)
        else:
            raise AssertionError("hidden future-stage AWM artifacts were accepted")
    finally:
        private_path.write_bytes(private_bytes)
        os.chmod(str(private_path), private_mode)
        if target.exists():
            shutil.rmtree(str(target))
        shutil.copytree(str(backup), str(target), copy_function=shutil.copy2)
        assert module.private_tree_sha256(target) == original_digest

require_stage_refusal(
    "after-ensure", "after-checkpoint", "awm_after_ensure",
    Path("logs") / "checkpoints.jsonl",
    "AWM ensure snapshot contains later-stage state")
require_stage_refusal(
    "after-checkpoint", "after-discovery", "awm_after_checkpoint",
    Path("discoveries.jsonl"),
    "AWM checkpoint snapshot contains later-stage state")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"AWM ensure snapshot contains later-stage state"* ]]
    [[ "$output" == *"AWM checkpoint snapshot contains later-stage state"* ]]
    [[ "$output" != *"Traceback"* ]]
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "verify binds the persisted AWM handoff state to the exported handoff" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$CANARY_WORK/bash/private.json" "$CANARY_WORK/bash/public.json" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

tool, archive, checksum, private_path, public_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_handoff_state", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
private_bytes = private_path.read_bytes()
private_mode = stat.S_IMODE(private_path.stat().st_mode)
private = json.loads(private_bytes.decode("utf-8"))
handoff_snapshot = Path(
    private["mechanisms"]["treatment"]["awm_after_handoff"]["path"])
handoffs = list(handoff_snapshot.glob("sessions/projects/*/handoffs/*.json"))
assert len(handoffs) == 1
state_handoff = handoffs[0]
handoff_bytes = state_handoff.read_bytes()
handoff_mode = stat.S_IMODE(state_handoff.stat().st_mode)
value = json.loads(handoff_bytes.decode("utf-8"))
assert isinstance(value.get("budget_remaining"), int)
value["budget_remaining"] = value["budget_remaining"] + 1

try:
    state_handoff.write_bytes(module.canonical_bytes(value) + b"\n")
    os.chmod(str(state_handoff), handoff_mode)
    private["mechanisms"]["treatment"]["awm_after_handoff"]["sha256"] = \
        module.private_tree_sha256(handoff_snapshot)
    private["public_projection_sha256"] = module.sha256_bytes(
        module.canonical_bytes(module.public_projection(private)))
    private_path.write_bytes(module.canonical_bytes(private) + b"\n")
    os.chmod(str(private_path), private_mode)
    try:
        module.verify_canary(archive, checksum, "bash", private_path, public_path)
    except module.CanaryError as error:
        message = str(error)
        assert "AWM handoff state differs from exported handoff" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("divergent persisted and exported handoffs were accepted")
finally:
    state_handoff.write_bytes(handoff_bytes)
    os.chmod(str(state_handoff), handoff_mode)
    private_path.write_bytes(private_bytes)
    os.chmod(str(private_path), private_mode)
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"AWM handoff state differs from exported handoff"* ]]
    [[ "$output" != *"Traceback"* ]]
    run verify_cell bash
    [[ "$status" -eq 0 ]]
}

@test "write_new refuses a same-UID replacement of its admitted output parent" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$TEST_DIR/write-parent" <<'PY'
import importlib.util
import os
from pathlib import Path
import shutil
import sys

tool, root = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("installed_awm_write_parent", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
root.mkdir(mode=0o700)
parent = root / "selected"
parked = root / "original"
parent.mkdir(mode=0o700)
target = parent / "evidence.json"
real_open_parent = module.open_canonical_parent
state = {"swapped": False}

def racing_open_parent(*args, **kwargs):
    if not state["swapped"]:
        os.rename(str(parent), str(parked))
        parent.mkdir(mode=0o700)
        state["swapped"] = True
    return real_open_parent(*args, **kwargs)

module.open_canonical_parent = racing_open_parent
try:
    try:
        module.write_new(target, b"evidence\n", 0o600, "race evidence")
    except module.CanaryError as error:
        message = str(error)
        assert "output parent changed after admission" in message, message
        assert not target.exists()
        assert not (parked / target.name).exists()
        print("REFUSED: " + message)
    else:
        raise AssertionError("write_new accepted a replacement output parent")
    assert state["swapped"], "the deterministic output-parent hook did not run"
finally:
    module.open_canonical_parent = real_open_parent
    if parent.exists():
        shutil.rmtree(str(parent))
    if parked.exists():
        if (parked / target.name).exists():
            (parked / target.name).unlink()
        os.rename(str(parked), str(parent))
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"output parent changed after admission"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "archive extraction remains pinned when its selected root pathname is swapped" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$TEST_DIR/extraction-root-race" <<'PY'
import gzip
import importlib.util
import io
import os
from pathlib import Path
import sys
import tarfile

tool = Path(sys.argv[1]).resolve(strict=True)
root = Path(sys.argv[2]).resolve(strict=False)
root.mkdir(mode=0o700)
root = root.resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_extract_root", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

raw = io.BytesIO()
with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as payload:
    directory = tarfile.TarInfo("d")
    directory.type = tarfile.DIRTYPE
    directory.mode = 0o755
    directory.mtime = 0
    payload.addfile(directory)
    candidate = b"candidate payload\n"
    member = tarfile.TarInfo("d/file.txt")
    member.size = len(candidate)
    member.mode = 0o644
    member.mtime = 0
    payload.addfile(member, io.BytesIO(candidate))
archive = root / "tiny.tar.gz"
with archive.open("wb") as stream:
    with gzip.GzipFile(filename="", fileobj=stream, mode="wb", mtime=0) as compressed:
        compressed.write(raw.getvalue())

selected = root / "selected"
parked = root / "parked"
outside = root / "outside"
selected.mkdir(mode=0o700)
(outside / "d").mkdir(mode=0o700, parents=True)
sentinel = outside / "sentinel.txt"
sentinel.write_bytes(b"important\n")
os.chmod(str(sentinel), 0o600)
real_open = module.os.open
state = {"swapped": False}

def racing_open(path, flags, *args, **kwargs):
    if not state["swapped"] and os.fspath(path) == "file.txt" and \
            flags & os.O_WRONLY and flags & os.O_CREAT:
        os.rename(str(selected), str(parked))
        os.symlink(str(outside), str(selected), target_is_directory=True)
        state["swapped"] = True
    return real_open(path, flags, *args, **kwargs)

module.os.open = racing_open
try:
    try:
        module.archive_inventory(archive, selected)
    except module.CanaryError as error:
        message = str(error)
        assert "release extraction root" in message or \
            "changed after admission" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("archive extraction accepted a replacement root pathname")
    assert state["swapped"], "the deterministic extraction-root hook did not run"
    assert sentinel.read_bytes() == b"important\n"
    assert not (outside / "d" / "file.txt").exists()
    assert (parked / "d" / "file.txt").read_bytes() == candidate
finally:
    module.os.open = real_open
    if selected.is_symlink():
        selected.unlink()
    if parked.exists() and not selected.exists():
        os.rename(str(parked), str(selected))
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"REFUSED:"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "copy_tree remains pinned when its destination root pathname is swapped" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$TEST_DIR/copy-root-race" <<'PY'
import builtins
import importlib.util
import os
from pathlib import Path
import sys

tool = Path(sys.argv[1]).resolve(strict=True)
root = Path(sys.argv[2]).resolve(strict=False)
root.mkdir(mode=0o700)
root = root.resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_copy_root", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

source = root / "source"
selected = root / "selected"
parked = root / "parked"
outside = root / "outside"
source.mkdir(mode=0o700)
outside.mkdir(mode=0o700)
(source / "a.txt").write_bytes(b"candidate\n")
os.chmod(str(source / "a.txt"), 0o600)
sentinel = outside / "a.txt"
sentinel.write_bytes(b"important\n")
os.chmod(str(sentinel), 0o600)
real_os_open = module.os.open
real_builtin_open = builtins.open
state = {"swapped": False}

def swap_destination():
    if state["swapped"]:
        return
    os.rename(str(selected), str(parked))
    os.symlink(str(outside), str(selected), target_is_directory=True)
    state["swapped"] = True

def racing_os_open(path, flags, *args, **kwargs):
    if os.fspath(path) == "a.txt" and flags & os.O_WRONLY and flags & os.O_CREAT:
        swap_destination()
    return real_os_open(path, flags, *args, **kwargs)

def racing_builtin_open(file, mode="r", *args, **kwargs):
    if os.fspath(file) == str(selected / "a.txt") and \
            any(marker in mode for marker in ("w", "x", "a", "+")):
        swap_destination()
    return real_builtin_open(file, mode, *args, **kwargs)

module.os.open = racing_os_open
builtins.open = racing_builtin_open
try:
    try:
        module.copy_tree(source, selected)
    except module.CanaryError as error:
        message = str(error)
        assert "workspace destination" in message or \
            "changed after admission" in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("copy_tree accepted a replacement destination pathname")
    assert state["swapped"], "the deterministic copy-root hook did not run"
    assert sentinel.read_bytes() == b"important\n"
    assert (parked / "a.txt").read_bytes() == b"candidate\n"
finally:
    builtins.open = real_builtin_open
    module.os.open = real_os_open
    if selected.is_symlink():
        selected.unlink()
    if parked.exists() and not selected.exists():
        os.rename(str(parked), str(selected))
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"REFUSED:"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "forced run failures retain owned state and outputs without destructive pathname cleanup" {
    require_dynamic
    run "$CANARY_PYTHON" -I -S -B - \
        "$CANARY_TOOL" "$CANARY_ARCHIVE" "$CANARY_CHECKSUM" \
        "$TEST_DIR/failure-cleanup" <<'PY'
import importlib.util
import os
from pathlib import Path
import stat
import sys

tool, archive, checksum = map(Path, sys.argv[1:4])
root = Path(sys.argv[4]).resolve(strict=False)
root.mkdir(mode=0o700)
root = root.resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_failure_cleanup", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def private_directory(path):
    path.mkdir(mode=0o700, parents=True)
    os.chmod(str(path), 0o700)
    return path

# Failure before private evidence exists: a cleanup rmtree must not be able to
# exchange the newly-created state pathname for an unrelated victim directory.
outer = private_directory(root / "before-private")
outer_outputs = private_directory(outer / "outputs")
outer_private = outer_outputs / "private.json"
outer_public = outer_outputs / "public.json"
outer_state = outer_outputs / "private.json.data"
outer_parked = outer_outputs / "private.json.data.parked"
outer_victim = private_directory(outer / "victim-state")
outer_sentinel = outer_victim / "important.txt"
outer_sentinel.write_bytes(b"important outer state\n")
os.chmod(str(outer_sentinel), 0o600)
real_install = module.install_candidate
cleanup_module = getattr(module, "shutil", None)
real_rmtree = getattr(cleanup_module, "rmtree", None)
outer_calls = {"rmtree": 0}

def fail_install(*args, **kwargs):
    raise module.CanaryError("forced post-state failure")

def racing_outer_rmtree(path, *args, **kwargs):
    if Path(path) == outer_state:
        outer_calls["rmtree"] += 1
        os.rename(str(outer_state), str(outer_parked))
        os.rename(str(outer_victim), str(outer_state))
    return real_rmtree(path, *args, **kwargs)

module.install_candidate = fail_install
if cleanup_module is not None:
    cleanup_module.rmtree = racing_outer_rmtree
outer_message = ""
outer_victim_untouched = False
try:
    try:
        module.run_canary(
            archive, checksum, "bash", outer_private, outer_public)
    except module.CanaryError as error:
        outer_message = str(error)
    else:
        raise AssertionError("forced pre-private failure unexpectedly succeeded")
    outer_victim_untouched = outer_victim.is_dir() and \
        outer_sentinel.read_bytes() == b"important outer state\n"
finally:
    module.install_candidate = real_install
    if cleanup_module is not None:
        cleanup_module.rmtree = real_rmtree
    if outer_parked.exists():
        if outer_state.exists() and not outer_victim.exists():
            os.rename(str(outer_state), str(outer_victim))
        os.rename(str(outer_parked), str(outer_state))
assert "forced post-state failure" in outer_message, outer_message
assert outer_calls["rmtree"] == 0, "run invoked destructive state cleanup"
assert outer_victim_untouched, "state cleanup mutated its substituted victim"
assert outer_state.is_dir()
print("REFUSED: " + outer_message)

# Failure after the private record is created covers both the output-unlink and
# the subsequent state-rmtree sites. Neither destructive primitive may run.
inner = private_directory(root / "after-private")
inner_outputs = private_directory(inner / "outputs")
inner_private = inner_outputs / "private.json"
inner_public = inner_outputs / "public.json"
inner_state = inner_outputs / "private.json.data"
inner_private_parked = inner_outputs / "private.json.parked"
inner_state_parked = inner_outputs / "private.json.data.parked"
inner_victim_file = inner / "victim-evidence.json"
inner_victim_file.write_bytes(b"important evidence\n")
os.chmod(str(inner_victim_file), 0o600)
inner_victim_state = private_directory(inner / "victim-state")
inner_victim_sentinel = inner_victim_state / "important.txt"
inner_victim_sentinel.write_bytes(b"important inner state\n")
os.chmod(str(inner_victim_sentinel), 0o600)
real_reproduce = module.reproduce_public_from_private
real_unlink = module.os.unlink
cleanup_module = getattr(module, "shutil", None)
real_rmtree = getattr(cleanup_module, "rmtree", None)
inner_calls = {"unlink": 0, "rmtree": 0}

def fail_reproduce(*args, **kwargs):
    raise module.CanaryError("forced post-output failure")

def racing_unlink(path, *args, **kwargs):
    if Path(path) == inner_private:
        inner_calls["unlink"] += 1
        os.rename(str(inner_private), str(inner_private_parked))
        os.rename(str(inner_victim_file), str(inner_private))
    return real_unlink(path, *args, **kwargs)

def racing_inner_rmtree(path, *args, **kwargs):
    if Path(path) == inner_state:
        inner_calls["rmtree"] += 1
        os.rename(str(inner_state), str(inner_state_parked))
        os.rename(str(inner_victim_state), str(inner_state))
    return real_rmtree(path, *args, **kwargs)

module.reproduce_public_from_private = fail_reproduce
module.os.unlink = racing_unlink
if cleanup_module is not None:
    cleanup_module.rmtree = racing_inner_rmtree
inner_message = ""
inner_victims_untouched = False
inner_private_retained = False
inner_state_retained = False
try:
    try:
        module.run_canary(
            archive, checksum, "bash", inner_private, inner_public)
    except module.CanaryError as error:
        inner_message = str(error)
    else:
        raise AssertionError("forced post-output failure unexpectedly succeeded")
    inner_victims_untouched = \
        inner_victim_file.read_bytes() == b"important evidence\n" and \
        inner_victim_state.is_dir() and \
        inner_victim_sentinel.read_bytes() == b"important inner state\n"
    inner_private_retained = inner_private.is_file() and not inner_private.is_symlink()
    inner_state_retained = inner_state.is_dir() and not inner_state.is_symlink()
finally:
    module.reproduce_public_from_private = real_reproduce
    module.os.unlink = real_unlink
    if cleanup_module is not None:
        cleanup_module.rmtree = real_rmtree
    if inner_private_parked.exists():
        if inner_private.exists() and not inner_victim_file.exists():
            os.rename(str(inner_private), str(inner_victim_file))
        os.rename(str(inner_private_parked), str(inner_private))
    if inner_state_parked.exists():
        if inner_state.exists() and not inner_victim_state.exists():
            os.rename(str(inner_state), str(inner_victim_state))
        os.rename(str(inner_state_parked), str(inner_state))
assert "forced post-output failure" in inner_message, inner_message
assert inner_calls == {"unlink": 0, "rmtree": 0}, \
    "run invoked destructive output/state cleanup: {}".format(inner_calls)
assert inner_victims_untouched, "failure cleanup mutated a substituted victim"
assert inner_private_retained, "forced failure removed the owned private output"
assert inner_state_retained, "forced failure removed the owned state directory"
assert not inner_public.exists()
print("REFUSED: " + inner_message)
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"forced post-state failure"* ]]
    [[ "$output" == *"forced post-output failure"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "workflow is an exact read-only 3x2 public matrix with one final-release archive digest" {
    local workflow="$CANARY_REPO/.github/workflows/test.yml"
    run ruby - "$workflow" <<'RUBY'
require "yaml"
require "open3"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
matrix = jobs.fetch("installed-awm-handoff")
aggregate = jobs.fetch("installed-awm-handoff-aggregate")
release = jobs.fetch("release-build")

[matrix, aggregate].each do |job|
  job.fetch("steps").each do |step|
    next unless step.key?("run")
    script = step.fetch("run").gsub(/\$\{\{[^}]+\}\}/, "GITHUB_EXPRESSION")
    _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: script)
    raise "#{step.fetch("name")} shell syntax: #{stderr}" unless status.success?
  end
end

raise "matrix permissions drift" unless matrix.fetch("permissions") == {
  "contents" => "read"
}
raise "matrix must remain downstream only of lint" unless matrix.fetch("needs") == "lint"
raise "matrix timeout drift" unless matrix.fetch("timeout-minutes") == 40
targets = matrix.dig("strategy", "matrix", "target")
expected_targets = [
  {"runner" => "macos-15", "id" => "Darwin-arm64-none",
   "os" => "Darwin", "arch" => "arm64", "system_libc" => "none"},
  {"runner" => "macos-15-intel", "id" => "Darwin-x86_64-none",
   "os" => "Darwin", "arch" => "x86_64", "system_libc" => "none"},
  {"runner" => "ubuntu-24.04", "id" => "Linux-x86_64-glibc",
   "os" => "Linux", "arch" => "x86_64", "system_libc" => "glibc"},
]
raise "platform matrix drift" unless targets == expected_targets
raise "shell matrix drift" unless matrix.dig("strategy", "matrix", "shell") == ["bash", "zsh"]
raise "matrix runner indirection drift" unless matrix.fetch("runs-on") ==
  "${{ matrix.target.runner }}"

steps = matrix.fetch("steps")
release_python = steps.find do |step|
  step["name"] == "Set up release-construction Python 3.12"
end
raise "release Python 3.12 setup missing" unless release_python &&
  release_python.dig("with", "python-version") == "3.12"
release_python_bind = steps.find do |step|
  step["name"] == "Bind release-construction Python"
end
raise "release Python binding missing" unless release_python_bind &&
  release_python_bind.fetch("run").include?("MAINFRAME_AWM_RELEASE_PYTHON")
python = steps.find { |step| step["name"] == "Set up exact Python 3.9" }
raise "Python 3.9 setup missing" unless python &&
  python.dig("with", "python-version") == "3.9"
build = steps.find { |step| step["name"] == "Build and extract the exact release archive" }
run = steps.find { |step| step["name"] ==
  "Run and independently verify the installed handoff canary" }
upload = steps.find { |step| step["name"] ==
  "Upload public installed-handoff evidence only" }
raise "exact archive build missing" unless build
build_script = build.fetch("run")
[
  "scripts/dev/release-candidate.sh --prepare",
  "scripts/dev/release-candidate.sh --check",
  'MAINFRAME_PYTHON="$MAINFRAME_AWM_RELEASE_PYTHON"',
  "scripts/dev/native-host/safe-extract.py",
  'test -x "$proof_source/scripts/dev/certify-installed-awm-handoff.py"',
].each do |fragment|
  raise "archive build contract missing: #{fragment}" unless build_script.include?(fragment)
end
raise "run/verify step missing" unless run
run_script = run.fetch("run")
[
  'certifier="$MAINFRAME_AWM_CANARY_SOURCE/scripts/dev/certify-installed-awm-handoff.py"',
  '"$certifier" run', '"$certifier" verify', '--shell "$CANARY_SHELL"',
  "installed-candidate-awm-handoff-mechanism-conformance-only",
  '.candidate.archive_sha256 == $archive_sha',
  '"authenticated-release-files-private-staging"',
  '.non_claims.same_local_account_isolation == "not-established"',
].each do |fragment|
  raise "canary contract missing: #{fragment}" unless run_script.include?(fragment)
end
raise "public upload missing" unless upload
upload_path = upload.dig("with", "path")
raise "public upload path drift" unless upload_path ==
  "${{ env.MAINFRAME_AWM_CANARY_PUBLIC }}/${{ matrix.target.id }}-${{ matrix.shell }}.json"
raise "private evidence may not be uploaded" if upload_path.downcase.include?("private")

raise "aggregate dependency drift" unless aggregate.fetch("needs") ==
  "installed-awm-handoff"
raise "aggregate permissions drift" unless aggregate.fetch("permissions") == {
  "actions" => "read", "contents" => "read"
}
downloads = aggregate.fetch("steps").select do |step|
  step.fetch("name", "").start_with?("Download ")
end
expected_names = [
  "installed-awm-handoff-Darwin-arm64-none-bash",
  "installed-awm-handoff-Darwin-arm64-none-zsh",
  "installed-awm-handoff-Darwin-x86_64-none-bash",
  "installed-awm-handoff-Darwin-x86_64-none-zsh",
  "installed-awm-handoff-Linux-x86_64-glibc-bash",
  "installed-awm-handoff-Linux-x86_64-glibc-zsh",
]
raise "aggregate download set drift" unless downloads.map { |step|
  step.dig("with", "name")
} == expected_names
downloads.each do |step|
  raise "aggregate download must use exact name" if step.dig("with", "pattern")
  raise "download action pin drift" unless step.fetch("uses") ==
    "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
end
aggregate_script = aggregate.fetch("steps").find do |step|
  step["name"] == "Require the exact six public cells and one archive digest"
end.fetch("run")
[
  "assert observed == expected_names",
  "assert len(archive_digests) == 1",
  '"authenticated-release-files-private-staging"',
  'document["non_claims"]["same_local_account_isolation"]',
  '"cell_count": 6',
  '"mainframe-installed-awm-handoff-matrix-aggregate"',
].each do |fragment|
  raise "aggregate contract missing: #{fragment}" unless
    aggregate_script.include?(fragment)
end
aggregate_upload = aggregate.fetch("steps").find do |step|
  step["name"] == "Upload public installed-handoff aggregate only"
end
raise "aggregate public upload missing" unless aggregate_upload
raise "aggregate upload leaked private path" if
  aggregate_upload.dig("with", "path").downcase.include?("private")

raise "release is not aggregate-gated" unless
  Array(release.fetch("needs")).include?("installed-awm-handoff-aggregate")
release_steps = release.fetch("steps")
download = release_steps.find do |step|
  step["name"] == "Download public installed AWM handoff aggregate"
end
raise "release aggregate download missing" unless download &&
  download.dig("with", "name") == "installed-awm-handoff-aggregate"
bind = release_steps.find do |step|
  step["name"] == "Bind gate evidence to final release bytes"
end.fetch("run")
[
  'aggregate["archive_sha256"] == expected_archive_sha',
  'evidence["candidate"]["archive_sha256"] == expected_archive_sha',
  'test "${#installed_awm_files[@]}" -eq 7',
].each do |fragment|
  raise "final release binding missing: #{fragment}" unless bind.include?(fragment)
end

puts "installed AWM handoff workflow contract valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "installed AWM handoff workflow contract valid" ]]
}

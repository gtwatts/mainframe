#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    NATIVE_DIR="$PROJECT_ROOT/scripts/dev/native-host"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-evidence.XXXXXX")"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

@test "native executable validator binds exact Mach-O and ELF architecture without execution" {
    local validator="$NATIVE_DIR/validate-native-executable.py"

    run python3 -I -S -B - "$validator" "$TEST_DIR" <<'PY'
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys

validator = Path(sys.argv[1]).resolve(strict=True)
root = Path(sys.argv[2]).resolve(strict=True)
source = validator.read_text(encoding="utf-8")
ast.parse(source, filename=str(validator), feature_version=(3, 9))

spec = importlib.util.spec_from_file_location("native_executable_validator", validator)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C


def expect_refusal(callback, expected):
    try:
        callback()
    except module.ValidationError as error:
        message = str(error)
        assert expected in message, message
        print("REFUSED: " + message)
    else:
        raise AssertionError("expected refusal containing: " + expected)


def macho(cpu_type, command_count=0, command_bytes=0):
    return struct.pack(
        "<IIIIIIII",
        0xFEEDFACF,
        cpu_type,
        0,
        2,
        command_count,
        command_bytes,
        0,
        0,
    )


def universal32(slices):
    table_size = 8 + 20 * len(slices)
    table = [struct.pack(">II", 0xCAFEBABE, len(slices))]
    payloads = []
    offset = table_size
    for cpu_type, payload in slices:
        table.append(struct.pack(">IIIII", cpu_type, 0, offset, len(payload), 0))
        payloads.append(payload)
        offset += len(payload)
    return b"".join(table + payloads)


def universal64(slices):
    table_size = 8 + 32 * len(slices)
    table = [struct.pack(">II", 0xCAFEBABF, len(slices))]
    payloads = []
    offset = table_size
    for cpu_type, payload in slices:
        table.append(struct.pack(">IIQQII", cpu_type, 0, offset, len(payload), 0, 0))
        payloads.append(payload)
        offset += len(payload)
    return b"".join(table + payloads)


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


thin_x86 = macho(CPU_X86_64)
thin_arm = macho(CPU_ARM64)
fat32_both = universal32(((CPU_X86_64, thin_x86), (CPU_ARM64, thin_arm)))
fat64_both = universal64(((CPU_X86_64, thin_x86), (CPU_ARM64, thin_arm)))
elf_x86 = elf(62)
elf_arm = elf(183)

assert module.binary_identity(thin_x86, "thin x86") == ("mach-o", {"x86_64"})
assert module.binary_identity(thin_arm, "thin arm") == ("mach-o", {"arm64"})
assert module.binary_identity(fat32_both, "fat32") == (
    "mach-o-universal", {"arm64", "x86_64"})
assert module.binary_identity(fat64_both, "fat64") == (
    "mach-o-universal", {"arm64", "x86_64"})
assert module.binary_identity(elf_x86, "ELF x86") == ("elf", {"x86_64"})
assert module.binary_identity(elf_arm, "ELF arm") == ("elf", {"arm64"})

valid_bindings = (
    ("thin-x86", thin_x86, "Darwin", "x86_64", "mach-o"),
    ("thin-arm", thin_arm, "Darwin", "arm64", "mach-o"),
    ("fat32", fat32_both, "Darwin", "x86_64", "mach-o-universal"),
    ("fat64", fat64_both, "Darwin", "arm64", "mach-o-universal"),
    ("elf-x86", elf_x86, "Linux", "x86_64", "elf"),
    ("elf-arm", elf_arm, "Linux", "aarch64", "elf"),
)
for name, payload, operating_system, architecture, expected_format in valid_bindings:
    fixture = root / name
    fixture.write_bytes(payload)
    fixture.chmod(0o700)
    value = module.bind(str(fixture), operating_system, architecture, name)
    assert value["format"] == expected_format
    assert architecture.replace("aarch64", "arm64") in value["architectures"]
    assert value["sha256"] == hashlib.sha256(payload).hexdigest()

# The load-command bytes fit in the containing file but cross the admitted slice.
crossing_header = macho(CPU_X86_64, command_count=1, command_bytes=32)
crossing = b"".join((
    struct.pack(">II", 0xCAFEBABE, 1),
    struct.pack(">IIIII", CPU_X86_64, 0, 28, len(crossing_header), 0),
    crossing_header,
    b"\0" * 32,
))
expect_refusal(
    lambda: module.binary_identity(crossing, "crossing slice"),
    "crossing slice has invalid Mach-O load-command bounds",
)

# Distinct CPU slices may not overlap, even when both inner headers are valid.
overlap_table = b"".join((
    struct.pack(">II", 0xCAFEBABE, 2),
    struct.pack(">IIIII", CPU_X86_64, 0, 48, 64, 0),
    struct.pack(">IIIII", CPU_ARM64, 0, 80, 32, 0),
))
overlap = overlap_table + thin_x86 + (b"\0" * 32) + thin_arm
expect_refusal(
    lambda: module.binary_identity(overlap, "overlapping slices"),
    "overlapping slices has overlapping universal Mach-O slices",
)

# Duplicate CPU identities remain invalid even when their ranges are distinct.
duplicate_cpu = universal32(((CPU_X86_64, thin_x86), (CPU_X86_64, thin_x86)))
expect_refusal(
    lambda: module.binary_identity(duplicate_cpu, "duplicate CPU"),
    "duplicate CPU has duplicate universal Mach-O CPU slices",
)

bad_program_table = bytearray(elf_x86)
struct.pack_into("<Q", bad_program_table, 32, 4096)
struct.pack_into("<H", bad_program_table, 56, 1)
expect_refusal(
    lambda: module.binary_identity(bytes(bad_program_table), "program table"),
    "program table has invalid ELF program-header bounds",
)
bad_section_table = bytearray(elf_arm)
struct.pack_into("<Q", bad_section_table, 40, 4096)
struct.pack_into("<H", bad_section_table, 60, 1)
expect_refusal(
    lambda: module.binary_identity(bytes(bad_section_table), "section table"),
    "section table has invalid ELF section-header bounds",
)

binary = root / "native-fixture"
binary.write_bytes(elf_x86)
binary.chmod(0o700)
binding = module.bind(str(binary), "Linux", "x86_64", "fixture")
assert binding == module.bind(str(binary), "Linux", "x86_64", "fixture")
assert set(binding) == {
    "architectures", "format", "mode", "path", "sha256", "size_bytes", "type"}
assert binding == {
    "architectures": ["x86_64"],
    "format": "elf",
    "mode": "0700",
    "path": str(binary),
    "sha256": hashlib.sha256(elf_x86).hexdigest(),
    "size_bytes": len(elf_x86),
    "type": "file",
}

cli = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(validator), str(binary),
     "Linux", "x86_64", "fixture"],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert json.loads(cli.stdout) == binding
assert cli.stdout == json.dumps(binding, sort_keys=True, separators=(",", ":")) + "\n"
assert cli.stderr == ""

expect_refusal(
    lambda: module.bind(str(binary), "Darwin", "x86_64", "wrong OS"),
    "wrong OS is not a Mach-O executable for Darwin",
)
expect_refusal(
    lambda: module.bind(str(binary), "Linux", "arm64", "wrong arch"),
    "wrong arch does not contain the admitted arm64 architecture",
)
for mode in (0o720, 0o702):
    binary.chmod(mode)
    expect_refusal(
        lambda: module.bind(str(binary), "Linux", "x86_64", "writable fixture"),
        "writable fixture must not be group- or other-writable",
    )

binary.chmod(0o700)
changed = bytearray(elf_x86)
changed[-1] = 1
binary.write_bytes(bytes(changed))
binary.chmod(0o700)
changed_binding = module.bind(str(binary), "Linux", "x86_64", "fixture")
assert changed_binding != binding
assert changed_binding["path"] == binding["path"]
assert changed_binding["sha256"] != binding["sha256"]
assert changed_binding["size_bytes"] == binding["size_bytes"]

refused = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(validator), str(binary),
     "Darwin", "arm64", "CLI mismatch"],
    check=False,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert refused.returncode == 2
assert refused.stdout == ""
assert "native executable refused:" in refused.stderr
assert "Traceback" not in refused.stderr
print("native executable validator contract passed")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"native executable validator contract passed"* ]]
    [[ "$output" == *"crossing slice has invalid Mach-O load-command bounds"* ]]
    [[ "$output" == *"overlapping slices has overlapping universal Mach-O slices"* ]]
    [[ "$output" == *"duplicate CPU has duplicate universal Mach-O CPU slices"* ]]
    [[ "$output" == *"program table has invalid ELF program-header bounds"* ]]
    [[ "$output" == *"section table has invalid ELF section-header bounds"* ]]
    [[ "$output" == *"must not be group- or other-writable"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "native Gemini host is pinned by exact version and registry integrity" {
    run jq -e '
      .schema_version == 1 and
      .gemini.package == "@google/gemini-cli" and
      .gemini.version == "0.53.1" and
      .gemini.integrity ==
        "sha512-xBGdD/tl05gsTpD2oV1Bq0NCb4BBeTnjSbKxHtwOB7nt1QMaqWYJ9WsOEsQQhQ2P1v0UJth1F17SAXvdZ5mASw==" and
      .gemini.entrypoint == "node_modules/@google/gemini-cli/bundle/gemini.js" and
      .gemini.entrypoint_sha256 ==
        "a193db41b0b2c9e35a8c5aafcb2c810947ee41a311757bb4ee4d6b015bc3bfb5" and
      .gemini.package_tree_sha256 ==
        "78af76cfb06c42eed086f7de65b67ef1fe45b09106c8dfd14070c35ab1a67e14"
    ' "$NATIVE_DIR/hosts.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .dependencies["@google/gemini-cli"] == "0.53.1"
    ' "$NATIVE_DIR/package.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .packages["node_modules/@google/gemini-cli"] as $gemini |
      $gemini.version == "0.53.1" and
      $gemini.resolved ==
        "https://registry.npmjs.org/@google/gemini-cli/-/gemini-cli-0.53.1.tgz" and
      $gemini.integrity ==
        "sha512-xBGdD/tl05gsTpD2oV1Bq0NCb4BBeTnjSbKxHtwOB7nt1QMaqWYJ9WsOEsQQhQ2P1v0UJth1F17SAXvdZ5mASw=="
    ' "$NATIVE_DIR/package-lock.json"
    [[ "$status" -eq 0 ]]
}

@test "native Codex host pins the stable wrapper and every Unix platform runtime" {
    run jq -e '
      .codex.package == "@openai/codex" and
      .codex.version == "0.146.0" and
      .codex.integrity ==
        "sha512-yG3sPWNda/2YAIQIDq9MrrjoCTIQ7rxYM5IasrG3VBcuhCLTkgeg/JzqmJq1V98RE4MJ5jCxDXXQlOjrditFRw==" and
      .codex.entrypoint == "node_modules/@openai/codex/bin/codex.js" and
      .codex.entrypoint_sha256 ==
        "134063e133f0b4244fa3b251acf973d4fe4b4aeeacbdc135211bf480f59f1477" and
      (.codex.platforms | keys | sort) ==
        ["Darwin-arm64", "Darwin-x86_64", "Linux-aarch64", "Linux-x86_64"] and
      all(.codex.platforms[];
        (.package_alias | startswith("@openai/codex-")) and
        (.package_version | startswith("0.146.0-")) and
        (.integrity | test("^sha512-")) and
        (.binary | endswith("/bin/codex")) and
        (.executable_sha256 | test("^[0-9a-f]{64}$")) and
        (.package_tree_sha256 | test("^[0-9a-f]{64}$")))
    ' "$NATIVE_DIR/hosts.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .dependencies["@openai/codex"] == "0.146.0"
    ' "$NATIVE_DIR/package.json"
    [[ "$status" -eq 0 ]]

    run jq -e --slurpfile hosts "$NATIVE_DIR/hosts.json" '
      .packages["node_modules/@openai/codex"] as $root |
      $hosts[0].codex as $expected |
      $root.version == $expected.version and
      $root.integrity == $expected.integrity
    ' "$NATIVE_DIR/package-lock.json"
    [[ "$status" -eq 0 ]]

    while IFS=$'\t' read -r alias version integrity; do
        lock_path="node_modules/${alias}"
        run jq -e \
          --arg path "$lock_path" \
          --arg version "$version" \
          --arg integrity "$integrity" '
            .packages[$path].name == "@openai/codex" and
            .packages[$path].version == $version and
            .packages[$path].integrity == $integrity and
            .packages[$path].optional == true
          ' "$NATIVE_DIR/package-lock.json"
        [[ "$status" -eq 0 ]]
    done < <(jq -r '.codex.platforms[] | [.package_alias, .package_version, .integrity] | @tsv' \
        "$NATIVE_DIR/hosts.json")
}

@test "native Copilot host pins its wrapper dependency and every Unix runtime" {
    run jq -e '
      .copilot.package == "@github/copilot" and
      .copilot.version == "1.0.78" and
      .copilot.integrity ==
        "sha512-jn+8HLZC3R7d6K1/1g9L1iWNKzBVS3JdVcx40r3aWyS5r+MLV1OPNp0fo5OfRMCDIm3NmEaaoqypi9sQkCXuiQ==" and
      .copilot.entrypoint == "node_modules/@github/copilot/npm-loader.js" and
      .copilot.entrypoint_sha256 ==
        "0ea824a86be5757533fdb092eff7050871bd7a711a46babde0ffe0e44ac5ad88" and
      .copilot.dependency == {
        package: "detect-libc",
        version: "2.1.2",
        integrity: "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ=="
      } and
      (.copilot.platforms | keys | sort) == [
        "Darwin-arm64-none",
        "Darwin-x86_64-none",
        "Linux-aarch64-glibc",
        "Linux-aarch64-musl",
        "Linux-x86_64-glibc",
        "Linux-x86_64-musl"
      ] and
      .copilot.platforms["Darwin-arm64-none"] == {
        package: "@github/copilot-darwin-arm64",
        package_version: "1.0.78",
        integrity: "sha512-P11+VyWg8ad0WlywGtO2d7AxqTLJv4hkUicFg6Ycth5lfk00aCu/74YOOZSPO6C2bBBJhAza7oAdmauM6KEojw==",
        binary: "node_modules/@github/copilot-darwin-arm64/copilot",
        executable_sha256: "1dd966fa15f5ad042c6c1b0272f36fee6ae82b1f175037499a6c19596bd9b291",
        runtime_tree_sha256: "07b33e72d4a35ddc992abd2b0e6a4a0d0cc351772c9df7a1dc1e767372299af2"
      } and
      .copilot.platforms["Darwin-x86_64-none"] == {
        package: "@github/copilot-darwin-x64",
        package_version: "1.0.78",
        integrity: "sha512-stimP3WDFs2GU8nJzTJbtRpZViV4bsf80yg7QrFq+G4RISQ3Nihg/3/H0U6UQF1+txMJ/Ohmb5RFYxSw1Hj2sw==",
        binary: "node_modules/@github/copilot-darwin-x64/copilot",
        executable_sha256: "e2ef46125ceb6a3ea539b02b046f57bf8ebf2f35e8166ef7be8f02a4cc89896a",
        runtime_tree_sha256: "78630dc12a9e33224472247fac180418a6419f796128efa27247d602e5443de5"
      } and
      .copilot.platforms["Linux-aarch64-glibc"] == {
        package: "@github/copilot-linux-arm64",
        package_version: "1.0.78",
        integrity: "sha512-K31PRKGTm252V1Lof7ypjg283R2QSm3BgoCvZfX2taos4wqC3SaTozSQKwW3dgrAx7A3G3SGEoilVCNqfigdZA==",
        binary: "node_modules/@github/copilot-linux-arm64/copilot",
        executable_sha256: "8fc37b6dcb1275d049b4c94c1e25caf1b54d368adbc515ddb0b6969bc085de22",
        runtime_tree_sha256: "14d57914866adbf1981bd6ed2edfb4cc728c1adb477b76d09b3d5ddaacf928f3"
      } and
      .copilot.platforms["Linux-x86_64-glibc"] == {
        package: "@github/copilot-linux-x64",
        package_version: "1.0.78",
        integrity: "sha512-QK3oMtAn9dIv+1u1kx0xNpZNtZxdI+uZVIyLl7myp+Oh2Uj8BLagVv6a7uP0cDphO3TgfIdlvpepCe5MIcx0fw==",
        binary: "node_modules/@github/copilot-linux-x64/copilot",
        executable_sha256: "7e87127e53dc5f9ebc33663287ea05c6e55f1de254adfd9b7d17936d7d65a51c",
        runtime_tree_sha256: "e80b4e541dda932fef319f79a14944c7e24acedb74b22c6dd8a6e7b015bbe386"
      } and
      .copilot.platforms["Linux-aarch64-musl"] == {
        package: "@github/copilot-linuxmusl-arm64",
        package_version: "1.0.78",
        integrity: "sha512-F/0cTMsz6ug4yiXn3RKaCAMsLR261U5Njb6G9Y/HeAI7ES/tKEo2t5SHuvgXaIH4mYiZsRvfDKdX7c0WgBX/Jg==",
        binary: "node_modules/@github/copilot-linuxmusl-arm64/copilot",
        executable_sha256: "feb9fc61493ec0e469bc2ca330ece29410559d8eaaba5a3d813e3c9cb3ea6110",
        runtime_tree_sha256: "ea7b29df5af9782ea6c0dc3f69a76c5e24ed5dad5698bcdf4ea14533771b9d98"
      } and
      .copilot.platforms["Linux-x86_64-musl"] == {
        package: "@github/copilot-linuxmusl-x64",
        package_version: "1.0.78",
        integrity: "sha512-YMaJaeBGbArGAFYel+yFaFW/0rFgh0Oqki2f2mUtlonTX/xHr8EB4+mTnMJkHYMFy4gOTC3OtSEEe1NaW/cBXQ==",
        binary: "node_modules/@github/copilot-linuxmusl-x64/copilot",
        executable_sha256: "a16c45dd92dab88f3b9f1d2135f160d7e39d411b1ca0110457420d417015a076",
        runtime_tree_sha256: "1e8c490d6e06819f6d9ea1b1dfe9f789009286957a00baedd2d35c0844a70ad3"
      }
    ' "$NATIVE_DIR/hosts.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .engines.node == ">=22" and
      .dependencies["@github/copilot"] == "1.0.78"
    ' "$NATIVE_DIR/package.json"
    [[ "$status" -eq 0 ]]

    run jq -e --slurpfile hosts "$NATIVE_DIR/hosts.json" '
      $hosts[0].copilot as $expected |
      .packages[""] as $workspace |
      .packages["node_modules/@github/copilot"] as $root |
      .packages["node_modules/detect-libc"] as $dependency |
      $workspace.engines.node == ">=22" and
      $workspace.dependencies["@github/copilot"] == $expected.version and
      $root.version == $expected.version and
      $root.resolved ==
        "https://registry.npmjs.org/@github/copilot/-/copilot-1.0.78.tgz" and
      $root.integrity == $expected.integrity and
      $root.dependencies == {"detect-libc": "^2.1.2"} and
      ([
        $root.optionalDependencies | to_entries[] |
        select(.key | test("^@github/copilot-(darwin|linux|linuxmusl)-(arm64|x64)$"))
      ] | length) == 6 and
      all($expected.platforms[];
        $root.optionalDependencies[.package] == .package_version) and
      $dependency.version == $expected.dependency.version and
      $dependency.resolved ==
        "https://registry.npmjs.org/detect-libc/-/detect-libc-2.1.2.tgz" and
      $dependency.integrity == $expected.dependency.integrity
    ' "$NATIVE_DIR/package-lock.json"
    [[ "$status" -eq 0 ]]

    while IFS=$'\t' read -r key package version integrity; do
        local lock_path="node_modules/$package"
        run jq -e \
          --arg key "$key" \
          --arg package "$package" \
          --arg path "$lock_path" \
          --arg version "$version" \
          --arg integrity "$integrity" '
            .packages[$path] as $locked |
            ($package | split("/")[-1]) as $name |
            $locked.version == $version and
            $locked.resolved ==
              ("https://registry.npmjs.org/" + $package + "/-/" + $name + "-" + $version + ".tgz") and
            $locked.integrity == $integrity and
            $locked.optional == true and
            $locked.cpu == [if ($package | endswith("arm64")) then "arm64" else "x64" end] and
            $locked.os == [if ($key | startswith("Darwin-")) then "darwin" else "linux" end] and
            (if ($key | endswith("-glibc")) then $locked.libc == ["glibc"]
             elif ($key | endswith("-musl")) then $locked.libc == ["musl"]
             else ($locked | has("libc") | not)
             end)
          ' "$NATIVE_DIR/package-lock.json"
        [[ "$status" -eq 0 ]]
    done < <(jq -r '.copilot.platforms | to_entries[] |
        [.key, .value.package, .value.package_version, .value.integrity] | @tsv' \
        "$NATIVE_DIR/hosts.json")
}

@test "native Claude host pins stable metadata signed release identity and every Unix runtime" {
    run jq -e '
      .claude.package == "@anthropic-ai/claude-code" and
      .claude.channel == "stable" and
      .claude.version == "2.1.220" and
      .claude.integrity ==
        "sha512-ogBrvwkqF9f8okmnXKxmRNHuvtFxFEffe5pWdqOV3iQDxlUOKirFqnyWC7NGXXnDA4WkkbPH8pvSbwyCR2Auyw==" and
      .claude.package_tree_sha256 ==
        "48c63b70077572c889931dd9024d3253aef33a7f558efd63a72287915228f154" and
      .claude.stub == "node_modules/@anthropic-ai/claude-code/bin/claude.exe" and
      .claude.stub_sha256 ==
        "6d7abae055d3b598281300a6c835086dec81bf3048f8a2294c5d3e50c8830d7b" and
      .claude.cli_wrapper == "node_modules/@anthropic-ai/claude-code/cli-wrapper.cjs" and
      .claude.cli_wrapper_sha256 ==
        "61ad63033d9c8155d5e60a29f45dc4665afa07631c0b108e62cc83bf45ba490e" and
      .claude.installer == "node_modules/@anthropic-ai/claude-code/install.cjs" and
      .claude.installer_sha256 ==
        "5cbab1670597f492cd4eeb946f3c344ebcb1fbd43c623ba192c9b33744461b85" and
      .claude.signed_release_manifest == {
        sha256: "40f281ff188f1cd4f39309da41a219014dad2555d96e9780c67a2138720d12ed",
        signature_sha256: "63ed32a9d1b382728ea3855a62aaf7ad19d2c7bdcb3eae91959f5bb1e316c99f",
        signing_key_sha256: "bd70a5e4a268002704024ceba7f8446024114e94f3f0bdd11c23a9e592be81c6",
        signing_key_fingerprint: "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE",
        commit: "4073f59596e272f39393db4f96abc5f4b10eff21",
        build_date: "2026-07-24T22:28:51Z"
      } and
      (.claude.platforms | keys | sort) == [
        "Darwin-arm64-none",
        "Darwin-x86_64-none",
        "Linux-aarch64-glibc",
        "Linux-aarch64-musl",
        "Linux-x86_64-glibc",
        "Linux-x86_64-musl"
      ] and
      .claude.platforms["Darwin-arm64-none"] == {
        package: "@anthropic-ai/claude-code-darwin-arm64",
        package_version: "2.1.220",
        integrity: "sha512-rmtd41Bf+n+YnhjSjtQ8WG5qy8KKogUp3YRfQrkLsTgPUD0H3j869rBInBJT3SHrKQ0hLghQLGM73CC1C+USLQ==",
        binary: "node_modules/@anthropic-ai/claude-code-darwin-arm64/claude",
        executable_sha256: "8addc857f3fe64d5a0368af9ee50321b50afb4a6918ba3ef018ab84f5dbbe081",
        package_tree_sha256: "6da681d4bb400bbffde53853dafc72ee4b004d3c150e3bd8c41df0e2b98a89ec",
        runtime_tree_sha256: "8e1106b53bdfc9501a20f6db370fbf3a99a8269eae3cf83a5648a7f5a1ebf385"
      } and
      .claude.platforms["Darwin-x86_64-none"] == {
        package: "@anthropic-ai/claude-code-darwin-x64",
        package_version: "2.1.220",
        integrity: "sha512-hbuoG+YCo37VzSKzKJ47ymRmt/YjASc3dRcsZtCcftLYdopv8KL889x/IbCl3cfp/VqV2rRDZ0f3aUDpHUFweQ==",
        binary: "node_modules/@anthropic-ai/claude-code-darwin-x64/claude",
        executable_sha256: "dca7be0aa7d3d924836d440e0c6d8e3d47ef3c8e61fa5809b54b9017170ce2f3",
        package_tree_sha256: "cc36d73a7be3c4b28e210ea59f7ec27248b8d28efa25fddd6ff3ecff10c76f67",
        runtime_tree_sha256: "49ddfd04e6f432f85112100e2430d54818c6e5622b11c6d7e1fa1976ecbd431f"
      } and
      .claude.platforms["Linux-aarch64-glibc"] == {
        package: "@anthropic-ai/claude-code-linux-arm64",
        package_version: "2.1.220",
        integrity: "sha512-VHFI8mKruIntKn7eq81sbyS19/KWmQcmJQsS/C+j9M/E+w0s4UytgsL7DADPjBE/GByNiKoRtLYDMntCjRlOdA==",
        binary: "node_modules/@anthropic-ai/claude-code-linux-arm64/claude",
        executable_sha256: "159e4a51d796f3bf14677577100f7efb845611b1ceaf0c30cbd8d4650d942185",
        package_tree_sha256: "2586a9a24559a93d848017c1d07e55226fc9a0c9f20bc0b717b3f640b9e44afe",
        runtime_tree_sha256: "8226f69c94fd9ce96627dde9ab9300308edb23ef9f788b24b29b9d45a7af32be"
      } and
      .claude.platforms["Linux-x86_64-glibc"] == {
        package: "@anthropic-ai/claude-code-linux-x64",
        package_version: "2.1.220",
        integrity: "sha512-3CGFCnI0gpgsqNeJruFALBDGJaKXOuok3alQEg56ty2yOPpIrOx/r2Y0+T4uhJl7kP5Hzw4IFkxo4DZKWvzQ7Q==",
        binary: "node_modules/@anthropic-ai/claude-code-linux-x64/claude",
        executable_sha256: "674f61f20ff306f3100cf9200e4c36c4b70278b5bef2884549819b942a89c863",
        package_tree_sha256: "20a769f239501b51e64d60814bb04460587ef694464cb426dfeab39a3c1d7077",
        runtime_tree_sha256: "56ffb3acc9a257d0681e6b2d1798d70e34454ecc69cf56398a49d4a0713f5924"
      } and
      .claude.platforms["Linux-aarch64-musl"] == {
        package: "@anthropic-ai/claude-code-linux-arm64-musl",
        package_version: "2.1.220",
        integrity: "sha512-m37ALw8jcbSknuyG7xDQjGPY7Gth3eX8iFY1XFEWABVq1iUMVAUn96WC9eqwi8/JSqyG2t3oNRiqHdi2ZNKFGQ==",
        binary: "node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude",
        executable_sha256: "5eb2697a1500c1b8736e53fd696392196dc6758cf1d470c64d8d2a2fd1629eeb",
        package_tree_sha256: "b0449d2447b346b9d5d4c74b1b1c33d25d63ebd4ef2262d682727296be437dc4",
        runtime_tree_sha256: "2d42d47eed2dd5a22210b7bbc156153bfd77f2182e3ce3e5bf77facab061e19e"
      } and
      .claude.platforms["Linux-x86_64-musl"] == {
        package: "@anthropic-ai/claude-code-linux-x64-musl",
        package_version: "2.1.220",
        integrity: "sha512-+QyT1KikOdMRKReWFaBYGsroYx2vEjjx54DwhMoC24oE1DxjC+SlKjeOTRXAKiu0fr0O549Lkhg2tuT5xtQpAQ==",
        binary: "node_modules/@anthropic-ai/claude-code-linux-x64-musl/claude",
        executable_sha256: "f1c20514a3571cdf9982e25c490042d740ed7cfed3f00c64ba92dc7ec47c3c5b",
        package_tree_sha256: "71415f838000b7b7a069fd78d2c8ea6c2e53c85a1582a76bdd901258e5ae4328",
        runtime_tree_sha256: "d5b808b8bf2e0b24918dfcea2bae0349535aa0fb5cc664756fdb6424545c7cfe"
      }
    ' "$NATIVE_DIR/hosts.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .engines.node == ">=22" and
      .dependencies["@anthropic-ai/claude-code"] == "2.1.220"
    ' "$NATIVE_DIR/package.json"
    [[ "$status" -eq 0 ]]

    run jq -e --slurpfile hosts "$NATIVE_DIR/hosts.json" '
      $hosts[0].claude as $expected |
      .packages[""] as $workspace |
      .packages["node_modules/@anthropic-ai/claude-code"] as $root |
      $workspace.engines.node == ">=22" and
      $workspace.dependencies["@anthropic-ai/claude-code"] == $expected.version and
      $root.version == $expected.version and
      $root.resolved ==
        "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.220.tgz" and
      $root.integrity == $expected.integrity and
      $root.hasInstallScript == true and
      $root.bin == {claude: "bin/claude.exe"} and
      $root.engines == {node: ">=22.0.0"} and
      ([
        $root.optionalDependencies | to_entries[] |
        select(.key | test("^@anthropic-ai/claude-code-(darwin|linux)-"))
      ] | length) == 6 and
      all($expected.platforms[];
        $root.optionalDependencies[.package] == .package_version)
    ' "$NATIVE_DIR/package-lock.json"
    [[ "$status" -eq 0 ]]

    while IFS=$'\t' read -r key package version integrity; do
        local lock_path="node_modules/$package"
        run jq -e \
          --arg key "$key" \
          --arg package "$package" \
          --arg path "$lock_path" \
          --arg version "$version" \
          --arg integrity "$integrity" '
            .packages[$path] as $locked |
            ($package | split("/")[-1]) as $name |
            $locked.version == $version and
            $locked.resolved ==
              ("https://registry.npmjs.org/" + $package + "/-/" + $name + "-" + $version + ".tgz") and
            $locked.integrity == $integrity and
            $locked.optional == true and
            $locked.cpu == [if ($package | test("arm64(-musl)?$")) then "arm64" else "x64" end] and
            $locked.os == [if ($key | startswith("Darwin-")) then "darwin" else "linux" end] and
            (if ($key | endswith("-glibc")) then $locked.libc == ["glibc"]
             elif ($key | endswith("-musl")) then $locked.libc == ["musl"]
             else ($locked | has("libc") | not)
             end)
          ' "$NATIVE_DIR/package-lock.json"
        [[ "$status" -eq 0 ]]
    done < <(jq -r '.claude.platforms | to_entries[] |
        [.key, .value.package, .value.package_version, .value.integrity] | @tsv' \
        "$NATIVE_DIR/hosts.json")
}

@test "Gemini fixture requests one exact sentinel then completes after denial" {
    run jq -e -s '
      length == 2 and
      all(.[]; .method == "generateContentStream") and
      .[0].response[0].candidates[0].content.parts[0].functionCall == {
        name: "run_shell_command",
        args: {
          command: "tofu destroy -auto-approve",
          description: "Run the native-host certification sentinel."
        }
      } and
      .[1].response[0].candidates[0].content.parts[0].text ==
        "MAINFRAME native host certification observed the policy result."
    ' "$NATIVE_DIR/fixtures/gemini-destroy.responses.jsonl"

    [[ "$status" -eq 0 ]]
}

@test "Codex fixture requests one exact exec call then completes after tool output" {
    run jq -e '
      .schema_version == 1 and
      .call_id == "mainframe-codex-destroy" and
      .command == "__MAINFRAME_SENTINEL_TOFU__ destroy -auto-approve" and
      .final_text == "MAINFRAME native host certification observed the policy result." and
      (.responses | length) == 2 and
      .responses[0][1].item == {
        type: "function_call",
        call_id: "mainframe-codex-destroy",
        name: "exec_command",
        arguments: "{\"cmd\":\"__MAINFRAME_SENTINEL_TOFU__ destroy -auto-approve\",\"shell\":\"__MAINFRAME_CERT_SHELL__\"}"
      } and
      .responses[1][1].item.content == [{
        type: "output_text",
        text: "MAINFRAME native host certification observed the policy result."
      }]
    ' "$NATIVE_DIR/fixtures/codex-destroy.responses.json"
    [[ "$status" -eq 0 ]]

    run python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-destroy.responses.json" \
      --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Codex Responses fixture valid" ]]

    run python3 -c \
      'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
      "$NATIVE_DIR/fixtures/codex-destroy.responses.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "adb6f847dd47e9c8e765d36bfd348d0ea7c345fffcfcdbe660593ba92d75b77d" ]]
}

@test "Codex destroy diagnostics expose only fixed error classes" {
    run python3 - "$NATIVE_DIR/codex-responses-server.py" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("mainframe_codex_diagnostics", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

private_path = "/tmp/private/mainframe-native-123-456/sentinel-bin/tofu"
bearer = "user-bearer-secret"
api_key = "user-api-key-secret"
json_token = "SENSITIVE_JSON_VALUE"
json_password = "SENSITIVE_PASS_VALUE"
raw = (
    f"exec_command failed for {private_path}: sandbox startup denied; "
    "bwrap could not create a user namespace: Operation not permitted\n"
    f"Authorization: Bearer {bearer}\n"
    f"api_key={api_key}\n"
    f'{{"token":"{json_token}","password":"{json_password}"}}\n'
    + ("x" * 2500)
)
diagnostic = module.destroy_function_output_diagnostic(raw)
assert diagnostic == {
    "bytes": len(raw.encode("utf-8")),
    "signals": [
        "sandbox_denied",
        "operation_not_permitted",
        "bubblewrap",
        "user_namespace",
    ],
}
rendered = json.dumps(diagnostic, sort_keys=True)
assert private_path not in rendered
assert "mainframe-native-123-456" not in rendered
assert bearer not in rendered
assert api_key not in rendered
assert json_token not in rendered
assert json_password not in rendered
assert "exec_command failed" not in rendered
print("Codex destroy diagnostics expose only fixed error classes")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Codex destroy diagnostics expose only fixed error classes" ]]
}

@test "Copilot fixture requests one exact bash call and has a fixed digest" {
    local fixture="$NATIVE_DIR/fixtures/copilot-destroy.chat-completions.json"

    run jq -e '
      . == {
        schema_version: 1,
        call_id: "mainframe-copilot-destroy",
        command: "tofu destroy -auto-approve",
        description: "Run the native-host certification sentinel.",
        mode: "sync",
        final_text: "MAINFRAME native host certification observed the policy result."
      }
    ' "$fixture"
    [[ "$status" -eq 0 ]]

    run python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$fixture" --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Copilot Chat Completions fixture valid" ]]

    run python3 -c \
      'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
      "$fixture"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "f79a034d619f89b2743d240919d47a0829104093fd358d4bb4a68487b3f96de9" ]]
}

@test "Claude fixture requests one exact Bash call and has a fixed digest" {
    local fixture="$NATIVE_DIR/fixtures/claude-destroy.messages.json"

    run jq -e '
      . == {
        schema_version: 1,
        call_id: "mainframe-claude-destroy",
        command: "tofu destroy -auto-approve",
        description: "Run the native-host certification sentinel.",
        final_text: "MAINFRAME native host certification observed the policy result."
      }
    ' "$fixture"
    [[ "$status" -eq 0 ]]

    run python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$fixture" --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Claude Messages fixture valid" ]]

    run python3 -c \
      'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
      "$fixture"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "aede0aba3a0c5dc12bcf098ba087148fb9e8f116838b8b79e9470639c4eee5f8" ]]
}

@test "AWM-chain fixtures use one exact nonce-free command and host-native metadata" {
    local gemini_fixture="$NATIVE_DIR/fixtures/gemini-awm-chain.responses.jsonl"
    local codex_fixture="$NATIVE_DIR/fixtures/codex-awm-chain.responses.json"
    local copilot_fixture="$NATIVE_DIR/fixtures/copilot-awm-chain.chat-completions.json"
    local claude_fixture="$NATIVE_DIR/fixtures/claude-awm-chain.messages.json"
    local gemini_command codex_command copilot_command claude_command

    run jq -e -s '
      length == 2 and
      .[0].response[0].candidates[0].content.parts[0].functionCall == {
        id: "mainframe-gemini-awm-chain",
        name: "run_shell_command",
        args: {
          command: .[0].response[0].candidates[0].content.parts[0].functionCall.args.command,
          description: "Run the MAINFRAME AWM chain step for Gemini."
        }
      } and
      .[1].response[0].candidates[0].content.parts[0].text ==
        "MAINFRAME AWM chain step completed for Gemini."
    ' "$gemini_fixture"
    [[ "$status" -eq 0 ]]

    run jq -e '
      . as $fixture |
      ($fixture.responses[0][1].item.arguments | fromjson) as $arguments |
      $fixture.schema_version == 1 and
      $fixture.call_id == "mainframe-codex-awm-chain" and
      ($fixture | has("description") | not) and
      $fixture.responses[0][1].item.type == "function_call" and
      $fixture.responses[0][1].item.call_id == "mainframe-codex-awm-chain" and
      $fixture.responses[0][1].item.name == "exec_command" and
      $arguments == {cmd: $fixture.command, shell: "__MAINFRAME_CERT_SHELL__"} and
      $fixture.responses[1][1].item.content == [{
        type: "output_text",
        text: "MAINFRAME AWM chain step completed for Codex."
      }]
    ' "$codex_fixture"
    [[ "$status" -eq 0 ]]

    run jq -e '
      . == {
        schema_version: 1,
        call_id: "mainframe-copilot-awm-chain",
        command: .command,
        description: "Run the MAINFRAME AWM chain step for Copilot.",
        mode: "sync",
        final_text: "MAINFRAME AWM chain step completed for Copilot."
      }
    ' "$copilot_fixture"
    [[ "$status" -eq 0 ]]

    run jq -e '
      . == {
        schema_version: 1,
        call_id: "mainframe-claude-awm-chain",
        command: .command,
        description: "Run the MAINFRAME AWM chain step for Claude.",
        final_text: "MAINFRAME AWM chain step completed for Claude."
      }
    ' "$claude_fixture"
    [[ "$status" -eq 0 ]]

    gemini_command="$(jq -er -s \
      '.[0].response[0].candidates[0].content.parts[0].functionCall.args.command' \
      "$gemini_fixture")"
    codex_command="$(jq -er .command "$codex_fixture")"
    copilot_command="$(jq -er .command "$copilot_fixture")"
    claude_command="$(jq -er .command "$claude_fixture")"

    run jq -n -e \
      --arg gemini "$gemini_command" \
      --arg codex "$codex_command" \
      --arg copilot "$copilot_command" \
      --arg claude "$claude_command" '
        def expected:
          "mainframe awm get --session \"$MAINFRAME_AWM_SESSION\" \"$MAINFRAME_AWM_READ_KEY\" > \"$MAINFRAME_AWM_SCRATCH\" || { printf \u0027MAINFRAME_AWM_MISSING_PREDECESSOR\\n\u0027 >&2; exit 42; }; printf \u0027\\n\u0027 >> \"$MAINFRAME_AWM_SCRATCH\" && IFS= read -r previous < \"$MAINFRAME_AWM_SCRATCH\" && test -n \"$previous\" && : > \"$MAINFRAME_AWM_SCRATCH\" && next=\"${previous}:${MAINFRAME_AGENT_NAME}\" && mainframe awm checkpoint --session \"$MAINFRAME_AWM_SESSION\" \"$MAINFRAME_AWM_WRITE_KEY\" \"$next\" --importance high --tags \"native-awm,$MAINFRAME_AGENT_NAME\" && printf \u0027MAINFRAME_AWM_CHAIN_OK:%s\\n\u0027 \"$MAINFRAME_AGENT_NAME\"";
        $gemini == expected and
        $codex == expected and
        $copilot == expected and
        $claude == expected and
        (expected | contains("nonce") | not) and
        (expected | contains("MAINFRAME_AWM_BIN") | not) and
        (expected | contains("$(") | not) and
        (expected | contains("\u0060") | not) and
        (expected | test("[0-9A-Fa-f]{32,}") | not)
      '
    [[ "$status" -eq 0 ]]

    local node_bin
    node_bin="$(command -v node)" || skip "Node.js is required for canonical gate parity"
    run env \
      MAINFRAME_AWM_SESSION=c4dddce87c34 \
      MAINFRAME_AWM_READ_KEY=chain.seed \
      MAINFRAME_AWM_WRITE_KEY=chain.gemini \
      MAINFRAME_AWM_SCRATCH=/tmp/mainframe-native-awm-chain.scratch \
      MAINFRAME_AGENT_NAME=gemini \
      "$node_bin" --input-type=module - "$PROJECT_ROOT" "$gemini_command" <<'JS'
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { join } from "node:path";

const root = process.argv[2];
const command = process.argv[3];
const runtime = await import(pathToFileURL(join(root, "security", "gate-normalizer.mjs")).href);
const document = JSON.parse(readFileSync(join(root, "security", "gate-rules.json"), "utf8"));
const result = runtime.classifyGateCommand(command, document.rules, process.env);
if (result.tier !== "low" || result.id !== "none") {
  throw new Error(`AWM fixture is not gateway-safe: ${JSON.stringify(result)}`);
}
console.log("AWM fixture is a canonical low-risk command");
JS
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM fixture is a canonical low-risk command" ]]

    run python3 -c '
import hashlib
import sys
for path in sys.argv[1:]:
    print(hashlib.sha256(open(path, "rb").read()).hexdigest())
' "$gemini_fixture" "$codex_fixture" "$copilot_fixture" "$claude_fixture"
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'7f6b596c454becb6d0eeafaf0d98db418d652cf1130f503556cc3fe0d7f4c999\n177bca6ac99803e17194bf339f733fa729ee2d508c39741fd8ff885129c9d6bf\n0cdf1e627d957795818b9e8b3c81d68df41280aa8868b59e828a174d95f07037\n5a2b2b9a136e6c0648d136f1ddaa26318ef029bf09a1b2884d739eb742bb203c' ]]
}

@test "AWM-chain loopback fixture scenarios are explicit exact and isolated from destroy" {
    run python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-awm-chain.responses.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Codex Responses AWM-chain fixture valid" ]]
    run python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-awm-chain.responses.json" --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-destroy.responses.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-destroy.responses.json" \
      --scenario destroy --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Codex Responses fixture valid" ]]

    run python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$NATIVE_DIR/fixtures/copilot-awm-chain.chat-completions.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Copilot Chat Completions AWM-chain fixture valid" ]]
    run python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$NATIVE_DIR/fixtures/copilot-awm-chain.chat-completions.json" --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$NATIVE_DIR/fixtures/copilot-destroy.chat-completions.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$NATIVE_DIR/fixtures/copilot-destroy.chat-completions.json" \
      --scenario destroy --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Copilot Chat Completions fixture valid" ]]

    run python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$NATIVE_DIR/fixtures/claude-awm-chain.messages.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Claude Messages AWM-chain fixture valid" ]]
    run python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$NATIVE_DIR/fixtures/claude-awm-chain.messages.json" --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$NATIVE_DIR/fixtures/claude-destroy.messages.json" \
      --scenario awm-chain --check-fixture
    [[ "$status" -ne 0 ]]
    run python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$NATIVE_DIR/fixtures/claude-destroy.messages.json" \
      --scenario destroy --check-fixture
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Claude Messages fixture valid" ]]
}

@test "AWM-chain servers accept only their concrete success marker" {
    run python3 - "$NATIVE_DIR" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

native = Path(sys.argv[1])


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, native / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


codex = load("mainframe_codex_fixture_server", "codex-responses-server.py")
copilot = load("mainframe_copilot_fixture_server", "copilot-chat-completions-server.py")
claude = load("mainframe_claude_fixture_server", "claude-messages-server.py")

assert codex.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:codex\n")
assert not codex.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:copilot\n")
assert not codex.awm_chain_output_succeeded(
    "MAINFRAME agent gateway blocked the tool call\nMAINFRAME_AWM_CHAIN_OK:codex"
)

assert copilot.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:copilot\n")
assert not copilot.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:claude\n")
assert not copilot.awm_chain_output_succeeded(
    "Denied by preToolUse hook: hook exited with code 2\nMAINFRAME_AWM_CHAIN_OK:copilot"
)

assert claude.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:claude\n", False)
assert not claude.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:codex\n", False)
assert not claude.awm_chain_output_succeeded("MAINFRAME_AWM_CHAIN_OK:claude\n", True)

destroy_fixtures = {
    codex: json.loads((native / "fixtures/codex-destroy.responses.json").read_text()),
    copilot: json.loads((native / "fixtures/copilot-destroy.chat-completions.json").read_text()),
    claude: json.loads((native / "fixtures/claude-destroy.messages.json").read_text()),
}
expected_default_keys = {
    codex: {
        "schema_version", "mode", "status", "requests", "advertised_exec_command",
        "function_output_seen", "denial_output_seen", "authorization_header_seen", "error",
    },
    copilot: {
        "schema_version", "mode", "status", "requests", "advertised_bash",
        "tool_output_seen", "denial_output_seen", "empty_authorization_seen",
        "user_credential_header_seen", "error",
    },
    claude: {
        "schema_version", "mode", "status", "requests", "advertised_bash",
        "tool_result_seen", "tool_result_is_error", "denial_output_seen",
        "placeholder_authorization_seen", "user_credential_header_seen", "error",
    },
}
for module, fixture in destroy_fixtures.items():
    assert set(module.FixtureState("control", fixture).summary()) == expected_default_keys[module]

print("AWM-chain success-marker predicates and default summaries valid")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM-chain success-marker predicates and default summaries valid" ]]
}

@test "AWM-chain servers keep request-hygiene secrets out of state and require exact missing-predecessor evidence" {
    run python3 - "$NATIVE_DIR" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

native = Path(sys.argv[1])


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, native / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


modules = [
    load("mainframe_codex_hygiene_server", "codex-responses-server.py"),
    load("mainframe_copilot_hygiene_server", "copilot-chat-completions-server.py"),
    load("mainframe_claude_hygiene_server", "claude-messages-server.py"),
]
raw_seed = "raw-seed-private"
derived = ["raw-seed-private:gemini", "raw-seed-private:codex"]
awm_root = "/private/mainframe-work/project/.mainframe-awm"
private_workdir = "/private/mainframe-work"
cases = [
    (derived[0], "derived-checkpoint"),
    (raw_seed, "raw-seed"),
    (awm_root, "awm-root"),
]

for module in modules:
    for leaked, expected_reason in cases:
        guard = module.RequestHygieneGuard(raw_seed, derived, awm_root)
        assert guard.inspect(f'{{"leak":"{leaked}"}}'.encode()) == expected_reason
        summary = guard.summary()
        assert summary == {
            "request_hygiene_checked": True,
            "request_hygiene_passed": False,
            "request_hygiene_checks": 1,
            "request_hygiene_rejections": 1,
            "request_hygiene_reason": expected_reason,
        }
        rendered = json.dumps(summary, sort_keys=True)
        assert all(secret not in rendered for secret in [raw_seed, *derived, awm_root, private_workdir])

    guard = module.RequestHygieneGuard(raw_seed, derived, awm_root)
    assert guard.inspect(b'{"safe":"request"}') is None
    assert guard.summary() == {
        "request_hygiene_checked": True,
        "request_hygiene_passed": True,
        "request_hygiene_checks": 1,
        "request_hygiene_rejections": 0,
        "request_hygiene_reason": None,
    }

valid_output = "Process exited with code 42\nMAINFRAME_AWM_MISSING_PREDECESSOR\n"
embedded_marker = "Process exited with code 42\nprefix MAINFRAME_AWM_MISSING_PREDECESSOR suffix\n"
wrong_exit = "Process exited with code 420\nMAINFRAME_AWM_MISSING_PREDECESSOR\n"
codex, copilot, claude = modules
for module in (codex, copilot):
    assert module.awm_missing_predecessor_output_succeeded(valid_output)
    assert not module.awm_missing_predecessor_output_succeeded(embedded_marker)
    assert not module.awm_missing_predecessor_output_succeeded(wrong_exit)
assert not codex.awm_missing_predecessor_output_succeeded(
    "MAINFRAME agent gateway blocked the tool call\n" + valid_output
)
assert not copilot.awm_missing_predecessor_output_succeeded(
    "Denied by preToolUse hook: hook exited with code 2\n" + valid_output
)
assert claude.awm_missing_predecessor_output_succeeded(valid_output, True)
assert not claude.awm_missing_predecessor_output_succeeded(valid_output, False)
assert not claude.awm_missing_predecessor_output_succeeded(embedded_marker, True)
assert not claude.awm_missing_predecessor_output_succeeded(wrong_exit, True)

fixtures = {
    codex: json.loads((native / "fixtures/codex-awm-chain.responses.json").read_text()),
    copilot: json.loads((native / "fixtures/copilot-awm-chain.chat-completions.json").read_text()),
    claude: json.loads((native / "fixtures/claude-awm-chain.messages.json").read_text()),
}
for module, fixture in fixtures.items():
    guard = module.RequestHygieneGuard(raw_seed, derived, awm_root)
    guard.inspect(b'{"safe":"first"}')
    guard.inspect(b'{"safe":"second"}')
    state = module.FixtureState(
        "control",
        fixture,
        module.AWM_CHAIN_SCENARIO,
        awm_expectation="missing-predecessor",
        request_hygiene=guard,
    )
    state.requests = 2
    state.missing_predecessor_marker_seen = True
    state.tool_result_nonzero = True
    summary = state.summary()
    assert summary["status"] == "expected-missing-predecessor"
    assert summary["requests"] == 2
    assert summary["missing_predecessor_marker_seen"] is True
    assert summary["tool_result_nonzero"] is True
    assert summary["request_hygiene_checked"] is True
    assert summary["request_hygiene_passed"] is True
    assert summary["request_hygiene_checks"] == 2
    rendered = json.dumps(summary, sort_keys=True)
    assert all(secret not in rendered for secret in [raw_seed, *derived, awm_root, private_workdir])

assert codex.AWM_MISSING_PREDECESSOR_FINAL_TEXT.encode() in codex.response_payload(
    fixtures[codex], 1, codex.AWM_MISSING_PREDECESSOR_FINAL_TEXT
)
assert copilot.AWM_MISSING_PREDECESSOR_FINAL_TEXT.encode() in copilot.completion_payload(
    fixtures[copilot], 1, copilot.AWM_MISSING_PREDECESSOR_FINAL_TEXT
)
assert claude.AWM_MISSING_PREDECESSOR_FINAL_TEXT.encode() in claude.response_payload(
    fixtures[claude], 1, claude.AWM_MISSING_PREDECESSOR_FINAL_TEXT
)

print("AWM-chain request-hygiene and missing-predecessor contracts valid")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM-chain request-hygiene and missing-predecessor contracts valid" ]]
}

@test "AWM-chain loopback servers complete exact two-request missing-predecessor conversations" {
    run python3 - "$NATIVE_DIR" "$TEST_DIR" <<'PY'
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import time

native = Path(sys.argv[1])
test_dir = Path(sys.argv[2])
raw_seed = "native-loopback-raw-seed"
derived = [f"{raw_seed}:gemini", f"{raw_seed}:codex", f"{raw_seed}:copilot"]
private_workdir = test_dir / "private-workdir"
awm_root = private_workdir / "project/.mainframe-awm"
private_workdir.mkdir()


def wait_ready(process, ready):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if ready.exists():
            return json.loads(ready.read_text())
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"server exited before ready: {stdout!r} {stderr!r}")
        time.sleep(0.02)
    process.kill()
    stdout, stderr = process.communicate()
    raise AssertionError(f"server did not become ready: {stdout!r} {stderr!r}")


def post(port, path, body, headers):
    encoded = json.dumps(body, separators=(",", ":")).encode()
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    connection.request("POST", path, body=encoded, headers=headers)
    response = connection.getresponse()
    payload = response.read()
    status = response.status
    connection.close()
    assert status == 200, payload
    return payload


def sse_json(payload):
    values = []
    for line in payload.decode().splitlines():
        if line.startswith("data: ") and line != "data: [DONE]":
            values.append(json.loads(line[6:]))
    return values


tools = {
    "codex": [
        {
            "type": "function",
            "name": "exec_command",
            "parameters": {"properties": {"cmd": {}, "shell": {}}},
        }
    ],
    "copilot": [
        {
            "type": "function",
            "function": {
                "name": "bash",
                "parameters": {
                    "properties": {
                        "command": {"type": "string"},
                        "description": {"type": "string"},
                    },
                    "required": ["command", "description"],
                },
            },
        }
    ],
    "claude": [
        {
            "name": "Bash",
            "input_schema": {
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        }
    ],
}
specs = {
    "codex": {
        "server": "codex-responses-server.py",
        "fixture": "codex-awm-chain.responses.json",
        "path": "/v1/responses",
        "call_id": "mainframe-codex-awm-chain",
        "final": "MAINFRAME AWM missing predecessor rejected for Codex.",
    },
    "copilot": {
        "server": "copilot-chat-completions-server.py",
        "fixture": "copilot-awm-chain.chat-completions.json",
        "path": "/v1/chat/completions",
        "call_id": "mainframe-copilot-awm-chain",
        "final": "MAINFRAME AWM missing predecessor rejected for Copilot.",
    },
    "claude": {
        "server": "claude-messages-server.py",
        "fixture": "claude-awm-chain.messages.json",
        "path": "/v1/messages?beta=true",
        "call_id": "mainframe-claude-awm-chain",
        "final": "MAINFRAME AWM missing predecessor rejected for Claude.",
    },
}

for host, spec in specs.items():
    ready = test_dir / f"{host}-missing-ready.json"
    state_path = test_dir / f"{host}-missing-state.json"
    command = [
        sys.executable,
        str(native / spec["server"]),
        "--fixture",
        str(native / "fixtures" / spec["fixture"]),
        "--scenario",
        "awm-chain",
        "--mode",
        "control",
        "--ready",
        str(ready),
        "--state",
        str(state_path),
        "--awm-expectation",
        "missing-predecessor",
        "--timeout",
        "5",
    ]
    if host == "codex":
        command.extend(["--shell", "/bin/bash"])
    environment = os.environ.copy()
    environment.update(
        {
            "MAINFRAME_AWM_GUARD_RAW_SEED": raw_seed,
            "MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON": json.dumps(derived),
            "MAINFRAME_AWM_GUARD_ROOT": str(awm_root),
        }
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    ready_value = wait_ready(process, ready)
    port = ready_value["port"]
    headers = {"Content-Type": "application/json"}
    if host == "claude":
        headers["Authorization"] = "Bearer mainframe-certification-placeholder"
    model = "mainframe-claude-certification" if host == "claude" else "gpt-5.5"

    if host == "codex":
        first = {"model": model, "stream": True, "tools": tools[host], "input": []}
        second = {
            "model": model,
            "stream": True,
            "tools": tools[host],
            "input": [
                {
                    "type": "function_call_output",
                    "call_id": spec["call_id"],
                    "output": "Process exited with code 42\nMAINFRAME_AWM_MISSING_PREDECESSOR\n",
                }
            ],
        }
    elif host == "copilot":
        first = {"model": model, "stream": True, "tools": tools[host], "messages": []}
        second = {
            "model": model,
            "stream": True,
            "tools": tools[host],
            "messages": [
                {
                    "role": "tool",
                    "tool_call_id": spec["call_id"],
                    "content": "Command exited with code 42\nMAINFRAME_AWM_MISSING_PREDECESSOR\n",
                }
            ],
        }
    else:
        first = {"model": model, "stream": True, "tools": tools[host], "messages": []}
        second = {
            "model": model,
            "stream": True,
            "tools": tools[host],
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": spec["call_id"],
                            "content": "Command exited with code 42\nMAINFRAME_AWM_MISSING_PREDECESSOR\n",
                            "is_error": True,
                        }
                    ],
                }
            ],
        }

    first_response = post(port, spec["path"], first, headers)
    second_response = post(port, spec["path"], second, headers)
    stdout, stderr = process.communicate(timeout=5)
    assert process.returncode == 0, (stdout, stderr)

    events = sse_json(second_response)
    if host == "codex":
        texts = [
            event["item"]["content"][0]["text"]
            for event in events
            if event.get("type") == "response.output_item.done"
            and event.get("item", {}).get("type") == "message"
        ]
    elif host == "copilot":
        texts = [
            event["choices"][0]["delta"]["content"]
            for event in events
            if "content" in event["choices"][0]["delta"]
        ]
    else:
        texts = [
            event["delta"]["text"]
            for event in events
            if event.get("type") == "content_block_delta"
            and event.get("delta", {}).get("type") == "text_delta"
        ]
    assert texts == [spec["final"]]

    state = json.loads(state_path.read_text())
    assert state["status"] == "expected-missing-predecessor"
    assert state["requests"] == 2
    assert state["success_marker_seen"] is False
    assert state["missing_predecessor_marker_seen"] is True
    assert state["tool_result_nonzero"] is True
    assert state["request_hygiene_checked"] is True
    assert state["request_hygiene_passed"] is True
    assert state["request_hygiene_checks"] == 2
    assert state["request_hygiene_rejections"] == 0
    assert state["request_hygiene_reason"] is None
    rendered = first_response + second_response + state_path.read_bytes()
    for secret in [raw_seed, *derived, str(awm_root), str(private_workdir)]:
        assert secret.encode() not in rendered

print("AWM-chain missing-predecessor loopback conversations valid")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM-chain missing-predecessor loopback conversations valid" ]]
}

@test "AWM-chain loopback servers reject every guarded AWM value before request parsing without echoing it" {
    run python3 - "$NATIVE_DIR" "$TEST_DIR" <<'PY'
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import time

native = Path(sys.argv[1])
test_dir = Path(sys.argv[2])
raw_seed = "request-secret-raw-seed"
derived = [f"{raw_seed}:gemini", f"{raw_seed}:codex"]
private_workdir = test_dir / "secret-private-workdir"
awm_root = private_workdir / "project/.mainframe-awm"
private_workdir.mkdir()


def wait_ready(process, ready):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if ready.exists():
            return json.loads(ready.read_text())
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"server exited before ready: {stdout!r} {stderr!r}")
        time.sleep(0.02)
    process.kill()
    process.communicate()
    raise AssertionError("server did not become ready")


cases = [
    ("codex-raw", "codex-responses-server.py", "codex-awm-chain.responses.json", "/v1/responses", raw_seed, "raw-seed"),
    ("copilot-derived", "copilot-chat-completions-server.py", "copilot-awm-chain.chat-completions.json", "/v1/chat/completions", derived[0], "derived-checkpoint"),
    ("claude-root", "claude-messages-server.py", "claude-awm-chain.messages.json", "/v1/messages?beta=true", str(awm_root), "awm-root"),
]

for name, server, fixture, path, leaked, reason in cases:
    ready = test_dir / f"{name}-ready.json"
    state_path = test_dir / f"{name}-state.json"
    command = [
        sys.executable,
        str(native / server),
        "--fixture",
        str(native / "fixtures" / fixture),
        "--scenario",
        "awm-chain",
        "--mode",
        "control",
        "--ready",
        str(ready),
        "--state",
        str(state_path),
        "--timeout",
        "5",
    ]
    if server == "codex-responses-server.py":
        command.extend(["--shell", "/bin/bash"])
    environment = os.environ.copy()
    environment.update(
        {
            "MAINFRAME_AWM_GUARD_RAW_SEED": raw_seed,
            "MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON": json.dumps(derived),
            "MAINFRAME_AWM_GUARD_ROOT": str(awm_root),
        }
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    port = wait_ready(process, ready)["port"]
    raw = f'{{"leak":"{leaked}"}}'.encode()
    headers = {"Content-Type": "application/json"}
    if server == "claude-messages-server.py":
        headers["Authorization"] = "Bearer mainframe-certification-placeholder"
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    connection.request("POST", path, body=raw, headers=headers)
    response = connection.getresponse()
    response_body = response.read()
    connection.close()
    assert response.status == 400
    stdout, stderr = process.communicate(timeout=5)
    assert process.returncode != 0
    state = json.loads(state_path.read_text())
    assert state["status"] == "error"
    assert state["requests"] == 0
    assert state["request_hygiene_checked"] is True
    assert state["request_hygiene_passed"] is False
    assert state["request_hygiene_checks"] == 1
    assert state["request_hygiene_rejections"] == 1
    assert state["request_hygiene_reason"] == reason
    rendered = response_body + state_path.read_bytes() + stdout.encode() + stderr.encode()
    assert leaked.encode() not in rendered
    assert raw_seed.encode() not in rendered
    assert all(value.encode() not in rendered for value in derived)
    assert str(awm_root).encode() not in rendered
    assert str(private_workdir).encode() not in rendered

print("AWM-chain raw request-hygiene rejection values valid")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM-chain raw request-hygiene rejection values valid" ]]
}

@test "Gemini certifier derives the installed privileged hook and isolates the control" {
    local driver="$PROJECT_ROOT/scripts/dev/certify-native-host.sh"
    local required

    run "$BASH_BIN" -n "$driver"
    [[ "$status" -eq 0 ]]

    for required in \
      'installed_activate="$workdir/extracted/lib/activate.sh"' \
      '_mainframe_enforce_bind_runtime "$2"' \
      '_mainframe_enforce_command_for gemini' \
      'jq -e --arg command "$expected_hook_command"' \
      '.hooks.BeforeTool == [{' \
      'matcher: "run_shell_command"' \
      'hooks: [{type: "command", command: $command}]' \
      'MAINFRAME_AGENT_BASH="$protected_agent_bash"' \
      'MAINFRAME_AGENT_JQ="$protected_agent_jq"' \
      'MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"' \
      'MAINFRAME_AGENT_SAFETY="$protected_agent_safety"' \
      'MAINFRAME_AGENT_SEAL="$protected_agent_seal"' \
      'resolved_tofu="$(PATH="$cert_path" type -P tofu)"' \
      'seal_extra <<< "$protected_agent_seal"' \
      "grep -Fq 'Runtime load: UNVERIFIED'"; do
        run rg -n --fixed-strings -- "$required" "$driver"
        [[ "$status" -eq 0 ]]
    done

    run rg -n 'env[[:space:]].*command -v tofu' "$driver"
    [[ "$status" -ne 0 ]]

    run python3 - "$driver" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()

exact_config_check = '''jq -e --arg command "$expected_hook_command" '
  .hooks.BeforeTool == [{
    matcher: "run_shell_command",
    hooks: [{type: "command", command: $command}]
  }]
'''
assert exact_config_check in text

for invocation in (
    'activate gemini --project "$workdir/control/project"',
    'activate gemini --project "$workdir/protected/project" --enforce',
    'protect status gemini --project "$workdir/protected/project"',
):
    pattern = (
        r'MAINFRAME_BASH="\$bash_bin" PATH="\$cert_path" \\\n\s*'
        + re.escape('"$mainframe_bin" ' + invocation)
    )
    assert re.search(pattern, text), invocation

run_gemini = re.search(r'^run_gemini\(\) \{\n(?P<body>.*?)^\}', text, re.MULTILINE | re.DOTALL)
assert run_gemini is not None
body = run_gemini.group('body')
control = re.search(r'^\s*control\)\n(?P<body>.*?)^\s*;;', body, re.MULTILINE | re.DOTALL)
protected = re.search(r'^\s*protected\)\n(?P<body>.*?)^\s*;;', body, re.MULTILINE | re.DOTALL)
assert control is not None
assert protected is not None
assert 'env -i' in body
assert '[[ -z "$audit" ]] || return 1' in control.group('body')
assert 'MAINFRAME_AGENT_' not in control.group('body')

bindings = (
    'MAINFRAME_AGENT_BASH="$protected_agent_bash"',
    'MAINFRAME_AGENT_JQ="$protected_agent_jq"',
    'MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"',
    'MAINFRAME_AGENT_SAFETY="$protected_agent_safety"',
    'MAINFRAME_AGENT_SEAL="$protected_agent_seal"',
)
for binding in bindings:
    assert binding not in control.group('body')
    assert protected.group('body').count(binding) == 1

for name in (
    'MAINFRAME_AGENT_BASH',
    'MAINFRAME_AGENT_JQ',
    'MAINFRAME_AGENT_GATEWAY',
    'MAINFRAME_AGENT_SAFETY',
    'MAINFRAME_AGENT_SEAL',
):
    assert f'"$expected_hook_command" == *\'{name}\'*' in text

assert '(.hooks.BeforeTool // []) | length == 0' in text
print('Gemini certifier privileged-hook contract valid')
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Gemini certifier privileged-hook contract valid" ]]

    run rg -n --fixed-strings -- \
      'mainframe agent-hook --format gemini || exit 2' "$driver"
    [[ "$status" -ne 0 ]]
}

@test "Codex certifier derives the privileged hook and disables ambient host features" {
    local driver="$NATIVE_DIR/certify-codex.sh"
    local required

    run rg -n --fixed-strings -- "-c 'check_for_update_on_startup=false'" \
      "$driver"
    [[ "$status" -eq 0 ]]
    run rg -n --fixed-strings -- "--disable in_app_updates" \
      "$driver"
    [[ "$status" -eq 0 ]]
    run rg -n --fixed-strings -- "-c 'allow_login_shell=false'" \
      "$driver"
    [[ "$status" -eq 0 ]]
    run rg -n --fixed-strings -- "--strict-config" \
      "$driver"
    [[ "$status" -eq 0 ]]
    run rg -n --fixed-strings -- "--disable shell_snapshot" \
      "$driver"
    [[ "$status" -eq 0 ]]
    run rg -n --fixed-strings -- "cannot invalidate stale evidence output" \
      "$driver"
    [[ "$status" -eq 0 ]]

    for required in \
      '_mainframe_enforce_command_for codex' \
      '_mainframe_enforce_bind_runtime "$workdir/protected/project"' \
      'jq -e --arg command "$expected_hook_command"' \
      'if [[ "$run" == protected ]]; then' \
      'MAINFRAME_AGENT_BASH="$protected_agent_bash"' \
      'MAINFRAME_AGENT_JQ="$protected_agent_jq"' \
      'MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"' \
      'MAINFRAME_AGENT_SAFETY="$protected_agent_safety"' \
      'MAINFRAME_AGENT_SEAL="$protected_agent_seal"' \
      'protected_agent_safety="$MAINFRAME_AGENT_SAFETY"' \
      'protected_agent_seal="$MAINFRAME_AGENT_SEAL"' \
      'expected_agent_seal="$(' \
      '"$(sha256_file "$protected_agent_safety")"' \
      '[[ "$protected_agent_seal" == "$expected_agent_seal" ]]' \
      '"$workdir/$run/project/sentinel-bin/tofu"' \
      '--sentinel "$workdir/$run/project/sentinel-bin/tofu"' \
      'PATH="$workdir/$run/project/sentinel-bin:$cert_path"' \
      'dump_run_diagnostics control' \
      'dump_run_diagnostics protected'; do
        run rg -n --fixed-strings -- "$required" "$driver"
        [[ "$status" -eq 0 ]]
    done

    run rg -n --fixed-strings -- 'MAINFRAME_NATIVE_CANARY_' "$driver"
    [[ "$status" -ne 0 ]]

    run rg -n --fixed-strings -- \
      'mainframe agent-hook --format codex || exit 2' "$driver"
    [[ "$status" -ne 0 ]]
}

@test "Copilot certifier uses offline BYOK exact-project trust and a PATH-first sentinel" {
    local driver="$NATIVE_DIR/certify-copilot.sh"
    local required

    run "$BASH_BIN" -n "$driver"
    [[ "$status" -eq 0 ]]

    for required in \
      'Node.js 22+ is required' \
      'cannot invalidate stale evidence output' \
      '{trustedFolders: [$project]}' \
      '. == {trustedFolders: [$project]}' \
      'activate copilot --project "$workdir/control/project"' \
      'activate copilot --project "$workdir/protected/project" --enforce' \
      '_mainframe_enforce_command_for copilot' \
      'jq -e --arg command "$expected_copilot_hook_command"' \
      '_mainframe_enforce_bind_runtime "$1"' \
      'case "$mode" in' \
      'MAINFRAME_AGENT_BASH="$protected_gateway_bash"' \
      'MAINFRAME_AGENT_JQ="$protected_gateway_jq"' \
      'MAINFRAME_AGENT_GATEWAY="$protected_gateway_script"' \
      'MAINFRAME_AGENT_SAFETY="$protected_gateway_safety"' \
      'MAINFRAME_AGENT_SEAL="$protected_gateway_seal"' \
      '[[ "${#protected_hook_bindings[@]}" -eq 5 ]]' \
      'protected_gateway_safety="${protected_hook_bindings[3]}"' \
      'protected_gateway_seal="${protected_hook_bindings[4]}"' \
      '[[ "$protected_gateway_safety" == "$installed_root/lib/agent_safety.sh" &&' \
      '[[ "$protected_gateway_seal" =~ ^([0-9a-f]{64}:){3}[0-9a-f]{64}$ ]]' \
      'COPILOT_HOME="$workdir/$run/copilot-home"' \
      'COPILOT_OFFLINE=true' \
      'COPILOT_AUTO_UPDATE=false' \
      'COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:$current_server_port/v1' \
      'COPILOT_PROVIDER_TYPE=openai' \
      'COPILOT_PROVIDER_WIRE_API=completions' \
      'COPILOT_MODEL=gpt-5.5' \
      'host_version="$(env -i' \
      'command: "tofu destroy -auto-approve"' \
      'def started_calls:' \
      '(requested_calls | length == 1)' \
      '(started_calls | length == 1)' \
      '(completed_calls | length == 1)' \
      'resolved_tofu' \
      '-C "$workdir/$run/project"' \
      'Run tofu destroy -auto-approve exactly once.' \
      '--allow-all-tools' \
      '--available-tools=bash' \
      '--no-auto-update' \
      '--no-remote' \
      '--no-remote-export' \
      '--disable-builtin-mcps' \
      '--no-experimental' \
      '--no-custom-instructions' \
      '--no-bash-env' \
      '--no-ask-user' \
      '--no-color' \
      '--log-level=error' \
      '--output-format=json' \
      'stderr_log="$workdir/$run/host.stderr.log"' \
      ') >"$log" 2>"$stderr_log"; then' \
      'stderr_size="$(wc -c < "$stderr_log" | tr -d '\''[:space:]'\'')"' \
      '"$stderr_size" -gt 65536'; do
        run rg -n --fixed-strings -- "$required" "$driver"
        [[ "$status" -eq 0 ]]
    done

    run rg -n --fixed-strings -- ') >"$log" 2>&1; then' "$driver"
    [[ "$status" -ne 0 ]]

    run rg -n --fixed-strings -- 'GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS' "$driver"
    [[ "$status" -ne 0 ]]
    run rg -n --fixed-strings -- '--allow-all-paths' "$driver"
    [[ "$status" -ne 0 ]]
    run rg -n 'COPILOT_PROVIDER_(API_KEY|TOKEN)=' "$driver"
    [[ "$status" -ne 0 ]]
    run rg -n '(^|[[:space:]])(GH_TOKEN|GITHUB_TOKEN)=' "$driver"
    [[ "$status" -ne 0 ]]
    run rg -n --fixed-strings -- \
      'mainframe agent-hook --format copilot || exit 2' "$driver"
    [[ "$status" -ne 0 ]]

    local version_line invalidation_line
    for driver in \
      "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" \
      "$NATIVE_DIR/certify-codex.sh" \
      "$NATIVE_DIR/certify-copilot.sh" \
      "$NATIVE_DIR/certify-claude.sh"; do
        version_line="$(rg -n '^VERSION=' "$driver" | cut -d: -f1)"
        invalidation_line="$(rg -n 'cannot invalidate stale evidence output' "$driver" | cut -d: -f1)"
        [[ "$version_line" =~ ^[0-9]+$ ]]
        [[ "$invalidation_line" =~ ^[0-9]+$ ]]
        [[ "$invalidation_line" -lt "$version_line" ]]
    done
}

@test "Claude certifier directly executes an isolated native binary with exact hook proof" {
    local driver="$NATIVE_DIR/certify-claude.sh"
    local required

    run "$BASH_BIN" -n "$driver"
    [[ "$status" -eq 0 ]]

    for required in \
      'Node.js 22+ is required' \
      'cannot invalidate stale evidence output' \
      'npm ci --prefix scripts/dev/native-host --ignore-scripts --no-audit --no-fund' \
      'certified_binary="$workdir/host-runtime/$binary_relative"' \
      'cp -R "$host_package" "$workdir/host-runtime/node_modules/@anthropic-ai/"' \
      'cp -R "$platform_package" "$workdir/host-runtime/node_modules/@anthropic-ai/"' \
      'chmod -R a-w "$workdir/host-runtime"' \
      'host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_runtime_root")"' \
      'host_version="$(env -i' \
      '"$certified_binary" --version' \
      'exec "${environment[@]}" "$certified_binary"' \
      'runtime_launch_mode: "npm-ignore-scripts-direct-platform-binary"' \
      'host_cli_wrapper_executed: false' \
      '--arg fixture_server_sha256 "$fixture_server_sha"' \
      'fixture_server_sha256: $fixture_server_sha256' \
      'activate claude-code --project "$workdir/control/project"' \
      'activate claude-code --project "$workdir/protected/project" --enforce' \
      '_mainframe_enforce_command_for claude-code' \
      '--arg command "$expected_hook_command"' \
      '_mainframe_enforce_bind_runtime "$1"' \
      'server_args+=(--protected-hook-command "$expected_hook_command")' \
      '--arg hook_command "$expected_hook_command"' \
      'MAINFRAME_AGENT_BASH="$protected_gateway_bash"' \
      'MAINFRAME_AGENT_JQ="$protected_gateway_jq"' \
      'MAINFRAME_AGENT_GATEWAY="$protected_gateway_script"' \
      'MAINFRAME_AGENT_SAFETY="$protected_gateway_safety"' \
      'MAINFRAME_AGENT_SEAL="$protected_gateway_seal"' \
      '[[ "${#protected_hook_bindings[@]}" -eq 5 ]]' \
      'protected_gateway_safety="${protected_hook_bindings[3]}"' \
      'protected_gateway_seal="${protected_hook_bindings[4]}"' \
      '[[ "$protected_gateway_safety" == "$installed_root/lib/agent_safety.sh" &&' \
      'protected_gateway_safety_sha="$(sha256_file "$protected_gateway_safety")"' \
      '"$protected_gateway_bash_sha:$protected_gateway_jq_sha:$protected_gateway_script_sha:$protected_gateway_safety_sha" ]]' \
      'ANTHROPIC_BASE_URL=http://127.0.0.1:$current_server_port' \
      'ANTHROPIC_AUTH_TOKEN=mainframe-certification-placeholder' \
      'CLAUDE_CONFIG_DIR="$workdir/$run/claude-config"' \
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' \
      'CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1' \
      '-p --output-format stream-json --verbose --include-hook-events' \
      '--no-session-persistence --setting-sources project' \
      '--strict-mcp-config --mcp-config '\''{"mcpServers":{}}'\''' \
      '--tools Bash --allowedTools '\''Bash(tofu destroy -auto-approve)'\''' \
      '--permission-mode dontAsk --disable-slash-commands --no-chrome' \
      'def hook_starts:' \
      'def hook_responses:' \
      'hook_starts[0].hook_name == "PreToolUse:Bash"' \
      'hook_starts[0].hook_event == "PreToolUse"' \
      'hook_responses[0].exit_code == 2' \
      'hook_responses[0].outcome == "error"' \
      'tool_results[0].is_error == true' \
      'result_records[0].permission_denials == [{' \
      'credential_mode: "claude-loopback-messages-synthetic-bearer-no-user-credentials"' \
      'provider_user_credentials_supplied: false' \
      'network_boundary: "loopback-base-url-and-nonessential-traffic-disabled"' \
      'project_trust_mode: "claude-print-mode-trust-verification-disabled"' \
      'settings_sources: "project-only"' \
      'managed_settings_present: false' \
      'permission_mode: "dontAsk"' \
      'tool_surface: "Bash-only-exact-command-allow"' \
      'control_executions: 1' \
      'protected_executions: 0' \
      'protected_hook_started: 1' \
      'protected_hook_responses: 1' \
      'protected_hook_exit_code: 2' \
      'for ((drain_attempt = 0; drain_attempt < 50; drain_attempt++)); do' \
      'dump_run_diagnostics control' \
      'dump_run_diagnostics protected' \
      '"host=claude"' \
      '"event=PreToolUse"' \
      '"tool=Bash"' \
      '"risk=high"' \
      '"rule=terraform-destroy"' \
      '"decision=deny"'; do
        run rg -n --fixed-strings -- "$required" "$driver"
        [[ "$status" -eq 0 ]]
    done

    for forbidden in \
      '--bare' \
      '--safe-mode' \
      '--dangerously-skip-permissions' \
      '--permission-mode bypassPermissions' \
      'bypassPermissionsModeAccepted' \
      'hasTrustDialogAccepted' \
      'ANTHROPIC_API_KEY=' \
      'CLAUDE_CODE_OAUTH_TOKEN='; do
        run rg -n --fixed-strings -- "$forbidden" "$driver"
        [[ "$status" -ne 0 ]]
    done

    run rg -n --fixed-strings -- \
      'mainframe agent-hook --format claude || exit 2' "$driver"
    [[ "$status" -ne 0 ]]

    run rg -n 'exec .*\b(installed_stub|installed_wrapper|installed_installer|certified_stub|certified_wrapper|certified_installer)\b' \
      "$driver"
    [[ "$status" -ne 0 ]]
}

@test "Codex fixture server rejects credential-bearing requests before serving a response" {
    local ready="$TEST_DIR/codex-ready.json"
    local state="$TEST_DIR/codex-state.json"
    local server_log="$TEST_DIR/codex-server.log"
    local sentinel="$TEST_DIR/tofu"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$sentinel"
    chmod 0755 "$sentinel"

    python3 "$NATIVE_DIR/codex-responses-server.py" \
      --fixture "$NATIVE_DIR/fixtures/codex-destroy.responses.json" \
      --mode control --ready "$ready" --state "$state" --sentinel "$sentinel" \
      --shell /bin/bash --timeout 10 \
      >"$server_log" 2>&1 &
    local server_pid=$!
    for _ in {1..200}; do
        [[ -s "$ready" ]] && break
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.05
    done
    [[ -s "$ready" ]]
    local port
    port="$(jq -er .port "$ready")"

    run curl --silent --show-error --output "$TEST_DIR/codex-response.json" \
      --header 'Authorization: Bearer forbidden' \
      --header 'Content-Type: application/json' \
      --data '{}' "http://127.0.0.1:${port}/v1/responses"
    [[ "$status" -eq 0 ]]

    set +e
    wait "$server_pid"
    local server_status=$?
    set -e
    [[ "$server_status" -ne 0 ]]
    run jq -e '
      .status == "error" and
      .requests == 0 and
      .authorization_header_seen == true and
      (.error | contains("credential header is forbidden"))
    ' "$state"
    [[ "$status" -eq 0 ]]
}

@test "Copilot fixture server rejects a non-empty provider credential before serving" {
    local ready="$TEST_DIR/copilot-ready.json"
    local state="$TEST_DIR/copilot-state.json"
    local server_log="$TEST_DIR/copilot-server.log"

    python3 "$NATIVE_DIR/copilot-chat-completions-server.py" \
      --fixture "$NATIVE_DIR/fixtures/copilot-destroy.chat-completions.json" \
      --mode control --ready "$ready" --state "$state" --timeout 10 \
      >"$server_log" 2>&1 &
    local server_pid=$!
    for _ in {1..200}; do
        [[ -s "$ready" ]] && break
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.05
    done
    [[ -s "$ready" ]]
    local port
    port="$(jq -er .port "$ready")"

    run curl --silent --show-error --output "$TEST_DIR/copilot-response.json" \
      --header 'Authorization: Bearer forbidden' \
      --header 'Content-Type: application/json' \
      --data '{}' "http://127.0.0.1:${port}/v1/chat/completions"
    [[ "$status" -eq 0 ]]

    set +e
    wait "$server_pid"
    local server_status=$?
    set -e
    [[ "$server_status" -ne 0 ]]
    run jq -e '
      .status == "error" and
      .requests == 0 and
      .user_credential_header_seen == true and
      .empty_authorization_seen == false and
      (.error | contains("non-empty Authorization credential is forbidden"))
    ' "$state"
    [[ "$status" -eq 0 ]]
}

@test "Claude fixture server accepts only its synthetic bearer and rejects ambient credentials" {
    local fixture="$NATIVE_DIR/fixtures/claude-destroy.messages.json"
    local ready="$TEST_DIR/claude-wrong-bearer-ready.json"
    local state="$TEST_DIR/claude-wrong-bearer-state.json"
    local server_log="$TEST_DIR/claude-wrong-bearer-server.log"

    python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$fixture" --mode control --ready "$ready" --state "$state" \
      --timeout 10 >"$server_log" 2>&1 &
    local server_pid=$!
    for _ in {1..200}; do
        [[ -s "$ready" ]] && break
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.05
    done
    [[ -s "$ready" ]]
    local port
    port="$(jq -er .port "$ready")"

    run curl --silent --show-error --output "$TEST_DIR/claude-wrong-bearer-response.json" \
      --header 'Authorization: Bearer real-user-credential-is-forbidden' \
      --header 'Content-Type: application/json' \
      --data '{}' "http://127.0.0.1:${port}/v1/messages?beta=true"
    [[ "$status" -eq 0 ]]

    set +e
    wait "$server_pid"
    local server_status=$?
    set -e
    [[ "$server_status" -ne 0 ]]
    run jq -e '
      .status == "error" and
      .requests == 0 and
      .placeholder_authorization_seen == false and
      .user_credential_header_seen == true and
      (.error | contains("exact placeholder Authorization header is required"))
    ' "$state"
    [[ "$status" -eq 0 ]]

    ready="$TEST_DIR/claude-api-key-ready.json"
    state="$TEST_DIR/claude-api-key-state.json"
    server_log="$TEST_DIR/claude-api-key-server.log"
    python3 "$NATIVE_DIR/claude-messages-server.py" \
      --fixture "$fixture" --mode control --ready "$ready" --state "$state" \
      --timeout 10 >"$server_log" 2>&1 &
    server_pid=$!
    for _ in {1..200}; do
        [[ -s "$ready" ]] && break
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.05
    done
    [[ -s "$ready" ]]
    port="$(jq -er .port "$ready")"

    run curl --silent --show-error --output "$TEST_DIR/claude-api-key-response.json" \
      --header 'Authorization: Bearer mainframe-certification-placeholder' \
      --header 'X-Api-Key: real-user-credential-is-forbidden' \
      --header 'Content-Type: application/json' \
      --data '{}' "http://127.0.0.1:${port}/v1/messages?beta=true"
    [[ "$status" -eq 0 ]]

    set +e
    wait "$server_pid"
    server_status=$?
    set -e
    [[ "$server_status" -ne 0 ]]
    run jq -e '
      .status == "error" and
      .requests == 0 and
      .placeholder_authorization_seen == true and
      .user_credential_header_seen == true and
      (.error | contains("credential header X-Api-Key is forbidden"))
    ' "$state"
    [[ "$status" -eq 0 ]]

    run rg -n 'LoopbackHTTPServer\(\("127\.0\.0\.1", 0\)' \
      "$NATIVE_DIR/claude-messages-server.py"
    [[ "$status" -eq 0 ]]
    run rg -n 'self\.path != "/v1/messages\?beta=true"' \
      "$NATIVE_DIR/claude-messages-server.py"
    [[ "$status" -eq 0 ]]
}

@test "native evidence schema fixes the paired-control and denial contract" {
    run jq -e '
      .properties.certification.const == "execution-certified" and
      (.required | index("host_package_integrity")) != null and
      (.required | index("host_package_tree_sha256")) != null and
      (.required | index("host_executable_sha256")) != null and
      (.required | index("archive_origin")) != null and
      .properties.control_executions.const == 1 and
      .properties.protected_executions.const == 0 and
      .properties.credential_mode.const ==
        "gemini-fake-responses-no-external-credentials" and
      .properties.audit.properties == {
        host: {const: "gemini"},
        event: {const: "BeforeTool"},
        tool: {const: "run_shell_command"},
        risk: {const: "high"},
        rule: {const: "terraform-destroy"},
        decision: {const: "deny"},
        records: {const: 1},
        mode: {const: "600"}
      }
    ' "$NATIVE_DIR/evidence.schema.json"

    [[ "$status" -eq 0 ]]
}

@test "loopback fixture servers bind without reverse DNS" {
    local fixture_server
    for fixture_server in \
        "$NATIVE_DIR/codex-responses-server.py" \
        "$NATIVE_DIR/copilot-chat-completions-server.py" \
        "$NATIVE_DIR/claude-messages-server.py"; do
        run rg -n --fixed-strings -- \
            'server = LoopbackHTTPServer(("127.0.0.1", 0), handler_for(state))' \
            "$fixture_server"
        [[ "$status" -eq 0 ]]
        run rg -n --fixed-strings -- 'server = HTTPServer(' "$fixture_server"
        [[ "$status" -eq 1 ]]
    done

    run python3 - \
        "$NATIVE_DIR/codex-responses-server.py" \
        "$NATIVE_DIR/copilot-chat-completions-server.py" \
        "$NATIVE_DIR/claude-messages-server.py" <<'PY'
import importlib.util
import pathlib
import socket
import sys


def forbidden_getfqdn(_host: str = "") -> str:
    raise AssertionError("reverse DNS must not run for a loopback fixture")


original_getfqdn = socket.getfqdn
socket.getfqdn = forbidden_getfqdn
try:
    for index, raw_path in enumerate(sys.argv[1:]):
        path = pathlib.Path(raw_path)
        spec = importlib.util.spec_from_file_location(f"fixture_server_{index}", path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with module.LoopbackHTTPServer(
            ("127.0.0.1", 0), module.BaseHTTPRequestHandler
        ) as server:
            assert server.server_name == "127.0.0.1"
            assert server.server_address[0] == "127.0.0.1"
            assert 0 < server.server_port < 65536
            assert server.server_port == server.server_address[1]
finally:
    socket.getfqdn = original_getfqdn
PY
    [[ "$status" -eq 0 ]]
}

@test "native evidence validator enforces every field and rejects extras" {
    local evidence="$TEST_DIR/evidence.json"
    local invalid="$TEST_DIR/evidence-invalid.json"

    jq -n '{
      schema_version: 1,
      certification: "execution-certified",
      host: "gemini",
      host_version: "0.53.1",
      host_package_integrity: "sha512-YWJjZA==",
      host_package_tree_sha256: ("e" * 64),
      host_executable_sha256: ("a" * 64),
      mainframe_version: "10.1.0",
      archive_sha256: ("b" * 64),
      archive_origin: "workspace-build",
      hook_config_sha256: ("c" * 64),
      os: "Linux",
      arch: "x86_64",
      system_libc: "glibc",
      source_git_commit: ("d" * 40),
      source_git_dirty: false,
      credential_mode: "gemini-fake-responses-no-external-credentials",
      control_executions: 1,
      protected_executions: 0,
      audit: {
        host: "gemini",
        event: "BeforeTool",
        tool: "run_shell_command",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: "2026-08-04T17:27:04Z"
    }' > "$evidence"

    run python3 "$NATIVE_DIR/validate-evidence.py" \
        "$NATIVE_DIR/evidence.schema.json" "$evidence"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "native-host evidence valid" ]]

    jq '.unexpected = true' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
        "$NATIVE_DIR/evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected keys"* ]]
}

@test "Codex evidence schema requires the platform runtime and exact denial tuple" {
    local evidence="$TEST_DIR/codex-evidence.json"
    local invalid="$TEST_DIR/codex-evidence-invalid.json"

    jq -n '{
      schema_version: 1,
      certification: "execution-certified",
      host: "codex",
      host_version: "0.146.0",
      host_package_integrity: "sha512-yG3sPWNda/2YAIQIDq9MrrjoCTIQ7rxYM5IasrG3VBcuhCLTkgeg/JzqmJq1V98RE4MJ5jCxDXXQlOjrditFRw==",
      host_platform_package: "@openai/codex-darwin-arm64",
      host_platform_version: "0.146.0-darwin-arm64",
      host_platform_package_integrity: "sha512-nb61yX4r5L6Z0dlC4o3u0GAK1YCd4TUvjaB382bajDoh84V+uv2hTBIVZ++fgXWV9yoeuNrNnNcn7GoTGOe2Tg==",
      host_package_tree_sha256: "a262d29e1dae17e6913b742a9d6b16ecf640cd66831100e4af2ee7e1ff40c99f",
      host_launcher_sha256: "134063e133f0b4244fa3b251acf973d4fe4b4aeeacbdc135211bf480f59f1477",
      host_executable_sha256: "ae1d3ffe6d48aec6a4dc3f50e7eb8e0d11962485a6a9406c5a7012139383da02",
      mainframe_version: "10.1.0",
      archive_sha256: ("b" * 64),
      archive_origin: "workspace-build",
      hook_config_sha256: ("c" * 64),
      fixture_sha256: "adb6f847dd47e9c8e765d36bfd348d0ea7c345fffcfcdbe660593ba92d75b77d",
      os: "Darwin",
      arch: "arm64",
      system_libc: "none",
      source_git_commit: ("d" * 40),
      source_git_dirty: false,
      credential_mode: "codex-loopback-responses-no-external-credentials",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      control_executions: 1,
      protected_executions: 0,
      audit: {
        host: "codex",
        event: "PreToolUse",
        tool: "Bash",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: "2026-08-04T17:27:04Z"
    }' > "$evidence"

    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/codex-evidence.schema.json" "$evidence"
    [[ "$status" -eq 0 ]]

    jq '.audit.host = "gemini"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/codex-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant 'codex'"* ]]

    jq '.arch = "x86_64"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/codex-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no anyOf alternative matched"* ]]
}

@test "Copilot evidence schema binds a valid runtime and rejects platform or audit drift" {
    local evidence="$TEST_DIR/copilot-evidence.json"
    local invalid="$TEST_DIR/copilot-evidence-invalid.json"

    jq -n '{
      schema_version: 1,
      certification: "execution-certified",
      host: "copilot",
      host_version: "1.0.78",
      host_package_integrity: "sha512-jn+8HLZC3R7d6K1/1g9L1iWNKzBVS3JdVcx40r3aWyS5r+MLV1OPNp0fo5OfRMCDIm3NmEaaoqypi9sQkCXuiQ==",
      host_dependency_package: "detect-libc",
      host_dependency_version: "2.1.2",
      host_dependency_integrity: "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==",
      host_platform_package: "@github/copilot-darwin-arm64",
      host_platform_version: "1.0.78",
      host_platform_package_integrity: "sha512-P11+VyWg8ad0WlywGtO2d7AxqTLJv4hkUicFg6Ycth5lfk00aCu/74YOOZSPO6C2bBBJhAza7oAdmauM6KEojw==",
      host_package_tree_sha256: "07b33e72d4a35ddc992abd2b0e6a4a0d0cc351772c9df7a1dc1e767372299af2",
      host_launcher_sha256: "0ea824a86be5757533fdb092eff7050871bd7a711a46babde0ffe0e44ac5ad88",
      host_executable_sha256: "1dd966fa15f5ad042c6c1b0272f36fee6ae82b1f175037499a6c19596bd9b291",
      mainframe_version: "10.1.0",
      archive_sha256: ("b" * 64),
      archive_origin: "workspace-build",
      hook_config_sha256: ("c" * 64),
      fixture_sha256: "f79a034d619f89b2743d240919d47a0829104093fd358d4bb4a68487b3f96de9",
      os: "Darwin",
      arch: "arm64",
      libc: "none",
      system_libc: "none",
      source_git_commit: ("d" * 40),
      source_git_dirty: false,
      credential_mode: "copilot-offline-loopback-chat-completions-no-user-credentials",
      provider_wire_api: "chat-completions",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      project_trust_mode: "isolated-copilot-home-exact-project",
      provider_user_credentials_supplied: false,
      control_executions: 1,
      protected_executions: 0,
      control_tool_success: true,
      protected_tool_denied: true,
      protected_denial: "Denied by preToolUse hook: hook exited with code 2",
      audit: {
        host: "copilot",
        event: "PreToolUse",
        tool: "bash",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: "2026-08-04T17:27:04Z"
    }' > "$evidence"

    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/copilot-evidence.schema.json" "$evidence"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "native-host evidence valid" ]]

    jq '.libc = "glibc"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/copilot-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no anyOf alternative matched"* ]]

    jq '.audit.tool = "Bash"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/copilot-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant 'bash'"* ]]
}

@test "Claude evidence schema binds signed direct-native proof and rejects security drift" {
    local evidence="$TEST_DIR/claude-evidence.json"
    local invalid="$TEST_DIR/claude-evidence-invalid.json"

    run python3 - "$NATIVE_DIR/claude-messages-server.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" <<'PY'
import hashlib
import json
import sys

server = hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest()
schema = json.load(open(sys.argv[2], encoding="utf-8"))
assert schema["properties"]["fixture_server_sha256"]["const"] == server
print("Claude fixture server bytes match the evidence schema pin")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Claude fixture server bytes match the evidence schema pin" ]]

    jq -n '{
      schema_version: 1,
      certification: "execution-certified",
      host: "claude",
      host_channel: "stable",
      host_version: "2.1.220",
      host_package_integrity: "sha512-ogBrvwkqF9f8okmnXKxmRNHuvtFxFEffe5pWdqOV3iQDxlUOKirFqnyWC7NGXXnDA4WkkbPH8pvSbwyCR2Auyw==",
      host_platform_package: "@anthropic-ai/claude-code-darwin-arm64",
      host_platform_version: "2.1.220",
      host_platform_package_integrity: "sha512-rmtd41Bf+n+YnhjSjtQ8WG5qy8KKogUp3YRfQrkLsTgPUD0H3j869rBInBJT3SHrKQ0hLghQLGM73CC1C+USLQ==",
      host_package_root_tree_sha256: "48c63b70077572c889931dd9024d3253aef33a7f558efd63a72287915228f154",
      host_package_tree_sha256: "8e1106b53bdfc9501a20f6db370fbf3a99a8269eae3cf83a5648a7f5a1ebf385",
      host_stub_sha256: "6d7abae055d3b598281300a6c835086dec81bf3048f8a2294c5d3e50c8830d7b",
      host_cli_wrapper_sha256: "61ad63033d9c8155d5e60a29f45dc4665afa07631c0b108e62cc83bf45ba490e",
      host_installer_sha256: "5cbab1670597f492cd4eeb946f3c344ebcb1fbd43c623ba192c9b33744461b85",
      host_executable_sha256: "8addc857f3fe64d5a0368af9ee50321b50afb4a6918ba3ef018ab84f5dbbe081",
      host_release_manifest_sha256: "40f281ff188f1cd4f39309da41a219014dad2555d96e9780c67a2138720d12ed",
      host_release_manifest_signature_sha256: "63ed32a9d1b382728ea3855a62aaf7ad19d2c7bdcb3eae91959f5bb1e316c99f",
      host_release_signing_key_fingerprint: "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE",
      host_release_commit: "4073f59596e272f39393db4f96abc5f4b10eff21",
      host_release_build_date: "2026-07-24T22:28:51Z",
      runtime_launch_mode: "npm-ignore-scripts-direct-platform-binary",
      host_cli_wrapper_executed: false,
      mainframe_version: "10.1.0",
      archive_sha256: ("b" * 64),
      archive_origin: "workspace-build",
      hook_config_sha256: ("c" * 64),
      fixture_sha256: "aede0aba3a0c5dc12bcf098ba087148fb9e8f116838b8b79e9470639c4eee5f8",
      fixture_server_sha256: "ea4b0c3d41edd9826d8b6aef4ad34ac91febe2ab480d70d0a2c12f0c7b5fd539",
      os: "Darwin",
      arch: "arm64",
      libc: "none",
      system_libc: "none",
      source_git_commit: ("d" * 40),
      source_git_dirty: false,
      credential_mode: "claude-loopback-messages-synthetic-bearer-no-user-credentials",
      provider_wire_api: "anthropic-messages",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      provider_placeholder_authorization: true,
      provider_user_credentials_supplied: false,
      network_boundary: "loopback-base-url-and-nonessential-traffic-disabled",
      project_trust_mode: "claude-print-mode-trust-verification-disabled",
      settings_sources: "project-only",
      managed_settings_present: false,
      permission_mode: "dontAsk",
      tool_surface: "Bash-only-exact-command-allow",
      control_executions: 1,
      protected_executions: 0,
      control_tool_success: true,
      protected_tool_denied: true,
      protected_hook_started: 1,
      protected_hook_responses: 1,
      protected_hook_exit_code: 2,
      protected_denial: "MAINFRAME agent gateway blocked the tool call: risk=high rule=terraform-destroy",
      audit: {
        host: "claude",
        event: "PreToolUse",
        tool: "Bash",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: "2026-08-04T17:27:04Z"
    }' > "$evidence"

    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$evidence"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "native-host evidence valid" ]]

    jq '.runtime_launch_mode = "npm-wrapper"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant 'npm-ignore-scripts-direct-platform-binary'"* ]]

    jq '.host_cli_wrapper_executed = true' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant False"* ]]

    jq '.provider_user_credentials_supplied = true' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant False"* ]]

    jq '.managed_settings_present = true' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant False"* ]]

    jq '.fixture_server_sha256 = ("0" * 64)' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant 'ea4b0c3d41edd9826d8b6aef4ad34ac91febe2ab480d70d0a2c12f0c7b5fd539'"* ]]

    jq '.host_release_commit = ("0" * 40)' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant '4073f59596e272f39393db4f96abc5f4b10eff21'"* ]]

    jq '.arch = "x86_64"' "$evidence" > "$invalid"
    run python3 "$NATIVE_DIR/validate-evidence.py" \
      "$NATIVE_DIR/claude-evidence.schema.json" "$invalid"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no anyOf alternative matched"* ]]
}

@test "package-tree identity changes with imported content and rejects symlinks" {
    local package_tree="$TEST_DIR/package"
    mkdir -p "$package_tree/bundle"
    printf '%s\n' 'import "./chunk.js";' > "$package_tree/bundle/entry.js"
    printf '%s\n' 'export const policy = "safe";' > "$package_tree/bundle/chunk.js"

    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    local original_digest="$output"

    printf '%s\n' 'export const policy = "modified";' > "$package_tree/bundle/chunk.js"
    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree"
    [[ "$status" -eq 0 ]]
    [[ "$output" != "$original_digest" ]]

    ln -s chunk.js "$package_tree/bundle/linked.js"
    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"contains a symbolic link"* ]]
}

@test "package-tree selected directories match an equivalent pruned tree" {
    local source_tree="$TEST_DIR/source-package"
    local expected_tree="$TEST_DIR/expected-package"
    local tree
    for tree in "$source_tree" "$expected_tree"; do
        mkdir -p "$tree/@github/copilot/bin" "$tree/detect-libc"
        printf '%s\n' 'copilot launcher' > "$tree/@github/copilot/bin/copilot.js"
        printf '%s\n' 'detect libc' > "$tree/detect-libc/index.js"
    done
    mkdir -p "$source_tree/unrelated"
    printf '%s\n' 'ignored content' > "$source_tree/unrelated/data.txt"

    run python3 "$NATIVE_DIR/hash-package-tree.py" "$source_tree" \
      "@github/copilot" "@github/copilot/bin" "detect-libc"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    local selected_digest="$output"

    run python3 "$NATIVE_DIR/hash-package-tree.py" "$expected_tree"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$selected_digest" ]]

    printf '%s\n' 'changed but still ignored' > "$source_tree/unrelated/data.txt"
    run python3 "$NATIVE_DIR/hash-package-tree.py" "$source_tree" \
      "detect-libc" "@github/copilot"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$selected_digest" ]]
}

@test "package-tree identity includes unexpected empty and duplicate selected-package siblings" {
    local package_tree="$TEST_DIR/selected-package-siblings"
    mkdir -p "$package_tree/detect-libc/lib"
    printf '%s\n' '{"name":"detect-libc"}' > "$package_tree/detect-libc/package.json"
    printf '%s\n' 'module.exports = true;' > "$package_tree/detect-libc/index.js"

    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree" detect-libc
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    local clean_digest="$output"

    mkdir "$package_tree/detect-libc/lib 2"
    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree" detect-libc
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    [[ "$output" != "$clean_digest" ]]
    rmdir "$package_tree/detect-libc/lib 2"

    cp "$package_tree/detect-libc/package.json" \
        "$package_tree/detect-libc/package 2.json"
    local injected_name=$'forged\nERROR: injected'
    printf '%s\n' 'untrusted path' > \
        "$package_tree/detect-libc/$injected_name"
    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree" detect-libc
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    [[ "$output" != "$clean_digest" ]]

    run python3 "$NATIVE_DIR/hash-package-tree.py" \
        --expected "$clean_digest" \
        --installed-label "Copilot wrapper-dependency-platform" \
        "$package_tree" detect-libc
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"ERROR: installed Copilot wrapper-dependency-platform tree does not match host manifest"* ]]
    [[ "$output" == *"installed-tree contamination or incomplete package data"* ]]
    [[ "$output" == *"expected selected-tree SHA-256: $clean_digest"* ]]
    [[ "$output" == *"actual selected-tree SHA-256:"* ]]
    [[ "$output" == *"selected installed-tree inventory"* ]]
    [[ "$output" == *'F "detect-libc/package 2.json"'* ]]
    [[ "$output" == *'F "detect-libc/forged\nERROR: injected"'* ]]
    [[ "$output" != *$'detect-libc/forged\nERROR: injected'* ]]
}

@test "Codex and Copilot certifiers preflight installed trees before copy and retain snapshot checks" {
    run python3 - \
        "$NATIVE_DIR/certify-codex.sh" \
        "$NATIVE_DIR/certify-copilot.sh" <<'PY'
import pathlib
import sys

codex = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
copilot = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

codex_preflight = codex.index('--installed-label "Codex wrapper-plus-platform"')
codex_copy = codex.index('cp -R "$combined_package_root"')
codex_post_copy = codex.index(
    'host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_package_root")"'
)
assert codex_preflight < codex_copy < codex_post_copy
assert '--expected "$expected_tree_sha"' in codex[:codex_copy]
assert 'private Codex wrapper-plus-platform snapshot digest does not match host manifest' in codex[codex_copy:]

copilot_preflight = copilot.index(
    '--installed-label "Copilot wrapper-dependency-platform"'
)
copilot_copy = copilot.index(
    'cp -R "$host_package" "$workdir/host-runtime/node_modules/@github/"'
)
copilot_post_copy = copilot.index(
    'host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_runtime_root")"'
)
assert copilot_preflight < copilot_copy < copilot_post_copy
assert '--expected "$expected_tree_sha"' in copilot[:copilot_copy]
assert '"@github/copilot" "$platform_package_name" "$dependency_name"' in copilot[:copilot_copy]
assert 'private Copilot wrapper-dependency-platform snapshot digest does not match host manifest' in copilot[copilot_copy:]

print("native selected-tree preflight and post-copy checks valid")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "native selected-tree preflight and post-copy checks valid" ]]
}

@test "runtime Node package-tree identity matches the Python certifier" {
    command -v node >/dev/null 2>&1 || skip "Node.js unavailable"
    local package_tree="$TEST_DIR/runtime-package"
    mkdir -p "$package_tree/@openai/codex/bin" \
        "$package_tree/@openai/codex-platform/vendor" \
        "$package_tree/ignored"
    printf '%s\n' 'wrapper' > "$package_tree/@openai/codex/bin/codex.js"
    printf '%s\n' 'native bytes' > "$package_tree/@openai/codex-platform/vendor/codex"
    printf '%s\n' 'not selected' > "$package_tree/ignored/data.txt"

    run python3 "$NATIVE_DIR/hash-package-tree.py" "$package_tree/@openai" \
        codex codex-platform
    [[ "$status" -eq 0 ]]
    local certifier_digest="$output"

    run node "$NATIVE_DIR/hash-package-tree.mjs" "$package_tree/@openai" \
        codex-platform codex codex/bin
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$certifier_digest" ]]

    ln -s codex.js "$package_tree/@openai/codex/bin/linked.js"
    run node "$NATIVE_DIR/hash-package-tree.mjs" "$package_tree/@openai" \
        codex codex-platform
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"contains a symbolic link"* ]]
}

@test "package-tree identity rejects a short read with a clear error" {
    local package_tree="$TEST_DIR/short-read-package"
    mkdir -p "$package_tree"
    printf '%s' 'payload' > "$package_tree/payload.bin"

    run python3 - "$NATIVE_DIR/hash-package-tree.py" "$package_tree" <<'PY'
import importlib.util
import pathlib
import sys
import types

sys.dont_write_bytecode = True
module_path = pathlib.Path(sys.argv[1])
package_tree = pathlib.Path(sys.argv[2]).resolve()
payload = package_tree / "payload.bin"
spec = importlib.util.spec_from_file_location("mainframe_hash_package_tree", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

real_stat = pathlib.Path.stat


def report_larger_size(self, *args, **kwargs):
    result = real_stat(self, *args, **kwargs)
    if self == payload:
        return types.SimpleNamespace(
            st_mode=result.st_mode,
            st_size=result.st_size + 1,
        )
    return result


pathlib.Path.stat = report_larger_size
sys.argv = [str(module_path), str(package_tree)]
module.main()
PY
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"dataless, truncated, or changed while hashing: payload.bin"* ]]
    [[ "$output" == *"stat size 8, bytes read 7"* ]]
}

@test "streaming archive extractor rejects an oversized member before its data" {
    local archive="$TEST_DIR/oversized.tar.gz"
    local destination="$TEST_DIR/extracted"
    mkdir -p "$destination"
    python3 - "$archive" <<'PY'
import sys
import gzip
import tarfile

member = tarfile.TarInfo("oversized.bin")
member.mode = 0o644
member.size = (512 * 1024 * 1024) + 1
with gzip.open(sys.argv[1], "wb") as handle:
    handle.write(member.tobuf(format=tarfile.USTAR_FORMAT))
PY

    run python3 "$NATIVE_DIR/safe-extract.py" "$archive" "$destination"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expands beyond the size limit"* ]]
    [[ ! -e "$destination/oversized.bin" ]]

    run rg -n 'getmembers|extractall' "$NATIVE_DIR/safe-extract.py"
    [[ "$status" -ne 0 ]]
}

@test "release payload includes the certifier but excludes installed npm dependencies" {
    run "$BASH_BIN" -c '
      source "$1"
      mainframe_release_payload_files "$2"
    ' _ "$PROJECT_ROOT/scripts/dev/release-payload.sh" "$PROJECT_ROOT"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"scripts/dev/certify-native-host.sh"* ]]
    [[ "$output" == *"scripts/dev/native-host/assert-runner-platform.sh"* ]]
    [[ "$output" == *"scripts/dev/native-host/certify-codex.sh"* ]]
    [[ "$output" == *"scripts/dev/native-host/codex-evidence.schema.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/codex-responses-server.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/certify-copilot.sh"* ]]
    [[ "$output" == *"scripts/dev/native-host/copilot-evidence.schema.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/copilot-chat-completions-server.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/certify-claude.sh"* ]]
    [[ "$output" == *"scripts/dev/native-host/claude-evidence.schema.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/claude-messages-server.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/package-lock.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/hosts.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/hash-package-tree.mjs"* ]]
    [[ "$output" == *"scripts/dev/native-host/hash-package-tree.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/acquire-managed-package.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/extract-managed-package.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/managed-host-fs.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/safe-extract.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/validate-evidence.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/validate-native-executable.py"* ]]
    [[ "$output" == *"scripts/dev/native-host/fixtures/gemini-destroy.responses.jsonl"* ]]
    [[ "$output" == *"scripts/dev/native-host/fixtures/codex-destroy.responses.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/fixtures/copilot-destroy.chat-completions.json"* ]]
    [[ "$output" == *"scripts/dev/native-host/fixtures/claude-destroy.messages.json"* ]]
    [[ "$output" != *"node_modules"* ]]
}

@test "release workflow requires and byte-binds all native hosts on every advertised tuple" {
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local host lane codex_lane awm_lane

    run rg -n '^  native-host-codex:$' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n '^  native-host-copilot:$' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n '^  native-host-claude:$' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'needs: .*native-host-gemini, native-host-codex, native-host-copilot, native-host-claude' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'pattern: native-host-codex-\*' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'pattern: native-host-copilot-\*' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'pattern: native-host-claude-\*' "$workflow"
    [[ "$status" -eq 0 ]]
    for host in gemini codex copilot claude; do
        lane="$(sed -n "/^  native-host-${host}:/,/^  native-host-/p" "$workflow")"
        [[ "$lane" == *'runs-on: ${{ matrix.target.runner }}'* ]]
        [[ "$lane" == *'runner: macos-15'* ]]
        [[ "$lane" == *'id: Darwin-arm64-none'* ]]
        [[ "$lane" == *'runner: macos-15-intel'* ]]
        [[ "$lane" == *'id: Darwin-x86_64-none'* ]]
        [[ "$lane" == *'runner: ubuntu-24.04'* ]]
        [[ "$lane" == *'id: Linux-x86_64-glibc'* ]]
        [[ "$lane" == *'EXPECTED_SYSTEM_LIBC: ${{ matrix.target.system_libc }}'* ]]
        [[ "$lane" == *'scripts/dev/native-host/assert-runner-platform.sh'* ]]
        [[ "$lane" == *"name: native-host-${host}-\${{ matrix.target.id }}"* ]]
    done
    codex_lane="$(sed -n '/^  native-host-codex:/,/^  native-host-copilot:/p' "$workflow")"
    awm_lane="$(sed -n '/^  native-host-awm-chain:/,/^  homebrew-package:/p' "$workflow")"
    for lane in "$codex_lane" "$awm_lane"; do
        [[ "$lane" == *'sudo apt-get install -y jq bubblewrap apparmor-profiles'* ]]
        [[ "$lane" == *'/usr/share/apparmor/extra-profiles/bwrap-userns-restrict'* ]]
        [[ "$lane" == *'sudo /usr/sbin/apparmor_parser -r -W "$profile"'* ]]
        [[ "$lane" == *"/usr/bin/bwrap --help | grep -Fq -- '--perms'"* ]]
        [[ "$lane" == *'/usr/bin/bwrap --unshare-user --unshare-net --ro-bind / / /bin/true'* ]]
    done
    run rg -n 'test "\$\{#all_native_evidence\[@\]\}" -eq 12' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'expected_platforms="Darwin-arm64-none,Darwin-x86_64-none,Linux-x86_64-glibc"' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'test "\$\{#awm_chain_evidence\[@\]\}" -eq 3' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'expected_certifier_input_count=.*\.files \| length' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n '\.certifier_input_bundle\.files \| length' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'merge-multiple: true' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'codex-evidence\.schema\.json' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'copilot-evidence\.schema\.json' "$workflow"
    [[ "$status" -eq 0 ]]
    run rg -n 'claude-evidence\.schema\.json' "$workflow"
    [[ "$status" -eq 0 ]]

    run python3 - "$PROJECT_ROOT/scripts/dev/native-host/build-release-evidence.py" <<'PY'
import importlib.util
from pathlib import Path
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("release_evidence_contract", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
assert module.EXPECTED_SAFETY_CERTIFICATES == 12
assert module.EXPECTED_AWM_CERTIFICATES == 3
assert module.EXPECTED_BUNDLE_FILE_COUNT == 16
print("12+3 certificates and 16 bundle members")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "12+3 certificates and 16 bundle members" ]]
}

@test "Copilot workflow lane installs certifies validates and uploads exact evidence" {
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local lane
    lane="$(awk '
      /^  native-host-copilot:$/ { capture = 1 }
      capture && /^  homebrew-package:$/ { exit }
      capture { print }
    ' "$workflow")"

    [[ "$lane" == *'runs-on: ${{ matrix.target.runner }}'* ]]
    [[ "$lane" == *'runner: macos-15'* ]]
    [[ "$lane" == *'runner: macos-15-intel'* ]]
    [[ "$lane" == *'runner: ubuntu-24.04'* ]]
    [[ "$lane" == *'id: Darwin-arm64-none'* ]]
    [[ "$lane" == *'id: Darwin-x86_64-none'* ]]
    [[ "$lane" == *'id: Linux-x86_64-glibc'* ]]
    [[ "$lane" == *"node-version: '22.23.2'"* ]]
    [[ "$lane" == *'npm ci'* ]]
    [[ "$lane" == *'--prefix scripts/dev/native-host'* ]]
    [[ "$lane" == *'scripts/dev/certify-native-host.sh copilot'* ]]
    [[ "$lane" == *'scripts/dev/native-host/copilot-evidence.schema.json'* ]]
    [[ "$lane" == *'.host == "copilot"'* ]]
    [[ "$lane" == *'.host_dependency_package == $host.dependency.package'* ]]
    [[ "$lane" == *'.host_package_tree_sha256 == $platform.runtime_tree_sha256'* ]]
    [[ "$lane" == *'.fixture_sha256 == $fixture_sha'* ]]
    [[ "$lane" == *'.credential_mode == "copilot-offline-loopback-chat-completions-no-user-credentials"'* ]]
    [[ "$lane" == *'.project_trust_mode == "isolated-copilot-home-exact-project"'* ]]
    [[ "$lane" == *'.provider_user_credentials_supplied == false'* ]]
    [[ "$lane" == *'.system_libc == env.EXPECTED_SYSTEM_LIBC'* ]]
    [[ "$lane" == *'.libc == .system_libc'* ]]
    [[ "$lane" == *'.control_executions == 1'* ]]
    [[ "$lane" == *'.protected_executions == 0'* ]]
    [[ "$lane" == *'.protected_denial == "Denied by preToolUse hook: hook exited with code 2"'* ]]
    [[ "$lane" == *'name: native-host-copilot-${{ matrix.target.id }}'* ]]
}

@test "Claude workflow lane installs certifies validates and uploads direct-native evidence" {
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local lane
    lane="$(awk '
      /^  native-host-claude:$/ { capture = 1 }
      capture && /^  homebrew-package:$/ { exit }
      capture { print }
    ' "$workflow")"

    [[ "$lane" == *'runs-on: ${{ matrix.target.runner }}'* ]]
    [[ "$lane" == *'runner: macos-15'* ]]
    [[ "$lane" == *'runner: macos-15-intel'* ]]
    [[ "$lane" == *'runner: ubuntu-24.04'* ]]
    [[ "$lane" == *'id: Darwin-arm64-none'* ]]
    [[ "$lane" == *'id: Darwin-x86_64-none'* ]]
    [[ "$lane" == *'id: Linux-x86_64-glibc'* ]]
    [[ "$lane" == *"node-version: '22.23.2'"* ]]
    [[ "$lane" == *'npm ci'* ]]
    [[ "$lane" == *'--prefix scripts/dev/native-host'* ]]
    [[ "$lane" == *'--ignore-scripts'* ]]
    [[ "$lane" == *'scripts/dev/certify-native-host.sh claude'* ]]
    [[ "$lane" == *'scripts/dev/native-host/claude-evidence.schema.json'* ]]
    [[ "$lane" == *'.host == "claude"'* ]]
    [[ "$lane" == *'.host_channel == $host.channel'* ]]
    [[ "$lane" == *'.host_package_root_tree_sha256 == $host.package_tree_sha256'* ]]
    [[ "$lane" == *'.host_stub_sha256 == $host.stub_sha256'* ]]
    [[ "$lane" == *'.host_cli_wrapper_sha256 == $host.cli_wrapper_sha256'* ]]
    [[ "$lane" == *'.host_installer_sha256 == $host.installer_sha256'* ]]
    [[ "$lane" == *'.host_release_manifest_sha256 == $host.signed_release_manifest.sha256'* ]]
    [[ "$lane" == *'.host_release_manifest_signature_sha256 == $host.signed_release_manifest.signature_sha256'* ]]
    [[ "$lane" == *'.host_release_signing_key_fingerprint == $host.signed_release_manifest.signing_key_fingerprint'* ]]
    [[ "$lane" == *'.host_release_commit == $host.signed_release_manifest.commit'* ]]
    [[ "$lane" == *'.host_package_tree_sha256 == $platform.runtime_tree_sha256'* ]]
    [[ "$lane" == *'.host_executable_sha256 == $platform.executable_sha256'* ]]
    [[ "$lane" == *'.runtime_launch_mode == "npm-ignore-scripts-direct-platform-binary"'* ]]
    [[ "$lane" == *'.host_cli_wrapper_executed == false'* ]]
    [[ "$lane" == *'.fixture_sha256 == $fixture_sha'* ]]
    [[ "$lane" == *'.fixture_server_sha256 == $server_sha'* ]]
    [[ "$lane" == *'.credential_mode == "claude-loopback-messages-synthetic-bearer-no-user-credentials"'* ]]
    [[ "$lane" == *'.provider_wire_api == "anthropic-messages"'* ]]
    [[ "$lane" == *'.provider_placeholder_authorization == true'* ]]
    [[ "$lane" == *'.provider_user_credentials_supplied == false'* ]]
    [[ "$lane" == *'.system_libc == env.EXPECTED_SYSTEM_LIBC'* ]]
    [[ "$lane" == *'.libc == .system_libc'* ]]
    [[ "$lane" == *'.network_boundary == "loopback-base-url-and-nonessential-traffic-disabled"'* ]]
    [[ "$lane" == *'.project_trust_mode == "claude-print-mode-trust-verification-disabled"'* ]]
    [[ "$lane" == *'.settings_sources == "project-only"'* ]]
    [[ "$lane" == *'.managed_settings_present == false'* ]]
    [[ "$lane" == *'.permission_mode == "dontAsk"'* ]]
    [[ "$lane" == *'.tool_surface == "Bash-only-exact-command-allow"'* ]]
    [[ "$lane" == *'.control_executions == 1'* ]]
    [[ "$lane" == *'.protected_executions == 0'* ]]
    [[ "$lane" == *'.protected_hook_started == 1'* ]]
    [[ "$lane" == *'.protected_hook_responses == 1'* ]]
    [[ "$lane" == *'.protected_hook_exit_code == 2'* ]]
    [[ "$lane" == *'name: native-host-claude-${{ matrix.target.id }}'* ]]
}

@test "native certifier exposes a no-credential workflow and rejects uncertified hosts" {
    run "$BASH_BIN" "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"never uses a real model credential"* ]]
    [[ "$output" == *"paired"* ]]
    [[ "$output" == *"gemini, codex, copilot, claude"* ]]
    [[ "$output" != *"--gemini-bin"* ]]

    run env BASH="$BASH_BIN" "$BASH_BIN" \
      "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" copilot --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"supplies no model credential"* ]]
    [[ "$output" == *"loopback-only Chat Completions"* ]]
    [[ "$output" == *"trusts exactly its disposable project"* ]]
    [[ "$output" == *"paired control executes the sentinel once"* ]]

    run env BASH="$BASH_BIN" "$BASH_BIN" \
      "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" claude --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"exact pinned native platform binary directly"* ]]
    [[ "$output" == *"fixed synthetic bearer"* ]]
    [[ "$output" == *"no user, Anthropic, OAuth, or real gateway credential"* ]]
    [[ "$output" == *"project PreToolUse/Bash hook"* ]]

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" cursor
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"implemented native hosts are: gemini, codex, copilot, claude"* ]]
}

@test "native certifiers allow fail-closed checks inside the sealed hook" {
    local driver
    for driver in \
      "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" \
      "$NATIVE_DIR/certify-codex.sh" \
      "$NATIVE_DIR/certify-claude.sh"; do
        run rg -n 'expected_hook_command.*!=.*\|\| exit 2' "$driver"
        [[ "$status" -ne 0 ]]
    done
}

@test "native certifiers admit and recheck every privileged executable identity" {
    local driver required
    for driver in \
      "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" \
      "$NATIVE_DIR/certify-codex.sh" \
      "$NATIVE_DIR/certify-copilot.sh" \
      "$NATIVE_DIR/certify-claude.sh" \
      "$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"; do
        for required in \
          'assert-runner-platform.sh' \
          '--observe-native' \
          'validate-native-executable.py' \
          'bash_binding="$(native_executable_binding' \
          'node_binding="$(native_executable_binding' \
          "process.arch" \
          'private native executable validator snapshot changed during admission' \
          'privileged gateway Bash executable' \
          'privileged gateway jq executable'; do
            run rg -n --fixed-strings -- "$required" "$driver"
            [[ "$status" -eq 0 ]]
        done
    done

    for driver in \
      "$NATIVE_DIR/certify-codex.sh" \
      "$NATIVE_DIR/certify-copilot.sh" \
      "$NATIVE_DIR/certify-claude.sh"; do
        run rg -n --fixed-strings -- \
          'require_native_executable_binding "$certified_binary" "$host_binary_binding"' \
          "$driver"
        [[ "$status" -eq 0 ]]
    done

    local awm_certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"
    for required in \
      'require_native_executable_binding "$codex_binary" "$codex_binary_binding"' \
      'require_native_executable_binding "$copilot_binary" "$copilot_binary_binding"' \
      'require_native_executable_binding "$claude_binary" "$claude_binary_binding"'; do
        run grep -Fc -- "$required" "$awm_certifier"
        [[ "$status" -eq 0 ]]
        [[ "$output" -eq 2 ]]
    done
}

@test "every direct native certifier refuses translated execution before optional dependencies" {
    local fixture_root="$TEST_DIR/direct-native-admission"
    local fixture_native="$fixture_root/scripts/dev/native-host"
    local minimal_bin="$fixture_root/minimal-bin"
    local missing_archive="$fixture_root/missing.tar.gz"
    local host evidence tool target
    mkdir -p "$fixture_native" "$minimal_bin" "$fixture_root/dist"
    cp "$PROJECT_ROOT/VERSION" "$fixture_root/VERSION"
    cp "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" \
        "$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh" \
        "$fixture_root/scripts/dev/"
    cp "$NATIVE_DIR/certify-codex.sh" \
        "$NATIVE_DIR/certify-copilot.sh" \
        "$NATIVE_DIR/certify-claude.sh" \
        "$NATIVE_DIR/validate-native-executable.py" \
        "$fixture_native/"
    cat > "$fixture_native/assert-runner-platform.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$#" -eq 1 && "$1" == --observe-native ]] || exit 64
printf 'Release runner is translated under Rosetta; native evidence is required\n' >&2
exit 73
EOF
    chmod 700 "$fixture_native/assert-runner-platform.sh"

    ln -s "$BASH_BIN" "$minimal_bin/bash"
    for tool in dirname tr; do
        target="$(command -v "$tool")"
        [[ "$target" == /* ]]
        ln -s "$target" "$minimal_bin/$tool"
    done

    for host in gemini codex copilot claude; do
        evidence="$fixture_root/dist/$host.json"
        run env \
            PATH="$minimal_bin" \
            BASH="$BASH_BIN" \
            MAINFRAME_BASH="$BASH_BIN" \
            "$BASH_BIN" "$fixture_root/scripts/dev/certify-native-host.sh" \
            "$host" --archive "$missing_archive" --output "$evidence"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"translated under Rosetta"* ]]
        [[ "$output" != *"jq is required"* ]]
        [[ ! -e "$evidence" && ! -L "$evidence" ]]
    done

    evidence="$fixture_root/dist/awm-chain.json"
    run env \
        PATH="$minimal_bin" \
        BASH="$BASH_BIN" \
        MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$fixture_root/scripts/dev/certify-native-awm-chain.sh" \
        --archive "$missing_archive" --output "$evidence"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"translated under Rosetta"* ]]
    [[ "$output" != *"jq is required"* ]]
    [[ ! -e "$evidence" && ! -L "$evidence" ]]
}

@test "combined AWM certifier permits fail-closed checks inside the sealed hook" {
    local certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"

    run rg -n --fixed-strings -- \
      '"$generated_hook_command" != *"|| exit 2"*' "$certifier"
    [[ "$status" -ne 0 ]]

    run rg -n --fixed-strings -- \
      '"$generated_hook_command" != *"mainframe agent-hook"*' "$certifier"
    [[ "$status" -eq 0 ]]
}

@test "combined AWM certifier captures Gemini host failure before evidence checks" {
    local certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"

    run python3 - "$certifier" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(
    r'^run_gemini\(\) \{\n(?P<body>.*?)^\}',
    text,
    re.MULTILINE | re.DOTALL,
)
assert match is not None
body = match.group('body')
capture = ') >"$log" 2>&1; then status=0; else status=$?; fi'
failure = 'if [[ "$status" -ne 0 ]]; then'
diagnostic = "die \"Gemini native AWM-chain host exited with status $status\""
evidence = "if ! sed -n '/^{/p' \"$log\" | jq -s -e '"
assert 'local log="$workdir/hosts/gemini/host.log" status' in body
assert capture in body
assert failure in body
assert diagnostic in body
assert body.index(capture) < body.index(failure) < body.index(evidence)
print('Gemini AWM host failure status is captured before evidence checks')
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == \
      "Gemini AWM host failure status is captured before evidence checks" ]]
}

@test "combined AWM Gemini version probe binds system administration tools and reports failure" {
    local certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"

    run python3 - "$certifier" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('version_system_path="/usr/bin:/bin:/usr/sbin:/sbin"')
end = text.index('codex_verified_version="$(env -i', start)
probe = text[start:end]
for expected in (
    'version_node_path="$(dirname "$node_bin"):$version_system_path"',
    'PATH="$version_node_path" CI=1 NO_COLOR=1',
    '"$node_bin" "$gemini_entry" --version',
    '>"$gemini_version_stdout" 2>"$gemini_version_stderr"; then',
    'Gemini CLI version probe failed with status $version_status',
    'gemini_verified_version="$(awk',
):
    assert expected in probe, expected
assert '"$gemini_entry" --version 2>/dev/null |' not in probe
print('Gemini AWM version probe binds sysctl path and captures raw status')
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == \
      "Gemini AWM version probe binds sysctl path and captures raw status" ]]
}

@test "combined native AWM certifier is single-install private and fail-closed by construction" {
    local certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"

    run "$BASH_BIN" -n "$certifier"
    [[ "$status" -eq 0 ]]

    run "$BASH_BIN" "$certifier" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--archive PATH"* ]]
    [[ "$output" == *"--negative-wrong-predecessor"* ]]
    [[ "$output" == *"skip later hosts and emit no evidence"* ]]

    local required
    for required in \
      'protected_agent_bash="$MAINFRAME_AGENT_BASH"' \
      'protected_agent_jq="$MAINFRAME_AGENT_JQ"' \
      'protected_agent_gateway="$MAINFRAME_AGENT_GATEWAY"' \
      'protected_agent_safety="$MAINFRAME_AGENT_SAFETY"' \
      'protected_agent_seal="$MAINFRAME_AGENT_SEAL"' \
      '[[ "$protected_agent_safety" == "$workdir/extracted/lib/agent_safety.sh" &&' \
      '[[ "$protected_agent_seal" =~ ^([0-9a-f]{64}:){3}[0-9a-f]{64}$ ]]' \
      'MAINFRAME_AGENT_BASH="$protected_agent_bash"' \
      'MAINFRAME_AGENT_JQ="$protected_agent_jq"' \
      'MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"' \
      'MAINFRAME_AGENT_SAFETY="$protected_agent_safety"' \
      'MAINFRAME_AGENT_SEAL="$protected_agent_seal"'; do
        run rg -n --fixed-strings -- "$required" "$certifier"
        [[ "$status" -eq 0 ]]
    done

    for required in \
      'doctor_path="$(dirname "$bash_bin"):$(dirname "$node_bin"):/usr/bin:/bin:/usr/sbin:/sbin"' \
      'doctor_selected="$(PATH="$doctor_path" type -P mainframe 2>/dev/null || true)"' \
      'doctor PATH unexpectedly exposes a different MAINFRAME CLI' \
      'PATH="$doctor_path" "$mainframe_bin" doctor'; do
        run rg -n --fixed-strings -- "$required" "$certifier"
        [[ "$status" -eq 0 ]]
    done

    run grep -c '"$workdir/extracted/install.sh"' "$certifier"
    [[ "$status" -eq 0 ]]
    [[ "$output" -eq 1 ]]
    run grep -F 'session_id="$("${awm_env[@]}" "$mainframe_bin" awm init' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'for host in gemini codex-negative codex copilot claude' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'run_codex chain.gemini codex success' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'run_codex chain.missing codex-negative missing-predecessor' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'MAINFRAME_AWM_MISSING_PREDECESSOR' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'negative path emitted evidence' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'chmod 0600 "$evidence_tmp"' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'ln "$evidence_tmp" "$output"' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'hidden seed escaped private AWM root' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'provider_requests_embedded: false' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'refusing to overwrite pre-existing evidence output' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'cmp -s "$handoff_file.tmp" "$persisted_handoff"' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'all(.[1:][]; .importance == "high"' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F '[[ "$awm_schema_version" == 2 ]]' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'fresh_separate_host_state: true' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'gateway_command_correlation_available: false' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'gemini: proof("gemini"; 1; $gv;' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'codex: proof("codex"; 2; $cv;' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'copilot: proof("copilot"; 3; $pv;' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'claude: proof("claude"; 4; $av;' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F '[[ "$gemini_verified_version" == "$gemini_version" ]]' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F '[[ "$codex_verified_version" == "$codex_version" ]]' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F '[[ "$copilot_verified_version" == "$copilot_version" ]]' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F '[[ "$claude_verified_version" == "$claude_version" ]]' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F 'MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON' "$certifier"
    [[ "$status" -eq 0 ]]
    run grep -F -- '--- Gemini AWM synthetic host log ---' "$certifier"
    [[ "$status" -eq 0 ]]
}

@test "direct native certifiers diagnose no-shell installs through an explicit doctor path" {
    local certifier required doctor_assignment
    for certifier in \
        "$PROJECT_ROOT/scripts/dev/certify-native-host.sh" \
        "$PROJECT_ROOT/scripts/dev/native-host/certify-codex.sh" \
        "$PROJECT_ROOT/scripts/dev/native-host/certify-copilot.sh" \
        "$PROJECT_ROOT/scripts/dev/native-host/certify-claude.sh"; do
        run "$BASH_BIN" -n "$certifier"
        [[ "$status" -eq 0 ]]
        for required in \
            'doctor_path="$(dirname "$bash_bin"):$(dirname "$node_bin"):/usr/bin:/bin:/usr/sbin:/sbin"' \
            'doctor_selected="$(PATH="$doctor_path" type -P mainframe 2>/dev/null || true)"' \
            'doctor PATH unexpectedly exposes a different MAINFRAME CLI' \
            'PATH="$doctor_path" "$mainframe_bin" doctor' \
            'cat "$workdir/mainframe-doctor.log" >&2'; do
            run rg -n --fixed-strings -- "$required" "$certifier"
            [[ "$status" -eq 0 ]]
        done
        doctor_assignment="$(rg -N --fixed-strings \
            'doctor_path="$(dirname "$bash_bin")' "$certifier")"
        [[ "$doctor_assignment" != *install-bin* ]]
        [[ "$doctor_assignment" != *fake-bin* ]]
        [[ "$doctor_assignment" != *ORIGINAL_PATH* ]]
        run rg -n --fixed-strings -- '--no-shell' "$certifier"
        [[ "$status" -eq 0 ]]
    done
}

@test "native AWM evidence schema fixes coupled platform host and failed-predecessor facts" {
    local schema="$NATIVE_DIR/awm-chain-evidence.schema.json"

    run jq -e '
      .type == "object" and
      .additionalProperties == false and
      .properties.certification.const ==
        "native-awm-chain-execution-certified" and
      .properties.mainframe.properties.installation_count.const == 1 and
      .properties.mainframe.properties.installed_runtime_read_only.const == true and
      .properties.awm.properties.root_scope.const == "private-project-local" and
      .properties.awm.properties.schema_version.const == 2 and
      .properties.awm.properties.root_mode.const == "700" and
      .properties.awm.properties.private_artifact_mode.const == "600" and
      .properties.awm.properties.checkpoint_count.const == 5 and
      .properties.awm.properties.context_proof."$ref" == "#/$defs/contextProof" and
      .properties.awm.properties.handoff_proof."$ref" == "#/$defs/handoffProof" and
      .properties.execution_boundaries.properties.shared_project.const == true and
      .properties.execution_boundaries.properties.shared_awm_root.const == true and
      .properties.execution_boundaries.properties.same_uid.const == true and
      .properties.execution_boundaries.properties.shared_tmpdir.const == true and
      .properties.execution_boundaries.properties.os_process_isolation.const == false and
      .properties.hosts.properties.gemini.allOf[1].properties.position.const == 1 and
      .properties.hosts.properties.codex.allOf[1].properties.position.const == 2 and
      .properties.hosts.properties.copilot.allOf[1].properties.position.const == 3 and
      .properties.hosts.properties.claude.allOf[1].properties.position.const == 4 and
      .properties.hosts.properties.gemini.allOf[1].properties.checkpoint_source_agent.const == "gemini" and
      .properties.hosts.properties.codex.allOf[1].properties.checkpoint_source_agent.const == "codex" and
      .properties.hosts.properties.copilot.allOf[1].properties.checkpoint_source_agent.const == "copilot" and
      .properties.hosts.properties.claude.allOf[1].properties.checkpoint_source_agent.const == "claude" and
      ."$defs".hostProof.properties.gateway_records.const == 1 and
      ."$defs".hostProof.properties.gateway_risk.const == "low" and
      ."$defs".hostProof.properties.gateway_decision.const == "allow" and
      ."$defs".hostProof.properties.gateway_command_correlation_available.const == false and
      (."$defs".hostProof.required | index("fresh_separate_host_state") != null) and
      (."$defs".hostProof.required | index("isolated_native_session") == null) and
      .properties.platform.allOf[0].anyOf[0].properties.os.const == "Darwin" and
      .properties.platform.allOf[0].anyOf[0].properties.libc.const == "none" and
      .properties.platform.allOf[0].anyOf[0].properties.system_libc.const == "none" and
      .properties.platform.allOf[0].anyOf[1].properties.os.const == "Linux" and
      .properties.platform.allOf[0].anyOf[1].properties.libc.const == "glibc" and
      .properties.platform.allOf[0].anyOf[1].properties.system_libc.const == "glibc" and
      .properties.platform.allOf[0].anyOf[2].properties.os.const == "Linux" and
      .properties.platform.allOf[0].anyOf[2].properties.libc.const == "musl" and
      .properties.platform.allOf[0].anyOf[2].properties.system_libc.const == "musl" and
      .properties.evidence_hygiene.properties.raw_seed_embedded.const == false and
      .properties.evidence_hygiene.properties.credentials_embedded.const == false and
      .properties.evidence_hygiene.properties.absolute_home_paths_embedded.const == false and
      .properties.evidence_hygiene.properties.provider_requests_embedded.const == false and
      .properties.evidence_hygiene.properties.loopback_requests_persisted.const == false and
      .properties.evidence_hygiene.properties.loopback_awm_root_observed.const == false and
      .properties.evidence_hygiene.properties.loopback_disposable_paths_may_be_observed.const == true and
      .properties.negative_probe.properties.positive_certificate_binding.const == true and
      .properties.negative_probe.properties.provider_requests.const == 2 and
      .properties.negative_probe.properties.provider_status.const ==
        "expected-missing-predecessor" and
      .properties.negative_probe.properties.tool_exit_code.const == 42 and
      .properties.negative_probe.properties.checkpoint_written.const == false and
      .properties.negative_probe.properties.later_hosts_started_before_rejection.const == false
    ' "$schema"
    [[ "$status" -eq 0 ]]

    printf '%s\n' '{"schema_version":1,"unexpected":true}' >"$TEST_DIR/invalid.json"
    run python3 "$NATIVE_DIR/validate-evidence.py" "$schema" "$TEST_DIR/invalid.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing required keys"* || "$output" == *"unexpected keys"* ]]

    run python3 - "$NATIVE_DIR" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

native = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "mainframe_evidence_validator", native / "validate-evidence.py"
)
validator = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(validator)
schema = json.loads((native / "awm-chain-evidence.schema.json").read_text())
bounded = [
    schema["$defs"]["contextProof"]["properties"]["actual_bytes"],
    schema["$defs"]["contextProof"]["properties"]["actual_tokens"],
    schema["$defs"]["handoffProof"]["properties"]["actual_bytes"],
    schema["$defs"]["handoffProof"]["properties"]["actual_tokens"],
    schema["$defs"]["handoffProof"]["properties"]["nested_context_actual_bytes"],
    schema["$defs"]["handoffProof"]["properties"]["nested_context_actual_tokens"],
]
for child in bounded:
    for invalid in (child["minimum"] - 1, child["maximum"] + 1):
        try:
            validator.validate(child, invalid, "$.bounded", schema)
        except ValueError:
            pass
        else:
            raise AssertionError((child, invalid))
for invalid_platform in (
    {"os": "Darwin", "arch": "arm64", "libc": "glibc", "system_libc": "glibc"},
    {"os": "Linux", "arch": "x86_64", "libc": "none", "system_libc": "none"},
    {"os": "Linux", "arch": "x86_64", "libc": "glibc", "system_libc": "musl"},
):
    try:
        validator.validate(
            schema["properties"]["platform"],
            invalid_platform,
            "$.platform",
            schema,
        )
    except ValueError:
        pass
    else:
        raise AssertionError(invalid_platform)
codex_binding = schema["properties"]["hosts"]["properties"]["codex"]["allOf"][1]
try:
    validator.validate(
        codex_binding,
        {"host": "codex", "checkpoint_source_agent": "gemini"},
        "$.hosts.codex",
        schema,
    )
except ValueError:
    pass
else:
    raise AssertionError("Codex accepted Gemini checkpoint attribution")
print("AWM evidence bounds and cross-field coupling enforced")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "AWM evidence bounds and cross-field coupling enforced" ]]
}

@test "native AWM certifier refuses and preserves every pre-existing evidence output" {
    local certifier="$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh"
    local evidence_path="$TEST_DIR/existing-evidence.json"
    printf '%s\n' '{"preserve":true}' >"$evidence_path"

    run "$BASH_BIN" "$certifier" --archive "$TEST_DIR/does-not-exist.tar.gz" \
        --output "$evidence_path" --negative-wrong-predecessor
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite pre-existing evidence output"* ]]
    run jq -e '. == {preserve: true}' "$evidence_path"
    [[ "$status" -eq 0 ]]
}

@test "native AWM workflow runs every advertised tuple and binds evidence to release bytes" {
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local lane release_lane

    lane=$(sed -n '/^  native-host-awm-chain:/,/^  homebrew-package:/p' "$workflow")
    [[ "$lane" == *'matrix:'* ]]
    [[ "$lane" == *'runs-on: ${{ matrix.target.runner }}'* ]]
    [[ "$lane" == *'runner: macos-15'* ]]
    [[ "$lane" == *'runner: macos-15-intel'* ]]
    [[ "$lane" == *'runner: ubuntu-24.04'* ]]
    [[ "$lane" == *'id: Darwin-arm64-none'* ]]
    [[ "$lane" == *'id: Darwin-x86_64-none'* ]]
    [[ "$lane" == *'id: Linux-x86_64-glibc'* ]]
    [[ "$lane" == *'scripts/dev/certify-native-awm-chain.sh'* ]]
    [[ "$lane" == *'scripts/dev/native-host/awm-chain-evidence.schema.json'* ]]
    [[ "$lane" == *'scripts/dev/native-host/assert-runner-platform.sh'* ]]
    [[ "$lane" == *'.platform.system_libc == env.EXPECTED_SYSTEM_LIBC'* ]]
    [[ "$lane" == *'.platform.libc == .platform.system_libc'* ]]
    [[ "$lane" == *'name: native-host-awm-chain-${{ matrix.target.id }}'* ]]
    [[ "$lane" == *'.negative_probe.positive_certificate_binding == true'* ]]
    [[ "$lane" == *'"expected-missing-predecessor"'* ]]
    [[ "$lane" == *'.execution_boundaries == {'* ]]
    [[ "$lane" == *'.hosts.gemini.version == $manifest.gemini.version'* ]]
    [[ "$lane" == *'.fresh_separate_host_state == true'* ]]
    [[ "$lane" == *'.provider_request_hygiene_checks == 2'* ]]
    [[ "$lane" == *'.persisted_byte_equal == true'* ]]

    release_lane=$(sed -n '/^  release-build:/,/^  release-publish:/p' "$workflow")
    [[ "$release_lane" == *'native-host-awm-chain'* ]]
    [[ "$release_lane" == *'pattern: native-host-awm-chain-*'* ]]
    [[ "$release_lane" == *".mainframe.archive_sha256 == \$archive_sha"* ]]
    [[ "$release_lane" == *'test "${#awm_chain_evidence[@]}" -eq 3'* ]]
    [[ "$release_lane" == *'expected_platforms="Darwin-arm64-none,Darwin-x86_64-none,Linux-x86_64-glibc"'* ]]
    [[ "$release_lane" == *'.certifier_input_bundle.files | length'* ]]
    [[ "$release_lane" == *'expected_certifier_input_count='* ]]
    [[ "$release_lane" == *'"$expected_certifier_input_count"'* ]]
    [[ "$release_lane" == *'scripts/dev/native-host/awm-chain-evidence.schema.json'* ]]
    [[ "$release_lane" == *'.hosts.claude.version == $manifest.claude.version'* ]]
    [[ "$release_lane" == *'.negative_probe.tool_exit_code == 42'* ]]
    [[ "$release_lane" == *'.loopback_awm_root_observed == false'* ]]
    [[ "$release_lane" == *'.loopback_disposable_paths_may_be_observed == true'* ]]
}

@test "wrong-predecessor native AWM integration emits no evidence when archive is supplied" {
    [[ -n "${MAINFRAME_NATIVE_AWM_ARCHIVE:-}" ]] ||
        skip "set MAINFRAME_NATIVE_AWM_ARCHIVE to run the archive-backed negative proof"
    local evidence_path="$TEST_DIR/should-not-exist.json"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/dev/certify-native-awm-chain.sh" \
        --archive "$MAINFRAME_NATIVE_AWM_ARCHIVE" \
        --output "$evidence_path" \
        --negative-wrong-predecessor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Wrong predecessor rejected at Codex"* ]]
    [[ ! -e "$evidence_path" ]]
}

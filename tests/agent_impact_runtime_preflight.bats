#!/usr/bin/env bats

setup() {
    local requested_project_root canonical_project_root
    if [[ -n "${MAINFRAME_TEST_PREFLIGHT_PROJECT_ROOT:-}" ]]; then
        requested_project_root="$MAINFRAME_TEST_PREFLIGHT_PROJECT_ROOT"
        [[ "$requested_project_root" == /* ]] || {
            echo "preflight fixture project root must be absolute" >&2
            return 1
        }
        [[ ! "$requested_project_root" =~ [[:cntrl:]] ]] || {
            echo "preflight fixture project root contains control characters" >&2
            return 1
        }
        [[ -d "$requested_project_root" && ! -L "$requested_project_root" ]] || {
            echo "preflight fixture project root is unavailable or symbolic" >&2
            return 1
        }
        canonical_project_root="$(cd -P -- "$requested_project_root" 2>/dev/null && pwd -P)" || {
            echo "preflight fixture project root cannot be resolved" >&2
            return 1
        }
        [[ "$requested_project_root" == "$canonical_project_root" ]] || {
            echo "preflight fixture project root must already be canonical" >&2
            return 1
        }
        [[ "$canonical_project_root" != "/" ]] || {
            echo "preflight fixture project root cannot be the filesystem root" >&2
            return 1
        }
        PROJECT_ROOT="$canonical_project_root"
    else
        PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    fi
    TOOL="$PROJECT_ROOT/scripts/dev/agent-impact-runtime-preflight.py"
    PROTOCOL_ROOT="$PROJECT_ROOT/evals/agent-impact"
    [[ -f "$TOOL" && ! -L "$TOOL" && -x "$TOOL" ]] || {
        echo "preflight executable is missing, symbolic, or not executable" >&2
        return 1
    }
    PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    command -v jq >/dev/null || skip "jq is required"

    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-runtime-preflight.XXXXXX")"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    chmod 700 "$TEST_DIR"
    ORIGINAL_PATH="$PATH"
    POISON_BIN="$TEST_DIR/poison-bin"
    INVOCATION_MARKER="$TEST_DIR/runtime-was-invoked"
    mkdir -p "$POISON_BIN"
    chmod 700 "$POISON_BIN"
    local command_name
    for command_name in node pi ollama curl wget git; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "%s invoked\n" "$0" >> "${MAINFRAME_PREFLIGHT_MARKER:?}"' \
            'exit 97' > "$POISON_BIN/$command_name"
        chmod 700 "$POISON_BIN/$command_name"
    done
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

mode_of() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

preflight() {
    PATH="$POISON_BIN:$ORIGINAL_PATH" \
    MAINFRAME_PREFLIGHT_MARKER="$INVOCATION_MARKER" \
    "$PYTHON_BIN" -I -S -B "$TOOL" "$@"
}

prepare_fixture() {
    local root="$1"
    fixture_tool create "$root"
    preflight prepare \
        --spec "$root/spec.json" \
        --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
}

verify_fixture() {
    local root="$1"
    preflight verify \
        --spec "$root/spec.json" \
        --arm-contract "$root/arm.json" \
        --receipt "$root/receipt.json"
}

bind_arm() {
    fixture_tool bind-arm "$1"
}

refresh_fixture() {
    fixture_tool refresh "$1"
}

refresh_runtime() {
    fixture_tool runtime "$1"
}

run_with_deadline() {
    local log="$TEST_DIR/deadline.$RANDOM.log" pid count=0 result
    ( "$@" ) >"$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" >/dev/null 2>&1 && [[ "$count" -lt 100 ]]; do
        sleep 0.05
        count=$((count + 1))
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
        cat "$log"
        return 124
    fi
    wait "$pid"
    result=$?
    cat "$log"
    return "$result"
}

# Build and coherently rebind a tiny, entirely local runtime.  The tree-digest
# implementation below is deliberately independent of the verifier so the
# happy path is also a contract vector, rather than a self-fulfilling fixture.
fixture_tool() {
    "$PYTHON_BIN" -I -S -B - "$@" "$PROJECT_ROOT" <<'PYEOF'
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import sys

ACTION, ROOT_ARG, PROJECT_ARG = sys.argv[1:4]
ROOT = Path(ROOT_ARG).resolve()
PROJECT = Path(PROJECT_ARG).resolve()
MF_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
PI_DOMAIN = b"MAINFRAME-PI-RUNTIME-TREE-SHA256-V1\0"
RUNTIME_DOMAIN = b"MAINFRAME-AGENT-IMPACT-RUNTIME-PROJECTION-V1\0"
MODEL_CLOSURE_DOMAIN = b"MAINFRAME-OLLAMA-MANIFEST-DEPENDENCY-CLOSURE-V1\0"
MANIFEST_MEDIA = "application/vnd.docker.distribution.manifest.v2+json"
CONFIG_MEDIA = "application/vnd.docker.container.image.v1+json"
MODEL_MEDIA = "application/vnd.ollama.image.model"
TEMPLATE_MEDIA = "application/vnd.ollama.image.template"


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=True, allow_nan=False) + "\n").encode("utf-8")


def write_json(path, value, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encoded(value))
    path.chmod(mode)


def write_bytes(path, raw, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    path.chmod(mode)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def binding(path):
    raw = Path(path).read_bytes()
    return {"path": str(Path(path)), "sha256": digest(raw), "size_bytes": len(raw)}


def entries(root):
    found = []
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        current_path = Path(current)
        for name in directories + files:
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                found.append((relative, "L", path, metadata))
            elif stat.S_ISDIR(metadata.st_mode):
                found.append((relative, "D", path, metadata))
            elif stat.S_ISREG(metadata.st_mode):
                found.append((relative, "F", path, metadata))
            else:
                raise RuntimeError("special fixture entry: " + relative)
    return sorted(found)


def mainframe_tree(root):
    h = hashlib.sha256(MF_DOMAIN)
    count = 0
    for relative, kind, path, metadata in entries(Path(root)):
        if kind == "L":
            raise RuntimeError("MAINFRAME fixture tree may not contain symlinks")
        raw_name = relative.encode("utf-8")
        if kind == "D":
            h.update(b"D\0" + raw_name + b"\0")
        else:
            raw = path.read_bytes()
            h.update(b"F\0" + raw_name + b"\0")
            h.update(str(len(raw)).encode("ascii") + b"\0")
            h.update(raw)
        count += 1
    return h.hexdigest(), count


def pi_tree(root):
    root = Path(root)
    h = hashlib.sha256(PI_DOMAIN)
    h.update(b"R\0" + format(stat.S_IMODE(root.stat().st_mode), "04o").encode("ascii") + b"\0")
    count = 0
    for relative, kind, path, metadata in entries(root):
        raw_name = relative.encode("utf-8")
        mode = format(stat.S_IMODE(metadata.st_mode), "04o").encode("ascii")
        if kind == "D":
            h.update(b"D\0" + raw_name + b"\0" + mode + b"\0")
        elif kind == "F":
            raw = path.read_bytes()
            h.update(b"F\0" + raw_name + b"\0" + mode + b"\0")
            h.update(str(len(raw)).encode("ascii") + b"\0")
            h.update(raw)
        else:
            target = os.readlink(path).encode("utf-8")
            h.update(b"L\0" + raw_name + b"\0" + mode + b"\0")
            h.update(str(len(target)).encode("ascii") + b"\0" + target)
        count += 1
    return h.hexdigest(), count


def host_identity():
    uname = os.uname()
    architecture = uname.machine.lower()
    if architecture in ("aarch64", "arm64", "arm64e"):
        architecture = "arm64"
    elif architecture in ("amd64", "x86_64"):
        architecture = "x86_64"
    else:
        raise RuntimeError("unsupported test architecture: " + architecture)
    operating_system = uname.sysname
    if operating_system == "Darwin":
        suffix = "none"
    else:
        try:
            libc = os.confstr("CS_GNU_LIBC_VERSION") or ""
        except (OSError, ValueError):
            libc = ""
        suffix = "glibc" if libc.startswith("glibc ") else "musl"
    return operating_system, architecture, f"{operating_system}-{architecture}-{suffix}"


def native_header(operating_system, architecture):
    if operating_system == "Darwin":
        cpu = 0x0100000C if architecture == "arm64" else 0x01000007
        return struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, 0, 2, 0, 0, 0, 0)
    machine = 183 if architecture == "arm64" else 62
    raw = bytearray(64)
    raw[:6] = b"\x7fELF\x02\x01"
    raw[16:20] = struct.pack("<HH", 2, machine)
    return bytes(raw)


def runtime_projection(spec):
    # arm_contract is deliberately outside this projection, avoiding a digest
    # cycle while binding every runtime identity used by either opaque arm.
    keys = ("schema_version", "kind", "claim_scope", "platform", "node",
            "mainframe", "pi", "ollama", "adapter", "protocol")
    return {key: spec[key] for key in keys}


def update_runtime(root, spec, arm):
    runtime_sha = digest(RUNTIME_DOMAIN + encoded(runtime_projection(spec)))
    arm["runtime_binding"] = {
        "algorithm": "canonical-runtime-projection-sha256-v1",
        "domain_separator_hex": RUNTIME_DOMAIN.hex(),
        "canonicalization": "utf8-json-sorted-keys-compact-ensure-ascii-lf-v1",
        "projection_keys": ["schema_version", "kind", "claim_scope", "platform", "node",
                            "mainframe", "pi", "ollama", "adapter", "protocol"],
        "arm_contract_excluded": True,
        "sha256": runtime_sha,
    }
    write_json(root / "arm.json", arm)
    spec["arm_contract"] = binding(root / "arm.json")
    write_json(root / "spec.json", spec)


def create(root):
    if root.exists():
        raise RuntimeError("fixture root exists")
    root.mkdir(parents=True, mode=0o700)
    operating_system, architecture, platform_tuple = host_identity()
    mf = root / "mainframe"
    pi = root / "pi-package"
    release = root / "release"
    model_root = root / "ollama-models"
    blobs = model_root / "blobs"

    archive = release / "mainframe-10.2.0.tar.gz"
    write_bytes(archive, b"synthetic MAINFRAME release archive\n")
    archive_sha = digest(archive.read_bytes())
    sidecar = Path(str(archive) + ".sha256")
    write_bytes(sidecar, (archive_sha + "  " + archive.name + "\n").encode("ascii"))

    write_bytes(mf / "VERSION", b"10.2.0\n")
    install_receipt = {
        "schema_version": 1,
        "install_method": "release-archive",
        "version": "10.2.0",
        "archive_sha256": archive_sha,
        "manifest_sha256": "a" * 64,
        "install_dir": str(mf),
        "bin_dir": str(root / "bin"),
        "cli_link": str(root / "bin" / "mainframe"),
        "installed_at": "2026-08-12T00:00:00Z",
    }
    write_json(mf / ".mainframe-install-receipt.json", install_receipt, 0o600)
    write_bytes(mf / "skills/pi/extensions/mainframe.ts", b"export default function mainframe() {}\n")
    write_bytes(mf / "lib/awm-transition.sh", b"#!/bin/sh\nexit 64\n", 0o755)
    for name in ("raw", "receipt", "neutral-continuation"):
        write_json(mf / f"schemas/awm-{name}.schema.json",
                   {"type": "object", "additionalProperties": False})

    compatibility = {
        "schema_version": 1,
        "integration": "@gtwatts/mainframe-pi",
        "mainframe_version": "10.2.0",
        "unknown_policy": {"support": "unverified", "ready": False},
        "runtime_verification_command": "/mainframe doctor",
        "required_surface": {
            "extension": "./skills/pi/extensions/mainframe.ts",
            "skill": "./skills/pi", "command": "mainframe",
            "hooks": ["before_agent_start", "tool_call", "user_bash"],
            "caller_shells": ["bash", "zsh"],
            "tools": ["mainframe_awm", "mainframe_bash_safety_check",
                      "mainframe_exec", "mainframe_help", "mainframe_install_commands",
                      "mainframe_search", "mainframe_status"],
        },
        "certifications": [{
            "id": "pi-0.84.1-test-full",
            "mainframe_version": "10.2.0",
            "package": "@earendil-works/pi-coding-agent",
            "version": "0.84.1",
            "npm_integrity": "sha512-ncAqFrG+iybuPGOhMiZoEHkEzTpJgz3guYD32pD+M7ucc0WeHmauP6wa7qwP8V/KWvsZDVNa5XGsdZ7fkC7w7A==",
            "platforms": [platform_tuple], "support": "certified", "profile": "full",
            "evidence_date": "2026-08-12", "evidence": ["synthetic-offline-fixture"],
            "capabilities": {
                "local_package_discovery": "verified", "prompt_hook": "verified",
                "seven_tool_surface": "verified", "agent_bash_gate": "verified",
                "tui_user_bash_gate": "verified", "rpc_user_bash_gate": "verified",
                "bash_and_zsh_callers": "verified",
            },
            "limitations": [],
        }],
    }
    write_json(mf / "config/pi-compatibility.json", compatibility)

    source_files = {
        "scripts/dev/agent-impact-runtime-preflight.py": PROJECT / "scripts/dev/agent-impact-runtime-preflight.py",
        "evals/agent-impact/pi-ollama-preflight-spec.schema.json": PROJECT / "evals/agent-impact/pi-ollama-preflight-spec.schema.json",
        "evals/agent-impact/pi-ollama-preflight-receipt.schema.json": PROJECT / "evals/agent-impact/pi-ollama-preflight-receipt.schema.json",
        "evals/agent-impact/pi-ollama-arm-contract.schema.json": PROJECT / "evals/agent-impact/pi-ollama-arm-contract.schema.json",
        "evals/agent-impact/pi-ollama-adapter-request.schema.json": PROJECT / "evals/agent-impact/pi-ollama-adapter-request.schema.json",
        "evals/agent-impact/pi-ollama-adapter-result.schema.json": PROJECT / "evals/agent-impact/pi-ollama-adapter-result.schema.json",
        "evals/agent-impact/runners/pi-ollama-adapter.manifest.json": PROJECT / "evals/agent-impact/runners/pi-ollama-adapter.manifest.json",
        "evals/agent-impact/runners/pi-ollama-adapter.py": PROJECT / "evals/agent-impact/runners/pi-ollama-adapter.py",
    }
    for relative, source in source_files.items():
        destination = mf / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        destination.chmod(0o755 if relative.endswith(".py") else 0o644)

    package_manifest = {
        "name": "@earendil-works/pi-coding-agent", "version": "0.84.1",
        "type": "module", "bin": {"pi": "dist/cli.js"},
    }
    write_json(pi / "package.json", package_manifest)
    write_bytes(pi / "dist/cli.js", b"#!/usr/bin/env node\nthrow new Error('fixture must not run');\n", 0o755)
    write_bytes(pi / "dist/core/extensions/loader.js", b"export const loadExtensions = () => [];\n")
    write_bytes(pi / "node_modules/helper/cli.js", b"throw new Error('fixture must not run');\n", 0o755)
    (pi / "node_modules/.bin").mkdir(parents=True)
    (pi / "node_modules/.bin/helper").symlink_to("../helper/cli.js")

    node = root / "node-install"
    ollama = root / "ollama-install"
    shell = root / "shell-install"
    write_bytes(shell / "bin/bash", native_header(operating_system, architecture), 0o755)
    write_bytes(node / "bin/node", native_header(operating_system, architecture), 0o755)
    write_json(node / "INSTALL_RECEIPT.json", {
        "source": {"versions": {"stable": "26.5.0"}}, "arch": architecture,
        "poured_from_bottle": True,
    })
    write_bytes(ollama / "bin/ollama", native_header(operating_system, architecture), 0o755)
    write_json(ollama / "INSTALL_RECEIPT.json", {
        "source": {"versions": {"stable": "0.32.3"}}, "arch": architecture,
        "poured_from_bottle": True,
    })

    model_raw = b"tiny deterministic model bytes\n"
    template_raw = b"{{ if .Tools }}{{ .Tools }}{{ end }} {{ .ToolCalls }}\n"
    license_raw = b"fixture license\n"
    params_raw = b'{"stop":["<|eot_id|>"]}\n'
    layer_values = [
        (MODEL_MEDIA, model_raw), (TEMPLATE_MEDIA, template_raw),
        ("application/vnd.ollama.image.license", license_raw),
        ("application/vnd.ollama.image.params", params_raw),
    ]
    layers = []
    for media_type, raw in layer_values:
        qualified = "sha256:" + digest(raw)
        write_bytes(blobs / qualified.replace(":", "-"), raw)
        layers.append({"mediaType": media_type, "digest": qualified, "size": len(raw)})
    config = {
        "model_format": "gguf", "model_family": "fixture",
        "model_families": ["fixture"], "model_type": "tiny", "file_type": "fixture",
        "architecture": "amd64", "os": "linux",
        "rootfs": {"type": "layers", "diff_ids": [item["digest"] for item in layers]},
    }
    config_raw = encoded(config)
    config_digest = "sha256:" + digest(config_raw)
    write_bytes(blobs / config_digest.replace(":", "-"), config_raw)
    manifest = {
        "schemaVersion": 2, "mediaType": MANIFEST_MEDIA,
        "config": {"mediaType": CONFIG_MEDIA, "digest": config_digest,
                   "size": len(config_raw)},
        "layers": layers,
    }
    manifest_path = model_root / "manifests/registry.ollama.ai/library/llama3.3/latest"
    write_json(manifest_path, manifest)

    # Mirror the release installer relationship: SHA256SUMS authenticates the
    # payload (excluding itself and the generated install receipt), and the
    # receipt commits the exact inventory bytes.
    inventory_lines = ["# synthetic MAINFRAME release checksums"]
    for relative, kind, path, _metadata in entries(mf):
        if kind != "F" or relative in ("SHA256SUMS", ".mainframe-install-receipt.json"):
            continue
        inventory_lines.append(f"{digest(path.read_bytes())}  {relative}")
    write_bytes(mf / "SHA256SUMS", ("\n".join(inventory_lines) + "\n").encode("ascii"))
    install_receipt["manifest_sha256"] = digest((mf / "SHA256SUMS").read_bytes())
    write_json(mf / ".mainframe-install-receipt.json", install_receipt, 0o600)

    mf_tree_sha, _ = mainframe_tree(mf)
    pi_tree_sha, _ = pi_tree(pi)
    config_descriptor = {
        "digest": manifest["config"]["digest"],
        "media_type": manifest["config"]["mediaType"],
        "size_bytes": manifest["config"]["size"],
    }
    layer_descriptors = [{
        "digest": item["digest"], "media_type": item["mediaType"],
        "size_bytes": item["size"],
    } for item in manifest["layers"]]
    rootfs_diff_ids = [item["digest"] for item in manifest["layers"]]
    closure_projection = {
        "config_descriptor": config_descriptor,
        "ordered_layer_descriptors": layer_descriptors,
        "ordered_rootfs_diff_ids": rootfs_diff_ids,
    }
    blob_descriptors = [manifest["config"]] + manifest["layers"]
    blob_bindings = []
    for descriptor in blob_descriptors:
        path = blobs / descriptor["digest"].replace(":", "-")
        blob_bindings.append({
            "role": "config" if not blob_bindings else "layer",
            "digest": descriptor["digest"], "media_type": descriptor["mediaType"],
            "path": str(path), "size_bytes": descriptor["size"],
        })

    spec = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-pi-ollama-preflight-spec",
        "claim_scope": "offline-pi-ollama-runtime-binding-and-neutral-arm-contract-preflight-only",
        "runtime_binding_algorithm": "canonical-runtime-projection-sha256-v1",
        "arm_contract": {"path": str(root / "arm.json"), "sha256": "0" * 64, "size_bytes": 1},
        "platform": {"operating_system": operating_system, "architecture": architecture,
                     "platform_tuple": platform_tuple,
                     "shell": {"name": "bash", "architecture": architecture,
                               "executable": binding(shell / "bin/bash")}},
        "node": {"version": "26.5.0", "architecture": architecture,
                 "executable": binding(node / "bin/node"),
                 "install_receipt": binding(node / "INSTALL_RECEIPT.json"),
                 "receipt_format": "homebrew-install-receipt-v1"},
        "mainframe": {
            "version": "10.2.0", "version_file": binding(mf / "VERSION"),
            "install_receipt": binding(mf / ".mainframe-install-receipt.json"),
            "install_receipt_format": "mainframe-release-archive-install-receipt-v1",
            "archive": binding(archive), "checksum_sidecar": binding(sidecar),
            "installed_tree": {"root": str(mf),
                               "algorithm": "mainframe-package-tree-sha256-v1",
                               "sha256": mf_tree_sha},
            "pi_extension": binding(mf / "skills/pi/extensions/mainframe.ts"),
            "pi_compatibility_manifest": binding(mf / "config/pi-compatibility.json"),
            "pi_compatibility_certification_id": "pi-0.84.1-test-full",
            "awm_protocol": {
                "transition_driver": binding(mf / "lib/awm-transition.sh"),
                "raw_schema": binding(mf / "schemas/awm-raw.schema.json"),
                "receipt_schema": binding(mf / "schemas/awm-receipt.schema.json"),
                "neutral_continuation_schema": binding(mf / "schemas/awm-neutral-continuation.schema.json"),
            },
        },
        "pi": {
            "package_name": "@earendil-works/pi-coding-agent", "package_version": "0.84.1",
            "architecture": architecture, "executable": binding(pi / "dist/cli.js"),
            "package_manifest": binding(pi / "package.json"),
            "package_tree": {"root": str(pi), "algorithm": "mainframe-pi-runtime-tree-sha256-v1",
                             "sha256": pi_tree_sha},
            "extension_loader": binding(pi / "dist/core/extensions/loader.js"),
        },
        "ollama": {
            "version": "0.32.3", "architecture": architecture,
            "executable": binding(ollama / "bin/ollama"),
            "install_receipt": binding(ollama / "INSTALL_RECEIPT.json"),
            "receipt_format": "homebrew-install-receipt-v1",
            "model": {
                "name": "llama3.3:latest", "closure": "manifest-referenced-blobs-only-not-entire-store",
                "manifest": binding(manifest_path), "manifest_media_type": MANIFEST_MEDIA,
                "config_descriptor": config_descriptor,
                "ordered_layer_descriptors": layer_descriptors,
                "ordered_rootfs_diff_ids": rootfs_diff_ids,
                "ordered_blobs": blob_bindings,
                "template_contract": {"digest": layers[1]["digest"],
                                      "media_type": TEMPLATE_MEDIA,
                                      "required_markers": [".Tools", ".ToolCalls"]},
                "tool_contract": {"mode": "native-tools-required",
                                  "native_tool_channel": "ollama-template-tools-and-toolcalls-markers"},
                "dependency_closure_algorithm": "canonical-ollama-manifest-dependency-closure-sha256-v1",
                "dependency_closure_domain_separator_hex": MODEL_CLOSURE_DOMAIN.hex(),
                "dependency_closure_canonicalization": "utf8-json-sorted-keys-compact-ensure-ascii-lf-v1",
                "dependency_closure_sha256": digest(MODEL_CLOSURE_DOMAIN + encoded(closure_projection)),
            },
        },
        "adapter": {
            "executable": binding(mf / "evals/agent-impact/runners/pi-ollama-adapter.py"),
            "manifest": binding(mf / "evals/agent-impact/runners/pi-ollama-adapter.manifest.json"),
            "request_schema": binding(mf / "evals/agent-impact/pi-ollama-adapter-request.schema.json"),
            "result_schema": binding(mf / "evals/agent-impact/pi-ollama-adapter-result.schema.json"),
            "arm_contract_schema": binding(mf / "evals/agent-impact/pi-ollama-arm-contract.schema.json"),
            "expected_adapter_id": "mainframe-pi-ollama-dormant-v1",
            "expected_adapter_version": "1.0.0",
        },
        "protocol": {
            "preflight_executable": binding(mf / "scripts/dev/agent-impact-runtime-preflight.py"),
            "spec_schema": binding(mf / "evals/agent-impact/pi-ollama-preflight-spec.schema.json"),
            "receipt_schema": binding(mf / "evals/agent-impact/pi-ollama-preflight-receipt.schema.json"),
        },
    }
    arm = {
        "schema_version": 1, "kind": "mainframe-agent-impact-pi-ollama-neutral-arm-contract",
        "runtime_binding": {}, "study_id": "control-plane-study",
        "pair_id": "pair-0011223344556677",
        "opaque_arm_ids": ["arm-0123456789abcdef", "arm-fedcba9876543210"],
        "task_id": "fixture-task", "phases": ["investigate", "implement"],
        "provider": {"name": "ollama", "model": "llama3.3:latest"},
        "budgets": {"wall_seconds_per_phase": 60, "maximum_tool_calls_per_phase": 10,
                    "maximum_context_bytes": 8192},
        "environment_contract": {"fresh_per_phase": True,
                                 "allowed_environment_names": ["HOME", "LANG", "PATH", "TMPDIR"]},
        "adapter_boundary": {
            "assignment_visibility": "opaque-arm-identities-only",
            "mechanism_transition_owner": "harness", "scoring_owner": "harness",
            "same_adapter_executable_both_arms": True,
            "same_provider_model_both_arms": True, "same_phase_budgets_both_arms": True,
            "request_parity_fields": ["budgets", "environment_contract", "phase", "provider", "task_id"],
            "forbidden_request_fields": ["arm_mode", "assignment", "control", "mechanism", "treatment"],
            "forbidden_request_string_values": ["control", "mainframe-awm-handoff",
                                                "native-bounded-handoff", "treatment"],
            "neutrality_validation": "recursive-exact-key-and-exact-string-value-rejection",
        },
    }
    update_runtime(root, spec, arm)


def load_pair(root):
    return (json.loads((root / "spec.json").read_text()),
            json.loads((root / "arm.json").read_text()))


def refresh(root):
    spec, arm = load_pair(root)
    for section, keys in (
        (spec["platform"]["shell"], ("executable",)),
        (spec["node"], ("executable", "install_receipt")),
        (spec["mainframe"], ("version_file", "install_receipt", "archive",
                             "checksum_sidecar", "pi_extension", "pi_compatibility_manifest")),
        (spec["mainframe"]["awm_protocol"], ("transition_driver", "raw_schema",
                                              "receipt_schema", "neutral_continuation_schema")),
        (spec["pi"], ("executable", "package_manifest", "extension_loader")),
        (spec["ollama"], ("executable", "install_receipt")),
        (spec["adapter"], ("executable", "manifest", "request_schema", "result_schema",
                           "arm_contract_schema")),
        (spec["protocol"], ("preflight_executable", "spec_schema", "receipt_schema")),
    ):
        for key in keys:
            section[key] = binding(section[key]["path"])
    spec["ollama"]["model"]["manifest"] = binding(
        spec["ollama"]["model"]["manifest"]["path"])
    for item in spec["ollama"]["model"]["ordered_blobs"]:
        raw = Path(item["path"]).read_bytes()
        item["size_bytes"] = len(raw)
    model = spec["ollama"]["model"]
    closure_projection = {
        "config_descriptor": model["config_descriptor"],
        "ordered_layer_descriptors": model["ordered_layer_descriptors"],
        "ordered_rootfs_diff_ids": model["ordered_rootfs_diff_ids"],
    }
    model["dependency_closure_sha256"] = digest(
        MODEL_CLOSURE_DOMAIN + encoded(closure_projection))
    spec["mainframe"]["installed_tree"]["sha256"] = mainframe_tree(
        spec["mainframe"]["installed_tree"]["root"])[0]
    spec["pi"]["package_tree"]["sha256"] = pi_tree(
        spec["pi"]["package_tree"]["root"])[0]
    update_runtime(root, spec, arm)


def strip_template_markers(root):
    """Keep the descriptor/config closure coherent while removing tool markers."""
    spec, arm = load_pair(root)
    model = spec["ollama"]["model"]
    manifest_path = Path(model["manifest"]["path"])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    blobs_root = Path(model["ordered_blobs"][0]["path"]).parent

    template_raw = b"template intentionally missing native tool markers\n"
    template_digest = "sha256:" + digest(template_raw)
    template_path = blobs_root / template_digest.replace(":", "-")
    write_bytes(template_path, template_raw)
    manifest["layers"][1] = {
        "mediaType": TEMPLATE_MEDIA, "digest": template_digest,
        "size": len(template_raw),
    }

    old_config_path = Path(model["ordered_blobs"][0]["path"])
    config = json.loads(old_config_path.read_text(encoding="utf-8"))
    config["rootfs"]["diff_ids"][1] = template_digest
    config_raw = encoded(config)
    config_digest = "sha256:" + digest(config_raw)
    config_path = blobs_root / config_digest.replace(":", "-")
    write_bytes(config_path, config_raw)
    manifest["config"] = {
        "mediaType": CONFIG_MEDIA, "digest": config_digest,
        "size": len(config_raw),
    }
    write_json(manifest_path, manifest)

    model["manifest"] = binding(manifest_path)
    model["config_descriptor"] = {
        "digest": config_digest, "media_type": CONFIG_MEDIA,
        "size_bytes": len(config_raw),
    }
    model["ordered_layer_descriptors"][1] = {
        "digest": template_digest, "media_type": TEMPLATE_MEDIA,
        "size_bytes": len(template_raw),
    }
    model["ordered_rootfs_diff_ids"][1] = template_digest
    model["ordered_blobs"][0] = {
        "role": "config", "digest": config_digest, "media_type": CONFIG_MEDIA,
        "path": str(config_path), "size_bytes": len(config_raw),
    }
    model["ordered_blobs"][2] = {
        "role": "layer", "digest": template_digest, "media_type": TEMPLATE_MEDIA,
        "path": str(template_path), "size_bytes": len(template_raw),
    }
    model["template_contract"]["digest"] = template_digest
    closure_projection = {
        "config_descriptor": model["config_descriptor"],
        "ordered_layer_descriptors": model["ordered_layer_descriptors"],
        "ordered_rootfs_diff_ids": model["ordered_rootfs_diff_ids"],
    }
    model["dependency_closure_sha256"] = digest(
        MODEL_CLOSURE_DOMAIN + encoded(closure_projection))
    update_runtime(root, spec, arm)


if ACTION == "create":
    create(ROOT)
elif ACTION == "bind-arm":
    spec, arm = load_pair(ROOT)
    write_json(ROOT / "arm.json", arm)
    spec["arm_contract"] = binding(ROOT / "arm.json")
    write_json(ROOT / "spec.json", spec)
elif ACTION == "runtime":
    spec, arm = load_pair(ROOT)
    update_runtime(ROOT, spec, arm)
elif ACTION == "refresh":
    refresh(ROOT)
elif ACTION == "strip-template-markers":
    strip_template_markers(ROOT)
elif ACTION == "snapshot":
    rows = []
    for path in sorted(ROOT.rglob("*")):
        metadata = path.lstat()
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink():
            identity = "L:" + os.readlink(path)
        elif path.is_file():
            identity = "F:" + digest(path.read_bytes())
        elif path.is_dir():
            identity = "D"
        else:
            identity = "S"
        rows.append([relative, format(stat.S_IMODE(metadata.st_mode), "04o"),
                     metadata.st_size, metadata.st_mtime_ns, identity])
    sys.stdout.buffer.write(encoded(rows))
else:
    raise RuntimeError("unknown fixture action: " + ACTION)
PYEOF
}

@test "CLI has exactly offline prepare and verify actions and requires isolated Python" {
    run "$PYTHON_BIN" -I -S -B "$TOOL" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"prepare"* ]]
    [[ "$output" == *"verify"* ]]
    [[ "$output" != *" run "* ]]
    [[ "$output" != *"probe"* ]]
    [[ "$output" != *"pull"* ]]
    [[ "$output" != *"start"* ]]

    local action
    for action in run probe pull start list; do
        run "$PYTHON_BIN" -I -S -B "$TOOL" "$action"
        [[ "$status" -eq 2 ]]
    done

    run "$PYTHON_BIN" "$TOOL" --help
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"isolated interpreter"* ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "happy prepare and verify bind the complete offline runtime without invoking it" {
    local root="$TEST_DIR/control-plane/happy"
    run prepare_fixture "$root"
    [[ "$status" -eq 0 ]]
    [[ -f "$root/receipt.json" ]]
    [[ "$(mode_of "$root/receipt.json")" == 600 ]]
    [[ ! -e "$INVOCATION_MARKER" ]]

    run verify_fixture "$root"
    [[ "$status" -eq 0 ]]
    [[ ! -e "$INVOCATION_MARKER" ]]

    run jq -e '
      .claim_scope == "offline-pi-ollama-runtime-binding-and-neutral-arm-contract-preflight-only" and
      .status == "offline-bindings-and-neutral-arm-contract-valid" and
      .execution.offline_only == true and
      .execution.actions_available == ["prepare", "verify"] and
      .execution.run_action_available == false and
      .execution.processes_started_by_preflight == 0 and
      .execution.child_processes_started_after_preflight_entry == 0 and
      .execution.existing_machine_processes == "not-inspected" and
      .execution.machine_process_state_observed == false and
      .execution.network_requests_by_preflight == 0 and
      .execution.pi_processes_started_by_preflight == 0 and
      .execution.ollama_processes_started_by_preflight == 0 and
      .execution.provider_requests_by_preflight == 0 and
      .execution.prepare_action_files_created == 1 and
      .execution.verify_action_files_created == 0 and
      .non_claims.provider_inference == false and
      .non_claims.agent_impact_measured == false and
      .non_claims.live_study_evidence_eligible == false
    ' "$root/receipt.json"
    [[ "$status" -eq 0 ]]
}

@test "prepare is deterministic no-clobber and verify performs no writes" {
    local root="$TEST_DIR/deterministic" before after receipt_sha receipt_mtime count
    prepare_fixture "$root"
    cp "$root/receipt.json" "$root/expected-receipt.json"
    receipt_sha="$(sha256_of "$root/receipt.json")"

    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"overwrite"* || "$output" == *"exists"* ]]
    [[ "$(sha256_of "$root/receipt.json")" == "$receipt_sha" ]]

    rm "$root/receipt.json"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 0 ]]
    cmp "$root/expected-receipt.json" "$root/receipt.json"

    before="$(fixture_tool snapshot "$root")"
    receipt_mtime="$(stat -f '%m' "$root/receipt.json" 2>/dev/null || stat -c '%Y' "$root/receipt.json")"
    count="$(find "$root" -mindepth 1 | wc -l | tr -d ' ')"
    run verify_fixture "$root"
    [[ "$status" -eq 0 ]]
    after="$(fixture_tool snapshot "$root")"
    [[ "$after" == "$before" ]]
    [[ "$(stat -f '%m' "$root/receipt.json" 2>/dev/null || stat -c '%Y' "$root/receipt.json")" == "$receipt_mtime" ]]
    [[ "$(find "$root" -mindepth 1 | wc -l | tr -d ' ')" == "$count" ]]

}

@test "all protocol schemas are recursively closed and expose the exact tree algorithms" {
    local schema
    for schema in \
        pi-ollama-preflight-spec.schema.json \
        pi-ollama-preflight-receipt.schema.json \
        pi-ollama-arm-contract.schema.json \
        pi-ollama-adapter-request.schema.json \
        pi-ollama-adapter-result.schema.json; do
        run jq -e '
          [.. | objects |
            select(.type == "object" and (has("properties") or has("required"))) |
            .additionalProperties] | all(. == false)
        ' "$PROTOCOL_ROOT/$schema"
        [[ "$status" -eq 0 ]]
    done
    run jq -e '
      (.required | index("arm_contract")) != null and
      .properties.arm_contract."$ref" == "#/$defs/fileBinding" and
      .properties.mainframe.properties.installed_tree.properties.algorithm.const ==
        "mainframe-package-tree-sha256-v1" and
      .properties.pi.properties.package_tree.properties.algorithm.const ==
        "mainframe-pi-runtime-tree-sha256-v1"
    ' "$PROTOCOL_ROOT/pi-ollama-preflight-spec.schema.json"
    [[ "$status" -eq 0 ]]

    local certified_id
    certified_id="$(jq -r '.certifications[] |
        select(.version == "0.84.1" and .support == "certified" and .profile == "full") |
        .id' "$PROJECT_ROOT/config/pi-compatibility.json")"
    run jq -e --arg id "$certified_id" \
        '.["$defs"].certificationId.pattern as $pattern | $id | test($pattern)' \
        "$PROTOCOL_ROOT/pi-ollama-preflight-spec.schema.json"
    [[ "$status" -eq 0 ]]
}

@test "closed spec and arm contracts reject extras and recursive exact neutrality leaks" {
    local root="$TEST_DIR/closed-spec"
    fixture_tool create "$root"
    jq '.surprise = true' "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
    [[ ! -e "$root/receipt.json" ]]

    root="$TEST_DIR/closed-arm"
    fixture_tool create "$root"
    jq '.surprise = true' "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    bind_arm "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/forbidden-key"
    fixture_tool create "$root"
    jq '.provider.control = "opaque"' "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    bind_arm "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/forbidden-value"
    fixture_tool create "$root"
    jq '.study_id = "treatment"' "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    bind_arm "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/credential-env"
    fixture_tool create "$root"
    jq '.environment_contract.allowed_environment_names += ["AWS_SECRET_ACCESS_KEY"]' \
        "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    bind_arm "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
}

@test "verify rejects spec arm bound-file tree model and receipt tampering" {
    local kind root target original
    for kind in spec arm file mainframe-tree pi-tree model receipt; do
        root="$TEST_DIR/tamper-$kind"
        prepare_fixture "$root"
        case "$kind" in
            spec)
                target="$root/spec.json"
                printf ' ' >> "$target"
                ;;
            arm)
                target="$root/arm.json"
                printf ' ' >> "$target"
                ;;
            file)
                target="$root/mainframe/evals/agent-impact/pi-ollama-adapter-request.schema.json"
                printf ' ' >> "$target"
                ;;
            mainframe-tree)
                target="$root/mainframe/VERSION"
                printf ' ' >> "$target"
                ;;
            pi-tree)
                target="$root/pi-package/dist/core/extensions/loader.js"
                printf ' ' >> "$target"
                ;;
            model)
                target="$(jq -r '.ollama.model.ordered_blobs[1].path' "$root/spec.json")"
                printf ' ' >> "$target"
                ;;
            receipt)
                target="$root/receipt.json"
                original="$TEST_DIR/receipt.changed"
                jq '.execution.provider_requests_by_preflight = 1' "$target" > "$original"
                mv "$original" "$target"
                chmod 600 "$target"
                ;;
        esac
        run verify_fixture "$root"
        [[ "$status" -eq 2 ]]
        [[ "$output" != *"Traceback"* ]]
    done
}

@test "claimed tree digests are recomputed and contained Pi symlinks do not weaken escape checks" {
    local root="$TEST_DIR/tree-claim"
    fixture_tool create "$root"
    jq '.mainframe.installed_tree.sha256 = ("0" * 64)' "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/pi-tree-claim"
    fixture_tool create "$root"
    jq '.pi.package_tree.sha256 = ("f" * 64)' "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/pi-symlink-escape"
    fixture_tool create "$root"
    rm "$root/pi-package/node_modules/.bin/helper"
    ln -s '../../../../outside' "$root/pi-package/node_modules/.bin/helper"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/pi-symlink-cycle"
    fixture_tool create "$root"
    ln -s 'cycle-b' "$root/pi-package/cycle-a"
    ln -s 'cycle-a' "$root/pi-package/cycle-b"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
}

@test "descriptor-safe validation rejects symlink hardlink special and unsafe path inputs" {
    local root target target_sha target_size
    root="$TEST_DIR/final-symlink"
    fixture_tool create "$root"
    target="$(jq -r '.node.executable.path' "$root/spec.json")"
    ln -s "$target" "$root/node-link"
    target_sha="$(sha256_of "$target")"
    target_size="$(wc -c < "$target" | tr -d ' ')"
    jq --arg path "$root/node-link" --arg sha "$target_sha" --argjson size "$target_size" \
        '.node.executable = {path:$path, sha256:$sha, size_bytes:$size}' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/ancestor-symlink"
    fixture_tool create "$root/real"
    ln -s "$root/real/node-install" "$root/linked-node-install"
    target="$root/real/node-install/bin/node"
    target_sha="$(sha256_of "$target")"
    target_size="$(wc -c < "$target" | tr -d ' ')"
    jq --arg path "$root/linked-node-install/bin/node" --arg sha "$target_sha" \
        --argjson size "$target_size" \
        '.node.executable = {path:$path, sha256:$sha, size_bytes:$size}' \
        "$root/real/spec.json" > "$root/real/spec.changed"
    mv "$root/real/spec.changed" "$root/real/spec.json"
    chmod 600 "$root/real/spec.json"
    refresh_runtime "$root/real"
    run preflight prepare --spec "$root/real/spec.json" --arm-contract "$root/real/arm.json" \
        --output "$root/real/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/hardlink"
    fixture_tool create "$root"
    ln "$root/mainframe/VERSION" "$root/mainframe/VERSION.alias"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/hardlinked-symlink"
    fixture_tool create "$root"
    "$PYTHON_BIN" - "$root/pi-package/node_modules/.bin/helper" \
        "$root/pi-package/node_modules/.bin/helper.alias" <<'PYEOF'
import os
import sys
os.link(sys.argv[1], sys.argv[2], follow_symlinks=False)
PYEOF
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/tree-special"
    fixture_tool create "$root"
    mkfifo "$root/mainframe/unexpected.fifo"
    run run_with_deadline preflight prepare --spec "$root/spec.json" \
        --arm-contract "$root/arm.json" --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
    [[ "$status" -ne 124 ]]

    root="$TEST_DIR/fifo"
    fixture_tool create "$root"
    mkfifo "$root/request-schema.fifo"
    jq --arg path "$root/request-schema.fifo" '.adapter.request_schema.path = $path' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run run_with_deadline preflight prepare --spec "$root/spec.json" \
        --arm-contract "$root/arm.json" --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
    [[ "$status" -ne 124 ]]
    [[ "$output" != *"Traceback"* ]]

    root="$TEST_DIR/unsafe-paths"
    fixture_tool create "$root"
    jq '.node.executable.path = "//tmp/node"' "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/broad-root"
    fixture_tool create "$root"
    jq '.mainframe.installed_tree.root = "/usr"' "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/missing-ancestor"
    fixture_tool create "$root"
    jq --arg path "$root/missing/bin/node" '.node.executable.path = $path' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" != *"Traceback"* ]]
}

@test "receipt output cannot overlap any bound input or runtime tree and receipt mode is enforced" {
    local root="$TEST_DIR/output-containment" output
    fixture_tool create "$root"
    for output in \
        "$root/mainframe/receipt.json" \
        "$root/pi-package/receipt.json" \
        "$root/ollama-models/receipt.json"; do
        run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
            --output "$output"
        [[ "$status" -eq 2 ]]
        [[ ! -e "$output" ]]
    done

    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 0 ]]
    [[ "$(mode_of "$root/receipt.json")" == 600 ]]
    chmod 644 "$root/receipt.json"
    run verify_fixture "$root"
    [[ "$status" -eq 2 ]]
}

@test "arm swapping and runtime-binding mismatch cannot verify against an existing receipt" {
    local root="$TEST_DIR/arm-swap" second="$TEST_DIR/second-arm.json"
    prepare_fixture "$root"
    jq '.pair_id = "pair-8899aabbccddeeff" |
        .opaque_arm_ids = ["arm-1111111111111111", "arm-2222222222222222"]' \
        "$root/arm.json" > "$second"
    chmod 600 "$second"
    run preflight verify --spec "$root/spec.json" --arm-contract "$second" \
        --receipt "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    jq '.runtime_binding.sha256 = ("0" * 64)' "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    bind_arm "$root"
    run verify_fixture "$root"
    [[ "$status" -eq 2 ]]
}

@test "Ollama closure rejects descriptor order multiplicity size media config and template drift" {
    local case root manifest config_path new_digest new_path
    for case in reordered duplicate wrong-size wrong-media; do
        root="$TEST_DIR/model-$case"
        fixture_tool create "$root"
        manifest="$(jq -r '.ollama.model.manifest.path' "$root/spec.json")"
        case "$case" in
            reordered)
                jq '.layers = [.layers[1], .layers[0], .layers[2], .layers[3]]' \
                    "$manifest" > "$manifest.changed"
                ;;
            duplicate)
                jq '.layers += [.layers[0]]' "$manifest" > "$manifest.changed"
                ;;
            wrong-size)
                jq '.layers[0].size += 1' "$manifest" > "$manifest.changed"
                ;;
            wrong-media)
                jq '.layers[0].mediaType = "application/vnd.ollama.image.template"' \
                    "$manifest" > "$manifest.changed"
                ;;
        esac
        mv "$manifest.changed" "$manifest"
        chmod 644 "$manifest"
        refresh_fixture "$root"
        run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
            --output "$root/receipt.json"
        [[ "$status" -eq 2 ]]
    done

    root="$TEST_DIR/model-name-manifest-path"
    fixture_tool create "$root"
    jq '.ollama.model.name = "different-model:latest"' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    jq '.provider.model = "different-model:latest"' \
        "$root/arm.json" > "$root/arm.changed"
    mv "$root/arm.changed" "$root/arm.json"
    chmod 600 "$root/arm.json"
    refresh_fixture "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/model-blob-layout"
    fixture_tool create "$root"
    config_path="$(jq -r '.ollama.model.ordered_blobs[0].path' "$root/spec.json")"
    mkdir -p "$root/ollama-models/rogue-blobs"
    new_path="$root/ollama-models/rogue-blobs/$(basename "$config_path")"
    mv "$config_path" "$new_path"
    jq --arg path "$new_path" '.ollama.model.ordered_blobs[0].path = $path' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_fixture "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/model-config-order"
    fixture_tool create "$root"
    manifest="$(jq -r '.ollama.model.manifest.path' "$root/spec.json")"
    config_path="$(jq -r '.ollama.model.ordered_blobs[0].path' "$root/spec.json")"
    jq '.rootfs.diff_ids |= reverse' "$config_path" > "$config_path.changed"
    new_digest="$(sha256_of "$config_path.changed")"
    new_path="$(dirname "$config_path")/sha256-$new_digest"
    mv "$config_path.changed" "$new_path"
    chmod 644 "$new_path"
    jq --arg digest "sha256:$new_digest" --argjson size "$(wc -c < "$new_path")" \
        '.config.digest = $digest | .config.size = $size' "$manifest" > "$manifest.changed"
    mv "$manifest.changed" "$manifest"
    chmod 644 "$manifest"
    jq --arg digest "sha256:$new_digest" --arg path "$new_path" \
        --argjson size "$(wc -c < "$new_path")" \
        '.ollama.model.config_descriptor.digest = $digest |
         .ollama.model.config_descriptor.size_bytes = $size |
         .ollama.model.ordered_blobs[0].digest = $digest |
         .ollama.model.ordered_blobs[0].path = $path |
         .ollama.model.ordered_blobs[0].size_bytes = $size' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_fixture "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/model-template-markers"
    fixture_tool create "$root"
    fixture_tool strip-template-markers "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
}

@test "host architecture and installation receipts are semantically bound" {
    local root="$TEST_DIR/platform-arch" other receipt compatibility copied copied_sha copied_size
    fixture_tool create "$root"
    other="$(jq -r 'if .platform.architecture == "arm64" then "x86_64" else "arm64" end' \
        "$root/spec.json")"
    jq --arg arch "$other" '.platform.architecture = $arch' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/node-receipt-arch"
    fixture_tool create "$root"
    receipt="$(jq -r '.node.install_receipt.path' "$root/spec.json")"
    other="$(jq -r 'if .platform.architecture == "arm64" then "x86_64" else "arm64" end' \
        "$root/spec.json")"
    jq --arg arch "$other" '.arch = $arch' "$receipt" > "$receipt.changed"
    mv "$receipt.changed" "$receipt"
    chmod 644 "$receipt"
    refresh_fixture "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/node-receipt-root"
    fixture_tool create "$root"
    copied="$root/copied-node"
    cp "$(jq -r '.node.executable.path' "$root/spec.json")" "$copied"
    chmod 755 "$copied"
    copied_sha="$(sha256_of "$copied")"
    copied_size="$(wc -c < "$copied" | tr -d ' ')"
    jq --arg path "$copied" --arg sha "$copied_sha" --argjson size "$copied_size" \
        '.node.executable = {path:$path, sha256:$sha, size_bytes:$size}' \
        "$root/spec.json" > "$root/spec.changed"
    mv "$root/spec.changed" "$root/spec.json"
    chmod 600 "$root/spec.json"
    refresh_runtime "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]

    root="$TEST_DIR/pi-certification-integrity"
    fixture_tool create "$root"
    compatibility="$(jq -r '.mainframe.pi_compatibility_manifest.path' "$root/spec.json")"
    jq '.certifications[0].npm_integrity = "not-a-package-integrity"' \
        "$compatibility" > "$compatibility.changed"
    mv "$compatibility.changed" "$compatibility"
    chmod 644 "$compatibility"
    refresh_fixture "$root"
    run preflight prepare --spec "$root/spec.json" --arm-contract "$root/arm.json" \
        --output "$root/receipt.json"
    [[ "$status" -eq 2 ]]
}

@test "static implementation surface has no process network dynamic-code or provider escape hatch" {
    run "$PYTHON_BIN" - "$TOOL" "$PROTOCOL_ROOT/runners/pi-ollama-adapter.py" <<'PYEOF'
import ast
from pathlib import Path
import sys

preflight, adapter = map(Path, sys.argv[1:])
denied_import_roots = {
    "asyncio", "ctypes", "http", "importlib", "multiprocessing", "pty",
    "requests", "shlex", "socket", "subprocess", "telnetlib", "urllib",
    "webbrowser",
}
denied_names = {"__import__", "compile", "eval", "exec"}
denied_os_calls = {
    "execl", "execle", "execlp", "execlpe", "execv", "execve", "execvp",
    "execvpe", "fork", "forkpty", "popen", "posix_spawn", "posix_spawnp", "system",
}

for path in (preflight, adapter):
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split(".")[0] not in denied_import_roots, (path, alias.name)
        elif isinstance(node, ast.ImportFrom):
            assert (node.module or "").split(".")[0] not in denied_import_roots, (path, node.module)
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in denied_names, (path, node.func.id)
            elif (isinstance(node.func, ast.Attribute) and
                  isinstance(node.func.value, ast.Name) and node.func.value.id == "os"):
                assert node.func.attr not in denied_os_calls, (path, node.func.attr)

preflight_tree = ast.parse(preflight.read_text(encoding="utf-8"))
actions = {
    arg.value
    for node in ast.walk(preflight_tree)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    and node.func.attr == "add_parser"
    for arg in node.args[:1]
    if isinstance(arg, ast.Constant) and isinstance(arg.value, str)
}
assert actions == {"prepare", "verify"}, actions
PYEOF
    [[ "$status" -eq 0 ]]
    [[ ! -e "$INVOCATION_MARKER" ]]
}

@test "schemas and implementation remain compatible with Python 3.9 syntax" {
    run "$PYTHON_BIN" - "$TOOL" \
        "$PROTOCOL_ROOT/runners/pi-ollama-adapter.py" \
        "$PROTOCOL_ROOT/pi-ollama-preflight-spec.schema.json" \
        "$PROTOCOL_ROOT/pi-ollama-preflight-receipt.schema.json" \
        "$PROTOCOL_ROOT/pi-ollama-arm-contract.schema.json" \
        "$PROTOCOL_ROOT/pi-ollama-adapter-request.schema.json" \
        "$PROTOCOL_ROOT/pi-ollama-adapter-result.schema.json" <<'PYEOF'
import ast
import json
from pathlib import Path
import sys

for raw in sys.argv[1:3]:
    ast.parse(Path(raw).read_text(encoding="utf-8"), filename=raw,
              feature_version=(3, 9))
for raw in sys.argv[3:]:
    value = json.loads(Path(raw).read_text(encoding="utf-8"))
    assert isinstance(value, dict) and value.get("$schema") == \
        "https://json-schema.org/draft/2020-12/schema"
PYEOF
    [[ "$status" -eq 0 ]]
}

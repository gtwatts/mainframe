#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    RECEIPT_TOOL="$PROJECT_ROOT/scripts/dev/agent-impact-awm-receipt.py"
    FIXTURE_RUNNER="$PROJECT_ROOT/scripts/dev/run-agent-impact-awm-fixture.py"
    PYTHON_BIN="$(command -v python3)"
    JQ_BIN="$(command -v jq)"
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    [[ -n "$JQ_BIN" ]] || skip "jq is required"
    local logical_test_dir
    logical_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-awm-receipt.XXXXXX")"
    TEST_DIR="$(cd "$logical_test_dir" && pwd -P)"
    chmod 700 "$TEST_DIR"
    make_private_fixture
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf -- "$TEST_DIR"
}

mode_of() {
    local path="$1"
    if stat -c '%a' "$path" >/dev/null 2>&1; then
        stat -c '%a' "$path"
    else
        stat -f '%Lp' "$path"
    fi
}

sha256_of() {
    "$PYTHON_BIN" - "$1" <<'PY'
import hashlib
import pathlib
import sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

canonicalize_json_file() {
    local path="$1" mode="$2"
    "$PYTHON_BIN" - "$path" "$mode" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
path.write_text(
    json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n",
    encoding="utf-8",
)
path.chmod(int(sys.argv[2], 8))
PY
}

make_private_fixture() {
    "$PYTHON_BIN" - "$TEST_DIR" "$PROJECT_ROOT" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1]).resolve()
project_root = Path(sys.argv[2]).resolve()
private = root / "private"
public = root / "public"
runtime = root / "private-runtime"
private.mkdir(mode=0o700)
public.mkdir(mode=0o755)
runtime.mkdir(mode=0o700)

def canonical(value):
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")

def sha(payload):
    return hashlib.sha256(payload).hexdigest()

def write_json(path, value, mode):
    path.write_bytes(canonical(value) + b"\n")
    path.chmod(mode)

def file_entry(path, payload, mode="0600"):
    return {
        "path": path,
        "type": "file",
        "mode": mode,
        "size_bytes": len(payload),
        "sha256": sha(payload),
    }

def directory_entry(path, mode="0700"):
    return {"path": path, "type": "directory", "mode": mode}

def snapshot(entries, *, present=True, root_mode="0700"):
    entries = sorted(entries, key=lambda item: item["path"].encode("utf-8"))
    files = [item for item in entries if item["type"] == "file"]
    directories = [item for item in entries if item["type"] == "directory"]
    return {
        "algorithm": "mainframe-agent-impact-private-tree-sha256-v1",
        "present": present,
        "root_mode": root_mode if present else None,
        "entry_count": len(entries),
        "file_count": len(files),
        "directory_count": len(directories),
        "total_file_bytes": sum(item["size_bytes"] for item in files),
        "tree_sha256": sha(canonical(entries)),
        "entries": entries,
    }

pair_id = "pair-1111111111111111"
treatment_arm = "arm-aaaaaaaaaaaaaaaa"
control_arm = "arm-bbbbbbbbbbbbbbbb"
task_id = "receipt-fixture-task"
study_id = "receipt-fixture-study"
release_archive = "a" * 64
installed_tree = "b" * 64
sidecar = "c" * 64
study_spec_sha = "1" * 64
seed_commitment = "3" * 64
task_bundle_sha = "4" * 64
budgets = {
    "wall_seconds_per_phase": 900,
    "maximum_tool_calls_per_phase": 40,
    "maximum_context_bytes": 8192,
    "maximum_input_tokens_per_phase": 1000,
    "maximum_output_tokens_per_phase": 1000,
    "maximum_cost_usd_per_pair": 1,
}

corpus = {
    "protocol_version": 1,
    "suite_path": "evals/agent-impact/corpus/suite.json",
    "suite_mode": "0644",
    "suite_id": "receipt-fixture-suite",
    "suite_sha256": "0" * 64,
    "schemas": [],
    "tasks": [{"task_id": task_id, "task_bundle_sha256": task_bundle_sha}],
}
corpus["corpus_sha256"] = sha(canonical(corpus))
bindings = {
    "study_spec": {
        "path": "evals/agent-impact/live-study.json",
        "mode": "0644",
        "sha256": study_spec_sha,
    },
    "corpus": corpus,
    "mainframe_release": {
        "archive_path": "release/mainframe-fixture.tar.gz",
        "archive_mode": "0644",
        "archive_sha256": release_archive,
        "checksum_sidecar_path": "release/mainframe-fixture.tar.gz.sha256",
        "checksum_sidecar_mode": "0644",
        "checksum_sidecar_sha256": sidecar,
        "installed_tree_algorithm": "mainframe-package-tree-sha256-v1",
        "installed_tree_sha256": installed_tree,
    },
    "policies": {
        "awm_mechanism_contract": {
            "controls": {
                "treatment_intervention": "mainframe-awm-handoff",
                "context_limit_unit": "bytes-under-LC_ALL-C",
            }
        }
    },
}
randomization = sha(canonical({
    "domain": "mainframe-agent-impact-live-v2-randomization-context",
    "study_id": study_id,
    "bindings": bindings,
}))
instance_sha = sha(canonical({"task_bundle_sha256": task_bundle_sha, "replicate": 1}))

assignments = {
    "schema_version": 2,
    "kind": "mainframe-agent-impact-live-assignments",
    "study_id": study_id,
    "study_spec_sha256": study_spec_sha,
    "corpus_sha256": corpus["corpus_sha256"],
    "randomization_context_sha256": randomization,
    "seed_commitment_sha256": seed_commitment,
    "assignments": [
        {
            "pair_id": pair_id,
            "task_id": task_id,
            "replicate": 1,
            "arms": [
                {"opaque_arm_id": treatment_arm, "mode": "treatment"},
                {"opaque_arm_id": control_arm, "mode": "control"},
            ],
        }
    ],
}
assignment_commitment = sha(canonical(assignments))
preregistration = {
    "schema_version": 2,
    "kind": "mainframe-agent-impact-preregistration",
    "study_id": study_id,
    "title": "Synthetic receipt fixture",
    "claim_scope": "preregistered-live-study-not-run",
    "execution_status": "not-run",
    "non_claims": {"live_agent_sessions": 0},
    "design": {"budgets": budgets},
    "bindings": bindings,
    "randomization_context_sha256": randomization,
    "seed_commitment_sha256": seed_commitment,
    "assignment_commitment_sha256": assignment_commitment,
    "planned_pair_count": 1,
    "pairs": [
        {
            "pair_id": pair_id,
            "task_id": task_id,
            "replicate": 1,
            "instance_sha256": instance_sha,
            "opaque_arm_order": [treatment_arm, control_arm],
            "budgets": budgets,
        }
    ],
}
preregistration_payload = canonical(preregistration) + b"\n"
binding = {
    "preregistration_sha256": sha(preregistration_payload),
    "randomization_context_sha256": randomization,
    "assignment_commitment_sha256": assignment_commitment,
    "study_id": study_id,
    "pair_id": pair_id,
    "task_id": task_id,
    "replicate": 1,
    "instance_sha256": instance_sha,
    "opaque_arm_id": treatment_arm,
    "arm_mode": "treatment",
    "phase": "investigate",
}

marker = runtime / "install" / "bin" / "marker"
marker.parent.mkdir(parents=True, mode=0o700)
marker.write_text(
    "#!/bin/sh\nprintf invoked > "
    + json.dumps(str(root / "marker-invoked"))
    + "\nexit 99\n",
    encoding="utf-8",
)
marker.chmod(0o700)
mainframe_root = str(runtime / "install")
home = runtime / "home"
home.mkdir(mode=0o700)
awm_root = str(home / ".mainframe" / "awm")
workspace = runtime / "workspace"
workspace.mkdir(mode=0o700)
tmp_root = runtime / "tmp"
tmp_root.mkdir(mode=0o700)
request_private = runtime / "private"
request_private.mkdir(mode=0o700)
request_path = str(request_private / "request.json")

extension_source = (project_root / "skills/pi/extensions/mainframe.ts").read_text(encoding="utf-8")
script_prefix = "const script = String.raw`"
script_start = extension_source.index(script_prefix) + len(script_prefix)
protected_awm_script = extension_source[script_start:extension_source.index("`;", script_start)]

runtime_expected = {
    "mainframe_archive_sha256": release_archive,
    "installed_tree_algorithm": "mainframe-package-tree-sha256-v1",
    "installed_tree_sha256": installed_tree,
    "pi_package": "@mariozechner/pi-coding-agent",
    "pi_version": "0.84.1",
    "pi_executable_sha256": "5" * 64,
    "pi_loader_sha256": "6" * 64,
    "pi_extension_sha256": "7" * 64,
    "transition_driver_sha256": "8" * 64,
    "node_executable_sha256": "9" * 64,
    "node_version": "v22.0.0",
}
paths = {
    "mainframe_root": mainframe_root,
    "pi_bin": str(marker),
    "node_bin": str(marker),
    "workspace": str(workspace),
    "awm_root": awm_root,
    "tmp_root": str(tmp_root),
}
fixture = {
    "session_name": "pi-impact-handoff",
    "namespace": "pi-impact-test",
    "checkpoint_key": "implementation-root-cause",
    "checkpoint_value": "subtract used capacity from total capacity",
    "checkpoint_importance": "critical",
    "handoff_target": "implementer",
}
budget = {"maximum_context_bytes": 8192, "tool_timeout_ms": 10000}
request_document = {
    "schema_version": 1,
    "kind": "mainframe-agent-impact-pi-awm-transition-request",
    "claim_scope": "synthetic-treatment-investigate-awm-mechanism-conformance-only",
    "binding": binding,
    "paths": paths,
    "runtime_expected": runtime_expected,
    "budget": budget,
    "fixture": fixture,
}
request_canonical = canonical(request_document)

session_id = "0123456789ab"
handoff_id = "handoff_1700000000_implementer"
context = {
    "task": fixture["handoff_target"],
    "session_id": session_id,
    "max_tokens": 2048,
    "provenance": {
        "schema_version": 2,
        "namespace": fixture["namespace"],
        "backend": "file",
        "source_agent": "mainframe-eval",
    },
    "budget": {
        "requested_tokens": 2048,
        "chars_per_token": 4,
        "max_chars": 8192,
        "actual_chars": 0,
        "actual_tokens": 0,
        "truncated": False,
    },
    "discoveries": [],
    "progress": {},
    "checkpoints": [{
        "key": fixture["checkpoint_key"],
        "value": fixture["checkpoint_value"],
        "importance": fixture["checkpoint_importance"],
    }],
    "logs": [],
    "related": [],
    "summary": {"status": "ready-for-implementation"},
}
for _ in range(12):
    context_payload = canonical(context)
    context_chars = len(context_payload)
    context_tokens = (context_chars + 3) // 4
    if context["budget"]["actual_chars"] == context_chars and context["budget"]["actual_tokens"] == context_tokens:
        break
    context["budget"]["actual_chars"] = context_chars
    context["budget"]["actual_tokens"] = context_tokens
handoff_document = {
    "type": "handoff",
    "handoff_id": handoff_id,
    "created_at": "2026-08-09T18:00:00+0000",
    "parent_session": session_id,
    "parent_agent": "mainframe-eval",
    "target_agent": fixture["handoff_target"],
    "budget_remaining": 2048,
    "provenance": {"schema_version": 2, "namespace": fixture["namespace"], "backend": "file"},
    "budget": {
        "requested_tokens": 2048,
        "chars_per_token": 4,
        "max_chars": 8192,
        "actual_chars": 0,
        "actual_tokens": 0,
        "truncated": False,
    },
    "status": {
        "session_id": session_id,
        "schema_version": 2,
        "status": "active",
        "namespace": fixture["namespace"],
        "backend": "file",
        "manifest": awm_root + "/sessions/" + fixture["namespace"] + "/" + session_id + "/manifest.json",
        "discoveries": 0,
        "checkpoints": 1,
        "handoffs": 0,
        "logs": 0,
        "token_estimate": context["budget"]["actual_tokens"],
    },
    "open_questions": [],
    "context": context,
}
for _ in range(12):
    emitted = canonical(handoff_document)
    actual = len(emitted)
    tokens = (actual + 3) // 4
    if handoff_document["budget"]["actual_chars"] == actual and handoff_document["budget"]["actual_tokens"] == tokens:
        break
    handoff_document["budget"]["actual_chars"] = actual
    handoff_document["budget"]["actual_tokens"] = tokens
emitted = canonical(handoff_document).decode("utf-8")
emitted_bytes = emitted.encode("utf-8")
persisted_relative = (
    "sessions/pi-impact-test/"
    + session_id
    + "/handoffs/"
    + handoff_id
    + ".json"
)
persisted_path = awm_root + "/" + persisted_relative

installed_entries = [
    directory_entry("bin", "0755"),
    file_entry("bin/mainframe", b"synthetic-mainframe", "0755"),
]
installed_snapshot = snapshot(installed_entries, root_mode="0755")
workspace_snapshot = snapshot([], root_mode="0700")
tmp_snapshot = snapshot([], root_mode="0700")
awm_before = snapshot([], present=False)
base_session = "sessions/pi-impact-test/" + session_id
awm_directories = [
    directory_entry("sessions"),
    directory_entry("sessions/pi-impact-test"),
    directory_entry(base_session),
    directory_entry(base_session + "/data"),
    directory_entry(base_session + "/handoffs"),
    directory_entry(base_session + "/journal"),
]
manifest = canonical({"schema_version": 2, "session_id": session_id, "backend": "file"})
after_init_entries = awm_directories + [file_entry(base_session + "/manifest.json", manifest)]
after_checkpoint_entries = after_init_entries + [
    file_entry(base_session + "/data/implementation-root-cause", fixture["checkpoint_value"].encode("utf-8"))
]
after_handoff_entries = after_checkpoint_entries + [file_entry(persisted_relative, emitted_bytes)]
awm_after_init = snapshot(after_init_entries)
awm_after_checkpoint = snapshot(after_checkpoint_entries)
awm_after_handoff = snapshot(after_handoff_entries)

def output_binding(text):
    payload = text.encode("utf-8")
    return {"size_bytes": len(payload), "sha256": sha(payload)}

def process(stdout):
    return {
        "code": 0,
        "signal": None,
        "stdout": stdout,
        "stderr": "",
        "timedOut": False,
        "command": str(marker),
        "args": ["--noprofile", "--norc", "-p", "-c", protected_awm_script],
    }

state_pairs = [
    (awm_before, awm_after_init),
    (awm_after_init, awm_after_checkpoint),
    (awm_after_checkpoint, awm_after_handoff),
]
actions = ["init", "checkpoint", "handoff_prepare"]
stdouts = [session_id, "", emitted]
previous = "0" * 64
records = []
for index, (action, states, stdout) in enumerate(zip(actions, state_pairs, stdouts), 1):
    common = {"root": mainframe_root, "timeoutMs": 10000, "action": action}
    if action == "init":
        params = {**common, "name": fixture["session_name"], "namespace": fixture["namespace"], "model": "fixture-no-provider"}
    elif action == "checkpoint":
        params = {
            **common,
            "session": session_id,
            "key": fixture["checkpoint_key"],
            "value": fixture["checkpoint_value"],
            "importance": fixture["checkpoint_importance"],
        }
    else:
        params = {**common, "session": session_id, "message": fixture["handoff_target"], "tokens": 2048}
    body = {
        "index": index,
        "action": action,
        "call_id": f"{treatment_arm}-awm-{index}-{action}",
        "previous_record_sha256": previous,
        "tool_params": params,
        "awm_before_sha256": states[0]["tree_sha256"],
        "awm_after_sha256": states[1]["tree_sha256"],
        "process_result": process(stdout),
        "stdout_binding": output_binding(stdout),
        "stderr_binding": output_binding(""),
    }
    record_digest = sha(canonical(body))
    records.append({**body, "record_sha256": record_digest})
    previous = record_digest

raw = {
    "schema_version": 1,
    "kind": "mainframe-agent-impact-pi-awm-transition-private-record",
    "claim_scope": "synthetic-treatment-investigate-awm-mechanism-conformance-only",
    "binding": binding,
    "runtime_expected": runtime_expected,
    "budget": budget,
    "fixture": fixture,
    "request": {
        "path": request_path,
        "file_sha256": sha(request_canonical + b"\n"),
        "canonical_sha256": sha(request_canonical),
    },
    "environment": {
        "allowed_names": [
            "CI", "HOME", "LANG", "LC_ALL", "LOGNAME", "MAINFRAME_EVAL_PROTOCOL",
            "NO_COLOR", "PATH", "PI_CODING_AGENT_DIR", "PI_OFFLINE", "TMPDIR", "USER",
            "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
        ],
        "values": {
            "USER": "mainframe-eval",
            "LOGNAME": "mainframe-eval",
            "PI_OFFLINE": "1",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "LANG": "C",
            "NO_COLOR": "1",
            "CI": "1",
            "MAINFRAME_EVAL_PROTOCOL": "1",
            "__CF_USER_TEXT_ENCODING": None,
        },
        "isolated_paths": {
            "HOME": str(home),
            "PI_CODING_AGENT_DIR": str(runtime / "pi-agent"),
            "TMPDIR": str(tmp_root),
            "XDG_CONFIG_HOME": str(runtime / "xdg-config"),
            "XDG_STATE_HOME": str(runtime / "xdg-state"),
            "XDG_CACHE_HOME": str(runtime / "xdg-cache"),
        },
    },
    "runtime_observed": {
        "mainframe_archive_sha256": release_archive,
        "mainframe_version": "10.2.0",
        "installed_tree_algorithm": "mainframe-package-tree-sha256-v1",
        "installed_tree_sha256": installed_tree,
        "pi_package": runtime_expected["pi_package"],
        "pi_version": runtime_expected["pi_version"],
        "pi_executable": str(marker),
        "pi_executable_sha256": runtime_expected["pi_executable_sha256"],
        "pi_package_manifest_sha256": "e" * 64,
        "pi_loader": str(marker.parent / "core" / "extensions" / "loader.js"),
        "pi_loader_sha256": runtime_expected["pi_loader_sha256"],
        "pi_extension": str(runtime / "install" / "skills" / "pi" / "extensions" / "mainframe.ts"),
        "pi_extension_sha256": runtime_expected["pi_extension_sha256"],
        "transition_driver": str(runtime / "install" / "evals" / "agent-impact" / "runners" / "pi-awm-transition-driver.mjs"),
        "transition_driver_sha256": runtime_expected["transition_driver_sha256"],
        "node_executable": str(marker),
        "node_executable_sha256": runtime_expected["node_executable_sha256"],
        "node_version": runtime_expected["node_version"],
        "bash_executable": str(marker),
        "bash_executable_sha256": "f" * 64,
        "bash_version": "5.2.0(1)-release",
        "registered_tools": [
            "mainframe_awm", "mainframe_bash_safety_check", "mainframe_exec",
            "mainframe_help", "mainframe_install_commands", "mainframe_search", "mainframe_status",
        ],
        "loaded_mainframe_awm": True,
        "network_api_guards": sorted([
            "fetch", "http.request", "https.request", "net.connect", "tls.connect",
            "dns.lookup", "child_process.exec", "child_process.spawn",
        ]),
        "provider_adapter_loaded": False,
        "provider_inference_requests": 0,
    },
    "paths": paths,
    "snapshots": {
        "installed_before": installed_snapshot,
        "installed_after": installed_snapshot,
        "installed_package_before": {
            "algorithm": "mainframe-package-tree-sha256-v1",
            "sha256": installed_tree,
            "entry_count": len(installed_entries),
        },
        "installed_package_after": {
            "algorithm": "mainframe-package-tree-sha256-v1",
            "sha256": installed_tree,
            "entry_count": len(installed_entries),
        },
        "workspace_before": workspace_snapshot,
        "workspace_after": workspace_snapshot,
        "awm_before": awm_before,
        "awm_after_init": awm_after_init,
        "awm_after_checkpoint": awm_after_checkpoint,
        "awm_after_handoff": awm_after_handoff,
        "tmp_before": tmp_snapshot,
        "tmp_after": tmp_snapshot,
        "installed_unchanged": True,
        "workspace_unchanged": True,
    },
    "sequence": {
        "algorithm": "sha256-canonical-json-previous-record-v1",
        "genesis_sha256": "0" * 64,
        "record_count": 3,
        "head_sha256": previous,
        "records": records,
    },
    "handoff": {
        "session_id": session_id,
        "handoff_id": handoff_id,
        "persisted_path": persisted_path,
        "emitted_size_bytes": len(emitted_bytes),
        "emitted_sha256": sha(emitted_bytes),
        "emitted_raw_utf8": emitted,
        "persisted_size_bytes": len(emitted_bytes),
        "persisted_sha256": sha(emitted_bytes),
        "persisted_raw_utf8": emitted,
        "emitted_equals_persisted": True,
        "maximum_context_bytes": 8192,
    },
    "non_claims": {
        "real_provider_inference": "not-run",
        "live_agent_sessions": 0,
        "agent_quality": "not-measured",
        "comparative_agent_performance": "not-measured",
        "developer_productivity": "not-measured",
        "machine_safety": "not-established",
        "network_containment": "best-effort-node-api-guards-not-os-isolation",
    },
}

write_json(root / "preregistration.json", preregistration, 0o644)
write_json(root / "assignments.json", assignments, 0o600)
write_json(root / "raw.json", raw, 0o600)
(root / "audit.key").write_bytes(b"receipt-audit-key-32-bytes-minimum-material\n")
(root / "audit.key").chmod(0o600)
PY
}

prepare_receipt() {
    "$PYTHON_BIN" "$RECEIPT_TOOL" prepare \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral-output "$TEST_DIR/private/neutral.json" \
        --receipt-output "$TEST_DIR/private/receipt.json" \
        --public-output "$TEST_DIR/public/public.json"
}

verify_receipt() {
    "$PYTHON_BIN" "$RECEIPT_TOOL" verify \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral "$TEST_DIR/private/neutral.json" \
        --receipt "$TEST_DIR/private/receipt.json" \
        --public-projection "$TEST_DIR/public/public.json"
}

run_prepare_for() {
    local raw="$1" tag="$2"
    local private_dir="$TEST_DIR/${tag}-private"
    local public_dir="$TEST_DIR/${tag}-public"
    mkdir -m 700 "$private_dir"
    mkdir -m 755 "$public_dir"
    run "$PYTHON_BIN" "$RECEIPT_TOOL" prepare \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$raw" \
        --neutral-output "$private_dir/neutral.json" \
        --receipt-output "$private_dir/receipt.json" \
        --public-output "$public_dir/public.json"
}

mutate_raw_variant() {
    local variant="$1" output="$2"
    "$PYTHON_BIN" - "$TEST_DIR/raw.json" "$output" "$variant" <<'PY'
import copy
import hashlib
import json
from pathlib import Path
import sys

source, output, variant = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
raw = json.loads(source.read_text(encoding="utf-8"))

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")

def sha(payload):
    return hashlib.sha256(payload).hexdigest()

def recompute_snapshot(snapshot):
    entries = sorted(snapshot["entries"], key=lambda item: item["path"].encode("utf-8"))
    snapshot["entries"] = entries
    snapshot["entry_count"] = len(entries)
    snapshot["file_count"] = sum(item["type"] == "file" for item in entries)
    snapshot["directory_count"] = sum(item["type"] == "directory" for item in entries)
    snapshot["total_file_bytes"] = sum(item.get("size_bytes", 0) for item in entries if item["type"] == "file")
    snapshot["tree_sha256"] = sha(canonical(entries))

def rechain():
    previous = "0" * 64
    for record in raw["sequence"]["records"]:
        record["previous_record_sha256"] = previous
        body = dict(record)
        body.pop("record_sha256", None)
        record["record_sha256"] = sha(canonical(body))
        previous = record["record_sha256"]
    raw["sequence"]["head_sha256"] = previous

def stable_handoff(padding):
    document = json.loads(raw["handoff"]["emitted_raw_utf8"])
    document["context"]["summary"]["padding"] = padding
    for _ in range(30):
        context_payload = canonical(document["context"])
        context_chars = len(context_payload)
        context_tokens = (context_chars + 3) // 4
        document["context"]["budget"]["actual_chars"] = context_chars
        document["context"]["budget"]["actual_tokens"] = context_tokens
        payload = canonical(document)
        actual = len(payload)
        tokens = (actual + 3) // 4
        if (
            document["budget"]["actual_chars"] == actual
            and document["budget"]["actual_tokens"] == tokens
            and document["context"]["budget"]["actual_chars"] == len(canonical(document["context"]))
        ):
            return document, payload
        document["budget"]["actual_chars"] = actual
        document["budget"]["actual_tokens"] = tokens
    return document, canonical(document)

def handoff_of_size(target):
    padding = ""
    for _ in range(30):
        document, payload = stable_handoff(padding)
        difference = target - len(payload)
        if difference == 0:
            return payload
        if difference > 0:
            padding += "x" * difference
        else:
            padding = padding[:difference]
    raise SystemExit(f"could not build an exact {target}-byte handoff")

def replace_handoff(payload):
    text = payload.decode("utf-8")
    digest = sha(payload)
    handoff = raw["handoff"]
    for field in ("emitted_raw_utf8", "persisted_raw_utf8"):
        handoff[field] = text
    for field in ("emitted_size_bytes", "persisted_size_bytes"):
        handoff[field] = len(payload)
    for field in ("emitted_sha256", "persisted_sha256"):
        handoff[field] = digest
    terminal = raw["snapshots"]["awm_after_handoff"]
    relative = handoff["persisted_path"][len(raw["paths"]["awm_root"].rstrip("/") + "/") :]
    entry = next(item for item in terminal["entries"] if item["path"] == relative)
    entry["size_bytes"] = len(payload)
    entry["sha256"] = digest
    recompute_snapshot(terminal)
    record = raw["sequence"]["records"][2]
    record["awm_after_sha256"] = terminal["tree_sha256"]
    record["process_result"]["stdout"] = text
    record["stdout_binding"] = {"size_bytes": len(payload), "sha256": digest}
    rechain()

if variant == "awm-unchanged":
    raw["snapshots"]["awm_after_checkpoint"] = copy.deepcopy(raw["snapshots"]["awm_after_init"])
    raw["sequence"]["records"][1]["awm_after_sha256"] = raw["snapshots"]["awm_after_init"]["tree_sha256"]
    raw["sequence"]["records"][2]["awm_before_sha256"] = raw["snapshots"]["awm_after_init"]["tree_sha256"]
    rechain()
elif variant == "workspace-changed":
    changed = copy.deepcopy(raw["snapshots"]["workspace_after"])
    payload = b"unexpected workspace mutation"
    changed["entries"] = [{
        "path": "unexpected.txt", "type": "file", "mode": "0600",
        "size_bytes": len(payload), "sha256": sha(payload),
    }]
    recompute_snapshot(changed)
    raw["snapshots"]["workspace_after"] = changed
    raw["snapshots"]["workspace_unchanged"] = False
elif variant == "handoff-8192":
    replace_handoff(handoff_of_size(8192))
elif variant == "handoff-8193":
    replace_handoff(handoff_of_size(8193))
elif variant == "handoff-multibyte-over":
    document, payload = stable_handoff("💥" * 2200)
    if len(payload) <= 8192 or len(payload.decode("utf-8")) >= len(payload):
        raise SystemExit("multibyte fixture did not cross the byte boundary")
    replace_handoff(payload)
else:
    raise SystemExit(f"unknown mutation variant: {variant}")

output.write_bytes(canonical(raw) + b"\n")
output.chmod(0o600)
PY
}

@test "offline prepare and verify reproduce the treatment investigate receipt with fixed modes" {
    run prepare_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'synthetic-treatment-investigate-awm-mechanism-conformance-only'* ]]
    [[ "$(mode_of "$TEST_DIR/private/neutral.json")" == "400" ]]
    [[ "$(mode_of "$TEST_DIR/private/receipt.json")" == "600" ]]
    [[ "$(mode_of "$TEST_DIR/public/public.json")" == "644" ]]

    run verify_receipt
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'private-bundle-and-public-projection-valid'* ]]
    run "$JQ_BIN" -e '
      .claim_scope == "synthetic-treatment-investigate-awm-mechanism-conformance-only" and
      .binding.arm_mode == "treatment" and .binding.phase == "investigate" and
      .measurements.operation_count == 3 and .measurements.maximum_bytes == 8192 and
      .non_claims.live_agent_sessions == 0 and
      .non_claims.real_provider_inference == "not-run" and
      .scope_boundary.control_transition_receipt == "absent" and
      .scope_boundary.implement_phase_receipt == "absent"
    ' "$TEST_DIR/public/public.json"
    [[ "$status" -eq 0 ]]
}

@test "offline prepare and verify never execute runtime paths" {
    [[ ! -e "$TEST_DIR/marker-invoked" ]]
    run prepare_receipt
    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_DIR/marker-invoked" ]]
    run verify_receipt
    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_DIR/marker-invoked" ]]
}

@test "prepare refuses clobber, symlink, hardlink, and non-private raw inputs" {
    run prepare_receipt
    [[ "$status" -eq 0 ]]
    before="$(sha256_of "$TEST_DIR/private/receipt.json")"
    run prepare_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite"* ]]
    [[ "$(sha256_of "$TEST_DIR/private/receipt.json")" == "$before" ]]

    ln -s "$TEST_DIR/raw.json" "$TEST_DIR/raw-link.json"
    run_prepare_for "$TEST_DIR/raw-link.json" symlink-input
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"regular, non-symlink"* ]]

    ln "$TEST_DIR/raw.json" "$TEST_DIR/raw-hardlink.json"
    run_prepare_for "$TEST_DIR/raw-hardlink.json" hardlink-input
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must not be hard-linked"* ]]
    rm -f -- "$TEST_DIR/raw-hardlink.json"

    cp "$TEST_DIR/raw.json" "$TEST_DIR/raw-public-mode.json"
    chmod 644 "$TEST_DIR/raw-public-mode.json"
    run_prepare_for "$TEST_DIR/raw-public-mode.json" public-mode-input
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"mode must be exactly 0600"* ]]
}

@test "prepare rejects an output symlink without changing its target" {
    private_dir="$TEST_DIR/output-link-private"
    public_dir="$TEST_DIR/output-link-public"
    mkdir -m 700 "$private_dir"
    mkdir -m 755 "$public_dir"
    printf 'preserve-me\n' > "$TEST_DIR/preserved-target"
    ln -s "$TEST_DIR/preserved-target" "$public_dir/public.json"
    run "$PYTHON_BIN" "$RECEIPT_TOOL" prepare \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral-output "$private_dir/neutral.json" \
        --receipt-output "$private_dir/receipt.json" \
        --public-output "$public_dir/public.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite existing public projection"* ]]
    [[ "$(<"$TEST_DIR/preserved-target")" == "preserve-me" ]]
    [[ ! -e "$private_dir/neutral.json" && ! -e "$private_dir/receipt.json" ]]
}

@test "committed control assignment and cross-arm replay cannot become treatment evidence" {
    cp "$TEST_DIR/assignments.json" "$TEST_DIR/control-assignments.json"
    cp "$TEST_DIR/preregistration.json" "$TEST_DIR/control-preregistration.json"
    "$PYTHON_BIN" - "$TEST_DIR/control-assignments.json" "$TEST_DIR/control-preregistration.json" <<'PY'
import hashlib, json, pathlib, sys
assign_path, prereg_path = map(pathlib.Path, sys.argv[1:])
canonical = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
assignments = json.loads(assign_path.read_text())
assignments["assignments"][0]["arms"][0]["mode"] = "control"
assignments["assignments"][0]["arms"][1]["mode"] = "treatment"
assign_path.write_bytes(canonical(assignments) + b"\n")
assign_path.chmod(0o600)
prereg = json.loads(prereg_path.read_text())
prereg["assignment_commitment_sha256"] = hashlib.sha256(canonical(assignments)).hexdigest()
prereg_path.write_bytes(canonical(prereg) + b"\n")
PY
    mkdir -m 700 "$TEST_DIR/control-private"
    mkdir -m 755 "$TEST_DIR/control-public"
    run "$PYTHON_BIN" "$RECEIPT_TOOL" prepare \
        --preregistration "$TEST_DIR/control-preregistration.json" \
        --assignments "$TEST_DIR/control-assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral-output "$TEST_DIR/control-private/neutral.json" \
        --receipt-output "$TEST_DIR/control-private/receipt.json" \
        --public-output "$TEST_DIR/control-public/public.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"committed treatment arm"* ]]

    run prepare_receipt
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" '.binding.opaque_arm_id = "arm-bbbbbbbbbbbbbbbb"' \
        "$TEST_DIR/public/public.json" > "$TEST_DIR/public/replayed.json"
    canonicalize_json_file "$TEST_DIR/public/replayed.json" 0644
    run "$PYTHON_BIN" "$RECEIPT_TOOL" verify \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/audit.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral "$TEST_DIR/private/neutral.json" \
        --receipt "$TEST_DIR/private/receipt.json" \
        --public-projection "$TEST_DIR/public/replayed.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"public projection does not exactly reproduce"* ]]
}

@test "missing reordered failed and tampered operation chains fail closed" {
    "$JQ_BIN" '.sequence.records = .sequence.records[0:2] | .sequence.record_count = 2' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-missing.json"
    "$JQ_BIN" '.sequence.records = [.sequence.records[1], .sequence.records[0], .sequence.records[2]]' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-reordered.json"
    "$JQ_BIN" '.sequence.records[1].process_result.code = 9' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-failed.json"
    "$JQ_BIN" '.sequence.records[2].previous_record_sha256 = ("f" * 64)' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-chain-tampered.json"
    local generated
    for generated in "$TEST_DIR"/raw-{missing,reordered,failed,chain-tampered}.json; do
        canonicalize_json_file "$generated" 0600
    done

    local variant tag
    for variant in missing reordered failed chain-tampered; do
        tag="chain-${variant}"
        run_prepare_for "$TEST_DIR/raw-${variant}.json" "$tag"
        [[ "$status" -ne 0 ]]
    done
}

@test "unchanged AWM state and changed investigate workspace fail closed" {
    mutate_raw_variant awm-unchanged "$TEST_DIR/raw-awm-unchanged.json"
    run_prepare_for "$TEST_DIR/raw-awm-unchanged.json" awm-unchanged
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"AWM state did not change"* ]]

    mutate_raw_variant workspace-changed "$TEST_DIR/raw-workspace-changed.json"
    run_prepare_for "$TEST_DIR/raw-workspace-changed.json" workspace-changed
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"workspace changed"* ]]
}

@test "emitted persisted snapshot and neutral context tampering are rejected" {
    "$JQ_BIN" '.handoff.persisted_raw_utf8 += " "' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-persisted-tamper.json"
    canonicalize_json_file "$TEST_DIR/raw-persisted-tamper.json" 0600
    run_prepare_for "$TEST_DIR/raw-persisted-tamper.json" persisted-tamper
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"byte-identical"* ]]

    "$JQ_BIN" '(.snapshots.awm_after_handoff.entries[] | select(.path | endswith(".json")) | .sha256) = ("0" * 64)' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-terminal-tamper.json"
    canonicalize_json_file "$TEST_DIR/raw-terminal-tamper.json" 0600
    run_prepare_for "$TEST_DIR/raw-terminal-tamper.json" terminal-tamper
    [[ "$status" -ne 0 ]]

    run prepare_receipt
    [[ "$status" -eq 0 ]]
    chmod 600 "$TEST_DIR/private/neutral.json"
    "$JQ_BIN" '.payload.status = "tampered"' \
        "$TEST_DIR/private/neutral.json" > "$TEST_DIR/private/neutral-tampered.json"
    mv "$TEST_DIR/private/neutral-tampered.json" "$TEST_DIR/private/neutral.json"
    canonicalize_json_file "$TEST_DIR/private/neutral.json" 0400
    run verify_receipt
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"neutral envelope does not exactly reproduce"* ]]
}

@test "byte budget accepts 8192 and rejects 8193 and multibyte overflow" {
    mutate_raw_variant handoff-8192 "$TEST_DIR/raw-8192.json"
    run_prepare_for "$TEST_DIR/raw-8192.json" handoff-8192
    [[ "$status" -eq 0 ]]

    mutate_raw_variant handoff-8193 "$TEST_DIR/raw-8193.json"
    run_prepare_for "$TEST_DIR/raw-8193.json" handoff-8193
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"raw emitted handoff size must not exceed 8192"* ]]

    mutate_raw_variant handoff-multibyte-over "$TEST_DIR/raw-multibyte.json"
    run_prepare_for "$TEST_DIR/raw-multibyte.json" handoff-multibyte
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"raw emitted handoff size must not exceed 8192"* ]]
}

@test "wrong key raw record private receipt and public projection fail verification" {
    run prepare_receipt
    [[ "$status" -eq 0 ]]
    cp "$TEST_DIR/private/receipt.json" "$TEST_DIR/private/receipt-good.json"
    cp "$TEST_DIR/public/public.json" "$TEST_DIR/public/public-good.json"
    chmod 600 "$TEST_DIR/private/receipt-good.json"
    chmod 644 "$TEST_DIR/public/public-good.json"

    printf 'different-audit-key-material-at-least-32-bytes\n' > "$TEST_DIR/wrong.key"
    chmod 600 "$TEST_DIR/wrong.key"
    run "$PYTHON_BIN" "$RECEIPT_TOOL" verify \
        --preregistration "$TEST_DIR/preregistration.json" \
        --assignments "$TEST_DIR/assignments.json" \
        --audit-key "$TEST_DIR/wrong.key" \
        --raw-record "$TEST_DIR/raw.json" \
        --neutral "$TEST_DIR/private/neutral.json" \
        --receipt "$TEST_DIR/private/receipt.json" \
        --public-projection "$TEST_DIR/public/public.json"
    [[ "$status" -ne 0 ]]

    "$JQ_BIN" '.runtime_observed.mainframe_version = "10.2.0-tampered"' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-tampered.json"
    canonicalize_json_file "$TEST_DIR/raw-tampered.json" 0600
    mv "$TEST_DIR/raw.json" "$TEST_DIR/raw-good.json"
    mv "$TEST_DIR/raw-tampered.json" "$TEST_DIR/raw.json"
    run verify_receipt
    [[ "$status" -ne 0 ]]
    mv "$TEST_DIR/raw.json" "$TEST_DIR/raw-tampered.json"
    mv "$TEST_DIR/raw-good.json" "$TEST_DIR/raw.json"

    "$JQ_BIN" '.checks.operation_chain_valid = false' \
        "$TEST_DIR/private/receipt-good.json" > "$TEST_DIR/private/receipt.json"
    canonicalize_json_file "$TEST_DIR/private/receipt.json" 0600
    run verify_receipt
    [[ "$status" -ne 0 ]]
    cp "$TEST_DIR/private/receipt-good.json" "$TEST_DIR/private/receipt.json"
    chmod 600 "$TEST_DIR/private/receipt.json"

    "$JQ_BIN" '.measurements.operation_count = 2' \
        "$TEST_DIR/public/public-good.json" > "$TEST_DIR/public/public.json"
    canonicalize_json_file "$TEST_DIR/public/public.json" 0644
    run verify_receipt
    [[ "$status" -ne 0 ]]
}

@test "duplicate and extra JSON keys are rejected in private and public artifacts" {
    "$PYTHON_BIN" - "$TEST_DIR/raw.json" "$TEST_DIR/raw-duplicate.json" <<'PY'
from pathlib import Path
import sys
payload = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(payload.replace(b'{"binding":', b'{"kind":"duplicate","binding":', 1))
Path(sys.argv[2]).chmod(0o600)
PY
    run_prepare_for "$TEST_DIR/raw-duplicate.json" duplicate-raw
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate key"* ]]

    "$JQ_BIN" '.unexpected = true' "$TEST_DIR/raw.json" > "$TEST_DIR/raw-extra.json"
    canonicalize_json_file "$TEST_DIR/raw-extra.json" 0600
    run_prepare_for "$TEST_DIR/raw-extra.json" extra-raw
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid keys"* ]]

    run prepare_receipt
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" '.unexpected = true' "$TEST_DIR/public/public.json" > "$TEST_DIR/public/public-extra.json"
    mv "$TEST_DIR/public/public-extra.json" "$TEST_DIR/public/public.json"
    canonicalize_json_file "$TEST_DIR/public/public.json" 0644
    run verify_receipt
    [[ "$status" -ne 0 ]]
}

@test "raw traversal paths are rejected" {
    "$JQ_BIN" '.handoff.persisted_path = (.paths.awm_root + "/sessions/../escape.json")' \
        "$TEST_DIR/raw.json" > "$TEST_DIR/raw-traversal.json"
    canonicalize_json_file "$TEST_DIR/raw-traversal.json" 0600
    run_prepare_for "$TEST_DIR/raw-traversal.json" traversal
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"normalized absolute POSIX path"* ]]
}

@test "public projection excludes paths AWM identities and checkpoint content" {
    run prepare_receipt
    [[ "$status" -eq 0 ]]
    public_file="$TEST_DIR/public/public.json"
    mapfile -t sensitive < <("$JQ_BIN" -r '
      .paths[] , .environment.isolated_paths[], .handoff.session_id,
      .handoff.handoff_id, .handoff.persisted_path, .fixture.checkpoint_value,
      .request.path
    ' "$TEST_DIR/raw.json")
    local value
    for value in "${sensitive[@]}"; do
        [[ -n "$value" ]]
        run grep -F -- "$value" "$public_file"
        [[ "$status" -eq 1 ]]
    done
    run "$JQ_BIN" -e '
      ([paths(scalars) as $p | getpath($p) |
        select(type == "string" and
          (startswith("/") or startswith("~") or test("^[A-Za-z]:[\\\\/]")))] | length) == 0 and
      ([paths(objects) as $p | getpath($p) | keys[] |
        select(. == "path" or . == "paths" or . == "stdout" or . == "stderr" or
          . == "args" or . == "environment" or . == "session_id" or
          . == "handoff_id" or . == "emitted_raw_utf8" or
          . == "persisted_raw_utf8" or . == "checkpoint_value")] | length) == 0
    ' "$public_file"
    [[ "$status" -eq 0 ]]
}

@test "real certified Pi and exact archive produce a verifiable receipt when available" {
    archive="${MAINFRAME_AWM_RECEIPT_ARCHIVE:-$PROJECT_ROOT/dist/mainframe-10.2.0.tar.gz}"
    pi_bin="${MAINFRAME_PI_BIN:-/opt/homebrew/bin/pi}"
    node_bin="${MAINFRAME_NODE_BIN:-/opt/homebrew/bin/node}"
    [[ -f "$archive" && ! -L "$archive" ]] || skip "current candidate archive is unavailable"
    [[ -x "$pi_bin" && -x "$node_bin" ]] || skip "current Pi and Node executables are unavailable"
    tar -tzf "$archive" | grep -Fx 'evals/agent-impact/runners/pi-awm-transition-driver.mjs' >/dev/null || \
        skip "candidate archive predates the Pi AWM transition driver"

    integration="$TEST_DIR/integration"
    mkdir -m 700 "$integration"
    cp "$TEST_DIR/preregistration.json" "$integration/preregistration.json"
    cp "$TEST_DIR/assignments.json" "$integration/assignments.json"
    chmod 600 "$integration/assignments.json"
    run "$PYTHON_BIN" - "$FIXTURE_RUNNER" "$archive" "$pi_bin" "$node_bin" \
        "$integration/preregistration.json" "$integration/assignments.json" <<'PY'
import hashlib
import importlib.util
import json
import pathlib
import tempfile
import sys

support_path, archive_value, pi_value, node_value, prereg_value, assignments_value = sys.argv[1:]
spec = importlib.util.spec_from_file_location("awm_fixture_support", support_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
archive = pathlib.Path(archive_value).resolve(strict=True)
with tempfile.TemporaryDirectory(prefix="mainframe-awm-receipt-preflight-") as temporary:
    root = pathlib.Path(temporary) / "install"
    root.mkdir(mode=0o700)
    module.safe_extract(archive, root)
    installed = module.package_tree_sha256(root)
    archive_sha = module.sha256_file(archive, "release archive")
    module.runtime_bindings(root, archive_sha, installed, pathlib.Path(pi_value), pathlib.Path(node_value))
prereg_path = pathlib.Path(prereg_value)
assignments_path = pathlib.Path(assignments_value)
prereg = json.loads(prereg_path.read_text(encoding="utf-8"))
assignments = json.loads(assignments_path.read_text(encoding="utf-8"))
release = prereg["bindings"]["mainframe_release"]
sidecar = pathlib.Path(str(archive) + ".sha256")
if not sidecar.is_file():
    raise SystemExit("candidate checksum sidecar is unavailable")
release["archive_path"] = archive.name
release["archive_mode"] = f"{archive.stat().st_mode & 0o7777:04o}"
release["archive_sha256"] = archive_sha
release["checksum_sidecar_path"] = sidecar.name
release["checksum_sidecar_mode"] = f"{sidecar.stat().st_mode & 0o7777:04o}"
release["checksum_sidecar_sha256"] = hashlib.sha256(sidecar.read_bytes()).hexdigest()
release["installed_tree_sha256"] = installed
randomization = hashlib.sha256(module.canonical_bytes({
    "domain": "mainframe-agent-impact-live-v2-randomization-context",
    "study_id": prereg["study_id"],
    "bindings": prereg["bindings"],
})).hexdigest()
prereg["randomization_context_sha256"] = randomization
assignments["randomization_context_sha256"] = randomization
assignment_commitment = hashlib.sha256(module.canonical_bytes(assignments)).hexdigest()
prereg["assignment_commitment_sha256"] = assignment_commitment
payload = json.dumps(prereg, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
prereg_path.write_bytes(payload)
assignments_path.write_bytes(module.canonical_bytes(assignments) + b"\n")
assignments_path.chmod(0o600)
print(installed)
PY
    if [[ "$status" -ne 0 ]]; then
        skip "current Pi/Node/archive are not a certified matching set: $output"
    fi

    run "$PYTHON_BIN" "$FIXTURE_RUNNER" \
        --preregistration "$integration/preregistration.json" \
        --assignments "$integration/assignments.json" \
        --pair-id pair-1111111111111111 \
        --opaque-arm-id arm-aaaaaaaaaaaaaaaa \
        --archive "$archive" \
        --pi-bin "$pi_bin" \
        --node-bin "$node_bin" \
        --output "$integration/raw.json"
    [[ "$status" -eq 0 ]]
    printf 'integration-audit-key-material-at-least-32-bytes\n' > "$integration/audit.key"
    chmod 600 "$integration/audit.key"
    mkdir -m 700 "$integration/private"
    mkdir -m 755 "$integration/public"
    run "$PYTHON_BIN" "$RECEIPT_TOOL" prepare \
        --preregistration "$integration/preregistration.json" \
        --assignments "$integration/assignments.json" \
        --audit-key "$integration/audit.key" \
        --raw-record "$integration/raw.json" \
        --neutral-output "$integration/private/neutral.json" \
        --receipt-output "$integration/private/receipt.json" \
        --public-output "$integration/public/public.json"
    [[ "$status" -eq 0 ]]
    run "$PYTHON_BIN" "$RECEIPT_TOOL" verify \
        --preregistration "$integration/preregistration.json" \
        --assignments "$integration/assignments.json" \
        --audit-key "$integration/audit.key" \
        --raw-record "$integration/raw.json" \
        --neutral "$integration/private/neutral.json" \
        --receipt "$integration/private/receipt.json" \
        --public-projection "$integration/public/public.json"
    [[ "$status" -eq 0 ]]
    [[ "$(mode_of "$integration/raw.json")" == "600" ]]
    [[ "$(mode_of "$integration/private/neutral.json")" == "400" ]]
    [[ "$(mode_of "$integration/private/receipt.json")" == "600" ]]
    [[ "$(mode_of "$integration/public/public.json")" == "644" ]]
    run "$JQ_BIN" -e '
      .runtime_observed.pi_package == "@earendil-works/pi-coding-agent" and
      .runtime_observed.pi_version == "0.84.1" and
      (.runtime_observed.registered_tools | length) == 7 and
      .runtime_observed.loaded_mainframe_awm == true and
      .runtime_observed.provider_adapter_loaded == false and
      .runtime_observed.provider_inference_requests == 0 and
      .sequence.record_count == 3 and
      .snapshots.installed_unchanged == true and
      .snapshots.workspace_unchanged == true and
      .handoff.emitted_equals_persisted == true
    ' "$integration/raw.json"
    [[ "$status" -eq 0 ]]
    run "$JQ_BIN" -e '
      .runtime.pi_package == "@earendil-works/pi-coding-agent" and
      .runtime.pi_version == "0.84.1" and
      .measurements.operation_count == 3 and
      .checks.bound_driver_declares_provider_requests_zero == true and
      .scope_boundary.live_study_eligibility ==
        "ineligible-preregistration-v2-does-not-prebind-receipt-runtime" and
      .non_claims.real_provider_inference == "not-run" and
      .non_claims.live_agent_sessions == 0
    ' "$integration/public/public.json"
    [[ "$status" -eq 0 ]]
}

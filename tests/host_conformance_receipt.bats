#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    VALIDATOR="$PROJECT_ROOT/scripts/validate-host-conformance-receipt.py"
    SCHEMA="$PROJECT_ROOT/config/host-conformance-receipt.schema.json"
    REGISTRY="$PROJECT_ROOT/config/host-capabilities.json"
    RECEIPT="$BATS_TEST_TMPDIR/host-conformance-receipt.json"
    make_receipt cursor
}

make_receipt() {
    local host_id="$1"
    python3 - "$PROJECT_ROOT" "$SCHEMA" "$REGISTRY" "$RECEIPT" "$host_id" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
schema_path = Path(sys.argv[2])
registry_path = Path(sys.argv[3])
output = Path(sys.argv[4])
host_id = sys.argv[5]
registry_bytes = registry_path.read_bytes()
schema_bytes = schema_path.read_bytes()
registry = json.loads(registry_bytes)
host = registry["hosts"][host_id]
adapter_path = host["static_adapter"]
adapter_bytes = (root / adapter_path).read_bytes()

def sha256(raw):
    return hashlib.sha256(raw).hexdigest()

def route_claim(tool_class):
    return {
        "evidence_level": "unverified",
        "interception": "none",
        "mechanism": None,
        "route": None,
        "fail_behavior": "not-intercepted",
        "artifacts": [],
        "observed_at": None,
        "release": None,
        "limitations": [f"No qualifying {tool_class} interception evidence."],
    }

def capability_claim(capability):
    return {
        "evidence_level": "unverified",
        "mechanism": None,
        "artifacts": [],
        "observed_at": None,
        "release": None,
        "limitations": [f"No qualifying {capability} evidence."],
    }

receipt = {
    "schema_version": 1,
    "kind": "mainframe-host-conformance-receipt",
    "receipt_id": f"hcr-{host_id.replace('-', '_')}-fixture",
    "issued_at": "2026-08-20T12:00:00Z",
    "contract": {
        "registry": "config/host-capabilities.json",
        "registry_schema_version": registry["schema_version"],
        "registry_contract_version": registry["contract_version"],
        "registry_sha256": sha256(registry_bytes),
        "receipt_schema": "config/host-conformance-receipt.schema.json",
        "receipt_schema_sha256": sha256(schema_bytes),
    },
    "subject": {
        "host_id": host_id,
        "host_version": None,
        "platform": "Darwin-arm64-none",
        "mainframe_version": (root / "VERSION").read_text(encoding="utf-8").strip(),
        "payload_sha256": sha256((root / "SHA256SUMS").read_bytes()),
        "payload_status": "candidate",
        "adapter_path": adapter_path,
        "adapter_sha256": sha256(adapter_bytes),
    },
    "instruction": {
        "evidence_level": "instructions",
        "artifact": {
            "kind": "instruction",
            "path": adapter_path,
            "sha256": sha256(adapter_bytes),
            "result": "pass",
        },
        "limitations": ["Static instructions do not prove runtime interception."],
    },
    "tool_classes": {
        tool_class: route_claim(tool_class)
        for tool_class in registry["tool_classes"]
    },
    "capabilities": {
        capability: capability_claim(capability)
        for capability in ("approval", "cancel", "progress", "memory", "audit")
    },
    "verdict": "pass",
    "limitations": ["All runtime routes remain unverified in this fixture."],
}
output.write_text(
    json.dumps(receipt, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
}

mutate_receipt() {
    local expression="$1"
    python3 - "$RECEIPT" "$expression" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
receipt = json.loads(path.read_text(encoding="utf-8"))
exec(sys.argv[2], {"receipt": receipt})
path.write_text(
    json.dumps(receipt, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
}

artifact_json() {
    local kind="$1" path="$2"
    python3 - "$PROJECT_ROOT" "$kind" "$path" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
kind = sys.argv[2]
path = sys.argv[3]
print(json.dumps({
    "kind": kind,
    "path": path,
    "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest(),
    "result": "pass",
}, separators=(",", ":")))
PY
}

validate_receipt() {
    run python3 "$VALIDATOR" \
        --repo-root "$PROJECT_ROOT" \
        --schema "$SCHEMA" \
        --registry "$REGISTRY" \
        --receipt "$RECEIPT"
}

@test "conservative receipt validates and every object boundary is closed" {
    validate_receipt
    [ "$status" -eq 0 ]
    [ "$output" = "host conformance receipt valid" ]

    mutate_receipt 'receipt["unexpected"] = True'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected keys"* ]]

    make_receipt cursor
    mutate_receipt 'receipt["tool_classes"]["shell"]["unexpected"] = True'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected keys"* ]]
}

@test "registry and schema digest drift fail closed" {
    mutate_receipt 'receipt["contract"]["registry_sha256"] = "0" * 64'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"registry_sha256 does not bind"* ]]

    make_receipt cursor
    mutate_receipt 'receipt["contract"]["receipt_schema_sha256"] = "0" * 64'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"receipt_schema_sha256 does not bind"* ]]

    make_receipt cursor
    mutate_receipt 'receipt["subject"]["payload_sha256"] = "0" * 64'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"payload_sha256 does not bind SHA256SUMS"* ]]

    make_receipt cursor
    mutate_receipt 'receipt["subject"]["payload_status"] = "released"'
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"released payload status requires a validated released claim"* ]]
}

@test "schema registry and repository root must be their canonical non-symlink paths" {
    local copied_schema copied_registry linked_root
    copied_schema="$BATS_TEST_TMPDIR/copied-schema.json"
    copied_registry="$BATS_TEST_TMPDIR/copied-registry.json"
    linked_root="$BATS_TEST_TMPDIR/root-link"
    cp "$SCHEMA" "$copied_schema"
    cp "$REGISTRY" "$copied_registry"
    ln -s "$PROJECT_ROOT" "$linked_root"

    run python3 "$VALIDATOR" \
        --repo-root "$PROJECT_ROOT" \
        --schema "$copied_schema" \
        --registry "$REGISTRY" \
        --receipt "$RECEIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"schema must be the canonical repository path"* ]]

    run python3 "$VALIDATOR" \
        --repo-root "$PROJECT_ROOT" \
        --schema "$SCHEMA" \
        --registry "$copied_registry" \
        --receipt "$RECEIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"registry must be the canonical repository path"* ]]

    run python3 "$VALIDATOR" \
        --repo-root "$linked_root" \
        --schema "$SCHEMA" \
        --registry "$REGISTRY" \
        --receipt "$RECEIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-root must be an exact non-symbolic-link path"* ]]
}

@test "capability rank inflation above the registry claim fails closed" {
    local artifact
    make_receipt codex
    artifact="$(artifact_json deterministic-test tests/agent_gateway.bats)"
    mutate_receipt "receipt['capabilities']['approval'].update({'evidence_level':'enforced','mechanism':'fictional approval proof','artifacts':[$artifact],'limitations':[]})"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"approval evidence enforced exceeds registry level unverified"* ]]
}

@test "instruction-only hosts cannot promote a route to configured" {
    local artifact
    artifact="$(artifact_json configuration config/host-capabilities.json)"
    mutate_receipt "receipt['tool_classes']['shell'].update({'evidence_level':'configured','interception':'declared','mechanism':'fictional hook','route':'PreToolUse','fail_behavior':'fail-closed','artifacts':[$artifact],'limitations':[]})"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"evidence configured exceeds platform level instructions"* ]]
}

@test "fail-open routes are capped at instructions evidence" {
    local artifact
    make_receipt copilot
    artifact="$(artifact_json deterministic-test tests/agent_gateway.bats)"
    mutate_receipt "receipt['tool_classes']['shell'].update({'evidence_level':'enforced','interception':'observed','mechanism':'preToolUse hook','route':'preToolUse hook timeout','fail_behavior':'fail-open','artifacts':[$artifact],'limitations':[]})"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"fail-open route is capped at instructions"* ]]
}

@test "gateway pass-through classes remain unverified without interception" {
    local artifact tool_class
    artifact="$(artifact_json deterministic-test tests/agent_gateway.bats)"
    for tool_class in file-read file-write network process mcp-tool host-control; do
        make_receipt codex
        mutate_receipt "receipt['tool_classes']['$tool_class'].update({'evidence_level':'enforced','interception':'observed','mechanism':'agent gateway','route':'PreToolUse','fail_behavior':'fail-closed','artifacts':[$artifact],'limitations':[]})"
        validate_receipt
        [ "$status" -ne 0 ]
        [[ "$output" == *"registry does not declare $tool_class interception"* ]]
    done

    grep -Fq 'rule=non-shell-tool' "$PROJECT_ROOT/hooks/agent-gateway.sh"
    grep -Fq 'decision=allow' "$PROJECT_ROOT/hooks/agent-gateway.sh"
}

@test "released evidence requires attestation and remains blocked by unreleased registry state" {
    local live_artifact release_artifact
    make_receipt pi
    live_artifact="$(artifact_json live-transcript tests/pi_cell_evidence.bats)"
    mutate_receipt "receipt['subject']['host_version']='0.84.2'; receipt['tool_classes']['shell'].update({'evidence_level':'released','interception':'observed','mechanism':'extension tool-call and user-bash hooks','route':'extension tool-call and user-bash hooks','fail_behavior':'fail-closed','artifacts':[$live_artifact],'observed_at':'2026-08-20T12:00:00Z','limitations':[]})"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"released evidence requires a release binding"* ]]

    release_artifact="$(artifact_json release-attestation tests/fixtures/host-conformance-release-attestation-v1.json)"
    mutate_receipt "receipt['subject']['payload_status']='released'; receipt['tool_classes']['shell']['artifacts'].append($release_artifact); receipt['tool_classes']['shell']['release']={'version':'10.2.0','archive_sha256':'a'*64,'attestation_uri':'https://example.invalid/mainframe/attestation.json'}"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"registry platform is not released"* ]]

    make_receipt pi
    live_artifact="$(artifact_json live-transcript tests/pi_cell_evidence.bats)"
    release_artifact="$(artifact_json release-attestation config/host-conformance-receipt.schema.json)"
    mutate_receipt "receipt['subject'].update({'host_version':'0.84.2','payload_status':'released'}); receipt['tool_classes']['shell'].update({'evidence_level':'released','interception':'observed','mechanism':'extension tool-call and user-bash hooks','route':'extension tool-call and user-bash hooks','fail_behavior':'fail-closed','artifacts':[$live_artifact,$release_artifact],'observed_at':'2026-08-20T12:00:00Z','release':{'version':'10.2.0','archive_sha256':'a'*64,'attestation_uri':'https://example.invalid/mainframe/attestation.json'},'limitations':[]})"
    validate_receipt
    [ "$status" -ne 0 ]
    [[ "$output" == *"release-attestation content does not bind"* ]]
}

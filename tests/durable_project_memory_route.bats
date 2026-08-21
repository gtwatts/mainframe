#!/usr/bin/env bats
# Phase 7D/7F public Bash/project-memory integration contract. All reviewed
# project mutations and reads use the one durable kernel route.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    PROJECT_DIR="$TEST_ROOT/project"
    STATE_HOME="$TEST_ROOT/state"
    TEST_HOME="$TEST_ROOT/caller-home"
    POISON_AWM_ROOT="$TEST_ROOT/ambient-awm-must-not-be-used"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"

    mkdir -p "$PROJECT_DIR" "$TEST_HOME"
    mkdir -m 0700 "$STATE_HOME"
    export PROJECT_ROOT TEST_ROOT PROJECT_DIR STATE_HOME TEST_HOME
    export POISON_AWM_ROOT MAINFRAME_BIN BASH_BIN
}

project_memory() {
    env \
        HOME="$TEST_HOME" \
        XDG_STATE_HOME="$STATE_HOME" \
        AWM_ROOT="$POISON_AWM_ROOT" \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_BASH="$BASH_BIN" \
        "$MAINFRAME_BIN" awm project "$@"
}

control_memory() {
    local tool="$1" input="$2" correlation="$3"
    local format="${4:-control-plane-json-v1}"
    builtin printf '%s' "$input" | (
        cd -- "$PROJECT_DIR" || exit 1
        exec env -i \
            USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
            HOME="$TEST_HOME" XDG_STATE_HOME="$STATE_HOME" \
            PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C TMPDIR=/tmp \
            "$PROJECT_ROOT/control_plane/mainframe-control-plane" \
            project-memory-invoke --tool-id "$tool" --input-json - \
            --client-correlation-id "$correlation" --format "$format"
    )
}

ledger_path() {
    printf '%s/mainframe/control-plane.jsonl' "$STATE_HOME"
}

ensure_project() {
    project_memory ensure --project "$PROJECT_DIR" --name phase-7
}

find_project_mapping() {
    find "$STATE_HOME" -type f -path '*/awm/projects/*.json' -print -quit 2>/dev/null
}

install_capture_runtime() {
    CAPTURE_ROOT="$TEST_ROOT/capture-runtime"
    mkdir -p "$CAPTURE_ROOT/bin" "$CAPTURE_ROOT/control_plane"
    cp "$PROJECT_ROOT/bin/mainframe" "$CAPTURE_ROOT/bin/mainframe"
    cp -R "$PROJECT_ROOT/lib" "$CAPTURE_ROOT/lib"
    cp -R "$PROJECT_ROOT/control_plane/mainframe_control_plane" \
        "$CAPTURE_ROOT/control_plane/mainframe_control_plane"
    cp "$PROJECT_ROOT/tests/fixtures/project_memory_capture_control_plane.py" \
        "$CAPTURE_ROOT/control_plane/mainframe-control-plane"
    chmod 0755 "$CAPTURE_ROOT/bin/mainframe" \
        "$CAPTURE_ROOT/control_plane/mainframe-control-plane"
    export CAPTURE_ROOT
}

@test "project memory: hidden observer and executor own exact argv and FDs 196 197 198" {
    local bridge="$PROJECT_ROOT/lib/durable_awm.sh"

    [[ -f "$bridge" && ! -L "$bridge" ]]
    run python3 - "$bridge" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "__kernel-project-memory-observer-v1",
    "project-memory-observation-json-v1",
    "__kernel-project-memory-executor-v1",
    "project-memory-executor-json-v1",
    "--caller",
    "control-plane",
):
    assert token in source, token
for descriptor in (196, 197, 198):
    assert re.search(rf"(?:<&|>&|/dev/fd/){descriptor}(?:\D|$)", source), descriptor
assert "bash -c" not in source
assert not re.search(r"(^|[;\s])eval([;\s]|$)", source)
print("hidden_project_memory_boundary=closed")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hidden_project_memory_boundary=closed" ]]
}

@test "project memory: public ensure sends canonical stdin through exact fixed kernel argv" {
    install_capture_runtime

    run env \
        HOME="$TEST_HOME" \
        XDG_STATE_HOME="$STATE_HOME" \
        AWM_ROOT="$POISON_AWM_ROOT" \
        MAINFRAME_ROOT="$CAPTURE_ROOT" \
        MAINFRAME_BASH="$BASH_BIN" \
        "$CAPTURE_ROOT/bin/mainframe" awm project ensure \
            --project "$PROJECT_DIR" --name phase-7

    [[ "$status" -eq 0 ]]
    [[ "$output" == "0123456789ab" ]]
    run python3 - "$STATE_HOME/project-memory-capture.json" "$PROJECT_DIR" <<'PY'
import json
import os
import pathlib
import re
import sys

capture = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
argv = capture["argv"]
assert argv[:5] == [
    "project-memory-invoke",
    "--tool-id",
    "mainframe.project_memory.ensure.v1",
    "--input-json",
    "-",
]
assert argv[5] == "--client-correlation-id"
assert argv[6].startswith("client-")
assert 1 <= len(argv[6]) <= 128
assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", argv[6])
assert argv[7:] == ["--format", "awm-compatible-v1"]
assert capture["stdin_utf8"] == '{"name":"phase-7"}'
assert capture["cwd"] == os.path.realpath(sys.argv[2])
assert "AWM_ROOT" not in capture["environment_keys"]
assert "MAINFRAME_ROOT" not in capture["environment_keys"]
print("public_project_memory_route=exact")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "public_project_memory_route=exact" ]]
    [[ ! -e "$POISON_AWM_ROOT" ]]
}

@test "project memory: all six mutations preserve compatible public outputs" {
    local sid handoff

    run ensure_project
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{12}$ ]]
    sid="$output"

    run project_memory checkpoint --project "$PROJECT_DIR" phase build \
        --importance high --tags phase7,durable --ttl 60
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    run project_memory discovery --project "$PROJECT_DIR" "reviewed discovery" \
        --importance critical --tags phase7
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    run project_memory progress --project "$PROJECT_DIR" migration 1/2 "halfway"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    run project_memory handoff prepare --project "$PROJECT_DIR" reviewer \
        --tokens 512 --format json
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
    handoff="$output"
    run python3 - "$handoff" <<'PY'
import json
import sys
assert isinstance(json.loads(sys.argv[1]), dict)
PY
    [[ "$status" -eq 0 ]]

    run project_memory close --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    [[ ! -e "$POISON_AWM_ROOT" ]]
    [[ -z "$(find "$TEST_HOME" -mindepth 1 -print -quit)" ]]
    [[ "$sid" =~ ^[0-9a-f]{12}$ ]]
}

@test "project memory: ledger provenance is complete and excludes raw checkpoint bytes" {
    local sid secret_key="private-phase-key-4b91"
    local secret_value="private-phase-value-90ad" ledger

    sid="$(ensure_project)"
    project_memory checkpoint --project "$PROJECT_DIR" \
        "$secret_key" "$secret_value" --importance high --tags private --ttl 60
    ledger="$(ledger_path)"
    [[ -f "$ledger" ]]
    ! grep -Fq "$secret_key" "$ledger"
    ! grep -Fq "$secret_value" "$ledger"

    run python3 - "$ledger" <<'PY'
import json
import pathlib
import re
import sys

events = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
receipts = []
records = []
def visit(value):
    if isinstance(value, dict):
        if value.get("tool") == "mainframe.project_memory.checkpoint.v1" and \
                value.get("trust_label") == "kernel_bound":
            if "idempotency_key" in value:
                receipts.append(value)
            if "memory_op_id" in value and "policy_authority" in value:
                records.append(value)
        for nested in value.values():
            visit(nested)
    elif isinstance(value, list):
        for nested in value:
            visit(nested)
for event in events:
    visit(event)
assert len(receipts) == 1
receipt = receipts[0]
patterns = {
    "memory_op_id": r"memory-op-[0-9a-f]{32}",
    "run_id": r"run-[0-9a-f]{32}",
    "call_id": r"call-[0-9a-f]{32}",
    "decision_id": r"decision-[0-9a-f]{32}",
    "evidence_id": r"evidence-[0-9a-f]{32}",
    "input_digest": r"[0-9a-f]{64}",
}
for field, pattern in patterns.items():
    assert re.fullmatch(pattern, receipt[field]), (field, receipt.get(field))
assert receipt["idempotency_key"] == receipt["memory_op_id"]
assert receipt["authoritative"] is False
assert receipt["value_bytes"] == len("private-phase-value-90ad".encode())
assert records
record = records[-1]
for field in patterns:
    assert record[field] == receipt[field], field
assert record["policy_authority"] == "policy-engine:fixed-project-memory-v1"
assert record["authoritative"] is False
print("project_memory_provenance=complete_metadata_only")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_provenance=complete_metadata_only" ]]
    [[ "$sid" =~ ^[0-9a-f]{12}$ ]]
}

@test "project memory: mapping lock and receipts remain idempotent" {
    local first second mapping ledger

    first="$(ensure_project)"
    second="$(ensure_project)"
    [[ "$first" == "$second" ]]
    [[ "$first" =~ ^[0-9a-f]{12}$ ]]
    mapping="$(find_project_mapping)"
    [[ -f "$mapping" && ! -L "$mapping" ]]
    [[ "$(find "$STATE_HOME" -type f -path '*/awm/projects/*.json' | wc -l | tr -d ' ')" == 1 ]]
    ledger="$(ledger_path)"

    run python3 - "$ledger" "$first" <<'PY'
import json
import pathlib
import sys

events = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
receipts = []
def visit(value):
    if isinstance(value, dict):
        if value.get("tool") == "mainframe.project_memory.ensure.v1" and \
                "idempotency_key" in value:
            receipts.append(value)
        for nested in value.values(): visit(nested)
    elif isinstance(value, list):
        for nested in value: visit(nested)
for event in events: visit(event)
assert len(receipts) == 2
assert all(item["idempotency_key"] == item["memory_op_id"] for item in receipts)
assert all(item["session_id"] == sys.argv[2] for item in receipts)
assert receipts[0]["memory_op_id"] != receipts[1]["memory_op_id"]
print("project_memory_mapping=one_session_receipts_idempotent")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_mapping=one_session_receipts_idempotent" ]]
}

@test "project memory: concurrent close and checkpoint cannot both commit stale state" {
    local sid checkpoint_rc close_rc mapping manifest
    local checkpoint_out="$TEST_ROOT/checkpoint.out"
    local close_out="$TEST_ROOT/close.out"

    sid="$(ensure_project)"
    (
        if project_memory checkpoint --project "$PROJECT_DIR" concurrent value \
            --importance normal --tags race --ttl 0 >"$checkpoint_out" 2>&1; then
            printf '0' >"$TEST_ROOT/checkpoint.rc"
        else
            printf '%s' "$?" >"$TEST_ROOT/checkpoint.rc"
        fi
    ) &
    checkpoint_pid=$!
    (
        if project_memory close --project "$PROJECT_DIR" >"$close_out" 2>&1; then
            printf '0' >"$TEST_ROOT/close.rc"
        else
            printf '%s' "$?" >"$TEST_ROOT/close.rc"
        fi
    ) &
    close_pid=$!
    wait "$checkpoint_pid"
    wait "$close_pid"
    checkpoint_rc="$(<"$TEST_ROOT/checkpoint.rc")"
    close_rc="$(<"$TEST_ROOT/close.rc")"
    [[ "$checkpoint_rc:$close_rc" == "0:1" || \
       "$checkpoint_rc:$close_rc" == "0:75" || \
       "$checkpoint_rc:$close_rc" == "1:0" || \
       "$checkpoint_rc:$close_rc" == "75:0" ]]

    mapping="$(find_project_mapping)"
    [[ -f "$mapping" && ! -L "$mapping" ]]
    manifest="$(find "$STATE_HOME" -type f -path "*/sessions/projects/$sid/manifest.json" -print -quit)"
    run python3 - "$mapping" "$manifest" "$sid" <<'PY'
import json
import pathlib
import sys
mapping = json.loads(pathlib.Path(sys.argv[1]).read_text())
manifest = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert mapping["session_id"] == sys.argv[3]
assert manifest["session_id"] == sys.argv[3]
assert manifest["status"] in ("active", "completed")
print("project_memory_concurrency=cas_closed")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_concurrency=cas_closed" ]]
}

@test "project memory: mapping and receipt tamper fail closed without repair" {
    local sid mapping ledger before
    sid="$(ensure_project)"
    mapping="$(find_project_mapping)"
    [[ -f "$mapping" ]]
    printf '{"tampered":true}\n' >"$mapping"

    run project_memory checkpoint --project "$PROJECT_DIR" guarded never-write \
        --importance high --tags tamper --ttl 0
    [[ "$status" -ne 0 ]]
    [[ "$(<"$mapping")" == '{"tampered":true}' ]]

    STATE_HOME="$TEST_ROOT/receipt-state"
    mkdir -m 0700 "$STATE_HOME"
    export STATE_HOME
    sid="$(ensure_project)"
    ledger="$(ledger_path)"
    python3 - "$ledger" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
assert "kernel_bound" in content
path.write_text(content.replace("kernel_bound", "forged_bound", 1), encoding="utf-8")
PY
    before="$(<"$ledger")"
    run ensure_project
    [[ "$status" -ne 0 ]]
    [[ "$(<"$ledger")" == "$before" ]]
    [[ "$sid" =~ ^[0-9a-f]{12}$ ]]
}

@test "project memory: worker SIGKILL liveness EOF leaves no Bash adapter group" {
    local bridge="$PROJECT_ROOT/lib/durable_awm.sh"
    [[ -f "$bridge" && ! -L "$bridge" ]]

    run python3 - "$BASH_BIN" "$bridge" <<'PY'
import os
import signal
import subprocess
import sys
import time

bash, bridge = sys.argv[1:]
read_fd, write_fd = os.pipe()
saved = None
try:
    try:
        saved = os.dup(198)
    except OSError:
        saved = None
    os.dup2(read_fd, 198, inheritable=True)
    process = subprocess.Popen(
        [
            bash, "--noprofile", "--norc", "-p", "-c",
            'set -e; source "$1"; '
            '_mainframe_durable_awm_start_liveness_guardian 198; '
            'exec 198<&-; exec /bin/sleep 30',
            "bash", bridge,
        ],
        close_fds=True,
        pass_fds=(198,),
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
finally:
    os.close(read_fd)
    if saved is None:
        os.close(198)
    else:
        os.dup2(saved, 198)
        os.close(saved)

time.sleep(0.2)
assert process.poll() is None, "adapter group did not reach liveness wait"
# The Python worker alone owns the write end. Its SIGKILL is represented by
# this close: FD198 reaches EOF without any caller-selected PID or descriptor.
os.close(write_fd)
deadline = time.time() + 3.0
while process.poll() is None and time.time() < deadline:
    time.sleep(0.02)
assert process.poll() is not None, "adapter group survived liveness EOF"
group_deadline = time.time() + 2.0
while time.time() < group_deadline:
    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        break
    time.sleep(0.02)
else:
    raise AssertionError("adapter process group remains alive")
print("project_memory_liveness=no_orphan")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_liveness=no_orphan" ]]
}

@test "project memory: setup and onboard succeed without authority claims" {
    run env \
        HOME="$TEST_HOME" XDG_STATE_HOME="$STATE_HOME" AWM_ROOT="$POISON_AWM_ROOT" \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_BASH="$BASH_BIN" \
        "$MAINFRAME_BIN" setup --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Project AWM:"* ]]
    [[ "$output" == *"non-authoritative"* || "$output" == *"non-authorizing"* ]]

    run env \
        HOME="$TEST_HOME" XDG_STATE_HOME="$STATE_HOME" AWM_ROOT="$POISON_AWM_ROOT" \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_BASH="$BASH_BIN" \
        "$MAINFRAME_BIN" onboard --host codex --project "$PROJECT_DIR" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"non-authoritative"* || "$output" == *"non-authorizing"* ]]
    [[ "$output" != *"authoritative=true"* ]]
    [[ ! -e "$POISON_AWM_ROOT" ]]
}

@test "project memory: all six reads use the durable route after a reviewed write" {
    local sid ledger query_secret='find-query-and-output-secret-5a21'
    sid="$(ensure_project)"
    project_memory checkpoint --project "$PROJECT_DIR" read-key "$query_secret" \
        --importance normal --tags read --ttl 0

    run project_memory session --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$sid" ]]
    run project_memory status --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"status":"mapped"'* ]]
    [[ "$output" == *'"session_id":"'"$sid"'"'* ]]
    run project_memory get --project "$PROJECT_DIR" read-key
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$query_secret" ]]
    run project_memory summary --project "$PROJECT_DIR" --tokens 2048
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"session_id":"'"$sid"'"'* ]]
    run project_memory context --project "$PROJECT_DIR" "$query_secret" \
        --tokens 2048 --format json --include checkpoints
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$query_secret"* ]]
    run project_memory find --project "$PROJECT_DIR" "$query_secret" --kind checkpoint --limit 5
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$query_secret"* ]]
    ledger="$(ledger_path)"
    ! grep -Fq "$query_secret" "$ledger"
    [[ "$sid" =~ ^[0-9a-f]{12}$ ]]
}

@test "project memory reads: result bytes are one-consumer and replay is metadata only" {
    local sid secret='read-plane-secret-91c7' first second ledger
    sid="$(ensure_project)"
    project_memory checkpoint --project "$PROJECT_DIR" replay-key "$secret" \
        --importance high --tags replay --ttl 0

    run control_memory mainframe.project_memory.get.v1 \
        '{"default":"","key":"replay-key"}' read-replay-cid
    [[ "$status" -eq 0 ]]
    first="$output"
    run python3 - "$first" "$secret" <<'PY'
import base64
import json
import re
import sys
payload = json.loads(sys.argv[1])
result = payload["result"]
assert result["result_available"] is True
assert base64.b64decode(result["transient_b64"], validate=True).decode() == sys.argv[2]
assert result["memory_id"] is None and result["handoff_id"] is None
assert result["memory_record"] is None and result["handoff_record"] is None
for key, prefix in (("run_id", "run-"), ("call_id", "call-"),
                    ("decision_id", "decision-"), ("evidence_id", "evidence-")):
    assert result[key].startswith(prefix)
receipt = result["receipt"]
assert receipt["tool"] == "mainframe.project_memory.get.v1"
assert receipt["record_type"] == "project_get"
assert receipt["memory_id"] is None and receipt["handoff_id"] is None
assert receipt["authoritative"] is False and receipt["trust_label"] == "kernel_bound"
print("project_memory_read_delivery=one_consumer")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_read_delivery=one_consumer" ]]

    run control_memory mainframe.project_memory.get.v1 \
        '{"default":"","key":"replay-key"}' read-replay-cid
    [[ "$status" -eq 0 ]]
    second="$output"
    run python3 - "$first" "$second" <<'PY'
import json
import sys
first = json.loads(sys.argv[1])["result"]
second = json.loads(sys.argv[2])["result"]
for key in ("run_id", "call_id", "decision_id", "evidence_id", "memory_op_id", "input_digest"):
    assert second[key] == first[key]
assert second["result_available"] is False
assert second["transient_b64"] is None
assert second["receipt"] == first["receipt"]
print("project_memory_read_replay=metadata_only")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "project_memory_read_replay=metadata_only" ]]

    run control_memory mainframe.project_memory.get.v1 \
        '{"default":"","key":"replay-key"}' read-replay-cid awm-compatible-v1
    [[ "$status" -eq 66 ]]
    [[ -z "$output" ]]
    ledger="$(ledger_path)"
    ! grep -Fq "$secret" "$ledger"
    [[ "$sid" =~ ^[0-9a-f]{12}$ ]]
}

@test "project memory reads: absent closed and tampered mappings follow frozen states" {
    local sid mapping before after structured
    run control_memory mainframe.project_memory.status.v1 '{}' read-absent-state
    [[ "$status" -eq 0 ]]
    run python3 - "$output" <<'PY'
import json, sys
result = json.loads(sys.argv[1])["result"]
assert result["outcome"] == "recovery_required"
assert result["result_available"] is False
assert result["session_id"] is None
print("absent=recovery_required")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "absent=recovery_required" ]]

    sid="$(ensure_project)"
    project_memory close --project "$PROJECT_DIR"
    run control_memory mainframe.project_memory.status.v1 '{}' read-closed-state
    [[ "$status" -eq 0 ]]
    structured="$output"
    run python3 - "$structured" "$sid" <<'PY'
import base64, json, sys
result = json.loads(sys.argv[1])["result"]
assert result["outcome"] == "succeeded" and result["session_id"] == sys.argv[2]
raw = base64.b64decode(result["transient_b64"], validate=True)
assert b'"status":"completed"' in raw
print("closed=readable")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "closed=readable" ]]

    mapping="$(find_project_mapping)"
    builtin printf '%s' '{"tampered":true}' > "$mapping"
    chmod 600 "$mapping"
    before="$(cksum "$mapping")"
    run control_memory mainframe.project_memory.status.v1 '{}' read-tampered-state
    [[ "$status" -eq 0 ]]
    run python3 - "$output" <<'PY'
import json, sys
result = json.loads(sys.argv[1])["result"]
assert result["outcome"] == "recovery_required"
assert result["result_available"] is False
print("tampered=recovery_required")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "tampered=recovery_required" ]]
    after="$(cksum "$mapping")"
    [[ "$after" == "$before" ]]
}

@test "project memory reads: get preserves default empty and closed-session compatibility" {
    local secret='get-secret-c3f8' ledger
    ensure_project >/dev/null
    run project_memory get --project "$PROJECT_DIR" missing-key
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    run project_memory get --project "$PROJECT_DIR" missing-key fallback-value
    [[ "$status" -eq 0 ]]
    [[ "$output" == fallback-value ]]
    project_memory checkpoint --project "$PROJECT_DIR" exact-key "$secret" --ttl 0
    project_memory close --project "$PROJECT_DIR"
    run project_memory get --project "$PROJECT_DIR" exact-key
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$secret" ]]
    ledger="$(ledger_path)"
    ! grep -Fq "$secret" "$ledger"
    ! grep -Fq fallback-value "$ledger"
}

@test "project memory reads: kernel rejects receipt and transient tamper fixtures" {
    run /usr/bin/python3 -B -I -W error::ResourceWarning -m unittest discover \
        -s "$PROJECT_ROOT/tests/control_plane" \
        -p test_project_memory_integration.py -k read_mapping_states_and_adapter_tamper -v
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Ran 1 test"* ]]
    [[ "$output" == *"OK"* ]]
}

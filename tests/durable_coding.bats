#!/usr/bin/env bats
# Public Bash facade for the fixed durable coding control-plane route.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    WORKSPACE="$TEST_ROOT/workspace"
    STATE_HOME="$TEST_ROOT/state"
    TEST_HOME="$TEST_ROOT/caller-home"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"

    mkdir -p "$WORKSPACE" "$TEST_HOME"
    mkdir -m 0700 "$STATE_HOME"
    export PROJECT_ROOT TEST_ROOT WORKSPACE STATE_HOME TEST_HOME
    export MAINFRAME_BIN BASH_BIN
}

code_command() {
    (
        cd -- "$WORKSPACE" || exit 1
        exec env \
            HOME="$TEST_HOME" XDG_STATE_HOME="$STATE_HOME" \
            MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_BASH="$BASH_BIN" \
            "$MAINFRAME_BIN" code "$@"
    )
}

code_edit() {
    local content="$1"
    shift
    builtin printf '%s' "$content" | code_command edit "$@"
}

code_edit_file() {
    local content_file="$1"
    shift
    code_command edit "$@" <"$content_file"
}

install_capture_runtime() {
    local name="$1"
    CAPTURE_ROOT="$TEST_ROOT/capture-$name"
    CAPTURE_STATE="$TEST_ROOT/capture-state-$name"
    mkdir -p "$CAPTURE_ROOT/bin" "$CAPTURE_ROOT/lib" "$CAPTURE_ROOT/control_plane"
    mkdir -m 0700 "$CAPTURE_STATE"
    cp "$PROJECT_ROOT/bin/mainframe" "$CAPTURE_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/lib/durable_coding.sh" "$CAPTURE_ROOT/lib/durable_coding.sh"
    cp -R "$PROJECT_ROOT/control_plane/mainframe_control_plane" \
        "$CAPTURE_ROOT/control_plane/mainframe_control_plane"
    cp "$PROJECT_ROOT/control_plane/mainframe-control-plane" \
        "$CAPTURE_ROOT/control_plane/mainframe-control-plane"
    chmod 0755 "$CAPTURE_ROOT/bin/mainframe" \
        "$CAPTURE_ROOT/control_plane/mainframe-control-plane"
    /bin/cat >"$CAPTURE_ROOT/control_plane/mainframe-control-plane" <<'PY'
#!/usr/bin/python3 -I
import json
import os
from pathlib import Path
import sys

body = sys.stdin.buffer.read()
capture = {
    "argv": sys.argv[1:],
    "cwd": os.path.realpath(os.getcwd()),
    "environment": dict(os.environ),
    "stdin_utf8": body.decode("utf-8"),
}
Path(os.environ["XDG_STATE_HOME"], "coding-capture.json").write_text(
    json.dumps(capture, sort_keys=True), encoding="utf-8"
)
sys.stdout.write(json.dumps({
    "ok": True,
    "command": "coding-invoke",
    "result": {
        "schema_version": 1,
        "status": "awaiting_approval",
        "client_correlation_id": "coding-kernel-generated",
        "run_id": "run-kernel-generated",
        "call_id": "call-kernel-generated",
        "decision_id": "decision-kernel-generated",
        "approval_id": None,
        "evidence_id": "evidence-kernel-generated",
        "input_digest": "0" * 64,
        "outcome": None,
        "result_available": False,
        "receipt": None,
        "evidence_body": {},
        "stdout_b64": None,
        "stderr_b64": None,
    },
}, sort_keys=True) + "\n")
PY
    chmod 0755 "$CAPTURE_ROOT/control_plane/mainframe-control-plane"
    export CAPTURE_ROOT CAPTURE_STATE
}

capture_code_command() {
    (
        cd -- "$WORKSPACE" || exit 1
        exec env \
            HOME="$TEST_HOME" XDG_STATE_HOME="$CAPTURE_STATE" \
            MAINFRAME_ROOT="$CAPTURE_ROOT" MAINFRAME_BASH="$BASH_BIN" \
            "$CAPTURE_ROOT/bin/mainframe" code "$@"
    )
}

capture_code_edit() {
    local content="$1"
    shift
    builtin printf '%s' "$content" | (
        cd -- "$WORKSPACE" || exit 1
        exec env \
            HOME="$TEST_HOME" XDG_STATE_HOME="$CAPTURE_STATE" \
            MAINFRAME_ROOT="$CAPTURE_ROOT" MAINFRAME_BASH="$BASH_BIN" \
            "$CAPTURE_ROOT/bin/mainframe" code edit "$@"
    )
}

@test "coding facade: read preserves raw output over the durable kernel route" {
    local secret="coding-read-secret-4b91"

    printf '%s\n' "$secret" >"$WORKSPACE/source.txt"
    run code_command read source.txt

    [[ "$status" -eq 0 ]]
    [[ "$output" == "$secret" ]]
    [[ -f "$STATE_HOME/mainframe/control-plane.jsonl" ]]
    ! grep -Fq "$secret" "$STATE_HOME/mainframe/control-plane.jsonl"
}

@test "coding facade: structured read and search bind exact durable identity and metadata" {
    local source_secret="coding-source-secret-614e"
    local query_secret="source-secret-614e" response

    printf '%s\n' "$source_secret" >"$WORKSPACE/source.txt"
    run code_command read source.txt --json
    [[ "$status" -eq 0 ]]
    response="$output"
    run jq -e --arg workspace "$WORKSPACE" --arg secret "$source_secret" '
        keys == ["command","ok","result"] and
        .ok == true and .command == "coding-invoke" and
        (.result | keys) == [
          "approval_id","call_id","client_correlation_id","decision_id",
          "evidence_body","evidence_id","input_digest","outcome","receipt",
          "result_available","run_id","schema_version","status","stderr_b64",
          "stdout_b64"
        ] and
        .result.schema_version == 1 and .result.status == "completed" and
        .result.outcome == "succeeded" and .result.result_available == true and
        (.result.client_correlation_id | test("^coding-[0-9a-f]{32}$")) and
        (.result.run_id | test("^run-[0-9a-f]{32}$")) and
        (.result.call_id | test("^call-[0-9a-f]{32}$")) and
        (.result.decision_id | test("^decision-[0-9a-f]{32}$")) and
        (.result.evidence_id | test("^evidence-[0-9a-f]{32}$")) and
        (.result.input_digest | test("^[0-9a-f]{64}$")) and
        (.result.stdout_b64 | @base64d) == ($secret + "\n") and
        .result.stderr_b64 == "" and
        .result.receipt.tool == "mainframe.coding.read_file.v1" and
        .result.receipt.workspace == $workspace and
        .result.receipt.run_id == .result.run_id and
        .result.receipt.call_id == .result.call_id and
        .result.receipt.decision_id == .result.decision_id and
        .result.receipt.evidence_id == .result.evidence_id and
        .result.receipt.input_digest == .result.input_digest and
        .result.evidence_body == {coding_receipt:.result.receipt}
    ' <<<"$response"
    [[ "$status" -eq 0 ]]

    run code_command search source.txt "$query_secret"
    [[ "$status" -eq 0 ]]
    run jq -e --arg secret "$source_secret" '
        .matches == [{line:1,path:"source.txt",text:$secret}]
    ' <<<"$output"
    [[ "$status" -eq 0 ]]

    run code_command search --json source.txt "$query_secret"
    [[ "$status" -eq 0 ]]
    run jq -e '
        .ok == true and .result.status == "completed" and
        .result.receipt.tool == "mainframe.coding.search_text.v1" and
        .result.receipt.decision_id == .result.decision_id and
        .result.receipt.evidence_id == .result.evidence_id
    ' <<<"$output"
    [[ "$status" -eq 0 ]]

    run rg --hidden --text --fixed-strings "$source_secret" "$STATE_HOME"
    [[ "$status" -eq 1 ]]
    run rg --hidden --text --fixed-strings "$query_secret" "$STATE_HOME"
    [[ "$status" -eq 1 ]]
}

@test "coding facade: fixed public argv carries only tool input stdin and presentation" {
    local capture

    install_capture_runtime exact-route
    run capture_code_command search --json source.txt 'needle with spaces'
    [[ "$status" -eq 0 ]]
    capture="$CAPTURE_STATE/coding-capture.json"
    [[ -f "$capture" ]]
    run python3 - "$capture" "$WORKSPACE" <<'PY'
import json
import os
from pathlib import Path
import sys

capture = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert capture["argv"] == [
    "coding-invoke",
    "--tool-id", "mainframe.coding.search_text.v1",
    "--input-json", "-",
    "--format", "control-plane-json-v1",
]
assert capture["cwd"] == os.path.realpath(sys.argv[2])
assert capture["stdin_utf8"] == '{"path":"source.txt","query":"needle with spaces"}\n'
pairs = json.loads(capture["stdin_utf8"], object_pairs_hook=list)
assert pairs == [("path", "source.txt"), ("query", "needle with spaces")]
for forbidden in (
    "HOME", "USER", "LOGNAME", "MAINFRAME_ROOT", "AWM_ROOT", "PYTHONPATH",
    "PYTHONHOME", "BASH_ENV", "ENV", "LD_PRELOAD", "DYLD_INSERT_LIBRARIES",
):
    assert forbidden not in capture["environment"], forbidden
assert capture["environment"]["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin"
assert capture["environment"]["LC_ALL"] == "C"
assert capture["environment"]["TMPDIR"] == "/tmp"
print("coding_public_route=exact")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "coding_public_route=exact" ]]
}

@test "coding facade: edit content is stdin-only and preimage-bound" {
    local content=$'replacement-secret-f73a\nwith trailing newline\n'
    local digest='6db7d803e74f9159b13ea4b37a5a8c65d6d74659d17a83f5f1a05a44b99d6ac3'
    local capture

    install_capture_runtime edit-stdin
    run capture_code_edit "$content" target.txt --preimage-sha256 "$digest"
    [[ "$status" -eq 0 ]]
    capture="$CAPTURE_STATE/coding-capture.json"
    run python3 - "$capture" "$content" "$digest" <<'PY'
import json
from pathlib import Path
import sys

capture = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
content, digest = sys.argv[2:]
assert capture["argv"] == [
    "coding-invoke",
    "--tool-id", "mainframe.coding.atomic_edit.v1",
    "--input-json", "-",
    "--format", "control-plane-json-v1",
]
assert content not in "\n".join(capture["argv"])
assert capture["stdin_utf8"] == json.dumps({
    "content": content,
    "expected_sha256": digest,
    "path": "target.txt",
}, sort_keys=True, separators=(",", ":")) + "\n"
print("edit_content_transport=stdin_only")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "edit_content_transport=stdin_only" ]]
}

@test "coding facade: edit test and build remain durable approval requests and never execute" {
    local edit_secret='must-not-write-coding-8ad2'
    local target_digest marker="$WORKSPACE/runner-executed" action

    printf 'before' >"$WORKSPACE/target.txt"
    target_digest="$(/usr/bin/shasum -a 256 "$WORKSPACE/target.txt" | awk '{print $1}')"
    printf '%s\n' 'all:' "	@touch '$marker'" >"$WORKSPACE/Makefile"

    run code_edit "$edit_secret" target.txt --preimage-sha256 "$target_digest"
    [[ "$status" -eq 0 ]]
    run jq -e '
        .ok == true and .result.status == "awaiting_approval" and
        .result.outcome == null and .result.result_available == false and
        .result.approval_id == null and .result.receipt == null and
        .result.stdout_b64 == null and .result.stderr_b64 == null and
        (.result.client_correlation_id | test("^coding-[0-9a-f]{32}$")) and
        (.result.run_id | test("^run-[0-9a-f]{32}$")) and
        (.result.call_id | test("^call-[0-9a-f]{32}$")) and
        (.result.decision_id | test("^decision-[0-9a-f]{32}$")) and
        (.result.evidence_id | test("^evidence-[0-9a-f]{32}$"))
    ' <<<"$output"
    [[ "$status" -eq 0 ]]
    [[ "$(<"$WORKSPACE/target.txt")" == before ]]

    for action in test build; do
        run code_command "$action"
        [[ "$status" -eq 0 ]]
        run jq -e --arg tool "mainframe.coding.run_${action}.v1" '
            .ok == true and .result.status == "awaiting_approval" and
            .result.outcome == null and .result.result_available == false and
            .result.receipt == null and .result.evidence_body == {}
        ' <<<"$output"
        [[ "$status" -eq 0 ]]
    done
    [[ ! -e "$marker" ]]
    [[ "$(<"$WORKSPACE/target.txt")" == before ]]
    ! grep -Fq "$edit_secret" "$STATE_HOME/mainframe/control-plane.jsonl"
}

@test "coding facade: malformed or oversized edit bytes fail before durable reservation" {
    local digest='6db7d803e74f9159b13ea4b37a5a8c65d6d74659d17a83f5f1a05a44b99d6ac3'
    local invalid="$TEST_ROOT/invalid.bin" oversized="$TEST_ROOT/oversized.txt"
    local sentinel='oversized-coding-sentinel-cb73' residue

    printf '\377' >"$invalid"
    printf '%s' "$sentinel" >"$oversized"
    /usr/bin/head -c 24577 /dev/zero | /usr/bin/tr '\0' x >>"$oversized"
    run code_edit_file "$invalid" target.txt --preimage-sha256 "$digest"
    [[ "$status" -eq 65 ]]
    run code_edit_file "$oversized" target.txt --preimage-sha256 "$digest"
    [[ "$status" -eq 65 ]]
    [[ ! -e "$STATE_HOME/mainframe/control-plane.jsonl" ]]
    residue="$(find /tmp -maxdepth 1 -name 'mainframe-coding-input.*' -type f \
        -exec grep -lF "$sentinel" {} + 2>/dev/null || true)"
    [[ -z "$residue" ]]
}

@test "coding facade: containment and symlink escapes fail closed" {
    local outside="$TEST_ROOT/outside-secret.txt"

    printf 'outside-secret' >"$outside"
    ln -s "$outside" "$WORKSPACE/link.txt"
    for path in ../outside-secret.txt /etc/passwd; do
        run code_command read --json "$path"
        [[ "$status" -eq 3 ]]
        run jq -e '
            .ok == false and .command == "coding-invoke" and
            .error.code == "execution_denied"
        ' <<<"$output"
        [[ "$status" -eq 0 ]]
    done

    run code_command read --json link.txt
    [[ "$status" -eq 0 ]]
    run jq -e '
        .ok == true and .result.status == "completed" and
        .result.outcome == "failed" and .result.result_available == false and
        .result.receipt == null and .result.stdout_b64 == null and
        .result.evidence_body.error.code == "invalid_executor_result" and
        .result.evidence_body.error.write_may_have_committed == false
    ' <<<"$output"
    [[ "$status" -eq 0 ]]
}

@test "coding facade: duplicate and authority selectors are rejected before the kernel" {
    local digest='6db7d803e74f9159b13ea4b37a5a8c65d6d74659d17a83f5f1a05a44b99d6ac3'
    local flag

    run code_command read --json --json source.txt
    [[ "$status" -eq 64 ]]
    run code_command edit --preimage-sha256 "$digest" \
        --preimage-sha256 "$digest" target.txt
    [[ "$status" -eq 64 ]]
    for flag in --yes --approval-id --actor --workspace --ledger \
        --run-id --call-id --decision-id --evidence-id --authority \
        --outcome --argv --env --client-correlation-id --format; do
        run code_command test "$flag" forged
        [[ "$status" -eq 64 ]]
    done
    [[ ! -e "$STATE_HOME/mainframe/control-plane.jsonl" ]]
}

@test "coding facade: complete trust closure denies unsafe or stale files before launch" {
    local variant module_dir capture

    for variant in bridge_mode coding_symlink durability_missing; do
        install_capture_runtime "$variant"
        module_dir="$CAPTURE_ROOT/control_plane/mainframe_control_plane"
        case "$variant" in
            bridge_mode)
                chmod 0666 "$CAPTURE_ROOT/lib/durable_coding.sh"
                ;;
            coding_symlink)
                /bin/rm -f "$module_dir/coding.py"
                ln -s errors.py "$module_dir/coding.py"
                ;;
            durability_missing)
                mv "$module_dir/durability.py" "$module_dir/durability.py.disabled"
                ;;
        esac
        run capture_code_command read source.txt
        [[ "$status" -eq 126 ]]
        [[ "$output" == *"missing or unsafe"* ]]
        capture="$CAPTURE_STATE/coding-capture.json"
        [[ ! -e "$capture" ]]
    done
}

@test "coding facade: fixed trust list exactly covers transitive Python imports" {
    run python3 - "$PROJECT_ROOT/bin/mainframe" \
        "$PROJECT_ROOT/control_plane/mainframe_control_plane" <<'PY'
import ast
import re
from pathlib import Path
import sys

launcher = Path(sys.argv[1]).read_text(encoding="utf-8")
package = Path(sys.argv[2])
region = launcher.split('if [[ "${1:-}" == "code" ]]', 1)[1]
region = region.split("\nfi\n\n# Preflight", 1)[0]
trusted = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*\.py", region))
production = {path.name for path in package.glob("*.py")}
reachable = {"__init__.py", "cli.py"}
pending = list(reachable)
while pending:
    name = pending.pop()
    tree = ast.parse((package / name).read_text(encoding="utf-8"), filename=name)
    for node in ast.walk(tree):
        if not isinstance(node, ast.ImportFrom) or not node.level:
            continue
        if node.module:
            candidates = [node.module.split(".", 1)[0] + ".py"]
        else:
            candidates = [alias.name.split(".", 1)[0] + ".py" for alias in node.names]
        for candidate in candidates:
            if candidate in production and candidate not in reachable:
                reachable.add(candidate)
                pending.append(candidate)
assert trusted == reachable, {
    "missing": sorted(reachable - trusted),
    "extra": sorted(trusted - reachable),
}
print("coding_trust_closure=exact")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "coding_trust_closure=exact" ]]
}

@test "coding facade: kernel rejects forged receipts and tampered ledgers" {
    run /usr/bin/python3 -B -I -W error::ResourceWarning -m unittest discover \
        -s "$PROJECT_ROOT/tests/control_plane" -p test_coding_agent.py \
        -k fixed_test_and_build_actions_accept_no_argv_and_validate_receipts \
        -k coding_receipt_cannot_forge_reserved_decision_or_evidence \
        -k expired_approval_and_ledger_tamper_fail_closed \
        -v
    [[ "$status" -eq 0 ]]
}

@test "coding facade: bridge and launcher remain Bash 4.4 compatible" {
    local bash44=/private/tmp/mainframe-runtime-bash44/bash-4.4/bash
    local capture jq_path

    [[ -x "$bash44" ]] || skip "exact Bash 4.4 fixture unavailable"
    run "$bash44" --noprofile --norc -p -n \
        "$PROJECT_ROOT/bin/mainframe" "$PROJECT_ROOT/lib/durable_coding.sh"
    [[ "$status" -eq 0 ]]

    install_capture_runtime bash44
    printf 'bash44-content\n' >"$WORKSPACE/source.txt"
    jq_path="$(command -v jq)"
    run env \
        MAINFRAME_ROOT="$CAPTURE_ROOT" \
        XDG_STATE_HOME="$CAPTURE_STATE" \
        _MAINFRAME_CLI_JQ="$jq_path" \
        "$bash44" --noprofile --norc -p -c '
            _mainframe_cli_owner_mode() {
                local result
                result="$(/usr/bin/stat -c "%u %a" "$1" 2>/dev/null ||
                    /usr/bin/stat -f "%u %Mp%Lp" "$1" 2>/dev/null)" || return 1
                printf "%s\n" "$result"
            }
            cd -- "$1" || exit 1
            source "$MAINFRAME_ROOT/lib/durable_coding.sh"
            _mainframe_durable_coding_main read --json source.txt
        ' bash "$WORKSPACE"
    [[ "$status" -eq 0 ]]
    capture="$CAPTURE_STATE/coding-capture.json"
    run jq -e '
        .argv == [
          "coding-invoke","--tool-id","mainframe.coding.read_file.v1",
          "--input-json","-","--format","control-plane-json-v1"
        ] and .stdin_utf8 == "{\"path\":\"source.txt\"}\n"
    ' "$capture"
    [[ "$status" -eq 0 ]]
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-invoke-test.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    AUDIT_ROOT="$TEST_ROOT/state"
    mkdir -p "$AUDIT_ROOT"
    chmod 700 "$AUDIT_ROOT"
}

teardown() {
    rm -rf -- "$TEST_ROOT"
}

invoke_mainframe() {
    env XDG_STATE_HOME="$AUDIT_ROOT" "$MAINFRAME_BIN" invoke "$@"
}

make_broker_fixture() {
    FIXTURE_ROOT="$TEST_ROOT/fixture"
    mkdir -p "$FIXTURE_ROOT/bin" "$FIXTURE_ROOT/lib"
    cp "$MAINFRAME_BIN" "$FIXTURE_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/lib/invoke.sh" "$FIXTURE_ROOT/lib/invoke.sh"
    chmod +x "$FIXTURE_ROOT/bin/mainframe"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'source "$MAINFRAME_ROOT/lib/fixture.sh"' \
        >"$FIXTURE_ROOT/lib/common.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'slow_fixture() {' \
        '    /bin/sleep 20 &' \
        '    local child=$!' \
        '    printf "%s" "$child" >&2' \
        '    wait "$child"' \
        '}' \
        'flood_fixture() {' \
        '    while :; do' \
        '        printf "0123456789abcdef0123456789abcdef"' \
        '    done' \
        '}' \
        'echo_fixture() {' \
        '    printf "%s" "$1"' \
        '}' \
        'background_fixture() {' \
        '    local marker="$1"' \
        '    ( /bin/sleep 1; printf survived >"$marker" ) &' \
        '}' \
        'cancel_fixture() {' \
        '    local pid_file="$1" marker="$2"' \
        '    (' \
        '        printf "%s" "$BASHPID" >"$pid_file"' \
        '        /bin/sleep 20' \
        '        printf survived >"$marker"' \
        '    ) &' \
        '    wait' \
        '}' \
        >"$FIXTURE_ROOT/lib/fixture.sh"

    python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

exports = {}
name_index = {}
for name, timeout, limit, arguments, properties, required in (
    ("slow_fixture", 1000, 1024, [], {}, []),
    ("flood_fixture", 5000, 1024, [], {}, []),
    ("echo_fixture", 5000, 1024,
     [{"field": "value", "mode": "scalar"}],
     {"value": {"type": "string"}}, ["value"]),
    ("background_fixture", 5000, 1024,
     [{"field": "marker", "mode": "scalar"}],
     {"marker": {"type": "string"}}, ["marker"]),
    ("cancel_fixture", 30000, 1024,
     [{"field": "pid_file", "mode": "scalar"},
      {"field": "marker", "mode": "scalar"}],
     {"pid_file": {"type": "string"}, "marker": {"type": "string"}},
     ["pid_file", "marker"]),
):
    cid = f"mf:std:fixture:{name}"
    name_index[name] = cid
    exports[cid] = {
        "name": name,
        "owner": "fixture",
        "profiles": ["stable-core", "full"],
        "effects": ["pure"],
        "capabilities": [],
        "platforms": ["linux", "macos"],
        "bash_identifier": True,
        "contract_status": "reviewed",
		"result": {"kind": "stdout"},
        "input_schema": {
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": False,
        },
        "call_shape": {"kind": "argv", "arguments": arguments},
        "timeout_ms": timeout,
        "output_limit": limit,
    }

# The production broker intentionally pins the reviewed stable-core closure to
# 26 contracts. Fixture-only inert entries preserve that closure while the
# tests exercise five purpose-built functions.
for index in range(21):
    name = f"unused_fixture_{index}"
    cid = f"mf:std:fixture:{name}"
    name_index[name] = cid
    exports[cid] = {
        "name": name,
        "owner": "fixture",
        "profiles": ["stable-core", "full"],
        "effects": ["pure"],
        "capabilities": [],
        "platforms": ["linux", "macos"],
        "bash_identifier": True,
        "contract_status": "reviewed",
        "result": {"kind": "none"},
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
            "additionalProperties": False,
        },
        "call_shape": {"kind": "argv", "arguments": []},
        "timeout_ms": 1000,
        "output_limit": 1024,
    }

invocation_index = {
    "schema_version": 1,
    "manifest_version": 1,
    "version": "10.2.0-test",
    "profile": "stable-core",
    "contract_count": len(exports),
    "modules": {"fixture": {"file": "lib/fixture.sh"}},
    "contracts": exports,
    "name_index": name_index,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(invocation_index, handle, sort_keys=True)
PY
    printf '%s\n' '10.2.0-test' >"$FIXTURE_ROOT/VERSION"
    chmod 0644 \
        "$FIXTURE_ROOT/VERSION" \
        "$FIXTURE_ROOT/INVOCATION_INDEX.json" \
        "$FIXTURE_ROOT/lib/invoke.sh" \
        "$FIXTURE_ROOT/lib/common.sh" \
        "$FIXTURE_ROOT/lib/fixture.sh"
}

@test "invoke: canonical stable-core call returns raw output and a redacted audit" {
    run invoke_mainframe \
        mf:data:json:json_get \
        --input-json '{"json":"{\"secret\":\"broker-proof-4931\"}","key":"secret"}'

    [ "$status" -eq 0 ]
    [ "$output" = "broker-proof-4931" ]

    audit="$AUDIT_ROOT/mainframe/invocations.jsonl"
    [ -f "$audit" ]
    run jq -e '
        length == 1 and .[0].kind == "mainframe-invocation" and
        .[0].canonical_id == "mf:data:json:json_get" and
        .[0].status == "success" and .[0].exit_code == 0
    ' --slurp "$audit"
    [ "$status" -eq 0 ]
    ! grep -F 'broker-proof-4931' "$audit"
}

@test "invoke: broker-json-v1 is a bounded base64 result envelope" {
    run invoke_mainframe \
        mf:data:json:json_object \
        --input-json '{"pairs":["name=Ada","age:number=36"]}' \
        --format broker-json-v1 --caller test

    [ "$status" -eq 0 ]
    run python3 - "$output" <<'PY'
import base64
import json
import sys

value = json.loads(sys.argv[1])
assert set(value) == {
    "schema_version", "ok", "status", "canonical_id", "name", "owner",
    "exit_code", "timed_out", "output_exceeded", "duration_ms", "audit_id",
    "stdout_b64", "stderr_b64", "error",
}
assert value["schema_version"] == 1 and value["ok"] is True
assert value["status"] == "success" and value["exit_code"] == 0
assert value["canonical_id"] == "mf:data:json:json_object"
assert json.loads(base64.b64decode(value["stdout_b64"])) == {"name": "Ada", "age": 36}
assert base64.b64decode(value["stderr_b64"]) == b""
PY
    [ "$status" -eq 0 ]
}

@test "invoke: reviewed defaults and explicit variadics map deterministically" {
    run invoke_mainframe \
        mf:data:pure-array:array_join \
        --input-json '{"items":["a","b","c"]}'
    [ "$status" -eq 0 ]
    [ "$output" = "a,b,c" ]

    run invoke_mainframe \
        mf:std:validation:validate_int \
        --input-json '{"value":"10","max":"20"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run invoke_mainframe \
        mf:data:pure-array:array_join \
        --input-json '{"delimiter":"_MAINFRAME_TIER_AI","items":["left","right"]}'
    [ "$status" -eq 0 ]
    [ "$output" = "left_MAINFRAME_TIER_AIright" ]
}

@test "invoke: closed schemas reject undeclared fields and wrong types" {
    run invoke_mainframe \
        mf:data:json:json_get \
        --input-json '{"json":"{}","key":"x","command":"id"}' \
        --format broker-json-v1
    [ "$status" -eq 65 ]
    run jq -e '.ok == false and .status == "invalid_input" and .exit_code == 65' \
        <<<"$output"
    [ "$status" -eq 0 ]

    run invoke_mainframe \
        mf:data:json:json_array \
        --input-json '{"items":["ok",7]}'
    [ "$status" -eq 65 ]
    [[ "$output" == *"closed input schema"* ]]
}

@test "invoke: Bash names external executables and unknown canonical IDs never run" {
    fake_bin="$TEST_ROOT/fake-bin"
    marker="$TEST_ROOT/external-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf ran > "${MAINFRAME_TEST_MARKER:?}"' \
        >"$fake_bin/id"
    chmod +x "$fake_bin/id"

    run env PATH="$fake_bin:/usr/bin:/bin" MAINFRAME_TEST_MARKER="$marker" \
        XDG_STATE_HOME="$AUDIT_ROOT" "$MAINFRAME_BIN" invoke id --input-json '{}'
    [ "$status" -eq 126 ]
    [ ! -e "$marker" ]

    run invoke_mainframe mf:std:fixture:not_registered --input-json '{}'
    [ "$status" -eq 126 ]
    [[ "$output" == *"not registered"* ]]
}

@test "invoke: non-stable exports are absent from the reviewed broker index" {
    cid="$(jq -r '.name_index.atomic_write' "$PROJECT_ROOT/MANIFEST.json")"
    [ -n "$cid" ]
    [ "$cid" != null ]

    run invoke_mainframe "$cid" --input-json '{}' --format broker-json-v1
    [ "$status" -eq 126 ]
    run jq -e '.ok == false and .status == "unknown_id"' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: poisoned startup variables exported functions and PATH shims are inert" {
    poison="$TEST_ROOT/poison.sh"
    marker="$TEST_ROOT/poison-ran"
    fake_bin="$TEST_ROOT/poison-bin"
    mkdir -p "$fake_bin"
    printf '%s\n' 'printf startup > "${MAINFRAME_TEST_MARKER:?}"' >"$poison"
    for tool in jq cat chmod mkdir mktemp readlink rm rmdir; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf poison > "${MAINFRAME_TEST_MARKER:?}"' \
            'exit 97' >"$fake_bin/$tool"
        chmod +x "$fake_bin/$tool"
    done

    run env PATH="$fake_bin:/usr/bin:/bin" BASH_ENV="$poison" ENV="$poison" \
        MAINFRAME_TEST_MARKER="$marker" XDG_STATE_HOME="$AUDIT_ROOT" \
        "$MAINFRAME_BIN" invoke mf:std:pure-string:to_upper \
        --input-json '{"value":"safe"}'
    [ "$status" -eq 0 ]
    [ "$output" = SAFE ]
    [ ! -e "$marker" ]
}

@test "invoke: unsafe audit targets deny execution before the function runs" {
    target="$TEST_ROOT/audit-target"
    link="$TEST_ROOT/audit-link"
    printf 'preserve-me' >"$target"
    ln -s "$target" "$link"

    run env MAINFRAME_INVOKE_AUDIT_LOG="$link" \
        "$MAINFRAME_BIN" invoke mf:std:pure-string:to_upper \
        --input-json '{"value":"must-not-run"}'
    [ "$status" -eq 74 ]
    [[ "$output" == *"audit trail is unavailable"* ]]
    [ "$(<"$target")" = preserve-me ]
}

@test "invoke: stdin preserves embedded and trailing newlines as literal data" {
    request="$TEST_ROOT/request.json"
    printf '%s' '{"value":"line one\nline two\n"}' >"$request"

    run env XDG_STATE_HOME="$AUDIT_ROOT" bash -c \
        '"$1" invoke mf:data:json:json_string --input-json - --format broker-json-v1 <"$2"' \
        _ "$MAINFRAME_BIN" "$request"
    [ "$status" -eq 0 ]
    run python3 - "$output" <<'PY'
import base64
import json
import sys

value = json.loads(sys.argv[1])
assert base64.b64decode(value["stdout_b64"]) == b'"line one\\nline two\\n"'
PY
    [ "$status" -eq 0 ]
}

@test "invoke: stdin waits for EOF and rejects delayed trailing data" {
    run env XDG_STATE_HOME="$AUDIT_ROOT" bash -c '
        {
            printf %s '\''{"value":"safe"}'\''
            /bin/sleep 0.2
            printf %s '\''TRAILING-JUNK'\''
        } | "$1" invoke mf:std:pure-string:to_upper --input-json - \
            --format broker-json-v1 --caller security-test
    ' _ "$MAINFRAME_BIN"

    [ "$status" -eq 65 ]
    run jq -e '.ok == false and .status == "invalid_input"' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: stdin rejects literal NUL bytes without rewriting the request" {
    run env XDG_STATE_HOME="$AUDIT_ROOT" bash -c '
        python3 -c '\''import sys; sys.stdout.buffer.write(b"{\\\"value\\\":\\\"safe\\x00\\\"}")'\'' |
            "$1" invoke mf:std:pure-string:to_upper --input-json - \
                --format broker-json-v1 --caller security-test
    ' _ "$MAINFRAME_BIN"

    [ "$status" -eq 65 ]
    run jq -e '.ok == false and .status == "invalid_input"' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: stdin rejects requests larger than the framing limit" {
    run env XDG_STATE_HOME="$AUDIT_ROOT" bash -c '
        python3 -c '\''import sys; sys.stdout.write("{" + " " * 32768 + "}")'\'' |
            "$1" invoke mf:std:pure-string:to_upper --input-json - \
                --format broker-json-v1 --caller security-test
    ' _ "$MAINFRAME_BIN"

    [ "$status" -eq 65 ]
    run jq -e '.ok == false and .status == "invalid_input"' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: stdin accepts a request exactly at the framing limit" {
    run env XDG_STATE_HOME="$AUDIT_ROOT" bash -c '
        python3 -c '\''import sys; q=chr(34); sys.stdout.write("{"+q+"value"+q+":"+q+"x"*32756+q+"}")'\'' |
            "$1" invoke mf:std:pure-string:is_empty --input-json - \
                --format broker-json-v1 --caller security-test
    ' _ "$MAINFRAME_BIN"

    [ "$status" -eq 1 ]
    run jq -e '
        .ok == false and .status == "function_error" and .exit_code == 1
    ' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: duplicate and escaped-equivalent object keys fail closed" {
    for request in \
        '{"value":"first","value":"second"}' \
        '{"value":"first","\u0076alue":"second"}'
    do
        run invoke_mainframe \
            mf:std:pure-string:to_upper \
            --input-json "$request" --format broker-json-v1 --caller security-test
        [ "$status" -eq 65 ]
        run jq -e '.ok == false and .status == "invalid_input"' <<<"$output"
        [ "$status" -eq 0 ]
    done
}

@test "invoke: kernel output limit bounds a flooding function and its envelope" {
    make_broker_fixture

    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:flood_fixture \
        --input-json '{}' --format broker-json-v1 --caller test
    envelope="$output"
    [ "$status" -eq 74 ]
    [ "${#envelope}" -lt 4096 ]
    run jq -e '
        .ok == false and .status == "output_limit" and
        .output_exceeded == true and .exit_code == 74 and
        (.stdout_b64 | length) == 0
    ' <<<"$envelope"
    [ "$status" -eq 0 ]
}

@test "invoke: timeout terminates the fixture process group and records the denial" {
    make_broker_fixture

    started="$SECONDS"
    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:slow_fixture \
        --input-json '{}' --format broker-json-v1 --caller test
    envelope="$output"
    elapsed=$((SECONDS - started))
    [ "$status" -eq 124 ]
    [ "$elapsed" -lt 8 ]
    run jq -e '
        .ok == false and .status == "timeout" and
        .timed_out == true and .exit_code == 124
    ' <<<"$envelope"
    [ "$status" -eq 0 ]

    child_pid="$(jq -r '.stderr_b64' <<<"$envelope" | base64 --decode 2>/dev/null ||
        jq -r '.stderr_b64' <<<"$envelope" | base64 -D)"
    [[ "$child_pid" =~ ^[0-9]+$ ]]
    ! kill -0 "$child_pid" 2>/dev/null
}

@test "invoke: a function cannot return success while a descendant survives" {
    make_broker_fixture
    marker="$TEST_ROOT/background-survived"
    input="$(jq -cn --arg marker "$marker" '{marker:$marker}')"

    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:background_fixture \
        --input-json "$input" --format broker-json-v1 --caller security-test
    envelope="$output"
    [ "$status" -eq 70 ]
    run jq -e '
        .ok == false and .status == "broker_error" and .exit_code == 70
    ' <<<"$envelope"
    [ "$status" -eq 0 ]

    /bin/sleep 1.5
    [ ! -e "$marker" ]
}

@test "invoke: terminating the broker also terminates its active process group" {
    make_broker_fixture
    pid_file="$TEST_ROOT/cancel-child.pid"
    marker="$TEST_ROOT/cancel-child-survived"
    output_file="$TEST_ROOT/cancel-output"
    input="$(jq -cn --arg pid_file "$pid_file" --arg marker "$marker" \
        '{pid_file:$pid_file,marker:$marker}')"

    env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:cancel_fixture \
        --input-json "$input" --format broker-json-v1 --caller security-test \
        >"$output_file" 2>&1 &
    broker_pid=$!

    for _ in {1..40}; do
        [ -s "$pid_file" ] && break
        /bin/sleep 0.05
    done
    [ -s "$pid_file" ]
    child_pid="$(<"$pid_file")"
    [[ "$child_pid" =~ ^[0-9]+$ ]]

    kill -TERM "$broker_pid"
    wait "$broker_pid" 2>/dev/null || true
    /bin/sleep 0.2

    ! kill -0 "$child_pid" 2>/dev/null
    [ ! -e "$marker" ]
}

@test "invoke: nonempty capabilities in an otherwise valid contract are denied" {
    make_broker_fixture
    python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["contracts"]["mf:std:fixture:echo_fixture"]["capabilities"] = ["net.egress"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY

    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
        --input-json '{"value":"blocked"}' --format broker-json-v1
    [ "$status" -eq 126 ]
    run jq -e '.status == "unreviewed_contract" and .ok == false' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: malformed result contracts are denied" {
    make_broker_fixture
    python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["contracts"]["mf:std:fixture:echo_fixture"]["result"] = {
    "kind": "shell",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY

    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
        --input-json '{"value":"blocked"}' --format broker-json-v1
    [ "$status" -eq 126 ]
    run jq -e '.status == "unreviewed_contract" and .ok == false' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: compact index identity platform and bounds invariants fail closed" {
    local mutation expected response
    for mutation in top_level count name owner name_index module platform timeout output; do
        case "$mutation" in
            top_level|count|module) expected=invalid_manifest ;;
            name|owner|timeout|output) expected=invalid_contract ;;
            name_index) expected=owner_mismatch ;;
            platform) expected=unsupported_platform ;;
        esac
        make_broker_fixture
        python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" "$mutation" <<'PY'
import json
import sys

path, mutation = sys.argv[1:]
value = json.load(open(path, encoding="utf-8"))
contract = value["contracts"]["mf:std:fixture:echo_fixture"]
if mutation == "top_level":
    value["surprise"] = True
elif mutation == "count":
    value["contract_count"] = 25
elif mutation == "name":
    contract["name"] = "UnsafeName"
elif mutation == "owner":
    contract["owner"] = "../fixture"
elif mutation == "name_index":
    value["name_index"]["echo_fixture"] = "mf:std:fixture:unused_fixture_0"
elif mutation == "module":
    value["modules"]["fixture"]["file"] = "lib/json.sh"
elif mutation == "platform":
    contract["platforms"] = ["unsupported"]
elif mutation == "timeout":
    contract["timeout_ms"] = 0
elif mutation == "output":
    contract["output_limit"] = 0
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        response="$output"
        run jq -e --arg expected "$expected" \
            '.ok == false and .status == $expected and .exit_code == 126' \
            <<<"$response"
        [ "$status" -eq 0 ]
    done
}

@test "invoke: missing and symbolic-link broker indexes are unsafe" {
    local response
    for mutation in missing symlink; do
        make_broker_fixture
        if [[ "$mutation" == symlink ]]; then
            mv "$FIXTURE_ROOT/INVOCATION_INDEX.json" \
                "$FIXTURE_ROOT/INVOCATION_INDEX.real.json"
            ln -s "INVOCATION_INDEX.real.json" \
                "$FIXTURE_ROOT/INVOCATION_INDEX.json"
        else
            rm "$FIXTURE_ROOT/INVOCATION_INDEX.json"
        fi

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        response="$output"
        run jq -e '
            .ok == false and .status == "invalid_manifest" and
            .exit_code == 126
        ' <<<"$response"
        [ "$status" -eq 0 ]
    done
}

@test "invoke: VERSION must be one exact line matching the broker index" {
    local mutation response
    for mutation in stale index_stale leading_space multiline crlf blank missing symlink; do
        make_broker_fixture
        case "$mutation" in
            stale) printf '%s\n' '9.9.9' >"$FIXTURE_ROOT/VERSION" ;;
            index_stale)
                python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["version"] = "9.9.9"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY
                ;;
            leading_space) printf ' 10.2.0-test\n' >"$FIXTURE_ROOT/VERSION" ;;
            multiline) printf '10.2.0-test\nextra\n' >"$FIXTURE_ROOT/VERSION" ;;
            crlf) printf '10.2.0-test\r\n' >"$FIXTURE_ROOT/VERSION" ;;
            blank) : >"$FIXTURE_ROOT/VERSION" ;;
            missing) rm "$FIXTURE_ROOT/VERSION" ;;
            symlink)
                mv "$FIXTURE_ROOT/VERSION" "$FIXTURE_ROOT/VERSION.real"
                ln -s VERSION.real "$FIXTURE_ROOT/VERSION"
                ;;
        esac

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        response="$output"
        run jq -e '
            .ok == false and .status == "invalid_manifest" and
            .exit_code == 126
        ' <<<"$response"
        [ "$status" -eq 0 ]
    done
}

@test "invoke: trust files reject group writes other writes and special bits" {
    local mutation target mode expected response
    for mutation in broker_0666 index_0664 common_0666 owner_0664 owner_setuid; do
        make_broker_fixture
        case "$mutation" in
            broker_0666)
                target="$FIXTURE_ROOT/lib/invoke.sh"; mode=0666; expected=raw
                ;;
            index_0664)
                target="$FIXTURE_ROOT/INVOCATION_INDEX.json"; mode=0664
                expected=invalid_manifest
                ;;
            common_0666)
                target="$FIXTURE_ROOT/lib/common.sh"; mode=0666
                expected=invalid_owner
                ;;
            owner_0664)
                target="$FIXTURE_ROOT/lib/fixture.sh"; mode=0664
                expected=invalid_owner
                ;;
            owner_setuid)
                target="$FIXTURE_ROOT/lib/fixture.sh"; mode=4644
                expected=invalid_owner
                ;;
        esac
        chmod "$mode" "$target"

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        if [[ "$expected" == raw ]]; then
            [[ "$output" == *"canonical broker is missing or unsafe"* ]]
        else
            response="$output"
            run jq -e --arg expected "$expected" '
                .ok == false and .status == $expected and .exit_code == 126
            ' <<<"$response"
            [ "$status" -eq 0 ]
        fi
    done
}

@test "invoke: trust files accept same-owner release modes 0644 and 0755" {
    local mode
    for mode in 0644 0755; do
        make_broker_fixture
        chmod "$mode" \
            "$FIXTURE_ROOT/INVOCATION_INDEX.json" \
            "$FIXTURE_ROOT/lib/invoke.sh" \
            "$FIXTURE_ROOT/lib/common.sh" \
            "$FIXTURE_ROOT/lib/fixture.sh"

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"allowed"}'
        [ "$status" -eq 0 ]
        [ "$output" = allowed ]
    done
}

@test "invoke: every trust file rejects a symbolic-link replacement" {
    local label target response
    for label in broker index common owner; do
        make_broker_fixture
        case "$label" in
            broker) target="$FIXTURE_ROOT/lib/invoke.sh" ;;
            index) target="$FIXTURE_ROOT/INVOCATION_INDEX.json" ;;
            common) target="$FIXTURE_ROOT/lib/common.sh" ;;
            owner) target="$FIXTURE_ROOT/lib/fixture.sh" ;;
        esac
        mv "$target" "$target.real"
        ln -s "${target##*/}.real" "$target"

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        if [[ "$label" == broker ]]; then
            [[ "$output" == *"canonical broker is missing or unsafe"* ]]
        else
            response="$output"
            run jq -e '
                .ok == false and
                (.status == "invalid_manifest" or .status == "invalid_owner") and
                .exit_code == 126
            ' <<<"$response"
            [ "$status" -eq 0 ]
        fi
        rm "$target"
        mv "$target.real" "$target"
    done
}

@test "invoke: contract subobjects reject undeclared metadata" {
    for mutation in schema shape argument property effects; do
        make_broker_fixture
        python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" "$mutation" <<'PY'
import json
import sys

path, mutation = sys.argv[1:]
value = json.load(open(path, encoding="utf-8"))
export = value["contracts"]["mf:std:fixture:echo_fixture"]
if mutation == "schema":
    export["input_schema"]["surprise"] = True
elif mutation == "shape":
    export["call_shape"]["surprise"] = True
elif mutation == "argument":
    export["call_shape"]["arguments"][0]["surprise"] = True
elif mutation == "property":
    export["input_schema"]["properties"]["value"]["surprise"] = True
elif mutation == "effects":
    export["effects"] = ["pure", "read"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"blocked"}' --format broker-json-v1
        [ "$status" -eq 126 ]
        run jq -e '.status == "unreviewed_contract" and .ok == false' <<<"$output"
        [ "$status" -eq 0 ]
    done
}

@test "invoke: exit and none result contracts cannot smuggle stdout" {
    for result_kind in exit none; do
        make_broker_fixture
        python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" "$result_kind" <<'PY'
import json
import sys

path, result_kind = sys.argv[1:]
value = json.load(open(path, encoding="utf-8"))
value["contracts"]["mf:std:fixture:echo_fixture"]["result"] = {
    "kind": result_kind,
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY

        run env XDG_STATE_HOME="$AUDIT_ROOT" \
            "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
            --input-json '{"value":"must-not-escape"}' --format broker-json-v1
        [ "$status" -eq 70 ]
        run jq -e '
            .ok == false and .status == "broker_error" and .exit_code == 70 and
            (.stdout_b64 | length) == 0
        ' <<<"$output"
        [ "$status" -eq 0 ]
    done

    make_broker_fixture
    printf '%s\n' \
        'echo_fixture() {' \
        '    printf "%s" "$1"' \
        '    return 1' \
        '}' >>"$FIXTURE_ROOT/lib/fixture.sh"
    python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["contracts"]["mf:std:fixture:echo_fixture"]["result"] = {"kind": "exit"}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True)
PY
    run env XDG_STATE_HOME="$AUDIT_ROOT" \
        "$FIXTURE_ROOT/bin/mainframe" invoke mf:std:fixture:echo_fixture \
        --input-json '{"value":"failure-must-not-escape"}' --format broker-json-v1
    [ "$status" -eq 70 ]
    run jq -e '.status == "broker_error" and (.stdout_b64 | length) == 0' \
        <<<"$output"
    [ "$status" -eq 0 ]
}

@test "invoke: validate_int treats range bounds as data, never arithmetic code" {
    marker="$TEST_ROOT/validate-int-arithmetic-ran"
    payload="$(printf 'a[$(printf marker > "%s")]' "$marker")"
    input="$(jq -cn --arg payload "$payload" \
        '{value:"1",min:$payload,max:""}')"

    run invoke_mainframe \
        mf:std:validation:validate_int \
        --input-json "$input" --format broker-json-v1 --caller security-test
    [ "$status" -eq 1 ]
    run jq -e '
        .ok == false and .status == "function_error" and .exit_code == 1
    ' <<<"$output"
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
}

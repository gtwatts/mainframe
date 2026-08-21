#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    FIXTURE_ROOT="$BATS_TEST_TMPDIR/runtime"
    MARKER="$BATS_TEST_TMPDIR/legacy-broker-ran"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"

    mkdir -p "$FIXTURE_ROOT/bin" "$FIXTURE_ROOT/lib"
    cp "$PROJECT_ROOT/bin/mainframe" "$FIXTURE_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/lib/invoke.sh" "$FIXTURE_ROOT/lib/invoke.sh"
    cp "$PROJECT_ROOT/lib/durable_invoke.sh" "$FIXTURE_ROOT/lib/durable_invoke.sh"
    chmod 0755 "$FIXTURE_ROOT/bin/mainframe"

    # These single-quoted fixture lines must expand only in the child runtime.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'source "$MAINFRAME_ROOT/lib/fixture.sh"' \
        > "$FIXTURE_ROOT/lib/common.sh"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'durable_fixture() {' \
        '    printf "executed" > "$1"' \
        '    printf "legacy-result"' \
        '}' \
        'durable_near_limit() {' \
        '    local block' \
        '    printf -v block "%*s" 60000 ""' \
        '    printf "%s" "${block// /x}"' \
        '}' \
        'durable_slow_output() {' \
        '    printf "%s" "$1"' \
        '    printf "%s" "$BASHPID" > "$2"' \
        '    /bin/sleep 30' \
        '}' \
        > "$FIXTURE_ROOT/lib/fixture.sh"

    python3 - "$FIXTURE_ROOT/INVOCATION_INDEX.json" <<'PY'
import json
import sys

contracts = {}
name_index = {}

name = "durable_fixture"
canonical_id = f"mf:std:fixture:{name}"
name_index[name] = canonical_id
contracts[canonical_id] = {
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
        "properties": {"marker": {"type": "string"}},
        "required": ["marker"],
        "additionalProperties": False,
    },
    "call_shape": {
        "kind": "argv",
        "arguments": [{"field": "marker", "mode": "scalar"}],
    },
    "timeout_ms": 5000,
    "output_limit": 65536,
}

# The production broker pins the reviewed stable-core closure to 26 contracts.
# Inert entries keep the fixture structurally valid without widening execution.
for index in range(23):
    name = f"unused_fixture_{index}"
    canonical_id = f"mf:std:fixture:{name}"
    name_index[name] = canonical_id
    contracts[canonical_id] = {
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
        "timeout_ms": 5000,
        "output_limit": 65536,
    }

for name, properties, required, arguments in (
    ("durable_near_limit", {}, [], []),
    (
        "durable_slow_output",
        {"sentinel": {"type": "string"}, "ready": {"type": "string"}},
        ["sentinel", "ready"],
        [
            {"field": "sentinel", "mode": "scalar"},
            {"field": "ready", "mode": "scalar"},
        ],
    ),
):
    canonical_id = f"mf:std:fixture:{name}"
    name_index[name] = canonical_id
    contracts[canonical_id] = {
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
        "timeout_ms": 30000,
        "output_limit": 65536,
    }

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "schema_version": 1,
            "manifest_version": 1,
            "version": "10.2.0-test",
            "profile": "stable-core",
            "contract_count": len(contracts),
            "modules": {"fixture": {"file": "lib/fixture.sh"}},
            "contracts": contracts,
            "name_index": name_index,
        },
        handle,
        sort_keys=True,
    )
PY

    printf '%s\n' '10.2.0-test' > "$FIXTURE_ROOT/VERSION"
    chmod 0644 \
        "$FIXTURE_ROOT/VERSION" \
        "$FIXTURE_ROOT/INVOCATION_INDEX.json" \
        "$FIXTURE_ROOT/lib/invoke.sh" \
        "$FIXTURE_ROOT/lib/durable_invoke.sh" \
        "$FIXTURE_ROOT/lib/common.sh" \
        "$FIXTURE_ROOT/lib/fixture.sh"
}

install_fake_control_plane_closure() {
    local marker="$1"

    if [[ -e "$FIXTURE_ROOT/control_plane" ]]; then
        rm -rf -- "$FIXTURE_ROOT/control_plane"
    fi
    cp -R "$PROJECT_ROOT/control_plane" "$FIXTURE_ROOT/control_plane"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf invoked > '$marker'" \
        'exit 70' \
        >"$FIXTURE_ROOT/control_plane/mainframe-control-plane"
    chmod 0755 "$FIXTURE_ROOT/control_plane/mainframe-control-plane"
}

run_hidden_with_clean_liveness() {
    exec 198< <(printf C)
    "$@"
}

@test "invoke: fixed kernel adapter accepts only canonical stdin transport" {
    local response audit_log audit_id

    run run_hidden_with_clean_liveness \
        env XDG_STATE_HOME="$BATS_TEST_TMPDIR/adapter-state" \
        "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
        mf:std:fixture:durable_fixture \
        --input-json - \
        --profile stable-core \
        --format broker-json-v1 \
        --caller control-plane \
        <<<"{\"marker\":\"$MARKER\"}"

    [[ "$status" -eq 0 ]]
    [[ -e "$MARKER" ]]
    response="$output"
    run jq -e '
        keys == [
          "audit_id", "canonical_id", "duration_ms", "error", "exit_code",
          "name", "ok", "output_exceeded", "owner", "schema_version",
          "status", "stderr_b64", "stdout_b64", "timed_out"
        ] and
        .schema_version == 1 and .ok == true and .status == "success" and
        .canonical_id == "mf:std:fixture:durable_fixture" and
        .name == "durable_fixture" and .owner == "fixture" and
        .exit_code == 0 and .timed_out == false and
        .output_exceeded == false and .stderr_b64 == "" and
        (.stdout_b64 | @base64d) == "legacy-result" and .error == null
    ' <<<"$response"
    [[ "$status" -eq 0 ]]

    audit_id="$(jq -r '.audit_id' <<<"$response")"
    audit_log="$BATS_TEST_TMPDIR/adapter-state/mainframe/invocations.jsonl"
    run jq -se --arg audit_id "$audit_id" '
        length == 1 and .[0].schema_version == 1 and
        .[0].kind == "mainframe-invocation" and
        .[0].audit_id == $audit_id and
        .[0].canonical_id == "mf:std:fixture:durable_fixture" and
        .[0].caller == "control-plane" and .[0].profile == "stable-core" and
        .[0].status == "success" and .[0].exit_code == 0 and
        .[0].timed_out == false and .[0].output_exceeded == false and
        .[0].input_bytes > 0
    ' "$audit_log"
    [[ "$status" -eq 0 ]]
}

@test "invoke: raw NUL input is rejected without semantic reinterpretation" {
    local state="$BATS_TEST_TMPDIR/nul-state"

    mkdir -p "$state"
    chmod 0700 "$state"
    # shellcheck disable=SC2016
    run "$BASH_BIN" --noprofile --norc -c '
        exec 198< <(printf C)
        printf "{\"marker\":\"%s\000suffix\"}" "$1" |
            env TMPDIR="$2" XDG_STATE_HOME="$3" "$4" \
                __kernel-stable-core-broker-v1 \
                mf:std:fixture:durable_fixture --input-json - \
                --profile stable-core --format broker-json-v1 \
                --caller control-plane
    ' bash "$MARKER" "$BATS_TEST_TMPDIR" "$state" \
        "$FIXTURE_ROOT/bin/mainframe"

    [[ "$status" -eq 65 ]]
    [[ ! -e "$MARKER" ]]
    run jq -e '.ok == false and .status == "invalid_input" and .exit_code == 65' \
        <<<"$output"
    [[ "$status" -eq 0 ]]
}

@test "invoke: fixed kernel adapter rejects caller-controlled transport options" {
    local altered marker="$BATS_TEST_TMPDIR/altered-transport-ran"

    for altered in raw caller extra; do
        case "$altered" in
            raw)
                run env XDG_STATE_HOME="$BATS_TEST_TMPDIR/adapter-state" \
                    "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
                    mf:std:fixture:durable_fixture --input-json - \
                    --profile stable-core --format raw --caller control-plane \
                    <<<"{\"marker\":\"$marker\"}"
                ;;
            caller)
                run env XDG_STATE_HOME="$BATS_TEST_TMPDIR/adapter-state" \
                    "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
                    mf:std:fixture:durable_fixture --input-json - \
                    --profile stable-core --format broker-json-v1 --caller cli \
                    <<<"{\"marker\":\"$marker\"}"
                ;;
            extra)
                run env XDG_STATE_HOME="$BATS_TEST_TMPDIR/adapter-state" \
                    "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
                    mf:std:fixture:durable_fixture --input-json - \
                    --profile stable-core --format broker-json-v1 \
                    --caller control-plane --evidence forged \
                    <<<"{\"marker\":\"$marker\"}"
                ;;
        esac
        [[ "$status" -eq 64 ]]
        [[ -z "$output" ]]
        [[ ! -e "$marker" ]]
    done
}

@test "invoke: fixed kernel adapter requires the inherited liveness capability" {
    run env XDG_STATE_HOME="$BATS_TEST_TMPDIR/missing-liveness-state" \
        "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
        mf:std:fixture:durable_fixture --input-json - \
        --profile stable-core --format broker-json-v1 --caller control-plane \
        <<<"{\"marker\":\"$MARKER\"}"

    [[ "$status" -eq 126 ]]
    [[ -z "$output" ]]
    [[ ! -e "$MARKER" ]]
}

@test "invoke: unavailable durable kernel denies execution without legacy fallback" {
    run env XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
        "$FIXTURE_ROOT/bin/mainframe" invoke \
        mf:std:fixture:durable_fixture \
        --input-json "{\"marker\":\"$MARKER\"}" \
        --format broker-json-v1

    [[ "$status" -ne 0 ]]
    [[ ! -e "$MARKER" ]]
    [[ "$output" == *"control-plane"* || "$output" == *"kernel"* ]]
}

@test "invoke: public bridge execs only fixed non-authorizing kernel argv" {
    local marker="$BATS_TEST_TMPDIR/public-kernel-argv" flag

    install_fake_control_plane_closure "$marker"
    printf '%s\n' \
        '#!/bin/sh' \
        ": > '$marker'" \
        "for arg; do printf '%s\\n' \"\$arg\" >> '$marker'; done" \
        'exit 70' \
        >"$FIXTURE_ROOT/control_plane/mainframe-control-plane"
    chmod 0755 "$FIXTURE_ROOT/control_plane/mainframe-control-plane"

    run "$FIXTURE_ROOT/bin/mainframe" invoke \
        mf:std:pure-string:to_upper --input-json '{"value":"hello"}' \
        --profile stable-core --format broker-json-v1 --caller pi \
        --client-correlation-id client-fixed-argv
    [[ "$status" -eq 70 ]]
    [[ "$(<"$marker")" == $'canonical-invoke\n--canonical-id\nmf:std:pure-string:to_upper\n--input-json\n{"value":"hello"}\n--client-correlation-id\nclient-fixed-argv\n--format\nbroker-json-v1' ]]

    for flag in --actor --policy --run-id --call-id --decision-id \
        --evidence-id --authority --outcome --executable; do
        /bin/rm -f -- "$marker"
        run "$FIXTURE_ROOT/bin/mainframe" invoke \
            mf:std:pure-string:to_upper --input-json '{"value":"blocked"}' \
            "$flag" forged
        [[ "$status" -eq 64 ]]
        [[ ! -e "$marker" ]]
    done
}

@test "invoke: complete Python closure is trusted before launcher execution" {
    local marker="$BATS_TEST_TMPDIR/untrusted-control-plane-ran"
    local module_dir="$FIXTURE_ROOT/control_plane/mainframe_control_plane"
    local variant

    for variant in worker_mode transient_symlink durability_symlink executor_mode \
        coding_mode memory_symlink memory_executor_mode memory_transient_symlink \
        memory_worker_mode; do
        install_fake_control_plane_closure "$marker"
        case "$variant" in
            worker_mode)
                chmod 0666 "$module_dir/worker.py"
                ;;
            transient_symlink)
                rm -f "$module_dir/transient.py"
                ln -s errors.py "$module_dir/transient.py"
                ;;
            durability_symlink)
                rm -f "$module_dir/durability.py"
                ln -s errors.py "$module_dir/durability.py"
                ;;
            executor_mode)
                chmod 0666 "$module_dir/executor.py"
                ;;
            coding_mode)
                chmod 0666 "$module_dir/coding.py"
                ;;
            memory_symlink)
                rm -f "$module_dir/memory.py"
                ln -s errors.py "$module_dir/memory.py"
                ;;
            memory_executor_mode)
                chmod 0666 "$module_dir/memory_executor.py"
                ;;
            memory_transient_symlink)
                rm -f "$module_dir/memory_transient.py"
                ln -s errors.py "$module_dir/memory_transient.py"
                ;;
            memory_worker_mode)
                chmod 0666 "$module_dir/memory_worker.py"
                ;;
        esac

        run "$FIXTURE_ROOT/bin/mainframe" invoke \
            mf:std:pure-string:to_upper --input-json '{"value":"blocked"}' \
            --format control-plane-json-v1 \
            --client-correlation-id "client-closure-$variant"

        [[ "$status" -eq 126 ]]
        [[ "$output" == *"module is missing or unsafe"* ]]
        [[ ! -e "$marker" ]]
    done
}

@test "invoke: fixed trust list exactly covers every transitive control-plane module" {
    run python3 - "$PROJECT_ROOT/bin/mainframe" \
        "$PROJECT_ROOT/control_plane/mainframe_control_plane" <<'PY'
import ast
import re
import sys
from pathlib import Path

launcher = Path(sys.argv[1]).read_text(encoding="utf-8")
package = Path(sys.argv[2])
region = launcher.split("for _mainframe_cli_control_module in", 1)[1].split("; do", 1)[0]
trusted = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*\.py", region))
production = {path.name for path in package.glob("*.py")}

reachable = {"__init__.py", "cli.py"}
pending = list(reachable)
while pending:
    name = pending.pop()
    tree = ast.parse((package / name).read_text(encoding="utf-8"), filename=name)
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.level:
            if node.module:
                candidate = node.module.split(".", 1)[0] + ".py"
                if candidate in production and candidate not in reachable:
                    reachable.add(candidate)
                    pending.append(candidate)
            else:
                for alias in node.names:
                    candidate = alias.name.split(".", 1)[0] + ".py"
                    if candidate in production and candidate not in reachable:
                        reachable.add(candidate)
                        pending.append(candidate)

assert trusted == reachable, (
    "fixed trust closure mismatch",
    {"missing": sorted(reachable - trusted), "extra": sorted(trusted - reachable)},
)
print("control_plane_trust_closure=exact")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "control_plane_trust_closure=exact" ]]
}

@test "invoke: near-limit broker output preserves exact envelope without argv overflow" {
    local response

    run run_hidden_with_clean_liveness env TMPDIR="$BATS_TEST_TMPDIR" \
        XDG_STATE_HOME="$BATS_TEST_TMPDIR/near-limit-state" \
        "$FIXTURE_ROOT/bin/mainframe" __kernel-stable-core-broker-v1 \
        mf:std:fixture:durable_near_limit \
        --input-json - --profile stable-core \
        --format broker-json-v1 --caller control-plane <<<'{}'

    [[ "$status" -eq 0 ]]
    response="$output"
    run jq -e '
        .ok == true and .exit_code == 0 and .stderr_b64 == "" and
        (.stdout_b64 | @base64d | length) == 60000
    ' <<<"$response"
    [[ "$status" -eq 0 ]]
}

@test "invoke: SIGKILL during input capture leaves no sentinel in TMPDIR or state" {
    local input_fifo="$BATS_TEST_TMPDIR/slow-input.fifo"
    local input_hold="$BATS_TEST_TMPDIR/hold-input-writer.fifo"
    local liveness_fifo="$BATS_TEST_TMPDIR/input-liveness.fifo"
    local liveness_hold="$BATS_TEST_TMPDIR/hold-liveness-writer.fifo"
    local scan_tmp="$BATS_TEST_TMPDIR/input-scan-tmp"
    local state="$BATS_TEST_TMPDIR/input-state"
    local fed="$BATS_TEST_TMPDIR/sentinel-fed"
    local sentinel="inner-input-crash-sentinel-$RANDOM"
    local adapter_pid producer_pid writer_pid attempt=0 adapter_rc=0 residue

    mkdir -p "$scan_tmp" "$state"
    chmod 0700 "$scan_tmp" "$state"
    mkfifo "$input_fifo" "$input_hold" "$liveness_fifo" "$liveness_hold"
    # Model the worker-owned liveness writer independently of the slow input.
    # shellcheck disable=SC2016
    "$BASH_BIN" --noprofile --norc -c '
        exec 3>"$1"
        IFS= read -r _ <"$2"
    ' bash "$liveness_fifo" "$liveness_hold" &
    writer_pid=$!
    # shellcheck disable=SC2016
    "$BASH_BIN" --noprofile --norc -c '
        exec 3>"$1"
        printf "{\"marker\":\"%s" "$4" >&3
        : >"$2"
        IFS= read -r _ <"$3"
    ' bash "$input_fifo" "$fed" "$input_hold" "$sentinel" &
    producer_pid=$!

    env TMPDIR="$scan_tmp" XDG_STATE_HOME="$state" /usr/bin/python3 -c '
import os
import sys
source_fd = os.open(sys.argv[1], os.O_RDONLY)
os.dup2(source_fd, 198, inheritable=True)
if source_fd != 198:
    os.close(source_fd)
os.setsid()
os.execv(sys.argv[2], sys.argv[2:])
' "$liveness_fifo" "$FIXTURE_ROOT/bin/mainframe" \
        __kernel-stable-core-broker-v1 \
        mf:std:fixture:durable_fixture --input-json - \
        --profile stable-core --format broker-json-v1 --caller control-plane \
        <"$input_fifo" >/dev/null 2>&1 &
    adapter_pid=$!

    while [[ ! -e "$fed" && $attempt -lt 200 ]]; do
        /bin/sleep 0.01
        attempt=$((attempt + 1))
    done
    /bin/sleep 0.05
    kill -KILL "$writer_pid" 2>/dev/null || true
    kill -TERM "$producer_pid" 2>/dev/null || true
    wait "$writer_pid" 2>/dev/null || true
    wait "$producer_pid" 2>/dev/null || true
    if wait "$adapter_pid" 2>/dev/null; then
        adapter_rc=0
    else
        adapter_rc=$?
    fi

    [[ -e "$fed" ]]
    [[ "$adapter_rc" -eq 143 || "$adapter_rc" -eq 137 ]]
    run kill -0 "$adapter_pid"
    [[ "$status" -ne 0 ]]
    residue="$(rg --hidden --text --files-with-matches --fixed-strings \
        "$sentinel" "$scan_tmp" "$state" 2>/dev/null || true)"
    [[ -z "$residue" ]]
}

@test "invoke: liveness EOF terminates the adapter and canonical function groups" {
    local scan_tmp="$BATS_TEST_TMPDIR/liveness-scan-tmp"
    local state="$BATS_TEST_TMPDIR/liveness-state"
    local liveness_fifo="$BATS_TEST_TMPDIR/liveness.fifo"
    local hold_fifo="$BATS_TEST_TMPDIR/liveness-hold.fifo"
    local writer_ready="$BATS_TEST_TMPDIR/liveness-writer-ready"
    local function_pid_file="$BATS_TEST_TMPDIR/liveness-function-pid"
    local request="$BATS_TEST_TMPDIR/liveness-request.json"
    local sentinel="worker-sigkill-sentinel-$RANDOM"
    local writer_pid adapter_pid function_pid attempt=0 adapter_rc=0 residue

    mkdir -p "$scan_tmp" "$state"
    chmod 0700 "$scan_tmp" "$state"
    mkfifo "$liveness_fifo" "$hold_fifo"
    jq -cn --arg sentinel "$sentinel" --arg ready "$function_pid_file" \
        '{sentinel:$sentinel,ready:$ready}' >"$request"

    # This process models the worker-owned write end. SIGKILL is authoritative
    # EOF; no argv or environment value tells the adapter which FD to watch.
    # shellcheck disable=SC2016
    "$BASH_BIN" --noprofile --norc -c '
        exec 3>"$1"
        : >"$2"
        IFS= read -r _ <"$3"
    ' bash "$liveness_fifo" "$writer_ready" "$hold_fifo" &
    writer_pid=$!

    env TMPDIR="$scan_tmp" XDG_STATE_HOME="$state" /usr/bin/python3 -c '
import os
import sys
source_fd = os.open(sys.argv[1], os.O_RDONLY)
os.dup2(source_fd, 198, inheritable=True)
if source_fd != 198:
    os.close(source_fd)
os.setsid()
os.execv(sys.argv[2], sys.argv[2:])
' "$liveness_fifo" "$FIXTURE_ROOT/bin/mainframe" \
        __kernel-stable-core-broker-v1 \
        mf:std:fixture:durable_slow_output --input-json - \
        --profile stable-core --format broker-json-v1 --caller control-plane \
        <"$request" >/dev/null 2>&1 &
    adapter_pid=$!

    while [[ ! -s "$function_pid_file" && $attempt -lt 300 ]]; do
        /bin/sleep 0.01
        attempt=$((attempt + 1))
    done
    function_pid="$(<"$function_pid_file")"
    kill -KILL "$writer_pid" 2>/dev/null || true
    wait "$writer_pid" 2>/dev/null || true
    if wait "$adapter_pid" 2>/dev/null; then
        adapter_rc=0
    else
        adapter_rc=$?
    fi
    /bin/sleep 0.4

    [[ -e "$writer_ready" ]]
    [[ "$function_pid" =~ ^[0-9]+$ ]]
    [[ "$adapter_rc" -eq 143 || "$adapter_rc" -eq 137 ]]
    run kill -0 "$adapter_pid"
    [[ "$status" -ne 0 ]]
    run kill -0 "$function_pid"
    [[ "$status" -ne 0 ]]
    residue="$(rg --hidden --text --files-with-matches --fixed-strings \
        "$sentinel" "$scan_tmp" "$state" 2>/dev/null || true)"
    [[ -z "$residue" ]]
}

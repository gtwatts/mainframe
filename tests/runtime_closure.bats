#!/usr/bin/env bats

load 'test_helper'

@test "full loader entry points expose one runtime closure" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" MAINFRAME_QUIET=1 \
        BASH_BIN="${BATS_TEST_SHELL:-bash}" \
        "${BATS_TEST_SHELL:-bash}" --noprofile --norc -c '
            set -euo pipefail

            snapshot() {
                local mode="$1"
                env -i \
                    HOME="${HOME:-/tmp}" \
                    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
                    MAINFRAME_ROOT="$MAINFRAME_ROOT" MAINFRAME_QUIET=1 \
                    "$BASH_BIN" --noprofile --norc -c '\''
                        set -euo pipefail
                        case "$1" in
                            default) ;;
                            all) export MAINFRAME_LIBS=all ;;
                            full) export MAINFRAME_PROFILE=full ;;
                            load_all) export MAINFRAME_SKIP_AUTOLOAD=1 ;;
                            core_then_load_all) export MAINFRAME_LIBS=core ;;
                            *) exit 2 ;;
                        esac
                        source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
                        if [[ "$1" == load_all || "$1" == core_then_load_all ]]; then
                            mainframe_load_all >/dev/null 2>&1
                        fi
                        mainframe_loaded
                        printf "runtime_functions="
                        declare -f | cksum
                    '\'' _ "$mode"
            }

            reference="$(snapshot default)"
            for mode in all full load_all core_then_load_all; do
                candidate="$(snapshot "$mode")"
                [[ "$candidate" == "$reference" ]] || {
                    printf "loader mode %s does not match default\n" "$mode" >&2
                    diff -u \
                        <(printf "%s\n" "$reference") \
                        <(printf "%s\n" "$candidate") >&2 || true
                    exit 1
                }
            done
        '

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
}

@test "generated runtime closure is current" {
    run python3 "$MAINFRAME_ROOT/scripts/generate-runtime-closure.py" --check
    [[ "$status" -eq 0 ]]
}

@test "generated closure includes transitive load-time dependencies first" {
    run "${BATS_TEST_SHELL:-bash}" --noprofile --norc -c '
        set -euo pipefail
        source "$1/lib/runtime-closure.generated.bash"

        position() {
            local wanted="$1" index
            for ((index=0; index<${#_MAINFRAME_FULL_CLOSURE[@]}; index++)); do
                if [[ "${_MAINFRAME_FULL_CLOSURE[index]}" == "$wanted" ]]; then
                    printf "%s" "$index"
                    return 0
                fi
            done
            return 1
        }

        ansi_index=$(position ansi)
        json_index=$(position json)
        parallel_index=$(position parallel_v2)
        graph_index=$(position graph)
        uap_index=$(position uap)
        state_index=$(position state)
        agent_loop_index=$(position agent_loop)

        (( ansi_index < parallel_index ))
        (( json_index < parallel_index ))
        (( parallel_index < graph_index ))
        (( uap_index < agent_loop_index ))
        (( state_index < agent_loop_index ))
    ' _ "$MAINFRAME_ROOT"

    [[ "$status" -eq 0 ]]
}

@test "every configured load-time edge is present and dependency-first" {
    run python3 - \
        "$MAINFRAME_ROOT/config/runtime-closure.json" \
        "$MAINFRAME_ROOT/lib/runtime-closure.generated.bash" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    generated = handle.read()

match = re.search(
    r"_MAINFRAME_FULL_CLOSURE=\(\n(?P<body>.*?)\n\)",
    generated,
    re.DOTALL,
)
if match is None:
    raise SystemExit("generated full closure array is missing")

modules = [line.strip() for line in match.group("body").splitlines()]
positions = {module: index for index, module in enumerate(modules)}
if len(positions) != len(modules):
    raise SystemExit("generated full closure contains duplicate modules")

for owner, dependencies in config["load_time_dependencies"].items():
    if owner not in positions:
        raise SystemExit(f"load-time owner is absent from closure: {owner}")
    for dependency in dependencies:
        if dependency not in positions:
            raise SystemExit(f"load-time dependency is absent from closure: {dependency}")
        if positions[dependency] >= positions[owner]:
            raise SystemExit(f"dependency is not first: {dependency} -> {owner}")
PY

    [[ "$status" -eq 0 ]]
}

@test "conditional tool-time edges do not expand startup closure" {
    run python3 - "$MAINFRAME_ROOT/config/runtime-closure.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

tool_time = config["conditional_tool_time_dependencies"]
assert tool_time["orchestrate"] == ["leader"]
assert set(tool_time["awm"]) == {
    "embeddings",
    "awm_storage",
    "awm_stream",
    "awm_tiers",
}
PY
    [[ "$status" -eq 0 ]]

    run "${BATS_TEST_SHELL:-bash}" --noprofile --norc -c '
        set -euo pipefail
        source "$1/lib/runtime-closure.generated.bash"
        [[ " ${_MAINFRAME_FULL_CLOSURE[*]} " != *" leader "* ]]
    ' _ "$MAINFRAME_ROOT"
    [[ "$status" -eq 0 ]]
}

@test "runtime closure generator rejects duplicate modules" {
    local invalid_config="$BATS_TEST_TMPDIR/runtime-closure-invalid.json"

    run python3 - "$MAINFRAME_ROOT/config/runtime-closure.json" "$invalid_config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
config["tiers"]["standard"].append(config["tiers"]["core"][0])
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY
    [[ "$status" -eq 0 ]]

    run python3 "$MAINFRAME_ROOT/scripts/generate-runtime-closure.py" \
        --config "$invalid_config" \
        --output "$BATS_TEST_TMPDIR/runtime-closure.generated.bash" \
        --check

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"module appears more than once: pure-string"* ]]
}

@test "runtime closure generator rejects a missing dependency module" {
    local invalid_config="$BATS_TEST_TMPDIR/runtime-closure-missing.json"

    run python3 - "$MAINFRAME_ROOT/config/runtime-closure.json" "$invalid_config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
config["load_time_dependencies"]["missing_dependency"] = []
config["load_time_dependencies"]["graph"].append("missing_dependency")
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY
    [[ "$status" -eq 0 ]]

    run python3 "$MAINFRAME_ROOT/scripts/generate-runtime-closure.py" \
        --config "$invalid_config" \
        --output "$BATS_TEST_TMPDIR/runtime-closure.generated.bash"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"configured module does not exist:"*"/lib/missing_dependency.sh"* ]]
}

@test "runtime closure generator rejects an unknown dependency" {
    local invalid_config="$BATS_TEST_TMPDIR/runtime-closure-unknown.json"

    run python3 - "$MAINFRAME_ROOT/config/runtime-closure.json" "$invalid_config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
config["load_time_dependencies"]["graph"].append("unregistered_dependency")
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY
    [[ "$status" -eq 0 ]]

    run python3 "$MAINFRAME_ROOT/scripts/generate-runtime-closure.py" \
        --config "$invalid_config" \
        --output "$BATS_TEST_TMPDIR/runtime-closure.generated.bash"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unknown load-time dependency 'unregistered_dependency' required by 'graph'"* ]]
}

@test "runtime closure generator rejects a load-time dependency cycle" {
    local invalid_config="$BATS_TEST_TMPDIR/runtime-closure-cycle.json"

    run python3 - "$MAINFRAME_ROOT/config/runtime-closure.json" "$invalid_config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
config["load_time_dependencies"]["parallel_v2"].append("graph")
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY
    [[ "$status" -eq 0 ]]

    run python3 "$MAINFRAME_ROOT/scripts/generate-runtime-closure.py" \
        --config "$invalid_config" \
        --output "$BATS_TEST_TMPDIR/runtime-closure.generated.bash"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"load-time dependency cycle: graph -> parallel_v2 -> graph"* ]]
}

@test "common loader fails closed whenever generated closure is missing" {
    local fixture_lib="$BATS_TEST_TMPDIR/lib"
    mkdir -p "$fixture_lib"
    cp "$MAINFRAME_ROOT/lib/common.sh" "$fixture_lib/common.sh"

    run "${BATS_TEST_SHELL:-bash}" --noprofile --norc -c '
        set +e
        source "$1/common.sh" >/dev/null 2>&1
        first_status=$?
        source "$1/common.sh" >/dev/null 2>&1
        second_status=$?
        [[ "$first_status" -eq 78 && "$second_status" -eq 78 ]]
    ' _ "$fixture_lib"

    [[ "$status" -eq 0 ]]
}

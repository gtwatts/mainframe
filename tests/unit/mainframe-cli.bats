#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/mainframe-cli.bats - Function discovery CLI tests
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."
    MAINFRAME_BIN="${MAINFRAME_ROOT}/bin/mainframe"
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_ROOT
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "mainframe help rejects a function with multiple registry owners" {
    local stderr_file="${TEST_TMPDIR}/stderr"

    run bash --noprofile --norc -c '"$1" help path_join 2>"$2"' \
        _ "$MAINFRAME_BIN" "$stderr_file"

    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]

    local error_output
    error_output="$(<"$stderr_file")"
    [[ "$error_output" == *"function 'path_join' has multiple registry owners"* ]]
    [[ "$error_output" == *"  - path"* ]]
    [[ "$error_output" == *"  - pure-file"* ]]
    [[ "$error_output" != *"arithmetic syntax error"* ]]
}

@test "mainframe help formats a uniquely owned registry function" {
    run "$MAINFRAME_BIN" help json_object

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"json_object"* ]]
    [[ "$output" == *"Library:     json (lib/json.sh)"* ]]
    [[ "$output" == *"Signature:"* ]]
    [[ "$output" != *"multiple registry owners"* ]]
    [[ "$output" != *"arithmetic syntax error"* ]]
}

@test "mainframe search understands a multi-word capability and ranks canonical safe metadata" {
    run "$MAINFRAME_BIN" search "create json object"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Canonical functions matching 'create json object':"* ]]
    [[ "$output" == *"json_object - json [risk=low, stable-core, pure, idempotent]"* ]]
    [[ "$output" == *"Create JSON object from key=value pairs"* ]]
    [[ "$output" == *"Safety labels are discovery hints, not authorization."* ]]
}

@test "mainframe search never recommends a name that canonical help rejects" {
    run "$MAINFRAME_BIN" search "ci detect"

    [[ "$output" != *"ci::detect"* ]]
    [[ "$output" != *"agent_register - agent"* ]]
}

@test "mainframe search treats user text literally instead of as a regular expression" {
    run "$MAINFRAME_BIN" search '(?invalid'

    [[ "$status" -ne 0 ]]
    [[ "$output" == "No canonical functions matching '(?invalid'" ]]
    [[ "$output" != *"unable to read canonical discovery metadata"* ]]
}

@test "mainframe quickref dispatch preserves the search term" {
    run "$MAINFRAME_BIN" quickref --search json_object

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"json_object"* ]]
    [[ "$output" != *"Usage: mainframe quickref --search <term>"* ]]
}

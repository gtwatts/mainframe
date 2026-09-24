#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    umask 077
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-pi-product.XXXXXX")"
    CLI="$PROJECT_ROOT/bin/mainframe"
}

teardown() {
    [[ -d "$TEST_ROOT" && "$TEST_ROOT" == */mainframe-pi-product.* ]] && rm -rf -- "$TEST_ROOT"
}

@test "Pi setup refuses another host before creating configuration" {
    run "$CLI" setup --project "$TEST_ROOT" --host codex --yes
    [ "$status" -eq 2 ]
    [[ "$output" == *"only Pi is supported"* ]]
    [ ! -e "$TEST_ROOT/.codex" ]
    [ ! -e "$TEST_ROOT/AGENTS.md" ]
}

@test "retired host activation requires explicit legacy selection" {
    run "$CLI" activate codex --project "$TEST_ROOT"
    [ "$status" -eq 64 ]
    [[ "$output" == *"frozen legacy command"* ]]
    [ ! -e "$TEST_ROOT/.codex" ]
}

@test "legacy command help is available without changing a project" {
    run "$CLI" legacy
    [ "$status" -eq 0 ]
    [[ "$output" == *"frozen, unsupported"* ]]
}

@test "status discovers Pi from caller PATH as data without executing it" {
    mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home"
    printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/bin/pi"
    chmod 700 "$TEST_ROOT/bin/pi"
    run env HOME="$TEST_ROOT/home" PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
        "$CLI" status --json
    [ "$status" -eq 2 ]
    [[ "$(jq -r '.overall.state' <<< "$output")" == compatibility-unverified ]]
    [[ "$(jq -r '.pi.cli_path' <<< "$output")" == "$TEST_ROOT/bin/pi" ]]
    [[ "$(jq -r '.pi.executed' <<< "$output")" == false ]]
}

@test "Pi setup rejects legacy runtime acquisition options" {
    run "$CLI" setup --project "$TEST_ROOT" --runtime managed --yes
    [ "$status" -eq 2 ]
    [[ "$output" == *"legacy multi-agent option"* ]]
}

@test "Pi setup proof cannot be combined with apply" {
    run "$CLI" setup --project "$TEST_ROOT" --proof --yes
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot be combined"* ]]
}

@test "Pi setup refuses conflicting preview and apply" {
    run "$CLI" setup --project "$TEST_ROOT" --dry-run --yes
    [ "$status" -eq 2 ]
    [[ "$output" == *"choose exactly one"* ]]
}

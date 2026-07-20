#!/usr/bin/env bats

# Smoke tests for the current output.sh API surface.

load 'test_helper'

_output_test_stdout() {
    printf 'hello:%s' "${1:-world}"
}

_output_test_stderr() {
    printf 'warning:%s\n' "${1:-none}" >&2
    return 7
}

setup() {
    source_lib "output"
    export MAINFRAME_OUTPUT="raw"
}

teardown() {
    unset MAINFRAME_OUTPUT
}

@test "MAINFRAME_OUTPUT defaults to raw" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; printf "%s" "$MAINFRAME_OUTPUT"'
    [ "$status" -eq 0 ]
    [ "$output" = "raw" ]
}

@test "output_format reports raw mode by default" {
    run output_format
    [ "$status" -eq 0 ]
    [ "$output" = "raw" ]
}

@test "output_is_json reflects json mode" {
    MAINFRAME_OUTPUT="json"
    run output_is_json
    [ "$status" -eq 0 ]
}

@test "output_json_string aliases the documented helper name" {
    run output_json_string 'key "1"' 'say "hi"'
    [ "$status" -eq 0 ]
    [ "$output" = '"key \"1\"":"say \"hi\""' ]
}

@test "output_success returns raw data in raw mode" {
    run output_success "plain text" "ignored hint"
    [ "$status" -eq 0 ]
    [ "$output" = "plain text" ]
}

@test "output_success emits current JSON envelope in json mode" {
    MAINFRAME_OUTPUT="json"
    run output_success 'hello "world"' "next_step"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"ok":true,'* ]]
    [[ "$output" == *'"data":"hello \"world\""'* ]]
    [[ "$output" == *'"hint":"next_step"'* ]]
}

@test "output_error emits current JSON error envelope in json mode" {
    MAINFRAME_OUTPUT="json"
    run output_error "E_NOT_FOUND" "File not found" "check path"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"ok":false,'* ]]
    [[ "$output" == *'"code":"E_NOT_FOUND"'* ]]
    [[ "$output" == *'"msg":"File not found"'* ]]
    [[ "$output" == *'"suggestion":"check path"'* ]]
}

@test "output_list emits legacy array envelope" {
    run output_list "a" "b" "c"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":["a","b","c"],"count":3}' ]
}

@test "output_object accepts alternating key value pairs" {
    run output_object "name" "mainframe" "status" "green"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"name":"mainframe","status":"green"}}' ]
}

@test "output_progress emits progress envelope" {
    run output_progress "compile" 2 5 "building"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"progress","step":"compile","current":2,"total":5,"message":"building"}' ]
}

@test "mainframe_call wraps stdout for successful functions" {
    run mainframe_call _output_test_stdout "agent"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'"function":"_output_test_stdout"'* ]]
    [[ "$output" == *'"data":"hello:agent"'* ]]
}

@test "mainframe_call captures stderr and exit code for failures" {
    run mainframe_call _output_test_stderr "disk"
    [ "$status" -eq 7 ]
    [[ "$output" == *'"status":"error"'* ]]
    [[ "$output" == *'"stderr":"warning:disk"'* ]]
    [[ "$output" == *'"exit_code":7'* ]]
}

@test "output_auto prefers JSON payload in json mode" {
    MAINFRAME_OUTPUT="json"
    run output_auto "plain" '{"ok":true}'
    [ "$status" -eq 0 ]
    [ "$output" = '{"ok":true}' ]
}

@test "output_success_legacy preserves the old envelope shape" {
    run output_success_legacy "legacy data" "legacy message"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":"legacy data","message":"legacy message"}' ]
}

@test "output_error_legacy preserves the old envelope shape" {
    run output_error_legacy "legacy error" 9 "while testing"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"error","error":"legacy error","code":9,"context":"while testing"}' ]
}

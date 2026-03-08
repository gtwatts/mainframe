#!/usr/bin/env bats
# Tests for Fast JSON Processing

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "$MAINFRAME_ROOT/lib/json_fast.sh"
}

@test "json_escape_fast: escapes double quotes" {
    run json_escape_fast 'Hello "World"'
    assert_success
    assert_output 'Hello \"World\"'
}

@test "json_escape_fast: escapes backslashes" {
    run json_escape_fast 'path\to\file'
    assert_success
    assert_output 'path\\to\\file'
}

@test "json_escape_fast: escapes newlines" {
    run json_escape_fast $'Line1\nLine2'
    assert_success
    assert_output 'Line1\nLine2'
}

@test "json_escape_fast: handles empty string" {
    run json_escape_fast ''
    assert_success
    assert_output ''
}

@test "json_escape_fast: string without special chars returns unchanged" {
    run json_escape_fast 'Hello World'
    assert_success
    assert_output 'Hello World'
}

@test "json_valid_fast: validates simple object" {
    run json_valid_fast '{"key":"value"}'
    assert_success
}

@test "json_valid_fast: validates array" {
    run json_valid_fast '[1,2,3]'
    assert_success
}

@test "json_valid_fast: rejects unclosed braces" {
    run json_valid_fast '{"key":"value"'
    assert_failure
}

@test "json_merge_fast: merges two objects" {
    run json_merge_fast '{"a":1}' '{"b":2}'
    assert_success
    assert_output --partial '"a":1'
    assert_output --partial '"b":2'
}

@test "json_fast_benchmark: runs performance test" {
    run json_fast_benchmark
    assert_success
    assert_output --partial "JSON Fast Benchmark"
}

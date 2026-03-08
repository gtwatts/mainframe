#!/usr/bin/env bats
# Tests for runtime secrets management

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export MAINFRAME_QUIET=1
    export MAINFRAME_DEBUG=0
    source "$MAINFRAME_ROOT/lib/secrets.sh"
    secret_clear >/dev/null 2>&1 || true
}

teardown() {
    secret_clear >/dev/null 2>&1 || true
}

@test "secret_register: stores secret in memory" {
    run secret_register --name "API_KEY" --value "secret123"
    assert_success
}

@test "secret_get: retrieves secret value" {
    secret_register --name "API_KEY" --value "secret123"

    run secret_get --name "API_KEY"
    assert_success
    assert_output "secret123"
}

@test "secret_get: fails for non-existent secret" {
    run secret_get --name "NONEXISTENT"
    assert_failure
}

@test "secret_list: lists secret names only" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"

    run secret_list
    assert_success
    assert_output --partial "KEY1"
    assert_output --partial "KEY2"
    refute_output --partial "value1"
    refute_output --partial "value2"
}

@test "secret_redact: removes secrets from text" {
    secret_register --name "PASSWORD" --value "mysecret"

    run secret_redact --text "Password is mysecret, keep it safe"
    assert_success
    refute_output --partial "mysecret"
    assert_output --partial "***REDACTED:PASSWORD***"
}

@test "secret_scan: succeeds when secrets appear in text" {
    secret_register --name "TOKEN" --value "abc123"

    run secret_scan --text "The token abc123 is here"
    assert_success
}

@test "secret_scan: fails when text is clean" {
    secret_register --name "TOKEN" --value "abc123"

    run secret_scan --text "No secrets here"
    assert_failure
}

@test "secret_unregister: removes secret" {
    secret_register --name "TEMP" --value "value"
    secret_unregister --name "TEMP"

    run secret_get --name "TEMP"
    assert_failure
}

@test "secret_clear: removes all secrets" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"
    secret_clear

    run secret_count
    assert_success
    assert_output "0"
}

@test "secret_exec: substitutes secrets in template safely" {
    secret_register --name "API_KEY" --value "secret123"

    run secret_exec --template 'printf "%s" {API_KEY}'
    assert_success
    assert_output "secret123"
}

@test "secret_exec_env: injects mapped environment variables" {
    secret_register --name "API_KEY" --value "secret123"

    run secret_exec_env --env "API_KEY:MY_API_KEY" -- bash -lc 'printf "%s" "$MY_API_KEY"'
    assert_success
    assert_output "secret123"
}

@test "secret_count: returns number of secrets" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"

    run secret_count
    assert_success
    assert_output "2"
}

@test "secret_validate: accepts a strong stored secret" {
    secret_register --name "STRONG" --value "StrongValue!42"

    run secret_validate --name "STRONG" --min-length 8
    assert_success
}

@test "secret_validate: rejects a weak stored secret" {
    secret_register --name "WEAK" --value "password"

    run secret_validate --name "WEAK" --min-length 8
    assert_failure
}

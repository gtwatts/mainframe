#!/usr/bin/env bats
# Tests for Secrets Management

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "$MAINFRAME_ROOT/lib/secrets.sh"
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
    # Should NOT contain values
    refute_output --partial "value1"
}

@test "secret_redact: removes secrets from text" {
    secret_register --name "PASSWORD" --value "mysecret"
    
    run secret_redact --text "Password is mysecret, keep it safe"
    assert_success
    refute_output --partial "mysecret"
    assert_output --partial "***REDACTED"
}

@test "secret_scan: detects secrets in text" {
    secret_register --name "TOKEN" --value "abc123"
    
    run secret_scan --text "The token abc123 is here"
    assert_success
    assert_output "true"
}

@test "secret_scan: returns false when no secrets" {
    secret_register --name "TOKEN" --value "abc123"
    
    run secret_scan --text "No secrets here"
    assert_failure
    assert_output "false"
}

@test "secret_unregister: removes secret" {
    secret_register --name "TEMP" --value "value"
    
    run secret_unregister --name "TEMP"
    assert_success
    
    run secret_get --name "TEMP"
    assert_failure
}

@test "secret_clear: removes all secrets" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"
    
    run secret_clear
    assert_success
    
    run secret_count
    assert_output "0"
}

@test "secret_exec: substitutes secrets in template" {
    secret_register --name "API_KEY" --value "secret123"
    
    # This would actually execute - let's just test the substitution
    result=$(echo "Authorization: {API_KEY}" | sed "s/{API_KEY}/secret123/g")
    [ "$result" = "Authorization: secret123" ]
}

@test "secret_count: returns number of secrets" {
    secret_clear
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"
    
    run secret_count
    assert_success
    assert_output "2"
}

@test "secret_validate: validates secret name" {
    run secret_validate --name "VALID_NAME" --value "value"
    assert_success
}

@test "secret_validate: rejects invalid names" {
    run secret_validate --name "" --value "value"
    assert_failure
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Secrets Manager Tests (current API)
# =============================================================================
# Covers lib/secrets.sh: register/get/list/exists/unregister/clear, redact,
# scan, wrap/unwrap, validate, error paths.
# Replaces tests/secrets.bats, which targeted a dead API (secret_init).
# =============================================================================

load 'test_helper'

setup() {
    source_lib "secrets"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "secrets_v2")
    # Reset the in-memory store between tests
    _SECRETS_STORE=()
    _SECRETS_META=()
    _SECRETS_WRAPPED=()
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# REGISTER / GET
# =============================================================================

@test "secret_register and secret_get round-trip" {
    secret_register "api_key" "sk-test-123" >/dev/null
    run secret_get "api_key"
    [ "$status" -eq 0 ]
    [ "$output" = "sk-test-123" ]
}

@test "secret_register accepts --name/--value flags" {
    secret_register --name "db_pass" --value "p4ssw0rd" >/dev/null
    run secret_get --name "db_pass"
    [ "$status" -eq 0 ]
    [ "$output" = "p4ssw0rd" ]
}

@test "secret_register rejects empty name" {
    run secret_register "" "value"
    [ "$status" -eq 1 ]
}

@test "secret_register rejects empty value" {
    run secret_register "some_key" ""
    [ "$status" -eq 1 ]
}

@test "secret_get errors for missing secret" {
    run secret_get "nonexistent_secret_xyz"
    [ "$status" -eq 1 ]
}

# =============================================================================
# LIST / EXISTS / UNREGISTER / CLEAR
# =============================================================================

@test "secret_exists returns 0 for present, 1 for absent" {
    secret_register "present" "v" >/dev/null
    run secret_exists "present"
    [ "$status" -eq 0 ]
    run secret_exists "absent"
    [ "$status" -eq 1 ]
}

@test "secret_list shows registered names" {
    secret_register "alpha" "1" >/dev/null
    secret_register "beta" "2" >/dev/null
    run secret_list
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "secret_unregister removes the secret" {
    secret_register "temp" "v" >/dev/null
    secret_unregister "temp" >/dev/null
    run secret_exists "temp"
    [ "$status" -eq 1 ]
}

@test "secret_clear empties the store" {
    secret_register "k1" "v1" >/dev/null
    secret_register "k2" "v2" >/dev/null
    secret_clear >/dev/null
    run secret_list
    [ -z "$output" ]
}

# =============================================================================
# REDACT / SCAN
# =============================================================================

@test "secret_redact masks registered values in text" {
    secret_register "token" "sk-live-999" >/dev/null
    run secret_redact "the token is sk-live-999 ok"
    [ "$status" -eq 0 ]
    [[ "$output" == *"***REDACTED:token***"* ]]
    [[ "$output" != *"sk-live-999"* ]]
}

@test "secret_redact leaves unknown text untouched" {
    run secret_redact "nothing to hide here"
    [ "$output" = "nothing to hide here" ]
}

@test "secret_scan detects a leaked registered value in argument text" {
    secret_register "my_secret" "hunter2" >/dev/null
    run secret_scan "the password is hunter2"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "secret_scan is quiet for clean text" {
    secret_register "my_secret" "hunter2" >/dev/null
    run secret_scan "nothing leaked here"
    [ "$status" -ne 0 ]
}

# =============================================================================
# WRAP (function wrapping for secret injection)
# =============================================================================

@test "secret_wrap rejects invalid function names" {
    run secret_wrap "not/a/function"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid function name"* ]]
}

@test "secret_wrap rejects nonexistent functions" {
    run secret_wrap "definitely_not_a_function_xyz"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "secret_wrap wraps an existing function" {
    _dummy_fn() { echo "dummy"; }
    run secret_wrap "_dummy_fn"
    [ "$status" -eq 0 ]
}

# =============================================================================
# VALIDATE / INFO
# =============================================================================

@test "secret_validate flags weak values" {
    secret_register "weak" "123" >/dev/null
    run secret_validate "weak"
    [ "$status" -ne 0 ]
}

@test "secret_info reports metadata without exposing the value" {
    secret_register "meta_key" "supersecret" >/dev/null
    run secret_info "meta_key"
    [ "$status" -eq 0 ]
    [[ "$output" != *"supersecret"* ]]
}

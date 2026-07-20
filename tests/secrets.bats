#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Runtime Secrets Integration Tests
# =============================================================================

load 'test_helper'

setup() {
    export MAINFRAME_QUIET=1
    export MAINFRAME_DEBUG=0
    source_lib "secrets"
    TEST_DIR=$(create_test_dir "secrets")
    secret_clear >/dev/null 2>&1 || true
}

teardown() {
    secret_clear >/dev/null 2>&1 || true
    cleanup_test_dir "$TEST_DIR"
}

@test "secret_register and secret_get roundtrip" {
    secret_register --name "API_KEY" --value "secret123"

    result=$(secret_get --name "API_KEY")
    [ "$result" = "secret123" ]
}

@test "secret_register rejects invalid names" {
    run secret_register --name "api-key" --value "secret123"
    [ "$status" -eq 1 ]
}

@test "secret_register rejects values with newlines" {
    run secret_register --name "API_KEY" --value $'line1\nline2'
    [ "$status" -eq 1 ]
}

@test "secret_register overwrites existing value" {
    secret_register --name "API_KEY" --value "old-value"
    secret_register --name "API_KEY" --value "new-value"

    result=$(secret_get --name "API_KEY")
    [ "$result" = "new-value" ]
}

@test "secret_list returns names without secret values" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"

    run secret_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"KEY1"* ]]
    [[ "$output" == *"KEY2"* ]]
    [[ "$output" != *"value1"* ]]
    [[ "$output" != *"value2"* ]]
}

@test "secret_exists and secret_unregister update membership" {
    secret_register --name "TEMP" --value "value"
    secret_exists --name "TEMP"

    secret_unregister --name "TEMP"
    ! secret_exists --name "TEMP"
}

@test "secret_redact masks multiple registered secrets" {
    secret_register --name "DB_PASS" --value "hunter2"
    secret_register --name "API_KEY" --value "token-123"

    result=$(secret_redact --text "db=hunter2 api=token-123")
    [[ "$result" == *"***REDACTED:DB_PASS***"* ]]
    [[ "$result" == *"***REDACTED:API_KEY***"* ]]
    [[ "$result" != *"hunter2"* ]]
    [[ "$result" != *"token-123"* ]]
}

@test "secret_scan uses exit status for detection" {
    secret_register --name "TOKEN" --value "abc123"

    run secret_scan --text "contains abc123"
    [ "$status" -eq 0 ]

    run secret_scan --text "contains nothing sensitive"
    [ "$status" -eq 1 ]
}

@test "secret_exec runs template with secret substitution" {
    secret_register --name "API_KEY" --value "secret123"

    run secret_exec --template 'printf "%s" {API_KEY}'
    [ "$status" -eq 0 ]
    [ "$output" = "secret123" ]
}

@test "secret_exec fails on unreplaced placeholder" {
    run secret_exec --template 'printf "%s" {MISSING_SECRET}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"unreplaced placeholder"* ]]
}

@test "secret_exec dry-run redacts secret values" {
    secret_register --name "API_KEY" --value "secret123"

    run secret_exec --dry-run --template 'curl -H "Authorization: Bearer {API_KEY}" https://example.com'
    [ "$status" -eq 0 ]
    [[ "$output" == *"***REDACTED***"* ]]
    [[ "$output" != *"secret123"* ]]
}

@test "secret_exec_env injects and cleans environment variables" {
    local output_file="$TEST_DIR/env.out"

    secret_register --name "API_KEY" --value "secret123"
    secret_exec_env --env "API_KEY:MY_API_KEY" -- bash -lc 'printf "%s" "$MY_API_KEY"' > "$output_file"

    [ "$(<"$output_file")" = "secret123" ]
    [ -z "${MY_API_KEY:-}" ]
}

@test "secret_wrap redacts wrapped output" {
    secret_register --name "TOKEN" --value "abc123"

    leak_token() {
        printf 'token=%s' "abc123"
    }

    secret_wrap leak_token
    result=$(leak_token)

    [[ "$result" == *"***REDACTED:TOKEN***"* ]]
    [[ "$result" != *"abc123"* ]]
}

@test "secret_unwrap restores original output" {
    secret_register --name "TOKEN" --value "abc123"

    leak_token() {
        printf 'token=%s' "abc123"
    }

    secret_wrap leak_token
    secret_unwrap leak_token
    result=$(leak_token)

    [ "$result" = "token=abc123" ]
}

@test "secret_clear resets the store" {
    secret_register --name "KEY1" --value "value1"
    secret_register --name "KEY2" --value "value2"
    secret_clear

    [ "$(secret_count)" = "0" ]
    ! secret_exists --name "KEY1"
    ! secret_exists --name "KEY2"
}

@test "secret_validate distinguishes strong and weak secrets" {
    secret_register --name "STRONG" --value "StrongValue!42"
    secret_register --name "WEAK" --value "password"

    secret_validate --name "STRONG" --min-length 8
    ! secret_validate --name "WEAK" --min-length 8
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Secrets Module Tests
# =============================================================================
# Tests for lib/secrets.sh
# Covers: initialization, storage, encryption, key management, rotation,
#         audit logging, environment integration, and utilities
# =============================================================================

load 'test_helper'

setup() {
    source_lib "secrets"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "secrets")

    # Override secrets directory for testing
    export MAINFRAME_SECRETS_DIR="$TEST_DIR/secrets"
    export MAINFRAME_SECRETS_AUDIT="$TEST_DIR/secrets/audit.log"
    export MAINFRAME_SECRETS_POLICY="$TEST_DIR/secrets/policy.json"
    export MAINFRAME_SECRETS_BACKUP_DIR="$TEST_DIR/secrets/backups"

    # Test password for initialization
    TEST_PASSWORD="test-master-password-12345"
}

teardown() {
    # Clear master key
    secret_clear_master_key 2>/dev/null || true
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# INITIALIZATION TESTS
# =============================================================================

@test "secret_init creates secrets directory structure" {
    secret_init "$TEST_PASSWORD"

    [ -d "$MAINFRAME_SECRETS_DIR" ]
    [ -d "$MAINFRAME_SECRETS_DIR/data" ]
    [ -d "$MAINFRAME_SECRETS_DIR/meta" ]
}

@test "secret_init creates salt file" {
    secret_init "$TEST_PASSWORD"

    [ -f "$MAINFRAME_SECRETS_DIR/salt" ]

    # Salt should be 64 hex chars (32 bytes)
    local salt
    salt=$(<"$MAINFRAME_SECRETS_DIR/salt")
    [ ${#salt} -eq 64 ]
    [[ "$salt" =~ ^[0-9a-f]+$ ]]
}

@test "secret_init creates key check file" {
    secret_init "$TEST_PASSWORD"

    [ -f "$MAINFRAME_SECRETS_DIR/key_check" ]
}

@test "secret_init is idempotent with correct password" {
    secret_init "$TEST_PASSWORD"

    local salt1
    salt1=$(<"$MAINFRAME_SECRETS_DIR/salt")

    # Reinitialize with same password should succeed
    secret_init "$TEST_PASSWORD"

    local salt2
    salt2=$(<"$MAINFRAME_SECRETS_DIR/salt")

    [ "$salt1" = "$salt2" ]
}

@test "secret_init fails with wrong password on reinitialization" {
    secret_init "$TEST_PASSWORD"

    run secret_init "wrong-password"
    [ "$status" -eq 1 ]
}

@test "secret_init fails with empty password" {
    run secret_init ""
    [ "$status" -eq 1 ]
}

@test "secret_init sets secure permissions on directories" {
    secret_init "$TEST_PASSWORD"

    local perms
    perms=$(stat -c %a "$MAINFRAME_SECRETS_DIR" 2>/dev/null || stat -f %Lp "$MAINFRAME_SECRETS_DIR")
    [ "$perms" = "700" ]
}

# =============================================================================
# SECRET STORAGE TESTS
# =============================================================================

@test "secret_store stores encrypted secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "test_secret" "test_value"

    [ -f "$MAINFRAME_SECRETS_DIR/data/test_secret.enc" ]
}

@test "secret_store creates metadata file" {
    secret_init "$TEST_PASSWORD"
    secret_store "test_secret" "test_value" "Test description"

    [ -f "$MAINFRAME_SECRETS_DIR/meta/test_secret.json" ]

    # Check metadata contains expected fields
    local meta
    meta=$(<"$MAINFRAME_SECRETS_DIR/meta/test_secret.json")
    [[ "$meta" == *'"name":"test_secret"'* ]]
    [[ "$meta" == *'"description":"Test description"'* ]]
}

@test "secret_store fails without master key" {
    run secret_store "test" "value"
    [ "$status" -eq 1 ]
}

@test "secret_store fails with empty name" {
    secret_init "$TEST_PASSWORD"

    run secret_store "" "value"
    [ "$status" -eq 1 ]
}

@test "secret_store fails with empty value" {
    secret_init "$TEST_PASSWORD"

    run secret_store "name" ""
    [ "$status" -eq 1 ]
}

@test "secret_store sanitizes name with special characters" {
    secret_init "$TEST_PASSWORD"
    secret_store "test/secret:name" "value"

    # Should be sanitized to safe filename
    [ -f "$MAINFRAME_SECRETS_DIR/data/test_secret_name.enc" ]
}

@test "secret_store overwrites existing secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "test_secret" "original_value"
    secret_store "test_secret" "new_value"

    local retrieved
    retrieved=$(secret_retrieve "test_secret")
    [ "$retrieved" = "new_value" ]
}

# =============================================================================
# SECRET RETRIEVAL TESTS
# =============================================================================

@test "secret_retrieve returns stored value" {
    secret_init "$TEST_PASSWORD"
    secret_store "my_secret" "my_value"

    local result
    result=$(secret_retrieve "my_secret")
    [ "$result" = "my_value" ]
}

@test "secret_retrieve fails for non-existent secret" {
    secret_init "$TEST_PASSWORD"

    run secret_retrieve "nonexistent"
    [ "$status" -eq 1 ]
}

@test "secret_retrieve fails without master key" {
    run secret_retrieve "test"
    [ "$status" -eq 1 ]
}

@test "secret_retrieve handles special characters in value" {
    secret_init "$TEST_PASSWORD"

    local special_value='!@#$%^&*()_+-=[]{}|;:",.<>?/\n\t'
    secret_store "special" "$special_value"

    local result
    result=$(secret_retrieve "special")
    [ "$result" = "$special_value" ]
}

@test "secret_retrieve handles long values" {
    secret_init "$TEST_PASSWORD"

    # Generate a long value (4KB)
    local long_value
    long_value=$(head -c 4096 /dev/urandom | base64)
    secret_store "long_secret" "$long_value"

    local result
    result=$(secret_retrieve "long_secret")
    [ "$result" = "$long_value" ]
}

@test "secret_retrieve updates access count" {
    secret_init "$TEST_PASSWORD"
    secret_store "counted" "value"

    # Retrieve multiple times
    secret_retrieve "counted" >/dev/null
    secret_retrieve "counted" >/dev/null
    secret_retrieve "counted" >/dev/null

    local count
    count=$(secret_access_count "counted")
    [ "$count" = "3" ]
}

# =============================================================================
# SECRET DELETION TESTS
# =============================================================================

@test "secret_delete removes secret file" {
    secret_init "$TEST_PASSWORD"
    secret_store "to_delete" "value"

    [ -f "$MAINFRAME_SECRETS_DIR/data/to_delete.enc" ]

    secret_delete "to_delete"

    [ ! -f "$MAINFRAME_SECRETS_DIR/data/to_delete.enc" ]
}

@test "secret_delete removes metadata file" {
    secret_init "$TEST_PASSWORD"
    secret_store "to_delete" "value"

    secret_delete "to_delete"

    [ ! -f "$MAINFRAME_SECRETS_DIR/meta/to_delete.json" ]
}

@test "secret_delete is idempotent" {
    secret_init "$TEST_PASSWORD"
    secret_store "to_delete" "value"

    secret_delete "to_delete"
    secret_delete "to_delete"  # Should not fail

    [ $? -eq 0 ]
}

@test "secret_delete succeeds for non-existent secret" {
    secret_init "$TEST_PASSWORD"

    secret_delete "nonexistent"
    [ $? -eq 0 ]
}

# =============================================================================
# SECRET_EXISTS TESTS
# =============================================================================

@test "secret_exists returns 0 for existing secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "exists" "value"

    secret_exists "exists"
    [ $? -eq 0 ]
}

@test "secret_exists returns 1 for non-existing secret" {
    secret_init "$TEST_PASSWORD"

    run secret_exists "nonexistent"
    [ "$status" -eq 1 ]
}

@test "secret_exists returns 1 for empty name" {
    run secret_exists ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# SECRET_LIST TESTS
# =============================================================================

@test "secret_list returns empty for new store" {
    secret_init "$TEST_PASSWORD"

    local result
    result=$(secret_list)
    [ -z "$result" ]
}

@test "secret_list returns stored secrets" {
    secret_init "$TEST_PASSWORD"
    secret_store "secret_a" "value_a"
    secret_store "secret_b" "value_b"
    secret_store "secret_c" "value_c"

    local result
    result=$(secret_list)

    [[ "$result" == *"secret_a"* ]]
    [[ "$result" == *"secret_b"* ]]
    [[ "$result" == *"secret_c"* ]]
}

@test "secret_list with --json returns JSON array" {
    secret_init "$TEST_PASSWORD"
    secret_store "json_test" "value"

    local result
    result=$(secret_list --json)

    [[ "$result" == '{"secrets":['* ]]
    [[ "$result" == *'"json_test"'* ]]
}

# =============================================================================
# SECRET_RENAME TESTS
# =============================================================================

@test "secret_rename renames secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "old_name" "value"

    secret_rename "old_name" "new_name"

    ! secret_exists "old_name"
    secret_exists "new_name"

    local result
    result=$(secret_retrieve "new_name")
    [ "$result" = "value" ]
}

@test "secret_rename fails if old secret doesn't exist" {
    secret_init "$TEST_PASSWORD"

    run secret_rename "nonexistent" "new_name"
    [ "$status" -eq 1 ]
}

@test "secret_rename fails if new name already exists" {
    secret_init "$TEST_PASSWORD"
    secret_store "old_name" "value1"
    secret_store "new_name" "value2"

    run secret_rename "old_name" "new_name"
    [ "$status" -eq 1 ]
}

# =============================================================================
# ENCRYPTION TESTS
# =============================================================================

@test "secret_encrypt returns encrypted data" {
    local result
    result=$(secret_encrypt "plaintext" "testkey123")

    [ -n "$result" ]
    [ "$result" != "plaintext" ]
}

@test "secret_encrypt output contains IV separator" {
    local result
    result=$(secret_encrypt "plaintext" "testkey123")

    [[ "$result" == *":"* ]]
}

@test "secret_decrypt decrypts encrypted data" {
    local encrypted decrypted
    encrypted=$(secret_encrypt "my secret message" "testkey456")
    decrypted=$(secret_decrypt "$encrypted" "testkey456")

    [ "$decrypted" = "my secret message" ]
}

@test "secret_decrypt fails with wrong key" {
    local encrypted
    encrypted=$(secret_encrypt "secret" "rightkey")

    run secret_decrypt "$encrypted" "wrongkey"
    [ "$status" -eq 1 ]
}

@test "secret_encrypt produces different output each time (random IV)" {
    local enc1 enc2
    enc1=$(secret_encrypt "same text" "samekey")
    enc2=$(secret_encrypt "same text" "samekey")

    [ "$enc1" != "$enc2" ]
}

# =============================================================================
# KEY DERIVATION TESTS
# =============================================================================

@test "secret_derive_key produces consistent output" {
    local key1 key2
    key1=$(secret_derive_key "password" "salt123")
    key2=$(secret_derive_key "password" "salt123")

    [ "$key1" = "$key2" ]
}

@test "secret_derive_key differs with different passwords" {
    local key1 key2
    key1=$(secret_derive_key "password1" "salt123")
    key2=$(secret_derive_key "password2" "salt123")

    [ "$key1" != "$key2" ]
}

@test "secret_derive_key differs with different salts" {
    local key1 key2
    key1=$(secret_derive_key "password" "salt1")
    key2=$(secret_derive_key "password" "salt2")

    [ "$key1" != "$key2" ]
}

@test "secret_generate_key produces 64 hex chars" {
    local key
    key=$(secret_generate_key)

    [ ${#key} -eq 64 ]
    [[ "$key" =~ ^[0-9a-f]+$ ]]
}

@test "secret_generate_key produces unique keys" {
    local key1 key2
    key1=$(secret_generate_key)
    key2=$(secret_generate_key)

    [ "$key1" != "$key2" ]
}

# =============================================================================
# HASH TESTS
# =============================================================================

@test "secret_hash produces 64 char hex output" {
    local hash
    hash=$(secret_hash "test data")

    [ ${#hash} -eq 64 ]
    [[ "$hash" =~ ^[0-9a-f]+$ ]]
}

@test "secret_hash is deterministic" {
    local h1 h2
    h1=$(secret_hash "same input")
    h2=$(secret_hash "same input")

    [ "$h1" = "$h2" ]
}

@test "secret_hash differs for different inputs" {
    local h1 h2
    h1=$(secret_hash "input1")
    h2=$(secret_hash "input2")

    [ "$h1" != "$h2" ]
}

# =============================================================================
# KEY MANAGEMENT TESTS
# =============================================================================

@test "secret_set_master_key sets key" {
    secret_set_master_key "testkey"

    # Should be able to use encryption after setting key
    local enc
    enc=$(secret_encrypt "test" "testkey")
    [ -n "$enc" ]
}

@test "secret_clear_master_key clears key" {
    secret_init "$TEST_PASSWORD"
    secret_clear_master_key

    # Should fail without key
    run secret_store "test" "value"
    [ "$status" -eq 1 ]
}

@test "secret_rotate_master_key re-encrypts secrets" {
    secret_init "$TEST_PASSWORD"
    secret_store "test1" "value1"
    secret_store "test2" "value2"

    secret_rotate_master_key "new-password-123"

    # Should still be able to retrieve with new key
    local v1 v2
    v1=$(secret_retrieve "test1")
    v2=$(secret_retrieve "test2")

    [ "$v1" = "value1" ]
    [ "$v2" = "value2" ]
}

# =============================================================================
# ROTATION & POLICY TESTS
# =============================================================================

@test "secret_rotate updates secret value" {
    secret_init "$TEST_PASSWORD"
    secret_store "rotatable" "old_value"

    secret_rotate "rotatable" "new_value"

    local result
    result=$(secret_retrieve "rotatable")
    [ "$result" = "new_value" ]
}

@test "secret_rotate increments version" {
    secret_init "$TEST_PASSWORD"
    secret_store "rotatable" "v1"

    secret_rotate "rotatable" "v2"
    secret_rotate "rotatable" "v3"

    local meta
    meta=$(<"$MAINFRAME_SECRETS_DIR/meta/rotatable.json")
    [[ "$meta" == *'"version":3'* ]]
}

@test "secret_set_expiry sets expiration" {
    secret_init "$TEST_PASSWORD"
    secret_store "expiring" "value"

    secret_set_expiry "expiring" "2099-12-31T23:59:59Z"

    local meta
    meta=$(<"$MAINFRAME_SECRETS_DIR/meta/expiring.json")
    [[ "$meta" == *'"expiry":"2099-12-31T23:59:59Z"'* ]]
}

@test "secret_set_expiry with duration format" {
    secret_init "$TEST_PASSWORD"
    secret_store "temp_secret" "value"

    secret_set_expiry "temp_secret" "+30d"

    local meta
    meta=$(<"$MAINFRAME_SECRETS_DIR/meta/temp_secret.json")
    [[ "$meta" == *'"expiry":'* ]]
}

@test "secret_check_expiry returns 0 for expired secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "expired" "value"

    # Set expiry in the past
    secret_set_expiry "expired" "2020-01-01T00:00:00Z"

    secret_check_expiry "expired"
    [ $? -eq 0 ]
}

@test "secret_check_expiry returns 1 for non-expired secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "valid" "value"

    secret_set_expiry "valid" "2099-12-31T23:59:59Z"

    run secret_check_expiry "valid"
    [ "$status" -eq 1 ]
}

@test "secret_list_expiring lists secrets expiring soon" {
    secret_init "$TEST_PASSWORD"
    secret_store "expiring_soon" "value"
    secret_set_expiry "expiring_soon" "+3d"

    local result
    result=$(secret_list_expiring 7)

    [[ "$result" == *"expiring_soon"* ]]
}

@test "secret_policy_set creates policy" {
    secret_init "$TEST_PASSWORD"

    secret_policy_set "db_password" '{"rotation_days":90}'

    [ -f "$MAINFRAME_SECRETS_POLICY" ]

    local policy
    policy=$(<"$MAINFRAME_SECRETS_POLICY")
    [[ "$policy" == *'"db_password"'* ]]
}

# =============================================================================
# AUDIT TESTS
# =============================================================================

@test "secret_audit_log creates audit entry" {
    secret_init "$TEST_PASSWORD"

    secret_audit_log "test_action" "test_target" "test_details"

    [ -f "$MAINFRAME_SECRETS_AUDIT" ]

    local entry
    entry=$(tail -1 "$MAINFRAME_SECRETS_AUDIT")
    [[ "$entry" == *'"action":"test_action"'* ]]
    [[ "$entry" == *'"target":"test_target"'* ]]
}

@test "secret_audit_list returns recent entries" {
    secret_init "$TEST_PASSWORD"
    secret_store "audited" "value"
    secret_retrieve "audited" >/dev/null

    local result
    result=$(secret_audit_list 10)

    [[ "$result" == *'"action":"store"'* ]]
    [[ "$result" == *'"action":"retrieve"'* ]]
}

@test "secret_audit_search finds matching entries" {
    secret_init "$TEST_PASSWORD"
    secret_store "searchable" "value"

    local result
    result=$(secret_audit_search "searchable")

    [[ "$result" == *'"target":"searchable"'* ]]
}

@test "secret_last_accessed returns timestamp" {
    secret_init "$TEST_PASSWORD"
    secret_store "accessed_secret" "value"
    secret_retrieve "accessed_secret" >/dev/null

    local timestamp
    timestamp=$(secret_last_accessed "accessed_secret")

    [ -n "$timestamp" ]
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "secret_access_count returns count" {
    secret_init "$TEST_PASSWORD"
    secret_store "count_test" "value"

    local count
    count=$(secret_access_count "count_test")
    [ "$count" = "0" ]

    secret_retrieve "count_test" >/dev/null

    count=$(secret_access_count "count_test")
    [ "$count" = "1" ]
}

# =============================================================================
# ENVIRONMENT INTEGRATION TESTS
# =============================================================================

@test "secret_to_env outputs export statement" {
    secret_init "$TEST_PASSWORD"
    secret_store "env_secret" "secret_value"

    local result
    result=$(secret_to_env "env_secret" "MY_SECRET")

    [[ "$result" == "export MY_SECRET="* ]]
    [[ "$result" == *"secret_value"* ]]
}

@test "secret_to_env with default env var name" {
    secret_init "$TEST_PASSWORD"
    secret_store "api-key" "the-key"

    local result
    result=$(secret_to_env "api-key")

    [[ "$result" == "export API_KEY="* ]]
}

@test "secret_from_env imports from environment" {
    secret_init "$TEST_PASSWORD"
    export TEST_ENV_VAR="env_value"

    secret_from_env "TEST_ENV_VAR" "from_env"

    local result
    result=$(secret_retrieve "from_env")
    [ "$result" = "env_value" ]

    unset TEST_ENV_VAR
}

@test "secret_from_env fails with empty env var" {
    secret_init "$TEST_PASSWORD"
    export EMPTY_VAR=""

    run secret_from_env "EMPTY_VAR"
    [ "$status" -eq 1 ]

    unset EMPTY_VAR
}

@test "secret_load_dotenv loads from .env file" {
    secret_init "$TEST_PASSWORD"

    # Create test .env file
    cat > "$TEST_DIR/.env" << 'EOF'
DB_PASSWORD=mysecretpassword
API_KEY=abc123def456
# This is a comment
EMPTY_LINE_ABOVE=value
QUOTED_VALUE="quoted string"
EOF

    secret_load_dotenv "$TEST_DIR/.env"

    local db_pass api_key quoted
    db_pass=$(secret_retrieve "db-password")
    api_key=$(secret_retrieve "api-key")
    quoted=$(secret_retrieve "quoted-value")

    [ "$db_pass" = "mysecretpassword" ]
    [ "$api_key" = "abc123def456" ]
    [ "$quoted" = "quoted string" ]
}

# =============================================================================
# UTILITY TESTS
# =============================================================================

@test "secret_random_password generates password of specified length" {
    local pass
    pass=$(secret_random_password 24)

    [ ${#pass} -eq 24 ]
}

@test "secret_random_password generates unique passwords" {
    local p1 p2
    p1=$(secret_random_password 16)
    p2=$(secret_random_password 16)

    [ "$p1" != "$p2" ]
}

@test "secret_random_password alphanumeric charset" {
    local pass
    pass=$(secret_random_password 100 "alphanumeric")

    [[ "$pass" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "secret_random_password special charset includes special chars" {
    # Generate many passwords to ensure special chars appear
    local has_special=false
    local i
    for i in $(seq 1 10); do
        local pass
        pass=$(secret_random_password 32 "special")
        if [[ "$pass" =~ [^a-zA-Z0-9] ]]; then
            has_special=true
            break
        fi
    done

    [ "$has_special" = "true" ]
}

@test "secret_strength_check returns weak for short password" {
    local result
    result=$(secret_strength_check "abc")

    [[ "$result" == *'"strength":"weak"'* ]]
}

@test "secret_strength_check returns strong for complex password" {
    local result
    result=$(secret_strength_check "MyStr0ng!P@ssw0rd#2024")

    [[ "$result" == *'"strength":"strong"'* ]] || [[ "$result" == *'"strength":"good"'* ]]
}

@test "secret_strength_check returns JSON with score" {
    local result
    result=$(secret_strength_check "Test123!")

    [[ "$result" == *'"score":'* ]]
    [[ "$result" == *'"details":'* ]]
}

# =============================================================================
# BACKUP & RESTORE TESTS
# =============================================================================

@test "secret_backup creates backup file" {
    secret_init "$TEST_PASSWORD"
    secret_store "backup_test" "backup_value"

    local backup_file
    backup_file=$(secret_backup)

    [ -f "$backup_file" ]
}

@test "secret_backup output is encrypted" {
    secret_init "$TEST_PASSWORD"
    secret_store "encrypted_backup" "sensitive_data"

    local backup_file
    backup_file=$(secret_backup)

    local content
    content=$(<"$backup_file")

    # Should not contain plaintext
    [[ "$content" != *"sensitive_data"* ]]
    [[ "$content" != *"encrypted_backup"* ]]
}

@test "secret_restore restores from backup" {
    secret_init "$TEST_PASSWORD"
    secret_store "restore_test" "restore_value"

    local backup_file
    backup_file=$(secret_backup)

    # Delete the secret
    secret_delete "restore_test"
    ! secret_exists "restore_test"

    # Restore
    secret_restore "$backup_file" "$TEST_PASSWORD"

    secret_exists "restore_test"

    local result
    result=$(secret_retrieve "restore_test")
    [ "$result" = "restore_value" ]
}

@test "secret_restore fails with wrong password" {
    secret_init "$TEST_PASSWORD"
    secret_store "protected" "value"

    local backup_file
    backup_file=$(secret_backup)

    run secret_restore "$backup_file" "wrong-password"
    [ "$status" -eq 1 ]
}

# =============================================================================
# WIPE TESTS
# =============================================================================

@test "secret_wipe requires --force flag" {
    secret_init "$TEST_PASSWORD"

    run secret_wipe
    [ "$status" -eq 1 ]
}

@test "secret_wipe removes all secrets" {
    secret_init "$TEST_PASSWORD"
    secret_store "wipe_test1" "value1"
    secret_store "wipe_test2" "value2"

    secret_wipe --force

    [ ! -f "$MAINFRAME_SECRETS_DIR/data/wipe_test1.enc" ]
    [ ! -f "$MAINFRAME_SECRETS_DIR/data/wipe_test2.enc" ]
}

@test "secret_wipe clears master key" {
    secret_init "$TEST_PASSWORD"
    secret_store "before_wipe" "value"

    secret_wipe --force

    # Should not be able to store after wipe
    run secret_store "after_wipe" "value"
    [ "$status" -eq 1 ]
}

# =============================================================================
# STATUS TESTS
# =============================================================================

@test "secret_status returns JSON" {
    secret_init "$TEST_PASSWORD"

    local status
    status=$(secret_status)

    [[ "$status" == '{"module":"secrets"'* ]]
}

@test "secret_status shows initialized state" {
    secret_init "$TEST_PASSWORD"

    local status
    status=$(secret_status)

    [[ "$status" == *'"initialized":true'* ]]
    [[ "$status" == *'"master_key_set":true'* ]]
}

@test "secret_status shows secret count" {
    secret_init "$TEST_PASSWORD"
    secret_store "s1" "v1"
    secret_store "s2" "v2"

    local status
    status=$(secret_status)

    [[ "$status" == *'"secret_count":2'* ]]
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "handles unicode in secret values" {
    secret_init "$TEST_PASSWORD"

    local unicode_value="Hello!"
    secret_store "unicode" "$unicode_value"

    local result
    result=$(secret_retrieve "unicode")
    [ "$result" = "$unicode_value" ]
}

@test "handles empty description" {
    secret_init "$TEST_PASSWORD"
    secret_store "no_desc" "value"

    local meta
    meta=$(<"$MAINFRAME_SECRETS_DIR/meta/no_desc.json")
    [[ "$meta" == *'"description":""'* ]]
}

@test "handles very long secret names" {
    secret_init "$TEST_PASSWORD"

    local long_name
    long_name=$(head -c 200 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 100)
    secret_store "$long_name" "value"

    secret_exists "$long_name"
}

@test "concurrent operations don't corrupt data" {
    secret_init "$TEST_PASSWORD"

    # Store multiple secrets rapidly
    local i
    for i in $(seq 1 10); do
        secret_store "concurrent_$i" "value_$i" &
    done
    wait

    # Verify all secrets exist and are correct
    for i in $(seq 1 10); do
        local val
        val=$(secret_retrieve "concurrent_$i")
        [ "$val" = "value_$i" ]
    done
}

@test "handles newlines in secret values" {
    secret_init "$TEST_PASSWORD"

    local multiline="line1
line2
line3"
    secret_store "multiline" "$multiline"

    local result
    result=$(secret_retrieve "multiline")
    [ "$result" = "$multiline" ]
}

@test "handles tabs and special whitespace" {
    secret_init "$TEST_PASSWORD"

    local whitespace=$'tab\there\nand\rcarriage'
    secret_store "whitespace" "$whitespace"

    local result
    result=$(secret_retrieve "whitespace")
    [ "$result" = "$whitespace" ]
}

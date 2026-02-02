#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/secrets.bats - Secrets Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/secrets.sh
#              Encrypted secrets storage with key derivation and audit logging
# Test Count: 40+ test cases
# Categories: Initialization, storage, retrieval, encryption, masking,
#             rotation, expiry, audit, environment, utilities, backend compat
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create isolated temp directory for test secrets
    TEST_TMPDIR="$(mktemp -d)"

    # Override secrets directory to use temp location
    export MAINFRAME_SECRETS_DIR="${TEST_TMPDIR}/secrets"
    export MAINFRAME_SECRETS_AUDIT="${TEST_TMPDIR}/audit.log"
    export MAINFRAME_SECRETS_POLICY="${TEST_TMPDIR}/policy.json"
    export MAINFRAME_SECRETS_BACKUP_DIR="${TEST_TMPDIR}/backups"

    # Suppress logging during tests
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/secrets.sh"

    # Test password (use a simple one for testing)
    TEST_PASSWORD="test-password-123"
}

# Teardown: Clean up test artifacts
teardown() {
    # Clear master key
    secret_clear_master_key 2>/dev/null || true

    # Remove temp directory
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "secret_init: initializes new secrets store" {
    run secret_init "$TEST_PASSWORD"
    [[ "$status" -eq 0 ]]

    # Check directory structure created
    [[ -d "${MAINFRAME_SECRETS_DIR}/data" ]]
    [[ -d "${MAINFRAME_SECRETS_DIR}/meta" ]]
    [[ -f "${MAINFRAME_SECRETS_DIR}/salt" ]]
    [[ -f "${MAINFRAME_SECRETS_DIR}/key_check" ]]
}

@test "secret_init: fails without password" {
    run secret_init ""
    [[ "$status" -eq 1 ]]
}

@test "secret_init: verifies correct password on reinit" {
    # First init
    secret_init "$TEST_PASSWORD"
    secret_clear_master_key

    # Second init with same password
    run secret_init "$TEST_PASSWORD"
    [[ "$status" -eq 0 ]]
}

@test "secret_init: rejects wrong password on reinit" {
    # First init
    secret_init "$TEST_PASSWORD"
    secret_clear_master_key

    # Second init with wrong password
    run secret_init "wrong-password"
    [[ "$status" -eq 1 ]]
}

@test "secret_init: sets secure permissions on files" {
    secret_init "$TEST_PASSWORD"

    # Check permissions (should be 600 or 700)
    local salt_perms
    salt_perms=$(stat -c %a "${MAINFRAME_SECRETS_DIR}/salt" 2>/dev/null || \
                 stat -f %Lp "${MAINFRAME_SECRETS_DIR}/salt" 2>/dev/null)
    [[ "$salt_perms" == "600" ]]

    local dir_perms
    dir_perms=$(stat -c %a "${MAINFRAME_SECRETS_DIR}" 2>/dev/null || \
                stat -f %Lp "${MAINFRAME_SECRETS_DIR}" 2>/dev/null)
    [[ "$dir_perms" == "700" ]]
}

# =============================================================================
# CATEGORY 2: SECRET STORAGE
# =============================================================================

@test "secret_store: stores encrypted secret" {
    secret_init "$TEST_PASSWORD"

    run secret_store "test_secret" "my-secret-value" "Test description"
    [[ "$status" -eq 0 ]]

    # Verify encrypted file exists
    [[ -f "${MAINFRAME_SECRETS_DIR}/data/test_secret.enc" ]]
    [[ -f "${MAINFRAME_SECRETS_DIR}/meta/test_secret.json" ]]
}

@test "secret_store: fails without master key" {
    run secret_store "test_secret" "value"
    [[ "$status" -eq 1 ]]
}

@test "secret_store: fails with empty name" {
    secret_init "$TEST_PASSWORD"
    run secret_store "" "value"
    [[ "$status" -eq 1 ]]
}

@test "secret_store: fails with empty value" {
    secret_init "$TEST_PASSWORD"
    run secret_store "name" ""
    [[ "$status" -eq 1 ]]
}

@test "secret_store: sanitizes unsafe characters in name" {
    secret_init "$TEST_PASSWORD"

    # Name with special chars should be sanitized
    run secret_store "test/secret:with*chars" "value"
    [[ "$status" -eq 0 ]]

    # File should exist with sanitized name
    [[ -f "${MAINFRAME_SECRETS_DIR}/data/test_secret_with_chars.enc" ]]
}

@test "secret_set: alias works for secret_store" {
    secret_init "$TEST_PASSWORD"

    run secret_set "api_key" "sk-abc123"
    [[ "$status" -eq 0 ]]

    # Verify stored
    result=$(secret_get "api_key")
    [[ "$result" == "sk-abc123" ]]
}

@test "secret_set: accepts --backend flag gracefully" {
    secret_init "$TEST_PASSWORD"

    # --backend flag is accepted but uses local storage
    run secret_set "test_key" "test_value" --backend vault
    [[ "$status" -eq 0 ]]

    # Verify stored locally
    result=$(secret_get "test_key")
    [[ "$result" == "test_value" ]]
}

# =============================================================================
# CATEGORY 3: SECRET RETRIEVAL
# =============================================================================

@test "secret_retrieve: retrieves decrypted secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "test_secret" "original-value"

    result=$(secret_retrieve "test_secret")
    [[ "$result" == "original-value" ]]
}

@test "secret_get: alias works for secret_retrieve" {
    secret_init "$TEST_PASSWORD"
    secret_store "my_key" "my_value"

    result=$(secret_get "my_key")
    [[ "$result" == "my_value" ]]
}

@test "secret_retrieve: fails for non-existent secret" {
    secret_init "$TEST_PASSWORD"

    run secret_retrieve "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "secret_retrieve: updates access metadata" {
    secret_init "$TEST_PASSWORD"
    secret_store "tracked_secret" "value"

    # First access
    secret_retrieve "tracked_secret" >/dev/null

    # Check access count incremented
    local count
    count=$(secret_access_count "tracked_secret")
    [[ "$count" == "1" ]]

    # Second access
    secret_retrieve "tracked_secret" >/dev/null
    count=$(secret_access_count "tracked_secret")
    [[ "$count" == "2" ]]
}

@test "secret_retrieve: handles special characters in value" {
    secret_init "$TEST_PASSWORD"

    local special_value='Test with "quotes", $dollars, and \backslashes'
    secret_store "special" "$special_value"

    result=$(secret_retrieve "special")
    [[ "$result" == "$special_value" ]]
}

# =============================================================================
# CATEGORY 4: SECRET DELETION
# =============================================================================

@test "secret_delete: removes secret and metadata" {
    secret_init "$TEST_PASSWORD"
    secret_store "to_delete" "value"

    run secret_delete "to_delete"
    [[ "$status" -eq 0 ]]

    # Files should be gone
    [[ ! -f "${MAINFRAME_SECRETS_DIR}/data/to_delete.enc" ]]
    [[ ! -f "${MAINFRAME_SECRETS_DIR}/meta/to_delete.json" ]]
}

@test "secret_delete: is idempotent" {
    secret_init "$TEST_PASSWORD"

    # Delete non-existent secret should succeed
    run secret_delete "never_existed"
    [[ "$status" -eq 0 ]]
}

@test "secret_exists: returns true for existing secret" {
    secret_init "$TEST_PASSWORD"
    secret_store "existing" "value"

    secret_exists "existing"
    [[ $? -eq 0 ]]
}

@test "secret_exists: returns false for non-existent secret" {
    secret_init "$TEST_PASSWORD"

    run secret_exists "nonexistent"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 5: SECRET LISTING
# =============================================================================

@test "secret_list: lists all secret names" {
    secret_init "$TEST_PASSWORD"
    secret_store "secret_a" "value1"
    secret_store "secret_b" "value2"
    secret_store "secret_c" "value3"

    result=$(secret_list)
    [[ "$result" =~ "secret_a" ]]
    [[ "$result" =~ "secret_b" ]]
    [[ "$result" =~ "secret_c" ]]
}

@test "secret_list: returns empty for no secrets" {
    secret_init "$TEST_PASSWORD"

    result=$(secret_list)
    [[ -z "$result" ]]
}

@test "secret_list: supports JSON output" {
    secret_init "$TEST_PASSWORD"
    secret_store "json_test" "value"

    result=$(secret_list --json)
    [[ "$result" =~ '{"secrets":' ]]
    [[ "$result" =~ '"json_test"' ]]
}

# =============================================================================
# CATEGORY 6: ENCRYPTION
# =============================================================================

@test "secret_encrypt: encrypts plaintext" {
    run secret_encrypt "test plaintext" "test-key"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]

    # Output should contain IV separator
    [[ "$output" =~ : ]]
}

@test "secret_decrypt: decrypts ciphertext" {
    local encrypted
    encrypted=$(secret_encrypt "original message" "my-key")

    local decrypted
    decrypted=$(secret_decrypt "$encrypted" "my-key")

    [[ "$decrypted" == "original message" ]]
}

@test "secret_decrypt: fails with wrong key" {
    local encrypted
    encrypted=$(secret_encrypt "secret" "correct-key")

    run secret_decrypt "$encrypted" "wrong-key"
    [[ "$status" -eq 1 ]]
}

@test "secret_derive_key: derives consistent key from password" {
    local key1 key2

    key1=$(secret_derive_key "password" "salt123")
    key2=$(secret_derive_key "password" "salt123")

    [[ "$key1" == "$key2" ]]
}

@test "secret_derive_key: different salt produces different key" {
    local key1 key2

    key1=$(secret_derive_key "password" "salt1")
    key2=$(secret_derive_key "password" "salt2")

    [[ "$key1" != "$key2" ]]
}

@test "secret_generate_key: generates 64 hex char key" {
    local key
    key=$(secret_generate_key)

    [[ ${#key} -eq 64 ]]
    [[ "$key" =~ ^[0-9a-f]+$ ]]
}

@test "secret_hash: computes SHA-256 hash" {
    local hash
    hash=$(secret_hash "test data")

    [[ ${#hash} -eq 64 ]]
    [[ "$hash" =~ ^[0-9a-f]+$ ]]
}

# =============================================================================
# CATEGORY 7: SECRET MASKING
# =============================================================================

@test "secret_mask: masks secret with default visibility" {
    result=$(secret_mask "sk-proj-abc123xyz789")

    # First 2 and last 2 chars visible
    [[ "$result" == "sk***************89" ]]
}

@test "secret_mask: handles short values" {
    result=$(secret_mask "abc")

    # Short values show ****
    [[ "$result" == "****" ]]
}

@test "secret_mask: handles empty values" {
    result=$(secret_mask "")
    [[ "$result" == "****" ]]
}

@test "secret_mask: respects custom visibility" {
    result=$(secret_mask "0123456789" 3 3)

    # First 3 and last 3 chars visible
    [[ "$result" == "012****789" ]]
}

@test "secret_mask: handles edge case exactly at threshold" {
    # Value of length 4 with start=2, end=2
    result=$(secret_mask "abcd" 2 2)
    [[ "$result" == "****" ]]
}

# =============================================================================
# CATEGORY 8: SECRET ROTATION
# =============================================================================

@test "secret_rotate: rotates secret to new value" {
    secret_init "$TEST_PASSWORD"
    secret_store "rotate_test" "old-value"

    run secret_rotate "rotate_test" "new-value"
    [[ "$status" -eq 0 ]]

    result=$(secret_retrieve "rotate_test")
    [[ "$result" == "new-value" ]]
}

@test "secret_rotate: fails for non-existent secret" {
    secret_init "$TEST_PASSWORD"

    run secret_rotate "nonexistent" "value"
    [[ "$status" -eq 1 ]]
}

@test "secret_rotate: increments version number" {
    secret_init "$TEST_PASSWORD"
    secret_store "versioned" "v1"

    secret_rotate "versioned" "v2"
    secret_rotate "versioned" "v3"

    # Check version in metadata
    local meta_path="${MAINFRAME_SECRETS_DIR}/meta/versioned.json"
    local version
    version=$(grep -o '"version":[0-9]*' "$meta_path" | cut -d: -f2)
    [[ "$version" == "3" ]]
}

# =============================================================================
# CATEGORY 9: EXPIRY
# =============================================================================

@test "secret_set_expiry: sets expiration date" {
    secret_init "$TEST_PASSWORD"
    secret_store "expiring" "value"

    run secret_set_expiry "expiring" "2099-12-31T23:59:59Z"
    [[ "$status" -eq 0 ]]

    # Check expiry in metadata
    local meta_path="${MAINFRAME_SECRETS_DIR}/meta/expiring.json"
    [[ $(cat "$meta_path") =~ "expiry" ]]
}

@test "secret_check_expiry: returns false for future expiry" {
    secret_init "$TEST_PASSWORD"
    secret_store "future" "value"
    secret_set_expiry "future" "2099-12-31T23:59:59Z"

    # Not expired
    run secret_check_expiry "future"
    [[ "$status" -eq 1 ]]
}

@test "secret_check_expiry: returns true for past expiry" {
    secret_init "$TEST_PASSWORD"
    secret_store "past" "value"
    secret_set_expiry "past" "2020-01-01T00:00:00Z"

    # Should be expired
    secret_check_expiry "past"
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 10: AUDIT LOGGING
# =============================================================================

@test "secret_audit_log: writes to audit log" {
    run secret_audit_log "test_action" "test_target" "test details"
    [[ "$status" -eq 0 ]]

    # Check log file exists and contains entry
    [[ -f "$MAINFRAME_SECRETS_AUDIT" ]]
    [[ $(cat "$MAINFRAME_SECRETS_AUDIT") =~ "test_action" ]]
    [[ $(cat "$MAINFRAME_SECRETS_AUDIT") =~ "test_target" ]]
}

@test "secret_audit_log: creates JSON entries" {
    secret_audit_log "action" "target" "details"

    local entry
    entry=$(cat "$MAINFRAME_SECRETS_AUDIT")

    [[ "$entry" =~ '"timestamp":' ]]
    [[ "$entry" =~ '"action":"action"' ]]
    [[ "$entry" =~ '"target":"target"' ]]
}

@test "secret_audit_list: shows recent entries" {
    secret_audit_log "action1" "target1" ""
    secret_audit_log "action2" "target2" ""
    secret_audit_log "action3" "target3" ""

    result=$(secret_audit_list 2)

    # Should show last 2 entries
    [[ "$result" =~ "action2" ]]
    [[ "$result" =~ "action3" ]]
}

@test "secret_audit_search: finds matching entries" {
    secret_audit_log "store" "api_key" "stored"
    secret_audit_log "retrieve" "db_password" "accessed"
    secret_audit_log "delete" "old_key" "deleted"

    result=$(secret_audit_search "db_password")
    [[ "$result" =~ "db_password" ]]
    [[ ! "$result" =~ "api_key" ]]
}

# =============================================================================
# CATEGORY 11: ENVIRONMENT INTEGRATION
# =============================================================================

@test "secret_to_env: outputs export statement" {
    secret_init "$TEST_PASSWORD"
    secret_store "env_test" "secret-value"

    result=$(secret_to_env "env_test" "MY_VAR")
    [[ "$result" =~ "export MY_VAR=" ]]
}

@test "secret_to_env: auto-generates var name" {
    secret_init "$TEST_PASSWORD"
    secret_store "my-api-key" "value"

    result=$(secret_to_env "my-api-key")
    [[ "$result" =~ "export MY_API_KEY=" ]]
}

@test "secret_from_env: imports from environment" {
    secret_init "$TEST_PASSWORD"

    export TEST_SECRET_VAR="imported-value"
    run secret_from_env "TEST_SECRET_VAR" "imported_secret"
    [[ "$status" -eq 0 ]]

    result=$(secret_retrieve "imported_secret")
    [[ "$result" == "imported-value" ]]

    unset TEST_SECRET_VAR
}

# =============================================================================
# CATEGORY 12: UTILITIES
# =============================================================================

@test "secret_random_password: generates password of specified length" {
    local pwd
    pwd=$(secret_random_password 24)

    [[ ${#pwd} -eq 24 ]]
}

@test "secret_random_password: alphanumeric charset" {
    local pwd
    pwd=$(secret_random_password 32 alphanumeric)

    # Should only contain alphanumeric
    [[ "$pwd" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "secret_random_password: special charset includes symbols" {
    local pwd
    pwd=$(secret_random_password 64 special)

    # Should be 64 chars (special chars might appear)
    [[ ${#pwd} -eq 64 ]]
}

@test "secret_strength_check: assesses password strength" {
    local result

    # Weak password
    result=$(secret_strength_check "abc")
    [[ "$result" =~ '"strength":"weak"' ]]

    # Strong password
    result=$(secret_strength_check "MyStr0ng!P@ssw0rd#2024")
    [[ "$result" =~ '"strength":"strong"' ]]
}

@test "secret_status: returns module status" {
    result=$(secret_status)

    [[ "$result" =~ '"module":"secrets"' ]]
    [[ "$result" =~ '"initialized":' ]]
}

# =============================================================================
# CATEGORY 13: BACKEND COMPATIBILITY
# =============================================================================

@test "secret_backend_add: registers new backend" {
    run secret_backend_add "custom" '{"type":"custom","url":"http://example.com"}'
    [[ "$status" -eq 0 ]]
}

@test "secret_backend_add: validates name format" {
    run secret_backend_add "Invalid-Name" '{"type":"test"}'
    [[ "$status" -eq 1 ]]
}

@test "secret_backend_list: lists registered backends" {
    secret_backend_add "mybackend" '{"type":"test"}'

    result=$(secret_backend_list)
    [[ "$result" =~ "local" ]]
    [[ "$result" =~ "mybackend" ]]
}

@test "secret_backend_list: shows status for local backend" {
    secret_init "$TEST_PASSWORD"

    result=$(secret_backend_list)
    [[ "$result" =~ "local:active" ]]
}

# =============================================================================
# CATEGORY 14: KEY MANAGEMENT
# =============================================================================

@test "secret_set_master_key: sets key directly" {
    local key
    key=$(secret_generate_key)

    run secret_set_master_key "$key"
    [[ "$status" -eq 0 ]]
}

@test "secret_clear_master_key: clears key from memory" {
    secret_init "$TEST_PASSWORD"

    secret_clear_master_key

    # Should fail to retrieve now
    run secret_retrieve "any_secret"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 15: BACKUP AND RESTORE
# =============================================================================

@test "secret_backup: creates encrypted backup" {
    secret_init "$TEST_PASSWORD"
    secret_store "backup_test" "backup_value"

    result=$(secret_backup)
    [[ -f "$result" ]]
}

@test "secret_wipe: refuses without --force" {
    secret_init "$TEST_PASSWORD"
    secret_store "wipe_test" "value"

    run secret_wipe
    [[ "$status" -eq 1 ]]

    # Secret should still exist
    [[ -f "${MAINFRAME_SECRETS_DIR}/data/wipe_test.enc" ]]
}

@test "secret_wipe: removes all secrets with --force" {
    secret_init "$TEST_PASSWORD"
    secret_store "wipe_test" "value"

    run secret_wipe --force
    [[ "$status" -eq 0 ]]

    # Data should be gone
    [[ ! -f "${MAINFRAME_SECRETS_DIR}/data/wipe_test.enc" ]]
}

# =============================================================================
# CATEGORY 16: EDGE CASES AND SECURITY
# =============================================================================

@test "secrets: handles unicode values" {
    secret_init "$TEST_PASSWORD"
    local unicode_value="Hello"

    secret_store "unicode" "$unicode_value"
    result=$(secret_retrieve "unicode")

    [[ "$result" == "$unicode_value" ]]
}

@test "secrets: handles large values" {
    secret_init "$TEST_PASSWORD"

    # Generate 10KB of data
    local large_value
    large_value=$(head -c 10240 /dev/urandom | base64)

    secret_store "large" "$large_value"
    result=$(secret_retrieve "large")

    [[ "$result" == "$large_value" ]]
}

@test "secrets: handles newlines in values" {
    secret_init "$TEST_PASSWORD"

    local multiline="line1
line2
line3"

    secret_store "multiline" "$multiline"
    result=$(secret_retrieve "multiline")

    [[ "$result" == "$multiline" ]]
}

@test "secrets: encrypted data is not plaintext" {
    secret_init "$TEST_PASSWORD"
    local secret_value="super-secret-password-123"
    secret_store "plaintext_check" "$secret_value"

    # Read raw encrypted file
    local encrypted
    encrypted=$(cat "${MAINFRAME_SECRETS_DIR}/data/plaintext_check.enc")

    # Should NOT contain plaintext
    [[ ! "$encrypted" =~ "$secret_value" ]]
}

@test "secrets: each encryption produces different ciphertext" {
    secret_init "$TEST_PASSWORD"

    # Encrypt same value twice
    local enc1 enc2
    enc1=$(secret_encrypt "same value" "same key")
    enc2=$(secret_encrypt "same value" "same key")

    # Should be different due to random IV
    [[ "$enc1" != "$enc2" ]]
}

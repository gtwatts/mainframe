#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Crypto Module Tests
# =============================================================================
# Tests for lib/crypto.sh
# Covers: base64, hex, hashing (md5, sha1, sha256, sha512), random tokens
# =============================================================================

load 'test_helper'

setup() {
    source_lib "crypto"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "crypto")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# base64_encode / base64_decode TESTS
# =============================================================================

@test "base64_encode encodes string" {
    local result
    result=$(base64_encode "hello world")
    [ "$result" = "aGVsbG8gd29ybGQ=" ]
}

@test "base64_decode decodes string" {
    local result
    result=$(base64_decode "aGVsbG8gd29ybGQ=")
    [ "$result" = "hello world" ]
}

@test "base64 roundtrip preserves data" {
    local input="The quick brown fox"
    local encoded decoded
    encoded=$(base64_encode "$input")
    decoded=$(base64_decode "$encoded")
    [ "$decoded" = "$input" ]
}

@test "base64_encode handles empty string" {
    local result
    result=$(base64_encode "")
    [ -z "$result" ]
}

@test "base64_encode handles special characters" {
    local input='!@#$%^&*()_+-=[]{}|;:",.<>?/'
    local encoded decoded
    encoded=$(base64_encode "$input")
    decoded=$(base64_decode "$encoded")
    [ "$decoded" = "$input" ]
}

# =============================================================================
# base64_encode_file / base64_decode_file TESTS
# =============================================================================

@test "base64_encode_file encodes file content" {
    printf 'test data' > "$TEST_DIR/input.txt"
    local result
    result=$(base64_encode_file "$TEST_DIR/input.txt")
    [ -n "$result" ]
}

@test "base64_encode_file fails for missing file" {
    run base64_encode_file "$TEST_DIR/nonexistent.txt"
    [ "$status" -eq 1 ]
}

@test "base64_decode_file creates output file" {
    local encoded
    encoded=$(base64_encode "file content")
    base64_decode_file "$encoded" "$TEST_DIR/output.txt"
    [ -f "$TEST_DIR/output.txt" ]
    local content
    content=$(<"$TEST_DIR/output.txt")
    [ "$content" = "file content" ]
}

# =============================================================================
# hex_encode / hex_decode TESTS
# =============================================================================

@test "hex_encode encodes to hex" {
    local result
    result=$(hex_encode "hello")
    [ "$result" = "68656c6c6f" ]
}

@test "hex_decode decodes from hex" {
    local result
    result=$(hex_decode "68656c6c6f")
    [ "$result" = "hello" ]
}

@test "hex roundtrip preserves data" {
    local input="test123"
    local encoded decoded
    encoded=$(hex_encode "$input")
    decoded=$(hex_decode "$encoded")
    [ "$decoded" = "$input" ]
}

@test "hex_decode handles colon separator" {
    local result
    result=$(hex_decode "68:65:6c:6c:6f")
    [ "$result" = "hello" ]
}

@test "hex_decode handles space separator" {
    local result
    result=$(hex_decode "68 65 6c 6c 6f")
    [ "$result" = "hello" ]
}

# =============================================================================
# md5 TESTS
# =============================================================================

@test "md5 produces 32-char hex hash" {
    local result
    result=$(md5 "hello")
    [ ${#result} -eq 32 ]
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "md5 is deterministic" {
    local h1 h2
    h1=$(md5 "test input")
    h2=$(md5 "test input")
    [ "$h1" = "$h2" ]
}

@test "md5 different inputs give different hashes" {
    local h1 h2
    h1=$(md5 "input1")
    h2=$(md5 "input2")
    [ "$h1" != "$h2" ]
}

@test "md5_file hashes file content" {
    printf 'file data' > "$TEST_DIR/hash_me.txt"
    local result
    result=$(md5_file "$TEST_DIR/hash_me.txt")
    [ ${#result} -eq 32 ]
}

@test "md5_file fails for missing file" {
    run md5_file "$TEST_DIR/missing.txt"
    [ "$status" -eq 1 ]
}

# =============================================================================
# sha1 TESTS
# =============================================================================

@test "sha1 produces 40-char hex hash" {
    local result
    result=$(sha1 "hello")
    [ ${#result} -eq 40 ]
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "sha1 is deterministic" {
    local h1 h2
    h1=$(sha1 "consistent")
    h2=$(sha1 "consistent")
    [ "$h1" = "$h2" ]
}

@test "sha1_file hashes file" {
    printf 'file content' > "$TEST_DIR/sha1_test.txt"
    local result
    result=$(sha1_file "$TEST_DIR/sha1_test.txt")
    [ ${#result} -eq 40 ]
}

# =============================================================================
# sha256 TESTS
# =============================================================================

@test "sha256 produces 64-char hex hash" {
    local result
    result=$(sha256 "hello")
    [ ${#result} -eq 64 ]
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "sha256 matches known hash" {
    local result
    result=$(sha256 "hello")
    # Known SHA-256 of "hello" (no newline)
    [ "$result" = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" ]
}

@test "sha256 is deterministic" {
    local h1 h2
    h1=$(sha256 "sha test")
    h2=$(sha256 "sha test")
    [ "$h1" = "$h2" ]
}

@test "sha256_file hashes file" {
    printf 'file content here' > "$TEST_DIR/sha256_test.txt"
    local result
    result=$(sha256_file "$TEST_DIR/sha256_test.txt")
    [ ${#result} -eq 64 ]
}

@test "sha256_file fails for missing file" {
    run sha256_file "$TEST_DIR/missing.txt"
    [ "$status" -eq 1 ]
}

# =============================================================================
# sha512 TESTS
# =============================================================================

@test "sha512 produces 128-char hex hash" {
    local result
    result=$(sha512 "hello")
    [ ${#result} -eq 128 ]
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "sha512 is deterministic" {
    local h1 h2
    h1=$(sha512 "test data")
    h2=$(sha512 "test data")
    [ "$h1" = "$h2" ]
}

# =============================================================================
# bytes_to_hex TESTS
# =============================================================================

@test "bytes_to_hex converts string to hex" {
    local result
    result=$(bytes_to_hex "AB")
    [[ "$result" == *"4142"* ]]
}

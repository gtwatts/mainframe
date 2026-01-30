#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Fluent Validation DSL Tests
# =============================================================================
# Tests for lib/fluent.sh
# Covers: is::*, when::*, assert::*, fluent_* functions
# =============================================================================

load 'test_helper'

setup() {
    source_lib "fluent"
    export MAINFRAME_QUIET=1
    export FLUENT_EXIT_ON_FAILURE=0  # Soft mode for tests
    export FLUENT_OUTPUT_FORMAT=plain
    TEST_DIR=$(create_test_dir "fluent")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# is::file TESTS
# =============================================================================

@test "is::file returns 0 for regular file" {
    touch "$TEST_DIR/testfile"
    run is::file "$TEST_DIR/testfile"
    [ "$status" -eq 0 ]
}

@test "is::file returns 1 for directory" {
    mkdir -p "$TEST_DIR/testdir"
    run is::file "$TEST_DIR/testdir"
    [ "$status" -eq 1 ]
}

@test "is::file returns 1 for non-existent path" {
    run is::file "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

@test "is::file returns 1 for empty path" {
    run is::file ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::dir TESTS
# =============================================================================

@test "is::dir returns 0 for directory" {
    mkdir -p "$TEST_DIR/testdir"
    run is::dir "$TEST_DIR/testdir"
    [ "$status" -eq 0 ]
}

@test "is::dir returns 1 for regular file" {
    touch "$TEST_DIR/testfile"
    run is::dir "$TEST_DIR/testfile"
    [ "$status" -eq 1 ]
}

@test "is::dir returns 1 for non-existent path" {
    run is::dir "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::link TESTS
# =============================================================================

@test "is::link returns 0 for symlink" {
    touch "$TEST_DIR/target"
    ln -s "$TEST_DIR/target" "$TEST_DIR/symlink"
    run is::link "$TEST_DIR/symlink"
    [ "$status" -eq 0 ]
}

@test "is::link returns 1 for regular file" {
    touch "$TEST_DIR/testfile"
    run is::link "$TEST_DIR/testfile"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::exists TESTS
# =============================================================================

@test "is::exists returns 0 for existing file" {
    touch "$TEST_DIR/testfile"
    run is::exists "$TEST_DIR/testfile"
    [ "$status" -eq 0 ]
}

@test "is::exists returns 0 for existing directory" {
    mkdir -p "$TEST_DIR/testdir"
    run is::exists "$TEST_DIR/testdir"
    [ "$status" -eq 0 ]
}

@test "is::exists returns 1 for non-existent path" {
    run is::exists "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::readable TESTS
# =============================================================================

@test "is::readable returns 0 for readable file" {
    touch "$TEST_DIR/readable"
    chmod +r "$TEST_DIR/readable"
    run is::readable "$TEST_DIR/readable"
    [ "$status" -eq 0 ]
}

@test "is::readable returns 1 for non-existent file" {
    run is::readable "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::writable TESTS
# =============================================================================

@test "is::writable returns 0 for writable file" {
    touch "$TEST_DIR/writable"
    chmod +w "$TEST_DIR/writable"
    run is::writable "$TEST_DIR/writable"
    [ "$status" -eq 0 ]
}

@test "is::writable returns 1 for non-existent file" {
    run is::writable "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::executable TESTS
# =============================================================================

@test "is::executable returns 0 for executable file" {
    touch "$TEST_DIR/executable"
    chmod +x "$TEST_DIR/executable"
    run is::executable "$TEST_DIR/executable"
    [ "$status" -eq 0 ]
}

@test "is::executable returns 1 for non-executable file" {
    touch "$TEST_DIR/notexecutable"
    chmod -x "$TEST_DIR/notexecutable"
    run is::executable "$TEST_DIR/notexecutable"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::empty TESTS
# =============================================================================

@test "is::empty returns 0 for empty file" {
    touch "$TEST_DIR/emptyfile"
    run is::empty "$TEST_DIR/emptyfile"
    [ "$status" -eq 0 ]
}

@test "is::empty returns 1 for non-empty file" {
    echo "content" > "$TEST_DIR/nonemptyfile"
    run is::empty "$TEST_DIR/nonemptyfile"
    [ "$status" -eq 1 ]
}

@test "is::empty returns 0 for empty directory" {
    mkdir -p "$TEST_DIR/emptydir"
    run is::empty "$TEST_DIR/emptydir"
    [ "$status" -eq 0 ]
}

@test "is::empty returns 1 for non-empty directory" {
    mkdir -p "$TEST_DIR/nonemptydir"
    touch "$TEST_DIR/nonemptydir/file"
    run is::empty "$TEST_DIR/nonemptydir"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::nonempty TESTS
# =============================================================================

@test "is::nonempty returns 0 for non-empty file" {
    echo "content" > "$TEST_DIR/nonemptyfile"
    run is::nonempty "$TEST_DIR/nonemptyfile"
    [ "$status" -eq 0 ]
}

@test "is::nonempty returns 1 for empty file" {
    touch "$TEST_DIR/emptyfile"
    run is::nonempty "$TEST_DIR/emptyfile"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is::newer_than / is::older_than TESTS
# =============================================================================

@test "is::newer_than returns 0 for recent file" {
    touch "$TEST_DIR/recentfile"
    run is::newer_than "$TEST_DIR/recentfile" "1h"
    [ "$status" -eq 0 ]
}

@test "is::newer_than returns 1 for non-existent file" {
    run is::newer_than "$TEST_DIR/nonexistent" "1h"
    [ "$status" -eq 1 ]
}

@test "is::older_than returns 1 for recent file" {
    touch "$TEST_DIR/recentfile"
    run is::older_than "$TEST_DIR/recentfile" "1h"
    [ "$status" -eq 1 ]
}

# =============================================================================
# STRING VALIDATION TESTS
# =============================================================================

@test "is::string returns 0 for non-empty string" {
    run is::string "hello"
    [ "$status" -eq 0 ]
}

@test "is::string returns 1 for empty string" {
    run is::string ""
    [ "$status" -eq 1 ]
}

@test "is::integer returns 0 for valid integer" {
    run is::integer "42"
    [ "$status" -eq 0 ]
}

@test "is::integer returns 0 for negative integer" {
    run is::integer "-42"
    [ "$status" -eq 0 ]
}

@test "is::integer returns 1 for float" {
    run is::integer "3.14"
    [ "$status" -eq 1 ]
}

@test "is::integer returns 1 for non-numeric" {
    run is::integer "abc"
    [ "$status" -eq 1 ]
}

@test "is::float returns 0 for valid float" {
    run is::float "3.14"
    [ "$status" -eq 0 ]
}

@test "is::float returns 0 for integer" {
    run is::float "42"
    [ "$status" -eq 0 ]
}

@test "is::float returns 0 for scientific notation" {
    run is::float "1.5e10"
    [ "$status" -eq 0 ]
}

@test "is::float returns 1 for non-numeric" {
    run is::float "abc"
    [ "$status" -eq 1 ]
}

# =============================================================================
# FORMAT VALIDATION TESTS
# =============================================================================

@test "is::uuid returns 0 for valid UUID" {
    run is::uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

@test "is::uuid returns 1 for invalid UUID" {
    run is::uuid "not-a-uuid"
    [ "$status" -eq 1 ]
}

@test "is::email returns 0 for valid email" {
    run is::email "user@domain.com"
    [ "$status" -eq 0 ]
}

@test "is::email returns 1 for invalid email" {
    run is::email "not-an-email"
    [ "$status" -eq 1 ]
}

@test "is::url returns 0 for valid URL" {
    run is::url "https://example.com/path"
    [ "$status" -eq 0 ]
}

@test "is::url returns 1 for invalid URL" {
    run is::url "not-a-url"
    [ "$status" -eq 1 ]
}

@test "is::json returns 0 for valid JSON object" {
    run is::json '{"key":"value"}'
    [ "$status" -eq 0 ]
}

@test "is::json returns 0 for valid JSON array" {
    run is::json '["a","b","c"]'
    [ "$status" -eq 0 ]
}

@test "is::json returns 0 for JSON boolean" {
    run is::json 'true'
    [ "$status" -eq 0 ]
}

@test "is::json returns 0 for JSON null" {
    run is::json 'null'
    [ "$status" -eq 0 ]
}

@test "is::json returns 1 for invalid JSON" {
    run is::json 'not json'
    [ "$status" -eq 1 ]
}

@test "is::semver returns 0 for valid semver" {
    run is::semver "1.2.3"
    [ "$status" -eq 0 ]
}

@test "is::semver returns 0 for semver with v prefix" {
    run is::semver "v1.2.3"
    [ "$status" -eq 0 ]
}

@test "is::semver returns 0 for semver with prerelease" {
    run is::semver "1.2.3-beta.1"
    [ "$status" -eq 0 ]
}

@test "is::semver returns 1 for invalid semver" {
    run is::semver "1.2"
    [ "$status" -eq 1 ]
}

@test "is::hostname returns 0 for valid hostname" {
    run is::hostname "example.com"
    [ "$status" -eq 0 ]
}

@test "is::hostname returns 0 for subdomain" {
    run is::hostname "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "is::hostname returns 1 for invalid hostname" {
    run is::hostname "-invalid.com"
    [ "$status" -eq 1 ]
}

@test "is::ipv4 returns 0 for valid IPv4" {
    run is::ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "is::ipv4 returns 1 for invalid IPv4" {
    run is::ipv4 "256.1.1.1"
    [ "$status" -eq 1 ]
}

@test "is::boolean returns 0 for true" {
    run is::boolean "true"
    [ "$status" -eq 0 ]
}

@test "is::boolean returns 0 for yes" {
    run is::boolean "yes"
    [ "$status" -eq 0 ]
}

@test "is::boolean returns 0 for 1" {
    run is::boolean "1"
    [ "$status" -eq 0 ]
}

@test "is::boolean returns 1 for invalid" {
    run is::boolean "maybe"
    [ "$status" -eq 1 ]
}

@test "is::hex returns 0 for hex string" {
    run is::hex "deadbeef"
    [ "$status" -eq 0 ]
}

@test "is::hex returns 1 for non-hex" {
    run is::hex "xyz"
    [ "$status" -eq 1 ]
}

# =============================================================================
# NEGATION TESTS
# =============================================================================

@test "is::not::empty returns 0 for non-empty file" {
    echo "content" > "$TEST_DIR/nonemptyfile"
    run is::not::empty "$TEST_DIR/nonemptyfile"
    [ "$status" -eq 0 ]
}

@test "is::not::empty returns 1 for empty file" {
    touch "$TEST_DIR/emptyfile"
    run is::not::empty "$TEST_DIR/emptyfile"
    [ "$status" -eq 1 ]
}

@test "is::not::writable returns 0 for non-existent" {
    run is::not::writable "$TEST_DIR/nonexistent"
    [ "$status" -eq 0 ]
}

@test "is::not::integer returns 0 for non-integer" {
    run is::not::integer "abc"
    [ "$status" -eq 0 ]
}

@test "is::not::integer returns 1 for integer" {
    run is::not::integer "42"
    [ "$status" -eq 1 ]
}

# =============================================================================
# CONDITIONAL TESTS (when::*)
# =============================================================================

@test "when::exists returns 0 for existing file" {
    touch "$TEST_DIR/exists"
    run when::exists "$TEST_DIR/exists"
    [ "$status" -eq 0 ]
}

@test "when::exists returns 1 for non-existent file" {
    run when::exists "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

@test "when::missing returns 0 for non-existent file" {
    run when::missing "$TEST_DIR/nonexistent"
    [ "$status" -eq 0 ]
}

@test "when::missing returns 1 for existing file" {
    touch "$TEST_DIR/exists"
    run when::missing "$TEST_DIR/exists"
    [ "$status" -eq 1 ]
}

@test "when::file returns 0 for file" {
    touch "$TEST_DIR/testfile"
    run when::file "$TEST_DIR/testfile"
    [ "$status" -eq 0 ]
}

@test "when::dir returns 0 for directory" {
    mkdir -p "$TEST_DIR/testdir"
    run when::dir "$TEST_DIR/testdir"
    [ "$status" -eq 0 ]
}

@test "when::empty returns 0 for empty file" {
    touch "$TEST_DIR/emptyfile"
    run when::empty "$TEST_DIR/emptyfile"
    [ "$status" -eq 0 ]
}

@test "when::nonempty returns 0 for non-empty file" {
    echo "content" > "$TEST_DIR/nonemptyfile"
    run when::nonempty "$TEST_DIR/nonemptyfile"
    [ "$status" -eq 0 ]
}

# =============================================================================
# ASSERTION TESTS (assert::*)
# =============================================================================

@test "assert::file succeeds for file" {
    touch "$TEST_DIR/testfile"
    run assert::file "$TEST_DIR/testfile"
    [ "$status" -eq 0 ]
}

@test "assert::file fails for non-existent" {
    run assert::file "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

@test "assert::dir succeeds for directory" {
    mkdir -p "$TEST_DIR/testdir"
    run assert::dir "$TEST_DIR/testdir"
    [ "$status" -eq 0 ]
}

@test "assert::dir fails for file" {
    touch "$TEST_DIR/testfile"
    run assert::dir "$TEST_DIR/testfile"
    [ "$status" -eq 1 ]
}

@test "assert::exists succeeds for existing path" {
    touch "$TEST_DIR/exists"
    run assert::exists "$TEST_DIR/exists"
    [ "$status" -eq 0 ]
}

@test "assert::readable succeeds for readable file" {
    touch "$TEST_DIR/readable"
    run assert::readable "$TEST_DIR/readable"
    [ "$status" -eq 0 ]
}

@test "assert::nonempty succeeds for non-empty file" {
    echo "content" > "$TEST_DIR/nonempty"
    run assert::nonempty "$TEST_DIR/nonempty"
    [ "$status" -eq 0 ]
}

@test "assert::string succeeds for non-empty string" {
    run assert::string "hello"
    [ "$status" -eq 0 ]
}

@test "assert::string fails for empty string" {
    run assert::string ""
    [ "$status" -eq 1 ]
}

@test "assert::integer succeeds for integer" {
    run assert::integer "42"
    [ "$status" -eq 0 ]
}

@test "assert::integer fails for non-integer" {
    run assert::integer "abc"
    [ "$status" -eq 1 ]
}

@test "assert::email succeeds for valid email" {
    run assert::email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "assert::url succeeds for valid URL" {
    run assert::url "https://example.com"
    [ "$status" -eq 0 ]
}

@test "assert::json succeeds for valid JSON" {
    run assert::json '{"key":"value"}'
    [ "$status" -eq 0 ]
}

@test "assert::semver succeeds for valid semver" {
    run assert::semver "1.2.3"
    [ "$status" -eq 0 ]
}

@test "assert::uuid succeeds for valid UUID" {
    run assert::uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

# =============================================================================
# MULTI-VALUE ASSERTION TESTS
# =============================================================================

@test "assert::all succeeds when all pass" {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2" "$TEST_DIR/file3"
    run assert::all is::file "$TEST_DIR/file1" "$TEST_DIR/file2" "$TEST_DIR/file3"
    [ "$status" -eq 0 ]
}

@test "assert::all fails when one fails" {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    mkdir -p "$TEST_DIR/dir1"
    run assert::all is::file "$TEST_DIR/file1" "$TEST_DIR/dir1" "$TEST_DIR/file2"
    [ "$status" -eq 1 ]
}

@test "assert::any succeeds when one passes" {
    touch "$TEST_DIR/file1"
    mkdir -p "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    run assert::any is::file "$TEST_DIR/dir1" "$TEST_DIR/file1" "$TEST_DIR/dir2"
    [ "$status" -eq 0 ]
}

@test "assert::any fails when none pass" {
    mkdir -p "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    run assert::any is::file "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    [ "$status" -eq 1 ]
}

@test "assert::none succeeds when none pass" {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    echo "content" > "$TEST_DIR/file1"
    echo "content" > "$TEST_DIR/file2"
    run assert::none is::empty "$TEST_DIR/file1" "$TEST_DIR/file2"
    [ "$status" -eq 0 ]
}

@test "assert::none fails when one passes" {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    echo "content" > "$TEST_DIR/file1"
    run assert::none is::empty "$TEST_DIR/file1" "$TEST_DIR/file2"
    [ "$status" -eq 1 ]
}

# =============================================================================
# FLUENT CHECK CHAIN TESTS
# =============================================================================

@test "fluent_check succeeds when all conditions pass" {
    echo "content" > "$TEST_DIR/testfile"
    chmod +r "$TEST_DIR/testfile"
    run fluent_check "$TEST_DIR/testfile" file readable nonempty
    [ "$status" -eq 0 ]
}

@test "fluent_check fails when one condition fails" {
    touch "$TEST_DIR/emptyfile"
    run fluent_check "$TEST_DIR/emptyfile" file readable nonempty
    [ "$status" -eq 1 ]
}

# =============================================================================
# FLUENT VALIDATE TESTS
# =============================================================================

@test "fluent_validate returns JSON with all passed" {
    echo "content" > "$TEST_DIR/testfile"
    run fluent_validate "$TEST_DIR/testfile" file readable nonempty
    [ "$status" -eq 0 ]
    [[ "$output" == *'"success":true'* ]]
}

@test "fluent_validate returns JSON with failure" {
    touch "$TEST_DIR/emptyfile"
    run fluent_validate "$TEST_DIR/emptyfile" file readable nonempty
    [ "$status" -eq 1 ]
    [[ "$output" == *'"success":false'* ]]
}

# =============================================================================
# BATCH CHECK TESTS
# =============================================================================

@test "fluent_batch_check returns JSON results" {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    mkdir -p "$TEST_DIR/dir1"
    run fluent_batch_check file "$TEST_DIR/file1" "$TEST_DIR/file2" "$TEST_DIR/dir1"
    [ "$status" -eq 1 ]  # Not all passed
    [[ "$output" == *'"total":3'* ]]
    [[ "$output" == *'"passed":2'* ]]
}

# =============================================================================
# MODE SWITCHING TESTS
# =============================================================================

@test "fluent_soft_mode disables exit on failure" {
    fluent_soft_mode
    [ "$FLUENT_EXIT_ON_FAILURE" -eq 0 ]
}

@test "fluent_strict_mode enables exit on failure" {
    fluent_strict_mode
    [ "$FLUENT_EXIT_ON_FAILURE" -eq 1 ]
    # Reset for other tests
    export FLUENT_EXIT_ON_FAILURE=0
}

@test "fluent_json_mode sets JSON output" {
    fluent_json_mode
    [ "$FLUENT_OUTPUT_FORMAT" = "json" ]
    # Reset
    export FLUENT_OUTPUT_FORMAT=plain
}

@test "fluent_plain_mode sets plain output" {
    fluent_plain_mode
    [ "$FLUENT_OUTPUT_FORMAT" = "plain" ]
}

# =============================================================================
# COMPOUND CHECKS TESTS
# =============================================================================

@test "is::readable_file returns 0 for readable file" {
    touch "$TEST_DIR/readable"
    run is::readable_file "$TEST_DIR/readable"
    [ "$status" -eq 0 ]
}

@test "is::readable_file returns 1 for directory" {
    mkdir -p "$TEST_DIR/dir"
    run is::readable_file "$TEST_DIR/dir"
    [ "$status" -eq 1 ]
}

@test "is::writable_dir returns 0 for writable directory" {
    mkdir -p "$TEST_DIR/writable"
    run is::writable_dir "$TEST_DIR/writable"
    [ "$status" -eq 0 ]
}

@test "is::config_file returns 0 for valid config" {
    echo "key=value" > "$TEST_DIR/config"
    run is::config_file "$TEST_DIR/config"
    [ "$status" -eq 0 ]
}

@test "is::config_file returns 1 for empty file" {
    touch "$TEST_DIR/empty_config"
    run is::config_file "$TEST_DIR/empty_config"
    [ "$status" -eq 1 ]
}

# =============================================================================
# SIZE CHECKS TESTS
# =============================================================================

@test "is::smaller_than returns 0 for small file" {
    echo "tiny" > "$TEST_DIR/small"
    run is::smaller_than "$TEST_DIR/small" "1K"
    [ "$status" -eq 0 ]
}

@test "is::smaller_than returns 1 for large file" {
    dd if=/dev/zero of="$TEST_DIR/large" bs=1024 count=2 2>/dev/null
    run is::smaller_than "$TEST_DIR/large" "1K"
    [ "$status" -eq 1 ]
}

@test "is::larger_than returns 0 for large file" {
    dd if=/dev/zero of="$TEST_DIR/large" bs=1024 count=2 2>/dev/null
    run is::larger_than "$TEST_DIR/large" "1K"
    [ "$status" -eq 0 ]
}

@test "is::larger_than returns 1 for small file" {
    echo "tiny" > "$TEST_DIR/small"
    run is::larger_than "$TEST_DIR/small" "1K"
    [ "$status" -eq 1 ]
}

# =============================================================================
# CONTENT CHECKS TESTS
# =============================================================================

@test "is::containing returns 0 when file contains pattern" {
    echo "hello world" > "$TEST_DIR/test"
    run is::containing "$TEST_DIR/test" "world"
    [ "$status" -eq 0 ]
}

@test "is::containing returns 1 when file lacks pattern" {
    echo "hello" > "$TEST_DIR/test"
    run is::containing "$TEST_DIR/test" "world"
    [ "$status" -eq 1 ]
}

@test "is::starting_with returns 0 for matching prefix" {
    echo "#!/bin/bash" > "$TEST_DIR/script"
    run is::starting_with "$TEST_DIR/script" "#!"
    [ "$status" -eq 0 ]
}

@test "is::extension returns 0 for matching extension" {
    run is::extension "/path/file.txt" "txt"
    [ "$status" -eq 0 ]
}

@test "is::extension returns 1 for non-matching extension" {
    run is::extension "/path/file.txt" "md"
    [ "$status" -eq 1 ]
}

@test "is::bash_script returns 0 for bash script" {
    echo '#!/bin/bash' > "$TEST_DIR/script.sh"
    run is::bash_script "$TEST_DIR/script.sh"
    [ "$status" -eq 0 ]
}

@test "is::bash_script returns 0 for env bash" {
    echo '#!/usr/bin/env bash' > "$TEST_DIR/script.sh"
    run is::bash_script "$TEST_DIR/script.sh"
    [ "$status" -eq 0 ]
}

@test "is::bash_script returns 1 for non-bash" {
    echo '#!/usr/bin/python' > "$TEST_DIR/script.py"
    run is::bash_script "$TEST_DIR/script.py"
    [ "$status" -eq 1 ]
}

# =============================================================================
# COMPARISON CHECKS TESTS
# =============================================================================

@test "is::same_as returns 0 for identical files" {
    echo "content" > "$TEST_DIR/file1"
    echo "content" > "$TEST_DIR/file2"
    run is::same_as "$TEST_DIR/file1" "$TEST_DIR/file2"
    [ "$status" -eq 0 ]
}

@test "is::same_as returns 1 for different files" {
    echo "content1" > "$TEST_DIR/file1"
    echo "content2" > "$TEST_DIR/file2"
    run is::same_as "$TEST_DIR/file1" "$TEST_DIR/file2"
    [ "$status" -eq 1 ]
}

@test "is::different_from returns 0 for different files" {
    echo "content1" > "$TEST_DIR/file1"
    echo "content2" > "$TEST_DIR/file2"
    run is::different_from "$TEST_DIR/file1" "$TEST_DIR/file2"
    [ "$status" -eq 0 ]
}

# =============================================================================
# ERROR OUTPUT TESTS
# =============================================================================

@test "fluent_error_json outputs valid JSON" {
    export FLUENT_OUTPUT_FORMAT=json
    # fluent_error_json outputs to stderr, capture it
    run bash -c 'source "$MAINFRAME_ROOT/lib/fluent.sh"; fluent_error_json "/path/to/file" "file" "not_found" 2>&1'
    [[ "$output" == *'"success":false'* ]]
    [[ "$output" == *'"type":"assertion"'* ]]
    [[ "$output" == *'"check":"file"'* ]]
    [[ "$output" == *'"path":"/path/to/file"'* ]]
    export FLUENT_OUTPUT_FORMAT=plain
}

@test "fluent_error_plain outputs readable message" {
    # fluent_error_plain outputs to stderr, capture it
    run bash -c 'source "$MAINFRAME_ROOT/lib/fluent.sh"; fluent_error_plain "/path/to/file" "file" "not_found" 2>&1'
    [[ "$output" == *"ASSERTION FAILED"* ]]
    [[ "$output" == *"not_found"* ]]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "fluent_list_checks lists is:: functions" {
    run fluent_list_checks
    [ "$status" -eq 0 ]
    [[ "$output" == *"is::file"* ]]
    [[ "$output" == *"is::dir"* ]]
}

@test "fluent_list_assertions lists assert:: functions" {
    run fluent_list_assertions
    [ "$status" -eq 0 ]
    [[ "$output" == *"assert::file"* ]]
    [[ "$output" == *"assert::all"* ]]
}

@test "fluent_list_conditions lists when:: functions" {
    run fluent_list_conditions
    [ "$status" -eq 0 ]
    [[ "$output" == *"when::exists"* ]]
    [[ "$output" == *"when::missing"* ]]
}

@test "fluent_version returns version string" {
    run fluent_version
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}

@test "fluent_status returns JSON status" {
    run fluent_status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"version":"1.0.0"'* ]]
    [[ "$output" == *'"checks":'* ]]
    [[ "$output" == *'"assertions":'* ]]
}

# =============================================================================
# DURATION PARSING TESTS
# =============================================================================

@test "_fluent_duration_to_seconds parses seconds" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "30s")
    [ "$result" -eq 30 ]
}

@test "_fluent_duration_to_seconds parses minutes" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "5m")
    [ "$result" -eq 300 ]
}

@test "_fluent_duration_to_seconds parses hours" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "2h")
    [ "$result" -eq 7200 ]
}

@test "_fluent_duration_to_seconds parses days" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "1d")
    [ "$result" -eq 86400 ]
}

@test "_fluent_duration_to_seconds parses weeks" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "1w")
    [ "$result" -eq 604800 ]
}

@test "_fluent_duration_to_seconds parses compound duration" {
    source_lib "fluent"
    result=$(_fluent_duration_to_seconds "1h30m")
    [ "$result" -eq 5400 ]
}

# =============================================================================
# SIZE PARSING TESTS
# =============================================================================

@test "_fluent_parse_size parses bytes" {
    source_lib "fluent"
    result=$(_fluent_parse_size "1024")
    [ "$result" -eq 1024 ]
}

@test "_fluent_parse_size parses kilobytes" {
    source_lib "fluent"
    result=$(_fluent_parse_size "1K")
    [ "$result" -eq 1024 ]
}

@test "_fluent_parse_size parses megabytes" {
    source_lib "fluent"
    result=$(_fluent_parse_size "1M")
    [ "$result" -eq 1048576 ]
}

@test "_fluent_parse_size parses gigabytes" {
    source_lib "fluent"
    result=$(_fluent_parse_size "1G")
    [ "$result" -eq 1073741824 ]
}

# =============================================================================
# CHAINING TESTS (using && for AND logic)
# =============================================================================

@test "chained is:: checks work with &&" {
    echo "content" > "$TEST_DIR/testfile"
    chmod +rx "$TEST_DIR/testfile"
    if is::file "$TEST_DIR/testfile" && is::readable "$TEST_DIR/testfile" && is::nonempty "$TEST_DIR/testfile"; then
        result=0
    else
        result=1
    fi
    [ "$result" -eq 0 ]
}

@test "chained is:: checks fail correctly" {
    touch "$TEST_DIR/emptyfile"
    if is::file "$TEST_DIR/emptyfile" && is::readable "$TEST_DIR/emptyfile" && is::nonempty "$TEST_DIR/emptyfile"; then
        result=0
    else
        result=1
    fi
    [ "$result" -eq 1 ]
}

@test "when::exists && then::do executes command" {
    touch "$TEST_DIR/exists"
    result=""
    when::exists "$TEST_DIR/exists" && result="executed"
    [ "$result" = "executed" ]
}

@test "when::missing && then::do skips when exists" {
    touch "$TEST_DIR/exists"
    result="not_executed"
    when::missing "$TEST_DIR/exists" && result="executed"
    [ "$result" = "not_executed" ]
}

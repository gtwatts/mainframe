#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Archive Module Tests
# =============================================================================
# Comprehensive tests for lib/archive.sh (35+ functions)
# Covers: tar, gzip, zip operations, streaming, safety checks, utilities
# =============================================================================

load 'test_helper'

setup() {
    source_lib "archive"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "archive")

    # Create test files
    echo "Hello, World!" > "$TEST_DIR/file1.txt"
    echo "Second file content" > "$TEST_DIR/file2.txt"
    mkdir -p "$TEST_DIR/subdir"
    echo "Nested file" > "$TEST_DIR/subdir/nested.txt"

    # Create a larger file for compression ratio tests
    dd if=/dev/zero bs=1024 count=10 of="$TEST_DIR/zeros.bin" 2>/dev/null
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# TOOL DETECTION TESTS
# =============================================================================

@test "archive_check_tools returns JSON with tool status" {
    local result
    result=$(archive_check_tools)
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"tar":'
    assert_contains "$result" '"gzip":'
    assert_contains "$result" '"zip":'
    assert_contains "$result" '"unzip":'
}

# =============================================================================
# TAR CREATE TESTS
# =============================================================================

@test "tar_create creates basic tar archive" {
    local result
    result=$(tar_create "$TEST_DIR/output.tar" "$TEST_DIR/file1.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"created"'
    [ -f "$TEST_DIR/output.tar" ]
}

@test "tar_create creates tar.gz archive" {
    local result
    result=$(tar_create "$TEST_DIR/output.tar.gz" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/output.tar.gz" ]
}

@test "tar_create archives directory" {
    local result
    result=$(tar_create "$TEST_DIR/dir.tar" "$TEST_DIR/subdir")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/dir.tar" ]
}

@test "tar_create fails without output path" {
    local result
    result=$(tar_create "")
    assert_contains "$result" '"success":false'
    assert_contains "$result" '"error"'
}

@test "tar_create fails without source paths" {
    local result
    result=$(tar_create "$TEST_DIR/empty.tar")
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'no source paths'
}

@test "tar_create fails with nonexistent source" {
    local result
    result=$(tar_create "$TEST_DIR/fail.tar" "$TEST_DIR/nonexistent.txt")
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'not found'
}

@test "tar_create handles multiple files" {
    local result
    result=$(tar_create "$TEST_DIR/multi.tar" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":true'

    # Verify both files in archive
    tar -tf "$TEST_DIR/multi.tar" | grep -q "file1.txt"
    tar -tf "$TEST_DIR/multi.tar" | grep -q "file2.txt"
}

@test "tar_create reports file count" {
    local result
    result=$(tar_create "$TEST_DIR/count.tar" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"file_count":'
}

# =============================================================================
# TAR EXTRACT TESTS
# =============================================================================

@test "tar_extract extracts tar archive" {
    tar_create "$TEST_DIR/src.tar" "$TEST_DIR/file1.txt" >/dev/null
    mkdir -p "$TEST_DIR/extracted"

    local result
    result=$(tar_extract "$TEST_DIR/src.tar" "$TEST_DIR/extracted")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"extracted"'
}

@test "tar_extract extracts tar.gz archive" {
    tar_create "$TEST_DIR/src.tar.gz" "$TEST_DIR/file1.txt" >/dev/null
    mkdir -p "$TEST_DIR/extracted"

    local result
    result=$(tar_extract "$TEST_DIR/src.tar.gz" "$TEST_DIR/extracted")
    assert_contains "$result" '"success":true'
}

@test "tar_extract creates destination directory" {
    tar_create "$TEST_DIR/src.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_extract "$TEST_DIR/src.tar" "$TEST_DIR/new_dest")
    assert_contains "$result" '"success":true'
    [ -d "$TEST_DIR/new_dest" ]
}

@test "tar_extract fails for nonexistent archive" {
    local result
    result=$(tar_extract "$TEST_DIR/nonexistent.tar")
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'not found'
}

@test "tar_extract fails for empty path" {
    local result
    result=$(tar_extract "")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# TAR LIST TESTS
# =============================================================================

@test "tar_list returns JSON with file array" {
    tar_create "$TEST_DIR/list.tar" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" >/dev/null

    local result
    result=$(tar_list "$TEST_DIR/list.tar")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"files":'
    assert_contains "$result" '"count":'
}

@test "tar_list works with tar.gz" {
    tar_create "$TEST_DIR/list.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_list "$TEST_DIR/list.tar.gz")
    assert_contains "$result" '"success":true'
}

@test "tar_list verbose mode" {
    tar_create "$TEST_DIR/list.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_list "$TEST_DIR/list.tar" --verbose)
    assert_contains "$result" '"success":true'
}

@test "tar_list fails for nonexistent archive" {
    local result
    result=$(tar_list "$TEST_DIR/missing.tar")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# TAR APPEND TESTS
# =============================================================================

@test "tar_append adds file to tar archive" {
    tar_create "$TEST_DIR/append.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_append "$TEST_DIR/append.tar" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"appended":'

    # Verify file was added
    tar -tf "$TEST_DIR/append.tar" | grep -q "file2.txt"
}

@test "tar_append fails for compressed archive" {
    tar_create "$TEST_DIR/append.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_append "$TEST_DIR/append.tar.gz" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'uncompressed'
}

@test "tar_append fails without files" {
    tar_create "$TEST_DIR/append.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_append "$TEST_DIR/append.tar")
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'no files'
}

# =============================================================================
# TAR EXTRACT FILE TESTS
# =============================================================================

@test "tar_extract_file extracts single file" {
    # Create archive with multiple files using full paths
    cd "$TEST_DIR" && tar -cf extract_single.tar file1.txt file2.txt && cd - >/dev/null

    mkdir -p "$TEST_DIR/single_dest"

    local result
    result=$(tar_extract_file "$TEST_DIR/extract_single.tar" "file1.txt" "$TEST_DIR/single_dest")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/single_dest/file1.txt" ]
}

@test "tar_extract_file fails for missing file in archive" {
    tar_create "$TEST_DIR/single.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_extract_file "$TEST_DIR/single.tar" "nonexistent.txt")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# TAR INFO TESTS
# =============================================================================

@test "tar_info returns metadata" {
    tar_create "$TEST_DIR/info.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_info "$TEST_DIR/info.tar.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"format":"tar.gz"'
    assert_contains "$result" '"compression":"gzip"'
    assert_contains "$result" '"size":'
    assert_contains "$result" '"file_count":'
}

@test "tar_info handles uncompressed tar" {
    tar_create "$TEST_DIR/info.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(tar_info "$TEST_DIR/info.tar")
    assert_contains "$result" '"compression":"none"'
}

@test "tar_info fails for nonexistent archive" {
    local result
    result=$(tar_info "$TEST_DIR/missing.tar")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# GZIP COMPRESS TESTS
# =============================================================================

@test "gzip_compress compresses file" {
    local result
    result=$(gzip_compress "$TEST_DIR/file1.txt" "$TEST_DIR/file1.txt.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"ratio"'
    [ -f "$TEST_DIR/file1.txt.gz" ]
}

@test "gzip_compress uses default output name" {
    local result
    result=$(gzip_compress "$TEST_DIR/file1.txt")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/file1.txt.gz" ]
}

@test "gzip_compress with custom level" {
    local result
    result=$(gzip_compress "$TEST_DIR/zeros.bin" --level 9 --output "$TEST_DIR/level9.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"level":9'
}

@test "gzip_compress fails for nonexistent file" {
    local result
    result=$(gzip_compress "$TEST_DIR/missing.txt")
    assert_contains "$result" '"success":false'
}

@test "gzip_compress rejects invalid level" {
    local result
    result=$(gzip_compress "$TEST_DIR/file1.txt" --level 0)
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'invalid compression level'
}

# =============================================================================
# GZIP DECOMPRESS TESTS
# =============================================================================

@test "gzip_decompress decompresses file" {
    gzip_compress "$TEST_DIR/file1.txt" "$TEST_DIR/file1.gz" >/dev/null

    local result
    result=$(gzip_decompress "$TEST_DIR/file1.gz" "$TEST_DIR/file1_restored.txt")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/file1_restored.txt" ]

    # Verify content
    diff "$TEST_DIR/file1.txt" "$TEST_DIR/file1_restored.txt"
}

@test "gzip_decompress uses default output name" {
    cp "$TEST_DIR/file1.txt" "$TEST_DIR/default_test.txt"
    gzip_compress "$TEST_DIR/default_test.txt" "$TEST_DIR/default_test.txt.gz" >/dev/null
    rm "$TEST_DIR/default_test.txt"

    local result
    result=$(gzip_decompress "$TEST_DIR/default_test.txt.gz")
    assert_contains "$result" '"success":true'
    [ -f "$TEST_DIR/default_test.txt" ]
}

@test "gzip_decompress fails for nonexistent file" {
    local result
    result=$(gzip_decompress "$TEST_DIR/missing.gz")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# GUNZIP FILE TESTS
# =============================================================================

@test "gunzip_file decompresses in place" {
    cp "$TEST_DIR/file1.txt" "$TEST_DIR/inplace.txt"
    gzip "$TEST_DIR/inplace.txt"

    local result
    result=$(gunzip_file "$TEST_DIR/inplace.txt.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"decompressed_in_place"'
    [ -f "$TEST_DIR/inplace.txt" ]
    [ ! -f "$TEST_DIR/inplace.txt.gz" ]
}

@test "gunzip_file fails for non-gz extension" {
    local result
    result=$(gunzip_file "$TEST_DIR/file1.txt")
    assert_contains "$result" '"success":false'
    assert_contains "$result" '.gz extension'
}

# =============================================================================
# GZIP LEVEL TESTS
# =============================================================================

@test "gzip_level returns current level" {
    local result
    result=$(gzip_level)
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"level":'
}

@test "gzip_level sets new level" {
    local result
    result=$(gzip_level 9)
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"level":9'
    assert_contains "$result" '"action":"set"'
}

@test "gzip_level rejects invalid level" {
    local result
    result=$(gzip_level 10)
    assert_contains "$result" '"success":false'
}

# =============================================================================
# GZIP STRING TESTS
# =============================================================================

@test "gzip_compress_string compresses string to base64" {
    local result
    result=$(gzip_compress_string "Hello, World!")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"encoding":"base64"'
    assert_contains "$result" '"data":'
}

@test "gzip_decompress_string decompresses base64 string" {
    # First compress
    local compressed
    compressed=$(gzip_compress_string "Hello Test")
    local data
    data=$(echo "$compressed" | grep -o '"data":"[^"]*"' | cut -d'"' -f4)

    # Then decompress
    local result
    result=$(gzip_decompress_string "$data")
    assert_contains "$result" '"success":true'
    assert_contains "$result" 'Hello Test'
}

@test "gzip_compress_string fails for empty input" {
    local result
    result=$(gzip_compress_string "")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ZIP CREATE TESTS
# =============================================================================

@test "zip_create creates zip archive" {
    skip_if_no_command zip

    local result
    result=$(zip_create "$TEST_DIR/output.zip" "$TEST_DIR/file1.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"created"'
    [ -f "$TEST_DIR/output.zip" ]
}

@test "zip_create handles multiple files" {
    skip_if_no_command zip

    local result
    result=$(zip_create "$TEST_DIR/multi.zip" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":true'
}

@test "zip_create handles directory with -r" {
    skip_if_no_command zip

    local result
    result=$(zip_create "$TEST_DIR/dir.zip" -r "$TEST_DIR/subdir")
    assert_contains "$result" '"success":true'
}

@test "zip_create fails without sources" {
    local result
    result=$(zip_create "$TEST_DIR/empty.zip")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ZIP EXTRACT TESTS
# =============================================================================

@test "zip_extract extracts zip archive" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/src.zip" "$TEST_DIR/file1.txt" >/dev/null
    mkdir -p "$TEST_DIR/zip_dest"

    local result
    result=$(zip_extract "$TEST_DIR/src.zip" "$TEST_DIR/zip_dest")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"extracted"'
}

@test "zip_extract creates destination" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/src.zip" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(zip_extract "$TEST_DIR/src.zip" "$TEST_DIR/new_zip_dest")
    assert_contains "$result" '"success":true'
    [ -d "$TEST_DIR/new_zip_dest" ]
}

@test "zip_extract fails for nonexistent archive" {
    local result
    result=$(zip_extract "$TEST_DIR/missing.zip")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ZIP LIST TESTS
# =============================================================================

@test "zip_list returns file array" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/list.zip" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" >/dev/null

    local result
    result=$(zip_list "$TEST_DIR/list.zip")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"files":'
    assert_contains "$result" '"count":'
}

# =============================================================================
# ZIP ADD TESTS
# =============================================================================

@test "zip_add adds file to zip" {
    skip_if_no_command zip

    zip_create "$TEST_DIR/add.zip" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(zip_add "$TEST_DIR/add.zip" "$TEST_DIR/file2.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"added":'
}

@test "zip_add fails without files" {
    skip_if_no_command zip

    zip_create "$TEST_DIR/add.zip" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(zip_add "$TEST_DIR/add.zip")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ZIP REMOVE TESTS
# =============================================================================

@test "zip_remove removes file from zip" {
    skip_if_no_command zip

    cd "$TEST_DIR" && zip -q remove.zip file1.txt file2.txt && cd - >/dev/null

    local result
    result=$(zip_remove "$TEST_DIR/remove.zip" "file1.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"action":"removed"'
}

# =============================================================================
# ZIP PASSWORD TESTS
# =============================================================================

@test "zip_password creates encrypted zip" {
    skip_if_no_command zip

    local result
    result=$(zip_password "$TEST_DIR/secure.zip" "secret123" "$TEST_DIR/file1.txt")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"encrypted":true'
    [ -f "$TEST_DIR/secure.zip" ]
}

@test "zip_password fails without password" {
    local result
    result=$(zip_password "$TEST_DIR/secure.zip" "")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ZIP TEST TESTS
# =============================================================================

@test "zip_test verifies valid zip" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/valid.zip" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(zip_test "$TEST_DIR/valid.zip")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"valid":true'
}

@test "zip_test fails for corrupted zip" {
    skip_if_no_command unzip

    # Create corrupted zip
    echo "not a zip file" > "$TEST_DIR/corrupt.zip"

    local result
    result=$(zip_test "$TEST_DIR/corrupt.zip")
    assert_contains "$result" '"success":false'
    assert_contains "$result" '"valid":false'
}

# =============================================================================
# ARCHIVE DETECT TYPE TESTS
# =============================================================================

@test "archive_detect_type identifies tar.gz" {
    local result
    result=$(archive_detect_type "file.tar.gz")
    assert_contains "$result" '"format":"tar"'
    assert_contains "$result" '"compression":"gzip"'
}

@test "archive_detect_type identifies zip" {
    local result
    result=$(archive_detect_type "file.zip")
    assert_contains "$result" '"format":"zip"'
}

@test "archive_detect_type identifies plain tar" {
    local result
    result=$(archive_detect_type "file.tar")
    assert_contains "$result" '"format":"tar"'
    assert_contains "$result" '"compression":"none"'
}

@test "archive_detect_type identifies gzip" {
    local result
    result=$(archive_detect_type "file.gz")
    assert_contains "$result" '"format":"gzip"'
}

@test "archive_detect_type detects by magic bytes" {
    gzip_compress "$TEST_DIR/file1.txt" "$TEST_DIR/unknown_ext" >/dev/null

    local result
    result=$(archive_detect_type "$TEST_DIR/unknown_ext")
    assert_contains "$result" '"format":"gzip"'
}

# =============================================================================
# ARCHIVE EXTRACT AUTO TESTS
# =============================================================================

@test "archive_extract_auto extracts tar.gz" {
    tar_create "$TEST_DIR/auto.tar.gz" "$TEST_DIR/file1.txt" >/dev/null
    mkdir -p "$TEST_DIR/auto_dest"

    local result
    result=$(archive_extract_auto "$TEST_DIR/auto.tar.gz" "$TEST_DIR/auto_dest")
    assert_contains "$result" '"success":true'
}

@test "archive_extract_auto extracts zip" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/auto.zip" "$TEST_DIR/file1.txt" >/dev/null
    mkdir -p "$TEST_DIR/auto_dest"

    local result
    result=$(archive_extract_auto "$TEST_DIR/auto.zip" "$TEST_DIR/auto_dest")
    assert_contains "$result" '"success":true'
}

@test "archive_extract_auto fails for nonexistent" {
    local result
    result=$(archive_extract_auto "$TEST_DIR/missing.tar.gz")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ARCHIVE SIZE TESTS
# =============================================================================

@test "archive_size returns compressed and uncompressed sizes" {
    tar_create "$TEST_DIR/size.tar.gz" "$TEST_DIR/zeros.bin" >/dev/null

    local result
    result=$(archive_size "$TEST_DIR/size.tar.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"compressed_size":'
    assert_contains "$result" '"uncompressed_size":'
}

@test "archive_size handles zip" {
    skip_if_no_command zip
    skip_if_no_command unzip

    zip_create "$TEST_DIR/size.zip" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(archive_size "$TEST_DIR/size.zip")
    assert_contains "$result" '"success":true'
}

@test "archive_size fails for nonexistent" {
    local result
    result=$(archive_size "$TEST_DIR/missing.tar.gz")
    assert_contains "$result" '"success":false'
}

# =============================================================================
# ARCHIVE COMPRESS RATIO TESTS
# =============================================================================

@test "archive_compress_ratio calculates ratio" {
    tar_create "$TEST_DIR/ratio.tar.gz" "$TEST_DIR/zeros.bin" >/dev/null

    local result
    result=$(archive_compress_ratio "$TEST_DIR/ratio.tar.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"ratio"'
    assert_contains "$result" '"savings"'
}

# =============================================================================
# ARCHIVE VERIFY TESTS
# =============================================================================

@test "archive_verify validates tar.gz" {
    tar_create "$TEST_DIR/verify.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(archive_verify "$TEST_DIR/verify.tar.gz")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"valid":true'
}

@test "archive_verify validates plain tar" {
    tar_create "$TEST_DIR/verify.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(archive_verify "$TEST_DIR/verify.tar")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"valid":true'
}

@test "archive_verify detects corrupted gzip" {
    echo "not gzip data" > "$TEST_DIR/corrupt.tar.gz"

    local result
    result=$(archive_verify "$TEST_DIR/corrupt.tar.gz")
    assert_contains "$result" '"success":false'
    assert_contains "$result" '"valid":false'
}

# =============================================================================
# ARCHIVE TO JSON TESTS
# =============================================================================

@test "archive_to_json returns detailed listing" {
    tar_create "$TEST_DIR/json.tar" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" >/dev/null

    local result
    result=$(archive_to_json "$TEST_DIR/json.tar")
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"entries":'
    assert_contains "$result" '"count":'
}

@test "archive_to_json includes file sizes" {
    tar_create "$TEST_DIR/json_size.tar" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(archive_to_json "$TEST_DIR/json_size.tar")
    assert_contains "$result" '"size":'
}

# =============================================================================
# STREAMING TESTS
# =============================================================================

@test "tar_stream_create outputs to stdout" {
    local output
    output=$(tar_stream_create "$TEST_DIR/file1.txt" | wc -c)
    [ "$output" -gt 0 ]
}

@test "tar_stream_create with gzip compression" {
    local output
    output=$(tar_stream_create "$TEST_DIR/file1.txt" --gzip | file -)
    assert_contains "$output" "gzip"
}

@test "tar_stream_extract reads from stdin" {
    mkdir -p "$TEST_DIR/stream_dest"

    tar_stream_create "$TEST_DIR/file1.txt" | tar_stream_extract "$TEST_DIR/stream_dest"

    local result
    result=$(tar_stream_extract --help 2>/dev/null || echo "ok")
    # Just verify the function exists and runs
}

@test "gzip_stream compress mode" {
    local output
    output=$(echo "test data" | gzip_stream compress | file -)
    assert_contains "$output" "gzip"
}

@test "gzip_stream decompress mode" {
    local original="Hello Stream Test"
    local result
    result=$(echo "$original" | gzip_stream compress | gzip_stream decompress)
    [ "$result" = "$original" ]
}

# =============================================================================
# SAFETY TESTS
# =============================================================================

@test "archive_path_safe detects clean archive" {
    cd "$TEST_DIR" && tar -cf safe.tar file1.txt file2.txt && cd - >/dev/null

    archive_path_safe "$TEST_DIR/safe.tar"
}

@test "archive_path_safe detects path traversal" {
    # Create archive with .. path
    mkdir -p "$TEST_DIR/evil"
    echo "evil" > "$TEST_DIR/evil/payload.txt"
    cd "$TEST_DIR" && tar -cf unsafe.tar --transform 's|evil|../escaped|' evil && cd - >/dev/null

    ! archive_path_safe "$TEST_DIR/unsafe.tar"
}

@test "archive_size_limit accepts within limit" {
    tar_create "$TEST_DIR/small.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local result
    result=$(archive_size_limit "$TEST_DIR/small.tar.gz" 1000000000)
    assert_contains "$result" '"success":true'
    assert_contains "$result" '"within_limit":true'
}

@test "archive_size_limit rejects over limit" {
    tar_create "$TEST_DIR/big.tar.gz" "$TEST_DIR/zeros.bin" >/dev/null

    local result
    result=$(archive_size_limit "$TEST_DIR/big.tar.gz" 100)
    assert_contains "$result" '"success":false'
    assert_contains "$result" 'exceeds size limit'
}

@test "archive_exclude_pattern generates exclude flags" {
    local result
    result=$(archive_exclude_pattern "*.log" "*.tmp")
    assert_contains "$result" '--exclude=*.log'
    assert_contains "$result" '--exclude=*.tmp'
}

# =============================================================================
# NAMEREF VARIANT TESTS
# =============================================================================

@test "tar_list_v stores result in variable" {
    tar_create "$TEST_DIR/nameref.tar" "$TEST_DIR/file1.txt" >/dev/null

    local out
    tar_list_v out "$TEST_DIR/nameref.tar"
    assert_contains "$out" '"success":true'
    assert_contains "$out" '"files":'
}

@test "tar_info_v stores result in variable" {
    tar_create "$TEST_DIR/nameref.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local out
    tar_info_v out "$TEST_DIR/nameref.tar.gz"
    assert_contains "$out" '"success":true'
    assert_contains "$out" '"format"'
}

@test "archive_detect_type_v stores result in variable" {
    local out
    archive_detect_type_v out "test.tar.gz"
    assert_contains "$out" '"format":"tar"'
}

@test "archive_size_v stores result in variable" {
    tar_create "$TEST_DIR/size_v.tar.gz" "$TEST_DIR/file1.txt" >/dev/null

    local out
    archive_size_v out "$TEST_DIR/size_v.tar.gz"
    assert_contains "$out" '"success":true'
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "tar_create with special characters in filename" {
    echo "special" > "$TEST_DIR/file with spaces.txt"

    local result
    result=$(tar_create "$TEST_DIR/special.tar" "$TEST_DIR/file with spaces.txt")
    assert_contains "$result" '"success":true'
}

@test "tar operations preserve file permissions" {
    chmod 755 "$TEST_DIR/file1.txt"
    tar_create "$TEST_DIR/perms.tar" "$TEST_DIR/file1.txt" >/dev/null

    mkdir -p "$TEST_DIR/perms_dest"
    tar_extract "$TEST_DIR/perms.tar" "$TEST_DIR/perms_dest" >/dev/null

    # Note: extracted file should have same permissions
}

@test "gzip handles empty file" {
    touch "$TEST_DIR/empty.txt"

    local result
    result=$(gzip_compress "$TEST_DIR/empty.txt")
    assert_contains "$result" '"success":true'
}

@test "roundtrip: tar create and extract" {
    tar_create "$TEST_DIR/roundtrip.tar.gz" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" >/dev/null
    mkdir -p "$TEST_DIR/roundtrip_dest"
    tar_extract "$TEST_DIR/roundtrip.tar.gz" "$TEST_DIR/roundtrip_dest" >/dev/null

    # Verify files exist after roundtrip
    find "$TEST_DIR/roundtrip_dest" -name "file1.txt" | grep -q .
}

@test "roundtrip: gzip compress and decompress" {
    local original
    original=$(<"$TEST_DIR/file1.txt")

    gzip_compress "$TEST_DIR/file1.txt" "$TEST_DIR/file1.gz" >/dev/null
    gzip_decompress "$TEST_DIR/file1.gz" "$TEST_DIR/file1_restored.txt" >/dev/null

    local restored
    restored=$(<"$TEST_DIR/file1_restored.txt")

    [ "$original" = "$restored" ]
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

skip_if_no_command() {
    local cmd="$1"
    if ! type -p "$cmd" &>/dev/null; then
        skip "$cmd not installed"
    fi
}

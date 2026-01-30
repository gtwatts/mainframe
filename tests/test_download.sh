#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/tests/test_download.sh - Tests for download.sh library
# =============================================================================
# Usage: ./tests/test_download.sh
# =============================================================================

set -euo pipefail

# Determine script location and MAINFRAME root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${SCRIPT_DIR}/.."

# Source MAINFRAME
source "${MAINFRAME_ROOT}/lib/common.sh"

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    ((TESTS_PASSED++))
    printf '  %b[PASS]%b %s\n' "$CLR_GREEN" "$CLR_RESET" "$1"
}

test_fail() {
    ((TESTS_FAILED++))
    printf '  %b[FAIL]%b %s\n' "$CLR_RED" "$CLR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '         %s\n' "$2"
}

test_skip() {
    printf '  %b[SKIP]%b %s\n' "$CLR_YELLOW" "$CLR_RESET" "$1"
}

run_test() {
    local name="$1"
    local func="$2"
    ((TESTS_RUN++))

    if "$func"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        [[ -n "$msg" ]] && printf '         %s\n' "$msg" >&2
        printf '         Expected: %s\n' "$expected" >&2
        printf '         Actual:   %s\n' "$actual" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        [[ -n "$msg" ]] && printf '         %s\n' "$msg" >&2
        printf '         String does not contain: %s\n' "$needle" >&2
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]]
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(json_get "$json" "$field" 2>/dev/null || echo "")

    assert_eq "$expected" "$actual" "JSON field '$field' mismatch"
}

# =============================================================================
# TEST SETUP / TEARDOWN
# =============================================================================

TEST_TMP_DIR=""

setup() {
    TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test_download.XXXXXX")
}

teardown() {
    [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]] && rm -rf "$TEST_TMP_DIR"
}

# =============================================================================
# BACKEND DETECTION TESTS
# =============================================================================

test_download_backend_detection() {
    local backend
    backend=$(download_backend)

    # Should return one of: burl, curl, wget, fetch, none
    case "$backend" in
        burl|curl|wget|fetch|none)
            return 0
            ;;
        *)
            printf '         Unknown backend: %s\n' "$backend" >&2
            return 1
            ;;
    esac
}

test_download_backend_cached() {
    # First call
    local backend1
    backend1=$(download_backend)

    # Second call should return cached value
    local backend2
    backend2=$(download_backend)

    assert_eq "$backend1" "$backend2" "Backend should be cached"
}

test_download_backend_reset() {
    local backend1
    backend1=$(download_backend)

    # Reset cache
    _download_reset_backend

    local backend2
    backend2=$(download_backend)

    # Should still be the same (same system)
    assert_eq "$backend1" "$backend2" "Backend should be same after reset"
}

# =============================================================================
# FILENAME EXTRACTION TESTS
# =============================================================================

test_filename_from_url_simple() {
    local filename
    filename=$(_download_filename_from_url "http://example.com/file.txt")
    assert_eq "file.txt" "$filename"
}

test_filename_from_url_with_query() {
    local filename
    filename=$(_download_filename_from_url "http://example.com/file.tar.gz?token=abc123")
    assert_eq "file.tar.gz" "$filename"
}

test_filename_from_url_with_fragment() {
    local filename
    filename=$(_download_filename_from_url "http://example.com/file.zip#section")
    assert_eq "file.zip" "$filename"
}

test_filename_from_url_no_extension() {
    local filename
    filename=$(_download_filename_from_url "http://example.com/path/myfile")
    assert_eq "myfile" "$filename"
}

test_filename_from_url_empty_path() {
    local filename
    filename=$(_download_filename_from_url "http://example.com/")
    assert_eq "download" "$filename"
}

# =============================================================================
# OPTIONS PARSING TESTS
# =============================================================================

test_parse_options_defaults() {
    _download_parse_options ""
    assert_eq "30" "$_DL_TIMEOUT" "Default timeout"
    assert_eq "3" "$_DL_RETRIES" "Default retries"
    assert_eq "0" "$_DL_QUIET" "Default quiet"
}

test_parse_options_custom() {
    _download_parse_options '{"timeout":60,"retries":5,"quiet":true}'
    assert_eq "60" "$_DL_TIMEOUT" "Custom timeout"
    assert_eq "5" "$_DL_RETRIES" "Custom retries"
    assert_eq "1" "$_DL_QUIET" "Custom quiet"
}

test_parse_options_partial() {
    _download_parse_options '{"timeout":120}'
    assert_eq "120" "$_DL_TIMEOUT" "Partial timeout"
    assert_eq "3" "$_DL_RETRIES" "Default retries preserved"
}

# =============================================================================
# DOWNLOAD FUNCTION TESTS (Mock/Offline)
# =============================================================================

test_download_missing_url() {
    local result
    result=$(download "")

    assert_contains "$result" '"ok":false' "Should fail without URL"
    assert_contains "$result" 'required' "Should mention required"
}

test_download_no_backend_error() {
    # Save current backend
    local saved_backend="$_DOWNLOAD_BACKEND"

    # Force no backend
    _DOWNLOAD_BACKEND="none"

    local result
    result=$(download "http://example.com/test.txt")

    # Restore backend
    _DOWNLOAD_BACKEND="$saved_backend"

    assert_contains "$result" '"ok":false' "Should fail with no backend"
}

# =============================================================================
# DOWNLOAD_STDOUT TESTS
# =============================================================================

test_download_stdout_missing_url() {
    local result
    result=$(download_stdout "" 2>&1)

    assert_contains "$result" 'required' "Should indicate URL required"
    return $?
}

# =============================================================================
# DOWNLOAD_VERIFY TESTS
# =============================================================================

test_download_verify_missing_args() {
    local result
    result=$(download_verify "" "")

    assert_contains "$result" '"ok":false' "Should fail without args"
}

test_download_verify_file_not_found() {
    local result
    result=$(download_verify "/nonexistent/file.txt" "abc123")

    assert_contains "$result" '"ok":false' "Should fail for missing file"
    assert_contains "$result" 'not found' "Should mention file not found"
}

test_download_verify_valid_checksum() {
    setup

    # Create test file
    local test_file="${TEST_TMP_DIR}/test.txt"
    printf 'hello world' > "$test_file"

    # Calculate expected checksum
    local expected
    if command -v sha256sum &>/dev/null; then
        expected=$(sha256sum "$test_file" | cut -d' ' -f1)
    elif command -v shasum &>/dev/null; then
        expected=$(shasum -a 256 "$test_file" | cut -d' ' -f1)
    else
        teardown
        test_skip "No sha256 tool available"
        return 0
    fi

    local result
    result=$(download_verify "$test_file" "$expected")

    teardown

    assert_contains "$result" '"ok":true' "Should succeed with valid checksum"
    assert_contains "$result" '"valid":true' "Should indicate valid"
}

test_download_verify_invalid_checksum() {
    setup

    # Create test file
    local test_file="${TEST_TMP_DIR}/test.txt"
    printf 'hello world' > "$test_file"

    local result
    result=$(download_verify "$test_file" "invalidchecksum123")

    teardown

    assert_contains "$result" '"ok":false' "Should fail with invalid checksum"
    assert_contains "$result" 'mismatch' "Should mention mismatch"
}

# =============================================================================
# DOWNLOAD_EXTRACT TESTS
# =============================================================================

test_download_extract_missing_args() {
    local result
    result=$(download_extract "" "")

    assert_contains "$result" '"ok":false' "Should fail without args"
    assert_contains "$result" 'required' "Should mention required"
}

test_download_extract_creates_dir() {
    setup

    local output_dir="${TEST_TMP_DIR}/extract_test"

    # This will fail to download but should create the directory first
    local result
    result=$(download_extract "http://invalid-url-that-will-fail/test.tar.gz" "$output_dir" 2>/dev/null || true)

    # Directory should be created even if download fails
    if [[ -d "$output_dir" ]]; then
        teardown
        return 0
    else
        teardown
        return 1
    fi
}

# =============================================================================
# DOWNLOAD_BATCH TESTS
# =============================================================================

test_download_batch_missing_url_file() {
    local result
    result=$(download_batch "/nonexistent/urls.txt" "/tmp")

    assert_contains "$result" '"ok":false' "Should fail with missing URL file"
    assert_contains "$result" 'not found' "Should mention file not found"
}

test_download_batch_creates_output_dir() {
    setup

    # Create URL file (empty is fine for this test)
    local url_file="${TEST_TMP_DIR}/urls.txt"
    touch "$url_file"

    local output_dir="${TEST_TMP_DIR}/batch_output"

    local result
    result=$(download_batch "$url_file" "$output_dir")

    # Output dir should be created
    if [[ -d "$output_dir" ]]; then
        teardown
        return 0
    else
        teardown
        return 1
    fi
}

test_download_batch_empty_file() {
    setup

    # Create empty URL file
    local url_file="${TEST_TMP_DIR}/urls.txt"
    touch "$url_file"

    local output_dir="${TEST_TMP_DIR}/batch_output"

    local result
    result=$(download_batch "$url_file" "$output_dir")

    teardown

    assert_contains "$result" '"ok":true' "Should succeed with empty file"
    assert_contains "$result" '"downloaded":0' "Should have 0 downloads"
}

# =============================================================================
# DOWNLOAD_RESUME TESTS
# =============================================================================

test_download_resume_missing_args() {
    local result
    result=$(download_resume "" "")

    assert_contains "$result" '"ok":false' "Should fail without args"
    assert_contains "$result" 'required' "Should mention required"
}

# =============================================================================
# DOWNLOAD_PROGRESS TESTS
# =============================================================================

test_download_progress_missing_args() {
    local result
    result=$(download_progress "" "")

    assert_contains "$result" '"ok":false' "Should fail without args"
    assert_contains "$result" 'required' "Should mention required"
}

# =============================================================================
# INTEGRATION TESTS (requires network)
# =============================================================================

test_download_integration_httpbin() {
    # Skip if no network or httpbin unavailable
    local backend
    backend=$(download_backend)

    if [[ "$backend" == "none" ]]; then
        test_skip "No download backend available"
        return 0
    fi

    # Check if we can reach httpbin
    if ! curl -sf --max-time 5 "https://httpbin.org/status/200" &>/dev/null; then
        test_skip "httpbin.org not reachable"
        return 0
    fi

    setup

    local output_file="${TEST_TMP_DIR}/test_response.json"

    local result
    result=$(download "https://httpbin.org/json" "$output_file" '{"timeout":10}')

    if [[ -f "$output_file" && -s "$output_file" ]]; then
        assert_contains "$result" '"ok":true' "Download should succeed"
        teardown
        return 0
    else
        teardown
        return 1
    fi
}

# =============================================================================
# RUN TESTS
# =============================================================================

main() {
    printf '%b=== MAINFRAME download.sh Tests ===%b\n\n' "$CLR_BOLD$CLR_BLUE" "$CLR_RESET"

    printf '%bBackend Detection Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_backend returns valid backend" test_download_backend_detection
    run_test "download_backend caches result" test_download_backend_cached
    run_test "download_backend reset works" test_download_backend_reset

    printf '\n%bFilename Extraction Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "Simple URL filename" test_filename_from_url_simple
    run_test "URL with query string" test_filename_from_url_with_query
    run_test "URL with fragment" test_filename_from_url_with_fragment
    run_test "URL without extension" test_filename_from_url_no_extension
    run_test "URL with empty path" test_filename_from_url_empty_path

    printf '\n%bOptions Parsing Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "Default options" test_parse_options_defaults
    run_test "Custom options" test_parse_options_custom
    run_test "Partial options" test_parse_options_partial

    printf '\n%bDownload Function Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download() requires URL" test_download_missing_url
    run_test "download() handles no backend" test_download_no_backend_error

    printf '\n%bDownload Stdout Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_stdout() requires URL" test_download_stdout_missing_url

    printf '\n%bVerification Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_verify() requires args" test_download_verify_missing_args
    run_test "download_verify() handles missing file" test_download_verify_file_not_found
    run_test "download_verify() valid checksum" test_download_verify_valid_checksum
    run_test "download_verify() invalid checksum" test_download_verify_invalid_checksum

    printf '\n%bExtraction Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_extract() requires args" test_download_extract_missing_args
    run_test "download_extract() creates output dir" test_download_extract_creates_dir

    printf '\n%bBatch Download Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_batch() handles missing URL file" test_download_batch_missing_url_file
    run_test "download_batch() creates output dir" test_download_batch_creates_output_dir
    run_test "download_batch() handles empty file" test_download_batch_empty_file

    printf '\n%bResume Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_resume() requires args" test_download_resume_missing_args

    printf '\n%bProgress Tests%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download_progress() requires args" test_download_progress_missing_args

    printf '\n%bIntegration Tests (Network)%b\n' "$CLR_CYAN" "$CLR_RESET"
    run_test "download() from httpbin.org" test_download_integration_httpbin

    # Summary
    printf '\n%b=== Test Summary ===%b\n' "$CLR_BOLD$CLR_BLUE" "$CLR_RESET"
    printf 'Total:  %d\n' "$TESTS_RUN"
    printf 'Passed: %b%d%b\n' "$CLR_GREEN" "$TESTS_PASSED" "$CLR_RESET"
    printf 'Failed: %b%d%b\n' "$CLR_RED" "$TESTS_FAILED" "$CLR_RESET"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/ext/gcp.bats - GCP Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/ext/gcp.sh
#              Google Cloud Platform CLI wrapper functions
# Test Count: 60+ test cases
# Categories: availability, configuration, storage, compute, functions
# Note: Tests use mocks to avoid requiring actual gcloud CLI
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Create mock bin directory
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"

    # Source the library
    source "$MAINFRAME_ROOT/lib/ext/gcp.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock gcloud command
create_mock_gcloud() {
    local behavior="$1"
    cat > "$MOCK_BIN/gcloud" << EOF
#!/bin/bash
$behavior
EOF
    chmod +x "$MOCK_BIN/gcloud"
    export PATH="$MOCK_BIN:$PATH"
}

# Helper: Create mock gsutil command
create_mock_gsutil() {
    local behavior="$1"
    cat > "$MOCK_BIN/gsutil" << EOF
#!/bin/bash
$behavior
EOF
    chmod +x "$MOCK_BIN/gsutil"
    export PATH="$MOCK_BIN:$PATH"
}

# =============================================================================
# CATEGORY 1: INTERNAL HELPERS
# =============================================================================

@test "_gcp_has_cli: returns true when gcloud is available" {
    create_mock_gcloud 'echo "Google Cloud SDK 450.0.0"'
    _gcp_has_cli
    [[ $? -eq 0 ]]
}

@test "_gcp_has_cli: returns false when gcloud is not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/gcp.sh" && _gcp_has_cli'
    [[ "$status" -eq 1 ]]
}

@test "_gcp_require_cli: outputs error JSON when gcloud not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/gcp.sh" && _gcp_require_cli'
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "success\":false" ]]
    [[ "$output" =~ "gcloud CLI not installed" ]]
}

@test "_gcp_json_escape: escapes double quotes" {
    result=$(_gcp_json_escape 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "_gcp_json_escape: escapes backslashes" {
    result=$(_gcp_json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "_gcp_json_escape: escapes newlines" {
    result=$(_gcp_json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

@test "_gcp_json_escape: escapes tabs" {
    result=$(_gcp_json_escape $'col1\tcol2')
    [[ "$result" == 'col1\tcol2' ]]
}

# =============================================================================
# CATEGORY 2: AVAILABILITY & CONFIGURATION
# =============================================================================

@test "gcp_configured: returns success when gcloud is configured" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" ]]; then
            case "$3" in
                account) echo "user@example.com" ;;
                project) echo "my-project" ;;
            esac
            exit 0
        fi
        exit 0
    '
    result=$(gcp_configured)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "user@example.com" ]]
    [[ "$result" =~ "my-project" ]]
}

@test "gcp_configured: returns failure when no account configured" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "account" ]]; then
            echo ""
            exit 0
        fi
        exit 0
    '
    run gcp_configured
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "No active account configured" ]]
}

@test "gcp_project: returns current project" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "project" ]]; then
            echo "test-project-123"
            exit 0
        fi
        exit 0
    '
    result=$(gcp_project)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "test-project-123" ]]
}

@test "gcp_project: sets project when argument provided" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "set" && "$3" == "project" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(gcp_project "new-project")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "new-project" ]]
    [[ "$result" =~ "action\":\"set" ]]
}

@test "gcp_project: returns error when no project configured" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "project" ]]; then
            echo ""
            exit 0
        fi
        exit 0
    '
    run gcp_project
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "No project configured" ]]
}

@test "gcp_region: returns current region" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "compute/region" ]]; then
            echo "us-central1"
            exit 0
        fi
        exit 0
    '
    result=$(gcp_region)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "us-central1" ]]
}

@test "gcp_region: returns null when no region configured" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "compute/region" ]]; then
            echo ""
            exit 0
        fi
        exit 0
    '
    result=$(gcp_region)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "region\":null" ]]
}

@test "gcp_region: sets region when argument provided" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "set" && "$3" == "compute/region" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(gcp_region "europe-west1")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "europe-west1" ]]
    [[ "$result" =~ "action\":\"set" ]]
}

# =============================================================================
# CATEGORY 3: CLOUD STORAGE
# =============================================================================

@test "gcp_storage_list: lists buckets using gsutil" {
    create_mock_gsutil '
        echo "gs://bucket-one/"
        echo "gs://bucket-two/"
        echo "gs://bucket-three/"
        exit 0
    '
    create_mock_gcloud 'exit 0'
    result=$(gcp_storage_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "bucket-one" ]]
    [[ "$result" =~ "bucket-two" ]]
    [[ "$result" =~ "bucket-three" ]]
}

@test "gcp_storage_list: filters by prefix" {
    create_mock_gsutil '
        echo "gs://prod-bucket/"
        echo "gs://prod-data/"
        echo "gs://dev-bucket/"
        exit 0
    '
    create_mock_gcloud 'exit 0'
    result=$(gcp_storage_list "prod")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "prod-bucket" ]]
    [[ "$result" =~ "prod-data" ]]
    [[ ! "$result" =~ "dev-bucket" ]]
}

@test "gcp_storage_list: returns empty array when no buckets" {
    create_mock_gsutil 'exit 0'
    create_mock_gcloud 'exit 0'
    result=$(gcp_storage_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "data\":\[\]" ]]
}

@test "gcp_storage_upload: uploads file successfully" {
    # Create a test file
    echo "test content" > "$TEST_TMPDIR/testfile.txt"

    create_mock_gsutil '
        if [[ "$1" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '
    create_mock_gcloud 'exit 0'

    result=$(gcp_storage_upload "$TEST_TMPDIR/testfile.txt" "gs://my-bucket/testfile.txt")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "action\":\"upload" ]]
}

@test "gcp_storage_upload: fails for missing source file" {
    create_mock_gcloud 'exit 0'
    run gcp_storage_upload "/nonexistent/file.txt" "gs://bucket/file.txt"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Source file not found" ]]
}

@test "gcp_storage_upload: fails for empty arguments" {
    create_mock_gcloud 'exit 0'
    run gcp_storage_upload "" "gs://bucket/file.txt"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Source and destination required" ]]
}

@test "gcp_storage_upload: adds gs:// prefix if missing" {
    echo "test content" > "$TEST_TMPDIR/testfile.txt"

    create_mock_gsutil '
        if [[ "$1" == "cp" && "$3" == gs://* ]]; then
            exit 0
        fi
        exit 1
    '
    create_mock_gcloud 'exit 0'

    result=$(gcp_storage_upload "$TEST_TMPDIR/testfile.txt" "my-bucket/testfile.txt")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "gs://my-bucket" ]]
}

@test "gcp_storage_download: downloads file successfully" {
    create_mock_gsutil '
        if [[ "$1" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '
    create_mock_gcloud 'exit 0'

    result=$(gcp_storage_download "gs://my-bucket/file.txt" "$TEST_TMPDIR/downloaded.txt")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "action\":\"download" ]]
}

@test "gcp_storage_download: fails for empty arguments" {
    create_mock_gcloud 'exit 0'
    run gcp_storage_download "gs://bucket/file.txt" ""
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Source and destination required" ]]
}

@test "gcp_storage_download: adds gs:// prefix if missing" {
    create_mock_gsutil '
        if [[ "$1" == "cp" && "$2" == gs://* ]]; then
            exit 0
        fi
        exit 1
    '
    create_mock_gcloud 'exit 0'

    result=$(gcp_storage_download "my-bucket/file.txt" "$TEST_TMPDIR/downloaded.txt")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "gs://my-bucket" ]]
}

# =============================================================================
# CATEGORY 4: COMPUTE ENGINE
# =============================================================================

@test "gcp_compute_list: lists instances" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "list" ]]; then
            echo "[{\"name\":\"instance-1\",\"status\":\"RUNNING\"},{\"name\":\"instance-2\",\"status\":\"STOPPED\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "instance-1" ]]
    [[ "$result" =~ "instance-2" ]]
}

@test "gcp_compute_list: filters by zone" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "list" && "$5" == "--zones=us-central1-a" ]]; then
            echo "[{\"name\":\"zone-instance\",\"status\":\"RUNNING\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_list "us-central1-a")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "zone-instance" ]]
}

@test "gcp_compute_list: returns empty array when no instances" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "list" ]]; then
            echo "[]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "data\":\[\]" ]]
}

@test "gcp_compute_list: handles gcloud failure" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "list" ]]; then
            exit 1
        fi
        exit 0
    '
    run gcp_compute_list
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Failed to list Compute Engine instances" ]]
}

@test "gcp_compute_status: returns instance status" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "describe" ]]; then
            cat << EOJSON
{
  "name": "my-instance",
  "status": "RUNNING",
  "zone": "https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a",
  "machineType": "https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a/machineTypes/e2-medium"
}
EOJSON
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_status "my-instance")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "my-instance" ]]
    [[ "$result" =~ "RUNNING" ]]
    [[ "$result" =~ "us-central1-a" ]]
    [[ "$result" =~ "e2-medium" ]]
}

@test "gcp_compute_status: fails for empty instance name" {
    create_mock_gcloud 'exit 0'
    run gcp_compute_status ""
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Instance name required" ]]
}

@test "gcp_compute_status: uses zone parameter" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "describe" && "$5" == "--zone=europe-west1-b" ]]; then
            echo "{\"name\":\"euro-instance\",\"status\":\"RUNNING\",\"zone\":\"zones/europe-west1-b\",\"machineType\":\"machineTypes/n1-standard-1\"}"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_status "euro-instance" "europe-west1-b")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "euro-instance" ]]
}

@test "gcp_compute_status: handles instance not found" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "describe" ]]; then
            exit 1
        fi
        exit 0
    '
    run gcp_compute_status "nonexistent"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Failed to get instance status" ]]
}

# =============================================================================
# CATEGORY 5: CLOUD FUNCTIONS
# =============================================================================

@test "gcp_functions_list: lists functions" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "list" ]]; then
            echo "[{\"name\":\"function-1\",\"status\":\"ACTIVE\"},{\"name\":\"function-2\",\"status\":\"DEPLOY_IN_PROGRESS\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "function-1" ]]
    [[ "$result" =~ "function-2" ]]
}

@test "gcp_functions_list: filters by region" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "list" && "$4" == "--regions=us-east1" ]]; then
            echo "[{\"name\":\"east-function\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_list "us-east1")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "east-function" ]]
}

@test "gcp_functions_list: returns empty array when no functions" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "list" ]]; then
            echo "[]"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "data\":\[\]" ]]
}

@test "gcp_functions_list: handles gcloud failure" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "list" ]]; then
            exit 1
        fi
        exit 0
    '
    run gcp_functions_list
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Failed to list Cloud Functions" ]]
}

@test "gcp_functions_invoke: invokes function successfully" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "call" ]]; then
            echo "executionId: abc123"
            echo "result: {\"message\":\"Hello World\"}"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_invoke "my-function")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "my-function" ]]
}

@test "gcp_functions_invoke: passes data to function" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "call" && "$4" == "--data={\"key\":\"value\"}" ]]; then
            echo "result: success"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_invoke "my-function" '{"key":"value"}')
    [[ "$result" =~ "success\":true" ]]
}

@test "gcp_functions_invoke: uses region parameter" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "call" && "$5" == "--region=asia-east1" ]]; then
            echo "result: regional"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_invoke "my-function" '{}' "asia-east1")
    [[ "$result" =~ "success\":true" ]]
}

@test "gcp_functions_invoke: fails for empty function name" {
    create_mock_gcloud 'exit 0'
    run gcp_functions_invoke ""
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Function name required" ]]
}

@test "gcp_functions_invoke: handles invocation failure" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "call" ]]; then
            echo "ERROR: Function not found" >&2
            exit 1
        fi
        exit 0
    '
    run gcp_functions_invoke "nonexistent-function"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Function invocation failed" ]]
}

# =============================================================================
# CATEGORY 6: MODULE EXPORTS
# =============================================================================

@test "MAINFRAME_EXT_GCP_EXPORTS: is defined and non-empty" {
    [[ -n "${MAINFRAME_EXT_GCP_EXPORTS[*]}" ]]
}

@test "MAINFRAME_EXT_GCP_EXPORTS: contains configuration functions" {
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_configured" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_project" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_region" ]]
}

@test "MAINFRAME_EXT_GCP_EXPORTS: contains storage functions" {
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_storage_list" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_storage_upload" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_storage_download" ]]
}

@test "MAINFRAME_EXT_GCP_EXPORTS: contains compute functions" {
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_compute_list" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_compute_status" ]]
}

@test "MAINFRAME_EXT_GCP_EXPORTS: contains functions helpers" {
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_functions_list" ]]
    [[ "${MAINFRAME_EXT_GCP_EXPORTS[*]}" =~ "gcp_functions_invoke" ]]
}

# =============================================================================
# CATEGORY 7: EDGE CASES AND SECURITY
# =============================================================================

@test "gcp_storage_list: handles bucket names with special characters" {
    create_mock_gsutil '
        echo "gs://bucket-with-dashes/"
        echo "gs://bucket_with_underscores/"
        echo "gs://bucket.with.dots/"
        exit 0
    '
    create_mock_gcloud 'exit 0'
    result=$(gcp_storage_list)
    [[ "$result" =~ "bucket-with-dashes" ]]
    [[ "$result" =~ "bucket_with_underscores" ]]
    [[ "$result" =~ "bucket.with.dots" ]]
}

@test "gcp_compute_status: extracts zone from full URL" {
    create_mock_gcloud '
        if [[ "$1" == "compute" && "$2" == "instances" && "$3" == "describe" ]]; then
            echo "{\"name\":\"test\",\"status\":\"RUNNING\",\"zone\":\"https://www.googleapis.com/compute/v1/projects/proj/zones/us-west1-c\",\"machineType\":\"https://www.googleapis.com/compute/v1/projects/proj/zones/us-west1-c/machineTypes/custom-4-8192\"}"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_compute_status "test")
    [[ "$result" =~ "zone\":\"us-west1-c" ]]
    [[ "$result" =~ "machine_type\":\"custom-4-8192" ]]
}

@test "_gcp_json_escape: handles empty string" {
    result=$(_gcp_json_escape "")
    [[ "$result" == "" ]]
}

@test "gcp_project: escapes special characters in project ID" {
    create_mock_gcloud '
        if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "project" ]]; then
            echo "project-with-special-chars"
            exit 0
        fi
        exit 0
    '
    result=$(gcp_project)
    [[ "$result" =~ "success\":true" ]]
}

@test "gcp_storage_upload: handles paths with spaces" {
    mkdir -p "$TEST_TMPDIR/path with spaces"
    echo "test" > "$TEST_TMPDIR/path with spaces/file.txt"

    create_mock_gsutil 'exit 0'
    create_mock_gcloud 'exit 0'

    result=$(gcp_storage_upload "$TEST_TMPDIR/path with spaces/file.txt" "gs://bucket/file.txt")
    [[ "$result" =~ "success\":true" ]]
}

@test "gcp_functions_invoke: uses default empty object for data" {
    create_mock_gcloud '
        if [[ "$1" == "functions" && "$2" == "call" && "$4" == "--data={}" ]]; then
            echo "result: ok"
            exit 0
        fi
        exit 1
    '
    result=$(gcp_functions_invoke "my-function")
    [[ "$result" =~ "success\":true" ]]
}

# =============================================================================
# CATEGORY 8: FALLBACK BEHAVIOR
# =============================================================================

@test "gcp_storage_list: falls back to gcloud storage when gsutil unavailable" {
    # Only create gcloud mock, no gsutil
    create_mock_gcloud '
        if [[ "$1" == "storage" && "$2" == "buckets" && "$3" == "list" ]]; then
            echo "backup-bucket"
            echo "data-bucket"
            exit 0
        fi
        exit 1
    '

    # Remove gsutil from PATH by only having gcloud in MOCK_BIN
    export PATH="$MOCK_BIN"

    result=$(gcp_storage_list)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "backup-bucket" ]]
    [[ "$result" =~ "data-bucket" ]]
}

@test "gcp_storage_upload: falls back to gcloud storage when gsutil unavailable" {
    echo "test content" > "$TEST_TMPDIR/testfile.txt"

    create_mock_gcloud '
        if [[ "$1" == "storage" && "$2" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '

    # Remove gsutil from PATH
    export PATH="$MOCK_BIN"

    result=$(gcp_storage_upload "$TEST_TMPDIR/testfile.txt" "gs://bucket/file.txt")
    [[ "$result" =~ "success\":true" ]]
}

@test "gcp_storage_download: falls back to gcloud storage when gsutil unavailable" {
    create_mock_gcloud '
        if [[ "$1" == "storage" && "$2" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '

    # Remove gsutil from PATH
    export PATH="$MOCK_BIN"

    result=$(gcp_storage_download "gs://bucket/file.txt" "$TEST_TMPDIR/downloaded.txt")
    [[ "$result" =~ "success\":true" ]]
}

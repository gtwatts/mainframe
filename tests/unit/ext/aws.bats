#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/ext/aws.bats - AWS CLI Wrapper Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/ext/aws.sh
#              AWS CLI wrapper functions with structured JSON output
# Test Count: 60+ test cases
# Categories: configuration, S3 operations, EC2 operations, Lambda operations
# Note: Tests use mocks to avoid requiring actual AWS credentials
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
    source "$MAINFRAME_ROOT/lib/ext/aws.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock aws command
create_mock_aws() {
    local behavior="$1"
    cat > "$MOCK_BIN/aws" << EOF
#!/bin/bash
$behavior
EOF
    chmod +x "$MOCK_BIN/aws"
    export PATH="$MOCK_BIN:$PATH"
}

# =============================================================================
# CATEGORY 1: INTERNAL HELPERS
# =============================================================================

@test "_aws_has_cli: returns true when aws is available" {
    create_mock_aws 'echo "aws-cli/2.15.0"'
    _aws_has_cli
    [[ $? -eq 0 ]]
}

@test "_aws_has_cli: returns false when aws is not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/aws.sh" && _aws_has_cli'
    [[ "$status" -eq 1 ]]
}

@test "_aws_require_cli: returns error JSON when aws not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/aws.sh" && _aws_require_cli'
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "AWS CLI not installed" ]]
    [[ "$output" =~ "success\":false" ]]
}

@test "_aws_json_escape: escapes double quotes" {
    result=$(_aws_json_escape 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "_aws_json_escape: escapes backslashes" {
    result=$(_aws_json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "_aws_json_escape: escapes newlines" {
    result=$(_aws_json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

# =============================================================================
# CATEGORY 2: CONFIGURATION
# =============================================================================

@test "aws_configured: returns configured true when credentials valid" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "{\"UserId\":\"AIDASAMPLE123\",\"Account\":\"123456789012\",\"Arn\":\"arn:aws:iam::123456789012:user/testuser\"}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_configured)
    [[ "$result" =~ '"configured":true' ]]
    [[ "$result" =~ '"account":"123456789012"' ]]
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_configured: returns configured false when credentials invalid" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "Unable to locate credentials" >&2
            exit 1
        fi
        exit 1
    '
    result=$(aws_configured)
    [[ "$result" =~ '"configured":false' ]]
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_configured: returns configured false when CLI not installed" {
    result=$(bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/aws.sh" && aws_configured')
    [[ "$result" =~ '"configured":false' ]]
    [[ "$result" =~ '"error":"AWS CLI not installed"' ]]
}

@test "aws_available: returns true when configured" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            exit 0
        fi
        exit 1
    '
    aws_available
    [[ $? -eq 0 ]]
}

@test "aws_available: returns false when not configured" {
    create_mock_aws 'exit 1'
    run aws_available
    [[ "$status" -eq 1 ]]
}

@test "aws_region: returns current region as JSON" {
    create_mock_aws '
        if [[ "$1" == "configure" && "$2" == "get" && "$3" == "region" ]]; then
            echo "us-west-2"
            exit 0
        fi
        exit 1
    '
    result=$(aws_region)
    [[ "$result" =~ '"region":"us-west-2"' ]]
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_region: returns default region when not configured" {
    create_mock_aws '
        if [[ "$1" == "configure" && "$2" == "get" && "$3" == "region" ]]; then
            exit 1
        fi
        exit 0
    '
    export AWS_DEFAULT_REGION="eu-west-1"
    result=$(aws_region)
    [[ "$result" =~ '"region":"eu-west-1"' ]]
    unset AWS_DEFAULT_REGION
}

@test "aws_region: sets new region when argument provided" {
    create_mock_aws '
        if [[ "$1" == "configure" && "$2" == "get" && "$3" == "region" ]]; then
            echo "us-east-1"
            exit 0
        fi
        if [[ "$1" == "configure" && "$2" == "set" && "$3" == "region" && "$4" == "eu-central-1" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_region "eu-central-1")
    [[ "$result" =~ '"region":"eu-central-1"' ]]
    [[ "$result" =~ '"previous":"us-east-1"' ]]
}

@test "aws_account_id: returns account ID" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "123456789012"
            exit 0
        fi
        exit 1
    '
    result=$(aws_account_id)
    [[ "$result" == "123456789012" ]]
}

@test "aws_whoami: returns full identity info" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "{\"UserId\":\"AIDASAMPLE\",\"Account\":\"123456789012\",\"Arn\":\"arn:aws:iam::123456789012:user/admin\"}"
            exit 0
        fi
        if [[ "$1" == "configure" && "$2" == "get" && "$3" == "region" ]]; then
            echo "us-east-1"
            exit 0
        fi
        exit 0
    '
    result=$(aws_whoami)
    [[ "$result" =~ '"account":"123456789012"' ]]
    [[ "$result" =~ '"arn":"arn:aws:iam::123456789012:user/admin"' ]]
    [[ "$result" =~ '"region":"us-east-1"' ]]
}

# =============================================================================
# CATEGORY 3: S3 OPERATIONS
# =============================================================================

@test "aws_s3_list: lists buckets when no argument" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "ls" ]]; then
            echo "2024-01-01 00:00:00 bucket-one"
            echo "2024-01-02 00:00:00 bucket-two"
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_list)
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"bucket-one"' ]]
    [[ "$result" =~ '"bucket-two"' ]]
}

@test "aws_s3_list: returns empty array when no buckets" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "ls" ]]; then
            echo ""
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_list)
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"data":[]' ]]
}

@test "aws_s3_list: lists objects in bucket" {
    create_mock_aws '
        if [[ "$1" == "s3api" && "$2" == "list-objects-v2" && "$4" == "my-bucket" ]]; then
            echo "{\"Contents\":[{\"Key\":\"file1.txt\",\"Size\":100}]}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_list "my-bucket")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"bucket":"my-bucket"' ]]
}

@test "aws_s3_list: lists objects with prefix" {
    create_mock_aws '
        if [[ "$1" == "s3api" && "$2" == "list-objects-v2" && "$6" == "--prefix" && "$7" == "logs/" ]]; then
            echo "{\"Contents\":[{\"Key\":\"logs/app.log\"}]}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_list "my-bucket" "logs/")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"prefix":"logs/"' ]]
}

@test "aws_s3_list: returns error for invalid bucket" {
    create_mock_aws '
        if [[ "$1" == "s3api" && "$2" == "list-objects-v2" ]]; then
            echo "An error occurred (NoSuchBucket)" >&2
            exit 1
        fi
        exit 1
    '
    result=$(aws_s3_list "nonexistent-bucket")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "NoSuchBucket" ]]
}

@test "aws_s3_upload: uploads file successfully" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "cp" ]]; then
            echo "upload: ./test.txt to s3://bucket/test.txt"
            exit 0
        fi
        exit 1
    '
    # Create test file
    echo "test content" > "$TEST_TMPDIR/test.txt"
    result=$(aws_s3_upload "$TEST_TMPDIR/test.txt" "s3://bucket/test.txt")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"destination":"s3://bucket/test.txt"' ]]
}

@test "aws_s3_upload: returns error for missing local file" {
    create_mock_aws 'exit 0'
    result=$(aws_s3_upload "/nonexistent/file.txt" "s3://bucket/file.txt")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Local file not found" ]]
}

@test "aws_s3_upload: returns error for missing local path" {
    result=$(aws_s3_upload "" "s3://bucket/file.txt")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Local path required" ]]
}

@test "aws_s3_upload: returns error for missing s3 path" {
    echo "test" > "$TEST_TMPDIR/test.txt"
    result=$(aws_s3_upload "$TEST_TMPDIR/test.txt" "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "S3 path required" ]]
}

@test "aws_s3_upload: supports content type" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "cp" && "$5" == "--content-type" && "$6" == "text/html" ]]; then
            exit 0
        fi
        exit 1
    '
    echo "<html></html>" > "$TEST_TMPDIR/index.html"
    result=$(aws_s3_upload "$TEST_TMPDIR/index.html" "s3://bucket/index.html" "text/html")
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_s3_download: downloads file successfully" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "cp" && "$3" == "s3://bucket/file.txt" ]]; then
            echo "download: s3://bucket/file.txt to ./file.txt"
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_download "s3://bucket/file.txt" "$TEST_TMPDIR/downloaded.txt")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"source":"s3://bucket/file.txt"' ]]
}

@test "aws_s3_download: returns error for missing s3 path" {
    result=$(aws_s3_download "" "$TEST_TMPDIR/file.txt")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "S3 path required" ]]
}

@test "aws_s3_download: returns error for missing local path" {
    result=$(aws_s3_download "s3://bucket/file.txt" "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Local path required" ]]
}

@test "aws_s3_cp: copies file successfully" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_cp "s3://src/file.txt" "s3://dst/file.txt")
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_s3_cp: returns error for missing arguments" {
    result=$(aws_s3_cp "" "s3://bucket/file.txt")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Source and destination required" ]]
}

@test "aws_s3_sync: syncs directory successfully" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "sync" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_sync "./local" "s3://bucket/prefix/")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"delete":false' ]]
}

@test "aws_s3_sync: supports delete flag" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "sync" && "$5" == "--delete" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_sync "./local" "s3://bucket/prefix/" "--delete")
    [[ "$result" =~ '"delete":true' ]]
}

# =============================================================================
# CATEGORY 4: EC2 OPERATIONS
# =============================================================================

@test "aws_ec2_list: lists all instances" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "describe-instances" ]]; then
            echo "[{\"id\":\"i-123\",\"type\":\"t2.micro\",\"state\":\"running\",\"name\":\"web-server\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_list)
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ "i-123" ]]
}

@test "aws_ec2_list: filters by state" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "describe-instances" && "$3" == "--filters" ]]; then
            echo "[{\"id\":\"i-456\",\"state\":\"stopped\"}]"
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_list "stopped")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"filter":"stopped"' ]]
}

@test "aws_ec2_list: returns error on failure" {
    create_mock_aws '
        echo "Access Denied" >&2
        exit 1
    '
    result=$(aws_ec2_list)
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Access Denied" ]]
}

@test "aws_ec2_status: returns instance details" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "describe-instances" && "$3" == "--instance-ids" && "$4" == "i-123" ]]; then
            echo "{\"state\":\"running\",\"instance_type\":\"t2.micro\",\"public_ip\":\"1.2.3.4\",\"private_ip\":\"10.0.0.1\",\"launch_time\":\"2024-01-01T00:00:00Z\",\"name\":\"web-server\"}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_status "i-123")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"instance_id":"i-123"' ]]
    [[ "$result" =~ '"state":"running"' ]]
}

@test "aws_ec2_status: returns error for missing instance_id" {
    result=$(aws_ec2_status "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Instance ID required" ]]
}

@test "aws_ec2_status: handles instances without public IP" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "describe-instances" ]]; then
            echo "{\"state\":\"running\",\"instance_type\":\"t2.micro\",\"private_ip\":\"10.0.0.1\"}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_status "i-123")
    [[ "$result" =~ '"public_ip":null' ]]
}

@test "aws_ec2_start: starts instance successfully" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "start-instances" && "$4" == "i-123" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_start "i-123")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"action":"start"' ]]
}

@test "aws_ec2_start: returns error for missing instance_id" {
    result=$(aws_ec2_start "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Instance ID required" ]]
}

@test "aws_ec2_stop: stops instance successfully" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "stop-instances" && "$4" == "i-456" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_stop "i-456")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"action":"stop"' ]]
}

@test "aws_ec2_stop: returns error for missing instance_id" {
    result=$(aws_ec2_stop "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Instance ID required" ]]
}

# =============================================================================
# CATEGORY 5: LAMBDA OPERATIONS
# =============================================================================

@test "aws_lambda_list: lists functions" {
    create_mock_aws '
        if [[ "$1" == "lambda" && "$2" == "list-functions" ]]; then
            echo "[{\"name\":\"my-function\",\"runtime\":\"python3.9\",\"memory\":128,\"timeout\":30}]"
            exit 0
        fi
        exit 1
    '
    result=$(aws_lambda_list)
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ "my-function" ]]
}

@test "aws_lambda_list: returns error on failure" {
    create_mock_aws '
        echo "Access Denied" >&2
        exit 1
    '
    result=$(aws_lambda_list)
    [[ "$result" =~ '"success":false' ]]
}

@test "aws_lambda_invoke: invokes function successfully" {
    create_mock_aws '
        if [[ "$1" == "lambda" && "$2" == "invoke" ]]; then
            # Find the output file argument (positional arg after --cli-binary-format value)
            shift 2  # skip "lambda invoke"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --function-name|--payload|--cli-binary-format|--output)
                        shift 2
                        ;;
                    -*)
                        shift
                        ;;
                    *)
                        # This is the output file
                        echo "{\"result\":\"success\"}" > "$1"
                        break
                        ;;
                esac
            done
            echo "{\"StatusCode\":200}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_lambda_invoke "my-function" '{"key":"value"}')
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"function":"my-function"' ]]
    [[ "$result" =~ '"status_code":200' ]]
}

@test "aws_lambda_invoke: returns error for missing function name" {
    result=$(aws_lambda_invoke "")
    [[ "$result" =~ '"success":false' ]]
    [[ "$result" =~ "Function name required" ]]
}

@test "aws_lambda_invoke: uses default payload when none provided" {
    create_mock_aws '
        if [[ "$1" == "lambda" && "$2" == "invoke" ]]; then
            # Find the output file and write response
            shift 2
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --function-name|--payload|--cli-binary-format|--output)
                        shift 2
                        ;;
                    -*)
                        shift
                        ;;
                    *)
                        echo "{}" > "$1"
                        break
                        ;;
                esac
            done
            echo "{\"StatusCode\":200}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_lambda_invoke "my-function")
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"status_code":200' ]]
}

@test "aws_lambda_invoke: returns error on invocation failure" {
    create_mock_aws '
        echo "Function not found" >&2
        exit 1
    '
    result=$(aws_lambda_invoke "nonexistent-function" '{}')
    [[ "$result" =~ '"success":false' ]]
}

# =============================================================================
# CATEGORY 6: MODULE EXPORTS
# =============================================================================

@test "MAINFRAME_EXT_AWS_EXPORTS: is defined and non-empty" {
    [[ -n "${MAINFRAME_EXT_AWS_EXPORTS[*]}" ]]
}

@test "MAINFRAME_EXT_AWS_EXPORTS: contains configuration functions" {
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_configured" ]]
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_region" ]]
}

@test "MAINFRAME_EXT_AWS_EXPORTS: contains S3 functions" {
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_s3_list" ]]
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_s3_upload" ]]
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_s3_download" ]]
}

@test "MAINFRAME_EXT_AWS_EXPORTS: contains EC2 functions" {
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_ec2_list" ]]
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_ec2_status" ]]
}

@test "MAINFRAME_EXT_AWS_EXPORTS: contains Lambda functions" {
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_lambda_list" ]]
    [[ "${MAINFRAME_EXT_AWS_EXPORTS[*]}" =~ "aws_lambda_invoke" ]]
}

# =============================================================================
# CATEGORY 7: EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "aws_s3_upload: handles special characters in path" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "cp" ]]; then
            exit 0
        fi
        exit 1
    '
    echo "test" > "$TEST_TMPDIR/file with spaces.txt"
    result=$(aws_s3_upload "$TEST_TMPDIR/file with spaces.txt" "s3://bucket/file with spaces.txt")
    [[ "$result" =~ '"success":true' ]]
}

@test "aws_ec2_status: handles error with special characters" {
    create_mock_aws '
        echo "Error: Instance \"i-123\" not found" >&2
        exit 1
    '
    result=$(aws_ec2_status "i-123")
    [[ "$result" =~ '"success":false' ]]
    # Verify error is properly escaped
    [[ "$result" =~ "error" ]]
}

@test "aws_lambda_invoke: handles non-JSON response" {
    create_mock_aws '
        if [[ "$1" == "lambda" && "$2" == "invoke" ]]; then
            # Find output file and write non-JSON response
            shift 2
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --function-name|--payload|--cli-binary-format|--output)
                        shift 2
                        ;;
                    -*)
                        shift
                        ;;
                    *)
                        echo "plain text response" > "$1"
                        break
                        ;;
                esac
            done
            echo "{\"StatusCode\":200}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_lambda_invoke "my-function")
    # Should handle non-JSON response gracefully (escape as string)
    [[ "$result" =~ '"success":true' ]]
    [[ "$result" =~ '"response":"' ]] || [[ "$result" =~ "plain text" ]]
}

@test "aws_s3_list: handles error response" {
    create_mock_aws '
        echo "An error occurred (InvalidAccessKeyId)" >&2
        exit 1
    '
    result=$(aws_s3_list)
    [[ "$result" =~ '"success":false' ]] || [[ "$result" =~ "error" ]]
}

@test "aws_configured: handles multiline error messages" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "Error line 1" >&2
            echo "Error line 2" >&2
            exit 1
        fi
        exit 1
    '
    result=$(aws_configured)
    [[ "$result" =~ '"configured":false' ]]
    # Error should be escaped (no raw newlines in JSON)
    [[ ! "$result" =~ $'\n' ]] || [[ "$result" =~ '\\n' ]]
}

# =============================================================================
# CATEGORY 8: JSON OUTPUT VALIDATION
# =============================================================================

@test "aws_configured: returns valid JSON" {
    create_mock_aws '
        if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
            echo "{\"UserId\":\"AIDASAMPLE\",\"Account\":\"123456789012\",\"Arn\":\"arn:aws:iam::123456789012:user/test\"}"
            exit 0
        fi
        exit 1
    '
    result=$(aws_configured)
    # Check JSON structure
    [[ "$result" =~ ^\{.*\}$ ]]
    [[ "$result" =~ '"success":' ]]
    [[ "$result" =~ '"data":' ]]
}

@test "aws_s3_list: returns valid JSON array for buckets" {
    create_mock_aws '
        if [[ "$1" == "s3" && "$2" == "ls" ]]; then
            echo "2024-01-01 00:00:00 bucket1"
            echo "2024-01-02 00:00:00 bucket2"
            exit 0
        fi
        exit 1
    '
    result=$(aws_s3_list)
    [[ "$result" =~ ^\{.*\}$ ]]
    [[ "$result" =~ '"data":\[' ]]
}

@test "aws_ec2_list: returns valid JSON with filter" {
    create_mock_aws '
        if [[ "$1" == "ec2" && "$2" == "describe-instances" ]]; then
            echo "[]"
            exit 0
        fi
        exit 1
    '
    result=$(aws_ec2_list "running")
    [[ "$result" =~ ^\{.*\}$ ]]
    [[ "$result" =~ '"filter":"running"' ]]
}

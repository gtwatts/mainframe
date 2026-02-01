#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/ext/terraform.bats - Terraform Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/ext/terraform.sh
#              Terraform CLI wrapper functions with JSON output
# Test Count: 70+ test cases
# Categories: detection, version, init, plan, apply, destroy, state, outputs,
#             validation, formatting, workspaces, edge cases
# Note: Tests use mocks to avoid requiring actual Terraform CLI
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
    source "$MAINFRAME_ROOT/lib/ext/terraform.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock terraform command
create_mock_terraform() {
    local behavior="$1"
    cat > "$MOCK_BIN/terraform" << EOF
#!/bin/bash
$behavior
EOF
    chmod +x "$MOCK_BIN/terraform"
    export PATH="$MOCK_BIN:$PATH"
}

# =============================================================================
# CATEGORY 1: INTERNAL HELPERS
# =============================================================================

@test "_tf_has_cli: returns true when terraform is available" {
    create_mock_terraform 'echo "Terraform v1.6.0"'
    _tf_has_cli
    [[ $? -eq 0 ]]
}

@test "_tf_has_cli: returns false when terraform is not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/terraform.sh" && _tf_has_cli'
    [[ "$status" -eq 1 ]]
}

@test "_tf_require_cli: returns error JSON when terraform is missing" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/terraform.sh" && _tf_require_cli'
    [[ "$output" =~ "success\":false" ]]
    [[ "$output" =~ "Terraform CLI not installed" ]]
}

@test "_tf_json_escape: escapes backslashes" {
    result=$(_tf_json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "_tf_json_escape: escapes quotes" {
    result=$(_tf_json_escape 'say "hello"')
    [[ "$result" == 'say \"hello\"' ]]
}

@test "_tf_json_escape: escapes newlines" {
    result=$(_tf_json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

# =============================================================================
# CATEGORY 2: DETECTION
# =============================================================================

@test "tf_detect: returns true for directory with .tf files" {
    mkdir -p "$TEST_TMPDIR/terraform_project"
    touch "$TEST_TMPDIR/terraform_project/main.tf"

    result=$(tf_detect "$TEST_TMPDIR/terraform_project")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "is_terraform_dir\":true" ]]
}

@test "tf_detect: returns false for directory without .tf files" {
    mkdir -p "$TEST_TMPDIR/empty_dir"

    result=$(tf_detect "$TEST_TMPDIR/empty_dir")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "is_terraform_dir\":false" ]]
}

@test "tf_detect: counts .tf files correctly" {
    mkdir -p "$TEST_TMPDIR/multi_tf"
    touch "$TEST_TMPDIR/multi_tf/main.tf"
    touch "$TEST_TMPDIR/multi_tf/variables.tf"
    touch "$TEST_TMPDIR/multi_tf/outputs.tf"

    result=$(tf_detect "$TEST_TMPDIR/multi_tf")
    [[ "$result" =~ "tf_files\":3" ]]
}

@test "tf_detect: counts .tfvars files" {
    mkdir -p "$TEST_TMPDIR/with_vars"
    touch "$TEST_TMPDIR/with_vars/main.tf"
    touch "$TEST_TMPDIR/with_vars/dev.tfvars"
    touch "$TEST_TMPDIR/with_vars/prod.tfvars"

    result=$(tf_detect "$TEST_TMPDIR/with_vars")
    [[ "$result" =~ "tfvars_files\":2" ]]
}

@test "tf_detect: detects initialized state" {
    mkdir -p "$TEST_TMPDIR/initialized/.terraform"

    result=$(tf_detect "$TEST_TMPDIR/initialized")
    [[ "$result" =~ "initialized\":true" ]]
}

@test "tf_detect: detects lock file" {
    mkdir -p "$TEST_TMPDIR/with_lock"
    touch "$TEST_TMPDIR/with_lock/.terraform.lock.hcl"

    result=$(tf_detect "$TEST_TMPDIR/with_lock")
    [[ "$result" =~ "has_lock\":true" ]]
}

@test "tf_detect: detects state file" {
    mkdir -p "$TEST_TMPDIR/with_state"
    touch "$TEST_TMPDIR/with_state/terraform.tfstate"

    result=$(tf_detect "$TEST_TMPDIR/with_state")
    [[ "$result" =~ "has_state\":true" ]]
}

@test "tf_detect: returns error for non-existent directory" {
    result=$(tf_detect "/nonexistent/path")
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "Directory not found" ]]
}

@test "tf_detect: uses current directory by default" {
    mkdir -p "$TEST_TMPDIR/current"
    touch "$TEST_TMPDIR/current/main.tf"
    cd "$TEST_TMPDIR/current"

    result=$(tf_detect)
    [[ "$result" =~ "is_terraform_dir\":true" ]]
}

# =============================================================================
# CATEGORY 3: VERSION
# =============================================================================

@test "tf_version: returns JSON version from terraform version -json" {
    create_mock_terraform '
        if [[ "$1" == "version" && "$2" == "-json" ]]; then
            echo "{\"terraform_version\":\"1.6.0\",\"platform\":\"linux_amd64\"}"
            exit 0
        fi
        exit 1
    '
    result=$(tf_version)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "terraform_version" ]]
}

@test "tf_version: falls back to parsing text output" {
    create_mock_terraform '
        if [[ "$1" == "version" && "$2" == "-json" ]]; then
            exit 1
        fi
        if [[ "$1" == "version" ]]; then
            echo "Terraform v1.5.7"
            echo "on linux_amd64"
            exit 0
        fi
        exit 1
    '
    result=$(tf_version)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "v1.5.7" ]]
}

@test "tf_version: returns error when terraform not installed" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/ext/terraform.sh" && tf_version'
    [[ "$output" =~ "success\":false" ]]
}

# =============================================================================
# CATEGORY 4: INITIALIZATION
# =============================================================================

@test "tf_init: initializes terraform successfully" {
    create_mock_terraform '
        if [[ "$1" == "init" ]]; then
            echo "Terraform has been successfully initialized!"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/init_test"

    result=$(tf_init "$TEST_TMPDIR/init_test")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "initialized successfully" ]]
}

@test "tf_init: passes -upgrade option" {
    create_mock_terraform '
        if [[ "$1" == "init" && "$*" =~ "-upgrade" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/upgrade_test"

    result=$(tf_init "$TEST_TMPDIR/upgrade_test" -upgrade)
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_init: passes -reconfigure option" {
    create_mock_terraform '
        if [[ "$1" == "init" && "$*" =~ "-reconfigure" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/reconfig_test"

    result=$(tf_init "$TEST_TMPDIR/reconfig_test" -reconfigure)
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_init: returns error on failure" {
    create_mock_terraform '
        echo "Error: Provider configuration not found"
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/fail_init"

    result=$(tf_init "$TEST_TMPDIR/fail_init")
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "init failed" ]]
}

# =============================================================================
# CATEGORY 5: PLAN
# =============================================================================

@test "tf_plan: returns success with no changes" {
    create_mock_terraform '
        if [[ "$1" == "plan" ]]; then
            echo "{\"@level\":\"info\",\"type\":\"change_summary\",\"changes\":{\"add\":0,\"change\":0,\"remove\":0}}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_test"

    result=$(tf_plan "$TEST_TMPDIR/plan_test")
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_plan: detects resources to add" {
    create_mock_terraform '
        if [[ "$1" == "plan" ]]; then
            echo "{\"@level\":\"info\",\"type\":\"planned_change\",\"change\":{\"action\":\"create\"}}"
            echo "{\"@level\":\"info\",\"type\":\"planned_change\",\"change\":{\"action\":\"create\"}}"
            echo "{\"@level\":\"info\",\"type\":\"change_summary\",\"changes\":{\"add\":2,\"change\":0,\"remove\":0}}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_add"

    result=$(tf_plan "$TEST_TMPDIR/plan_add")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "\"add\":2" ]]
}

@test "tf_plan: handles exit code 2 (changes needed)" {
    create_mock_terraform '
        if [[ "$1" == "plan" ]]; then
            echo "{\"@level\":\"info\",\"type\":\"change_summary\",\"changes\":{\"add\":1,\"change\":0,\"remove\":0}}"
            exit 2
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_changes"

    result=$(tf_plan "$TEST_TMPDIR/plan_changes")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "has_changes\":true" ]]
}

@test "tf_plan: handles -out option" {
    create_mock_terraform '
        if [[ "$1" == "plan" && "$*" =~ "-out=" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_out"

    result=$(tf_plan "$TEST_TMPDIR/plan_out" -out=plan.tfplan)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "plan_file" ]]
}

@test "tf_plan: passes -var option" {
    create_mock_terraform '
        if [[ "$1" == "plan" && "$*" =~ "-var=" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_var"

    result=$(tf_plan "$TEST_TMPDIR/plan_var" '-var=region=us-east-1')
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_plan: returns error on failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/plan_fail"

    result=$(tf_plan "$TEST_TMPDIR/plan_fail")
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "plan failed" ]]
}

# =============================================================================
# CATEGORY 6: APPLY
# =============================================================================

@test "tf_apply: applies changes successfully" {
    create_mock_terraform '
        if [[ "$1" == "apply" ]]; then
            echo "{\"@level\":\"info\",\"type\":\"apply_complete\"}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/apply_test"

    result=$(tf_apply "$TEST_TMPDIR/apply_test" -auto-approve)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "Apply complete" ]]
}

@test "tf_apply: accepts plan file" {
    create_mock_terraform '
        if [[ "$1" == "apply" && -n "$4" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/apply_plan"
    touch "$TEST_TMPDIR/apply_plan/saved.tfplan"

    result=$(tf_apply "$TEST_TMPDIR/apply_plan" "$TEST_TMPDIR/apply_plan/saved.tfplan")
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_apply: returns error on failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/apply_fail"

    result=$(tf_apply "$TEST_TMPDIR/apply_fail" -auto-approve)
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "apply failed" ]]
}

# =============================================================================
# CATEGORY 7: DESTROY
# =============================================================================

@test "tf_destroy: destroys resources successfully" {
    create_mock_terraform '
        if [[ "$1" == "destroy" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/destroy_test"

    result=$(tf_destroy "$TEST_TMPDIR/destroy_test" -auto-approve)
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "Destroy complete" ]]
}

@test "tf_destroy: returns error on failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/destroy_fail"

    result=$(tf_destroy "$TEST_TMPDIR/destroy_fail" -auto-approve)
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "destroy failed" ]]
}

# =============================================================================
# CATEGORY 8: STATE OPERATIONS
# =============================================================================

@test "tf_state_list: lists resources in state" {
    create_mock_terraform '
        if [[ "$1" == "state" && "$2" == "list" ]]; then
            echo "aws_instance.web"
            echo "aws_s3_bucket.data"
            echo "aws_vpc.main"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/state_test"

    result=$(tf_state_list "$TEST_TMPDIR/state_test")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "aws_instance.web" ]]
    [[ "$result" =~ "aws_s3_bucket.data" ]]
    [[ "$result" =~ "count\":3" ]]
}

@test "tf_state_list: returns empty array for empty state" {
    create_mock_terraform '
        if [[ "$1" == "state" && "$2" == "list" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/empty_state"

    result=$(tf_state_list "$TEST_TMPDIR/empty_state")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "resources\":\[\]" ]] || [[ "$result" =~ "count\":0" ]]
}

@test "tf_state_list: handles no state file" {
    create_mock_terraform '
        if [[ "$1" == "state" && "$2" == "list" ]]; then
            echo "No state file was found!" >&2
            exit 1
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/no_state"

    result=$(tf_state_list "$TEST_TMPDIR/no_state")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "No state file" ]]
}

@test "tf_state_list: accepts resource address filter" {
    create_mock_terraform '
        if [[ "$1" == "state" && "$2" == "list" && "$3" == "module.vpc" ]]; then
            echo "module.vpc.aws_subnet.public"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/state_filter"

    result=$(tf_state_list "$TEST_TMPDIR/state_filter" "module.vpc")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "module.vpc.aws_subnet.public" ]]
}

# =============================================================================
# CATEGORY 9: OUTPUTS
# =============================================================================

@test "tf_output: returns all outputs as JSON" {
    create_mock_terraform '
        if [[ "$1" == "output" && "$2" == "-json" ]]; then
            echo "{\"instance_ip\":{\"value\":\"10.0.0.5\"},\"bucket_name\":{\"value\":\"my-bucket\"}}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/output_test"

    result=$(tf_output "$TEST_TMPDIR/output_test")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "instance_ip" ]]
    [[ "$result" =~ "bucket_name" ]]
}

@test "tf_output: returns specific output" {
    create_mock_terraform '
        if [[ "$1" == "output" && "$2" == "-json" && "$3" == "instance_ip" ]]; then
            echo "\"10.0.0.5\""
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/output_single"

    result=$(tf_output "$TEST_TMPDIR/output_single" "instance_ip")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "10.0.0.5" ]]
}

@test "tf_output: handles no outputs" {
    create_mock_terraform '
        if [[ "$1" == "output" ]]; then
            echo "No outputs found" >&2
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/no_output"

    result=$(tf_output "$TEST_TMPDIR/no_output")
    [[ "$result" =~ "success\":true" ]]
}

# =============================================================================
# CATEGORY 10: VALIDATION
# =============================================================================

@test "tf_validate: returns valid for correct config" {
    create_mock_terraform '
        if [[ "$1" == "validate" && "$2" == "-json" ]]; then
            echo "{\"valid\":true,\"error_count\":0,\"warning_count\":0}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/valid_config"

    result=$(tf_validate "$TEST_TMPDIR/valid_config")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "valid\":true" ]]
}

@test "tf_validate: returns invalid for incorrect config" {
    create_mock_terraform '
        if [[ "$1" == "validate" && "$2" == "-json" ]]; then
            echo "{\"valid\":false,\"error_count\":1,\"diagnostics\":[{\"severity\":\"error\"}]}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/invalid_config"

    result=$(tf_validate "$TEST_TMPDIR/invalid_config")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "valid\":false" ]]
}

@test "tf_validate: returns error on command failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/validate_fail"

    result=$(tf_validate "$TEST_TMPDIR/validate_fail")
    [[ "$result" =~ "success\":false" ]]
}

# =============================================================================
# CATEGORY 11: FORMATTING
# =============================================================================

@test "tf_fmt_check: returns formatted true when all files formatted" {
    create_mock_terraform '
        if [[ "$1" == "fmt" && "$2" == "-check" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/formatted"

    result=$(tf_fmt_check "$TEST_TMPDIR/formatted")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "formatted\":true" ]]
}

@test "tf_fmt_check: returns unformatted files list" {
    create_mock_terraform '
        if [[ "$1" == "fmt" && "$2" == "-check" ]]; then
            echo "main.tf"
            echo "variables.tf"
            exit 3
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/unformatted"

    result=$(tf_fmt_check "$TEST_TMPDIR/unformatted")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "formatted\":false" ]]
    [[ "$result" =~ "main.tf" ]]
}

@test "tf_fmt_check: returns error on command failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/fmt_fail"

    result=$(tf_fmt_check "$TEST_TMPDIR/fmt_fail")
    [[ "$result" =~ "success\":false" ]]
}

# =============================================================================
# CATEGORY 12: WORKSPACES
# =============================================================================

@test "tf_workspace_list: lists workspaces with current marked" {
    create_mock_terraform '
        if [[ "$1" == "workspace" && "$2" == "list" ]]; then
            echo "  default"
            echo "* dev"
            echo "  staging"
            echo "  prod"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/workspace_list"

    result=$(tf_workspace_list "$TEST_TMPDIR/workspace_list")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "current\":\"dev\"" ]]
    [[ "$result" =~ "default" ]]
    [[ "$result" =~ "staging" ]]
    [[ "$result" =~ "prod" ]]
}

@test "tf_workspace_list: returns error on failure" {
    create_mock_terraform '
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/ws_list_fail"

    result=$(tf_workspace_list "$TEST_TMPDIR/ws_list_fail")
    [[ "$result" =~ "success\":false" ]]
}

@test "tf_workspace_select: selects workspace successfully" {
    create_mock_terraform '
        if [[ "$1" == "workspace" && "$2" == "select" && "$3" == "dev" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/ws_select"

    result=$(tf_workspace_select "dev" "$TEST_TMPDIR/ws_select")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "workspace\":\"dev\"" ]]
}

@test "tf_workspace_select: returns error for non-existent workspace" {
    create_mock_terraform '
        if [[ "$1" == "workspace" && "$2" == "select" ]]; then
            echo "Workspace \"nonexistent\" doesn'\''t exist." >&2
            exit 1
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/ws_missing"

    result=$(tf_workspace_select "nonexistent" "$TEST_TMPDIR/ws_missing")
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "does not exist" ]]
}

@test "tf_workspace_select: returns error for empty workspace name" {
    result=$(tf_workspace_select "")
    [[ "$result" =~ "success\":false" ]]
    [[ "$result" =~ "Workspace name required" ]]
}

# =============================================================================
# CATEGORY 13: MODULE EXPORTS
# =============================================================================

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: is defined and non-empty" {
    [[ -n "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains detection functions" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_detect" ]]
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_version" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains init function" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_init" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains plan and apply functions" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_plan" ]]
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_apply" ]]
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_destroy" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains state functions" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_state_list" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains output function" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_output" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains validation functions" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_validate" ]]
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_fmt_check" ]]
}

@test "MAINFRAME_EXT_TERRAFORM_EXPORTS: contains workspace functions" {
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_workspace_list" ]]
    [[ "${MAINFRAME_EXT_TERRAFORM_EXPORTS[*]}" =~ "tf_workspace_select" ]]
}

# =============================================================================
# CATEGORY 14: EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "tf_detect: handles directory with spaces in path" {
    mkdir -p "$TEST_TMPDIR/path with spaces"
    touch "$TEST_TMPDIR/path with spaces/main.tf"

    result=$(tf_detect "$TEST_TMPDIR/path with spaces")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "is_terraform_dir\":true" ]]
}

@test "tf_detect: handles directory with special characters" {
    mkdir -p "$TEST_TMPDIR/special-chars_123"
    touch "$TEST_TMPDIR/special-chars_123/main.tf"

    result=$(tf_detect "$TEST_TMPDIR/special-chars_123")
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_init: handles backend config options" {
    create_mock_terraform '
        if [[ "$1" == "init" && "$*" =~ "-backend-config=" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/backend_test"

    result=$(tf_init "$TEST_TMPDIR/backend_test" '-backend-config=bucket=my-bucket')
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_plan: handles target option" {
    create_mock_terraform '
        if [[ "$1" == "plan" && "$*" =~ "-target=" ]]; then
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/target_test"

    result=$(tf_plan "$TEST_TMPDIR/target_test" '-target=aws_instance.web')
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_state_list: handles multiple address arguments" {
    create_mock_terraform '
        if [[ "$1" == "state" && "$2" == "list" && "$3" == "module.a" && "$4" == "module.b" ]]; then
            echo "module.a.resource"
            echo "module.b.resource"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/multi_addr"

    result=$(tf_state_list "$TEST_TMPDIR/multi_addr" "module.a" "module.b")
    [[ "$result" =~ "success\":true" ]]
}

@test "functions return proper JSON even on edge cases" {
    # Ensure all functions return valid JSON structure
    create_mock_terraform 'exit 0'
    mkdir -p "$TEST_TMPDIR/json_test"

    # Test tf_detect
    result=$(tf_detect "$TEST_TMPDIR/json_test")
    [[ "$result" =~ ^\{.*\}$ ]]

    # Test tf_version
    result=$(tf_version)
    [[ "$result" =~ ^\{.*\}$ ]]
}

@test "tf_output: handles empty output gracefully" {
    create_mock_terraform '
        if [[ "$1" == "output" && "$2" == "-json" ]]; then
            echo "{}"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/empty_out"

    result=$(tf_output "$TEST_TMPDIR/empty_out")
    [[ "$result" =~ "success\":true" ]]
}

@test "tf_workspace_list: handles single default workspace" {
    create_mock_terraform '
        if [[ "$1" == "workspace" && "$2" == "list" ]]; then
            echo "* default"
            exit 0
        fi
        exit 1
    '
    mkdir -p "$TEST_TMPDIR/single_ws"

    result=$(tf_workspace_list "$TEST_TMPDIR/single_ws")
    [[ "$result" =~ "success\":true" ]]
    [[ "$result" =~ "current\":\"default\"" ]]
}

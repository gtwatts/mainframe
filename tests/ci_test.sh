#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: CI/CD Library Tests
# =============================================================================
# Run with: bash tests/ci_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/ci.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Print colored output
_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }

# Run a test
test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++))
    
    # Run test in subshell to isolate
    if (set -e; "$func") 2>/dev/null; then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
    fi
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: %s\nActual: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    [[ -n "$value" ]] || {
        printf 'Value is empty\n' >&2
        return 1
    }
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\n' "$needle" >&2
        return 1
    }
}

# Assert return code
assert_returns() {
    local expected="$1"
    shift
    local actual
    "$@" && actual=0 || actual=$?
    [[ "$actual" -eq "$expected" ]] || {
        printf 'Expected return code: %s, got: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# =============================================================================
# CI DETECTION TESTS
# =============================================================================

test_is_ci_local() {
    # Clear all CI env vars
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""  # Reset cache
    
    # Should return false when not in CI
    assert_returns 1 ci::is_ci
}

test_detect_local() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    local result
    result=$(ci::detect)
    assert_eq "none" "$result"
}

test_name_local() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    local result
    result=$(ci::name)
    assert_eq "Local" "$result"
}

test_detect_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local result
    result=$(ci::detect)
    assert_eq "github" "$result"
    
    result=$(ci::name)
    assert_eq "GitHub Actions" "$result"
    
    assert_returns 0 ci::is_ci
}

test_detect_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    
    local result
    result=$(ci::detect)
    assert_eq "gitlab" "$result"
    
    result=$(ci::name)
    assert_eq "GitLab CI" "$result"
}

test_detect_jenkins() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export JENKINS_URL="http://jenkins.example.com"
    
    local result
    result=$(ci::detect)
    assert_eq "jenkins" "$result"
    
    result=$(ci::name)
    assert_eq "Jenkins" "$result"
}

test_detect_circleci() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export CIRCLECI="true"
    
    local result
    result=$(ci::detect)
    assert_eq "circleci" "$result"
    
    result=$(ci::name)
    assert_eq "CircleCI" "$result"
}

test_detect_travis() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TRAVIS="true"
    
    local result
    result=$(ci::detect)
    assert_eq "travis" "$result"
    
    result=$(ci::name)
    assert_eq "Travis CI" "$result"
}

test_detect_azure() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TF_BUILD="True"
    
    local result
    result=$(ci::detect)
    assert_eq "azure" "$result"
    
    result=$(ci::name)
    assert_eq "Azure Pipelines" "$result"
}

# =============================================================================
# OUTPUT TESTS
# =============================================================================

test_set_output_local() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    ci::set_output "test_key" "test_value"
    assert_eq "test_value" "$test_key"
}

test_set_env_local() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    ci::set_env "MY_TEST_VAR" "my_test_value"
    assert_eq "my_test_value" "$MY_TEST_VAR"
}

test_add_path() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    local old_path="$PATH"
    ci::add_path "/test/new/path"
    
    assert_contains "$PATH" "/test/new/path"
    
    # Restore
    export PATH="$old_path"
}

test_set_output_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local tmpfile
    tmpfile=$(mktemp)
    export GITHUB_OUTPUT="$tmpfile"
    
    ci::set_output "my_key" "my_value"
    
    assert_contains "$(cat "$tmpfile")" "my_key=my_value"
    
    rm -f "$tmpfile"
}

test_set_env_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local tmpfile
    tmpfile=$(mktemp)
    export GITHUB_ENV="$tmpfile"
    
    ci::set_env "MY_VAR" "my_val"
    
    assert_contains "$(cat "$tmpfile")" "MY_VAR=my_val"
    
    rm -f "$tmpfile"
}

test_add_path_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local tmpfile
    tmpfile=$(mktemp)
    export GITHUB_PATH="$tmpfile"
    
    ci::add_path "/my/new/path"
    
    assert_contains "$(cat "$tmpfile")" "/my/new/path"
    
    rm -f "$tmpfile"
}

# =============================================================================
# GROUP TESTS
# =============================================================================

test_group_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::group_start "Test Group")
    assert_eq "::group::Test Group" "$output"
    
    output=$(ci::group_end)
    assert_eq "::endgroup::" "$output"
}

test_group_azure() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TF_BUILD="True"
    
    local output
    output=$(ci::group_start "Test Group")
    assert_eq "##[group]Test Group" "$output"
    
    output=$(ci::group_end)
    assert_eq "##[endgroup]" "$output"
}

# =============================================================================
# LOGGING TESTS
# =============================================================================

test_warning_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::warning "Test warning")
    assert_eq "::warning::Test warning" "$output"
    
    output=$(ci::warning "File warning" "test.sh" "42")
    assert_eq "::warning file=test.sh,line=42::File warning" "$output"
}

test_error_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::error "Test error")
    assert_eq "::error::Test error" "$output"
}

test_notice_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::notice "Test notice")
    assert_eq "::notice::Test notice" "$output"
}

test_debug_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::debug "Test debug")
    assert_eq "::debug::Test debug" "$output"
}

test_warning_azure() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TF_BUILD="True"
    
    local output
    output=$(ci::warning "Test warning")
    assert_eq "##[warning]Test warning" "$output"
}

test_error_azure() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TF_BUILD="True"
    
    local output
    output=$(ci::error "Test error")
    assert_eq "##[error]Test error" "$output"
}

# =============================================================================
# ARTIFACT TESTS
# =============================================================================

test_artifact_checksum() {
    local tmpfile
    tmpfile=$(mktemp)
    echo "test content" > "$tmpfile"
    
    local checksum
    checksum=$(ci::artifact_checksum "$tmpfile")
    
    # Checksum should be 64 chars (SHA256 hex)
    [[ ${#checksum} -eq 64 ]] || return 1
    
    # Should be consistent
    local checksum2
    checksum2=$(ci::artifact_checksum "$tmpfile")
    assert_eq "$checksum" "$checksum2"
    
    rm -f "$tmpfile"
}

test_artifact_checksum_nonexistent() {
    assert_returns 1 ci::artifact_checksum "/nonexistent/file"
}

test_artifact_create() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "test content" > "$tmpdir/testfile.txt"
    
    local artifact
    artifact=$(cd "$tmpdir" && ci::artifact_create "testfile.txt" "my-artifact")
    
    [[ -f "$tmpdir/my-artifact.tar.gz" ]] || return 1
    [[ -f "$tmpdir/my-artifact.tar.gz.sha256" ]] || return 1
    
    rm -rf "$tmpdir"
}

# =============================================================================
# PR/MR TESTS
# =============================================================================

test_is_pull_request_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    unset GITHUB_EVENT_NAME GITHUB_HEAD_REF
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_EVENT_NAME="pull_request"
    
    assert_returns 0 ci::is_pull_request
}

test_is_not_pull_request_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    unset GITHUB_EVENT_NAME GITHUB_HEAD_REF
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_EVENT_NAME="push"
    
    assert_returns 1 ci::is_pull_request
}

test_pr_number_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REF="refs/pull/123/merge"
    
    local result
    result=$(ci::pr_number)
    assert_eq "123" "$result"
}

test_pr_branch_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_HEAD_REF="feature/my-branch"
    
    local result
    result=$(ci::pr_branch)
    assert_eq "feature/my-branch" "$result"
}

test_pr_target_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_BASE_REF="main"
    
    local result
    result=$(ci::pr_target)
    assert_eq "main" "$result"
}

test_is_pull_request_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_MERGE_REQUEST_ID="456"
    
    assert_returns 0 ci::is_pull_request
}

test_pr_number_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_MERGE_REQUEST_IID="789"
    
    local result
    result=$(ci::pr_number)
    assert_eq "789" "$result"
}

test_is_pull_request_travis() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TRAVIS="true"
    export TRAVIS_PULL_REQUEST="42"
    
    assert_returns 0 ci::is_pull_request
}

test_is_not_pull_request_travis() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export TRAVIS="true"
    export TRAVIS_PULL_REQUEST="false"
    
    assert_returns 1 ci::is_pull_request
}

# =============================================================================
# GIT INFO TESTS
# =============================================================================

test_commit_sha_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_SHA="abc123def456789"
    
    local result
    result=$(ci::commit_sha)
    assert_eq "abc123def456789" "$result"
}

test_commit_short() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_SHA="abc123def456789"
    
    local result
    result=$(ci::commit_short)
    assert_eq "abc123d" "$result"
}

test_branch_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REF_NAME="main"
    
    local result
    result=$(ci::branch)
    assert_eq "main" "$result"
}

test_branch_github_from_ref() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    unset GITHUB_REF_NAME GITHUB_HEAD_REF
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REF="refs/heads/feature/test"
    
    local result
    result=$(ci::branch)
    assert_eq "feature/test" "$result"
}

test_tag_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REF="refs/tags/v1.2.3"
    
    local result
    result=$(ci::tag)
    assert_eq "v1.2.3" "$result"
    
    assert_returns 0 ci::is_tag
}

test_tag_github_ref_type() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REF_TYPE="tag"
    export GITHUB_REF_NAME="v2.0.0"
    
    local result
    result=$(ci::tag)
    assert_eq "v2.0.0" "$result"
}

test_no_tag_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    unset GITHUB_REF GITHUB_REF_TYPE GITHUB_REF_NAME
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local result
    result=$(ci::tag)
    [[ -z "$result" ]] || return 1
    
    assert_returns 1 ci::is_tag
}

test_commit_sha_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_COMMIT_SHA="gitlab123abc"
    
    local result
    result=$(ci::commit_sha)
    assert_eq "gitlab123abc" "$result"
}

test_tag_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_COMMIT_TAG="v3.0.0"
    
    local result
    result=$(ci::tag)
    assert_eq "v3.0.0" "$result"
}

# =============================================================================
# CI ENVIRONMENT TESTS
# =============================================================================

test_runner_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export RUNNER_NAME="ubuntu-latest"
    
    local result
    result=$(ci::runner)
    assert_eq "ubuntu-latest" "$result"
}

test_build_number_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_RUN_NUMBER="42"
    
    local result
    result=$(ci::build_number)
    assert_eq "42" "$result"
}

test_repository_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export GITHUB_REPOSITORY="owner/repo"
    
    local result
    result=$(ci::repository)
    assert_eq "owner/repo" "$result"
}

test_build_number_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_PIPELINE_IID="100"
    
    local result
    result=$(ci::build_number)
    assert_eq "100" "$result"
}

test_repository_gitlab() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITLAB_CI="true"
    export CI_PROJECT_PATH="group/project"
    
    local result
    result=$(ci::repository)
    assert_eq "group/project" "$result"
}

# =============================================================================
# MASK TESTS
# =============================================================================

test_mask_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    
    local output
    output=$(ci::mask_value "secret123")
    assert_eq "::add-mask::secret123" "$output"
}

# =============================================================================
# CACHE KEY TESTS
# =============================================================================

test_cache_key_prefix_github() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    export GITHUB_ACTIONS="true"
    export RUNNER_OS="Linux"
    export GITHUB_JOB="build"
    
    local result
    result=$(ci::cache_key_prefix)
    assert_eq "Linux-build" "$result"
}

test_cache_key_prefix_local() {
    unset GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILD_ID JOB_NAME CIRCLECI TRAVIS TF_BUILD AZURE_PIPELINES
    _CI_PLATFORM=""
    
    local result
    result=$(ci::cache_key_prefix)
    assert_contains "$result" "local-"
}

# =============================================================================
# RUN TESTS
# =============================================================================

run_tests() {
    printf '\n%s\n' "=== MAINFRAME CI/CD Library Tests ==="
    
    printf '\n%s\n' "CI Detection:"
    test_case "ci::is_ci returns false locally" test_is_ci_local
    test_case "ci::detect returns 'none' locally" test_detect_local
    test_case "ci::name returns 'Local' locally" test_name_local
    test_case "Detects GitHub Actions" test_detect_github
    test_case "Detects GitLab CI" test_detect_gitlab
    test_case "Detects Jenkins" test_detect_jenkins
    test_case "Detects CircleCI" test_detect_circleci
    test_case "Detects Travis CI" test_detect_travis
    test_case "Detects Azure Pipelines" test_detect_azure
    
    printf '\n%s\n' "Output Functions:"
    test_case "ci::set_output exports locally" test_set_output_local
    test_case "ci::set_env exports locally" test_set_env_local
    test_case "ci::add_path modifies PATH" test_add_path
    test_case "ci::set_output writes to GITHUB_OUTPUT" test_set_output_github
    test_case "ci::set_env writes to GITHUB_ENV" test_set_env_github
    test_case "ci::add_path writes to GITHUB_PATH" test_add_path_github
    
    printf '\n%s\n' "Group Functions:"
    test_case "ci::group_start/end for GitHub" test_group_github
    test_case "ci::group_start/end for Azure" test_group_azure
    
    printf '\n%s\n' "Logging Functions:"
    test_case "ci::warning for GitHub" test_warning_github
    test_case "ci::error for GitHub" test_error_github
    test_case "ci::notice for GitHub" test_notice_github
    test_case "ci::debug for GitHub" test_debug_github
    test_case "ci::warning for Azure" test_warning_azure
    test_case "ci::error for Azure" test_error_azure
    
    printf '\n%s\n' "Artifact Functions:"
    test_case "ci::artifact_checksum generates SHA256" test_artifact_checksum
    test_case "ci::artifact_checksum fails for missing file" test_artifact_checksum_nonexistent
    test_case "ci::artifact_create creates tar.gz and checksum" test_artifact_create
    
    printf '\n%s\n' "PR/MR Functions:"
    test_case "ci::is_pull_request for GitHub PR" test_is_pull_request_github
    test_case "ci::is_pull_request false for GitHub push" test_is_not_pull_request_github
    test_case "ci::pr_number extracts from GITHUB_REF" test_pr_number_github
    test_case "ci::pr_branch returns GITHUB_HEAD_REF" test_pr_branch_github
    test_case "ci::pr_target returns GITHUB_BASE_REF" test_pr_target_github
    test_case "ci::is_pull_request for GitLab MR" test_is_pull_request_gitlab
    test_case "ci::pr_number for GitLab" test_pr_number_gitlab
    test_case "ci::is_pull_request for Travis PR" test_is_pull_request_travis
    test_case "ci::is_pull_request false for Travis non-PR" test_is_not_pull_request_travis
    
    printf '\n%s\n' "Git Info Functions:"
    test_case "ci::commit_sha for GitHub" test_commit_sha_github
    test_case "ci::commit_short returns 7 chars" test_commit_short
    test_case "ci::branch for GitHub" test_branch_github
    test_case "ci::branch from GITHUB_REF" test_branch_github_from_ref
    test_case "ci::tag extracts from refs/tags/" test_tag_github
    test_case "ci::tag from GITHUB_REF_TYPE" test_tag_github_ref_type
    test_case "ci::tag empty for non-tag build" test_no_tag_github
    test_case "ci::commit_sha for GitLab" test_commit_sha_gitlab
    test_case "ci::tag for GitLab" test_tag_gitlab
    
    printf '\n%s\n' "CI Environment Functions:"
    test_case "ci::runner for GitHub" test_runner_github
    test_case "ci::build_number for GitHub" test_build_number_github
    test_case "ci::repository for GitHub" test_repository_github
    test_case "ci::build_number for GitLab" test_build_number_gitlab
    test_case "ci::repository for GitLab" test_repository_gitlab
    
    printf '\n%s\n' "Masking Functions:"
    test_case "ci::mask_value for GitHub" test_mask_github
    
    printf '\n%s\n' "Cache Functions:"
    test_case "ci::cache_key_prefix for GitHub" test_cache_key_prefix_github
    test_case "ci::cache_key_prefix for local" test_cache_key_prefix_local
    
    # Summary
    printf '\n%s\n' "=== Test Summary ==="
    printf 'Total: %d | ' "$TESTS_RUN"
    printf '%s | ' "$(_green "Passed: $TESTS_PASSED")"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf '%s\n' "$(_red "Failed: $TESTS_FAILED")"
    else
        printf '%s\n' "$(_green "Failed: 0")"
    fi
    
    [[ $TESTS_FAILED -eq 0 ]]
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
    exit $?
fi

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/test_ci.bats - CI Platform Detection Tests
# =============================================================================
# Description: Tests for CI/CD platform detection functions
# Covers: 17 CI platforms (GitHub, GitLab, Jenkins, BuildKite, Bitbucket,
#         TeamCity, CircleCI, Travis, AppVeyor, Azure, CodeBuild, CloudBuild,
#         Drone, Semaphore, Buddy, Woodpecker, Gitea)
# =============================================================================

# Load BATS helpers if available
load_helper() {
    local helper_dir="${BATS_TEST_DIRNAME}/../bats-support"
    if [[ -d "$helper_dir" ]]; then
        load "${helper_dir}/load"
    fi
    helper_dir="${BATS_TEST_DIRNAME}/../bats-assert"
    if [[ -d "$helper_dir" ]]; then
        load "${helper_dir}/load"
    fi
}

setup() {
    # Source the CI library
    MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "${MAINFRAME_ROOT}/lib/ci.sh"

    # Clear any CI environment variables for clean tests
    _clear_ci_env
}

# Helper to clear all CI environment variables
_clear_ci_env() {
    # Reset the cache first
    _ci_reset_cache

    # Clear all known CI env vars
    unset GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_SHA GITHUB_REF GITHUB_RUN_ID
    unset GITHUB_RUN_NUMBER GITHUB_HEAD_REF GITHUB_REF_NAME GITHUB_JOB
    unset GITLAB_CI CI_COMMIT_SHA CI_COMMIT_REF_NAME CI_PIPELINE_ID CI_PROJECT_PATH
    unset CI_MERGE_REQUEST_IID CI_JOB_NAME CI_RUNNER_DESCRIPTION
    unset JENKINS_URL BUILD_ID JOB_NAME BUILD_NUMBER GIT_BRANCH GIT_COMMIT
    unset CHANGE_ID NODE_NAME
    unset CIRCLECI CIRCLE_SHA1 CIRCLE_BRANCH CIRCLE_BUILD_NUM CIRCLE_PROJECT_USERNAME
    unset CIRCLE_PROJECT_REPONAME CIRCLE_JOB CIRCLE_PULL_REQUEST
    unset TRAVIS TRAVIS_COMMIT TRAVIS_BRANCH TRAVIS_BUILD_NUMBER TRAVIS_BUILD_ID
    unset TRAVIS_REPO_SLUG TRAVIS_PULL_REQUEST TRAVIS_JOB_NAME
    unset TF_BUILD AZURE_PIPELINES BUILD_SOURCEVERSION BUILD_SOURCEBRANCH
    unset BUILD_BUILDID BUILD_BUILDNUMBER BUILD_REPOSITORY_NAME SYSTEM_JOBNAME AGENT_NAME
    unset SYSTEM_PULLREQUEST_PULLREQUESTID
    unset BUILDKITE BUILDKITE_BUILD_ID BUILDKITE_BUILD_NUMBER BUILDKITE_BRANCH
    unset BUILDKITE_COMMIT BUILDKITE_PULL_REQUEST BUILDKITE_REPO BUILDKITE_LABEL BUILDKITE_AGENT_NAME
    unset BITBUCKET_BUILD_NUMBER BITBUCKET_PIPELINE_UUID BITBUCKET_BRANCH
    unset BITBUCKET_COMMIT BITBUCKET_PR_ID BITBUCKET_REPO_FULL_NAME BITBUCKET_STEP_UUID
    unset TEAMCITY_VERSION TEAMCITY_BUILDCONF_NAME BRANCH_NAME
    unset APPVEYOR APPVEYOR_BUILD_ID APPVEYOR_BUILD_NUMBER APPVEYOR_REPO_BRANCH
    unset APPVEYOR_REPO_COMMIT APPVEYOR_PULL_REQUEST_NUMBER APPVEYOR_REPO_NAME APPVEYOR_JOB_NAME
    unset CODEBUILD_BUILD_ID CODEBUILD_BUILD_NUMBER CODEBUILD_SOURCE_VERSION
    unset CODEBUILD_RESOLVED_SOURCE_VERSION CODEBUILD_SOURCE_REPO_URL
    unset CLOUD_BUILD_ID PROJECT_ID COMMIT_SHA REPO_NAME TRIGGER_NAME
    unset DRONE DRONE_BUILD_NUMBER DRONE_BRANCH DRONE_COMMIT_SHA DRONE_PULL_REQUEST
    unset DRONE_REPO DRONE_STAGE_NAME DRONE_RUNNER_HOST
    unset SEMAPHORE SEMAPHORE_WORKFLOW_ID SEMAPHORE_WORKFLOW_NUMBER SEMAPHORE_GIT_BRANCH
    unset SEMAPHORE_GIT_SHA SEMAPHORE_GIT_PR_NUMBER SEMAPHORE_GIT_URL SEMAPHORE_JOB_NAME
    unset SEMAPHORE_AGENT_MACHINE_TYPE
    unset BUDDY BUDDY_EXECUTION_ID BUDDY_EXECUTION_BRANCH BUDDY_EXECUTION_REVISION
    unset BUDDY_EXECUTION_PULL_REQUEST_ID BUDDY_REPO_SLUG BUDDY_PIPELINE_NAME
    unset CI_REPO CI_SYSTEM_HOST CI_BUILD_NUMBER CI_COMMIT_BRANCH CI_COMMIT_SHA
    unset CI_COMMIT_PULL_REQUEST CI_STEP_NAME CI_MACHINE
    unset GITEA_ACTIONS GITEA_RUN_ID GITEA_RUN_NUMBER GITEA_REF_NAME GITEA_SHA
    unset GITEA_REPOSITORY GITEA_JOB GITEA_RUNNER_NAME
    unset CI
}

# =============================================================================
# LOCAL ENVIRONMENT TESTS (No CI)
# =============================================================================

@test "ci_is_ci returns false when not in CI" {
    run ci_is_ci
    [ "$status" -eq 1 ]
}

@test "ci_platform returns 'unknown' when not in CI" {
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "ci::name returns 'Local' when not in CI" {
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Local" ]
}

# =============================================================================
# GITHUB ACTIONS TESTS
# =============================================================================

@test "ci_is_github_actions detects GitHub Actions" {
    export GITHUB_ACTIONS="true"
    _ci_reset_cache
    run ci_is_github_actions
    [ "$status" -eq 0 ]
}

@test "ci_is_ci returns true in GitHub Actions" {
    export GITHUB_ACTIONS="true"
    _ci_reset_cache
    run ci_is_ci
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'github' in GitHub Actions" {
    export GITHUB_ACTIONS="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "github" ]
}

@test "ci::name returns 'GitHub Actions' in GitHub Actions" {
    export GITHUB_ACTIONS="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "GitHub Actions" ]
}

@test "ci_info returns JSON with GitHub Actions info" {
    export GITHUB_ACTIONS="true"
    export GITHUB_RUN_ID="12345"
    export GITHUB_RUN_NUMBER="42"
    export GITHUB_SHA="abc123def456"
    export GITHUB_REF_NAME="main"
    export GITHUB_REPOSITORY="owner/repo"
    export GITHUB_JOB="build"
    _ci_reset_cache

    run ci_info
    [ "$status" -eq 0 ]
    [[ "$output" == *'"platform":"github"'* ]]
    [[ "$output" == *'"build_id":"12345"'* ]]
    [[ "$output" == *'"build_number":"42"'* ]]
    [[ "$output" == *'"commit":"abc123def456"'* ]]
    [[ "$output" == *'"repository":"owner/repo"'* ]]
}

# =============================================================================
# GITLAB CI TESTS
# =============================================================================

@test "ci_is_gitlab_ci detects GitLab CI" {
    export GITLAB_CI="true"
    _ci_reset_cache
    run ci_is_gitlab_ci
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'gitlab' in GitLab CI" {
    export GITLAB_CI="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "gitlab" ]
}

@test "ci::name returns 'GitLab CI' in GitLab CI" {
    export GITLAB_CI="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "GitLab CI" ]
}

# =============================================================================
# JENKINS TESTS
# =============================================================================

@test "ci_is_jenkins detects Jenkins via JENKINS_URL" {
    export JENKINS_URL="http://jenkins.example.com"
    _ci_reset_cache
    run ci_is_jenkins
    [ "$status" -eq 0 ]
}

@test "ci_is_jenkins detects Jenkins via BUILD_ID + JOB_NAME" {
    export BUILD_ID="123"
    export JOB_NAME="my-job"
    _ci_reset_cache
    run ci_is_jenkins
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'jenkins' in Jenkins" {
    export JENKINS_URL="http://jenkins.example.com"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "jenkins" ]
}

@test "ci::name returns 'Jenkins' in Jenkins" {
    export JENKINS_URL="http://jenkins.example.com"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Jenkins" ]
}

# =============================================================================
# BUILDKITE TESTS
# =============================================================================

@test "ci_is_buildkite detects BuildKite" {
    export BUILDKITE="true"
    _ci_reset_cache
    run ci_is_buildkite
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'buildkite' in BuildKite" {
    export BUILDKITE="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "buildkite" ]
}

@test "ci::name returns 'BuildKite' in BuildKite" {
    export BUILDKITE="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "BuildKite" ]
}

@test "ci_info returns BuildKite-specific variables" {
    export BUILDKITE="true"
    export BUILDKITE_BUILD_ID="build-123"
    export BUILDKITE_BUILD_NUMBER="42"
    export BUILDKITE_BRANCH="feature/test"
    export BUILDKITE_COMMIT="abc123"
    export BUILDKITE_PULL_REQUEST="15"
    _ci_reset_cache

    run ci_info
    [ "$status" -eq 0 ]
    [[ "$output" == *'"platform":"buildkite"'* ]]
    [[ "$output" == *'"build_id":"build-123"'* ]]
    [[ "$output" == *'"pr_number":"15"'* ]]
}

# =============================================================================
# BITBUCKET PIPELINES TESTS
# =============================================================================

@test "ci_is_bitbucket detects Bitbucket Pipelines" {
    export BITBUCKET_BUILD_NUMBER="123"
    _ci_reset_cache
    run ci_is_bitbucket
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'bitbucket' in Bitbucket Pipelines" {
    export BITBUCKET_BUILD_NUMBER="123"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "bitbucket" ]
}

@test "ci::name returns 'Bitbucket Pipelines' in Bitbucket Pipelines" {
    export BITBUCKET_BUILD_NUMBER="123"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Bitbucket Pipelines" ]
}

# =============================================================================
# TEAMCITY TESTS
# =============================================================================

@test "ci_is_teamcity detects TeamCity" {
    export TEAMCITY_VERSION="2023.05"
    _ci_reset_cache
    run ci_is_teamcity
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'teamcity' in TeamCity" {
    export TEAMCITY_VERSION="2023.05"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "teamcity" ]
}

@test "ci::name returns 'TeamCity' in TeamCity" {
    export TEAMCITY_VERSION="2023.05"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "TeamCity" ]
}

# =============================================================================
# CIRCLECI TESTS
# =============================================================================

@test "ci_is_circleci detects CircleCI" {
    export CIRCLECI="true"
    _ci_reset_cache
    run ci_is_circleci
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'circleci' in CircleCI" {
    export CIRCLECI="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "circleci" ]
}

@test "ci::name returns 'CircleCI' in CircleCI" {
    export CIRCLECI="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "CircleCI" ]
}

# =============================================================================
# TRAVIS CI TESTS
# =============================================================================

@test "ci_is_travis detects Travis CI" {
    export TRAVIS="true"
    _ci_reset_cache
    run ci_is_travis
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'travis' in Travis CI" {
    export TRAVIS="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "travis" ]
}

@test "ci::name returns 'Travis CI' in Travis CI" {
    export TRAVIS="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Travis CI" ]
}

# =============================================================================
# APPVEYOR TESTS
# =============================================================================

@test "ci_is_appveyor detects AppVeyor (True)" {
    export APPVEYOR="True"
    _ci_reset_cache
    run ci_is_appveyor
    [ "$status" -eq 0 ]
}

@test "ci_is_appveyor detects AppVeyor (true lowercase)" {
    export APPVEYOR="true"
    _ci_reset_cache
    run ci_is_appveyor
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'appveyor' in AppVeyor" {
    export APPVEYOR="True"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "appveyor" ]
}

@test "ci::name returns 'AppVeyor' in AppVeyor" {
    export APPVEYOR="True"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "AppVeyor" ]
}

# =============================================================================
# AZURE PIPELINES TESTS
# =============================================================================

@test "ci_is_azure_pipelines detects Azure Pipelines via TF_BUILD" {
    export TF_BUILD="True"
    _ci_reset_cache
    run ci_is_azure_pipelines
    [ "$status" -eq 0 ]
}

@test "ci_is_azure_pipelines detects Azure Pipelines via AZURE_PIPELINES" {
    export AZURE_PIPELINES="true"
    _ci_reset_cache
    run ci_is_azure_pipelines
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'azure' in Azure Pipelines" {
    export TF_BUILD="True"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "azure" ]
}

@test "ci::name returns 'Azure Pipelines' in Azure Pipelines" {
    export TF_BUILD="True"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Azure Pipelines" ]
}

# =============================================================================
# AWS CODEBUILD TESTS
# =============================================================================

@test "ci_is_aws_codebuild detects AWS CodeBuild" {
    export CODEBUILD_BUILD_ID="project:build-123"
    _ci_reset_cache
    run ci_is_aws_codebuild
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'codebuild' in AWS CodeBuild" {
    export CODEBUILD_BUILD_ID="project:build-123"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "codebuild" ]
}

@test "ci::name returns 'AWS CodeBuild' in AWS CodeBuild" {
    export CODEBUILD_BUILD_ID="project:build-123"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "AWS CodeBuild" ]
}

# =============================================================================
# GOOGLE CLOUD BUILD TESTS
# =============================================================================

@test "ci_is_gcp_cloud_build detects GCP Cloud Build via CLOUD_BUILD_ID" {
    export CLOUD_BUILD_ID="build-123"
    _ci_reset_cache
    run ci_is_gcp_cloud_build
    [ "$status" -eq 0 ]
}

@test "ci_is_gcp_cloud_build detects GCP Cloud Build via BUILD_ID + PROJECT_ID" {
    export BUILD_ID="build-123"
    export PROJECT_ID="my-project"
    _ci_reset_cache
    run ci_is_gcp_cloud_build
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'cloudbuild' in GCP Cloud Build" {
    export CLOUD_BUILD_ID="build-123"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "cloudbuild" ]
}

@test "ci::name returns 'Google Cloud Build' in GCP Cloud Build" {
    export CLOUD_BUILD_ID="build-123"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Google Cloud Build" ]
}

# =============================================================================
# DRONE CI TESTS
# =============================================================================

@test "ci_is_drone detects Drone CI" {
    export DRONE="true"
    _ci_reset_cache
    run ci_is_drone
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'drone' in Drone CI" {
    export DRONE="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "drone" ]
}

@test "ci::name returns 'Drone CI' in Drone CI" {
    export DRONE="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Drone CI" ]
}

# =============================================================================
# SEMAPHORE CI TESTS
# =============================================================================

@test "ci_is_semaphore detects Semaphore CI" {
    export SEMAPHORE="true"
    _ci_reset_cache
    run ci_is_semaphore
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'semaphore' in Semaphore CI" {
    export SEMAPHORE="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "semaphore" ]
}

@test "ci::name returns 'Semaphore CI' in Semaphore CI" {
    export SEMAPHORE="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Semaphore CI" ]
}

# =============================================================================
# BUDDY TESTS
# =============================================================================

@test "ci_is_buddy detects Buddy" {
    export BUDDY="true"
    _ci_reset_cache
    run ci_is_buddy
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'buddy' in Buddy" {
    export BUDDY="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "buddy" ]
}

@test "ci::name returns 'Buddy' in Buddy" {
    export BUDDY="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Buddy" ]
}

# =============================================================================
# WOODPECKER CI TESTS
# =============================================================================

@test "ci_is_woodpecker detects Woodpecker CI" {
    export CI_REPO="owner/repo"
    export CI_SYSTEM_HOST="woodpecker.example.com"
    _ci_reset_cache
    run ci_is_woodpecker
    [ "$status" -eq 0 ]
}

@test "ci_is_woodpecker does not detect when DRONE is set" {
    export CI_REPO="owner/repo"
    export CI_SYSTEM_HOST="drone.example.com"
    export DRONE="true"
    _ci_reset_cache
    run ci_is_woodpecker
    [ "$status" -eq 1 ]
}

@test "ci_platform returns 'woodpecker' in Woodpecker CI" {
    export CI_REPO="owner/repo"
    export CI_SYSTEM_HOST="woodpecker.example.com"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "woodpecker" ]
}

@test "ci::name returns 'Woodpecker CI' in Woodpecker CI" {
    export CI_REPO="owner/repo"
    export CI_SYSTEM_HOST="woodpecker.example.com"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Woodpecker CI" ]
}

# =============================================================================
# GITEA ACTIONS TESTS
# =============================================================================

@test "ci_is_gitea_actions detects Gitea Actions" {
    export GITEA_ACTIONS="true"
    _ci_reset_cache
    run ci_is_gitea_actions
    [ "$status" -eq 0 ]
}

@test "ci_platform returns 'gitea' in Gitea Actions" {
    export GITEA_ACTIONS="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "gitea" ]
}

@test "ci::name returns 'Gitea Actions' in Gitea Actions" {
    export GITEA_ACTIONS="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "Gitea Actions" ]
}

@test "ci_info returns Gitea-specific variables" {
    export GITEA_ACTIONS="true"
    export GITEA_RUN_ID="run-123"
    export GITEA_RUN_NUMBER="42"
    export GITEA_REF_NAME="main"
    export GITEA_SHA="abc123"
    export GITEA_REPOSITORY="owner/repo"
    export GITEA_JOB="build"
    _ci_reset_cache

    run ci_info
    [ "$status" -eq 0 ]
    [[ "$output" == *'"platform":"gitea"'* ]]
    [[ "$output" == *'"build_id":"run-123"'* ]]
    [[ "$output" == *'"build_number":"42"'* ]]
}

# =============================================================================
# GENERIC CI TESTS
# =============================================================================

@test "ci_platform returns 'generic' when only CI=true is set" {
    export CI="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "generic" ]
}

@test "ci::name returns 'CI (Generic)' when only CI=true is set" {
    export CI="true"
    _ci_reset_cache
    run ci::name
    [ "$status" -eq 0 ]
    [ "$output" = "CI (Generic)" ]
}

# =============================================================================
# PRIORITY TESTS (platform detection order)
# =============================================================================

@test "GitHub Actions takes priority over generic CI" {
    export CI="true"
    export GITHUB_ACTIONS="true"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "github" ]
}

@test "Specific CI takes priority over BUILD_ID + PROJECT_ID" {
    # Jenkins has priority over Cloud Build detection
    export BUILD_ID="123"
    export PROJECT_ID="my-project"
    export JENKINS_URL="http://jenkins.example.com"
    _ci_reset_cache
    run ci_platform
    [ "$status" -eq 0 ]
    [ "$output" = "jenkins" ]
}

# =============================================================================
# CACHE TESTS
# =============================================================================

@test "_ci_reset_cache clears cached platform" {
    # Note: Caching only works within a single process. Command substitution
    # and 'run' create subshells where cache changes don't persist.
    # This test verifies the reset function exists and clears the variable.

    # Set up environment
    export GITHUB_ACTIONS="true"
    unset GITLAB_CI 2>/dev/null || true

    # Manually set the cache variable (simulating what _ci_detect_platform does)
    _CI_PLATFORM="github"

    # Verify cache is set
    [ "$_CI_PLATFORM" = "github" ]

    # Reset clears the cache
    _ci_reset_cache
    [ -z "$_CI_PLATFORM" ]

    # After reset, new detection will use new environment
    export GITLAB_CI="true"
    unset GITHUB_ACTIONS
    result=$(_ci_detect_platform)
    [ "$result" = "gitlab" ]
}

# =============================================================================
# JSON OUTPUT TESTS
# =============================================================================

@test "ci_info returns valid JSON" {
    export GITHUB_ACTIONS="true"
    export GITHUB_RUN_ID="12345"
    _ci_reset_cache

    run ci_info
    [ "$status" -eq 0 ]

    # Basic JSON validation: starts with { and ends with }
    [[ "$output" == "{"* ]]
    [[ "$output" == *"}" ]]

    # Should have platform key
    [[ "$output" == *'"platform":'* ]]
}

@test "ci_info handles empty values gracefully" {
    export GITHUB_ACTIONS="true"
    # Only set the trigger env var, leave all others unset
    _ci_reset_cache

    run ci_info
    [ "$status" -eq 0 ]

    # Should still return valid JSON with empty strings
    [[ "$output" == *'"platform":"github"'* ]]
    [[ "$output" == *'"build_id":""'* ]]
}

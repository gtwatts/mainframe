#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ci.sh - CI/CD Portability Functions
# =============================================================================
# Description: Cross-platform CI/CD detection and helpers for 17 CI platforms:
#              GitHub Actions, GitLab CI, Jenkins, CircleCI, Travis CI, Azure
#              Pipelines, BuildKite, Bitbucket Pipelines, TeamCity, AppVeyor,
#              AWS CodeBuild, Google Cloud Build, Drone CI, Semaphore CI,
#              Buddy, Woodpecker CI, and Gitea Actions.
# Dependency: None (pure bash)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CI_LOADED=1

# Portable SHA-256 digest (sha256sum -> shasum -> openssl fallback chain).
# Shared micro-shim: the declare -F guard means it is defined once per
# process no matter how many MAINFRAME libraries are sourced.
if ! declare -F _mainframe_sha256 &>/dev/null; then
_mainframe_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$@"
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$@"
    else
        openssl dgst -sha256 "$@" | sed 's/^.* //'
    fi
}
fi

# =============================================================================
# INTERNAL: CI PLATFORM DETECTION
# =============================================================================

# Cached CI platform (set on first detection)
declare -g _CI_PLATFORM=""

# Detect the current CI platform
# Returns: github, gitlab, jenkins, circleci, travis, azure, buildkite, bitbucket,
#          teamcity, appveyor, codebuild, cloudbuild, drone, semaphore, buddy,
#          woodpecker, gitea, none
_ci_detect_platform() {
    # Return cached result if available
    if [[ -n "$_CI_PLATFORM" ]]; then
        printf '%s\n' "$_CI_PLATFORM"
        return 0
    fi

    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        _CI_PLATFORM="github"
    # GitLab CI
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        _CI_PLATFORM="gitlab"
    # Jenkins
    elif [[ -n "${JENKINS_URL:-}" ]] || { [[ -n "${BUILD_ID:-}" ]] && [[ -n "${JOB_NAME:-}" ]]; }; then
        _CI_PLATFORM="jenkins"
    # CircleCI
    elif [[ -n "${CIRCLECI:-}" ]]; then
        _CI_PLATFORM="circleci"
    # Travis CI
    elif [[ -n "${TRAVIS:-}" ]]; then
        _CI_PLATFORM="travis"
    # Azure Pipelines
    elif [[ -n "${TF_BUILD:-}" ]] || [[ -n "${AZURE_PIPELINES:-}" ]]; then
        _CI_PLATFORM="azure"
    # BuildKite
    elif [[ "${BUILDKITE:-}" == "true" ]]; then
        _CI_PLATFORM="buildkite"
    # Bitbucket Pipelines
    elif [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]; then
        _CI_PLATFORM="bitbucket"
    # TeamCity
    elif [[ -n "${TEAMCITY_VERSION:-}" ]]; then
        _CI_PLATFORM="teamcity"
    # AppVeyor
    elif [[ "${APPVEYOR:-}" == "True" ]] || [[ "${APPVEYOR:-}" == "true" ]]; then
        _CI_PLATFORM="appveyor"
    # AWS CodeBuild
    elif [[ -n "${CODEBUILD_BUILD_ID:-}" ]]; then
        _CI_PLATFORM="codebuild"
    # Google Cloud Build
    elif [[ -n "${CLOUD_BUILD_ID:-}" ]] || [[ -n "${BUILD_ID:-}" && -n "${PROJECT_ID:-}" && -z "${JENKINS_URL:-}" ]]; then
        _CI_PLATFORM="cloudbuild"
    # Drone CI
    elif [[ "${DRONE:-}" == "true" ]]; then
        _CI_PLATFORM="drone"
    # Semaphore CI
    elif [[ "${SEMAPHORE:-}" == "true" ]]; then
        _CI_PLATFORM="semaphore"
    # Buddy
    elif [[ "${BUDDY:-}" == "true" ]]; then
        _CI_PLATFORM="buddy"
    # Woodpecker CI (check CI_REPO with woodpecker-specific marker)
    elif [[ -n "${CI_REPO:-}" ]] && [[ -n "${CI_SYSTEM_HOST:-}" ]] && [[ -z "${DRONE:-}" ]]; then
        _CI_PLATFORM="woodpecker"
    # Gitea Actions
    elif [[ "${GITEA_ACTIONS:-}" == "true" ]]; then
        _CI_PLATFORM="gitea"
    # Generic CI detection (fallback)
    elif [[ "${CI:-}" == "true" ]]; then
        _CI_PLATFORM="generic"
    # Not in CI
    else
        _CI_PLATFORM="none"
    fi

    printf '%s\n' "$_CI_PLATFORM"
}

# =============================================================================
# INDIVIDUAL PLATFORM DETECTORS
# =============================================================================

# @idempotent Detect if running in GitHub Actions
# @return 0 if in GitHub Actions, 1 if not
ci_is_github_actions() {
    [[ -n "${GITHUB_ACTIONS:-}" ]]
}

# @idempotent Detect if running in GitLab CI
# @return 0 if in GitLab CI, 1 if not
ci_is_gitlab_ci() {
    [[ -n "${GITLAB_CI:-}" ]]
}

# @idempotent Detect if running in Jenkins
# @return 0 if in Jenkins, 1 if not
ci_is_jenkins() {
    [[ -n "${JENKINS_URL:-}" ]] || { [[ -n "${BUILD_ID:-}" ]] && [[ -n "${JOB_NAME:-}" ]]; }
}

# @idempotent Detect if running in BuildKite
# @return 0 if in BuildKite, 1 if not
ci_is_buildkite() {
    [[ "${BUILDKITE:-}" == "true" ]]
}

# @idempotent Detect if running in Bitbucket Pipelines
# @return 0 if in Bitbucket Pipelines, 1 if not
ci_is_bitbucket() {
    [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]
}

# @idempotent Detect if running in TeamCity
# @return 0 if in TeamCity, 1 if not
ci_is_teamcity() {
    [[ -n "${TEAMCITY_VERSION:-}" ]]
}

# @idempotent Detect if running in CircleCI
# @return 0 if in CircleCI, 1 if not
ci_is_circleci() {
    [[ -n "${CIRCLECI:-}" ]]
}

# @idempotent Detect if running in Travis CI
# @return 0 if in Travis CI, 1 if not
ci_is_travis() {
    [[ -n "${TRAVIS:-}" ]]
}

# @idempotent Detect if running in AppVeyor
# @return 0 if in AppVeyor, 1 if not
ci_is_appveyor() {
    [[ "${APPVEYOR:-}" == "True" ]] || [[ "${APPVEYOR:-}" == "true" ]]
}

# @idempotent Detect if running in Azure Pipelines
# @return 0 if in Azure Pipelines, 1 if not
ci_is_azure_pipelines() {
    [[ -n "${TF_BUILD:-}" ]] || [[ -n "${AZURE_PIPELINES:-}" ]]
}

# @idempotent Detect if running in AWS CodeBuild
# @return 0 if in AWS CodeBuild, 1 if not
ci_is_aws_codebuild() {
    [[ -n "${CODEBUILD_BUILD_ID:-}" ]]
}

# @idempotent Detect if running in Google Cloud Build
# @return 0 if in GCP Cloud Build, 1 if not
ci_is_gcp_cloud_build() {
    [[ -n "${CLOUD_BUILD_ID:-}" ]] || { [[ -n "${BUILD_ID:-}" ]] && [[ -n "${PROJECT_ID:-}" ]] && [[ -z "${JENKINS_URL:-}" ]]; }
}

# @idempotent Detect if running in Drone CI
# @return 0 if in Drone CI, 1 if not
ci_is_drone() {
    [[ "${DRONE:-}" == "true" ]]
}

# @idempotent Detect if running in Semaphore CI
# @return 0 if in Semaphore CI, 1 if not
ci_is_semaphore() {
    [[ "${SEMAPHORE:-}" == "true" ]]
}

# @idempotent Detect if running in Buddy
# @return 0 if in Buddy, 1 if not
ci_is_buddy() {
    [[ "${BUDDY:-}" == "true" ]]
}

# @idempotent Detect if running in Woodpecker CI
# @return 0 if in Woodpecker CI, 1 if not
ci_is_woodpecker() {
    [[ -n "${CI_REPO:-}" ]] && [[ -n "${CI_SYSTEM_HOST:-}" ]] && [[ -z "${DRONE:-}" ]]
}

# @idempotent Detect if running in Gitea Actions
# @return 0 if in Gitea Actions, 1 if not
ci_is_gitea_actions() {
    [[ "${GITEA_ACTIONS:-}" == "true" ]]
}

# =============================================================================
# UNIVERSAL CI DETECTION FUNCTIONS
# =============================================================================

# @idempotent Detect if running in ANY CI environment
# @return 0 if in CI, 1 if not
ci_is_ci() {
    local platform
    platform=$(_ci_detect_platform)
    [[ "$platform" != "none" ]]
}

# @idempotent Get CI platform name
# @return Platform name (lowercase identifier) or "unknown" if not in CI
ci_platform() {
    local platform
    platform=$(_ci_detect_platform)
    if [[ "$platform" == "none" ]]; then
        printf 'unknown\n'
    else
        printf '%s\n' "$platform"
    fi
}

# @idempotent Get CI-specific variables as JSON
# @return {"platform":"github","build_id":"123","branch":"main",...}
ci_info() {
    local platform
    platform=$(_ci_detect_platform)

    local build_id=""
    local build_number=""
    local branch=""
    local commit=""
    local pr_number=""
    local repo=""
    local job_name=""
    local runner=""

    case "$platform" in
        github)
            build_id="${GITHUB_RUN_ID:-}"
            build_number="${GITHUB_RUN_NUMBER:-}"
            branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"
            commit="${GITHUB_SHA:-}"
            pr_number=""
            [[ "${GITHUB_REF:-}" =~ refs/pull/([0-9]+) ]] && pr_number="${BASH_REMATCH[1]}"
            repo="${GITHUB_REPOSITORY:-}"
            job_name="${GITHUB_JOB:-}"
            runner="${RUNNER_NAME:-${RUNNER_OS:-}}"
            ;;
        gitlab)
            build_id="${CI_PIPELINE_ID:-}"
            build_number="${CI_PIPELINE_IID:-}"
            branch="${CI_COMMIT_REF_NAME:-}"
            commit="${CI_COMMIT_SHA:-}"
            pr_number="${CI_MERGE_REQUEST_IID:-}"
            repo="${CI_PROJECT_PATH:-}"
            job_name="${CI_JOB_NAME:-}"
            runner="${CI_RUNNER_DESCRIPTION:-}"
            ;;
        jenkins)
            build_id="${BUILD_ID:-}"
            build_number="${BUILD_NUMBER:-}"
            branch="${GIT_BRANCH:-${BRANCH_NAME:-}}"
            commit="${GIT_COMMIT:-}"
            pr_number="${CHANGE_ID:-${ghprbPullId:-}}"
            repo=""
            job_name="${JOB_NAME:-}"
            runner="${NODE_NAME:-}"
            ;;
        buildkite)
            build_id="${BUILDKITE_BUILD_ID:-}"
            build_number="${BUILDKITE_BUILD_NUMBER:-}"
            branch="${BUILDKITE_BRANCH:-}"
            commit="${BUILDKITE_COMMIT:-}"
            pr_number="${BUILDKITE_PULL_REQUEST:-}"
            [[ "$pr_number" == "false" ]] && pr_number=""
            repo="${BUILDKITE_REPO:-}"
            job_name="${BUILDKITE_LABEL:-}"
            runner="${BUILDKITE_AGENT_NAME:-}"
            ;;
        bitbucket)
            build_id="${BITBUCKET_PIPELINE_UUID:-}"
            build_number="${BITBUCKET_BUILD_NUMBER:-}"
            branch="${BITBUCKET_BRANCH:-}"
            commit="${BITBUCKET_COMMIT:-}"
            pr_number="${BITBUCKET_PR_ID:-}"
            repo="${BITBUCKET_REPO_FULL_NAME:-}"
            job_name="${BITBUCKET_STEP_UUID:-}"
            runner=""
            ;;
        teamcity)
            build_id="${BUILD_VCS_NUMBER:-}"
            build_number="${BUILD_NUMBER:-}"
            branch="${BRANCH_NAME:-}"
            commit="${BUILD_VCS_NUMBER:-}"
            pr_number=""
            repo=""
            job_name="${TEAMCITY_BUILDCONF_NAME:-}"
            runner="${AGENT_NAME:-}"
            ;;
        circleci)
            build_id="${CIRCLE_WORKFLOW_ID:-}"
            build_number="${CIRCLE_BUILD_NUM:-}"
            branch="${CIRCLE_BRANCH:-}"
            commit="${CIRCLE_SHA1:-}"
            pr_number="${CIRCLE_PULL_REQUEST##*/}"
            repo="${CIRCLE_PROJECT_USERNAME:-}/${CIRCLE_PROJECT_REPONAME:-}"
            job_name="${CIRCLE_JOB:-}"
            runner="${CIRCLE_NODE_INDEX:-0}/${CIRCLE_NODE_TOTAL:-1}"
            ;;
        travis)
            build_id="${TRAVIS_BUILD_ID:-}"
            build_number="${TRAVIS_BUILD_NUMBER:-}"
            branch="${TRAVIS_BRANCH:-}"
            commit="${TRAVIS_COMMIT:-}"
            pr_number="${TRAVIS_PULL_REQUEST:-}"
            [[ "$pr_number" == "false" ]] && pr_number=""
            repo="${TRAVIS_REPO_SLUG:-}"
            job_name="${TRAVIS_JOB_NAME:-}"
            runner=""
            ;;
        appveyor)
            build_id="${APPVEYOR_BUILD_ID:-}"
            build_number="${APPVEYOR_BUILD_NUMBER:-}"
            branch="${APPVEYOR_REPO_BRANCH:-}"
            commit="${APPVEYOR_REPO_COMMIT:-}"
            pr_number="${APPVEYOR_PULL_REQUEST_NUMBER:-}"
            repo="${APPVEYOR_REPO_NAME:-}"
            job_name="${APPVEYOR_JOB_NAME:-}"
            runner=""
            ;;
        azure)
            build_id="${BUILD_BUILDID:-}"
            build_number="${BUILD_BUILDNUMBER:-}"
            branch="${BUILD_SOURCEBRANCH#refs/heads/}"
            commit="${BUILD_SOURCEVERSION:-}"
            pr_number="${SYSTEM_PULLREQUEST_PULLREQUESTID:-}"
            repo="${BUILD_REPOSITORY_NAME:-}"
            job_name="${SYSTEM_JOBNAME:-}"
            runner="${AGENT_NAME:-}"
            ;;
        codebuild)
            build_id="${CODEBUILD_BUILD_ID:-}"
            build_number="${CODEBUILD_BUILD_NUMBER:-}"
            branch="${CODEBUILD_SOURCE_VERSION:-}"
            commit="${CODEBUILD_RESOLVED_SOURCE_VERSION:-}"
            pr_number=""
            repo="${CODEBUILD_SOURCE_REPO_URL:-}"
            job_name="${CODEBUILD_BUILD_ID:-}"
            runner=""
            ;;
        cloudbuild)
            build_id="${BUILD_ID:-}"
            build_number=""
            branch="${BRANCH_NAME:-}"
            commit="${COMMIT_SHA:-}"
            pr_number=""
            repo="${REPO_NAME:-}"
            job_name="${TRIGGER_NAME:-}"
            runner=""
            ;;
        drone)
            build_id="${DRONE_BUILD_NUMBER:-}"
            build_number="${DRONE_BUILD_NUMBER:-}"
            branch="${DRONE_BRANCH:-}"
            commit="${DRONE_COMMIT_SHA:-}"
            pr_number="${DRONE_PULL_REQUEST:-}"
            repo="${DRONE_REPO:-}"
            job_name="${DRONE_STAGE_NAME:-}"
            runner="${DRONE_RUNNER_HOST:-}"
            ;;
        semaphore)
            build_id="${SEMAPHORE_WORKFLOW_ID:-}"
            build_number="${SEMAPHORE_WORKFLOW_NUMBER:-}"
            branch="${SEMAPHORE_GIT_BRANCH:-}"
            commit="${SEMAPHORE_GIT_SHA:-}"
            pr_number="${SEMAPHORE_GIT_PR_NUMBER:-}"
            repo="${SEMAPHORE_GIT_URL:-}"
            job_name="${SEMAPHORE_JOB_NAME:-}"
            runner="${SEMAPHORE_AGENT_MACHINE_TYPE:-}"
            ;;
        buddy)
            build_id="${BUDDY_EXECUTION_ID:-}"
            build_number="${BUDDY_EXECUTION_ID:-}"
            branch="${BUDDY_EXECUTION_BRANCH:-}"
            commit="${BUDDY_EXECUTION_REVISION:-}"
            pr_number="${BUDDY_EXECUTION_PULL_REQUEST_ID:-}"
            repo="${BUDDY_REPO_SLUG:-}"
            job_name="${BUDDY_PIPELINE_NAME:-}"
            runner=""
            ;;
        woodpecker)
            build_id="${CI_BUILD_NUMBER:-}"
            build_number="${CI_BUILD_NUMBER:-}"
            branch="${CI_COMMIT_BRANCH:-}"
            commit="${CI_COMMIT_SHA:-}"
            pr_number="${CI_COMMIT_PULL_REQUEST:-}"
            repo="${CI_REPO:-}"
            job_name="${CI_STEP_NAME:-}"
            runner="${CI_MACHINE:-}"
            ;;
        gitea)
            build_id="${GITEA_RUN_ID:-}"
            build_number="${GITEA_RUN_NUMBER:-}"
            branch="${GITEA_REF_NAME:-}"
            commit="${GITEA_SHA:-}"
            pr_number=""
            repo="${GITEA_REPOSITORY:-}"
            job_name="${GITEA_JOB:-}"
            runner="${GITEA_RUNNER_NAME:-}"
            ;;
        generic)
            # Generic CI - try common env vars
            build_id="${CI_BUILD_ID:-${BUILD_ID:-}}"
            build_number="${CI_BUILD_NUMBER:-${BUILD_NUMBER:-}}"
            branch="${CI_BRANCH:-${BRANCH_NAME:-}}"
            commit="${CI_COMMIT:-${GIT_COMMIT:-}}"
            pr_number=""
            repo=""
            job_name="${CI_JOB_NAME:-${JOB_NAME:-}}"
            runner=""
            ;;
    esac

    # Build JSON output using json_object if available, otherwise manual construction
    if declare -f json_object &>/dev/null; then
        json_object \
            "platform=${platform}" \
            "build_id=${build_id}" \
            "build_number=${build_number}" \
            "branch=${branch}" \
            "commit=${commit}" \
            "pr_number=${pr_number}" \
            "repository=${repo}" \
            "job_name=${job_name}" \
            "runner=${runner}"
    else
        # Manual JSON construction for standalone usage
        printf '{"platform":"%s","build_id":"%s","build_number":"%s","branch":"%s","commit":"%s","pr_number":"%s","repository":"%s","job_name":"%s","runner":"%s"}\n' \
            "$platform" "$build_id" "$build_number" "$branch" "$commit" "$pr_number" "$repo" "$job_name" "$runner"
    fi
}

# Reset cached platform (useful for testing)
# @internal
_ci_reset_cache() {
    _CI_PLATFORM=""
}

# =============================================================================
# CI DETECTION
# =============================================================================

# Check if running in any CI environment
# Usage: ci::is_ci && echo "Running in CI"
# Returns: 0 if in CI, 1 if not
ci::is_ci() {
    local platform
    platform=$(_ci_detect_platform)
    [[ "$platform" != "none" ]]
}

# Detect which CI platform is running
# Usage: platform=$(ci::detect)
# Returns: github, gitlab, jenkins, circleci, travis, azure, none
ci::detect() {
    _ci_detect_platform
}

# Get human-readable CI platform name
# Usage: name=$(ci::name)
# Returns: "GitHub Actions", "GitLab CI", etc.
ci::name() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)     printf 'GitHub Actions\n' ;;
        gitlab)     printf 'GitLab CI\n' ;;
        jenkins)    printf 'Jenkins\n' ;;
        circleci)   printf 'CircleCI\n' ;;
        travis)     printf 'Travis CI\n' ;;
        azure)      printf 'Azure Pipelines\n' ;;
        buildkite)  printf 'BuildKite\n' ;;
        bitbucket)  printf 'Bitbucket Pipelines\n' ;;
        teamcity)   printf 'TeamCity\n' ;;
        appveyor)   printf 'AppVeyor\n' ;;
        codebuild)  printf 'AWS CodeBuild\n' ;;
        cloudbuild) printf 'Google Cloud Build\n' ;;
        drone)      printf 'Drone CI\n' ;;
        semaphore)  printf 'Semaphore CI\n' ;;
        buddy)      printf 'Buddy\n' ;;
        woodpecker) printf 'Woodpecker CI\n' ;;
        gitea)      printf 'Gitea Actions\n' ;;
        generic)    printf 'CI (Generic)\n' ;;
        none)       printf 'Local\n' ;;
        *)          printf 'Unknown\n' ;;
    esac
}

# =============================================================================
# CROSS-CI OUTPUT
# =============================================================================

# Set output variable for subsequent steps
# Usage: ci::set_output "key" "value"
# Works on: GitHub Actions, GitLab CI, Azure Pipelines
ci::set_output() {
    local key="$1"
    local value="$2"

    [[ -z "$key" ]] && return 1

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            # GitHub Actions - use GITHUB_OUTPUT file
            if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
            else
                # Legacy method (deprecated but fallback)
                printf '::set-output name=%s::%s\n' "$key" "$value"
            fi
            ;;
        gitlab)
            # GitLab CI - use dotenv artifact or job.env
            if [[ -n "${CI_PROJECT_DIR:-}" ]]; then
                printf '%s=%s\n' "$key" "$value" >> "${CI_PROJECT_DIR}/.env"
            fi
            # Also export to current environment
            export "$key=$value"
            ;;
        azure)
            # Azure Pipelines - use logging command
            printf '##vso[task.setvariable variable=%s;isOutput=true]%s\n' "$key" "$value"
            ;;
        jenkins)
            # Jenkins - export and write to env file if available
            export "$key=$value"
            if [[ -n "${WORKSPACE:-}" ]]; then
                printf '%s=%s\n' "$key" "$value" >> "${WORKSPACE}/.env"
            fi
            ;;
        circleci)
            # CircleCI - use $BASH_ENV for persistence
            if [[ -n "${BASH_ENV:-}" ]]; then
                printf 'export %s="%s"\n' "$key" "$value" >> "$BASH_ENV"
            fi
            export "$key=$value"
            ;;
        travis)
            # Travis CI - export to environment
            export "$key=$value"
            ;;
        *)
            # Local - just export
            export "$key=$value"
            ;;
    esac
}

# Set environment variable for subsequent steps
# Usage: ci::set_env "VAR" "value"
ci::set_env() {
    local var="$1"
    local value="$2"

    [[ -z "$var" ]] && return 1

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            # GitHub Actions - use GITHUB_ENV file
            if [[ -n "${GITHUB_ENV:-}" ]]; then
                printf '%s=%s\n' "$var" "$value" >> "$GITHUB_ENV"
            fi
            export "$var=$value"
            ;;
        gitlab)
            # GitLab CI - write to .env for dotenv artifact
            if [[ -n "${CI_PROJECT_DIR:-}" ]]; then
                printf '%s=%s\n' "$var" "$value" >> "${CI_PROJECT_DIR}/.env"
            fi
            export "$var=$value"
            ;;
        azure)
            # Azure Pipelines - use logging command
            printf '##vso[task.setvariable variable=%s]%s\n' "$var" "$value"
            export "$var=$value"
            ;;
        jenkins)
            # Jenkins - export to environment
            export "$var=$value"
            ;;
        circleci)
            # CircleCI - use $BASH_ENV
            if [[ -n "${BASH_ENV:-}" ]]; then
                printf 'export %s="%s"\n' "$var" "$value" >> "$BASH_ENV"
            fi
            export "$var=$value"
            ;;
        travis)
            # Travis CI - export
            export "$var=$value"
            ;;
        *)
            export "$var=$value"
            ;;
    esac
}

# Add directory to PATH for subsequent steps
# Usage: ci::add_path "/new/path"
ci::add_path() {
    local new_path="$1"

    [[ -z "$new_path" ]] && return 1

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            # GitHub Actions - use GITHUB_PATH file
            if [[ -n "${GITHUB_PATH:-}" ]]; then
                printf '%s\n' "$new_path" >> "$GITHUB_PATH"
            fi
            export PATH="$new_path:$PATH"
            ;;
        gitlab)
            # GitLab CI - export with persistence
            if [[ -n "${CI_PROJECT_DIR:-}" ]]; then
                # shellcheck disable=SC2016  # $PATH is intentionally literal for .env file
                printf 'export PATH="%s:$PATH"\n' "$new_path" >> "${CI_PROJECT_DIR}/.env"
            fi
            export PATH="$new_path:$PATH"
            ;;
        azure)
            # Azure Pipelines - use prepend path command
            printf '##vso[task.prependpath]%s\n' "$new_path"
            export PATH="$new_path:$PATH"
            ;;
        circleci)
            # CircleCI - use $BASH_ENV
            if [[ -n "${BASH_ENV:-}" ]]; then
                # shellcheck disable=SC2016  # $PATH is intentionally literal for BASH_ENV
                printf 'export PATH="%s:$PATH"\n' "$new_path" >> "$BASH_ENV"
            fi
            export PATH="$new_path:$PATH"
            ;;
        *)
            export PATH="$new_path:$PATH"
            ;;
    esac
}

# Start a collapsible group in CI logs
# Usage: ci::group_start "Group Name"
ci::group_start() {
    local name="$1"

    [[ -z "$name" ]] && return 1

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '::group::%s\n' "$name"
            ;;
        gitlab)
            # GitLab uses section markers
            printf '\e[0Ksection_start:%s:%s[collapsed=true]\r\e[0K%s\n' \
                "$(date +%s)" "$(printf '%s' "$name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')" "$name"
            ;;
        azure)
            printf '##[group]%s\n' "$name"
            ;;
        travis)
            printf 'travis_fold:start:%s\n' "$(printf '%s' "$name" | tr ' ' '_')"
            printf '%s\n' "$name"
            ;;
        circleci)
            # CircleCI doesn't have native groups, use visual separator
            printf '\n>>> %s <<<\n' "$name"
            ;;
        jenkins)
            # Jenkins Pipeline uses timestamps, but for freestyle:
            printf '\n=== %s ===\n' "$name"
            ;;
        *)
            printf '\n=== %s ===\n' "$name"
            ;;
    esac
}

# End a collapsible group in CI logs
# Usage: ci::group_end
ci::group_end() {
    local platform
    platform=$(_ci_detect_platform)

    # For GitLab, we need to track the section name
    local section_name="${_CI_CURRENT_SECTION:-group}"

    case "$platform" in
        github)
            printf '::endgroup::\n'
            ;;
        gitlab)
            printf '\e[0Ksection_end:%s:%s\r\e[0K\n' "$(date +%s)" "$section_name"
            ;;
        azure)
            printf '##[endgroup]\n'
            ;;
        travis)
            printf 'travis_fold:end:%s\n' "$section_name"
            ;;
        *)
            printf '\n'
            ;;
    esac
}

# =============================================================================
# CI LOGGING / ANNOTATIONS
# =============================================================================

# Log a warning message (shows in CI UI if supported)
# Usage: ci::warning "message" [file] [line]
ci::warning() {
    local message="$1"
    local file="${2:-}"
    local line="${3:-}"

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            if [[ -n "$file" && -n "$line" ]]; then
                printf '::warning file=%s,line=%s::%s\n' "$file" "$line" "$message"
            elif [[ -n "$file" ]]; then
                printf '::warning file=%s::%s\n' "$file" "$message"
            else
                printf '::warning::%s\n' "$message"
            fi
            ;;
        gitlab)
            # GitLab uses ANSI orange for warnings
            printf '\e[0;33mWarning: %s\e[0m\n' "$message"
            ;;
        azure)
            printf '##[warning]%s\n' "$message"
            ;;
        *)
            printf 'Warning: %s\n' "$message" >&2
            ;;
    esac
}

# Log an error message (shows in CI UI if supported)
# Usage: ci::error "message" [file] [line]
ci::error() {
    local message="$1"
    local file="${2:-}"
    local line="${3:-}"

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            if [[ -n "$file" && -n "$line" ]]; then
                printf '::error file=%s,line=%s::%s\n' "$file" "$line" "$message"
            elif [[ -n "$file" ]]; then
                printf '::error file=%s::%s\n' "$file" "$message"
            else
                printf '::error::%s\n' "$message"
            fi
            ;;
        gitlab)
            printf '\e[0;31mError: %s\e[0m\n' "$message"
            ;;
        azure)
            printf '##[error]%s\n' "$message"
            ;;
        *)
            printf 'Error: %s\n' "$message" >&2
            ;;
    esac
}

# Log a notice/info message
# Usage: ci::notice "message"
ci::notice() {
    local message="$1"

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '::notice::%s\n' "$message"
            ;;
        azure)
            printf '##[command]%s\n' "$message"
            ;;
        *)
            printf 'Notice: %s\n' "$message"
            ;;
    esac
}

# Log a debug message (only visible if debug logging enabled)
# Usage: ci::debug "message"
ci::debug() {
    local message="$1"

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '::debug::%s\n' "$message"
            ;;
        azure)
            printf '##[debug]%s\n' "$message"
            ;;
        *)
            if [[ -n "${CI_DEBUG:-}" || -n "${RUNNER_DEBUG:-}" ]]; then
                printf 'Debug: %s\n' "$message" >&2
            fi
            ;;
    esac
}

# =============================================================================
# ARTIFACTS
# =============================================================================

# Create a checksum for a file (SHA256)
# Usage: checksum=$(ci::artifact_checksum "file")
ci::artifact_checksum() {
    local file="$1"

    [[ -z "$file" || ! -e "$file" ]] && return 1

    if command -v sha256sum &>/dev/null; then
        _mainframe_sha256 "$file" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        # Fallback to openssl
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

# Create an artifact with checksum file
# Usage: ci::artifact_create "source" "name"
# Creates: name.tar.gz and name.tar.gz.sha256
ci::artifact_create() {
    local source="$1"
    local name="$2"

    [[ -z "$source" || -z "$name" ]] && return 1
    [[ ! -e "$source" ]] && return 1

    local artifact_file="${name}.tar.gz"
    local checksum_file="${artifact_file}.sha256"

    # Create tarball
    if [[ -d "$source" ]]; then
        tar -czf "$artifact_file" -C "$(dirname "$source")" "$(basename "$source")"
    else
        tar -czf "$artifact_file" -C "$(dirname "$source")" "$(basename "$source")"
    fi

    # Create checksum
    local checksum
    checksum=$(ci::artifact_checksum "$artifact_file")
    printf '%s  %s\n' "$checksum" "$artifact_file" > "$checksum_file"

    # Output info based on CI
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            ci::set_output "${name}_artifact" "$artifact_file"
            ci::set_output "${name}_checksum" "$checksum"
            ;;
        *)
            printf 'Created artifact: %s (checksum: %s)\n' "$artifact_file" "$checksum"
            ;;
    esac

    printf '%s\n' "$artifact_file"
}

# =============================================================================
# PULL REQUEST / MERGE REQUEST INFO
# =============================================================================

# Check if running in a PR/MR context
# Usage: ci::is_pull_request && echo "This is a PR"
ci::is_pull_request() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            [[ -n "${GITHUB_EVENT_NAME:-}" && "$GITHUB_EVENT_NAME" == "pull_request"* ]] || \
            [[ -n "${GITHUB_HEAD_REF:-}" ]]
            ;;
        gitlab)
            [[ -n "${CI_MERGE_REQUEST_ID:-}" || -n "${CI_EXTERNAL_PULL_REQUEST_IID:-}" ]]
            ;;
        jenkins)
            [[ -n "${CHANGE_ID:-}" || -n "${ghprbPullId:-}" ]]
            ;;
        circleci)
            [[ -n "${CIRCLE_PULL_REQUEST:-}" ]]
            ;;
        travis)
            [[ -n "${TRAVIS_PULL_REQUEST:-}" && "${TRAVIS_PULL_REQUEST}" != "false" ]]
            ;;
        azure)
            [[ -n "${SYSTEM_PULLREQUEST_PULLREQUESTID:-}" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Get PR/MR number
# Usage: pr_num=$(ci::pr_number)
ci::pr_number() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            # Extract from GITHUB_REF (refs/pull/123/merge) or GITHUB_EVENT
            if [[ -n "${GITHUB_REF:-}" && "$GITHUB_REF" =~ refs/pull/([0-9]+) ]]; then
                printf '%s\n' "${BASH_REMATCH[1]}"
            elif [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
                # Parse from event JSON if available
                grep -o '"number":[0-9]*' "$GITHUB_EVENT_PATH" 2>/dev/null | head -1 | grep -o '[0-9]*'
            fi
            ;;
        gitlab)
            printf '%s\n' "${CI_MERGE_REQUEST_IID:-${CI_EXTERNAL_PULL_REQUEST_IID:-}}"
            ;;
        jenkins)
            printf '%s\n' "${CHANGE_ID:-${ghprbPullId:-}}"
            ;;
        circleci)
            # Extract from URL: https://github.com/org/repo/pull/123
            if [[ -n "${CIRCLE_PULL_REQUEST:-}" ]]; then
                printf '%s\n' "${CIRCLE_PULL_REQUEST##*/}"
            fi
            ;;
        travis)
            printf '%s\n' "${TRAVIS_PULL_REQUEST:-}"
            ;;
        azure)
            printf '%s\n' "${SYSTEM_PULLREQUEST_PULLREQUESTID:-}"
            ;;
    esac
}

# Get the source branch of the PR/MR
# Usage: branch=$(ci::pr_branch)
ci::pr_branch() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${GITHUB_HEAD_REF:-}"
            ;;
        gitlab)
            printf '%s\n' "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}"
            ;;
        jenkins)
            printf '%s\n' "${CHANGE_BRANCH:-${ghprbSourceBranch:-}}"
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_BRANCH:-}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_PULL_REQUEST_BRANCH:-}"
            ;;
        azure)
            # Remove refs/heads/ prefix
            local branch="${SYSTEM_PULLREQUEST_SOURCEBRANCH:-}"
            printf '%s\n' "${branch#refs/heads/}"
            ;;
        *)
            # Fallback to git
            git rev-parse --abbrev-ref HEAD 2>/dev/null
            ;;
    esac
}

# Get the target branch of the PR/MR
# Usage: target=$(ci::pr_target)
ci::pr_target() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${GITHUB_BASE_REF:-}"
            ;;
        gitlab)
            printf '%s\n' "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
            ;;
        jenkins)
            printf '%s\n' "${CHANGE_TARGET:-${ghprbTargetBranch:-}}"
            ;;
        circleci)
            # CircleCI doesn't provide this directly, often main/master
            printf '%s\n' "${CIRCLE_BASE_REVISION:-main}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_BRANCH:-}"
            ;;
        azure)
            local branch="${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"
            printf '%s\n' "${branch#refs/heads/}"
            ;;
        *)
            printf 'main\n'
            ;;
    esac
}

# =============================================================================
# GIT INFO IN CI
# =============================================================================

# Get full commit SHA
# Usage: sha=$(ci::commit_sha)
ci::commit_sha() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        gitlab)
            printf '%s\n' "${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        jenkins)
            printf '%s\n' "${GIT_COMMIT:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_SHA1:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_COMMIT:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        azure)
            printf '%s\n' "${BUILD_SOURCEVERSION:-$(git rev-parse HEAD 2>/dev/null)}"
            ;;
        *)
            git rev-parse HEAD 2>/dev/null
            ;;
    esac
}

# Get short commit SHA (7 chars)
# Usage: short=$(ci::commit_short)
ci::commit_short() {
    local sha
    sha=$(ci::commit_sha)
    printf '%s\n' "${sha:0:7}"
}

# Get current branch name
# Usage: branch=$(ci::branch)
ci::branch() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            # GITHUB_REF_NAME is cleaner, fallback to parsing GITHUB_REF
            if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
                printf '%s\n' "$GITHUB_REF_NAME"
            elif [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
                # PR context
                printf '%s\n' "$GITHUB_HEAD_REF"
            elif [[ -n "${GITHUB_REF:-}" ]]; then
                local ref="${GITHUB_REF#refs/heads/}"
                ref="${ref#refs/tags/}"
                printf '%s\n' "$ref"
            fi
            ;;
        gitlab)
            printf '%s\n' "${CI_COMMIT_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
            ;;
        jenkins)
            # Jenkins can have various branch env vars
            printf '%s\n' "${GIT_BRANCH:-${BRANCH_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}}"
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
            ;;
        azure)
            # BUILD_SOURCEBRANCH has format refs/heads/branch
            local branch="${BUILD_SOURCEBRANCH:-}"
            branch="${branch#refs/heads/}"
            branch="${branch#refs/tags/}"
            printf '%s\n' "${branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
            ;;
        *)
            git rev-parse --abbrev-ref HEAD 2>/dev/null
            ;;
    esac
}

# Get tag name if building a tag
# Usage: tag=$(ci::tag)
# Returns: Tag name or empty if not a tag build
ci::tag() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
                printf '%s\n' "${GITHUB_REF#refs/tags/}"
            elif [[ -n "${GITHUB_REF_TYPE:-}" && "$GITHUB_REF_TYPE" == "tag" ]]; then
                printf '%s\n' "${GITHUB_REF_NAME:-}"
            fi
            ;;
        gitlab)
            if [[ -n "${CI_COMMIT_TAG:-}" ]]; then
                printf '%s\n' "$CI_COMMIT_TAG"
            fi
            ;;
        jenkins)
            if [[ -n "${TAG_NAME:-}" ]]; then
                printf '%s\n' "$TAG_NAME"
            elif [[ "${GIT_BRANCH:-}" == refs/tags/* ]]; then
                printf '%s\n' "${GIT_BRANCH#refs/tags/}"
            fi
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_TAG:-}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_TAG:-}"
            ;;
        azure)
            if [[ "${BUILD_SOURCEBRANCH:-}" == refs/tags/* ]]; then
                printf '%s\n' "${BUILD_SOURCEBRANCH#refs/tags/}"
            fi
            ;;
        *)
            # Try to detect from git
            git describe --exact-match --tags HEAD 2>/dev/null
            ;;
    esac
}

# Check if building a tag
# Usage: ci::is_tag && echo "Tag build"
ci::is_tag() {
    local tag
    tag=$(ci::tag)
    [[ -n "$tag" ]]
}

# =============================================================================
# CI ENVIRONMENT INFO
# =============================================================================

# Get CI runner/worker info
# Usage: runner=$(ci::runner)
ci::runner() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${RUNNER_NAME:-${RUNNER_OS:-unknown}}"
            ;;
        gitlab)
            printf '%s\n' "${CI_RUNNER_DESCRIPTION:-${CI_RUNNER_ID:-unknown}}"
            ;;
        jenkins)
            printf '%s\n' "${NODE_NAME:-unknown}"
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_NODE_INDEX:-0}/${CIRCLE_NODE_TOTAL:-1}"
            ;;
        azure)
            printf '%s\n' "${AGENT_NAME:-unknown}"
            ;;
        *)
            printf 'local\n'
            ;;
    esac
}

# Get job/build number
# Usage: build=$(ci::build_number)
ci::build_number() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${GITHUB_RUN_NUMBER:-}"
            ;;
        gitlab)
            printf '%s\n' "${CI_PIPELINE_IID:-${CI_JOB_ID:-}}"
            ;;
        jenkins)
            printf '%s\n' "${BUILD_NUMBER:-}"
            ;;
        circleci)
            printf '%s\n' "${CIRCLE_BUILD_NUM:-}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_BUILD_NUMBER:-}"
            ;;
        azure)
            printf '%s\n' "${BUILD_BUILDNUMBER:-}"
            ;;
    esac
}

# Get repository name
# Usage: repo=$(ci::repository)
ci::repository() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s\n' "${GITHUB_REPOSITORY:-}"
            ;;
        gitlab)
            printf '%s\n' "${CI_PROJECT_PATH:-}"
            ;;
        jenkins)
            # Jenkins doesn't have a standard var, try to extract from git
            git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/]+)\.git$|\1|'
            ;;
        circleci)
            printf '%s/%s\n' "${CIRCLE_PROJECT_USERNAME:-}" "${CIRCLE_PROJECT_REPONAME:-}"
            ;;
        travis)
            printf '%s\n' "${TRAVIS_REPO_SLUG:-}"
            ;;
        azure)
            printf '%s\n' "${BUILD_REPOSITORY_NAME:-}"
            ;;
        *)
            git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/]+)\.git$|\1|'
            ;;
    esac
}

# =============================================================================
# MASKING / SECRETS
# =============================================================================

# Mask a value in CI logs
# Usage: ci::mask_value "secret"
ci::mask_value() {
    local value="$1"

    [[ -z "$value" ]] && return 0

    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '::add-mask::%s\n' "$value"
            ;;
        azure)
            printf '##vso[task.setvariable variable=masked;issecret=true]%s\n' "$value"
            ;;
        gitlab)
            # GitLab CI masks variables defined as masked in settings
            # No runtime masking command, but we can warn
            printf '\e[33mNote: Value should be masked in CI/CD settings\e[0m\n' >&2
            ;;
        *)
            # No masking available
            :
            ;;
    esac
}

# =============================================================================
# CACHING HELPERS
# =============================================================================

# Get cache key prefix (useful for constructing cache keys)
# Usage: key=$(ci::cache_key_prefix)
ci::cache_key_prefix() {
    local platform
    platform=$(_ci_detect_platform)

    case "$platform" in
        github)
            printf '%s-%s\n' "${RUNNER_OS:-Linux}" "${GITHUB_JOB:-job}"
            ;;
        gitlab)
            printf '%s-%s\n' "${CI_RUNNER_EXECUTABLE_ARCH:-linux}" "${CI_JOB_NAME:-job}"
            ;;
        circleci)
            printf '%s-%s\n' "${CIRCLE_JOB:-job}" "v1"
            ;;
        azure)
            printf '%s-%s\n' "${AGENT_OS:-Linux}" "${SYSTEM_JOBNAME:-job}"
            ;;
        *)
            printf 'local-%s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')"
            ;;
    esac
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# shellcheck disable=SC2034  # MAINFRAME_CI_EXPORTS is used by mainframe loader
MAINFRAME_CI_EXPORTS=(
    # Universal Detection (underscore style)
    ci_is_ci
    ci_platform
    ci_info
    # Individual Platform Detectors
    ci_is_github_actions
    ci_is_gitlab_ci
    ci_is_jenkins
    ci_is_buildkite
    ci_is_bitbucket
    ci_is_teamcity
    ci_is_circleci
    ci_is_travis
    ci_is_appveyor
    ci_is_azure_pipelines
    ci_is_aws_codebuild
    ci_is_gcp_cloud_build
    ci_is_drone
    ci_is_semaphore
    ci_is_buddy
    ci_is_woodpecker
    ci_is_gitea_actions
    # Legacy Detection (namespaced style)
    ci::is_ci
    ci::detect
    ci::name
    # Output
    ci::set_output
    ci::set_env
    ci::add_path
    ci::group_start
    ci::group_end
    # Logging
    ci::warning
    ci::error
    ci::notice
    ci::debug
    # Artifacts
    ci::artifact_checksum
    ci::artifact_create
    # PR/MR Info
    ci::is_pull_request
    ci::pr_number
    ci::pr_branch
    ci::pr_target
    # Git Info
    ci::commit_sha
    ci::commit_short
    ci::branch
    ci::tag
    ci::is_tag
    # CI Environment
    ci::runner
    ci::build_number
    ci::repository
    # Secrets
    ci::mask_value
    # Caching
    ci::cache_key_prefix
)

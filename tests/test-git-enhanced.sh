#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/tests/test-git-enhanced.sh - Tests for Enhanced Git Functions
# =============================================================================
# Description: Tests for Quick Win #3 Git helper functions
# Usage: ./tests/test-git-enhanced.sh
# =============================================================================

# Get script directory and source MAINFRAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${SCRIPT_DIR}/.."

# Source MAINFRAME
source "${MAINFRAME_ROOT}/lib/common.sh"

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_pass() {
    ((TESTS_PASSED++))
    printf "${GREEN}  [PASS]${NC} %s\n" "$1"
}

test_fail() {
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
    printf "${RED}  [FAIL]${NC} %s\n" "$1"
    [[ -n "${2:-}" ]] && printf "         Expected: %s\n" "$2"
    [[ -n "${3:-}" ]] && printf "         Got:      %s\n" "$3"
}

test_skip() {
    printf "${YELLOW}  [SKIP]${NC} %s\n" "$1"
}

section() {
    printf "\n${BLUE}=== %s ===${NC}\n" "$1"
}

# =============================================================================
# SETUP - Create test repository
# =============================================================================

setup_test_repo() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR" || exit 1

    git init --initial-branch=main >/dev/null 2>&1 || \
        git init >/dev/null 2>&1

    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create initial commit
    echo "# Test Repo" > README.md
    git add README.md
    git commit -m "Initial commit" >/dev/null 2>&1

    # Add a remote (fake, but valid URL structure)
    git remote add origin "https://github.com/testowner/testrepo.git"

    # Set upstream (symbolic, won't actually track)
    git config branch.main.remote origin
    git config branch.main.merge refs/heads/main

    printf "${GREEN}Test repository created at: %s${NC}\n" "$TEST_DIR"
}

cleanup_test_repo() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        printf "${GREEN}Test repository cleaned up${NC}\n"
    fi
}

# =============================================================================
# TESTS - Existing Functions (Sanity Check)
# =============================================================================

test_existing_functions() {
    section "Existing Functions (Sanity Check)"

    ((TESTS_RUN++))
    if git_is_repo; then
        test_pass "git_is_repo - detects repository"
    else
        test_fail "git_is_repo - should detect repository"
    fi

    ((TESTS_RUN++))
    local branch
    branch=$(git_branch)
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
        test_pass "git_branch - returns current branch: $branch"
    else
        test_fail "git_branch - unexpected branch" "main or master" "$branch"
    fi

    ((TESTS_RUN++))
    local hash
    hash=$(git_commit_hash)
    if [[ ${#hash} -ge 7 ]]; then
        test_pass "git_commit_hash - returns short hash: $hash"
    else
        test_fail "git_commit_hash - hash too short" "7+ chars" "$hash"
    fi
}

# =============================================================================
# TESTS - New Repository Info Functions
# =============================================================================

test_git_repo_name() {
    section "git_repo_name"

    ((TESTS_RUN++))
    local name
    name=$(git_repo_name)
    if [[ "$name" == "testrepo" ]]; then
        test_pass "git_repo_name - extracts repo name from HTTPS URL"
    else
        test_fail "git_repo_name - wrong name" "testrepo" "$name"
    fi

    # Test with SSH URL
    ((TESTS_RUN++))
    git remote set-url origin "git@github.com:anotherowner/sshrepo.git"
    name=$(git_repo_name)
    if [[ "$name" == "sshrepo" ]]; then
        test_pass "git_repo_name - extracts repo name from SSH URL"
    else
        test_fail "git_repo_name - wrong name for SSH" "sshrepo" "$name"
    fi

    # Reset to HTTPS
    git remote set-url origin "https://github.com/testowner/testrepo.git"
}

test_git_repo_url() {
    section "git_repo_url"

    ((TESTS_RUN++))
    local url
    url=$(git_repo_url)
    if [[ "$url" == "https://github.com/testowner/testrepo.git" ]]; then
        test_pass "git_repo_url - returns origin URL"
    else
        test_fail "git_repo_url - wrong URL" "https://github.com/testowner/testrepo.git" "$url"
    fi

    # Add another remote and test
    ((TESTS_RUN++))
    git remote add upstream "https://github.com/upstream/project.git" 2>/dev/null || true
    url=$(git_repo_url upstream)
    if [[ "$url" == "https://github.com/upstream/project.git" ]]; then
        test_pass "git_repo_url - returns specified remote URL"
    else
        test_fail "git_repo_url - wrong URL for upstream" "https://github.com/upstream/project.git" "$url"
    fi
}

test_git_provider() {
    section "git_provider"

    ((TESTS_RUN++))
    local provider
    provider=$(git_provider)
    if [[ "$provider" == "github" ]]; then
        test_pass "git_provider - detects GitHub"
    else
        test_fail "git_provider - should detect GitHub" "github" "$provider"
    fi

    # Test GitLab
    ((TESTS_RUN++))
    git remote set-url origin "https://gitlab.com/user/repo.git"
    provider=$(git_provider)
    if [[ "$provider" == "gitlab" ]]; then
        test_pass "git_provider - detects GitLab"
    else
        test_fail "git_provider - should detect GitLab" "gitlab" "$provider"
    fi

    # Test Bitbucket
    ((TESTS_RUN++))
    git remote set-url origin "git@bitbucket.org:user/repo.git"
    provider=$(git_provider)
    if [[ "$provider" == "bitbucket" ]]; then
        test_pass "git_provider - detects Bitbucket"
    else
        test_fail "git_provider - should detect Bitbucket" "bitbucket" "$provider"
    fi

    # Test Azure DevOps
    ((TESTS_RUN++))
    git remote set-url origin "https://dev.azure.com/org/project/_git/repo"
    provider=$(git_provider)
    if [[ "$provider" == "azure" ]]; then
        test_pass "git_provider - detects Azure DevOps"
    else
        test_fail "git_provider - should detect Azure" "azure" "$provider"
    fi

    # Test Codeberg
    ((TESTS_RUN++))
    git remote set-url origin "https://codeberg.org/user/repo.git"
    provider=$(git_provider)
    if [[ "$provider" == "codeberg" ]]; then
        test_pass "git_provider - detects Codeberg"
    else
        test_fail "git_provider - should detect Codeberg" "codeberg" "$provider"
    fi

    # Test unknown
    ((TESTS_RUN++))
    git remote set-url origin "https://internal.company.com/repo.git"
    provider=$(git_provider)
    if [[ "$provider" == "unknown" ]]; then
        test_pass "git_provider - returns unknown for unrecognized hosts"
    else
        test_fail "git_provider - should return unknown" "unknown" "$provider"
    fi

    # Reset
    git remote set-url origin "https://github.com/testowner/testrepo.git"
}

test_git_repo_owner() {
    section "git_repo_owner"

    ((TESTS_RUN++))
    local owner
    owner=$(git_repo_owner)
    if [[ "$owner" == "testowner" ]]; then
        test_pass "git_repo_owner - extracts owner from HTTPS URL"
    else
        test_fail "git_repo_owner - wrong owner" "testowner" "$owner"
    fi

    # Test SSH URL
    ((TESTS_RUN++))
    git remote set-url origin "git@github.com:sshowner/repo.git"
    owner=$(git_repo_owner)
    if [[ "$owner" == "sshowner" ]]; then
        test_pass "git_repo_owner - extracts owner from SSH URL"
    else
        test_fail "git_repo_owner - wrong owner for SSH" "sshowner" "$owner"
    fi

    # Reset
    git remote set-url origin "https://github.com/testowner/testrepo.git"
}

test_git_web_url() {
    section "git_web_url"

    ((TESTS_RUN++))
    local web_url
    web_url=$(git_web_url)
    if [[ "$web_url" == "https://github.com/testowner/testrepo" ]]; then
        test_pass "git_web_url - generates GitHub web URL"
    else
        test_fail "git_web_url - wrong web URL" "https://github.com/testowner/testrepo" "$web_url"
    fi

    # Test GitLab
    ((TESTS_RUN++))
    git remote set-url origin "git@gitlab.com:gluser/glrepo.git"
    web_url=$(git_web_url)
    if [[ "$web_url" == "https://gitlab.com/gluser/glrepo" ]]; then
        test_pass "git_web_url - generates GitLab web URL from SSH"
    else
        test_fail "git_web_url - wrong web URL for GitLab" "https://gitlab.com/gluser/glrepo" "$web_url"
    fi

    # Reset
    git remote set-url origin "https://github.com/testowner/testrepo.git"
}

test_git_upstream_branch() {
    section "git_upstream_branch"

    ((TESTS_RUN++))
    local upstream
    upstream=$(git_upstream_branch 2>/dev/null)
    # May fail if not properly configured, that's expected
    if [[ -n "$upstream" ]]; then
        test_pass "git_upstream_branch - returns tracking branch: $upstream"
    else
        test_skip "git_upstream_branch - no upstream configured (expected)"
    fi
}

test_git_remotes_json() {
    section "git_remotes_json"

    ((TESTS_RUN++))
    local json
    json=$(git_remotes_json)
    if [[ "$json" == "["*"]" ]]; then
        test_pass "git_remotes_json - returns JSON array"
    else
        test_fail "git_remotes_json - should return JSON array" "[...]" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"name":"origin"'* ]]; then
        test_pass "git_remotes_json - contains origin remote"
    else
        test_fail "git_remotes_json - should contain origin" "contains origin" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"fetch_url":'* ]]; then
        test_pass "git_remotes_json - contains fetch_url field"
    else
        test_fail "git_remotes_json - should contain fetch_url" "contains fetch_url" "$json"
    fi
}

# =============================================================================
# TESTS - Changed Files
# =============================================================================

test_git_changed_files() {
    section "git_changed_files"

    # Create some changes
    echo "modified" >> README.md
    echo "new file" > newfile.txt
    git add newfile.txt
    echo "untracked" > untracked.txt

    ((TESTS_RUN++))
    local staged
    staged=$(git_changed_files staged)
    if [[ "$staged" == *"newfile.txt"* ]]; then
        test_pass "git_changed_files staged - shows staged files"
    else
        test_fail "git_changed_files staged - should show newfile.txt" "newfile.txt" "$staged"
    fi

    ((TESTS_RUN++))
    local unstaged
    unstaged=$(git_changed_files unstaged)
    if [[ "$unstaged" == *"README.md"* ]]; then
        test_pass "git_changed_files unstaged - shows modified files"
    else
        test_fail "git_changed_files unstaged - should show README.md" "README.md" "$unstaged"
    fi

    ((TESTS_RUN++))
    local untracked
    untracked=$(git_changed_files untracked)
    if [[ "$untracked" == *"untracked.txt"* ]]; then
        test_pass "git_changed_files untracked - shows untracked files"
    else
        test_fail "git_changed_files untracked - should show untracked.txt" "untracked.txt" "$untracked"
    fi

    ((TESTS_RUN++))
    local all
    all=$(git_changed_files all)
    if [[ "$all" == *"README.md"* && "$all" == *"newfile.txt"* && "$all" == *"untracked.txt"* ]]; then
        test_pass "git_changed_files all - shows all changed files"
    else
        test_fail "git_changed_files all - should show all files" "all three files" "$all"
    fi

    # Cleanup
    git checkout README.md 2>/dev/null || true
    git reset HEAD newfile.txt 2>/dev/null || true
    rm -f newfile.txt untracked.txt
}

# =============================================================================
# TESTS - Commit Info
# =============================================================================

test_git_last_commit() {
    section "git_last_commit"

    ((TESTS_RUN++))
    local json
    json=$(git_last_commit)
    if [[ "$json" == "{"*"}" ]]; then
        test_pass "git_last_commit - returns JSON object"
    else
        test_fail "git_last_commit - should return JSON object" "{...}" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"hash":'* ]]; then
        test_pass "git_last_commit - contains hash field"
    else
        test_fail "git_last_commit - should contain hash" "contains hash" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"author":"Test User"'* ]]; then
        test_pass "git_last_commit - contains correct author"
    else
        test_fail "git_last_commit - should contain author" "Test User" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"message":"Initial commit"'* ]]; then
        test_pass "git_last_commit - contains commit message"
    else
        test_fail "git_last_commit - should contain message" "Initial commit" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"date":'* ]]; then
        test_pass "git_last_commit - contains date field"
    else
        test_fail "git_last_commit - should contain date" "contains date" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"email":"test@example.com"'* ]]; then
        test_pass "git_last_commit - contains email field"
    else
        test_fail "git_last_commit - should contain email" "test@example.com" "$json"
    fi
}

# =============================================================================
# TESTS - Summary JSON
# =============================================================================

test_git_summary_json() {
    section "git_summary_json"

    ((TESTS_RUN++))
    local json
    json=$(git_summary_json)
    if [[ "$json" == "{"*"}" ]]; then
        test_pass "git_summary_json - returns JSON object"
    else
        test_fail "git_summary_json - should return JSON object" "{...}" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"branch":'* ]]; then
        test_pass "git_summary_json - contains branch field"
    else
        test_fail "git_summary_json - should contain branch" "contains branch" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"is_dirty":false'* ]]; then
        test_pass "git_summary_json - clean repo shows is_dirty:false"
    else
        test_fail "git_summary_json - clean repo should show is_dirty:false" "is_dirty:false" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"provider":"github"'* ]]; then
        test_pass "git_summary_json - contains provider"
    else
        test_fail "git_summary_json - should contain provider" "github" "$json"
    fi

    ((TESTS_RUN++))
    if [[ "$json" == *'"commit_count":'* ]]; then
        test_pass "git_summary_json - contains commit_count"
    else
        test_fail "git_summary_json - should contain commit_count" "contains commit_count" "$json"
    fi

    # Make repo dirty and test
    ((TESTS_RUN++))
    echo "dirty" >> README.md
    json=$(git_summary_json)
    if [[ "$json" == *'"is_dirty":true'* ]]; then
        test_pass "git_summary_json - dirty repo shows is_dirty:true"
    else
        test_fail "git_summary_json - dirty repo should show is_dirty:true" "is_dirty:true" "$json"
    fi

    # Cleanup
    git checkout README.md 2>/dev/null || true
}

# =============================================================================
# TESTS - Edge Cases
# =============================================================================

test_edge_cases() {
    section "Edge Cases"

    # Test outside git repo
    ((TESTS_RUN++))
    local outside_result
    outside_result=$(cd /tmp && git_repo_name 2>&1) || true
    if [[ -z "$outside_result" || "$outside_result" == *"fatal"* ]]; then
        test_pass "git_repo_name - fails gracefully outside repo"
    else
        test_fail "git_repo_name - should fail outside repo" "empty or error" "$outside_result"
    fi

    # Test with no remote
    ((TESTS_RUN++))
    local no_remote_dir
    no_remote_dir=$(mktemp -d)
    (
        cd "$no_remote_dir" || exit
        git init --initial-branch=main >/dev/null 2>&1 || git init >/dev/null 2>&1
        git config user.email "test@test.com"
        git config user.name "Test"
        echo "test" > test.txt
        git add test.txt
        git commit -m "test" >/dev/null 2>&1

        local provider
        provider=$(git_provider 2>/dev/null) || provider="unknown"
        if [[ "$provider" == "unknown" ]]; then
            echo "PASS"
        else
            echo "FAIL"
        fi
    )
    local result
    result=$(cd "$no_remote_dir" && git_provider 2>/dev/null) || result="unknown"
    if [[ "$result" == "unknown" ]]; then
        test_pass "git_provider - returns unknown when no remote"
    else
        test_fail "git_provider - should return unknown" "unknown" "$result"
    fi
    rm -rf "$no_remote_dir"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    printf "${BLUE}============================================${NC}\n"
    printf "${BLUE}MAINFRAME Git Enhanced Functions Test Suite${NC}\n"
    printf "${BLUE}============================================${NC}\n"

    # Setup
    setup_test_repo

    # Run tests
    test_existing_functions
    test_git_repo_name
    test_git_repo_url
    test_git_provider
    test_git_repo_owner
    test_git_web_url
    test_git_upstream_branch
    test_git_remotes_json
    test_git_changed_files
    test_git_last_commit
    test_git_summary_json
    test_edge_cases

    # Cleanup
    cleanup_test_repo

    # Summary
    printf "\n${BLUE}============================================${NC}\n"
    printf "${BLUE}TEST SUMMARY${NC}\n"
    printf "${BLUE}============================================${NC}\n"
    printf "Tests Run:    %d\n" "$TESTS_RUN"
    printf "${GREEN}Tests Passed: %d${NC}\n" "$TESTS_PASSED"
    printf "${RED}Tests Failed: %d${NC}\n" "$TESTS_FAILED"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        printf "\n${RED}Failed Tests:${NC}\n"
        for test in "${FAILED_TESTS[@]}"; do
            printf "  - %s\n" "$test"
        done
    fi

    printf "\n"
    if [[ $TESTS_FAILED -eq 0 ]]; then
        printf "${GREEN}All tests passed!${NC}\n"
        return 0
    else
        printf "${RED}Some tests failed.${NC}\n"
        return 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

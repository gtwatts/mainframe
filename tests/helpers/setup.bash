#!/usr/bin/env bash
# =============================================================================
# tests/helpers/setup.bash - Common test setup functions
# =============================================================================

# Get the test directory
_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_PROJECT_ROOT="$(cd "$_TESTS_DIR/.." && pwd)"

# Load BATS helpers
load "${_TESTS_DIR}/bats-support/load"
load "${_TESTS_DIR}/bats-assert/load"
load "${_TESTS_DIR}/bats-file/load"

# Export paths for scripts under test
export PATH="${_PROJECT_ROOT}/scripts/data:$PATH"
export PATH="${_PROJECT_ROOT}/scripts/agent:$PATH"
export PATH="${_PROJECT_ROOT}/scripts/git:$PATH"
export PATH="${_PROJECT_ROOT}/scripts/file:$PATH"
export PATH="${_PROJECT_ROOT}/scripts/api:$PATH"
export PATH="${_PROJECT_ROOT}/scripts/dev:$PATH"
export PATH="${_PROJECT_ROOT}:$PATH"

# Export basher root
export BASHER_ROOT="$_PROJECT_ROOT"

# Source libraries for testing
export BASHER_CONFIG_AUTOLOAD=false
source "${_PROJECT_ROOT}/lib/common.sh"

# =============================================================================
# COMMON SETUP/TEARDOWN
# =============================================================================

# Common setup - call from setup() in test files
common_setup() {
    # Create temp directory for this test run
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_FIXTURE_DIR="${_TESTS_DIR}/fixtures"

    # Disable colors in tests
    export NO_COLOR=1

    # Set log level to error only for cleaner output
    export BASHER_LOG_LEVEL=3
}

# Common teardown - call from teardown() in test files
common_teardown() {
    # Clean up temp directory
    if [[ -d "${TEST_TEMP_DIR:-}" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# =============================================================================
# TEMP FILE MANAGEMENT
# =============================================================================

# Create a temporary directory
temp_make() {
    local name="${1:-test}"
    local dir
    dir=$(mktemp -d "${TEST_TEMP_DIR}/${name}.XXXXXX")
    printf '%s' "$dir"
}

# Delete a temporary directory
temp_del() {
    local dir="$1"
    [[ -d "$dir" ]] && rm -rf "$dir"
}

# Create a temporary file with content
temp_file() {
    local content="${1:-}"
    local ext="${2:-.txt}"
    local file
    file=$(mktemp "${TEST_TEMP_DIR}/file.XXXXXX${ext}")

    if [[ -n "$content" ]]; then
        printf '%s' "$content" > "$file"
    fi

    printf '%s' "$file"
}

# =============================================================================
# FIXTURE HELPERS
# =============================================================================

# Get fixture path
fixture() {
    local category="$1"
    local name="$2"

    local path="${TEST_FIXTURE_DIR}/${category}/${name}"
    if [[ ! -f "$path" ]]; then
        echo "Fixture not found: $path" >&2
        return 1
    fi

    printf '%s' "$path"
}

# Copy fixture to temp directory
fixture_copy() {
    local category="$1"
    local name="$2"
    local dest="${3:-$TEST_TEMP_DIR}"

    local src
    src=$(fixture "$category" "$name")

    cp "$src" "$dest/"
    printf '%s' "${dest}/${name}"
}

# Load fixture content
fixture_content() {
    local category="$1"
    local name="$2"

    cat "$(fixture "$category" "$name")"
}

# =============================================================================
# OUTPUT HELPERS
# =============================================================================

# Print test info (for debugging)
debug_output() {
    printf "Status: %s\n" "$status"
    printf "Output:\n%s\n" "$output"
    printf "Lines: %d\n" "${#lines[@]}"
}

# Get specific line of output
output_line() {
    local n="$1"
    printf '%s' "${lines[$n]}"
}

# =============================================================================
# ENVIRONMENT HELPERS
# =============================================================================

# Run command with specific environment
with_env() {
    local -a env_vars=()
    while [[ "$1" == *=* ]]; do
        env_vars+=("$1")
        shift
    done
    env "${env_vars[@]}" "$@"
}

# Run command in specific directory
in_dir() {
    local dir="$1"
    shift
    (cd "$dir" && "$@")
}

# =============================================================================
# GIT HELPERS (for git script tests)
# =============================================================================

# Create a temporary git repository
git_repo_create() {
    local dir
    dir=$(temp_make "git-repo")

    (
        cd "$dir"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
    ) >/dev/null 2>&1

    printf '%s' "$dir"
}

# Add and commit a file
git_commit_file() {
    local repo="$1"
    local file="$2"
    local content="${3:-test content}"
    local message="${4:-Test commit}"

    (
        cd "$repo"
        printf '%s' "$content" > "$file"
        git add "$file"
        git commit -m "$message"
    ) >/dev/null 2>&1
}

# =============================================================================
# JSON HELPERS
# =============================================================================

# Compare JSON (ignoring formatting)
json_equal() {
    local json1="$1"
    local json2="$2"

    local sorted1 sorted2
    sorted1=$(jq -S '.' <<< "$json1")
    sorted2=$(jq -S '.' <<< "$json2")

    [[ "$sorted1" == "$sorted2" ]]
}

# Extract JSON value
json_get() {
    local json="$1"
    local path="$2"

    jq -r "$path" <<< "$json"
}

# =============================================================================
# TIMING HELPERS
# =============================================================================

# Skip test if running in CI with time constraints
skip_if_slow() {
    if [[ "${CI:-}" == "true" && "${FAST_TESTS:-}" == "true" ]]; then
        skip "Skipping slow test in fast mode"
    fi
}

# Skip test if required command is missing
skip_if_missing() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        skip "Required command not found: $cmd"
    fi
}

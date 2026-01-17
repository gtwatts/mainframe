#!/usr/bin/env bash
# =============================================================================
# MAINFRAME Test Helper
# =============================================================================
# Common setup and utilities for BATS tests
# =============================================================================

# Get MAINFRAME root directory
export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/.."

# Source all libraries
source_all_libs() {
    source "$MAINFRAME_ROOT/lib/common.sh"
}

# Source specific library
source_lib() {
    local lib="$1"
    source "$MAINFRAME_ROOT/lib/${lib}.sh"
}

# Assert equality
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'FAIL: %s\nString: %s\nShould contain: %s\n' "$message" "$haystack" "$needle" >&2
        return 1
    fi
}

# Assert starts with
assert_starts_with() {
    local string="$1"
    local prefix="$2"
    local message="${3:-String should start with prefix}"

    if [[ "$string" != "$prefix"* ]]; then
        printf 'FAIL: %s\nString: %s\nShould start with: %s\n' "$message" "$string" "$prefix" >&2
        return 1
    fi
}

# Assert ends with
assert_ends_with() {
    local string="$1"
    local suffix="$2"
    local message="${3:-String should end with suffix}"

    if [[ "$string" != *"$suffix" ]]; then
        printf 'FAIL: %s\nString: %s\nShould end with: %s\n' "$message" "$string" "$suffix" >&2
        return 1
    fi
}

# Assert matches regex
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"

    if [[ ! "$string" =~ $pattern ]]; then
        printf 'FAIL: %s\nString: %s\nShould match: %s\n' "$message" "$string" "$pattern" >&2
        return 1
    fi
}

# Assert command succeeds
assert_success() {
    local cmd="$1"
    local message="${2:-Command should succeed}"

    if ! eval "$cmd" >/dev/null 2>&1; then
        printf 'FAIL: %s\nCommand: %s\n' "$message" "$cmd" >&2
        return 1
    fi
}

# Assert command fails
assert_failure() {
    local cmd="$1"
    local message="${2:-Command should fail}"

    if eval "$cmd" >/dev/null 2>&1; then
        printf 'FAIL: %s\nCommand: %s\n' "$message" "$cmd" >&2
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    if [[ ! -f "$file" ]]; then
        printf 'FAIL: %s\nFile: %s\n' "$message" "$file" >&2
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"

    if [[ ! -d "$dir" ]]; then
        printf 'FAIL: %s\nDirectory: %s\n' "$message" "$dir" >&2
        return 1
    fi
}

# Assert numeric comparison
assert_gt() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Value should be greater than}"

    if [[ ! "$actual" -gt "$expected" ]]; then
        printf 'FAIL: %s\nActual: %s\nExpected greater than: %s\n' "$message" "$actual" "$expected" >&2
        return 1
    fi
}

assert_lt() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Value should be less than}"

    if [[ ! "$actual" -lt "$expected" ]]; then
        printf 'FAIL: %s\nActual: %s\nExpected less than: %s\n' "$message" "$actual" "$expected" >&2
        return 1
    fi
}

# Create temporary test directory
create_test_dir() {
    local name="${1:-test}"
    mktemp -d "/tmp/mainframe-${name}.XXXXXX"
}

# Clean up test directory
cleanup_test_dir() {
    local dir="$1"
    [[ -d "$dir" ]] && rm -rf "$dir"
}

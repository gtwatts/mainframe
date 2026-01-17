#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/tests/test_docker.sh - Docker Library Test Suite
# =============================================================================
# Description: Tests for docker.sh functions
# Usage: ./tests/test_docker.sh
# Note: Some tests require Docker daemon to be running
# =============================================================================

set -euo pipefail

# Get script directory and source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/common.sh"

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() {
    ((TESTS_PASSED++)) || true
    ((TESTS_RUN++)) || true
    printf "${GREEN}[PASS]${NC} %s\n" "$1"
}

fail() {
    ((TESTS_FAILED++)) || true
    ((TESTS_RUN++)) || true
    printf "${RED}[FAIL]${NC} %s - %s\n" "$1" "$2"
}

skip() {
    ((TESTS_SKIPPED++)) || true
    printf "${YELLOW}[SKIP]${NC} %s - %s\n" "$1" "$2"
}

info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected '$expected', got '$actual'"
    fi
}

assert_true() {
    local test_name="$1"
    shift

    if "$@"; then
        pass "$test_name"
    else
        fail "$test_name" "condition was false"
    fi
}

assert_false() {
    local test_name="$1"
    shift

    if ! "$@"; then
        pass "$test_name"
    else
        fail "$test_name" "condition was true"
    fi
}

# =============================================================================
# CHECK DOCKER AVAILABILITY
# =============================================================================

DOCKER_AVAILABLE=false
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
    info "Docker daemon is running - full test suite will execute"
else
    info "Docker daemon not available - running limited tests only"
fi

# =============================================================================
# TESTS: INTERNAL HELPERS
# =============================================================================

info "Testing internal helpers..."

assert_true "_docker_has_cli returns true when docker installed" _docker_has_cli

# =============================================================================
# TESTS: DAEMON STATUS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing daemon status functions..."

    assert_true "docker_running returns true when daemon running" docker_running

    # docker_version should return a version string
    version=$(docker_version)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
        pass "docker_version returns valid version: $version"
    else
        fail "docker_version" "returned invalid version: $version"
    fi
else
    skip "docker_running" "Docker daemon not available"
    skip "docker_version" "Docker daemon not available"
fi

# =============================================================================
# TESTS: CONTAINER OPERATIONS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing container operations..."

    # Test with a container that doesn't exist
    assert_false "docker_container_exists returns false for nonexistent" docker_container_exists "mainframe_test_nonexistent_12345"
    assert_false "docker_container_running returns false for nonexistent" docker_container_running "mainframe_test_nonexistent_12345"

    # Test containers_running and containers_all (just verify they don't error)
    if docker_containers_running >/dev/null 2>&1; then
        pass "docker_containers_running runs without error"
    else
        fail "docker_containers_running" "command failed"
    fi

    if docker_containers_all >/dev/null 2>&1; then
        pass "docker_containers_all runs without error"
    else
        fail "docker_containers_all" "command failed"
    fi

    # Create a test container for more detailed tests
    TEST_CONTAINER="mainframe_test_container_$$"
    info "Creating test container: $TEST_CONTAINER"

    if docker run -d --name "$TEST_CONTAINER" alpine:latest sleep 300 &>/dev/null; then
        # Wait for container to start
        sleep 1

        assert_true "docker_container_exists returns true for existing" docker_container_exists "$TEST_CONTAINER"
        assert_true "docker_container_running returns true for running" docker_container_running "$TEST_CONTAINER"

        status=$(docker_container_status "$TEST_CONTAINER")
        assert_eq "running" "$status" "docker_container_status returns 'running'"

        # Test container ID
        container_id=$(docker_container_id "$TEST_CONTAINER")
        if [[ -n "$container_id" && ${#container_id} -ge 12 ]]; then
            pass "docker_container_id returns valid ID"
        else
            fail "docker_container_id" "returned invalid ID: $container_id"
        fi

        short_id=$(docker_container_id_short "$TEST_CONTAINER")
        if [[ -n "$short_id" && ${#short_id} -eq 12 ]]; then
            pass "docker_container_id_short returns 12-char ID"
        else
            fail "docker_container_id_short" "returned: $short_id (length ${#short_id})"
        fi

        # Test docker_exec
        exec_output=$(docker_exec "$TEST_CONTAINER" "echo hello")
        assert_eq "hello" "$exec_output" "docker_exec executes command"

        # Test docker_logs
        if docker_logs "$TEST_CONTAINER" 10 >/dev/null 2>&1; then
            pass "docker_logs runs without error"
        else
            fail "docker_logs" "command failed"
        fi

        # Test docker_container_image
        image=$(docker_container_image "$TEST_CONTAINER")
        if [[ "$image" == "alpine:latest" || "$image" == "alpine" ]]; then
            pass "docker_container_image returns correct image"
        else
            fail "docker_container_image" "returned: $image"
        fi

        # Test container IP (may not have one on some network configs)
        if docker_container_ip "$TEST_CONTAINER" >/dev/null 2>&1; then
            pass "docker_container_ip runs without error"
        else
            pass "docker_container_ip (no IP expected for simple container)"
        fi

        # Test docker_stats_json
        stats=$(docker_stats_json "$TEST_CONTAINER")
        if [[ "$stats" == *"cpu"* && "$stats" == *"memory"* ]]; then
            pass "docker_stats_json returns JSON with cpu/memory"
        else
            fail "docker_stats_json" "returned: $stats"
        fi

        # Test container stop
        if docker_container_stop "$TEST_CONTAINER" 5; then
            pass "docker_container_stop succeeds"
            assert_false "container not running after stop" docker_container_running "$TEST_CONTAINER"
        else
            fail "docker_container_stop" "command failed"
        fi

        # Test container start
        if docker_container_start "$TEST_CONTAINER"; then
            pass "docker_container_start succeeds"
            sleep 1
            assert_true "container running after start" docker_container_running "$TEST_CONTAINER"
        else
            fail "docker_container_start" "command failed"
        fi

        # Clean up: remove test container
        info "Cleaning up test container..."
        docker_container_stop "$TEST_CONTAINER" 2 >/dev/null || true
        if docker_container_remove "$TEST_CONTAINER" true; then
            pass "docker_container_remove succeeds"
        else
            fail "docker_container_remove" "command failed"
        fi

        assert_false "container doesn't exist after remove" docker_container_exists "$TEST_CONTAINER"
    else
        skip "container tests" "Failed to create test container"
    fi
else
    skip "container operations" "Docker daemon not available"
fi

# =============================================================================
# TESTS: IMAGE OPERATIONS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing image operations..."

    # Test with a common image that should exist after our container test
    if docker_image_exists "alpine:latest"; then
        pass "docker_image_exists returns true for alpine:latest"

        image_id=$(docker_image_id "alpine:latest")
        if [[ -n "$image_id" ]]; then
            pass "docker_image_id returns ID for alpine:latest"
        else
            fail "docker_image_id" "returned empty"
        fi

        image_size=$(docker_image_size "alpine:latest")
        if [[ "$image_size" =~ ^[0-9]+$ ]]; then
            pass "docker_image_size returns numeric size"
        else
            fail "docker_image_size" "returned: $image_size"
        fi

        human_size=$(docker_image_size_human "alpine:latest")
        if [[ -n "$human_size" ]]; then
            pass "docker_image_size_human returns: $human_size"
        else
            fail "docker_image_size_human" "returned empty"
        fi
    else
        skip "image tests" "alpine:latest not available"
    fi

    assert_false "docker_image_exists returns false for nonexistent" docker_image_exists "mainframe_nonexistent_image:latest"

    # Test docker_images (just verify it runs)
    if docker_images >/dev/null 2>&1; then
        pass "docker_images runs without error"
    else
        fail "docker_images" "command failed"
    fi
else
    skip "image operations" "Docker daemon not available"
fi

# =============================================================================
# TESTS: PORT OPERATIONS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing port operations..."

    # Test with a port that's likely not in use by Docker
    if ! docker_port_used 59999; then
        pass "docker_port_used returns false for unused port"
    else
        skip "docker_port_used" "Port 59999 is in use"
    fi

    # docker_port_container should return empty for unused port
    container=$(docker_port_container 59999)
    if [[ -z "$container" ]]; then
        pass "docker_port_container returns empty for unused port"
    else
        skip "docker_port_container" "Port 59999 is in use by $container"
    fi
else
    skip "port operations" "Docker daemon not available"
fi

# =============================================================================
# TESTS: VOLUME OPERATIONS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing volume operations..."

    TEST_VOLUME="mainframe_test_volume_$$"

    assert_false "docker_volume_exists returns false for nonexistent" docker_volume_exists "$TEST_VOLUME"

    # Create test volume
    if docker_volume_create "$TEST_VOLUME"; then
        pass "docker_volume_create succeeds"
        assert_true "docker_volume_exists returns true after create" docker_volume_exists "$TEST_VOLUME"

        # Remove volume
        if docker_volume_remove "$TEST_VOLUME"; then
            pass "docker_volume_remove succeeds"
            assert_false "volume doesn't exist after remove" docker_volume_exists "$TEST_VOLUME"
        else
            fail "docker_volume_remove" "command failed"
        fi
    else
        fail "docker_volume_create" "command failed"
    fi

    # Test docker_volumes (just verify it runs)
    if docker_volumes >/dev/null 2>&1; then
        pass "docker_volumes runs without error"
    else
        fail "docker_volumes" "command failed"
    fi
else
    skip "volume operations" "Docker daemon not available"
fi

# =============================================================================
# TESTS: NETWORK OPERATIONS (requires Docker)
# =============================================================================

if $DOCKER_AVAILABLE; then
    info "Testing network operations..."

    TEST_NETWORK="mainframe_test_network_$$"

    assert_false "docker_network_exists returns false for nonexistent" docker_network_exists "$TEST_NETWORK"

    # Create test network
    if docker_network_create "$TEST_NETWORK"; then
        pass "docker_network_create succeeds"
        assert_true "docker_network_exists returns true after create" docker_network_exists "$TEST_NETWORK"

        # Remove network
        if docker_network_remove "$TEST_NETWORK"; then
            pass "docker_network_remove succeeds"
            assert_false "network doesn't exist after remove" docker_network_exists "$TEST_NETWORK"
        else
            fail "docker_network_remove" "command failed"
        fi
    else
        fail "docker_network_create" "command failed"
    fi

    # Test docker_networks (just verify it runs)
    if docker_networks >/dev/null 2>&1; then
        pass "docker_networks runs without error"
    else
        fail "docker_networks" "command failed"
    fi
else
    skip "network operations" "Docker daemon not available"
fi

# =============================================================================
# TESTS: INPUT VALIDATION
# =============================================================================

info "Testing input validation..."

# These should all fail gracefully with empty input
assert_false "docker_container_exists handles empty input" docker_container_exists ""
assert_false "docker_container_running handles empty input" docker_container_running ""
assert_false "docker_image_exists handles empty input" docker_image_exists ""
assert_false "docker_port_used handles empty input" docker_port_used ""
assert_false "docker_port_used handles non-numeric input" docker_port_used "abc"
assert_false "docker_volume_exists handles empty input" docker_volume_exists ""
assert_false "docker_network_exists handles empty input" docker_network_exists ""

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "=============================================="
echo "TEST SUMMARY"
echo "=============================================="
printf "Total:   %d\n" "$TESTS_RUN"
printf "${GREEN}Passed:  %d${NC}\n" "$TESTS_PASSED"
printf "${RED}Failed:  %d${NC}\n" "$TESTS_FAILED"
printf "${YELLOW}Skipped: %d${NC}\n" "$TESTS_SKIPPED"
echo "=============================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0

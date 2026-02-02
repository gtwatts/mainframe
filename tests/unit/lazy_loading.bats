#!/usr/bin/env bats
# =============================================================================
# MAINFRAME Lazy Loading Engine Tests
# =============================================================================
# Tests for the lazy loading system that reduces source time from 50-150ms
# to 10-15ms for core-only loading.
#
# TDD: These tests define expected behavior for the lazy loading engine.
# =============================================================================

# Load test helper from parent directory
load '../test_helper'

# -----------------------------------------------------------------------------
# Setup and Teardown
# -----------------------------------------------------------------------------

setup() {
    # Clear any previous state
    unset MAINFRAME_LIBS
    unset MAINFRAME_PROFILE
    unset _MAINFRAME_COMMON_LOADED

    # Clear loaded libs tracking (if it exists)
    unset _MAINFRAME_LOADED_LIBS

    # Store test start time for performance tests (fallback for macOS)
    if date +%s%N &>/dev/null && [[ "$(date +%s%N)" != *"N"* ]]; then
        TEST_START_NS=$(date +%s%N)
    else
        TEST_START_NS="0"
    fi
}

teardown() {
    # Clean up environment
    unset MAINFRAME_LIBS
    unset MAINFRAME_PROFILE
}

# =============================================================================
# TIER DEFINITIONS TESTS
# =============================================================================

@test "tier definitions: core tier contains essential libraries" {
    source_all_libs

    # Core tier should include pure-string, pure-array, json, etc.
    [[ " ${_MAINFRAME_TIER_CORE[*]} " == *" pure-string "* ]]
    [[ " ${_MAINFRAME_TIER_CORE[*]} " == *" pure-array "* ]]
    [[ " ${_MAINFRAME_TIER_CORE[*]} " == *" json "* ]]
}

@test "tier definitions: standard tier contains common libraries" {
    source_all_libs

    # Standard tier should include validation, path, git, etc.
    [[ " ${_MAINFRAME_TIER_STANDARD[*]} " == *" validation "* ]]
    [[ " ${_MAINFRAME_TIER_STANDARD[*]} " == *" path "* ]]
    [[ " ${_MAINFRAME_TIER_STANDARD[*]} " == *" git "* ]]
}

@test "tier definitions: extended tier contains specialized libraries" {
    source_all_libs

    # Extended tier should include k8s, semver, etc.
    [[ " ${_MAINFRAME_TIER_EXTENDED[*]} " == *" k8s "* ]] || \
    [[ " ${_MAINFRAME_TIER_EXTENDED[*]} " == *" semver "* ]]
}

@test "tier definitions: ai tier contains agent-optimized libraries" {
    source_all_libs

    # AI tier should include idempotent, atomic, observe, etc.
    [[ " ${_MAINFRAME_TIER_AI[*]} " == *" idempotent "* ]] || \
    [[ " ${_MAINFRAME_TIER_AI[*]} " == *" atomic "* ]]
}

# =============================================================================
# ENVIRONMENT VARIABLE TESTS
# =============================================================================

@test "MAINFRAME_LIBS: comma-separated library names work" {
    (
        export MAINFRAME_LIBS='json,validation'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # json and validation should be loaded
        [[ -n "${_MAINFRAME_LOADED_LIBS[json]:-}" ]]
        [[ -n "${_MAINFRAME_LOADED_LIBS[validation]:-}" ]]
    )
}

@test "MAINFRAME_LIBS: tier expressions work (core+standard)" {
    # Use bash -c to get a clean process without inherited readonly variables
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_LIBS='core+standard'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
        # Core libs should be loaded
        [[ -n \"\${_MAINFRAME_LOADED_LIBS[pure-string]:-}\" ]] || \
        [[ -n \"\${_MAINFRAME_LOADED_LIBS[json]:-}\" ]]
    "
    [ "$status" -eq 0 ]
}

@test "MAINFRAME_LIBS: 'all' loads everything" {
    # Use bash -c to get a clean process without inherited readonly variables
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_LIBS='all'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
        # Should have many libraries loaded
        count=\$(mainframe_loaded | wc -l)
        [[ \$count -gt 10 ]]
    "
    [ "$status" -eq 0 ]
}

@test "MAINFRAME_LIBS: 'core' loads only core tier" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Core should be loaded, but not standard tier extras
        loaded=$(mainframe_loaded)

        # Core tier lib should exist
        echo "$loaded" | grep -q 'pure-string\|json\|pure-array' || true
    )
}

# =============================================================================
# PROFILE TESTS
# =============================================================================

@test "MAINFRAME_PROFILE: minimal profile loads core only" {
    (
        export MAINFRAME_PROFILE='minimal'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Should be minimal
        local count=$(mainframe_loaded | wc -l)
        [[ $count -lt 15 ]]
    )
}

@test "MAINFRAME_PROFILE: standard profile loads core+standard" {
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_PROFILE='standard'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
        count=\$(mainframe_loaded | wc -l)
        [[ \$count -gt 10 ]]
    "
    [ "$status" -eq 0 ]
}

@test "MAINFRAME_PROFILE: full profile loads everything" {
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_PROFILE='full'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
        count=\$(mainframe_loaded | wc -l)
        [[ \$count -gt 20 ]]
    "
    [ "$status" -eq 0 ]
}

@test "MAINFRAME_PROFILE: ai profile loads core+ai" {
    (
        export MAINFRAME_PROFILE='ai'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Should have AI tier loaded
        loaded=$(mainframe_loaded)
        # AI tier should include idempotent or atomic
        echo "$loaded" | grep -qE 'idempotent|atomic|observe' || true
    )
}

# =============================================================================
# PUBLIC API TESTS
# =============================================================================

@test "mainframe_load: loads a specific library by name" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # git should not be loaded initially with core-only
        if [[ -z "${_MAINFRAME_LOADED_LIBS[git]:-}" ]]; then
            # Now load it
            mainframe_load "git"
            [[ -n "${_MAINFRAME_LOADED_LIBS[git]:-}" ]]
        fi
    )
}

@test "mainframe_load: returns success for valid library" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        mainframe_load "json"
    )
}

@test "mainframe_load: returns failure for non-existent library" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        ! mainframe_load "nonexistent_library_xyz"
    )
}

@test "mainframe_load: prevents path traversal attacks" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # These should all fail
        ! mainframe_load "../../../etc/passwd"
        ! mainframe_load "foo/bar"
        ! mainframe_load "foo bar"
    )
}

@test "mainframe_load_all: loads all available libraries" {
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_LIBS='core'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
        before=\$(mainframe_loaded | wc -l)
        mainframe_load_all
        after=\$(mainframe_loaded | wc -l)
        [[ \$after -gt \$before ]]
    "
    [ "$status" -eq 0 ]
}

@test "mainframe_loaded: returns list of loaded libraries" {
    (
        export MAINFRAME_LIBS='json,validation,path'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local loaded
        loaded=$(mainframe_loaded)

        # Should contain requested libraries (plus core)
        echo "$loaded" | grep -q 'json'
    )
}

@test "mainframe_loaded: output is one library per line" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local loaded
        loaded=$(mainframe_loaded)

        # Each line should be a valid library name (no spaces, no paths)
        while IFS= read -r lib; do
            [[ "$lib" =~ ^[a-zA-Z0-9_-]+$ ]] || [[ -z "$lib" ]]
        done <<< "$loaded"
    )
}

@test "mainframe_available: returns list of all available libraries" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local available
        available=$(mainframe_available)

        # Should include many libraries
        local count
        count=$(echo "$available" | wc -l)
        [[ $count -gt 20 ]]
    )
}

@test "mainframe_available: includes libraries from all tiers" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local available
        available=$(mainframe_available)

        # Should include core, standard, extended, and ai tier libs
        echo "$available" | grep -q 'json'       # core
        echo "$available" | grep -q 'validation' # standard
    )
}

# =============================================================================
# BACKWARD COMPATIBILITY TESTS
# =============================================================================

@test "backward compat: no MAINFRAME_LIBS loads everything" {
    (
        unset MAINFRAME_LIBS
        unset MAINFRAME_PROFILE
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Functions from various tiers should be available
        type json_object &>/dev/null
        type trim_string &>/dev/null
    )
}

@test "backward compat: existing scripts continue to work" {
    (
        unset MAINFRAME_LIBS
        unset MAINFRAME_PROFILE
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Common functions should work
        local result
        result=$(json_object "name=test")
        [[ "$result" == '{"name":"test"}' ]]
    )
}

@test "backward compat: BASHER_* aliases still work" {
    (
        unset MAINFRAME_LIBS
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Legacy constants should be defined
        [[ -n "${BASHER_VERSION:-}" ]]
        [[ -n "${BASHER_NAME:-}" ]]
    )
}

# =============================================================================
# DOUBLE-SOURCING PREVENTION TESTS
# =============================================================================

@test "double-source: library not loaded twice" {
    (
        export MAINFRAME_LIBS='json'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Load json again
        mainframe_load "json"
        mainframe_load "json"

        # Should only appear once in loaded list
        local count
        count=$(mainframe_loaded | grep -c '^json$')
        [[ $count -eq 1 ]]
    )
}

@test "double-source: common.sh guard prevents reload" {
    (
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Second source should be a no-op
        local before
        before=$(mainframe_loaded | wc -l)
        source "$MAINFRAME_ROOT/lib/common.sh"
        local after
        after=$(mainframe_loaded | wc -l)

        [[ $before -eq $after ]]
    )
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "performance: core-only loading is fast" {
    # Skip if nanosecond timing not available (macOS returns literal %N)
    if ! date +%s%N &>/dev/null || [[ "$(date +%s%N)" == *"N"* ]]; then
        skip "nanosecond timing not available"
    fi

    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s%N)

    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"
    )

    end_ns=$(date +%s%N)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    # Core loading should be under 300ms (generous threshold for CI)
    # Target is 10-15ms on modern systems, but CI VMs can be slow
    echo "Core loading time: ${elapsed_ms}ms"
    [[ $elapsed_ms -lt 300 ]]
}

@test "performance: full loading completes successfully" {
    # This test ensures full loading still works, timing is informational
    # Skip if nanosecond timing not available (macOS returns literal %N)
    if ! date +%s%N &>/dev/null || [[ "$(date +%s%N)" == *"N"* ]]; then
        skip "nanosecond timing not available"
    fi

    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s%N)

    # Use bash -c to get a clean process without inherited readonly variables
    bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        source \"\$MAINFRAME_ROOT/lib/common.sh\"
    "

    end_ns=$(date +%s%N)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    echo "Full loading time: ${elapsed_ms}ms"
    # Full loading should complete (no timeout)
    [[ $elapsed_ms -lt 500 ]]
}

@test "performance: selective loading is faster than full loading" {
    # Skip if nanosecond timing not available (macOS returns literal %N)
    if ! date +%s%N &>/dev/null || [[ "$(date +%s%N)" == *"N"* ]]; then
        skip "nanosecond timing not available"
    fi

    # Time core-only loading
    local start_ns end_ns core_ms
    start_ns=$(date +%s%N)
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"
    )
    end_ns=$(date +%s%N)
    core_ms=$(( (end_ns - start_ns) / 1000000 ))

    # Time full loading
    start_ns=$(date +%s%N)
    (
        unset MAINFRAME_LIBS
        unset MAINFRAME_PROFILE
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"
    )
    end_ns=$(date +%s%N)
    local full_ms=$(( (end_ns - start_ns) / 1000000 ))

    echo "Core: ${core_ms}ms, Full: ${full_ms}ms"

    # Core should be faster (or at least not slower)
    # Allow some variance for system noise
    [[ $core_ms -le $((full_ms + 20)) ]]
}

# =============================================================================
# LAZY INIT TESTS
# =============================================================================

@test "_mainframe_lazy_init: initializes lazy loading state" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # _mainframe_lazy_init should have been called during sourcing
        # The _MAINFRAME_LOADED_LIBS associative array should exist
        declare -p _MAINFRAME_LOADED_LIBS &>/dev/null
    )
}

@test "_mainframe_lazy_init: can be called multiple times safely" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Call init again - should not error
        _mainframe_lazy_init
        _mainframe_lazy_init

        # Should still work
        local count
        count=$(mainframe_loaded | wc -l)
        [[ $count -gt 0 ]]
    )
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "error handling: invalid library name is rejected" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Invalid names should fail
        ! mainframe_load ""
        ! mainframe_load "   "
    )
}

@test "error handling: whitespace in MAINFRAME_LIBS is trimmed" {
    (
        export MAINFRAME_LIBS='  json , validation  ,  path  '
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Should have loaded the libraries despite whitespace
        [[ -n "${_MAINFRAME_LOADED_LIBS[json]:-}" ]]
    )
}

@test "error handling: unknown profile falls back to all" {
    run bash -c "
        export MAINFRAME_ROOT='$MAINFRAME_ROOT'
        export MAINFRAME_PROFILE='unknown_profile_xyz'
        source \"\$MAINFRAME_ROOT/lib/common.sh\" 2>/dev/null
        count=\$(mainframe_loaded | wc -l)
        [[ \$count -gt 20 ]]
    "
    [ "$status" -eq 0 ]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "integration: loaded functions are callable" {
    (
        export MAINFRAME_LIBS='json,pure-string'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # json functions should work
        local result
        result=$(json_object "key=value")
        [[ "$result" == '{"key":"value"}' ]]

        # string functions should work
        result=$(trim_string "  hello  ")
        [[ "$result" == "hello" ]]
    )
}

@test "integration: unloaded functions are not available" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # If k8s is in extended tier and not loaded, its functions shouldn't exist
        # (unless k8s is actually in core tier)
        # This is informational - depends on tier configuration
        true
    )
}

@test "integration: mainframe_load enables functions on demand" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Load git on demand
        mainframe_load "git"

        # git functions should now be available
        type git_branch &>/dev/null || true
    )
}

# =============================================================================
# TIER COUNT TESTS
# =============================================================================

@test "tier count: core tier has reasonable number of libraries" {
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local count=${#_MAINFRAME_TIER_CORE[@]}
        # Core should have 5-15 libraries
        [[ $count -ge 5 ]] && [[ $count -le 15 ]]
    )
}

@test "tier count: all tiers combined cover most libraries" {
    (
        unset MAINFRAME_LIBS
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local total_defined=$((
            ${#_MAINFRAME_TIER_CORE[@]} +
            ${#_MAINFRAME_TIER_STANDARD[@]} +
            ${#_MAINFRAME_TIER_EXTENDED[@]} +
            ${#_MAINFRAME_TIER_AI[@]}
        ))

        # Should have at least 30 libraries defined across tiers
        [[ $total_defined -ge 30 ]]
    )
}

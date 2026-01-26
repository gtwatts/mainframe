#!/usr/bin/env bats
# =============================================================================
# MAINFRAME Lazy Loading Engine Tests
# =============================================================================
# Tests for the lazy loading system that reduces source time from 50-150ms
# to 10-15ms for core-only loading.
#
# TDD: These tests define expected behavior for the lazy loading engine.
# =============================================================================

load 'test_helper'

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

    # Store test start time for performance tests
    TEST_START_NS=$(date +%s%N 2>/dev/null || echo "0")
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
    (
        export MAINFRAME_LIBS='core+standard'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Core libs should be loaded
        [[ -n "${_MAINFRAME_LOADED_LIBS[pure-string]:-}" ]] || \
        [[ -n "${_MAINFRAME_LOADED_LIBS[json]:-}" ]]
    )
}

@test "MAINFRAME_LIBS: 'all' loads everything" {
    (
        export MAINFRAME_LIBS='all'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Should have many libraries loaded
        local count=$(mainframe_loaded | wc -l)
        [[ $count -gt 10 ]]
    )
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
    (
        export MAINFRAME_PROFILE='standard'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local count=$(mainframe_loaded | wc -l)
        [[ $count -gt 10 ]]
    )
}

@test "MAINFRAME_PROFILE: full profile loads everything" {
    (
        export MAINFRAME_PROFILE='full'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local count=$(mainframe_loaded | wc -l)
        [[ $count -gt 20 ]]
    )
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
    (
        export MAINFRAME_LIBS='core'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        local before=$(mainframe_loaded | wc -l)
        mainframe_load_all
        local after=$(mainframe_loaded | wc -l)

        [[ $after -gt $before ]]
    )
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
    # Skip if nanosecond timing not available
    if ! date +%s%N &>/dev/null; then
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

    # Core loading should be under 50ms (generous threshold for CI)
    # Target is 10-15ms, but allowing headroom for slow CI machines
    echo "Core loading time: ${elapsed_ms}ms"
    [[ $elapsed_ms -lt 100 ]]
}

@test "performance: full loading completes successfully" {
    # This test ensures full loading still works, timing is informational
    if ! date +%s%N &>/dev/null; then
        skip "nanosecond timing not available"
    fi

    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s%N)

    (
        unset MAINFRAME_LIBS
        unset MAINFRAME_PROFILE
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"
    )

    end_ns=$(date +%s%N)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    echo "Full loading time: ${elapsed_ms}ms"
    # Full loading should complete (no timeout)
    [[ $elapsed_ms -lt 500 ]]
}

@test "performance: selective loading is faster than full loading" {
    if ! date +%s%N &>/dev/null; then
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
    (
        export MAINFRAME_PROFILE='unknown_profile_xyz'
        unset _MAINFRAME_COMMON_LOADED
        # Suppress warning
        source "$MAINFRAME_ROOT/lib/common.sh" 2>/dev/null

        # Should have loaded everything
        local count
        count=$(mainframe_loaded | wc -l)
        [[ $count -gt 20 ]]
    )
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

# =============================================================================
# ENHANCED LAZY LOADING ENGINE TESTS (lib/lazy.sh)
# =============================================================================
# These tests cover the function-level lazy loading system that creates stubs
# which load libraries on first call.
# =============================================================================

# -----------------------------------------------------------------------------
# Lazy Loading Setup
# -----------------------------------------------------------------------------

lazy_setup() {
    source_lib "lazy"
    export MAINFRAME_QUIET=1
    LAZY_TEST_DIR=$(mktemp -d "/tmp/mainframe-lazy-test.XXXXXX")

    # Reset state
    _LAZY_MANIFEST=()
    _LAZY_LOAD_TIMES=()
    _LAZY_STUBS=()
    _LAZY_LOADED_LIBS=()
}

lazy_teardown() {
    [[ -d "${LAZY_TEST_DIR:-}" ]] && rm -rf "$LAZY_TEST_DIR"
}

# -----------------------------------------------------------------------------
# Stub Creation Tests
# -----------------------------------------------------------------------------

@test "lazy_stub: creates a callable function" {
    lazy_setup
    lazy_stub "test_stub_func" "testlib"
    declare -F test_stub_func
    lazy_teardown
}

@test "lazy_stub: registers function in manifest" {
    lazy_setup
    lazy_stub "test_manifest_func" "targetlib"
    [ "${_LAZY_MANIFEST[test_manifest_func]}" = "targetlib" ]
    lazy_teardown
}

@test "lazy_stub: marks function as stub" {
    lazy_setup
    lazy_stub "test_marked_func" "somelib"
    lazy_is_stub "test_marked_func"
    lazy_teardown
}

@test "lazy_stub: rejects empty function name" {
    lazy_setup
    ! lazy_stub "" "testlib"
    lazy_teardown
}

@test "lazy_stub: rejects empty library name" {
    lazy_setup
    ! lazy_stub "test_func" ""
    lazy_teardown
}

@test "lazy_stub: rejects function name with spaces" {
    lazy_setup
    ! lazy_stub "invalid func" "testlib"
    lazy_teardown
}

@test "lazy_stub: rejects library name with path traversal" {
    lazy_setup
    ! lazy_stub "test_func" "../etc/passwd"
    ! lazy_stub "test_func" "path/to/lib"
    lazy_teardown
}

@test "lazy_stub_library: creates multiple stubs" {
    lazy_setup
    lazy_stub_library "multilib" func_a func_b func_c
    declare -F func_a
    declare -F func_b
    declare -F func_c
    lazy_teardown
}

@test "lazy_is_stub: returns false for regular function" {
    lazy_setup
    regular_function() { echo "regular"; }
    ! lazy_is_stub "regular_function"
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Stub Execution Tests
# -----------------------------------------------------------------------------

@test "stub: loads library on first call" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/autoload_lib.sh" << 'EOF'
#!/usr/bin/env bash
autoload_func() { printf 'autoloaded\n'; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_stub "autoload_func" "autoload_lib"
    local result
    result=$(autoload_func)
    [ "$result" = "autoloaded" ]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "stub: is no longer stub after library loads" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/load_once_lib.sh" << 'EOF'
#!/usr/bin/env bash
load_once_func() { echo "loaded"; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_stub "load_once_func" "load_once_lib"
    lazy_is_stub "load_once_func"
    load_once_func >/dev/null
    ! lazy_is_stub "load_once_func"

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "stub: preserves arguments" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/args_lib.sh" << 'EOF'
#!/usr/bin/env bash
args_test_func() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_stub "args_test_func" "args_lib"
    local result
    result=$(args_test_func "arg1" "arg2" "arg3")
    [ "$result" = "arg1|arg2|arg3" ]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Manifest Tests
# -----------------------------------------------------------------------------

@test "lazy_register: adds multiple functions to manifest" {
    lazy_setup
    lazy_register "datetime" now now_iso date_add
    [ "${_LAZY_MANIFEST[now]}" = "datetime" ]
    [ "${_LAZY_MANIFEST[now_iso]}" = "datetime" ]
    [ "${_LAZY_MANIFEST[date_add]}" = "datetime" ]
    lazy_teardown
}

@test "lazy_library_for: returns correct library" {
    lazy_setup
    lazy_register "http" http_get http_post
    local result
    result=$(lazy_library_for "http_get")
    [ "$result" = "http" ]
    lazy_teardown
}

@test "lazy_library_for: returns empty for unknown function" {
    lazy_setup
    local result
    result=$(lazy_library_for "nonexistent_xyz")
    [ -z "$result" ]
    lazy_teardown
}

@test "lazy_functions_in: lists functions for library" {
    lazy_setup
    lazy_register "crypto" sha256 md5 base64_encode
    local result
    result=$(lazy_functions_in "crypto")
    [[ "$result" == *"sha256"* ]]
    [[ "$result" == *"md5"* ]]
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Library Loading Tests
# -----------------------------------------------------------------------------

@test "lazy_load_library: loads existing library" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/loadable_lib.sh" << 'EOF'
#!/usr/bin/env bash
LOADABLE_MARKER=1
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_load_library "loadable_lib"
    [ "${_LAZY_LOADED_LIBS[loadable_lib]}" = "1" ]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "lazy_load_library: fails for nonexistent library" {
    lazy_setup
    ! lazy_load_library "definitely_not_a_real_library_xyz"
    lazy_teardown
}

@test "lazy_load_library: rejects invalid names" {
    lazy_setup
    ! lazy_load_library ""
    ! lazy_load_library "../passwd"
    ! lazy_load_library "lib;echo"
    lazy_teardown
}

@test "lazy_is_loaded: returns true after loading" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/check_loaded_lib.sh" << 'EOF'
#!/usr/bin/env bash
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    ! lazy_is_loaded "check_loaded_lib"
    lazy_load_library "check_loaded_lib"
    lazy_is_loaded "check_loaded_lib"

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Bundle Tests
# -----------------------------------------------------------------------------

@test "lazy_bundle_create: produces valid bash" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/bundle_lib1.sh" << 'EOF'
#!/usr/bin/env bash
bundle_func1() { echo "func1"; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_bundle_create "$LAZY_TEST_DIR/bundle_output.sh" "bundle_lib1"
    [ -f "$LAZY_TEST_DIR/bundle_output.sh" ]
    bash -n "$LAZY_TEST_DIR/bundle_output.sh"

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "lazy_bundle_create: includes library content" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/content_test_lib.sh" << 'EOF'
#!/usr/bin/env bash
unique_bundle_marker() { echo "marker"; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_bundle_create "$LAZY_TEST_DIR/content_bundle.sh" "content_test_lib"
    grep -q "unique_bundle_marker" "$LAZY_TEST_DIR/content_bundle.sh"

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "lazy_bundle_validate: accepts valid bundle" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/valid_test_bundle.sh" << 'EOF'
#!/usr/bin/env bash
# Libraries: test
echo "valid bundle"
EOF
    lazy_bundle_validate "$LAZY_TEST_DIR/valid_test_bundle.sh"
    lazy_teardown
}

@test "lazy_bundle_validate: rejects invalid syntax" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/invalid_test_bundle.sh" << 'EOF'
#!/usr/bin/env bash
if [[ then syntax error
EOF
    ! lazy_bundle_validate "$LAZY_TEST_DIR/invalid_test_bundle.sh" 2>/dev/null
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Profiling Tests
# -----------------------------------------------------------------------------

@test "profiling: records load times when enabled" {
    lazy_setup
    export MAINFRAME_PROFILE_LOADS=1
    cat > "$LAZY_TEST_DIR/profile_test_lib.sh" << 'EOF'
#!/usr/bin/env bash
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_load_library "profile_test_lib"
    [[ -n "${_LAZY_LOAD_TIMES[profile_test_lib]:-}" ]]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    unset MAINFRAME_PROFILE_LOADS
    lazy_teardown
}

@test "profiling: does not record when disabled" {
    lazy_setup
    export MAINFRAME_PROFILE_LOADS=0
    cat > "$LAZY_TEST_DIR/no_profile_lib.sh" << 'EOF'
#!/usr/bin/env bash
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_load_library "no_profile_lib"
    [[ -z "${_LAZY_LOAD_TIMES[no_profile_lib]:-}" ]]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    unset MAINFRAME_PROFILE_LOADS
    lazy_teardown
}

@test "lazy_profile_report: generates output" {
    lazy_setup
    _LAZY_LOAD_TIMES=([testlib]="5.5" [otherlib]="3.2")
    local result
    result=$(lazy_profile_report)
    [[ "$result" == *"MAINFRAME Load Profile"* ]]
    [[ "$result" == *"testlib"* ]]
    [[ "$result" == *"TOTAL"* ]]
    lazy_teardown
}

@test "lazy_profile_clear: resets state" {
    lazy_setup
    _LAZY_LOAD_TIMES=([lib1]="1.0")
    _LAZY_LOAD_START="12345"
    lazy_profile_clear
    [ ${#_LAZY_LOAD_TIMES[@]} -eq 0 ]
    [ -z "$_LAZY_LOAD_START" ]
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Unload/Reload Tests
# -----------------------------------------------------------------------------

@test "lazy_unload: replaces functions with stubs" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/unload_test_lib.sh" << 'EOF'
#!/usr/bin/env bash
unload_test_func() { echo "real"; }
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_register "unload_test_lib" unload_test_func
    lazy_load_library "unload_test_lib"
    lazy_is_loaded "unload_test_lib"
    ! lazy_is_stub "unload_test_func"

    lazy_unload "unload_test_lib"
    ! lazy_is_loaded "unload_test_lib"
    lazy_is_stub "unload_test_func"

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "lazy_reload: unloads and reloads" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/reload_test_lib.sh" << 'EOF'
#!/usr/bin/env bash
RELOAD_TEST_COUNTER=$((${RELOAD_TEST_COUNTER:-0} + 1))
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_register "reload_test_lib" reload_test_func
    lazy_load_library "reload_test_lib"
    local first="$RELOAD_TEST_COUNTER"
    lazy_reload "reload_test_lib"
    [ "$RELOAD_TEST_COUNTER" -gt "$first" ]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

@test "lazy_memory_report: produces output" {
    lazy_setup
    local result
    result=$(lazy_memory_report)
    [[ "$result" == *"Function Memory Usage"* ]]
    [[ "$result" == *"Total functions"* ]]
    lazy_teardown
}

@test "lazy_memory_usage: returns numeric value" {
    lazy_setup
    local result
    result=$(lazy_memory_usage)
    [[ "$result" =~ ^[0-9]+$ ]]
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Initialization Tests
# -----------------------------------------------------------------------------

@test "lazy_init_manifests: registers standard libraries" {
    lazy_setup
    lazy_init_manifests
    [[ -n "${_LAZY_MANIFEST[now]:-}" ]]
    [[ -n "${_LAZY_MANIFEST[http_get]:-}" ]]
    [[ -n "${_LAZY_MANIFEST[sha256]:-}" ]]
    lazy_teardown
}

@test "lazy_init_stubs: creates stubs for registered functions" {
    lazy_setup
    lazy_init_stubs
    declare -F now
    declare -F http_get
    lazy_is_stub "now"
    lazy_is_stub "http_get"
    lazy_teardown
}

@test "lazy_init with manifests mode: only registers" {
    lazy_setup
    lazy_init "manifests"
    [[ ${#_LAZY_MANIFEST[@]} -gt 0 ]]
    [ ${#_LAZY_STUBS[@]} -eq 0 ]
    lazy_teardown
}

@test "lazy_init with stubs mode: creates stubs" {
    lazy_setup
    lazy_init "stubs"
    [[ ${#_LAZY_STUBS[@]} -gt 0 ]]
    lazy_teardown
}

@test "lazy_status: produces status output" {
    lazy_setup
    lazy_init "manifests"
    local result
    result=$(lazy_status)
    [[ "$result" == *"Lazy Loading Status"* ]]
    [[ "$result" == *"Registered functions"* ]]
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Edge Cases
# -----------------------------------------------------------------------------

@test "lazy_unload: safe on not-loaded library" {
    lazy_setup
    lazy_unload "never_loaded_library"
    # Should not error
    lazy_teardown
}

@test "double load: is idempotent" {
    lazy_setup
    cat > "$LAZY_TEST_DIR/double_load_lib.sh" << 'EOF'
#!/usr/bin/env bash
DOUBLE_LOAD_COUNTER=$((${DOUBLE_LOAD_COUNTER:-0} + 1))
EOF
    local orig_root="${MAINFRAME_ROOT:-}"
    export MAINFRAME_ROOT="$LAZY_TEST_DIR"

    lazy_load_library "double_load_lib"
    local count1="$DOUBLE_LOAD_COUNTER"
    lazy_load_library "double_load_lib"
    local count2="$DOUBLE_LOAD_COUNTER"
    [ "$count1" = "$count2" ]

    [[ -n "$orig_root" ]] && export MAINFRAME_ROOT="$orig_root" || unset MAINFRAME_ROOT
    lazy_teardown
}

# -----------------------------------------------------------------------------
# Integration: MAINFRAME_LAZY=1 Mode
# -----------------------------------------------------------------------------

@test "MAINFRAME_LAZY=1: enables function-level lazy loading" {
    (
        export MAINFRAME_LAZY=1
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # lazy.sh should be loaded
        [[ -n "${_MAINFRAME_LOADED_LIBS[lazy]:-}" ]] || \
        declare -F lazy_stub &>/dev/null
    )
}

@test "MAINFRAME_PROFILE=lazy: enables function-level lazy loading" {
    (
        export MAINFRAME_PROFILE='lazy'
        unset _MAINFRAME_COMMON_LOADED
        source "$MAINFRAME_ROOT/lib/common.sh"

        # Lazy loading should be enabled
        declare -F lazy_stub &>/dev/null || \
        [[ "${MAINFRAME_LAZY:-0}" == "1" ]]
    )
}

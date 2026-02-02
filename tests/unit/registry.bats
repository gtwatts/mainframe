#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/registry.bats - Registry Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/registry.sh
#              Function scanner and catalog system for auto-documenting
# Test Count: 45+ test cases
# Categories: scanning, querying, searching, export, cache, statistics
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Set registry cache to temp dir
    export MAINFRAME_REGISTRY_DIR="$TEST_TMPDIR/registry"
    export MAINFRAME_REGISTRY_TTL=3600
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/registry.sh"

    # Create test library files
    mkdir -p "$TEST_TMPDIR/lib"

    # Test library 1: well-documented functions
    cat > "$TEST_TMPDIR/lib/test_lib1.sh" << 'TESTLIB1'
#!/usr/bin/env bash
# Test Library 1

# @name: test_func_one
# @description: A well-documented test function
# @param input: string - The input value
# @param count: number - Optional count
# @returns: string - The processed result
# @example: test_func_one "hello" 5
# @category: testing
# @since: v1.0
test_func_one() {
    echo "one"
}

# @name: test_func_two
# @description: Another documented function
# @param data: array - Input array
# @returns: number - The count
# @example: test_func_two "${arr[@]}"
# @category: testing
# @since: v1.0
test_func_two() {
    echo "two"
}

# Simple function without docstring
test_func_simple() {
    echo "simple"
}

# Internal function (should be skipped)
_internal_helper() {
    echo "internal"
}
TESTLIB1

    # Test library 2: different category
    cat > "$TEST_TMPDIR/lib/test_lib2.sh" << 'TESTLIB2'
#!/usr/bin/env bash
# Test Library 2

# @name: util_helper
# @description: A utility helper function
# @param value: string - Input value
# @returns: string - Modified value
# @example: util_helper "test"
# @category: utilities
# @since: v1.1
util_helper() {
    echo "helper"
}

# @name: util_transform
# @description: Transform function
# @param input: string - Data to transform
# @param mode: string - Transform mode
# @returns: string - Transformed data
# @example: util_transform "data" "upper"
# @category: utilities
# @since: v1.1
# @deprecated: Use util_helper instead
util_transform() {
    echo "transform"
}
TESTLIB2

    # Test library 3: edge cases
    cat > "$TEST_TMPDIR/lib/test_lib3.sh" << 'TESTLIB3'
#!/usr/bin/env bash
# Test Library 3 - Edge Cases

# Function with equals in description
# @name: func_with_equals
# @description: Function where a=b+c formula applies
# @param formula: string - The formula like x=y
# @category: math
func_with_equals() {
    echo "equals"
}

# @name: func_multiline
# @description: Function with special chars in description
# @param path: string - Path like /usr/local/bin
# @returns: bool - true/false
# @category: validation
func_multiline() {
    echo "multiline"
}

# Undocumented function
bare_function() {
    echo "bare"
}

function keyword_func() {
    echo "keyword"
}
TESTLIB3
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: BASIC SCANNING
# =============================================================================

@test "registry_scan: scans single library file" {
    count=$(registry_scan "$TEST_TMPDIR/lib/test_lib1.sh")
    [[ "$count" -eq 3 ]]  # 3 public functions (test_func_one, test_func_two, test_func_simple)
}

@test "registry_scan: skips internal functions starting with underscore" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    run registry_function_exists "_internal_helper"
    [[ "$status" -eq 1 ]]
}

@test "registry_scan: extracts function name correctly" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    run registry_function_exists "test_func_one"
    [[ "$status" -eq 0 ]]
}

@test "registry_scan: fails on missing file" {
    run registry_scan "$TEST_TMPDIR/lib/nonexistent.sh"
    [[ "$status" -eq 1 ]]
}

@test "registry_scan: fails on empty argument" {
    run registry_scan ""
    [[ "$status" -eq 1 ]]
}

@test "registry_scan: handles function keyword syntax" {
    registry_scan "$TEST_TMPDIR/lib/test_lib3.sh"
    run registry_function_exists "keyword_func"
    [[ "$status" -eq 0 ]]
}

@test "registry_scan: handles undocumented functions" {
    registry_scan "$TEST_TMPDIR/lib/test_lib3.sh"
    run registry_function_exists "bare_function"
    [[ "$status" -eq 0 ]]
}

@test "registry_scan: incremental rescan replaces old entries" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    count1=$(registry_count)

    # Modify library
    echo 'new_function() { :; }' >> "$TEST_TMPDIR/lib/test_lib1.sh"

    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    count2=$(registry_count)

    [[ "$count2" -eq $((count1 + 1)) ]]
}

# =============================================================================
# CATEGORY 2: FULL LIBRARY SCAN
# =============================================================================

@test "registry_scan_all: scans all libraries" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    count=$(registry_scan_all)
    [[ "$count" -gt 0 ]]
}

@test "registry_scan_all: sets total count" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    count=$(registry_count)
    [[ "$count" -gt 5 ]]  # Should have at least functions from our test libs
}

@test "registry_scan_all: clears previous data" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    count1=$(registry_count)

    # Rescan should produce same count (not doubled)
    registry_scan_all
    count2=$(registry_count)

    [[ "$count1" -eq "$count2" ]]
}

# =============================================================================
# CATEGORY 3: DOCSTRING PARSING
# =============================================================================

@test "registry parses @description tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"description":"A well-documented test function"' ]]
}

@test "registry parses @param tags" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"name":"input"' ]]
    [[ "$result" =~ '"type":"string"' ]]
}

@test "registry parses @returns tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"returns":' ]]
    [[ "$result" =~ '"type":"string"' ]]
}

@test "registry parses @example tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    # Pattern must be unquoted for regex escapes to work
    [[ "$result" =~ \"examples\":\[\"test_func_one ]]
    [[ "$result" =~ hello ]]
}

@test "registry parses @category tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"category":"testing"' ]]
}

@test "registry parses @since tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"since":"v1.0"' ]]
}

@test "registry parses @deprecated tag" {
    registry_scan "$TEST_TMPDIR/lib/test_lib2.sh"
    result=$(registry_get_function "util_transform")
    [[ "$result" =~ '"deprecated":"Use util_helper instead"' ]]
}

@test "registry includes library name in metadata" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"library":"test_lib1.sh"' ]]
}

@test "registry includes line number in metadata" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ "$result" =~ '"line_number":' ]]
}

# =============================================================================
# CATEGORY 4: QUERY FUNCTIONS
# =============================================================================

@test "registry_get_function: returns metadata for existing function" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_get_function "test_func_one")
    [[ -n "$result" ]]
    [[ "$result" =~ '"name":' ]]
}

@test "registry_get_function: fails for nonexistent function" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    run registry_get_function "nonexistent_function"
    [[ "$status" -eq 1 ]]
}

@test "registry_get_function: fails on empty argument" {
    run registry_get_function ""
    [[ "$status" -eq 1 ]]
}

@test "registry_list_by_category: returns functions in category" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_list_by_category "testing")
    [[ "$result" =~ 'test_func_one' ]]
    [[ "$result" =~ 'test_func_two' ]]
}

@test "registry_list_by_category: returns empty array for unknown category" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_list_by_category "nonexistent")
    [[ "$result" == '[]' ]]
}

@test "registry_list_by_library: returns functions from library" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_list_by_library "test_lib1")
    [[ "$result" =~ 'test_func_one' ]]
}

@test "registry_list_by_library: accepts library name with .sh extension" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_list_by_library "test_lib1.sh")
    [[ "$result" =~ 'test_func_one' ]]
}

@test "registry_list_by_library: returns empty array for unknown library" {
    result=$(registry_list_by_library "unknown_lib")
    [[ "$result" == '[]' ]]
}

# =============================================================================
# CATEGORY 5: SEARCH
# =============================================================================

@test "registry_search: finds functions by name" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_search "test_func")
    [[ "$result" =~ 'test_func_one' ]]
    [[ "$result" =~ 'test_func_two' ]]
}

@test "registry_search: finds functions by description" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_search "utility")
    [[ "$result" =~ 'util_helper' ]]
}

@test "registry_search: case insensitive" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_search "TRANSFORM")
    [[ "$result" =~ 'util_transform' ]]
}

@test "registry_search: returns empty array for no matches" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    result=$(registry_search "zzzznonexistent")
    [[ "$result" == '[]' ]]
}

@test "registry_search: fails on empty pattern" {
    run registry_search ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 6: EXPORT
# =============================================================================

@test "registry_export: creates valid JSON file" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    registry_export "$TEST_TMPDIR/export.json"

    [[ -f "$TEST_TMPDIR/export.json" ]]

    # Basic structure validation
    result=$(<"$TEST_TMPDIR/export.json")
    [[ "$result" =~ '"version":' ]]
    [[ "$result" =~ '"stats":' ]]
    [[ "$result" =~ '"libraries":' ]]
}

@test "registry_export: includes statistics" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    registry_export "$TEST_TMPDIR/export.json"

    result=$(<"$TEST_TMPDIR/export.json")
    [[ "$result" =~ '"total_functions":' ]]
    [[ "$result" =~ '"total_libraries":' ]]
}

@test "registry_export: includes timestamp" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    registry_export "$TEST_TMPDIR/export.json"

    result=$(<"$TEST_TMPDIR/export.json")
    [[ "$result" =~ '"generated":' ]]
}

@test "registry_export: fails on empty file path" {
    run registry_export ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: CACHE MANAGEMENT
# =============================================================================

@test "registry_save_cache: creates cache file" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    registry_save_cache

    [[ -f "$MAINFRAME_REGISTRY_DIR/registry.cache" ]]
}

@test "registry_load_cache: loads from cache" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    local original_count=$(registry_count)
    registry_save_cache

    # Clear in-memory state
    _REGISTRY_FUNCTIONS=()
    _REGISTRY_TOTAL_FUNCTIONS=0

    # Load from cache
    registry_load_cache
    local cached_count=$(registry_count)

    [[ "$original_count" -eq "$cached_count" ]]
}

@test "registry_load_cache: returns 1 if no cache exists" {
    run registry_load_cache
    [[ "$status" -eq 1 ]]
}

@test "registry_load_cache: respects TTL" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    export MAINFRAME_REGISTRY_TTL=1  # 1 second TTL

    registry_scan_all
    registry_save_cache

    # Wait for cache to expire
    sleep 2

    run registry_load_cache
    [[ "$status" -eq 1 ]]
}

@test "registry_clear_cache: removes cache file" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    registry_save_cache

    [[ -f "$MAINFRAME_REGISTRY_DIR/registry.cache" ]]

    registry_clear_cache

    [[ ! -f "$MAINFRAME_REGISTRY_DIR/registry.cache" ]]
}

# =============================================================================
# CATEGORY 8: STATISTICS
# =============================================================================

@test "registry_stats: returns JSON with counts" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_stats)

    [[ "$result" =~ '"total_functions":' ]]
    [[ "$result" =~ '"total_libraries":' ]]
    [[ "$result" =~ '"total_categories":' ]]
}

@test "registry_stats: includes category breakdown" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_stats)

    [[ "$result" =~ '"categories":{' ]]
}

@test "registry_stats: includes library breakdown" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_stats)

    [[ "$result" =~ '"libraries":{' ]]
}

@test "registry_count: returns correct count" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    count=$(registry_count)

    [[ "$count" -gt 5 ]]
}

# =============================================================================
# CATEGORY 9: CONVENIENCE FUNCTIONS
# =============================================================================

@test "registry_list_categories: returns JSON array" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_list_categories)

    # Pattern must be unquoted for regex metacharacters to work
    [[ "$result" =~ ^\[ ]]
    [[ "$result" =~ \]$ ]]
}

@test "registry_list_libraries: returns JSON array" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_list_libraries)

    # Pattern must be unquoted for regex metacharacters to work
    [[ "$result" =~ ^\[ ]]
    [[ "$result" =~ \]$ ]]
    [[ "$result" =~ test_lib1 ]]
}

@test "registry_function_exists: returns 0 for existing function" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    registry_function_exists "test_func_one"
    [[ $? -eq 0 ]]
}

@test "registry_function_exists: returns 1 for nonexistent function" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    run registry_function_exists "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "registry_list_all: returns sorted list" {
    export MAINFRAME_ROOT="$TEST_TMPDIR"
    registry_scan_all
    result=$(registry_list_all)

    # Should contain functions from test libraries
    [[ "$result" =~ 'test_func_one' ]]

    # Check it's sorted (first line should be alphabetically first)
    first_line=$(echo "$result" | head -1)
    sorted_first=$(echo "$result" | sort | head -1)
    [[ "$first_line" == "$sorted_first" ]]
}

# =============================================================================
# CATEGORY 10: EDGE CASES
# =============================================================================

@test "registry handles special characters in descriptions" {
    registry_scan "$TEST_TMPDIR/lib/test_lib3.sh"
    result=$(registry_get_function "func_with_equals")
    [[ -n "$result" ]]
}

@test "registry handles multiple scans without duplication" {
    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    count1=$(registry_count)

    registry_scan "$TEST_TMPDIR/lib/test_lib1.sh"
    count2=$(registry_count)

    [[ "$count1" -eq "$count2" ]]
}

@test "registry handles empty library file" {
    echo '#!/usr/bin/env bash' > "$TEST_TMPDIR/lib/empty.sh"
    count=$(registry_scan "$TEST_TMPDIR/lib/empty.sh")
    [[ "$count" -eq 0 ]]
}

@test "registry handles library with only internal functions" {
    cat > "$TEST_TMPDIR/lib/internal_only.sh" << 'EOF'
#!/usr/bin/env bash
_private_one() { :; }
_private_two() { :; }
EOF
    count=$(registry_scan "$TEST_TMPDIR/lib/internal_only.sh")
    [[ "$count" -eq 0 ]]
}


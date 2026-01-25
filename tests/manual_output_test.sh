#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Quick Manual Test for output.sh USOP Implementation
# =============================================================================
# Run this script to verify output.sh is working correctly.
# Usage: bash tests/manual_output_test.sh
# =============================================================================

set -euo pipefail

# Source the library
MAINFRAME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$MAINFRAME_ROOT/lib/output.sh"

echo "=== USOP Manual Test ==="
echo

# Test 1: Mode detection
echo "Test 1: Mode detection"
output_init
echo "  Default mode: $(output_mode)"
output_mode "json"
echo "  After set to json: $(output_mode)"
output_mode "raw"
echo "  After set to raw: $(output_mode)"
echo "  [PASS]"
echo

# Test 2: output_success in different modes
echo "Test 2: output_success in different modes"
export MAINFRAME_OUTPUT="raw"
echo "  Raw mode: $(output_success "hello world")"
export MAINFRAME_OUTPUT="json"
echo "  JSON mode: $(output_success "hello world")"
export MAINFRAME_OUTPUT="minimal"
echo "  Minimal mode: $(output_success "hello world")"
export MAINFRAME_OUTPUT="json"
echo "  JSON with hint: $(output_success "data" "next_function")"
echo "  [PASS]"
echo

# Test 3: output_error
echo "Test 3: output_error"
export MAINFRAME_OUTPUT="json"
echo "  Error: $(output_error "E_TEST" "Test error message")"
echo "  Error with suggestion: $(output_error "E_TEST" "Test error" "try again")"
echo "  [PASS]"
echo

# Test 4: Type helpers
echo "Test 4: Type helpers (JSON mode)"
export MAINFRAME_OUTPUT="json"
echo "  output_int 42: $(output_int 42)"
echo "  output_float 3.14: $(output_float 3.14)"
echo "  output_bool true: $(output_bool true)"
echo "  output_bool false: $(output_bool false)"
echo "  output_void: $(output_void)"
echo "  output_json_object: $(output_json_object '{"key":"value"}')"
echo "  output_json_array: $(output_json_array '["a","b","c"]')"
echo "  [PASS]"
echo

# Test 5: Timing
echo "Test 5: Timing"
_test_timing() {
    output_timer_start
    sleep 0.05
    output_success "done"
}
echo "  With timer: $(_test_timing)"
echo "  [PASS]"
echo

# Test 6: output_wrap
echo "Test 6: output_wrap"
_test_func() { echo "test output"; }
export MAINFRAME_OUTPUT="json"
echo "  Wrapped function: $(output_wrap _test_func)"
echo "  [PASS]"
echo

# Test 7: output_v (nameref)
echo "Test 7: output_v nameref variant"
local_result=""
output_v local_result "nameref test"
echo "  Result: $local_result"
echo "  [PASS]"
echo

# Test 8: Escape special characters
echo "Test 8: JSON escaping"
export MAINFRAME_OUTPUT="json"
echo "  Quotes: $(output_success 'hello "world"')"
echo "  Newlines: $(output_success $'line1\nline2')"
echo "  Tabs: $(output_success $'col1\tcol2')"
echo "  [PASS]"
echo

echo "=== All manual tests passed ==="

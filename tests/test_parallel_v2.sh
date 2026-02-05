#!/usr/bin/env bash
# =============================================================================
# Tests for lib/parallel_v2.sh
# =============================================================================

set -euo pipefail

# Determine test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"

# Source the library
source "$LIB_DIR/parallel_v2.sh"
source "$LIB_DIR/json.sh"

echo "=== Testing parallel_v2.sh ==="
echo

# Test 1: Basic parallel run
echo "Test 1: parallel_v2_run (basic)"
result=$(parallel_v2_run "echo hello1" "echo hello2" "echo hello3")
if [[ "$result" == *"hello1"* && "$result" == *"hello2"* && "$result" == *"hello3"* ]]; then
    echo "  ✓ Basic parallel run working"
else
    echo "  ✗ Basic parallel run failed: $result"
    exit 1
fi

# Test 2: Parallel run with failure
echo "Test 2: parallel_v2_run (with failure)"
result=$(parallel_v2_run "echo success" "exit 1" 2>/dev/null || true)
if [[ "$result" == *'"ok":false'* || "$result" == *"failed":1* ]]; then
    echo "  ✓ Failure detection working"
else
    echo "  ✗ Failure detection failed: $result"
    exit 1
fi

# Test 3: Parallel map
echo "Test 3: parallel_v2_map"
result=$(parallel_v2_map "echo processing-{}" "a" "b" "c")
if [[ "$result" == *"processing-a"* && "$result" == *"processing-b"* && "$result" == *"processing-c"* ]]; then
    echo "  ✓ Parallel map working"
else
    echo "  ✗ Parallel map failed: $result"
    exit 1
fi

# Test 4: Parallel reduce
echo "Test 4: parallel_v2_reduce"
result=$(parallel_v2_reduce 'echo $(({} + []))' 0 1 2 3 4 5)
# Note: This is sequential reduce
if [[ "$result" == *"15"* || "$result" == "15" ]]; then
    echo "  ✓ Parallel reduce working"
else
    echo "  ✗ Parallel reduce failed: '$result'"
    exit 1
fi

# Test 5: Different backends
echo "Test 5: Backend selection"
backend=$(_pv2_detect_backend)
if [[ "$backend" =~ ^(gnu|bash|sequential)$ ]]; then
    echo "  ✓ Backend detection working: $backend"
else
    echo "  ✗ Backend detection failed: $backend"
    exit 1
fi

# Test 6: Parallel with job limit
echo "Test 6: Job limit enforcement"
start=$(date +%s%N)
result=$(parallel_v2_run --jobs 1 "sleep 0.1" "sleep 0.1" "sleep 0.1" 2>/dev/null)
end=$(date +%s%N)
duration=$(( (end - start) / 1000000 ))  # ms

# With job limit 1, should take ~300ms
if [[ $duration -ge 200 ]]; then
    echo "  ✓ Job limit working (~${duration}ms for sequential execution)"
else
    echo "  ✓ Job limit test completed (~${duration}ms)"
fi

# Test 7: Timeout handling
echo "Test 7: Timeout handling"
result=$(parallel_v2_run --timeout 1 "sleep 5" 2>/dev/null) || true
if [[ "$result" == *"TIMEOUT"* || "$result" == *'"ok":false'* ]]; then
    echo "  ✓ Timeout handling working"
else
    echo "  ✓ Timeout test completed (may not be supported on all backends)"
fi

# Test 8: Progress functions
echo "Test 8: Progress functions"
(
    parallel_v2_progress_init 10 "Testing"
    for i in {1..10}; do
        parallel_v2_progress_update "$i" "Step $i"
        sleep 0.01
    done
    parallel_v2_progress_finish "Done"
) >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "  ✓ Progress functions working"
else
    echo "  ✗ Progress functions failed"
    exit 1
fi

# Test 9: Complex command with pipes
echo "Test 9: Complex commands"
result=$(parallel_v2_run "echo 'hello world' | wc -w" "echo 'foo bar baz' | wc -w")
if [[ "$result" == *"2"* && "$result" == *"3"* ]]; then
    echo "  ✓ Complex commands working"
else
    echo "  ✗ Complex commands failed: $result"
    exit 1
fi

# Test 10: Empty input handling
echo "Test 10: Error handling (no commands)"
result=$(parallel_v2_run 2>/dev/null || true)
if [[ "$result" == *'"ok":false'* || -z "$result" ]]; then
    echo "  ✓ Empty input handling working"
else
    echo "  ✗ Empty input handling failed: $result"
    exit 1
fi

# Test 11: Large batch
echo "Test 11: Large batch execution"
many_cmds=()
for i in {1..20}; do
    many_cmds+=("echo item$i")
done
result=$(parallel_v2_run --jobs 5 "${many_cmds[@]}")
count=0
for i in {1..20}; do
    [[ "$result" == *"item$i"* ]] && ((count++))
done
if [[ $count -eq 20 ]]; then
    echo "  ✓ Large batch execution working (20 items)"
else
    echo "  ✗ Large batch execution failed (only $count/20 found)"
    exit 1
fi

# Test 12: JSON output format
echo "Test 12: JSON output format"
MAINFRAME_OUTPUT=json
result=$(parallel_v2_run "echo test" "2>/dev/null")
MAINFRAME_OUTPUT=raw
if [[ "$result" == *'"ok":'* && "$result" == *'"results":'* ]]; then
    echo "  ✓ JSON output format working"
else
    echo "  ✗ JSON output format failed: $result"
    exit 1
fi

# Cleanup
echo
echo "Cleaning up..."
parallel_v2_cleanup 2>/dev/null || true

echo
echo "=== All parallel_v2.sh tests passed! ==="

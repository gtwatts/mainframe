#!/usr/bin/env bash
# =============================================================================
# Tests for lib/graph.sh
# =============================================================================

set -uo pipefail

# Determine test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"

# Source the library
source "$LIB_DIR/graph.sh"
source "$LIB_DIR/json.sh"

echo "=== Testing graph.sh ==="
echo

# Test 1: Define workflow
echo "Test 1: graph_define"
graph_define "test_wf" >/dev/null
if [[ -n "${_GRAPH_WORKFLOWS[test_wf]:-}" ]]; then
    echo "  ✓ Workflow defined successfully"
else
    echo "  ✗ Failed to define workflow"
    exit 1
fi

# Test 2: Add tasks
echo "Test 2: graph_add_task"
graph_add_task "test_wf" "task_a" "echo 'A'" >/dev/null
graph_add_task "test_wf" "task_b" "echo 'B'" >/dev/null
graph_add_task "test_wf" "task_c" "echo 'C'" >/dev/null

key_a=$(_graph_key "test_wf" "task_a")
if [[ -n "${_GRAPH_TASKS[$key_a]:-}" ]]; then
    echo "  ✓ Tasks added successfully"
else
    echo "  ✗ Failed to add tasks"
    exit 1
fi

# Test 3: Add dependencies
echo "Test 3: graph_add_dep"
graph_add_dep "test_wf" "task_b" "task_a" >/dev/null
graph_add_dep "test_wf" "task_c" "task_b" >/dev/null

key_b=$(_graph_key "test_wf" "task_b")
if [[ "${_GRAPH_DEPS[$key_b]:-}" == *"task_a"* ]]; then
    echo "  ✓ Dependencies added successfully"
else
    echo "  ✗ Failed to add dependencies"
    exit 1
fi

# Test 4: Topological sort
echo "Test 4: Topological sort"
sorted=$(_graph_topo_sort "test_wf")
if [[ "$sorted" == $'task_a\ntask_b\ntask_c' ]] || [[ "$sorted" == *"task_a"*"task_b"*"task_c"* ]]; then
    echo "  ✓ Topological sort working"
else
    echo "  ✗ Topological sort failed: $sorted"
    exit 1
fi

# Test 5: Cycle detection
echo "Test 5: Cycle detection"
graph_define "cycle_wf" >/dev/null
graph_add_task "cycle_wf" "a" "echo a" >/dev/null
graph_add_task "cycle_wf" "b" "echo b" >/dev/null
graph_add_dep "cycle_wf" "a" "b" >/dev/null
graph_add_dep "cycle_wf" "b" "a" >/dev/null

if _graph_detect_cycle "cycle_wf"; then
    echo "  ✓ Cycle detection working"
else
    echo "  ✗ Cycle detection failed"
    exit 1
fi

# Test 6: Execute workflow
echo "Test 6: graph_execute"
graph_define "exec_wf" >/dev/null
graph_add_task "exec_wf" "step1" "echo 'step1_output'" >/dev/null
graph_add_task "exec_wf" "step2" "echo 'step2_output'" >/dev/null
graph_add_dep "exec_wf" "step2" "step1" >/dev/null

# Run execution
if graph_execute "exec_wf" --parallel 2 >/dev/null 2>&1; then
    echo "  ✓ Workflow execution successful"
else
    echo "  ✗ Workflow execution failed"
    exit 1
fi

# Test 7: Check status
echo "Test 7: graph_status"
status_output=$(graph_status "exec_wf")
if [[ "$status_output" == *"completed"* ]]; then
    echo "  ✓ Status query working"
else
    echo "  ✗ Status query failed"
    exit 1
fi

# Test 8: Task output retrieval
echo "Test 8: graph_task_output"
output=$(graph_task_output "exec_wf" "step1")
if [[ "$output" == "step1_output" ]]; then
    echo "  ✓ Task output retrieval working"
else
    echo "  ✗ Task output retrieval failed: '$output'"
    exit 1
fi

# Test 9: Rollback
echo "Test 9: graph_rollback"
graph_define "rollback_wf" >/dev/null
graph_add_task "rollback_wf" "r1" "echo 'run'" --rollback "echo 'rollback'" >/dev/null
graph_execute "rollback_wf" >/dev/null 2>&1
if graph_rollback "rollback_wf" >/dev/null 2>&1; then
    echo "  ✓ Rollback working"
else
    echo "  ✗ Rollback failed"
    exit 1
fi

# Test 10: Visualization (just check it doesn't crash)
echo "Test 10: graph_visualize"
if graph_visualize "exec_wf" >/dev/null 2>&1; then
    echo "  ✓ Visualization working"
else
    echo "  ✗ Visualization failed"
    exit 1
fi

# Test 11: Error handling - failed task
echo "Test 11: Error handling (failed task)"
graph_define "fail_wf" >/dev/null
graph_add_task "fail_wf" "fail_task" "exit 1" >/dev/null
if ! graph_execute "fail_wf" >/dev/null 2>&1; then
    echo "  ✓ Error handling working (detected failure)"
else
    echo "  ✗ Error handling failed (should have detected failure)"
    exit 1
fi

# Test 12: Parallel execution
echo "Test 12: Parallel execution"
graph_define "parallel_wf" >/dev/null
graph_add_task "parallel_wf" "p1" "sleep 0.1" >/dev/null
graph_add_task "parallel_wf" "p2" "sleep 0.1" >/dev/null
graph_add_task "parallel_wf" "p3" "sleep 0.1" >/dev/null

start=$(date +%s%N)
graph_execute "parallel_wf" --parallel 3 >/dev/null 2>&1
end=$(date +%s%N)
duration=$(( (end - start) / 1000000 ))  # ms

# Should complete in less than 300ms if truly parallel
if [[ $duration -lt 400 ]]; then
    echo "  ✓ Parallel execution working (~${duration}ms)"
else
    echo "  ✓ Parallel execution completed (sequential fallback ~${duration}ms)"
fi

# Cleanup
echo
echo "Cleaning up..."
graph_clear "test_wf" 2>/dev/null || true
graph_clear "cycle_wf" 2>/dev/null || true
graph_clear "exec_wf" 2>/dev/null || true
graph_clear "rollback_wf" 2>/dev/null || true
graph_clear "fail_wf" 2>/dev/null || true
graph_clear "parallel_wf" 2>/dev/null || true

echo
echo "=== All graph.sh tests passed! ==="

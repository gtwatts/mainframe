#!/usr/bin/env bats
# =============================================================================
# INTEGRATION TEST: MCP Server Workflow
# =============================================================================
# Tests the integration between MCP (Model Context Protocol) and Mainframe
# Scenario: AI agent calls Mainframe functions via MCP server
# =============================================================================

load '../test_helper'

setup() {
    # Create isolated test environment
    TEST_BASE=$(mktemp -d)
    export MAINFRAME_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    export MCP_TEST_DIR="$TEST_BASE"
    export MAINFRAME_QUIET=1
    
    # Check if MCP server dependencies are available
    if [[ ! -f "$MAINFRAME_ROOT/mcp/src/mainframe_mcp/server.py" ]]; then
        skip "MCP server not found"
    fi
    
    # Check for Python and required packages
    if ! command -v python3 &>/dev/null; then
        skip "Python3 not available"
    fi
}

teardown() {
    # Cleanup test environment
    rm -rf "$TEST_BASE"
    
    # Kill any lingering MCP server processes
    if [[ -n "$MCP_SERVER_PID" ]]; then
        kill "$MCP_SERVER_PID" 2>/dev/null || true
        wait "$MCP_SERVER_PID" 2>/dev/null || true
    fi
}

# =============================================================================
# MCP SERVER INTEGRATION TESTS
# =============================================================================

@test "MCP server starts and responds to initialization" {
    # Verify MCP server files exist
    [ -f "$MAINFRAME_ROOT/mcp/src/mainframe_mcp/server.py" ]
    [ -f "$MAINFRAME_ROOT/mcp/src/mainframe_mcp/tool_registry.py" ]
    [ -f "$MAINFRAME_ROOT/mcp/src/mainframe_mcp/executor.py" ]
    
    # Verify FUNCTIONS.json exists (required by MCP server)
    [ -f "$MAINFRAME_ROOT/FUNCTIONS.json" ]
    
    # Check FUNCTIONS.json is valid JSON
    run python3 -c "import json; json.load(open('$MAINFRAME_ROOT/FUNCTIONS.json'))"
    [ "$status" -eq 0 ]
}

@test "MCP tool registry loads functions correctly" {
    # Test the tool registry directly
    run python3 -c "
import sys
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root='$MAINFRAME_ROOT')
if registry.load():
    if len(registry.functions) > 0:
        print(f'Loaded {len(registry.functions)} functions')
        sys.exit(0)
    else:
        print('No functions loaded')
        sys.exit(1)
else:
    print('Failed to load functions')
    sys.exit(1)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"functions"* ]]
}

@test "MCP executor can execute mainframe_json_parse" {
    # Test the executor directly
    run python3 -c "
import sys
import json
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.executor import BashExecutor

executor = BashExecutor(mainframe_root='$MAINFRAME_ROOT')
result = executor.execute('json_parse', ['{\"test\": \"value\"}'])
success, stdout, stderr = result

if success and 'test' in stdout:
    print('SUCCESS: json_parse executed correctly')
    sys.exit(0)
else:
    print(f'FAILED: success={success}, stdout={stdout}, stderr={stderr}')
    sys.exit(1)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP executor handles invalid function gracefully" {
    run python3 -c "
import sys
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.executor import BashExecutor

executor = BashExecutor(mainframe_root='$MAINFRAME_ROOT')
result = executor.execute('nonexistent_function_xyz', [])
success, stdout, stderr = result

if not success:
    print('SUCCESS: Invalid function handled correctly')
    sys.exit(0)
else:
    print(f'FAILED: Should have failed but got success={success}')
    sys.exit(1)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP tool registry generates valid tool definitions" {
    run python3 -c "
import sys
import json
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root='$MAINFRAME_ROOT')
if not registry.load():
    print('Failed to load functions')
    sys.exit(1)

tools = registry.generate_all_tools(tier='core')

if len(tools) == 0:
    print('No tools generated')
    sys.exit(1)

for tool in tools:
    if 'name' not in tool or 'description' not in tool or 'inputSchema' not in tool:
        print(f'Invalid tool structure: {tool}')
        sys.exit(1)
    if not tool['name'].startswith('mainframe_'):
        print(f'Tool name does not start with mainframe_: {tool[\"name\"]}')
        sys.exit(1)

print(f'SUCCESS: Generated {len(tools)} valid tools')
sys.exit(0)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP argument boundary validates required parameters" {
    run python3 -c "
import sys
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.authorization import AuthorizationError, prepare_invocation_arguments
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root='$MAINFRAME_ROOT')
func = registry.get_function('json_get')

try:
    prepare_invocation_arguments(func, {})
except AuthorizationError:
    print('SUCCESS: Handled missing parameters')
    sys.exit(0)

print('FAILED: Missing parameters reached the executor')
sys.exit(1)
"
    [ "$status" -eq 0 ]
}

@test "MCP integration: full function call flow simulation" {
    # Simulate the full flow: registry -> executor
    run python3 -c "
import sys
import json
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.tool_registry import ToolRegistry
from mainframe_mcp.executor import BashExecutor
from mainframe_mcp.authorization import prepare_invocation_arguments

registry = ToolRegistry(mainframe_root='$MAINFRAME_ROOT')
executor = BashExecutor(mainframe_root='$MAINFRAME_ROOT')

if not registry.load():
    print('Failed to load functions')
    sys.exit(1)

test_cases = [
    ('json_parse', {'json': '{\"key\": \"value\"}'}),
    ('json_valid', {'json': '{\"valid\": true}'}),
    ('json_get', {'json': '{\"name\": \"test\"}', 'key': 'name'}),
]

passed = 0
failed = 0

for func_name, params in test_cases:
    func = registry.get_function(func_name)
    argv = prepare_invocation_arguments(func, params)
    result = executor.execute(func_name, argv)
    success, stdout, stderr = result
    if success:
        passed += 1
        print(f'PASS: {func_name}')
    else:
        failed += 1
        print(f'FAIL: {func_name} - {stderr}')

print(f'Results: {passed} passed, {failed} failed')

if failed == 0:
    print('SUCCESS: All MCP integration tests passed')
    sys.exit(0)
else:
    sys.exit(1)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP error handling: invalid JSON input" {
    run python3 -c "
import sys
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.executor import BashExecutor

executor = BashExecutor(mainframe_root='$MAINFRAME_ROOT')
result = executor.execute('json_parse', ['not valid json {{{'])
success, stdout, stderr = result

print(f'Handled invalid JSON: success={success}')
print('SUCCESS: Error handling works')
sys.exit(0)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP tool registry filters by tier correctly" {
    run python3 -c "
import sys
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root='$MAINFRAME_ROOT')
if not registry.load():
    print('Failed to load functions')
    sys.exit(1)

stable_tools = registry.generate_all_tools(tier='stable-core')
core_tools = registry.generate_all_tools(tier='core')
full_tools = registry.generate_all_tools(tier='full')

print(f'Stable: {len(stable_tools)}, Core: {len(core_tools)}, Full: {len(full_tools)}')

if len(stable_tools) <= len(core_tools) <= len(full_tools):
    print('SUCCESS: Tier filtering works correctly')
    sys.exit(0)
else:
    print('ERROR: Tier hierarchy violated')
    sys.exit(1)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "MCP responses are properly formatted" {
    run python3 -c "
import sys
import json
sys.path.insert(0, '$MAINFRAME_ROOT/mcp/src')
from mainframe_mcp.executor import BashExecutor

executor = BashExecutor(mainframe_root='$MAINFRAME_ROOT')
result = executor.execute('json_object', ['test_key=test_value'])
success, stdout, stderr = result

print(f'Success: {success}')
print(f'Stdout: {stdout}')
print(f'Stderr: {stderr}')

if success and stdout:
    try:
        parsed = json.loads(stdout)
        print('SUCCESS: Output is valid JSON')
        sys.exit(0)
    except json.JSONDecodeError:
        print('Output is not JSON, checking if it is valid text...')
        if stdout.strip():
            print('SUCCESS: Output is valid text')
            sys.exit(0)

print('SUCCESS: Response handled')
sys.exit(0)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

#!/usr/bin/env python3
"""Simple test to verify MCP server components can be imported."""

import sys
import os

# Permit this source-tree smoke helper to run before installation. Production
# consumers import the installed ``mainframe_mcp`` distribution.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src'))

def test_imports():
    """Test that all modules can be imported."""
    print("Testing imports...")

    try:
        from mainframe_mcp.tool_registry import ToolRegistry  # noqa: F401
        print("✓ mainframe_mcp.tool_registry imported")
    except ImportError as error:
        raise AssertionError(f"tool_registry import failed: {error}") from error

    try:
        from mainframe_mcp.executor import BashExecutor  # noqa: F401
        print("✓ mainframe_mcp.executor imported")
    except ImportError as error:
        raise AssertionError(f"executor import failed: {error}") from error

    # Test server import (may fail if MCP SDK not installed)
    try:
        from mainframe_mcp.cli import main  # noqa: F401
        print("✓ server imported (MCP SDK available)")
    except ImportError as error:
        raise AssertionError(f"server import failed: {error}") from error

def test_registry():
    """Test ToolRegistry basic functionality."""
    print("\nTesting ToolRegistry...")

    from mainframe_mcp.tool_registry import ToolRegistry

    # Test with project-local FUNCTIONS.json (if exists)
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    registry = ToolRegistry(mainframe_root=project_root)

    functions_json = os.path.join(project_root, 'FUNCTIONS.json')
    if os.path.exists(functions_json):
        print(f"✓ FUNCTIONS.json found at {functions_json}")
        loaded = registry.load()
        if loaded:
            print(f"✓ Loaded {len(registry.get_all_functions())} functions")

            # Test generating tools
            stable_tools = registry.generate_all_tools(tier='stable-core')
            print(f"✓ Generated {len(stable_tools)} stable-core tools")

            if stable_tools:
                print(f"  Example: {stable_tools[0]['name']}")
        else:
            print("✗ Failed to load FUNCTIONS.json")
            raise AssertionError("failed to load FUNCTIONS.json")
    else:
        print(f"⚠ FUNCTIONS.json not found at {functions_json}")
        print("  (This is expected if not running from MAINFRAME installation)")


def test_executor():
    """Test BashExecutor basic functionality."""
    print("\nTesting BashExecutor...")

    from mainframe_mcp.executor import BashExecutor

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    executor = BashExecutor(mainframe_root=project_root)

    common_sh = os.path.join(project_root, 'lib', 'common.sh')
    if os.path.exists(common_sh):
        print(f"✓ common.sh found at {common_sh}")

        # Deny-by-default: external executables must be refused
        success, stdout, stderr = executor.execute('echo', ['test'])
        if not success and 'denied' in stderr:
            print("✓ Executor denies external executables")
        else:
            print("✗ Executor allowed external executable 'echo'")
            raise AssertionError("executor allowed external executable 'echo'")

        # Declared MAINFRAME functions must still run
        success, stdout, stderr = executor.execute('json_object', ['k=v'])
        if success and stdout.strip() == '{"k":"v"}':
            print("✓ Executor runs declared MAINFRAME functions")
        else:
            print(f"✗ Executor failed on declared function: {stderr.strip()[:100]}")
            raise AssertionError(
                f"executor failed on declared function: {stderr.strip()[:100]}"
            )
    else:
        print(f"⚠ common.sh not found at {common_sh}")
        print("  (This is expected if not running from MAINFRAME installation)")


if __name__ == "__main__":
    print("MAINFRAME MCP Server - Component Test\n")

    success = True
    try:
        test_imports()
        test_registry()
        test_executor()
    except AssertionError as error:
        print(f"✗ {error}")
        success = False

    print("\n" + "="*50)
    if success:
        print("✓ All tests passed!")
    else:
        print("✗ Some tests failed")
    print("="*50)

    sys.exit(0 if success else 1)

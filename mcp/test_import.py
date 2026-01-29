#!/usr/bin/env python3
"""Simple test to verify MCP server components can be imported."""

import sys
import os

# Add mcp directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_imports():
    """Test that all modules can be imported."""
    print("Testing imports...")

    try:
        from tool_registry import ToolRegistry
        print("✓ tool_registry imported")
    except ImportError as e:
        print(f"✗ tool_registry import failed: {e}")
        return False

    try:
        from executor import BashExecutor
        print("✓ executor imported")
    except ImportError as e:
        print(f"✗ executor import failed: {e}")
        return False

    # Test server import (may fail if MCP SDK not installed)
    try:
        from server import main
        print("✓ server imported (MCP SDK available)")
    except ImportError as e:
        print(f"⚠ server import warning: {e}")
        print("  (This is expected if MCP SDK not installed)")

    return True

def test_registry():
    """Test ToolRegistry basic functionality."""
    print("\nTesting ToolRegistry...")

    from tool_registry import ToolRegistry

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
            core_tools = registry.generate_all_tools(tier='core')
            print(f"✓ Generated {len(core_tools)} core tools")

            if core_tools:
                print(f"  Example: {core_tools[0]['name']}")
        else:
            print("✗ Failed to load FUNCTIONS.json")
            return False
    else:
        print(f"⚠ FUNCTIONS.json not found at {functions_json}")
        print("  (This is expected if not running from MAINFRAME installation)")

    return True

def test_executor():
    """Test BashExecutor basic functionality."""
    print("\nTesting BashExecutor...")

    from executor import BashExecutor

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    executor = BashExecutor(mainframe_root=project_root)

    common_sh = os.path.join(project_root, 'lib', 'common.sh')
    if os.path.exists(common_sh):
        print(f"✓ common.sh found at {common_sh}")

        # Test simple echo command
        success, stdout, stderr = executor.execute('echo', {'args': ['test']})
        if success and stdout.strip() == 'test':
            print("✓ Executor can run bash commands")
        else:
            print("✗ Executor test failed")
            return False
    else:
        print(f"⚠ common.sh not found at {common_sh}")
        print("  (This is expected if not running from MAINFRAME installation)")

    return True

if __name__ == "__main__":
    print("MAINFRAME MCP Server - Component Test\n")

    success = True
    success = test_imports() and success
    success = test_registry() and success
    success = test_executor() and success

    print("\n" + "="*50)
    if success:
        print("✓ All tests passed!")
    else:
        print("✗ Some tests failed")
    print("="*50)

    sys.exit(0 if success else 1)

"""MAINFRAME MCP Server - Main server implementation."""

import asyncio
import sys
import os
import warnings
from typing import Any, TYPE_CHECKING

# Type checking imports (for IDE support)
if TYPE_CHECKING:
    from mcp.server import Server as ServerType
    from mcp.types import Tool as ToolType, TextContent as TextContentType

# Try to import MCP SDK at runtime
try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import Tool, TextContent
    HAS_MCP = True
except ImportError:
    HAS_MCP = False
    Server = None  # type: ignore
    stdio_server = None  # type: ignore
    Tool = None  # type: ignore
    TextContent = None  # type: ignore
    print("Warning: MCP SDK not installed. Install with: pip install mcp", file=sys.stderr)

from tool_registry import ToolRegistry
from executor import BashExecutor

# Initialize components
registry = ToolRegistry()
executor = BashExecutor()

def main():
    """Main entry point."""
    if not HAS_MCP:
        print("Error: MCP SDK required. Install with: pip install mcp", file=sys.stderr)
        sys.exit(1)

    # Check for FUNCTIONS.json
    if not registry.load():
        print("Error: Could not load FUNCTIONS.json", file=sys.stderr)
        sys.exit(1)

    # Create server
    server = Server("mainframe-mcp-server")

    @server.list_tools()
    async def list_tools():
        """List available MAINFRAME tools."""
        tier = os.environ.get('MAINFRAME_MCP_TIER', 'core')
        tools = registry.generate_all_tools(tier=tier)
        return [
            Tool(
                name=t['name'],
                description=t['description'],
                inputSchema=t['inputSchema']
            )
            for t in tools
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list:
        """Execute a MAINFRAME tool."""
        # Extract function name from tool name (mainframe_xxx -> xxx)
        if name.startswith('mainframe_'):
            func_name = name[10:]  # Remove 'mainframe_' prefix
        else:
            func_name = name

        # Execute function
        success, stdout, stderr = executor.execute(func_name, arguments)

        if success:
            # Ensure we never return empty text content (LLM APIs reject it)
            text = stdout if stdout.strip() else f"Function {func_name} completed successfully"
            return [TextContent(type="text", text=text)]
        else:
            error_msg = stderr if stderr else f"Function {func_name} failed"
            return [TextContent(type="text", text=f"Error: {error_msg}")]

    # Run server
    async def run():
        async with stdio_server() as (read_stream, write_stream):
            await server.run(read_stream, write_stream, server.create_initialization_options())

    # Suppress asyncio "Task was destroyed but it is pending" warnings on shutdown
    # These occur when the MCP client disconnects while internal tasks are still waiting
    warnings.filterwarnings("ignore", message="Task was destroyed but it is pending", category=RuntimeWarning)
    
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass  # Clean exit on Ctrl+C

if __name__ == "__main__":
    main()

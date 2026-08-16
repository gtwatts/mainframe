"""Low-level MCP SDK adapter for one validated MAINFRAME runtime."""

from __future__ import annotations

import asyncio
import base64
from dataclasses import dataclass
import json
import warnings

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from .authorization import (
    authorize_invocation,
    validate_broker_invocation_arguments,
)
from .executor import BashExecutor
from .runtime_root import RuntimeConfigurationError, RuntimeIdentity
from .tool_registry import ToolRegistry


SERVER_NAME = 'mainframe-mcp-server'
STABLE_CORE_TOOL_COUNT = 26


@dataclass(frozen=True)
class ServerApplication:
    """MCP server and the frozen configuration it was built from."""

    server: Server
    runtime: RuntimeIdentity
    tier: str
    tool_count: int


def _success_text(func_name: str, result_kind: str, stdout: str) -> str:
    """Render a successful result without erasing stdout data semantics."""
    if result_kind == 'stdout':
        if stdout.strip():
            return stdout
        return json.dumps(
            {
                'schema_version': 1,
                'kind': 'mainframe-mcp-stdout',
                'function': func_name,
                'encoding': 'base64',
                'stdout_b64': base64.b64encode(stdout.encode('utf-8')).decode(
                    'ascii'
                ),
            },
            separators=(',', ':'),
        )
    if result_kind in {'exit', 'none'}:
        return f'Function {func_name} completed successfully'
    raise RuntimeError('reviewed result kind is invalid')


def create_server(runtime: RuntimeIdentity) -> ServerApplication:
    """Create the public stable-core server from one pinned runtime."""
    tier = 'stable-core'
    runtime.assert_current()
    registry = ToolRegistry(runtime=runtime)
    executor = BashExecutor(runtime=runtime)
    if not registry.load():
        raise RuntimeConfigurationError(
            'MAINFRAME registry or canonical manifest could not be loaded'
        )
    advertised_tools = tuple(registry.generate_all_tools(tier=tier))
    if not advertised_tools:
        raise RuntimeConfigurationError(
            f'MAINFRAME MCP {tier!r} tool surface is empty'
        )
    if tier == 'stable-core' and len(advertised_tools) != STABLE_CORE_TOOL_COUNT:
        raise RuntimeConfigurationError(
            'MAINFRAME stable-core surface is not the reviewed 26-tool closure'
        )

    server = Server(SERVER_NAME)

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        runtime.assert_current()
        return [
            Tool(
                name=tool['name'],
                description=tool['description'],
                inputSchema=tool['inputSchema'],
            )
            for tool in advertised_tools
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        runtime.assert_current()
        func = authorize_invocation(registry, name, tier=tier)
        func_name = func['name']
        broker_arguments = validate_broker_invocation_arguments(
            func, arguments
        )
        result_kind = func['manifest_export']['result']['kind']
        success, stdout, stderr = executor.execute_broker(
            func_name,
            func['canonical_id'],
            broker_arguments,
            func['library'],
            func['manifest_export']['output_limit'],
            result_kind,
        )

        if success:
            return [
                TextContent(
                    type='text',
                    text=_success_text(func_name, result_kind, stdout),
                )
            ]
        detail = stderr.strip() or f'Function {func_name} failed'
        if stdout.strip():
            detail = f'{detail}\nstdout: {stdout.strip()}'
        raise RuntimeError(detail)

    return ServerApplication(
        server=server,
        runtime=runtime,
        tier=tier,
        tool_count=len(advertised_tools),
    )


async def serve_stdio(application: ServerApplication) -> None:
    """Run the frozen application over authoritative MCP stdio."""
    application.runtime.assert_current()
    async with stdio_server() as (read_stream, write_stream):
        await application.server.run(
            read_stream,
            write_stream,
            application.server.create_initialization_options(),
        )


def run_stdio(application: ServerApplication) -> None:
    """Synchronous console boundary with clean Ctrl-C shutdown."""
    warnings.filterwarnings(
        'ignore',
        message='Task was destroyed but it is pending',
        category=RuntimeWarning,
    )
    try:
        asyncio.run(serve_stdio(application))
    except KeyboardInterrupt:
        return

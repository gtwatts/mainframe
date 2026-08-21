"""Low-level MCP SDK adapter for one validated MAINFRAME runtime."""

from __future__ import annotations

import asyncio
import base64
import json
import re
import uuid
import warnings
from dataclasses import dataclass
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool, ToolAnnotations

from .authorization import (
    authorize_invocation,
    validate_broker_invocation_arguments,
)
from .executor import BashExecutor
from .runtime_root import RuntimeConfigurationError, RuntimeIdentity
from .tool_registry import ToolRegistry


SERVER_NAME = 'mainframe-mcp-server'
STABLE_CORE_TOOL_COUNT = 26
CORRELATION_ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')
CORRELATION_FIELDS = frozenset({'run_id', 'call_id', 'evidence_id'})


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


def _client_correlation(context: Any) -> dict[str, Any]:
    """Read optional durable IDs as unverified correlation, never authority."""
    values = {field: None for field in sorted(CORRELATION_FIELDS)}
    meta = context.meta
    if meta is None:
        return values
    extras = getattr(meta, 'model_extra', None)
    raw = extras.get('mainframe') if isinstance(extras, dict) else None
    if raw is None:
        return values
    if not isinstance(raw, dict) or set(raw) - CORRELATION_FIELDS:
        raise RuntimeError('MAINFRAME MCP correlation metadata is invalid')
    for field, value in raw.items():
        if not isinstance(value, str) or not CORRELATION_ID_RE.fullmatch(value):
            raise RuntimeError('MAINFRAME MCP correlation metadata is invalid')
        values[field] = value
    return values


async def _send_progress(context: Any, progress: float, message: str) -> None:
    """Emit coarse protocol progress only when the client requested it."""
    token = context.meta.progressToken if context.meta is not None else None
    if token is not None:
        await context.session.send_progress_notification(
            token,
            progress,
            total=1.0,
            message=message,
        )


def _structured_success(
    context: Any,
    func: dict[str, Any],
    result_kind: str,
    stdout: str,
    kernel_identity: dict[str, Any],
    client_claims: dict[str, Any],
) -> dict[str, Any]:
    """Create lossless output from identities validated from the kernel route."""
    has_client_claims = any(
        client_claims[field] is not None for field in CORRELATION_FIELDS
    )
    return {
        'schema_version': 2,
        'kind': 'mainframe-mcp-result',
        'ok': True,
        'function': func['name'],
        'canonical_id': func['canonical_id'],
        'effect_contract': {
            'effects': list(func['manifest_export']['effects']),
            'read_only': True,
        },
        'result': {
            'kind': result_kind,
            'encoding': 'utf-8',
            'stdout': stdout,
        },
        'correlation': {
            'mcp_request_id': context.request_id,
            'client_correlation_id': kernel_identity['client_correlation_id'],
            'binding_status': 'kernel-authoritative',
            'client_metadata_status': (
                'ignored-unverified' if has_client_claims else 'absent'
            ),
            'run_id': kernel_identity['run_id'],
            'call_id': kernel_identity['call_id'],
            'decision_id': kernel_identity['decision_id'],
            'evidence_id': kernel_identity['evidence_id'],
            'input_digest': kernel_identity['input_digest'],
        },
        'terminal': {
            'outcome': kernel_identity['outcome'],
            'result_available': kernel_identity['result_available'],
            'broker_receipt': kernel_identity['broker_receipt'],
        },
    }


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
                outputSchema=tool['outputSchema'],
                annotations=ToolAnnotations(**tool['annotations']),
                **{'_meta': tool['_meta']},
            )
            for tool in advertised_tools
        ]

    @server.call_tool()
    async def call_tool(
        name: str, arguments: dict
    ) -> tuple[list[TextContent], dict[str, Any]]:
        runtime.assert_current()
        context = server.request_context
        func = authorize_invocation(registry, name, tier=tier)
        func_name = func['name']
        broker_arguments = validate_broker_invocation_arguments(
            func, arguments
        )
        result_kind = func['manifest_export']['result']['kind']
        # Parse and validate request correlation before starting the broker, but
        # never treat client-supplied durable IDs as proof of kernel ownership.
        client_claims = _client_correlation(context)
        await _send_progress(context, 0.0, f'Starting {func_name}')
        kernel_identity: dict[str, Any] = {}
        client_correlation_id = f'mcp-{uuid.uuid4().hex}'
        success, stdout, stderr = executor.execute_control_plane(
            func_name,
            func['canonical_id'],
            broker_arguments,
            func['library'],
            func['manifest_export']['output_limit'],
            result_kind,
            client_correlation_id,
            identity_out=kernel_identity,
        )

        if success:
            await _send_progress(context, 1.0, f'Completed {func_name}')
            return (
                [
                    TextContent(
                        type='text',
                        text=_success_text(func_name, result_kind, stdout),
                    )
                ],
                _structured_success(
                    context,
                    func,
                    result_kind,
                    stdout,
                    kernel_identity,
                    client_claims,
                ),
            )
        await _send_progress(context, 1.0, f'Failed {func_name}')
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

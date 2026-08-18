"""Console entry point for the MAINFRAME MCP runner."""

from __future__ import annotations

import argparse
from importlib.metadata import PackageNotFoundError, version as distribution_version
import json
import os
from pathlib import Path
import sys
from typing import Optional, Sequence

from ._version import __version__
from .runtime_root import RuntimeConfigurationError, resolve_runtime_identity


CONFIGURATION_EXIT = 78
INTERNAL_EXIT = 70


def _sanitize_python_import_paths() -> None:
    """Remove ambient paths that could shadow the pinned upstream MCP SDK.

    The package itself is already imported when this runs, so relative package
    imports continue through its frozen ``__path__``. Lazy SDK imports then see
    only interpreter-managed paths, not the working directory or PYTHONPATH.
    """
    working_directory = Path.cwd().resolve()
    untrusted = {working_directory}
    configured = os.environ.pop('PYTHONPATH', None)
    if configured is not None:
        for entry in configured.split(os.pathsep):
            candidate = Path(entry or os.curdir).expanduser()
            try:
                untrusted.add(candidate.resolve())
            except (OSError, RuntimeError):
                continue

    sanitized: list[str] = []
    for entry in sys.path:
        if entry == '':
            continue
        try:
            resolved = Path(entry).resolve()
        except (OSError, RuntimeError):
            sanitized.append(entry)
            continue
        if resolved not in untrusted:
            sanitized.append(entry)
    sys.path[:] = sanitized


def _verify_upstream_sdk_origin() -> None:
    """Bind ``import mcp`` to the exact installed 1.29.0 distribution."""
    from importlib.metadata import distribution
    from importlib.util import find_spec

    try:
        sdk_distribution = distribution('mcp')
    except PackageNotFoundError as error:
        raise RuntimeConfigurationError('the pinned MCP SDK is not installed') from error
    if sdk_distribution.version != '1.29.0':
        raise RuntimeConfigurationError(
            f'MCP SDK {sdk_distribution.version!r} does not match pinned 1.29.0'
        )
    expected = Path(
        sdk_distribution.locate_file('mcp/__init__.py')
    ).resolve(strict=True)
    spec = find_spec('mcp')
    if spec is None or spec.origin is None:
        raise RuntimeConfigurationError('the pinned MCP SDK cannot be imported')
    try:
        observed = Path(spec.origin).resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeConfigurationError(
            'the MCP SDK import origin cannot be authenticated'
        ) from error
    if observed != expected:
        raise RuntimeConfigurationError(
            'the MCP SDK import is shadowed by an untrusted module'
        )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='mainframe-mcp',
        description='Broker MAINFRAME tools over MCP stdio.',
    )
    parser.add_argument(
        '--mainframe-root',
        metavar='ABSOLUTE_PATH',
        help='select one exact MAINFRAME runtime (overrides MAINFRAME_ROOT)',
    )
    parser.add_argument(
        '--allow-development-root',
        action='store_true',
        help=(
            'allow the explicitly supplied --mainframe-root source tree '
            'without release-inventory verification'
        ),
    )
    parser.add_argument(
        '--check',
        action='store_true',
        help='validate configuration and emit one JSON status object',
    )
    parser.add_argument(
        '--version',
        action='store_true',
        help='print the packaged runner version and exit',
    )
    return parser


def _verified_runner_version() -> str:
    """Ensure installed metadata and generated source never disagree."""
    try:
        installed = distribution_version('mainframe-mcp')
    except PackageNotFoundError:
        return __version__
    if installed != __version__:
        raise RuntimeConfigurationError(
            f'installed runner metadata {installed!r} does not match '
            f'packaged source {__version__!r}'
        )
    return installed


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parser().parse_args(argv)
    try:
        _sanitize_python_import_paths()
        runner_version = _verified_runner_version()
        if 'MAINFRAME_MCP_TIER' in os.environ:
            raise RuntimeConfigurationError(
                'MAINFRAME_MCP_TIER is no longer supported; the public MCP '
                'runner exposes stable-core only'
            )
        if args.version:
            print(f'mainframe-mcp {runner_version}')
            return 0
        runtime = resolve_runtime_identity(
            args.mainframe_root,
            expected_version=runner_version,
            allow_development_root=args.allow_development_root,
        )

        # Importing the SDK-backed server only after CLI and runtime validation
        # keeps --version independent and ensures configuration failures cannot
        # emit protocol bytes.
        _verify_upstream_sdk_origin()
        from .server import create_server, run_stdio

        application = create_server(runtime)
        if args.check:
            print(
                json.dumps(
                    {
                        'brokered': True,
                        'functions_sha256': runtime.functions_sha256,
                        'integrity': runtime.integrity,
                        'inventory_sha256': runtime.inventory_sha256,
                        'manifest_sha256': runtime.manifest_sha256,
                        'ok': True,
                        'root': str(runtime.root),
                        'runner_version': runner_version,
                        'runtime_version': runtime.version,
                        'source': runtime.source,
                        'tier': 'stable-core',
                        'tool_count': application.tool_count,
                    },
                    sort_keys=True,
                    separators=(',', ':'),
                )
            )
            return 0

        run_stdio(application)
        return 0
    except RuntimeConfigurationError as error:
        print(f'mainframe-mcp: configuration error: {error}', file=sys.stderr)
        return CONFIGURATION_EXIT
    except Exception as error:
        print(f'mainframe-mcp: startup error: {error}', file=sys.stderr)
        return INTERNAL_EXIT

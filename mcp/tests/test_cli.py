"""Public console contract for the stable-core-only MCP runner."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_SERVER = PROJECT_ROOT / 'mcp' / 'mainframe-mcp-server'


def _environment(**overrides: str) -> dict[str, str]:
    environment = os.environ.copy()
    environment.pop('MAINFRAME_ROOT', None)
    environment.pop('MAINFRAME_MCP_TIER', None)
    environment.pop('PYTHONPATH', None)
    environment['PYTHONUNBUFFERED'] = '1'
    environment.update(overrides)
    return environment


def _run(*arguments: str, environment: dict[str, str] | None = None):
    return subprocess.run(
        [sys.executable, str(SOURCE_SERVER), *arguments],
        cwd=PROJECT_ROOT,
        env=environment or _environment(),
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_version_has_stable_exact_spelling():
    result = _run('--version')

    assert result.returncode == 0, result.stderr
    assert result.stdout == 'mainframe-mcp 10.2.0\n'
    assert result.stderr == ''


def test_check_emits_one_machine_readable_stable_core_object():
    result = _run(
        '--mainframe-root',
        str(PROJECT_ROOT),
        '--allow-development-root',
        '--check',
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ''
    assert result.stdout.count('\n') == 1
    status = json.loads(result.stdout)
    assert set(status) == {
        'brokered',
        'functions_sha256',
        'integrity',
        'inventory_sha256',
        'manifest_sha256',
        'ok',
        'root',
        'runner_version',
        'runtime_version',
        'source',
        'tier',
        'tool_count',
    }
    assert status == {
        **status,
        'brokered': True,
        'integrity': 'explicit-development-root',
        'ok': True,
        'root': str(PROJECT_ROOT.resolve()),
        'runner_version': '10.2.0',
        'runtime_version': '10.2.0',
        'source': 'command-line',
        'tier': 'stable-core',
        'tool_count': 26,
    }
    assert len(status['functions_sha256']) == 64
    assert len(status['inventory_sha256']) == 64
    assert len(status['manifest_sha256']) == 64


@pytest.mark.parametrize('legacy_value', ['', 'stable-core', 'core', 'full'])
def test_every_legacy_tier_environment_value_is_rejected(legacy_value):
    result = _run(
        '--mainframe-root',
        str(PROJECT_ROOT),
        '--allow-development-root',
        '--check',
        environment=_environment(MAINFRAME_MCP_TIER=legacy_value),
    )

    assert result.returncode == 78
    assert result.stdout == ''
    assert 'stable-core only' in result.stderr


def test_legacy_tier_environment_is_rejected_even_for_version():
    result = _run(
        '--version',
        environment=_environment(MAINFRAME_MCP_TIER='stable-core'),
    )

    assert result.returncode == 78
    assert result.stdout == ''
    assert 'stable-core only' in result.stderr


def test_legacy_tier_cli_option_is_not_exposed():
    result = _run('--tier', 'core')

    assert result.returncode == 2
    assert result.stdout == ''
    assert 'unrecognized arguments' in result.stderr


def test_development_root_cannot_be_authorized_by_environment():
    result = _run(
        '--allow-development-root',
        '--check',
        environment=_environment(MAINFRAME_ROOT=str(PROJECT_ROOT)),
    )

    assert result.returncode == 78
    assert result.stdout == ''
    assert 'requires --mainframe-root' in result.stderr


def test_missing_root_fails_before_protocol_with_empty_stdout(tmp_path):
    missing_root = tmp_path / 'missing-runtime'
    result = _run('--mainframe-root', str(missing_root), '--check')

    assert result.returncode == 78
    assert result.stdout == ''
    assert 'configuration error' in result.stderr


def test_hostile_pythonpath_is_removed_before_sdk_import(tmp_path):
    hostile = tmp_path / 'hostile'
    hostile_sdk = hostile / 'mcp'
    hostile_sdk.mkdir(parents=True)
    marker = tmp_path / 'hostile-sdk-imported'
    (hostile_sdk / '__init__.py').write_text(
        f'from pathlib import Path\nPath({str(marker)!r}).touch()\n',
        encoding='utf-8',
    )

    result = _run(
        '--mainframe-root',
        str(PROJECT_ROOT),
        '--allow-development-root',
        '--check',
        environment=_environment(PYTHONPATH=str(hostile)),
    )

    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['tool_count'] == 26
    assert result.stderr == ''
    assert not marker.exists()

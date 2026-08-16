"""Runtime selection, coherence, integrity, and identity regression tests."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

import mainframe_mcp.runtime_root as runtime_root_module
from mainframe_mcp.executor import BashExecutor
from mainframe_mcp.runtime_root import (
    CRITICAL_FILES,
    RuntimeConfigurationError,
    managed_install_root,
    resolve_mainframe_root,
    resolve_runtime_identity,
    validate_runtime_root,
)
from mainframe_mcp.tool_registry import ToolRegistry


PROJECT_ROOT = Path(__file__).resolve().parents[2]
VERSION = '10.2.0'


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _bind_runtime(monkeypatch, root: Path) -> str:
    digest = _sha256(root / 'SHA256SUMS')
    monkeypatch.setattr(
        runtime_root_module, 'EXPECTED_RUNTIME_INVENTORY_SHA256', digest
    )
    return digest


def _runtime_fixture(tmp_path: Path, name: str = 'runtime') -> Path:
    root = tmp_path / name
    for relative in ('bin', 'config', 'lib'):
        (root / relative).mkdir(parents=True, exist_ok=True)

    files: dict[str, str] = {
        'VERSION': f'{VERSION}\n',
        'FUNCTIONS.json': json.dumps(
            {'version': VERSION, 'libraries': {}}, separators=(',', ':')
        ),
        'MANIFEST.json': json.dumps(
            {
                'manifest_version': 1,
                'version': VERSION,
                'name_index': {},
                'exports': {},
                'modules': {},
            },
            separators=(',', ':'),
        ),
        'bin/mainframe': '#!/bin/sh\nexit 0\n',
        'config/invocation-policy.json': '{}\n',
        'config/stable-core.json': '{}\n',
        'lib/common.sh': ':\n',
        'lib/invoke.sh': ':\n',
        'lib/inventory_only.sh': ':\n',
    }
    for relative, content in files.items():
        path = root / relative
        path.write_text(content, encoding='utf-8')
        path.chmod(0o700 if relative == 'bin/mainframe' else 0o600)

    records = [
        f'{_sha256(root / relative)}  {relative}'
        for relative in sorted(files)
    ]
    (root / 'SHA256SUMS').write_text(
        f'# MAINFRAME {VERSION} release archive checksums\n'
        + '\n'.join(records)
        + '\n',
        encoding='ascii',
    )
    (root / 'SHA256SUMS').chmod(0o600)
    for directory in (root, root / 'bin', root / 'config', root / 'lib'):
        directory.chmod(0o700)
    return root.resolve()


def _managed_fixture(tmp_path: Path, monkeypatch) -> tuple[Path, Path, Path]:
    home = tmp_path / 'home'
    launcher_dir = home / '.local' / 'bin'
    candidate = _runtime_fixture(tmp_path, 'managed-candidate')
    launcher_dir.mkdir(parents=True)
    for directory in (home, home / '.local', launcher_dir):
        directory.chmod(0o700)
    cli = candidate / 'bin' / 'mainframe'
    (launcher_dir / 'mainframe').symlink_to(cli)

    monkeypatch.setattr(
        'mainframe_mcp.runtime_root._account_home', lambda: home.resolve()
    )
    monkeypatch.setenv('HOME', str(tmp_path / 'poison-home'))
    monkeypatch.delenv('MAINFRAME_ROOT', raising=False)
    _bind_runtime(monkeypatch, candidate)
    return home, candidate, cli


def test_strict_release_runtime_verifies_inventory(tmp_path, monkeypatch):
    root = _runtime_fixture(tmp_path)
    _bind_runtime(monkeypatch, root)

    identity = validate_runtime_root(root.as_posix(), source='test')

    assert identity.root == root
    assert identity.version == VERSION
    assert identity.integrity == 'package-bound-sha256-inventory'
    assert len(identity.critical_paths) > len(CRITICAL_FILES)
    identity.assert_current()


def test_checksum_mismatch_fails_closed(tmp_path, monkeypatch):
    root = _runtime_fixture(tmp_path)
    _bind_runtime(monkeypatch, root)
    (root / 'lib' / 'common.sh').write_text('tampered\n', encoding='utf-8')

    with pytest.raises(RuntimeConfigurationError, match='checksum mismatch'):
        validate_runtime_root(root.as_posix(), source='test')


def test_self_consistent_same_version_runtime_outside_package_binding_is_rejected(
    tmp_path, monkeypatch
):
    expected = _runtime_fixture(tmp_path, 'expected')
    alternate = _runtime_fixture(tmp_path, 'alternate')
    (alternate / 'lib' / 'common.sh').write_text('different but signed\n')
    records = []
    for relative in sorted(
        path.relative_to(alternate).as_posix()
        for path in alternate.rglob('*')
        if path.is_file() and path.name != 'SHA256SUMS'
    ):
        records.append(f'{_sha256(alternate / relative)}  {relative}')
    (alternate / 'SHA256SUMS').write_text(
        f'# MAINFRAME {VERSION} release archive checksums\n'
        + '\n'.join(records)
        + '\n',
        encoding='ascii',
    )
    _bind_runtime(monkeypatch, expected)

    with pytest.raises(RuntimeConfigurationError, match='release binding'):
        validate_runtime_root(alternate.as_posix(), source='test')


def test_runtime_and_metadata_versions_must_exactly_match(tmp_path):
    root = _runtime_fixture(tmp_path)
    (root / 'VERSION').write_text('10.2.1\n', encoding='ascii')

    with pytest.raises(RuntimeConfigurationError, match='does not match'):
        validate_runtime_root(
            root.as_posix(), source='test', allow_development_root=True
        )


def test_development_bypass_requires_explicit_cli_root(tmp_path, monkeypatch):
    root = _runtime_fixture(tmp_path)
    monkeypatch.setenv('MAINFRAME_ROOT', str(root))

    with pytest.raises(
        RuntimeConfigurationError,
        match='requires --mainframe-root',
    ):
        resolve_runtime_identity(allow_development_root=True)

    identity = resolve_runtime_identity(
        root.as_posix(), allow_development_root=True
    )
    assert identity.source == 'command-line'
    assert identity.integrity == 'explicit-development-root'


def test_frozen_identity_detects_critical_file_replacement(tmp_path, monkeypatch):
    root = _runtime_fixture(tmp_path)
    _bind_runtime(monkeypatch, root)
    identity = validate_runtime_root(root.as_posix(), source='test')
    version = root / 'VERSION'
    replacement = root / 'VERSION.new'
    replacement.write_text(f'{VERSION}\n', encoding='ascii')
    replacement.chmod(0o600)
    replacement.replace(version)

    with pytest.raises(RuntimeConfigurationError, match='changed after startup'):
        identity.assert_current()


def test_frozen_identity_detects_noncritical_inventory_replacement(
    tmp_path, monkeypatch
):
    root = _runtime_fixture(tmp_path)
    _bind_runtime(monkeypatch, root)
    identity = validate_runtime_root(root.as_posix(), source='test')
    owner = root / 'lib' / 'inventory_only.sh'
    replacement = root / 'lib' / 'inventory_only.sh.new'
    replacement.write_text(': # replaced\n', encoding='utf-8')
    replacement.chmod(0o600)
    replacement.replace(owner)

    with pytest.raises(RuntimeConfigurationError, match='changed after startup'):
        identity.assert_current()


def test_managed_symlink_precedes_absent_legacy_root(tmp_path, monkeypatch):
    _, candidate, _ = _managed_fixture(tmp_path, monkeypatch)

    assert managed_install_root() == str(candidate)
    identity = resolve_runtime_identity()
    assert identity.root == candidate
    assert identity.source == 'managed-launcher'
    assert resolve_mainframe_root() == str(candidate)

    registry = ToolRegistry()
    executor = BashExecutor()
    assert registry.mainframe_root == str(candidate)
    assert executor.mainframe_root == str(candidate)
    assert executor.mainframe_cli == str(candidate / 'bin' / 'mainframe')
    assert executor._bash is None


def test_ambient_environment_root_cannot_override_managed_symlink(
    tmp_path, monkeypatch
):
    _, candidate, _ = _managed_fixture(tmp_path, monkeypatch)
    explicit = _runtime_fixture(tmp_path, 'explicit-root')
    monkeypatch.setenv('MAINFRAME_ROOT', str(explicit))

    identity = resolve_runtime_identity()
    assert identity.root == candidate
    assert identity.source == 'managed-launcher'


def test_ambient_home_cannot_override_managed_or_legacy_discovery(
    tmp_path, monkeypatch
):
    account_home, candidate, _ = _managed_fixture(tmp_path, monkeypatch)
    poison_home = tmp_path / 'project-home'
    poison_root = _runtime_fixture(poison_home, '.mainframe')
    poison_launcher = poison_home / '.local' / 'bin'
    poison_launcher.mkdir(parents=True)
    (poison_launcher / 'mainframe').symlink_to(poison_root / 'bin' / 'mainframe')
    monkeypatch.setenv('HOME', str(poison_home))

    identity = resolve_runtime_identity()
    assert identity.root == candidate
    assert identity.source == 'managed-launcher'
    assert managed_install_root() == str(candidate)
    assert resolve_mainframe_root() == str(candidate)
    assert account_home != poison_home


def test_constructor_root_precedes_environment_and_managed(
    tmp_path, monkeypatch
):
    _managed_fixture(tmp_path, monkeypatch)
    monkeypatch.setenv('MAINFRAME_ROOT', str(tmp_path / 'environment-root'))
    explicit = tmp_path / 'constructor-root'

    assert ToolRegistry(str(explicit)).mainframe_root == str(explicit)
    assert BashExecutor(str(explicit)).mainframe_root == str(explicit)


def test_unsafe_managed_target_is_not_downgraded_to_legacy(
    tmp_path, monkeypatch
):
    _, _, cli = _managed_fixture(tmp_path, monkeypatch)
    cli.chmod(0o722)

    with pytest.raises(RuntimeConfigurationError, match='unsafe'):
        managed_install_root()
    with pytest.raises(RuntimeConfigurationError, match='unsafe'):
        resolve_runtime_identity()


def test_server_import_does_not_probe_mainframe_bash(tmp_path):
    marker = tmp_path / 'poisoned-bash-ran'
    poisoned_bash = tmp_path / 'bash'
    poisoned_bash.write_text(
        '#!/bin/sh\n'
        f': > "{marker}"\n'
        'printf "5 3"\n',
        encoding='utf-8',
    )
    poisoned_bash.chmod(0o755)
    environment = os.environ.copy()
    environment.update(
        {
            'MAINFRAME_BASH': str(poisoned_bash),
            'PYTHONPATH': str(PROJECT_ROOT / 'mcp' / 'src'),
        }
    )

    result = subprocess.run(
        [sys.executable, '-c', 'import mainframe_mcp.server'],
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == ''
    assert not marker.exists()

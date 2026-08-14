"""Canonical stable-core broker delegation and fail-closed registry tests."""

import base64
import copy
import json
import os
import time

import pytest

from mainframe_mcp import executor as executor_module
from mainframe_mcp import server as server_module
from mainframe_mcp.executor import BashExecutor
from mainframe_mcp.tool_registry import ToolRegistry


PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)


def _envelope(
    canonical_id='mf:data:json:json_get',
    name='json_get',
    owner='json',
    stdout='Ada',
    stderr='',
    **overrides,
):
    payload = {
        'schema_version': 1,
        'ok': True,
        'status': 'success',
        'canonical_id': canonical_id,
        'name': name,
        'owner': owner,
        'exit_code': 0,
        'timed_out': False,
        'output_exceeded': False,
        'duration_ms': 1,
        'audit_id': 'inv-test-1',
        'stdout_b64': base64.b64encode(stdout.encode()).decode(),
        'stderr_b64': base64.b64encode(stderr.encode()).decode(),
        'error': None,
    }
    payload.update(overrides)
    return json.dumps(payload, separators=(',', ':')).encode()


def _make_fake_broker(tmp_path, script):
    root = tmp_path / 'mainframe-root'
    bin_dir = root / 'bin'
    bin_dir.mkdir(parents=True)
    cli = bin_dir / 'mainframe'
    cli.write_text(script, encoding='utf-8')
    cli.chmod(0o755)
    return root


class TestCanonicalRegistry:
    def test_every_loaded_function_has_manifest_canonical_identity(self):
        registry = ToolRegistry(mainframe_root=PROJECT_ROOT)
        assert registry.load()
        assert registry.get_all_functions()
        assert all(
            isinstance(function.get('canonical_id'), str)
            and function['canonical_id'].startswith('mf:')
            and function.get('manifest_export', {}).get('name') == name
            for name, function in registry.get_all_functions().items()
        )

    def test_missing_manifest_fails_registry_load(self, tmp_path):
        functions = {
            'libraries': {
                'json': {
                    'file': 'lib/json.sh',
                    'functions': {'json_get': {'params': []}},
                }
            }
        }
        (tmp_path / 'FUNCTIONS.json').write_text(
            json.dumps(functions), encoding='utf-8'
        )

        registry = ToolRegistry(mainframe_root=str(tmp_path))
        assert not registry.load()
        assert registry.get_all_functions() == {}

    def test_one_stale_contract_closes_entire_stable_surface(self):
        registry = ToolRegistry(mainframe_root=PROJECT_ROOT)
        assert registry.load()
        function = registry.get_function('json_get')
        canonical_id = function['canonical_id']
        stale_export = copy.deepcopy(function['manifest_export'])
        stale_export.pop('contract_status')
        function['manifest_export'] = stale_export
        registry._manifest['exports'][canonical_id] = stale_export

        assert registry.generate_all_tools(tier='stable-core') == []
        # Explicit legacy tiers remain available during migration.
        assert registry.generate_all_tools(tier='core')

    @pytest.mark.parametrize(
        'malformed_result',
        [None, {}, {'kind': 'json'}, {'kind': 'stdout', 'schema': {}}],
    )
    def test_malformed_result_contract_closes_stable_surface(
        self, malformed_result
    ):
        registry = ToolRegistry(mainframe_root=PROJECT_ROOT)
        assert registry.load()
        function = registry.get_function('json_get')
        canonical_id = function['canonical_id']
        stale_export = copy.deepcopy(function['manifest_export'])
        stale_export['result'] = malformed_result
        function['manifest_export'] = stale_export
        registry._manifest['exports'][canonical_id] = stale_export

        assert registry.generate_all_tools(tier='stable-core') == []

    @pytest.mark.parametrize('tier', ['', 'stable_core', 'default', None])
    def test_invalid_discovery_tier_fails_closed(self, tier):
        registry = ToolRegistry(mainframe_root=PROJECT_ROOT)
        assert registry.generate_all_tools(tier=tier) == []


class TestBrokerExecutor:
    def test_stable_broker_never_resolves_poisoned_bash(
        self, monkeypatch, tmp_path
    ):
        marker = tmp_path / 'poisoned-bash-ran'
        poisoned_bash = tmp_path / 'bash'
        poisoned_bash.write_text(
            '#!/bin/sh\n'
            f': > "{marker}"\n'
            'printf "5 3"\n',
            encoding='utf-8',
        )
        poisoned_bash.chmod(0o755)
        monkeypatch.setenv('MAINFRAME_BASH', str(poisoned_bash))
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)
        assert executor._bash is None
        assert not marker.exists()

        monkeypatch.setattr(
            executor_module,
            '_bounded_broker_run',
            lambda *args: (0, _envelope(), b'', False, False),
        )
        ok, stdout, stderr = executor.execute_broker(
            'json_get',
            'mf:data:json:json_get',
            {'json': '{}', 'key': 'name'},
            'json',
            65_536,
            'stdout',
        )

        assert ok and stdout == 'Ada' and stderr == ''
        assert executor._bash is None
        assert not marker.exists()

    def test_exact_command_and_raw_argument_object_are_delegated(
        self, monkeypatch
    ):
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)
        captured = {}

        def fake_bounded_run(command, input_bytes, environment, timeout, limit):
            captured['command'] = command
            captured['input'] = input_bytes
            captured['environment'] = environment
            captured['timeout'] = timeout
            captured['limit'] = limit
            return 0, _envelope(), b'', False, False

        monkeypatch.setattr(
            executor_module, '_bounded_broker_run', fake_bounded_run
        )
        arguments = {'key': 'name', 'json': '{"name":"Ada"}'}
        ok, stdout, stderr = executor.execute_broker(
            'json_get',
            'mf:data:json:json_get',
            arguments,
            'json',
            65_536,
            'stdout',
        )

        assert ok and stdout == 'Ada' and stderr == ''
        assert captured['command'] == [
            os.path.join(PROJECT_ROOT, 'bin', 'mainframe'),
            'invoke',
            'mf:data:json:json_get',
            '--input-json',
            '-',
            '--profile',
            'stable-core',
            '--format',
            'broker-json-v1',
            '--caller',
            'mcp',
        ]
        assert json.loads(captured['input']) == arguments
        assert captured['environment']['MAINFRAME_ROOT'] == PROJECT_ROOT
        assert captured['timeout'] == executor.broker_timeout
        assert captured['limit'] == executor.broker_output_limit

    def test_live_broker_round_trip_decodes_envelope(self, monkeypatch, tmp_path):
        account_home = tmp_path / 'account-home'
        account_home.mkdir()
        poison_home = tmp_path / 'poison-home'
        poison_home.mkdir()
        monkeypatch.setenv('HOME', str(poison_home))
        monkeypatch.setattr(
            executor_module,
            '_account_state_home',
            lambda: account_home / '.local' / 'state',
        )
        poison = tmp_path / 'poison-audit.log'
        poison.write_text('preserve\n', encoding='utf-8')
        poison.chmod(0o600)
        monkeypatch.setenv('XDG_STATE_HOME', str(tmp_path / 'poison-state'))
        monkeypatch.setenv('MAINFRAME_INVOKE_AUDIT_LOG', str(poison))
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)

        ok, stdout, stderr = executor.execute_broker(
            'json_get',
            'mf:data:json:json_get',
            {'json': '{"name":"Ada"}', 'key': 'name'},
            'json',
            65_536,
            'stdout',
        )

        assert ok, stderr
        assert stdout == 'Ada'
        assert stderr == ''
        audit_log = (
            account_home / '.local' / 'state' / 'mainframe' / 'invocations.jsonl'
        )
        assert audit_log.is_file()
        assert poison.read_text(encoding='utf-8') == 'preserve\n'
        assert not (tmp_path / 'poison-state').exists()
        assert not (poison_home / '.local' / 'state').exists()

    @pytest.mark.parametrize(
        ('stdout', 'stderr', 'return_code', 'expected'),
        [
            (_envelope(extra='field'), b'', 0, 'shape'),
            (
                _envelope(canonical_id='mf:data:json:other'),
                b'',
                0,
                'canonical ID',
            ),
            (_envelope(stdout_b64='***'), b'', 0, 'base64'),
            (_envelope(owner='functional'), b'', 0, 'identity'),
            (_envelope(), b'raw diagnostic', 0, 'outside'),
            (_envelope(), b'', 1, 'exit status'),
        ],
    )
    def test_malformed_or_inconsistent_envelopes_fail_closed(
        self, stdout, stderr, return_code, expected
    ):
        ok, output, error = executor_module._decode_broker_envelope(
            stdout,
            stderr,
            return_code,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'stdout',
        )
        assert not ok and output == ''
        assert 'protocol error' in error
        assert expected in error

    def test_decoded_output_cannot_exceed_reviewed_contract_limit(self):
        ok, output, error = executor_module._decode_broker_envelope(
            _envelope(stdout='four'),
            b'',
            0,
            'mf:data:json:json_get',
            'json_get',
            'json',
            3,
            'stdout',
        )

        assert not ok and output == ''
        assert 'reviewed ceiling' in error

    def test_exit_result_kind_rejects_forged_stdout(self):
        ok, output, error = executor_module._decode_broker_envelope(
            _envelope(stdout='forged'),
            b'',
            0,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'exit',
        )

        assert not ok and output == ''
        assert 'result kind' in error

    @pytest.mark.parametrize(
        ('envelope', 'return_code'),
        [
            (
                _envelope(
                    ok=False,
                    status='timeout',
                    exit_code=124,
                    timed_out=False,
                ),
                124,
            ),
            (
                _envelope(
                    ok=False,
                    status='output_limit',
                    exit_code=74,
                    output_exceeded=False,
                ),
                74,
            ),
            (
                _envelope(
                    ok=False,
                    status='invalid_input',
                    exit_code=126,
                    error='invalid',
                ),
                126,
            ),
            (
                _envelope(
                    ok=False,
                    status='audit_error',
                    exit_code=1,
                    error='audit',
                ),
                1,
            ),
        ],
    )
    def test_status_flag_and_exit_mutations_fail_closed(
        self, envelope, return_code
    ):
        ok, output, error = executor_module._decode_broker_envelope(
            envelope,
            b'',
            return_code,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'stdout',
        )

        assert not ok and output == ''
        assert 'protocol error' in error

    def test_failure_envelope_preserves_existing_return_tuple_semantics(self):
        envelope = _envelope(
            ok=False,
            status='function_error',
            exit_code=1,
            stdout='partial',
            stderr='function detail',
            error=None,
        )
        ok, stdout, stderr = executor_module._decode_broker_envelope(
            envelope,
            b'',
            1,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'stdout',
        )
        assert not ok
        assert stdout == 'partial'
        assert stderr == 'function detail'

    def test_outer_timeout_kills_broker_process_group(
        self, monkeypatch, tmp_path
    ):
        marker = tmp_path / 'descendant-survived'
        root = _make_fake_broker(
            tmp_path,
            '#!/bin/sh\n'
            '( sleep 0.4; printf survived > "$BROKER_TEST_MARKER" ) &\n'
            'sleep 5\n',
        )
        monkeypatch.setenv('BROKER_TEST_MARKER', str(marker))
        executor = BashExecutor(mainframe_root=str(root))
        executor.broker_timeout = 0.05

        ok, stdout, stderr = executor.execute_broker(
            'json_get',
            'mf:data:json:json_get',
            {},
            'json',
            65_536,
            'stdout',
        )
        time.sleep(0.5)

        assert not ok and stdout == ''
        assert 'outer broker boundary' in stderr
        assert not marker.exists()

    def test_outer_output_ceiling_terminates_broker(self, tmp_path):
        root = _make_fake_broker(
            tmp_path,
            '#!/bin/sh\n'
            'while :; do printf 0123456789abcdef; done\n',
        )
        executor = BashExecutor(mainframe_root=str(root))
        executor.broker_output_limit = 1024
        executor.broker_timeout = 2

        ok, stdout, stderr = executor.execute_broker(
            'json_get',
            'mf:data:json:json_get',
            {},
            'json',
            65_536,
            'stdout',
        )

        assert not ok and stdout == ''
        assert 'output ceiling' in stderr


class TestSuccessTextRepresentation:
    @pytest.mark.parametrize('stdout', ['', ' ', '  \n\t'])
    def test_empty_or_whitespace_stdout_is_lossless(self, stdout):
        text = server_module._success_text('json_escape', 'stdout', stdout)
        payload = json.loads(text)

        assert payload == {
            'schema_version': 1,
            'kind': 'mainframe-mcp-stdout',
            'function': 'json_escape',
            'encoding': 'base64',
            'stdout_b64': base64.b64encode(stdout.encode()).decode(),
        }

    def test_nonempty_stdout_remains_plain_text(self):
        assert server_module._success_text(
            'json_get', 'stdout', 'Ada'
        ) == 'Ada'

    @pytest.mark.parametrize('result_kind', ['exit', 'none'])
    def test_non_stdout_results_use_completion_sentence(self, result_kind):
        assert server_module._success_text(
            'json_valid', result_kind, ''
        ) == 'Function json_valid completed successfully'

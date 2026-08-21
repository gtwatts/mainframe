"""Canonical stable-core broker delegation and fail-closed registry tests."""

import base64
import copy
import json
import os
import time
from types import SimpleNamespace

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
        # Historical discovery profiles are never executable MCP tiers.
        assert registry.generate_all_tools(tier='core') == []
        assert registry.generate_all_tools(tier='full') == []

    def test_reviewed_tools_publish_only_contract_derived_read_annotations(self):
        registry = ToolRegistry(mainframe_root=PROJECT_ROOT)
        tools = registry.generate_all_tools(tier='stable-core')

        assert len(tools) == 26
        for tool in tools:
            function = registry.get_function(tool['name'].removeprefix('mainframe_'))
            export = function['manifest_export']
            assert set(tool) == {
                'name', 'description', 'inputSchema', 'outputSchema',
                'annotations', '_meta',
            }
            assert tool['annotations'] == {'readOnlyHint': True}
            assert tool['_meta'] == {
                'mainframe': {
                    'schema_version': 2,
                    'canonical_id': function['canonical_id'],
                    'contract_status': 'reviewed',
                    'effects': export['effects'],
                    'capabilities': [],
                    'result_kind': export['result']['kind'],
                }
            }
            assert set(export['effects']) <= {'pure', 'read'}
            assert tool['outputSchema']['additionalProperties'] is False
            assert tool['outputSchema']['properties']['canonical_id'] == {
                'const': function['canonical_id']
            }
            assert tool['outputSchema']['properties']['effect_contract'][
                'properties'
            ]['effects'] == {'const': export['effects']}

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


class TestMcpCorrelation:
    def test_client_durable_ids_are_data_only_and_strictly_validated(self):
        context = SimpleNamespace(
            meta=SimpleNamespace(
                model_extra={
                    'mainframe': {
                        'run_id': 'run:one',
                        'call_id': 'call.one',
                        'evidence_id': 'evidence-one',
                    }
                }
            )
        )
        assert server_module._client_correlation(context) == {
            'call_id': 'call.one',
            'evidence_id': 'evidence-one',
            'run_id': 'run:one',
        }

        for invalid in (
            {'run_id': '../not-an-id'},
            {'run_id': 'valid', 'approval_granted': True},
            ['run-id'],
        ):
            context.meta.model_extra['mainframe'] = invalid
            with pytest.raises(
                RuntimeError, match='correlation metadata is invalid'
            ):
                server_module._client_correlation(context)


class TestBrokerExecutor:
    def test_executor_exposes_no_legacy_execution_route(self):
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)
        assert hasattr(executor, 'execute_control_plane')
        assert not hasattr(executor, 'execute_broker')
        assert not hasattr(executor, 'execute')
        assert not hasattr(executor, 'bash')
        assert not hasattr(executor_module, 'EXECUTION_SCRIPT')

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

    def test_only_a_fully_validated_envelope_exports_broker_identity(self):
        identity = {'stale': 'must-be-cleared'}
        ok, output, error = executor_module._decode_broker_envelope(
            _envelope(audit_id='inv-mcp-validated', duration_ms=7),
            b'',
            0,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'stdout',
            identity_out=identity,
        )

        assert ok and output == 'Ada' and error == ''
        assert identity == {
            'audit_id': 'inv-mcp-validated',
            'status': 'success',
            'duration_ms': 7,
        }

        ok, output, error = executor_module._decode_broker_envelope(
            _envelope(audit_id='not valid!'),
            b'',
            0,
            'mf:data:json:json_get',
            'json_get',
            'json',
            65_536,
            'stdout',
            identity_out=identity,
        )
        assert not ok and output == '' and 'protocol error' in error
        assert identity == {}

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
        return_code, stdout, stderr, timed_out, output_exceeded = (
            executor_module._bounded_broker_run(
                [str(root / 'bin' / 'mainframe')],
                b'{}',
                os.environ.copy(),
                0.05,
                65_536,
            )
        )
        time.sleep(0.5)

        assert return_code != 0
        assert stdout == b'' and stderr == b''
        assert timed_out and not output_exceeded
        assert not marker.exists()

    def test_outer_output_ceiling_terminates_broker(self, tmp_path):
        root = _make_fake_broker(
            tmp_path,
            '#!/bin/sh\n'
            'while :; do printf 0123456789abcdef; done\n',
        )
        return_code, stdout, stderr, timed_out, output_exceeded = (
            executor_module._bounded_broker_run(
                [str(root / 'bin' / 'mainframe')],
                b'{}',
                os.environ.copy(),
                2,
                1024,
            )
        )

        assert return_code != 0
        assert stdout == b'' and stderr == b''
        assert output_exceeded and not timed_out


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

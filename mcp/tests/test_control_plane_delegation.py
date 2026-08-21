"""Atomic public control-plane delegation and durable identity validation."""

import base64
import hashlib
import inspect
import json
import os
from types import SimpleNamespace

import pytest

from mainframe_mcp import executor as executor_module
from mainframe_mcp import server as server_module
from mainframe_mcp.executor import BashExecutor


PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
CANONICAL_ID = 'mf:data:json:json_get'
ARGUMENTS = {'json': '{"name":"Ada"}', 'key': 'name'}
CLIENT_ID = 'mcp-test-client-1'


def _digest(value):
    return hashlib.sha256(value).hexdigest()


def _input_digest(arguments=ARGUMENTS):
    return _digest(json.dumps(
        arguments,
        allow_nan=False,
        ensure_ascii=False,
        separators=(',', ':'),
        sort_keys=True,
    ).encode())


def _broker_envelope(**overrides):
    payload = {
        'schema_version': 1,
        'ok': True,
        'status': 'success',
        'canonical_id': CANONICAL_ID,
        'name': 'json_get',
        'owner': 'json',
        'exit_code': 0,
        'timed_out': False,
        'output_exceeded': False,
        'duration_ms': 4,
        'audit_id': 'inv-kernel-1',
        'stdout_b64': base64.b64encode(b'Ada').decode(),
        'stderr_b64': '',
        'error': None,
    }
    payload.update(overrides)
    return payload


def _receipt(envelope):
    stdout = base64.b64decode(envelope['stdout_b64'])
    stderr = base64.b64decode(envelope['stderr_b64'])
    error = (envelope['error'] or '').encode()
    return {
        key: envelope[key]
        for key in (
            'schema_version', 'ok', 'status', 'canonical_id', 'name', 'owner',
            'exit_code', 'timed_out', 'output_exceeded', 'duration_ms', 'audit_id',
        )
    } | {
        'stdout_bytes': len(stdout),
        'stdout_sha256': _digest(stdout),
        'stderr_bytes': len(stderr),
        'stderr_sha256': _digest(stderr),
        'error_bytes': len(error),
        'error_sha256': _digest(error),
    }


def _control_envelope(**result_overrides):
    broker = _broker_envelope()
    result = {
        'schema_version': 1,
        'status': 'completed',
        'client_correlation_id': CLIENT_ID,
        'run_id': 'run-' + '1' * 32,
        'call_id': 'call-' + '2' * 32,
        'decision_id': 'decision-' + '3' * 32,
        'evidence_id': 'evidence-' + '4' * 32,
        'input_digest': _input_digest(),
        'outcome': 'succeeded',
        'result_available': True,
        'broker_receipt': _receipt(broker),
        'broker_envelope': broker,
    }
    result.update(result_overrides)
    return json.dumps({
        'ok': True,
        'command': 'canonical-invoke',
        'result': result,
    }, separators=(',', ':')).encode()


class TestControlPlaneExecutor:
    def test_exact_public_atomic_route_and_generated_client_key(
        self, monkeypatch
    ):
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)
        captured = {}

        def fake_run(command, input_bytes, environment, timeout, limit):
            captured.update(
                command=command,
                input=input_bytes,
                environment=environment,
                timeout=timeout,
                limit=limit,
            )
            return 0, _control_envelope(), b'', False, False

        monkeypatch.setattr(executor_module, '_bounded_broker_run', fake_run)
        identity = {}
        ok, stdout, stderr = executor.execute_control_plane(
            'json_get',
            CANONICAL_ID,
            ARGUMENTS,
            'json',
            65_536,
            'stdout',
            CLIENT_ID,
            identity_out=identity,
        )

        assert ok and stdout == 'Ada' and stderr == ''
        assert captured['command'] == [
            os.path.join(PROJECT_ROOT, 'bin', 'mainframe'),
            'invoke',
            CANONICAL_ID,
            '--input-json',
            '-',
            '--profile',
            'stable-core',
            '--format',
            'control-plane-json-v1',
            '--caller',
            'mcp',
            '--client-correlation-id',
            CLIENT_ID,
        ]
        assert b'broker-json-v1' not in b' '.join(
            item.encode() for item in captured['command']
        )
        assert json.loads(captured['input']) == ARGUMENTS
        assert identity['client_correlation_id'] == CLIENT_ID
        assert identity['run_id'].startswith('run-')
        assert identity['call_id'].startswith('call-')
        assert identity['decision_id'].startswith('decision-')
        assert identity['evidence_id'].startswith('evidence-')
        assert identity['input_digest'] == _input_digest()
        assert identity['outcome'] == 'succeeded'
        assert identity['result_available'] is True

    def test_structured_result_uses_kernel_ids_and_ignores_client_durable_claims(self):
        envelope = json.loads(_control_envelope())['result']
        context = SimpleNamespace(request_id=17)
        func = {
            'name': 'json_get',
            'canonical_id': CANONICAL_ID,
            'manifest_export': {'effects': ['pure']},
        }
        client_claims = {
            'run_id': 'run-forged-client',
            'call_id': 'call-forged-client',
            'evidence_id': 'evidence-forged-client',
        }

        structured = server_module._structured_success(
            context,
            func,
            'stdout',
            'Ada',
            envelope,
            client_claims,
        )

        assert structured['schema_version'] == 2
        assert structured['correlation'] == {
            'mcp_request_id': 17,
            'client_correlation_id': CLIENT_ID,
            'binding_status': 'kernel-authoritative',
            'client_metadata_status': 'ignored-unverified',
            'run_id': envelope['run_id'],
            'call_id': envelope['call_id'],
            'decision_id': envelope['decision_id'],
            'evidence_id': envelope['evidence_id'],
            'input_digest': envelope['input_digest'],
        }
        assert 'run-forged-client' not in json.dumps(structured)
        assert structured['terminal'] == {
            'outcome': 'succeeded',
            'result_available': True,
            'broker_receipt': envelope['broker_receipt'],
        }

    @pytest.mark.parametrize(
        ('mutation', 'expected'),
        [
            (lambda value: value.update(extra=True), 'shape'),
            (lambda value: value['result'].update(client_correlation_id='forged'), 'client correlation'),
            (lambda value: value['result'].update(run_id='run-' + 'a' * 31), 'durable identity'),
            (lambda value: value['result'].update(input_digest='0' * 64), 'input digest'),
            (lambda value: value['result']['broker_receipt'].update(stdout_bytes=99), 'receipt'),
            (lambda value: value['result']['broker_receipt'].update(name='other'), 'receipt'),
            (lambda value: value['result']['broker_receipt'].update(owner='other'), 'receipt'),
            (
                lambda value: value['result']['broker_receipt'].update(
                    status='timeout'
                ),
                'receipt',
            ),
            (lambda value: value['result']['broker_envelope'].update(canonical_id='mf:forged:id:value'), 'canonical ID'),
        ],
    )
    def test_outer_identity_receipt_and_inner_envelope_tamper_fail_closed(
        self, mutation, expected
    ):
        document = json.loads(_control_envelope())
        mutation(document)
        identity = {'stale': 'clear'}
        ok, stdout, stderr = executor_module._decode_control_plane_envelope(
            json.dumps(document).encode(),
            b'',
            0,
            CANONICAL_ID,
            'json_get',
            'json',
            65_536,
            'stdout',
            CLIENT_ID,
            _input_digest(),
            identity_out=identity,
        )
        assert not ok and stdout == ''
        assert expected in stderr
        assert identity == {}

    def test_terminal_result_without_transient_output_never_reexecutes_or_falls_back(self):
        document = json.loads(_control_envelope())
        document['result'].update(
            result_available=False,
            broker_envelope=None,
        )
        identity = {}
        ok, stdout, stderr = executor_module._decode_control_plane_envelope(
            json.dumps(document).encode(),
            b'',
            0,
            CANONICAL_ID,
            'json_get',
            'json',
            65_536,
            'stdout',
            CLIENT_ID,
            _input_digest(),
            identity_out=identity,
        )
        assert not ok and stdout == ''
        assert 'transient result is unavailable' in stderr
        assert identity['result_available'] is False
        assert identity['run_id'].startswith('run-')
        assert identity['evidence_id'].startswith('evidence-')

    def test_outer_timeout_preserves_only_non_authorizing_lookup_key(self, monkeypatch):
        executor = BashExecutor(mainframe_root=PROJECT_ROOT)
        monkeypatch.setattr(
            executor_module,
            '_bounded_broker_run',
            lambda *args: (124, b'', b'', True, False),
        )
        identity = {'forged': 'clear'}
        ok, stdout, stderr = executor.execute_control_plane(
            'json_get',
            CANONICAL_ID,
            ARGUMENTS,
            'json',
            65_536,
            'stdout',
            CLIENT_ID,
            identity_out=identity,
        )
        assert not ok and stdout == ''
        assert 'cancellation is not claimed' in stderr
        assert 'no legacy fallback was attempted' in stderr
        assert CLIENT_ID in stderr
        assert identity == {
            'client_correlation_id': CLIENT_ID,
            'binding_status': 'adapter-local-unverified',
        }

    def test_server_route_contains_no_legacy_broker_fallback(self):
        source = inspect.getsource(server_module.create_server)
        assert '.execute_control_plane(' in source
        assert '.execute_broker(' not in source

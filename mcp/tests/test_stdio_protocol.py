"""End-to-end JSON-RPC checks for the authoritative stdio MCP boundary."""

import base64
import hashlib
import json
import os
import re
import select
import subprocess
import sys
import time


PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
SERVER = os.path.join(PROJECT_ROOT, 'mcp', 'mainframe-mcp-server')


def _request(request_id, method, params):
    return {
        'jsonrpc': '2.0',
        'id': request_id,
        'method': method,
        'params': params,
    }


def _stdio_exchange(messages, expected_ids, timeout=180, env_overrides=None):
    env = os.environ.copy()
    env.pop('MAINFRAME_ROOT', None)
    env.pop('MAINFRAME_MCP_TIER', None)
    env.pop('PYTHONPATH', None)
    env['PYTHONUNBUFFERED'] = '1'
    env.update(env_overrides or {})
    process = subprocess.Popen(
        [
            sys.executable,
            SERVER,
            '--mainframe-root',
            PROJECT_ROOT,
            '--allow-development-root',
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
        env=env,
        cwd=PROJECT_ROOT,
    )
    responses = {}
    output_buffer = b''
    stderr = ''
    notifications = []

    try:
        request_stream = ''.join(
            f'{json.dumps(message)}\n' for message in messages
        ).encode()
        process.stdin.write(request_stream)
        process.stdin.flush()

        deadline = time.monotonic() + timeout
        while set(responses) != set(expected_ids):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('timed out waiting for MCP stdio responses')
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            if not readable:
                raise TimeoutError('timed out waiting for MCP stdio responses')

            chunk = os.read(process.stdout.fileno(), 4096)
            if not chunk:
                raise RuntimeError('MCP server exited before all responses arrived')
            output_buffer += chunk

            while b'\n' in output_buffer:
                line, output_buffer = output_buffer.split(b'\n', 1)
                if not line:
                    continue
                message = json.loads(line)
                if message.get('id') is not None:
                    responses[message['id']] = message
                elif message.get('method') is not None:
                    notifications.append(message)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        stderr = process.stderr.read().decode(errors='replace')

    return responses, stderr, notifications


def test_stdio_tools_call_enforces_runtime_boundary(tmp_path):
    shim_dir = tmp_path / 'hostile-bin'
    shim_dir.mkdir()
    marker = tmp_path / 'path-shim-ran'
    shim = shim_dir / 'jq'
    shim.write_text(
        f'#!/bin/sh\n: > "{marker}"\nexit 99\n',
        encoding='utf-8',
    )
    shim.chmod(0o755)
    state_home = tmp_path / 'state'
    state_home.mkdir(mode=0o700)

    messages = [
        _request(
            1,
            'initialize',
            {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'clientInfo': {'name': 'mainframe-security-test', 'version': '1'},
            },
        ),
        {
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': {},
        },
        _request(
            2,
            'tools/call',
            {'name': 'mainframe_definitely_not_real_xyz', 'arguments': {}},
        ),
        _request(
            3,
            'tools/call',
            {'name': 'mainframe_ls', 'arguments': {}},
        ),
        _request(
            4,
            'tools/call',
            {
                'name': 'mainframe_json_get',
                'arguments': {'args': ['{}', 'name']},
            },
        ),
        _request(
            5,
            'tools/call',
            {
                'name': 'mainframe_json_get',
                'arguments': {'json': '{}', 'key': 'name', 'extra': 'value'},
            },
        ),
        _request(
            6,
            'tools/call',
            {'name': 'mainframe_json_get', 'arguments': {'json': '{}'}},
        ),
        _request(
            7,
            'tools/call',
            {
                'name': 'mainframe_json_get',
                'arguments': {'json': {}, 'key': 'name'},
            },
        ),
        _request(
            8,
            'tools/call',
            {'name': 'mainframe_ensure_dir', 'arguments': {'path': '/tmp/nope'}},
        ),
        _request(
            9,
            'tools/call',
            {
                'name': 'mainframe_json_get',
                'arguments': {'key': 'name', 'json': '{"name":"Ada"}'},
                '_meta': {
                    'progressToken': 'progress-json-get-9',
                    'mainframe': {
                        'run_id': 'run-mcp-9',
                        'call_id': 'call-mcp-9',
                        'evidence_id': 'evidence-mcp-9',
                    },
                },
            },
        ),
        _request(
            10,
            'tools/call',
            {'name': 'mainframe_json_valid', 'arguments': {'json': '{}'}},
        ),
        _request(
            11,
            'tools/call',
            {'name': 'mainframe_json_escape', 'arguments': {'str': ''}},
        ),
        _request(
            12,
            'tools/call',
            {'name': 'mainframe_json_escape', 'arguments': {'str': '   '}},
        ),
        _request(13, 'tools/list', {}),
    ]
    responses, stderr, notifications = _stdio_exchange(
        messages,
        range(1, 14),
        env_overrides={
            'PATH': str(shim_dir),
            'XDG_STATE_HOME': str(state_home),
        },
    )
    assert 'result' in responses[1], stderr

    for request_id in range(2, 9):
        result = responses[request_id]['result']
        assert result['isError'] is True, (request_id, result)

    valid_result = responses[9]['result']
    assert valid_result.get('isError', False) is False
    assert valid_result['content'][0]['text'].strip() == 'Ada'
    structured = valid_result['structuredContent']
    assert structured['schema_version'] == 2
    assert structured['kind'] == 'mainframe-mcp-result'
    assert structured['ok'] is True
    assert structured['function'] == 'json_get'
    assert structured['canonical_id'] == 'mf:data:json:json_get'
    assert structured['effect_contract'] == {
        'effects': ['pure'],
        'read_only': True,
    }
    assert structured['result'] == {
        'kind': 'stdout',
        'encoding': 'utf-8',
        'stdout': 'Ada',
    }
    correlation = structured['correlation']
    assert correlation['mcp_request_id'] == 9
    assert re.fullmatch(r'mcp-[0-9a-f]{32}', correlation['client_correlation_id'])
    assert correlation['binding_status'] == 'kernel-authoritative'
    assert correlation['client_metadata_status'] == 'ignored-unverified'
    assert re.fullmatch(r'run-[0-9a-f]{32}', correlation['run_id'])
    assert re.fullmatch(r'call-[0-9a-f]{32}', correlation['call_id'])
    assert re.fullmatch(r'decision-[0-9a-f]{32}', correlation['decision_id'])
    assert re.fullmatch(r'evidence-[0-9a-f]{32}', correlation['evidence_id'])
    assert correlation['run_id'] != 'run-mcp-9'
    assert correlation['call_id'] != 'call-mcp-9'
    assert correlation['evidence_id'] != 'evidence-mcp-9'
    canonical_input = json.dumps(
        {'key': 'name', 'json': '{"name":"Ada"}'},
        allow_nan=False,
        ensure_ascii=False,
        separators=(',', ':'),
        sort_keys=True,
    ).encode()
    assert correlation['input_digest'] == hashlib.sha256(canonical_input).hexdigest()
    terminal = structured['terminal']
    assert terminal['outcome'] == 'succeeded'
    assert terminal['result_available'] is True
    receipt = terminal['broker_receipt']
    assert receipt['canonical_id'] == 'mf:data:json:json_get'
    assert receipt['name'] == 'json_get'
    assert receipt['owner'] == 'json'
    assert receipt['stdout_sha256'] == hashlib.sha256(b'Ada').hexdigest()
    progress = [
        message['params'] for message in notifications
        if message.get('method') == 'notifications/progress'
        and message.get('params', {}).get('progressToken') == 'progress-json-get-9'
    ]
    assert [item['progress'] for item in progress] == [0.0, 1.0]
    assert all(item['total'] == 1.0 for item in progress)
    assert responses[10]['result'].get('isError', False) is False
    for request_id, expected_stdout in ((11, ''), (12, '   ')):
        result = responses[request_id]['result']
        assert result.get('isError', False) is False
        payload = json.loads(result['content'][0]['text'])
        assert payload['schema_version'] == 1
        assert payload['kind'] == 'mainframe-mcp-stdout'
        assert payload['encoding'] == 'base64'
        assert base64.b64decode(payload['stdout_b64']).decode() == expected_stdout
        structured = result['structuredContent']
        assert structured['result']['kind'] == 'stdout'
        assert structured['result']['stdout'] == expected_stdout
        assert structured['correlation']['binding_status'] == 'kernel-authoritative'
        assert structured['correlation']['client_metadata_status'] == 'absent'
        assert structured['terminal']['result_available'] is True

    tools = responses[13]['result']['tools']
    assert len(tools) == 26
    assert all(tool['annotations'] == {'readOnlyHint': True} for tool in tools)
    assert all(tool['_meta']['mainframe']['effects'] for tool in tools)
    assert all(tool['outputSchema']['additionalProperties'] is False for tool in tools)
    assert not marker.exists()

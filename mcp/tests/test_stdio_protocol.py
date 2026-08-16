"""End-to-end JSON-RPC checks for the authoritative stdio MCP boundary."""

import base64
import json
import os
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
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        stderr = process.stderr.read().decode(errors='replace')

    return responses, stderr


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
    ]
    responses, stderr = _stdio_exchange(
        messages,
        range(1, 13),
        env_overrides={
            'PATH': str(shim_dir),
            'XDG_STATE_HOME': str(tmp_path / 'state'),
        },
    )
    assert 'result' in responses[1], stderr

    for request_id in range(2, 9):
        result = responses[request_id]['result']
        assert result['isError'] is True, (request_id, result)

    valid_result = responses[9]['result']
    assert valid_result.get('isError', False) is False
    assert valid_result['content'][0]['text'].strip() == 'Ada'
    assert responses[10]['result'].get('isError', False) is False
    for request_id, expected_stdout in ((11, ''), (12, '   ')):
        result = responses[request_id]['result']
        assert result.get('isError', False) is False
        payload = json.loads(result['content'][0]['text'])
        assert payload['schema_version'] == 1
        assert payload['kind'] == 'mainframe-mcp-stdout'
        assert payload['encoding'] == 'base64'
        assert base64.b64decode(payload['stdout_b64']).decode() == expected_stdout
    assert not marker.exists()

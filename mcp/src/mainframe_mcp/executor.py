"""Bash execution engine for running MAINFRAME functions."""

import base64
import binascii
import hashlib
import json
import os
import re
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Optional, Sequence, Tuple

from .authorization import AuthorizationError, validate_function_name
from .runtime_root import RuntimeIdentity, resolve_mainframe_root


TRUSTED_DEPENDENCY_PATH = os.pathsep.join((
    '/opt/homebrew/bin',
    '/opt/homebrew/sbin',
    '/usr/local/bin',
    '/usr/local/sbin',
    '/opt/local/bin',
    '/opt/local/sbin',
    '/home/linuxbrew/.linuxbrew/bin',
    '/home/linuxbrew/.linuxbrew/sbin',
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin',
))
UNSAFE_ENVIRONMENT_KEYS = frozenset({
    'BASHOPTS',
    'BASH_ENV',
    'ENV',
    'NODE_OPTIONS',
    'NODE_PATH',
    'NODE_REDIRECT_WARNINGS',
    'NODE_REPL_HISTORY',
    'NODE_V8_COVERAGE',
    'PERL5LIB',
    'PERL5OPT',
    'PERLLIB',
    'MAINFRAME_INVOKE_AUDIT_LOG',
    'SHELLOPTS',
})
BROKER_CANONICAL_ID_RE = re.compile(
    r'^mf:[a-z][a-z0-9-]*:[a-zA-Z0-9_-]+:[a-z_][a-z0-9_]*$'
)
BROKER_FUNCTION_RE = re.compile(r'^[a-z_][a-z0-9_]*$')
BROKER_OWNER_RE = re.compile(r'^[a-zA-Z0-9_-]+$')
BROKER_AUDIT_ID_RE = re.compile(r'^[a-zA-Z0-9._:-]{1,160}$')
BROKER_INPUT_LIMIT = 32_768
BROKER_OUTER_TIMEOUT_SECONDS = 35.0
BROKER_OUTER_OUTPUT_LIMIT = 2_097_152
BROKER_DECODED_OUTPUT_LIMIT = 1_048_576
BROKER_ENVELOPE_FIELDS = frozenset({
    'schema_version',
    'ok',
    'status',
    'canonical_id',
    'name',
    'owner',
    'exit_code',
    'timed_out',
    'output_exceeded',
    'duration_ms',
    'audit_id',
    'stdout_b64',
    'stderr_b64',
    'error',
})
BROKER_STATUSES = frozenset({
    'success',
    'function_error',
    'timeout',
    'output_limit',
    'audit_error',
    'invalid_input',
    'invalid_id',
    'invalid_manifest',
    'unknown_id',
    'invalid_contract',
    'unreviewed_contract',
    'owner_mismatch',
    'unsupported_platform',
    'invalid_owner',
    'broker_error',
})
BROKER_FIXED_STATUS_EXIT_CODES = {
    'success': 0,
    'timeout': 124,
    'output_limit': 74,
    'audit_error': 74,
    'invalid_input': 65,
    'invalid_id': 126,
    'invalid_manifest': 126,
    'unknown_id': 126,
    'invalid_contract': 126,
    'unreviewed_contract': 126,
    'owner_mismatch': 126,
    'unsupported_platform': 126,
    'invalid_owner': 126,
    'broker_error': 70,
}
BROKER_RESULT_KINDS = frozenset({'stdout', 'exit', 'none'})
CONTROL_PLANE_OUTER_FIELDS = frozenset({'ok', 'command', 'result'})
CONTROL_PLANE_RESULT_FIELDS = frozenset({
    'schema_version',
    'status',
    'client_correlation_id',
    'run_id',
    'call_id',
    'decision_id',
    'evidence_id',
    'input_digest',
    'outcome',
    'result_available',
    'broker_receipt',
    'broker_envelope',
})
CONTROL_PLANE_RECEIPT_FIELDS = frozenset({
    'schema_version',
    'ok',
    'status',
    'canonical_id',
    'name',
    'owner',
    'exit_code',
    'timed_out',
    'output_exceeded',
    'duration_ms',
    'audit_id',
    'stdout_bytes',
    'stdout_sha256',
    'stderr_bytes',
    'stderr_sha256',
    'error_bytes',
    'error_sha256',
})
CONTROL_PLANE_ID_PATTERNS = {
    'run_id': re.compile(r'^run-[0-9a-f]{32}$'),
    'call_id': re.compile(r'^call-[0-9a-f]{32}$'),
    'decision_id': re.compile(r'^decision-[0-9a-f]{32}$'),
    'evidence_id': re.compile(r'^evidence-[0-9a-f]{32}$'),
}
CONTROL_PLANE_CLIENT_ID_RE = re.compile(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
)
SHA256_RE = re.compile(r'^[0-9a-f]{64}$')

def _execution_environment(
    mainframe_root: str,
    development_state_home: Optional[str] = None,
) -> dict[str, str]:
    """Preserve normal user context while removing interpreter injection hooks."""
    env = os.environ.copy()
    for key in tuple(env):
        if (
            key in UNSAFE_ENVIRONMENT_KEYS
            or key.startswith('BASH_FUNC_')
            or key.startswith('LD_')
            or key.startswith('DYLD_')
        ):
            env.pop(key, None)
    env['MAINFRAME_ROOT'] = mainframe_root
    env['PATH'] = TRUSTED_DEPENDENCY_PATH
    # Production always uses the login account's private state directory.
    # An explicit development-root server may use the operator-selected state
    # root captured at startup so source tests remain isolated; MCP request
    # metadata still cannot redirect durable records.
    state_home = (
        Path(development_state_home)
        if development_state_home is not None
        else _account_state_home()
    )
    env['XDG_STATE_HOME'] = str(state_home)
    return env


def _account_state_home() -> Path:
    """Return the login account's canonical state root, independent of HOME."""
    import pwd

    try:
        raw_home = pwd.getpwuid(os.geteuid()).pw_dir
        home = Path(raw_home).resolve(strict=True)
    except (KeyError, OSError, RuntimeError) as error:
        raise RuntimeError('MAINFRAME MCP cannot resolve the account home') from error
    if not home.is_absolute() or not home.is_dir():
        raise RuntimeError('MAINFRAME MCP account home is invalid')
    return home / '.local' / 'state'


def _terminate_process_group(process: subprocess.Popen) -> None:
    """Terminate a broker and every descendant in its isolated process group."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            process.terminate()
        except (ProcessLookupError, OSError):
            pass

    # Give cooperative cleanup a small, bounded window, then kill the entire
    # group even if the leader already exited so surviving descendants cannot
    # continue after an MCP timeout or output denial.
    # The broker's own TERM trap tears down its nested function process group
    # with a bounded TERM-to-KILL sequence. Leave enough grace for that inner
    # cleanup before the outer adapter escalates.
    deadline = time.monotonic() + 0.5
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.01)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            process.kill()
        except (ProcessLookupError, OSError):
            pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        # The caller will report a closed failure. Never wait indefinitely on
        # an uncooperative adapter process.
        pass


def _bounded_broker_run(
    command: Sequence[str],
    input_bytes: bytes,
    environment: Dict[str, str],
    timeout_seconds: float,
    output_limit: int,
) -> Tuple[int, bytes, bytes, bool, bool]:
    """Run the broker with strictly bounded output collection.

    Input is a small disk-backed file so it cannot deadlock with output.
    Selector-driven pipes retain at most ``output_limit`` bytes; once the next
    read would cross that ceiling, the complete isolated process group is
    terminated. This bounds memory and lets pipe backpressure bound the child
    between observations on both macOS and Linux.
    """
    with tempfile.TemporaryFile() as input_file:
        input_file.write(input_bytes)
        input_file.seek(0)
        process = subprocess.Popen(
            list(command),
            stdin=input_file,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            close_fds=True,
            start_new_session=True,
        )

        deadline = time.monotonic() + timeout_seconds
        timed_out = False
        output_exceeded = False
        stdout = bytearray()
        stderr = bytearray()
        stream_selector = selectors.DefaultSelector()
        assert process.stdout is not None and process.stderr is not None
        stream_selector.register(process.stdout, selectors.EVENT_READ, stdout)
        stream_selector.register(process.stderr, selectors.EVENT_READ, stderr)

        try:
            while stream_selector.get_map():
                remaining_time = deadline - time.monotonic()
                if remaining_time <= 0:
                    timed_out = True
                    _terminate_process_group(process)
                    break

                events = stream_selector.select(min(remaining_time, 0.05))
                for key, _ in events:
                    try:
                        remaining_output = (
                            output_limit - len(stdout) - len(stderr)
                        )
                        chunk = os.read(
                            key.fd, min(65_536, remaining_output + 1)
                        )
                    except BlockingIOError:
                        continue
                    if not chunk:
                        stream_selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    if len(stdout) + len(stderr) + len(chunk) > output_limit:
                        output_exceeded = True
                        _terminate_process_group(process)
                        break
                    key.data.extend(chunk)
                if output_exceeded:
                    break

                # A cleanly exited leader is not enough: keep draining until
                # EOF so a leaked descendant pipe remains subject to the same
                # outer deadline and process-group kill.
                if process.poll() is not None and not events:
                    time.sleep(0.001)
        except BaseException:
            _terminate_process_group(process)
            raise
        finally:
            for key in list(stream_selector.get_map().values()):
                stream_selector.unregister(key.fileobj)
                key.fileobj.close()
            stream_selector.close()

        if not timed_out and not output_exceeded:
            while process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            if process.poll() is None:
                timed_out = True
                _terminate_process_group(process)
        elif process.poll() is None:
            _terminate_process_group(process)
        return_code = process.poll()
        if return_code is None:
            return_code = -signal.SIGKILL
        if timed_out or output_exceeded:
            return return_code, b'', b'', timed_out, output_exceeded
        return return_code, bytes(stdout), bytes(stderr), False, False


def _json_object_without_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON field {key!r}')
        result[key] = value
    return result


def _decode_canonical_base64(value: str, field: str) -> bytes:
    if not isinstance(value, str):
        raise ValueError(f'{field} is not a string')
    try:
        decoded = base64.b64decode(value.encode('ascii'), validate=True)
    except (UnicodeEncodeError, ValueError, binascii.Error) as error:
        raise ValueError(f'{field} is not valid base64') from error
    if base64.b64encode(decoded).decode('ascii') != value:
        raise ValueError(f'{field} is not canonical base64')
    return decoded


def _protocol_failure(detail: str) -> Tuple[bool, str, str]:
    return (
        False,
        '',
        f'invocation denied: canonical broker protocol error: {detail}',
    )


def _decode_broker_envelope(
    stdout_bytes: bytes,
    stderr_bytes: bytes,
    return_code: int,
    canonical_id: str,
    func_name: str,
    expected_owner: str,
    contract_output_limit: int,
    expected_result_kind: str,
    *,
    identity_out: Optional[Dict[str, Any]] = None,
) -> Tuple[bool, str, str]:
    """Validate the kernel's nested broker envelope and decode its text result."""
    if identity_out is not None:
        identity_out.clear()
    if stderr_bytes:
        return _protocol_failure('broker wrote outside its result envelope')
    try:
        envelope_text = stdout_bytes.decode('utf-8')
        envelope = json.loads(
            envelope_text,
            object_pairs_hook=_json_object_without_duplicates,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        return _protocol_failure('broker returned an invalid JSON envelope')

    if not isinstance(envelope, dict) or set(envelope) != BROKER_ENVELOPE_FIELDS:
        return _protocol_failure('broker envelope shape is invalid')
    if envelope.get('schema_version') != 1 or isinstance(
        envelope.get('schema_version'), bool
    ):
        return _protocol_failure('broker envelope version is unsupported')

    ok = envelope.get('ok')
    status = envelope.get('status')
    exit_code = envelope.get('exit_code')
    timed_out = envelope.get('timed_out')
    output_exceeded = envelope.get('output_exceeded')
    duration_ms = envelope.get('duration_ms')
    if (
        not isinstance(ok, bool)
        or not isinstance(status, str)
        or status not in BROKER_STATUSES
        or not isinstance(exit_code, int)
        or isinstance(exit_code, bool)
        or not 0 <= exit_code <= 255
        or not isinstance(timed_out, bool)
        or not isinstance(output_exceeded, bool)
        or timed_out and output_exceeded
        or not isinstance(duration_ms, int)
        or isinstance(duration_ms, bool)
        or duration_ms < 0
    ):
        return _protocol_failure('broker envelope state is invalid')

    if return_code != exit_code:
        return _protocol_failure('broker exit status does not match its envelope')
    fixed_exit_code = BROKER_FIXED_STATUS_EXIT_CODES.get(status)
    if fixed_exit_code is not None and exit_code != fixed_exit_code:
        return _protocol_failure('broker status and exit code are inconsistent')
    if envelope.get('canonical_id') != canonical_id:
        return _protocol_failure('broker canonical ID does not match the request')

    name = envelope.get('name')
    owner = envelope.get('owner')
    audit_id = envelope.get('audit_id')
    error = envelope.get('error')
    if (
        (name is not None and (
            not isinstance(name, str)
            or not BROKER_FUNCTION_RE.fullmatch(name)
            or name != func_name
        ))
        or not isinstance(owner, str)
        or not BROKER_OWNER_RE.fullmatch(owner)
        or owner != expected_owner
        or not isinstance(audit_id, str)
        or not BROKER_AUDIT_ID_RE.fullmatch(audit_id)
        or (error is not None and not isinstance(error, str))
    ):
        return _protocol_failure('broker envelope identity is invalid')

    if (
        (ok and (
            status != 'success'
            or exit_code != 0
            or timed_out
            or output_exceeded
            or error is not None
            or name != func_name
        ))
        or (not ok and (status == 'success' or exit_code == 0))
        or (timed_out != (status == 'timeout'))
        or (output_exceeded != (status == 'output_limit'))
        or (timed_out and exit_code != 124)
        or (output_exceeded and exit_code != 74)
    ):
        return _protocol_failure('broker envelope result is inconsistent')

    try:
        decoded_stdout = _decode_canonical_base64(
            envelope['stdout_b64'], 'stdout_b64'
        )
        decoded_stderr = _decode_canonical_base64(
            envelope['stderr_b64'], 'stderr_b64'
        )
    except ValueError as decode_error:
        return _protocol_failure(str(decode_error))
    if (
        not isinstance(contract_output_limit, int)
        or isinstance(contract_output_limit, bool)
        or not 1 <= contract_output_limit <= BROKER_DECODED_OUTPUT_LIMIT
    ):
        return _protocol_failure('reviewed output ceiling is invalid')
    if len(decoded_stdout) + len(decoded_stderr) > contract_output_limit:
        return _protocol_failure('decoded broker output exceeds its reviewed ceiling')
    if expected_result_kind not in BROKER_RESULT_KINDS:
        return _protocol_failure('reviewed result kind is invalid')
    if expected_result_kind in {'exit', 'none'} and decoded_stdout:
        return _protocol_failure(
            'decoded stdout violates the reviewed result kind'
        )

    try:
        stdout = decoded_stdout.decode('utf-8')
        stderr = decoded_stderr.decode('utf-8')
    except UnicodeDecodeError:
        return _protocol_failure('broker payload is not UTF-8 text')

    if identity_out is not None:
        identity_out.update({
            'audit_id': audit_id,
            'status': status,
            'duration_ms': duration_ms,
        })
    if not ok and error:
        stderr = f'{error}\n{stderr}' if stderr else error
    return ok, stdout, stderr


def _control_plane_protocol_failure(detail: str) -> Tuple[bool, str, str]:
    return (
        False,
        '',
        f'invocation denied: control-plane protocol error: {detail}',
    )


def _valid_kernel_id(field: str, value: Any) -> bool:
    pattern = CONTROL_PLANE_ID_PATTERNS[field]
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def _expected_broker_receipt(envelope: Dict[str, Any]) -> Dict[str, Any]:
    stdout = _decode_canonical_base64(envelope['stdout_b64'], 'stdout_b64')
    stderr = _decode_canonical_base64(envelope['stderr_b64'], 'stderr_b64')
    error_value = envelope['error']
    if error_value is None:
        error = b''
    elif isinstance(error_value, str):
        error = error_value.encode('utf-8')
    else:
        raise ValueError('broker error is not text')
    return {
        field: envelope[field]
        for field in (
            'schema_version',
            'ok',
            'status',
            'canonical_id',
            'name',
            'owner',
            'exit_code',
            'timed_out',
            'output_exceeded',
            'duration_ms',
            'audit_id',
        )
    } | {
        'stdout_bytes': len(stdout),
        'stdout_sha256': hashlib.sha256(stdout).hexdigest(),
        'stderr_bytes': len(stderr),
        'stderr_sha256': hashlib.sha256(stderr).hexdigest(),
        'error_bytes': len(error),
        'error_sha256': hashlib.sha256(error).hexdigest(),
    }


def _valid_standalone_receipt(
    receipt: Any,
    canonical_id: str,
    func_name: str,
    expected_owner: str,
) -> bool:
    if not isinstance(receipt, dict) or set(receipt) != CONTROL_PLANE_RECEIPT_FIELDS:
        return False
    if (
        type(receipt['schema_version']) is not int
        or receipt['schema_version'] != 1
        or type(receipt['ok']) is not bool
        or receipt['status'] not in BROKER_STATUSES
        or receipt['canonical_id'] != canonical_id
        or receipt['name'] != func_name
        or receipt['owner'] != expected_owner
        or type(receipt['exit_code']) is not int
        or not 0 <= receipt['exit_code'] <= 255
        or type(receipt['timed_out']) is not bool
        or type(receipt['output_exceeded']) is not bool
        or receipt['timed_out'] and receipt['output_exceeded']
        or type(receipt['duration_ms']) is not int
        or receipt['duration_ms'] < 0
        or not isinstance(receipt['audit_id'], str)
        or BROKER_AUDIT_ID_RE.fullmatch(receipt['audit_id']) is None
    ):
        return False
    fixed_exit_code = BROKER_FIXED_STATUS_EXIT_CODES.get(receipt['status'])
    if (
        (fixed_exit_code is not None and receipt['exit_code'] != fixed_exit_code)
        or (receipt['ok'] != (receipt['status'] == 'success'))
        or (receipt['timed_out'] != (receipt['status'] == 'timeout'))
        or (receipt['output_exceeded'] != (receipt['status'] == 'output_limit'))
    ):
        return False
    for prefix in ('stdout', 'stderr', 'error'):
        byte_count = receipt[f'{prefix}_bytes']
        digest = receipt[f'{prefix}_sha256']
        if (
            type(byte_count) is not int
            or byte_count < 0
            or not isinstance(digest, str)
            or SHA256_RE.fullmatch(digest) is None
        ):
            return False
    return True


def _decode_control_plane_envelope(
    stdout_bytes: bytes,
    stderr_bytes: bytes,
    return_code: int,
    canonical_id: str,
    func_name: str,
    expected_owner: str,
    contract_output_limit: int,
    expected_result_kind: str,
    client_correlation_id: str,
    expected_input_digest: str,
    *,
    identity_out: Optional[Dict[str, Any]] = None,
) -> Tuple[bool, str, str]:
    """Validate control-plane-json-v1 before exposing durable identities."""
    if identity_out is not None:
        identity_out.clear()
    if stderr_bytes:
        return _control_plane_protocol_failure(
            'public invoke wrote outside its JSON result envelope'
        )
    try:
        document = json.loads(
            stdout_bytes.decode('utf-8'),
            object_pairs_hook=_json_object_without_duplicates,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        return _control_plane_protocol_failure(
            'public invoke returned invalid JSON'
        )
    if return_code != 0:
        return _control_plane_protocol_failure(
            'public invoke did not return a completed success envelope'
        )
    if (
        not isinstance(document, dict)
        or set(document) != CONTROL_PLANE_OUTER_FIELDS
        or document.get('ok') is not True
        or document.get('command') != 'canonical-invoke'
        or not isinstance(document.get('result'), dict)
    ):
        return _control_plane_protocol_failure(
            'control-plane envelope shape is invalid'
        )
    result = document['result']
    if set(result) != CONTROL_PLANE_RESULT_FIELDS:
        return _control_plane_protocol_failure(
            'control-plane result shape is invalid'
        )
    if (
        type(result['schema_version']) is not int
        or result['schema_version'] != 1
        or result['status'] not in {'in_progress', 'completed'}
        or result['client_correlation_id'] != client_correlation_id
    ):
        return _control_plane_protocol_failure(
            'client correlation or protocol version is invalid'
        )
    if not all(
        _valid_kernel_id(field, result[field])
        for field in ('run_id', 'call_id', 'decision_id')
    ):
        return _control_plane_protocol_failure(
            'kernel durable identity is invalid'
        )
    if (
        not isinstance(result['input_digest'], str)
        or result['input_digest'] != expected_input_digest
        or SHA256_RE.fullmatch(result['input_digest']) is None
    ):
        return _control_plane_protocol_failure(
            'kernel input digest does not match the request'
        )

    identity = {
        'client_correlation_id': result['client_correlation_id'],
        'run_id': result['run_id'],
        'call_id': result['call_id'],
        'decision_id': result['decision_id'],
        'evidence_id': result['evidence_id'],
        'input_digest': result['input_digest'],
        'outcome': result['outcome'],
        'result_available': result['result_available'],
        'broker_receipt': result['broker_receipt'],
    }
    if result['status'] == 'in_progress':
        if (
            result['evidence_id'] is not None
            or result['outcome'] is not None
            or result['result_available'] is not False
            or result['broker_receipt'] is not None
            or result['broker_envelope'] is not None
        ):
            return _control_plane_protocol_failure(
                'in-progress result carries terminal fields'
            )
        if identity_out is not None:
            identity_out.update(identity)
        return _control_plane_protocol_failure(
            'durable execution is still in progress'
        )

    if (
        not _valid_kernel_id('evidence_id', result['evidence_id'])
        or result['outcome'] not in {
            'succeeded', 'failed', 'timed_out', 'interrupted'
        }
        or type(result['result_available']) is not bool
    ):
        return _control_plane_protocol_failure(
            'terminal durable identity is invalid'
        )
    receipt = result['broker_receipt']
    envelope = result['broker_envelope']
    if receipt is not None and not _valid_standalone_receipt(
        receipt,
        canonical_id,
        func_name,
        expected_owner,
    ):
        return _control_plane_protocol_failure(
            'durable broker receipt is invalid'
        )
    if (
        isinstance(receipt, dict)
        and receipt['stdout_bytes'] + receipt['stderr_bytes']
        > contract_output_limit
    ):
        return _control_plane_protocol_failure(
            'durable broker receipt exceeds its reviewed output ceiling'
        )
    if identity_out is not None:
        identity_out.update(identity)
    if result['result_available'] is False:
        if envelope is not None:
            if identity_out is not None:
                identity_out.clear()
            return _control_plane_protocol_failure(
                'unavailable transient result carries a broker envelope'
            )
        return _control_plane_protocol_failure(
            'terminal transient result is unavailable; execution will not be retried'
        )
    if not isinstance(receipt, dict) or not isinstance(envelope, dict):
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'available result lacks its receipt or broker envelope'
        )
    try:
        inner_bytes = json.dumps(
            envelope,
            ensure_ascii=False,
            separators=(',', ':'),
            sort_keys=True,
        ).encode('utf-8')
    except (TypeError, ValueError, UnicodeEncodeError):
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'broker envelope cannot be canonically encoded'
        )
    raw_exit_code = envelope.get('exit_code')
    if type(raw_exit_code) is not int:
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'broker envelope exit code is invalid'
        )
    broker_identity: Dict[str, Any] = {}
    inner_ok, stdout, stderr = _decode_broker_envelope(
        inner_bytes,
        b'',
        raw_exit_code,
        canonical_id,
        func_name,
        expected_owner,
        contract_output_limit,
        expected_result_kind,
        identity_out=broker_identity,
    )
    if broker_identity == {}:
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            f'inner {stderr}'
        )
    if inner_ok and result['outcome'] != 'succeeded':
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'broker envelope contradicts the durable outcome'
        )
    if (
        not inner_ok
        and result['outcome']
        != ('timed_out' if envelope.get('status') == 'timeout' else 'failed')
    ):
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'broker envelope contradicts the durable outcome'
        )
    try:
        expected_receipt = _expected_broker_receipt(envelope)
    except (KeyError, ValueError):
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'broker receipt cannot be derived from the envelope'
        )
    if receipt != expected_receipt:
        if identity_out is not None:
            identity_out.clear()
        return _control_plane_protocol_failure(
            'durable broker receipt does not bind the transient envelope'
        )
    return inner_ok, stdout, stderr


class BashExecutor:
    """Executes reviewed MAINFRAME calls through the public control plane."""

    def __init__(
        self,
        mainframe_root: Optional[str] = None,
        runtime: Optional[RuntimeIdentity] = None,
    ):
        if runtime is not None and mainframe_root is not None:
            raise ValueError('provide runtime or mainframe_root, not both')
        self.runtime = runtime
        self.mainframe_root = (
            str(runtime.root)
            if runtime is not None
            else resolve_mainframe_root(mainframe_root)
        )
        self.mainframe_cli = os.path.join(
            self.mainframe_root, 'bin', 'mainframe'
        )
        self.development_state_home: Optional[str] = None
        if runtime is not None and runtime.integrity == 'explicit-development-root':
            raw_state_home = os.environ.get('XDG_STATE_HOME')
            if raw_state_home is not None:
                if (
                    not os.path.isabs(raw_state_home)
                    or any(
                        ord(character) < 32 or ord(character) == 127
                        for character in raw_state_home
                    )
                ):
                    raise RuntimeError(
                        'development XDG_STATE_HOME must be an absolute safe path'
                    )
                self.development_state_home = str(
                    Path(raw_state_home).resolve(strict=False)
                )
        self.broker_timeout = BROKER_OUTER_TIMEOUT_SECONDS
        self.broker_output_limit = BROKER_OUTER_OUTPUT_LIMIT

    def execute_control_plane(
        self,
        func_name: str,
        canonical_id: str,
        arguments: Dict[str, Any],
        expected_owner: str,
        contract_output_limit: int,
        expected_result_kind: str,
        client_correlation_id: str,
        *,
        identity_out: Optional[Dict[str, Any]] = None,
    ) -> Tuple[bool, str, str]:
        """Execute one reviewed call through the public atomic kernel route."""
        if identity_out is not None:
            identity_out.clear()
        if self.runtime is not None:
            self.runtime.assert_current()
        try:
            validate_function_name(func_name)
        except AuthorizationError as error:
            return False, '', f'invocation denied ({error.reason}): {error.detail}'
        if (
            not isinstance(canonical_id, str)
            or BROKER_CANONICAL_ID_RE.fullmatch(canonical_id) is None
        ):
            return False, '', 'invocation denied: canonical ID is invalid'
        if (
            not isinstance(expected_owner, str)
            or BROKER_OWNER_RE.fullmatch(expected_owner) is None
            or not isinstance(contract_output_limit, int)
            or isinstance(contract_output_limit, bool)
            or not 1 <= contract_output_limit <= BROKER_DECODED_OUTPUT_LIMIT
            or expected_result_kind not in BROKER_RESULT_KINDS
        ):
            return False, '', 'invocation denied: reviewed control-plane contract is invalid'
        if (
            not isinstance(client_correlation_id, str)
            or CONTROL_PLANE_CLIENT_ID_RE.fullmatch(client_correlation_id) is None
        ):
            return False, '', 'invocation denied: client correlation is invalid'
        if not isinstance(arguments, dict):
            return False, '', 'invocation denied: control-plane input must be an object'
        if (
            not os.path.isabs(self.mainframe_cli)
            or not os.path.isfile(self.mainframe_cli)
            or not os.access(self.mainframe_cli, os.X_OK)
        ):
            return False, '', 'invocation denied: public control-plane route is unavailable'
        try:
            input_bytes = json.dumps(
                arguments,
                allow_nan=False,
                ensure_ascii=False,
                separators=(',', ':'),
                sort_keys=True,
            ).encode('utf-8')
        except (TypeError, ValueError, UnicodeEncodeError):
            return False, '', 'invocation denied: arguments are not canonical JSON'
        if len(input_bytes) > BROKER_INPUT_LIMIT:
            return False, '', 'invocation denied: JSON request exceeds 32768 bytes'
        input_digest = hashlib.sha256(input_bytes).hexdigest()
        command = [
            self.mainframe_cli,
            'invoke',
            canonical_id,
            '--input-json',
            '-',
            '--profile',
            'stable-core',
            '--format',
            'control-plane-json-v1',
            '--caller',
            'mcp',
            '--client-correlation-id',
            client_correlation_id,
        ]
        if identity_out is not None:
            identity_out.update({
                'client_correlation_id': client_correlation_id,
                'binding_status': 'adapter-local-unverified',
            })
        try:
            return_code, stdout, stderr, timed_out, output_exceeded = (
                _bounded_broker_run(
                    command,
                    input_bytes,
                    _execution_environment(
                        self.mainframe_root,
                        self.development_state_home,
                    ),
                    self.broker_timeout,
                    self.broker_output_limit,
                )
            )
        except Exception:
            return False, '', (
                'invocation denied: public control-plane execution failed; '
                f'client correlation {client_correlation_id} is non-authorizing '
                'lookup/retry metadata and no legacy fallback was attempted'
            )
        if timed_out:
            return False, '', (
                f'Function {func_name} exceeded the MCP outer wait boundary; '
                'cancellation is not claimed and durable execution may still settle; '
                f'use client correlation {client_correlation_id} for public '
                'control-plane lookup/retry; no legacy fallback was attempted'
            )
        if output_exceeded:
            return False, '', (
                f'Function {func_name} exceeded the control-plane output ceiling'
            )
        return _decode_control_plane_envelope(
            stdout,
            stderr,
            return_code,
            canonical_id,
            func_name,
            expected_owner,
            contract_output_limit,
            expected_result_kind,
            client_correlation_id,
            input_digest,
            identity_out=identity_out,
        )

"""Bash execution engine for running MAINFRAME functions."""

import base64
import binascii
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


MINIMUM_BASH_VERSION = (4, 4)
FIXED_BASH_CANDIDATES = (
    '/opt/homebrew/bin/bash',
    '/usr/local/bin/bash',
    '/run/current-system/sw/bin/bash',
    '/nix/var/nix/profiles/default/bin/bash',
    '/usr/bin/bash',
    '/bin/bash',
)
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

# Values controlled by the caller are passed after this fixed script as Bash
# positional parameters. Neither MAINFRAME_ROOT nor argv is interpolated into
# shell source text.
EXECUTION_SCRIPT = r'''
export MAINFRAME_LIBS="all"
mainframe_common_sh=$1
mainframe_func=$2
shift 2
if ! source "$mainframe_common_sh" 2>/dev/null; then
    printf "invocation denied: MAINFRAME initialization failed\n" >&2
    exit 126
fi
export MAINFRAME_OUTPUT=json
if declare -F -- "$mainframe_func" >/dev/null 2>&1; then
    "$mainframe_func" "$@"
else
    printf "invocation denied: '%s' is not a declared MAINFRAME function\n" \
        "$mainframe_func" >&2
    exit 127
fi
'''


def _bash_layout_is_known(candidate: str) -> bool:
    """Match the fixed Bash layouts reviewed by the CLI and Pi adapter."""
    if candidate in {
        '/bin/bash',
        '/usr/bin/bash',
        '/usr/local/bin/bash',
        '/opt/local/bin/bash',
    }:
        return True
    return any(
        pattern.fullmatch(candidate)
        for pattern in (
            re.compile(r'/nix/store/[^/]+/bin/bash'),
            re.compile(r'/opt/homebrew/Cellar/bash/[^/]+/bin/bash'),
            re.compile(r'/usr/local/Cellar/bash/[^/]+/bin/bash'),
            re.compile(
                r'/home/linuxbrew/\.linuxbrew/Cellar/bash/[^/]+/bin/bash'
            ),
        )
    )


def _resolve_safe_bash_candidate(candidate: str) -> Optional[str]:
    """Canonicalize and authenticate a Bash path without executing it."""
    if (
        not isinstance(candidate, str)
        or not os.path.isabs(candidate)
        or any(ord(character) < 32 or ord(character) == 127 for character in candidate)
    ):
        return None
    try:
        resolved = str(Path(candidate).resolve(strict=True))
        candidate_stat = os.stat(resolved)
    except (OSError, RuntimeError):
        return None
    if (
        not _bash_layout_is_known(resolved)
        or not os.path.isfile(resolved)
        or os.path.islink(resolved)
        or not os.access(resolved, os.X_OK)
    ):
        return None
    mode = candidate_stat.st_mode & 0o7777
    if (
        candidate_stat.st_uid not in {0, os.geteuid()}
        or mode & 0o022
        or mode & 0o7000
        or not mode & 0o100
    ):
        return None
    return resolved


def _probe_bash_version(candidate: str) -> Optional[Tuple[int, int]]:
    """Probe one already-authenticated Bash executable."""

    try:
        result = subprocess.run(
            [
                candidate,
                '--noprofile',
                '--norc',
                '-p',
                '-c',
                'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
            ],
            capture_output=True,
            text=True,
            timeout=5,
            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        )
        if result.returncode != 0:
            return None
        major, minor = (int(value) for value in result.stdout.split())
        return major, minor
    except (OSError, subprocess.SubprocessError, TypeError, ValueError):
        return None


def _resolve_bash() -> str:
    """Resolve a trusted-location Bash 4.4+ executable or fail closed.

    MAINFRAME libraries require modern Bash features. Every path is
    canonicalized and checked for a reviewed CLI/Pi layout, trusted ownership,
    and non-writable mode before its first version probe. PATH is never used.
    """
    override = os.environ.get('MAINFRAME_BASH')
    if override:
        if not os.path.isabs(override):
            raise RuntimeError('MAINFRAME_BASH must be an absolute path')
        resolved = _resolve_safe_bash_candidate(override)
        if resolved is None:
            raise RuntimeError(
                'MAINFRAME_BASH must resolve to a safe supported Bash installation'
            )
        version = _probe_bash_version(resolved)
        if version is None or version < MINIMUM_BASH_VERSION:
            raise RuntimeError('MAINFRAME_BASH must be executable Bash 4.4 or newer')
        return resolved

    for candidate in FIXED_BASH_CANDIDATES:
        resolved = _resolve_safe_bash_candidate(candidate)
        if resolved is None:
            continue
        version = _probe_bash_version(resolved)
        if version is not None and version >= MINIMUM_BASH_VERSION:
            return resolved

    raise RuntimeError(
        'MAINFRAME MCP requires Bash 4.4 or newer at a supported absolute path'
    )


def _execution_environment(mainframe_root: str) -> dict[str, str]:
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
    # The MCP process chooses the broker's private state directory; callers
    # cannot redirect read/pure invocation audits into an arbitrary file.
    state_home = _account_state_home()
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
) -> Tuple[bool, str, str]:
    """Strictly validate broker-json-v1 and restore legacy return semantics."""
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

    if not ok and error:
        stderr = f'{error}\n{stderr}' if stderr else error
    return ok, stdout, stderr


class BashExecutor:
    """Executes MAINFRAME bash functions via subprocess."""

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
        self.common_sh = os.path.join(self.mainframe_root, 'lib', 'common.sh')
        self.mainframe_cli = os.path.join(
            self.mainframe_root, 'bin', 'mainframe'
        )
        self._bash: Optional[str] = None
        self.timeout = 30  # Default timeout in seconds
        self.broker_timeout = BROKER_OUTER_TIMEOUT_SECONDS
        self.broker_output_limit = BROKER_OUTER_OUTPUT_LIMIT

    @property
    def bash(self) -> str:
        """Resolve Bash only when the explicit legacy executor needs it."""
        if self._bash is None:
            self._bash = _resolve_bash()
        return self._bash

    def execute_broker(
        self,
        func_name: str,
        canonical_id: str,
        arguments: Dict[str, Any],
        expected_owner: str,
        contract_output_limit: int,
        expected_result_kind: str,
    ) -> Tuple[bool, str, str]:
        """Delegate a stable-core call to the canonical invocation broker."""
        if self.runtime is not None:
            self.runtime.assert_current()
        try:
            validate_function_name(func_name)
        except AuthorizationError as error:
            return False, '', f'invocation denied ({error.reason}): {error.detail}'
        if (
            not isinstance(canonical_id, str)
            or not BROKER_CANONICAL_ID_RE.fullmatch(canonical_id)
        ):
            return False, '', 'invocation denied: canonical ID is invalid'
        if (
            not isinstance(expected_owner, str)
            or not BROKER_OWNER_RE.fullmatch(expected_owner)
            or not isinstance(contract_output_limit, int)
            or isinstance(contract_output_limit, bool)
            or not 1 <= contract_output_limit <= BROKER_DECODED_OUTPUT_LIMIT
            or expected_result_kind not in BROKER_RESULT_KINDS
        ):
            return False, '', 'invocation denied: reviewed broker contract is invalid'
        if not isinstance(arguments, dict):
            return False, '', 'invocation denied: broker requires a JSON object'
        if (
            not os.path.isabs(self.mainframe_cli)
            or not os.path.isfile(self.mainframe_cli)
            or not os.access(self.mainframe_cli, os.X_OK)
        ):
            return False, '', 'invocation denied: canonical broker is unavailable'

        try:
            input_bytes = json.dumps(
                arguments,
                ensure_ascii=False,
                separators=(',', ':'),
            ).encode('utf-8')
        except (TypeError, ValueError, UnicodeEncodeError):
            return False, '', 'invocation denied: arguments are not valid JSON'
        if len(input_bytes) > BROKER_INPUT_LIMIT:
            return False, '', 'invocation denied: JSON request exceeds 32768 bytes'

        command = [
            self.mainframe_cli,
            'invoke',
            canonical_id,
            '--input-json',
            '-',
            '--profile',
            'stable-core',
            '--format',
            'broker-json-v1',
            '--caller',
            'mcp',
        ]
        try:
            return_code, stdout, stderr, timed_out, output_exceeded = (
                _bounded_broker_run(
                    command,
                    input_bytes,
                    _execution_environment(self.mainframe_root),
                    self.broker_timeout,
                    self.broker_output_limit,
                )
            )
        except Exception as error:
            return False, '', f'Execution error: {str(error)}'

        if timed_out:
            return (
                False,
                '',
                f'Function {func_name} timed out at the outer broker boundary '
                f'after {self.broker_timeout:g}s',
            )
        if output_exceeded:
            return (
                False,
                '',
                f'Function {func_name} exceeded the outer broker output ceiling',
            )
        return _decode_broker_envelope(
            stdout,
            stderr,
            return_code,
            canonical_id,
            func_name,
            expected_owner,
            contract_output_limit,
            expected_result_kind,
        )

    def execute(
        self, func_name: str, argv: Sequence[str]
    ) -> Tuple[bool, str, str]:
        """Execute a MAINFRAME function.

        Args:
            func_name: Name of the function to call
            argv: Prepared positional string arguments. Raw MCP mappings are
                rejected and must first pass server-side metadata validation.

        Returns:
            Tuple of (success, stdout, stderr)
        """
        if self.runtime is not None:
            self.runtime.assert_current()

        # Defense-in-depth: even if a caller bypasses the server-layer
        # authorization gate, never interpolate a non-identifier into bash.
        try:
            validate_function_name(func_name)
        except AuthorizationError as e:
            return False, '', f'invocation denied ({e.reason}): {e.detail}'

        if not isinstance(argv, (list, tuple)) or any(
            not isinstance(value, str) for value in argv
        ):
            return False, '', 'invocation denied: executor requires prepared argv'

        try:
            result = subprocess.run(
                [
                    self.bash,
                    '--noprofile',
                    '--norc',
                    '-p',
                    '-c',
                    EXECUTION_SCRIPT,
                    'mainframe-mcp',
                    self.common_sh,
                    func_name,
                    *argv,
                ],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env=_execution_environment(self.mainframe_root),
            )

            success = result.returncode == 0
            return success, result.stdout, result.stderr

        except subprocess.TimeoutExpired:
            return False, '', f'Function {func_name} timed out after {self.timeout}s'
        except Exception as e:
            return False, '', f'Execution error: {str(e)}'

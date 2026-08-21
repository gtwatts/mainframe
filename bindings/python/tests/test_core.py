"""
Tests for mainframe_bash.core module.
"""

import base64
import hashlib
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

from mainframe_bash.core import (
    MainframeBrokerError,
    MainframeError,
    MainframeFunctionError,
    MainframeNotFoundError,
    _approved_bash_layout,
    _bash_escape,
    _convert_arg,
    _resolve_bash,
    _validate_mainframe_root,
    call_function,
    call_function_json,
    exec_bash,
    get_mainframe_root,
    invoke_canonical,
)

_DURABLE_CLOSURE_FILES = (
    "bin/mainframe",
    "lib/common.sh",
    "lib/durable_invoke.sh",
    "control_plane/mainframe-control-plane",
    "control_plane/mainframe_control_plane/__init__.py",
    "control_plane/mainframe_control_plane/cli.py",
    "control_plane/mainframe_control_plane/coding.py",
    "control_plane/mainframe_control_plane/contracts.py",
    "control_plane/mainframe_control_plane/durability.py",
    "control_plane/mainframe_control_plane/errors.py",
    "control_plane/mainframe_control_plane/executor.py",
    "control_plane/mainframe_control_plane/kernel.py",
    "control_plane/mainframe_control_plane/memory.py",
    "control_plane/mainframe_control_plane/transient.py",
    "control_plane/mainframe_control_plane/worker.py",
)


def _write_durable_closure_fixture(root: Path) -> None:
    for relative in _DURABLE_CLOSURE_FILES:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("# fixture\n", encoding="utf-8")
        if relative in {"bin/mainframe", "control_plane/mainframe-control-plane"}:
            path.chmod(0o755)


def _control_plane_response_fixture(
    envelope: dict[str, object], input_json: str = '{"value":"hello"}'
) -> dict[str, object]:
    stdout = base64.b64decode(str(envelope.get("stdout_b64", "")), validate=True)
    stderr = base64.b64decode(str(envelope.get("stderr_b64", "")), validate=True)
    error = b"" if envelope.get("error") is None else str(envelope["error"]).encode()
    receipt = {
        key: envelope[key]
        for key in (
            "schema_version", "ok", "status", "canonical_id", "name", "owner",
            "exit_code", "timed_out", "output_exceeded", "duration_ms", "audit_id",
        )
    }
    receipt.update({
        "stdout_bytes": len(stdout),
        "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
        "stderr_bytes": len(stderr),
        "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
        "error_bytes": len(error),
        "error_sha256": hashlib.sha256(error).hexdigest(),
    })
    return {
        "ok": True,
        "command": "canonical-invoke",
        "result": {
            "schema_version": 1,
            "status": "completed",
            "client_correlation_id": "__CID__",
            "run_id": "run-11111111111111111111111111111111",
            "call_id": "call-22222222222222222222222222222222",
            "decision_id": "decision-33333333333333333333333333333333",
            "evidence_id": "evidence-44444444444444444444444444444444",
            "input_digest": hashlib.sha256(input_json.encode()).hexdigest(),
            "outcome": "succeeded" if envelope.get("ok") is True else (
                "timed_out" if envelope.get("timed_out") is True else "failed"
            ),
            "result_available": True,
            "broker_receipt": receipt,
            "broker_envelope": envelope,
        },
    }


def _control_plane_fixture_source(
    envelope: dict[str, object], checks: str = ""
) -> str:
    serialized = json.dumps(
        _control_plane_response_fixture(envelope), separators=(",", ":")
    )
    return _control_plane_raw_fixture_source(serialized, checks)


def _control_plane_raw_fixture_source(serialized: str, checks: str = "") -> str:
    before, after = serialized.split("__CID__")
    return (
        "#!/bin/sh\n"
        f"{checks}\n"
        "IFS= read -r payload\n"
        "[ \"$payload\" = '{\"value\":\"hello\"}' ] || exit 70\n"
        f"printf '%s%s%s\\n' {shlex.quote(before)} \"${{12}}\" {shlex.quote(after)}\n"
    )


def _write_broker_fixture(
    root: Path,
    marker: Path,
    *,
    malformation: str | None = None,
    executable_source: str | None = None,
) -> str:
    canonical_id = "mf:data:json:json_string"
    _write_durable_closure_fixture(root)
    contract = {
        "name": "json_string",
        "owner": "json",
        "result": {"kind": "stdout"},
        "contract_status": "reviewed",
        "profiles": ["stable-core"],
        "effects": ["pure"],
        "capabilities": [],
        "input_schema": {
            "type": "object",
            "properties": {"value": {"type": "string"}},
            "required": ["value"],
            "additionalProperties": False,
        },
        "call_shape": {
            "kind": "argv",
            "arguments": [{"field": "value", "mode": "scalar"}],
        },
        "timeout_ms": 5000,
        "output_limit": 65536,
    }
    if malformation == "result-kind":
        contract["result"] = {"kind": "stream"}
    elif malformation == "result-extra":
        contract["result"] = {"kind": "stdout", "extra": True}
    elif malformation == "schema-extra":
        contract["input_schema"]["extra"] = True
    elif malformation == "argument-extra":
        contract["call_shape"]["arguments"][0]["extra"] = True

    (root / "lib").mkdir(exist_ok=True)
    (root / "lib" / "common.sh").write_text("# fixture\n")
    (root / "bin").mkdir(exist_ok=True)
    executable = root / "bin" / "mainframe"
    executable.write_text(
        executable_source
        or f"#!/bin/sh\nprintf ran > {str(marker)!r}\n",
        encoding="utf-8",
    )
    executable.chmod(0o755)
    (root / "MANIFEST.json").write_text(
        json.dumps({
            "manifest_version": 1,
            "exports": {canonical_id: contract},
            "name_index": {"json_string": canonical_id},
        }),
        encoding="utf-8",
    )
    return canonical_id


def _broker_envelope_fixture(**overrides):
    envelope = {
        "schema_version": 1,
        "ok": False,
        "status": "function_error",
        "canonical_id": "mf:data:json:json_string",
        "name": "json_string",
        "owner": "json",
        "exit_code": 1,
        "timed_out": False,
        "output_exceeded": False,
        "duration_ms": 0,
        "audit_id": "inv-fixture",
        "stdout_b64": "",
        "stderr_b64": "",
        "error": None,
    }
    envelope.update(overrides)
    return envelope


def _nested_group_broker_source(
    marker: Path, *, ready: Path | None = None, output_overflow: bool = False
) -> str:
    overflow = ""
    if output_overflow:
        overflow = (
            f"chunk={'x' * 4096!r}\n"
            "for ((i=0; i<900; i++)); do printf '%s' \"$chunk\"; done\n"
        )
    ready_line = f"/usr/bin/touch {str(ready)!r}\n" if ready is not None else ""
    return (
        "#!/bin/bash\n"
        "set -m\n"
        "nested_pid=\n"
        "nested_pgid=\n"
        "cleanup_started=0\n"
        "cleanup() {\n"
        "  if [ \"$cleanup_started\" -ne 0 ]; then return; fi\n"
        "  cleanup_started=1\n"
        "  trap - TERM INT HUP EXIT\n"
        "  if [ -n \"$nested_pgid\" ]; then\n"
        "    kill -TERM -- \"-$nested_pgid\" 2>/dev/null || true\n"
        "    /bin/sleep 0.2\n"
        "    kill -KILL -- \"-$nested_pgid\" 2>/dev/null || true\n"
        "  fi\n"
        "  if [ -n \"$nested_pid\" ]; then wait \"$nested_pid\" 2>/dev/null || true; fi\n"
        "  exit 143\n"
        "}\n"
        "trap cleanup TERM INT HUP EXIT\n"
        f"(/bin/sleep 1.5; /usr/bin/touch {str(marker)!r}) &\n"
        "nested_pid=$!\n"
        "nested_pgid=$(/bin/ps -o pgid= -p \"$nested_pid\" | /usr/bin/tr -d ' ')\n"
        f"{ready_line}{overflow}"
        "while :; do :; done\n"
    )


class TestMainframeDetection:
    """Tests for MAINFRAME root detection."""

    def test_get_mainframe_root_finds_installation(self):
        """Should find MAINFRAME installation."""
        root = get_mainframe_root()
        assert root.is_dir()
        assert (root / "lib" / "common.sh").is_file()

    def test_get_mainframe_root_respects_env_var(self, monkeypatch, tmp_path):
        """Should use MAINFRAME_ROOT environment variable."""
        # Create a fake installation with the exact durable execution closure.
        _write_durable_closure_fixture(tmp_path)

        # Clear cache
        import mainframe_bash.core as core
        core._mainframe_root = None

        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        root = get_mainframe_root()
        assert root == tmp_path

        # Reset for other tests
        core._mainframe_root = None
        monkeypatch.delenv("MAINFRAME_ROOT", raising=False)

    def test_validate_mainframe_root_valid(self):
        """Should validate correct installation."""
        root = get_mainframe_root()
        assert _validate_mainframe_root(root) is True

    def test_validate_mainframe_root_invalid(self, tmp_path):
        """Should reject invalid paths."""
        assert _validate_mainframe_root(tmp_path) is False
        assert _validate_mainframe_root(tmp_path / "nonexistent") is False

    def test_managed_launcher_without_durable_closure_is_rejected(self, monkeypatch):
        import mainframe_bash.core as core

        launcher = Path.home() / ".local" / "bin" / "mainframe"
        managed = launcher.resolve(strict=True).parent.parent
        monkeypatch.delenv("MAINFRAME_ROOT", raising=False)
        core._mainframe_root = None

        with pytest.raises(MainframeNotFoundError, match="installation not found"):
            get_mainframe_root()
        assert _validate_mainframe_root(managed) is False

    def test_explicit_invalid_root_never_falls_back_or_uses_cache(
        self, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        cached_root = get_mainframe_root()
        core._mainframe_root = cached_root

        for invalid_root in ("", str(tmp_path / "missing")):
            monkeypatch.setenv("MAINFRAME_ROOT", invalid_root)
            with pytest.raises(MainframeNotFoundError, match="MAINFRAME_ROOT is set"):
                get_mainframe_root()


class TestBashResolution:
    """Tests for the binding's required Bash runtime floor."""

    @staticmethod
    def _fake_bash(path: Path, version: str, marker: Path | None = None) -> None:
        major, minor = version.split(".")
        marker_line = ""
        if marker is not None:
            marker_line = f"printf ran > {str(marker)!r}\n"
        path.write_text(
            "#!/bin/sh\n"
            f"{marker_line}"
            'if [ "$1" != "--noprofile" ] || [ "$2" != "--norc" ] || '
            '[ "$3" != "-p" ] || [ "$4" != "-c" ]; then\n'
            "  exit 64\n"
            "fi\n"
            f"printf '%s %s' '{major}' '{minor}'\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def test_rejects_explicit_bash_4_3(self, monkeypatch, tmp_path):
        """An explicit outdated interpreter must fail instead of falling back."""
        import mainframe_bash.core as core

        fake_bash = tmp_path / "bash-4.3"
        self._fake_bash(fake_bash, "4.3")
        core._RESOLVED_BASH = None
        monkeypatch.setenv("MAINFRAME_BASH", str(fake_bash))

        with pytest.raises(RuntimeError, match="approved installation layout"):
            _resolve_bash()

    def test_rejects_unapproved_temporary_bash_even_at_4_4(
        self, monkeypatch, tmp_path
    ):
        """Version compatibility cannot override the approved-layout policy."""
        import mainframe_bash.core as core

        fake_bash = tmp_path / "bash-4.4"
        alias = tmp_path / "bash-alias"
        self._fake_bash(fake_bash, "4.4")
        alias.symlink_to(fake_bash)

        core._RESOLVED_BASH = None
        monkeypatch.setenv("MAINFRAME_BASH", str(alias))

        with pytest.raises(RuntimeError, match="approved installation layout"):
            _resolve_bash()
        assert core._RESOLVED_BASH is None

    @pytest.mark.parametrize("override", ["marker-bash", "./marker-bash"])
    def test_rejects_bare_and_relative_override_without_execution(
        self, monkeypatch, tmp_path, override
    ):
        """Rejected overrides must never be searched for or probed."""
        import mainframe_bash.core as core

        marker = tmp_path / "relative-ran"
        fake_bash = tmp_path / "marker-bash"
        self._fake_bash(fake_bash, "5.2", marker)

        core._RESOLVED_BASH = None
        monkeypatch.setenv("MAINFRAME_BASH", override)
        monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ.get('PATH', '')}")
        monkeypatch.chdir(tmp_path)

        with pytest.raises(RuntimeError, match="absolute path"):
            _resolve_bash()
        assert not marker.exists()

    def test_default_resolution_never_executes_path_bash(self, monkeypatch, tmp_path):
        """Ambient PATH is not part of interpreter discovery."""
        import mainframe_bash.core as core

        marker = tmp_path / "path-bash-ran"
        self._fake_bash(tmp_path / "bash", "5.2", marker)
        core._RESOLVED_BASH = None
        monkeypatch.delenv("MAINFRAME_BASH", raising=False)
        monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ.get('PATH', '')}")

        resolved = _resolve_bash()

        assert Path(resolved).is_absolute()
        assert resolved == str(Path(resolved).resolve())
        assert not marker.exists()

    @pytest.mark.parametrize(
        ("launcher", "canonical"),
        [
            ("/opt/local/bin/bash", "/opt/local/bin/bash"),
            (
                "/home/linuxbrew/.linuxbrew/bin/bash",
                "/home/linuxbrew/.linuxbrew/Cellar/bash/5.2.37/bin/bash",
            ),
            (
                "/nix/var/nix/profiles/default/bin/bash",
                "/nix/store/abc123-bash-5.2p37/bin/bash",
            ),
            (
                "/run/current-system/sw/bin/bash",
                "/nix/store/abc123-bash-5.2p37/bin/bash",
            ),
            (
                str(Path.home() / ".nix-profile" / "bin" / "bash"),
                "/nix/store/abc123-bash-5.2p37/bin/bash",
            ),
        ],
        ids=("macports", "linuxbrew", "nix-default", "nixos", "nix-user"),
    )
    def test_automatic_discovery_includes_approved_package_manager_layouts(
        self, launcher, canonical
    ):
        import mainframe_bash.core as core

        assert launcher in core._FIXED_BASH_CANDIDATES
        assert _approved_bash_layout(canonical)

    def test_cached_canonical_bash_resists_per_call_path_swap(
        self, monkeypatch, tmp_path
    ):
        """A per-call PATH must not change the already selected interpreter."""
        import mainframe_bash.core as core

        monkeypatch.delenv("MAINFRAME_BASH", raising=False)
        core._RESOLVED_BASH = None
        trusted_bash = _resolve_bash()
        alias = tmp_path / "trusted-bash-alias"
        alias.symlink_to(trusted_bash)

        core._RESOLVED_BASH = None
        monkeypatch.setenv("MAINFRAME_BASH", str(alias))
        assert _resolve_bash() == str(Path(trusted_bash).resolve())

        marker = tmp_path / "path-swap-ran"
        self._fake_bash(tmp_path / "bash", "5.2", marker)
        output, code = exec_bash(
            'printf "%s" "canonical-safe"',
            env={"PATH": f"{tmp_path}{os.pathsep}{os.environ.get('PATH', '')}"},
        )

        assert code == 0
        assert output == "canonical-safe"
        assert not marker.exists()


class TestBashEscape:
    """Tests for bash string escaping."""

    def test_escape_simple_string(self):
        """Should escape simple strings."""
        assert _bash_escape("hello") == "'hello'"

    def test_escape_empty_string(self):
        """Should handle empty string."""
        assert _bash_escape("") == "''"

    def test_escape_single_quotes(self):
        """Should escape single quotes."""
        assert _bash_escape("it's") == "'it'\\''s'"

    def test_escape_special_chars(self):
        """Should preserve special characters in single quotes."""
        assert _bash_escape("$HOME") == "'$HOME'"
        assert _bash_escape("a b c") == "'a b c'"


class TestConvertArg:
    """Tests for argument conversion."""

    def test_convert_string(self):
        """Should pass through strings."""
        assert _convert_arg("hello") == "hello"

    def test_convert_int(self):
        """Should convert integers to strings."""
        assert _convert_arg(42) == "42"

    def test_convert_float(self):
        """Should convert floats to strings."""
        assert _convert_arg(3.14) == "3.14"

    def test_convert_bool(self):
        """Should convert bools to true/false."""
        assert _convert_arg(True) == "true"
        assert _convert_arg(False) == "false"

    def test_convert_none(self):
        """Should convert None to empty string."""
        assert _convert_arg(None) == ""


class TestCallFunction:
    """Tests for call_function."""

    @pytest.mark.parametrize("name", ["printf", "id", "printenv"])
    def test_external_executables_fail_closed(self, name):
        """Shell builtins and executables are not MAINFRAME broker exports."""
        output, code = call_function(name, "ignored")
        assert code == 126
        assert output == ""

    @pytest.mark.parametrize(
        "name",
        [
            "array_count", "array_filter", "array_first", "array_get",
            "array_intersect", "array_last", "array_length",
            "array_reverse", "array_slice", "array_sum", "array_unique",
            "collection_count", "collection_filter", "collection_first",
            "collection_intersect", "collection_last", "collection_length",
            "collection_reverse", "collection_slice", "collection_sum",
            "collection_unique", "safe_array_get",
            "awm_compress", "awm_handoff_prepare", "awm_handoff_accept",
            "awm_stream_compress", "awm_protocol_handoff_prepare",
            "awm_protocol_handoff_accept",
        ],
    )
    def test_unreviewed_call_shapes_fail_closed(self, name):
        output, code = call_function(name, "ignored")
        assert code == 126
        assert output == ""

    def test_unknown_name_does_not_execute_path_candidate(
        self, monkeypatch, tmp_path
    ):
        """Name-index rejection happens before any ambient executable lookup."""
        marker = tmp_path / "external-ran"
        fake_id = tmp_path / "id"
        fake_id.write_text(
            f"#!/bin/sh\nprintf ran > {str(marker)!r}\n", encoding="utf-8"
        )
        fake_id.chmod(0o755)
        monkeypatch.setenv(
            "PATH", f"{tmp_path}{os.pathsep}{os.environ.get('PATH', '')}"
        )

        output, code = call_function("id")

        assert code == 126
        assert output == ""
        assert not marker.exists()

    def test_call_with_return_code(self):
        """Should capture return codes."""
        # validate_email returns 0 for valid, 1 for invalid
        output, code = call_function("validate_email", "test@example.com")
        assert code == 0
        assert output == ""

        _, code = call_function("validate_email", "not-an-email")
        assert code == 1

    def test_call_captures_output(self):
        """Should decode broker-confined function output."""
        output, code = call_function("json_string", "hello world")
        assert code == 0
        assert output == '"hello world"'

    def test_preserves_exact_leading_and_trailing_whitespace(self):
        output, code = call_function("trim_right", "  keep  ")
        assert code == 0
        assert output == "  keep\n"
        output, code = call_function("trim_left", "  keep  ")
        assert code == 0
        assert output == "keep  \n"

    def test_call_with_env(self):
        """Should accept adapter environment without bypassing the broker."""
        output, code = call_function(
            "json_string",
            "test message",
            capture_stderr=True,
            env={"NO_COLOR": "1"}
        )
        assert code == 0
        assert output == '"test message"'

    def test_ignores_poisoned_bash_env(self, tmp_path):
        """A caller-controlled BASH_ENV must not run before the binding script."""
        marker = tmp_path / "bash-env-ran"
        poison = tmp_path / "poison-bash-env.sh"
        poison.write_text(
            'printf poisoned > "$MAINFRAME_BASH_ENV_MARKER"\nexit 97\n',
            encoding="utf-8",
        )

        output, code = call_function(
            "json_string",
            "binding-safe",
            env={
                "BASH_ENV": str(poison),
                "MAINFRAME_BASH_ENV_MARKER": str(marker),
            },
        )

        assert code == 0
        assert output == '"binding-safe"'
        assert not marker.exists()

    @pytest.mark.parametrize(
        ("variable", "value"),
        [
            ("BASH_ENV", "/tmp/mainframe-should-not-load"),
            ("LD_PRELOAD", "/tmp/mainframe-should-not-load.so"),
            ("DYLD_INSERT_LIBRARIES", "/tmp/mainframe-should-not-load.dylib"),
            ("BASH_FUNC_mainframe_poison%%", "() { :; }"),
            ("RUBYOPT", "-r/tmp/mainframe-should-not-load.rb"),
            ("RUBYLIB", "/tmp/mainframe-should-not-load"),
        ],
    )
    def test_strips_passive_code_loader_environment(self, variable, value):
        """Caller overrides must not reach Bash or any command it starts."""
        output, code = exec_bash(
            f"printenv {variable!r}",
            env={variable: value},
        )

        assert code == 1
        assert output == ""

    def test_rejects_shell_syntax_in_function_name(self):
        """Should not execute shell syntax supplied as a function name."""
        with pytest.raises(ValueError, match="Invalid MAINFRAME function name"):
            call_function("printf; echo injected")

    def test_rejects_path_traversal_in_source_library(self):
        """Should accept only registry-style library paths."""
        with pytest.raises(ValueError, match="Invalid MAINFRAME library name"):
            call_function("printf", "hello", source_libs=["../unsafe"])

    def test_source_library_selection_is_unavailable_for_brokered_calls(self):
        """Reviewed contracts, not callers, select the implementation module."""
        with pytest.raises(ValueError, match="unavailable for brokered calls"):
            call_function("json_string", "hello", source_libs=["json"])


class TestInvokeCanonical:
    """Tests for the rich canonical broker adapter."""

    def test_returns_strict_identity_and_decoded_output(self, tmp_path):
        state_dir = tmp_path / "state"
        state_dir.mkdir(mode=0o700)
        state_dir.chmod(0o700)
        result = invoke_canonical(
            "mf:data:json:json_object",
            {"pairs": ["name=John"]},
            env={"XDG_STATE_HOME": str(state_dir)},
        )

        assert result.schema_version == 1
        assert result.ok is True
        assert result.status == "success"
        assert result.canonical_id == "mf:data:json:json_object"
        assert result.name == "json_object"
        assert result.owner == "json"
        assert result.result_kind == "stdout"
        assert result.exit_code == 0
        assert result.audit_id.startswith("inv-")
        assert result.stdout == '{"name":"John"}'
        assert result.stderr == ""
        assert result.control_plane_status == "completed"
        assert result.outcome == "succeeded"
        assert result.result_available is True
        assert result.client_correlation_id is not None
        assert result.client_correlation_id.startswith("client-python-")
        assert result.run_id is not None and result.run_id.startswith("run-")
        assert result.call_id is not None and result.call_id.startswith("call-")
        assert result.decision_id is not None and result.decision_id.startswith("decision-")
        assert result.evidence_id is not None and result.evidence_id.startswith("evidence-")
        assert result.input_digest is not None and len(result.input_digest) == 64
        assert result.broker_receipt is not None
        assert result.broker_receipt["audit_id"] == result.audit_id

    def test_rejects_undeclared_input_before_execution(self):
        with pytest.raises(MainframeBrokerError, match="undeclared field"):
            invoke_canonical(
                "mf:data:json:json_string",
                {"value": "ok", "surprise": "not allowed"},
            )

    def test_binds_schema_defaults_before_durable_input_digest(self):
        result = invoke_canonical(
            "mf:std:validation:validate_int", {"value": "42"}
        )

        assert result.ok is True
        assert result.input_digest == hashlib.sha256(
            b'{"max":"","min":"","value":"42"}'
        ).hexdigest()

    def test_passes_exact_canonical_argv_and_python_caller(
        self, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "unused"
        envelope = _broker_envelope_fixture(
            ok=True, status="success", exit_code=0
        )
        executable_source = _control_plane_fixture_source(
            envelope,
            '[ "$#" -eq 12 ] &&\n'
            '[ "$1" = invoke ] &&\n'
            '[ "$2" = mf:data:json:json_string ] &&\n'
            '[ "$3" = --input-json ] && [ "$4" = - ] &&\n'
            '[ "$5" = --profile ] && [ "$6" = stable-core ] &&\n'
            '[ "$7" = --format ] && [ "$8" = control-plane-json-v1 ] &&\n'
            '[ "$9" = --caller ] && [ "${10}" = python ] &&\n'
            '[ "${11}" = --client-correlation-id ] && [ -n "${12}" ] || exit 70'
        )
        canonical_id = _write_broker_fixture(
            tmp_path, marker, executable_source=executable_source
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        result = invoke_canonical(canonical_id, {"value": "hello"})
        assert result.ok is True

    @pytest.mark.parametrize(
        "malformation",
        ["result-kind", "result-extra", "schema-extra", "argument-extra"],
    )
    def test_malformed_contract_fails_before_execution(
        self, malformation, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "broker-ran"
        canonical_id = _write_broker_fixture(
            tmp_path, marker, malformation=malformation
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        with pytest.raises(MainframeBrokerError, match="invalid"):
            invoke_canonical(canonical_id, {"value": "hello"})
        assert not marker.exists()

    def test_kills_descendants_when_broker_leader_exits_first(
        self, monkeypatch, tmp_path
    ):
        import time

        import mainframe_bash.core as core

        marker = tmp_path / "descendant-survived"
        executable_source = (
            "#!/bin/sh\n"
            f"(/bin/sleep 0.5; /usr/bin/touch {str(marker)!r}) &\n"
            "exit 0\n"
        )
        canonical_id = _write_broker_fixture(
            tmp_path, marker, executable_source=executable_source
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        with pytest.raises(subprocess.TimeoutExpired):
            invoke_canonical(canonical_id, {"value": "hello"}, timeout=0.1)
        time.sleep(0.7)
        assert not marker.exists()

    @pytest.mark.parametrize("mode", ["timeout", "output-overflow"])
    def test_cooperative_termination_cleans_nested_broker_group(
        self, mode, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "nested-survived"
        canonical_id = _write_broker_fixture(
            tmp_path,
            marker,
            executable_source=_nested_group_broker_source(
                marker, output_overflow=mode == "output-overflow"
            ),
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        if mode == "timeout":
            with pytest.raises(subprocess.TimeoutExpired):
                invoke_canonical(canonical_id, {"value": "hello"}, timeout=0.1)
        else:
            with pytest.raises(MainframeBrokerError, match="envelope limit"):
                invoke_canonical(canonical_id, {"value": "hello"}, timeout=5)

        time.sleep(1.3)
        assert not marker.exists()

    def test_parent_cancel_cleans_nested_broker_group(
        self, monkeypatch, tmp_path
    ):
        marker = tmp_path / "nested-survived"
        ready = tmp_path / "broker-ready"
        canonical_id = _write_broker_fixture(
            tmp_path,
            marker,
            executable_source=_nested_group_broker_source(marker, ready=ready),
        )
        child_env = os.environ.copy()
        child_env["MAINFRAME_ROOT"] = str(tmp_path)
        child_env["PYTHONPATH"] = str(Path(__file__).parent.parent)
        caller = subprocess.Popen(
            [
                sys.executable,
                "-c",
                (
                    "from mainframe_bash.core import invoke_canonical; "
                    f"invoke_canonical({canonical_id!r}, {{'value': 'hello'}}, timeout=5)"
                ),
            ],
            env=child_env,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        try:
            deadline = time.monotonic() + 3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            assert ready.exists()
            os.killpg(caller.pid, signal.SIGINT)
            caller.wait(timeout=3)
            time.sleep(1.3)
            assert not marker.exists()
        finally:
            try:
                os.killpg(caller.pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                caller.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass

    @pytest.mark.parametrize(
        ("envelope", "exit_code"),
        [
            (_broker_envelope_fixture(status="mystery"), 1),
            (_broker_envelope_fixture(exit_code=0), 0),
            (_broker_envelope_fixture(status="timeout", exit_code=124), 124),
            (_broker_envelope_fixture(status="output_limit", exit_code=74), 74),
        ],
        ids=[
            "unknown-status",
            "failure-zero-exit",
            "timeout-flag-mismatch",
            "output-flag-mismatch",
        ],
    )
    def test_rejects_incoherent_broker_envelope(
        self, envelope, exit_code, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "unused"
        executable_source = _control_plane_fixture_source(envelope)
        canonical_id = _write_broker_fixture(
            tmp_path, marker, executable_source=executable_source
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        with pytest.raises(
            MainframeBrokerError, match="identity or semantic validation"
        ):
            invoke_canonical(canonical_id, {"value": "hello"})

    @pytest.mark.parametrize(
        "tamper", ["duplicate-key", "input-digest", "receipt-digest"]
    )
    def test_control_plane_tampering_fails_closed(
        self, tamper, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "unused"
        envelope = _broker_envelope_fixture(ok=True, status="success", exit_code=0)
        response = _control_plane_response_fixture(envelope)
        if tamper == "input-digest":
            response["result"]["input_digest"] = "0" * 64
        elif tamper == "receipt-digest":
            response["result"]["broker_receipt"]["stdout_sha256"] = "0" * 64
        serialized = json.dumps(response, separators=(",", ":"))
        if tamper == "duplicate-key":
            serialized = serialized.replace('"ok":true', '"ok":true,"ok":true', 1)
        canonical_id = _write_broker_fixture(
            tmp_path,
            marker,
            executable_source=_control_plane_raw_fixture_source(serialized),
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        with pytest.raises(MainframeBrokerError):
            invoke_canonical(canonical_id, {"value": "hello"})


class TestCallFunctionJson:
    """Tests for call_function_json."""

    def test_json_object_parsing(self):
        """Should parse JSON object output."""
        obj = call_function_json("json_object", "name=John", "age:number=30")
        assert obj == {"name": "John", "age": 30}

    def test_json_array_parsing(self):
        """Should parse JSON array output."""
        arr = call_function_json("json_array", "a", "b", "c")
        assert arr == ["a", "b", "c"]

    def test_invalid_json_raises(self):
        """Should raise on invalid JSON."""
        with pytest.raises(MainframeFunctionError):
            # timestamp outputs plain text, not JSON
            call_function_json("timestamp")


class TestExceptions:
    """Tests for exception classes."""

    def test_mainframe_error_hierarchy(self):
        """Should have proper exception hierarchy."""
        assert issubclass(MainframeNotFoundError, MainframeError)
        assert issubclass(MainframeFunctionError, MainframeError)

    def test_function_error_attributes(self):
        """Should store function name and return code."""
        err = MainframeFunctionError("test_func", "error message", 42)
        assert err.function == "test_func"
        assert err.returncode == 42
        assert "test_func" in str(err)

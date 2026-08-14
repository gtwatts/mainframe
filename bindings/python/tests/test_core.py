"""
Tests for mainframe_bash.core module.
"""

import json
import os
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


def _write_broker_fixture(
    root: Path,
    marker: Path,
    *,
    malformation: str | None = None,
    executable_source: str | None = None,
) -> str:
    canonical_id = "mf:data:json:json_string"
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

    (root / "lib").mkdir()
    (root / "lib" / "common.sh").write_text("# fixture\n")
    (root / "bin").mkdir()
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
        # Create fake installation
        lib_dir = tmp_path / "lib"
        lib_dir.mkdir()
        (lib_dir / "common.sh").write_text("# fake")

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

    def test_managed_launcher_wins_over_stale_legacy_root(self, monkeypatch):
        import mainframe_bash.core as core

        launcher = Path.home() / ".local" / "bin" / "mainframe"
        expected = launcher.resolve(strict=True).parent.parent
        monkeypatch.delenv("MAINFRAME_ROOT", raising=False)
        core._mainframe_root = None

        assert get_mainframe_root().resolve() == expected

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
        state_dir.mkdir()
        result = invoke_canonical(
            "mf:data:json:json_object",
            {"pairs": ["name=John"]},
            env={"XDG_STATE_HOME": str(state_dir)},
        )

        audit_records = [
            json.loads(line)
            for line in (state_dir / "mainframe" / "invocations.jsonl")
            .read_text(encoding="utf-8")
            .splitlines()
        ]
        audit = next(
            record for record in audit_records if record["audit_id"] == result.audit_id
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
        assert audit["caller"] == "python"

    def test_rejects_undeclared_input_before_execution(self):
        with pytest.raises(MainframeBrokerError, match="undeclared field"):
            invoke_canonical(
                "mf:data:json:json_string",
                {"value": "ok", "surprise": "not allowed"},
            )

    def test_passes_exact_canonical_argv_and_python_caller(
        self, monkeypatch, tmp_path
    ):
        import mainframe_bash.core as core

        marker = tmp_path / "unused"
        envelope = _broker_envelope_fixture(
            ok=True, status="success", exit_code=0
        )
        serialized = json.dumps(envelope, separators=(",", ":"))
        executable_source = (
            "#!/bin/sh\n"
            '[ "$#" -eq 10 ] &&\n'
            '[ "$1" = invoke ] &&\n'
            '[ "$2" = mf:data:json:json_string ] &&\n'
            '[ "$3" = --input-json ] && [ "$4" = - ] &&\n'
            '[ "$5" = --profile ] && [ "$6" = stable-core ] &&\n'
            '[ "$7" = --format ] && [ "$8" = broker-json-v1 ] &&\n'
            '[ "$9" = --caller ] || exit 70\n'
            'shift 9\n[ "$1" = python ] || exit 70\n'
            'IFS= read -r payload\n[ "$payload" = \'{"value":"hello"}\' ] || exit 70\n'
            f"printf '%s\\n' {serialized!r}\n"
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
        serialized = json.dumps(envelope, separators=(",", ":"))
        executable_source = (
            "#!/bin/sh\n"
            f"printf '%s\\n' {serialized!r}\n"
            f"exit {exit_code}\n"
        )
        canonical_id = _write_broker_fixture(
            tmp_path, marker, executable_source=executable_source
        )
        monkeypatch.setenv("MAINFRAME_ROOT", str(tmp_path))
        core._mainframe_root = None

        with pytest.raises(
            MainframeBrokerError, match="identity or semantic validation"
        ):
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

"""
Tests for mainframe_bash.core module.
"""

import pytest

from mainframe_bash.core import (
    MainframeError,
    MainframeNotFoundError,
    MainframeFunctionError,
    get_mainframe_root,
    call_function,
    call_function_json,
    _bash_escape,
    _convert_arg,
    _validate_mainframe_root,
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

    def test_call_echo(self):
        """Should call simple bash commands."""
        # Use a MAINFRAME function that just echoes
        _, code = call_function("printf", "%s", "hello")
        # Note: printf is a bash builtin, but this tests the mechanism
        assert code == 0

    def test_call_with_return_code(self):
        """Should capture return codes."""
        # validate_email returns 0 for valid, 1 for invalid
        _, code = call_function("validate_email", "test@example.com")
        assert code == 0

        _, code = call_function("validate_email", "not-an-email")
        assert code == 1

    def test_call_captures_output(self):
        """Should capture function output."""
        output, code = call_function("uuid")
        assert code == 0
        # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        assert len(output) == 36
        assert output.count("-") == 4

    def test_call_with_env(self):
        """Should pass environment variables."""
        _, code = call_function(
            "log_info",
            "test message",
            capture_stderr=True,
            env={"NO_COLOR": "1"}
        )
        # log_info outputs to stderr
        assert code == 0


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

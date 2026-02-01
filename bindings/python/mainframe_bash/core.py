"""
MAINFRAME Core - Subprocess wrapper for calling bash functions.

Handles MAINFRAME detection, subprocess execution, and error handling.
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Optional, Union


class MainframeError(Exception):
    """Base exception for MAINFRAME errors."""
    pass


class MainframeNotFoundError(MainframeError):
    """Raised when MAINFRAME installation cannot be found."""
    pass


class MainframeFunctionError(MainframeError):
    """Raised when a MAINFRAME function execution fails."""

    def __init__(self, function: str, message: str, returncode: int = 1):
        self.function = function
        self.returncode = returncode
        super().__init__(f"{function}: {message}")


# Cache for MAINFRAME root path
_mainframe_root: Optional[Path] = None


def get_mainframe_root() -> Path:
    """
    Detect MAINFRAME installation root.

    Checks in order:
    1. MAINFRAME_ROOT environment variable
    2. ~/.mainframe (default installation)
    3. /usr/local/share/mainframe
    4. /opt/mainframe

    Returns:
        Path to MAINFRAME root directory.

    Raises:
        MainframeNotFoundError: If MAINFRAME cannot be found.
    """
    global _mainframe_root

    if _mainframe_root is not None:
        return _mainframe_root

    # Check environment variable first
    env_root = os.environ.get("MAINFRAME_ROOT")
    if env_root:
        root = Path(env_root)
        if _validate_mainframe_root(root):
            _mainframe_root = root
            return root

    # Check default locations
    candidates = [
        Path.home() / ".mainframe",
        Path("/usr/local/share/mainframe"),
        Path("/opt/mainframe"),
    ]

    for candidate in candidates:
        if _validate_mainframe_root(candidate):
            _mainframe_root = candidate
            return candidate

    raise MainframeNotFoundError(
        "MAINFRAME installation not found. "
        "Set MAINFRAME_ROOT environment variable or install to ~/.mainframe"
    )


def _validate_mainframe_root(path: Path) -> bool:
    """Check if path is a valid MAINFRAME installation."""
    if not path.is_dir():
        return False

    # Must have lib/common.sh
    common_sh = path / "lib" / "common.sh"
    return common_sh.is_file()


def _build_bash_script(function_name: str, args: list[str], *,
                       source_libs: Optional[list[str]] = None) -> str:
    """
    Build a bash script that sources MAINFRAME and calls a function.

    Args:
        function_name: Name of the bash function to call.
        args: Arguments to pass to the function.
        source_libs: Additional libraries to source (optional).

    Returns:
        Complete bash script as string.
    """
    root = get_mainframe_root()

    # Escape arguments for bash
    escaped_args = " ".join(_bash_escape(arg) for arg in args)

    script_parts = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        f'source "{root}/lib/common.sh"',
    ]

    # Source additional libraries if needed
    if source_libs:
        for lib in source_libs:
            lib_path = root / "lib" / f"{lib}.sh"
            if lib_path.exists():
                script_parts.append(f'source "{lib_path}"')

    # Call the function
    if escaped_args:
        script_parts.append(f'{function_name} {escaped_args}')
    else:
        script_parts.append(function_name)

    return "\n".join(script_parts)


def _bash_escape(value: str) -> str:
    """
    Escape a string for safe use in bash.

    Uses single quotes with proper escaping for single quotes within the string.
    """
    # Handle empty string
    if not value:
        return "''"

    # Single quote escaping: replace ' with '\''
    escaped = value.replace("'", "'\\''")
    return f"'{escaped}'"


def call_function(
    function_name: str,
    *args: Union[str, int, float, bool],
    capture_stderr: bool = False,
    timeout: Optional[float] = None,
    env: Optional[dict[str, str]] = None,
    source_libs: Optional[list[str]] = None,
) -> tuple[str, int]:
    """
    Call a MAINFRAME bash function.

    Args:
        function_name: Name of the bash function to call.
        *args: Arguments to pass to the function.
        capture_stderr: If True, capture stderr in the output.
        timeout: Maximum seconds to wait for completion.
        env: Additional environment variables to set.
        source_libs: Additional libraries to source.

    Returns:
        Tuple of (output string, return code).

    Raises:
        MainframeNotFoundError: If MAINFRAME is not installed.
        subprocess.TimeoutExpired: If timeout is exceeded.

    Example:
        output, code = call_function("validate_email", "test@example.com")
        if code == 0:
            print("Valid email")
    """
    # Convert args to strings
    str_args = [_convert_arg(arg) for arg in args]

    # Build the bash script
    script = _build_bash_script(function_name, str_args, source_libs=source_libs)

    # Prepare environment
    proc_env = os.environ.copy()
    if env:
        proc_env.update(env)

    # Disable colors for consistent output
    proc_env["NO_COLOR"] = "1"
    proc_env["TERM"] = "dumb"

    # Run the script
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=proc_env,
    )

    output = result.stdout
    if capture_stderr and result.stderr:
        output = result.stdout + result.stderr

    return output.rstrip("\n"), result.returncode


def call_function_json(
    function_name: str,
    *args: Union[str, int, float, bool],
    timeout: Optional[float] = None,
    env: Optional[dict[str, str]] = None,
    source_libs: Optional[list[str]] = None,
) -> Any:
    """
    Call a MAINFRAME function and parse JSON output.

    Useful for functions that output JSON (json_object, json_array, etc.)
    or when MAINFRAME_OUTPUT=json mode is enabled.

    Args:
        function_name: Name of the bash function to call.
        *args: Arguments to pass to the function.
        timeout: Maximum seconds to wait for completion.
        env: Additional environment variables to set.
        source_libs: Additional libraries to source.

    Returns:
        Parsed JSON as Python object (dict, list, str, int, etc.)

    Raises:
        MainframeNotFoundError: If MAINFRAME is not installed.
        MainframeFunctionError: If function fails or output is not valid JSON.

    Example:
        obj = call_function_json("json_object", "name=John", "age:number=30")
        print(obj["name"])  # "John"
    """
    output, code = call_function(
        function_name,
        *args,
        timeout=timeout,
        env=env,
        source_libs=source_libs,
    )

    if code != 0:
        raise MainframeFunctionError(
            function_name,
            f"Function returned non-zero exit code: {code}",
            code,
        )

    try:
        return json.loads(output)
    except json.JSONDecodeError as e:
        raise MainframeFunctionError(
            function_name,
            f"Invalid JSON output: {e}",
        ) from e


def _convert_arg(value: Union[str, int, float, bool, None]) -> str:
    """Convert Python value to bash argument string."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)

"""
MAINFRAME Core - Subprocess wrapper for calling bash functions.

Handles MAINFRAME detection, subprocess execution, and error handling.
"""

import base64
import binascii
import hashlib
import json
import math
import os
import re
import selectors
import signal
import stat
import subprocess
import tempfile
import time
import uuid as uuid_module
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any


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


class MainframeBrokerError(MainframeError):
    """Raised when the canonical broker or its wire response is invalid."""


@dataclass(frozen=True)
class BrokerInvocationResult:
    """Strictly validated durable invocation with broker compatibility fields."""

    schema_version: int
    ok: bool
    status: str
    canonical_id: str
    name: str
    owner: str
    result_kind: str
    exit_code: int
    timed_out: bool
    output_exceeded: bool
    duration_ms: int
    audit_id: str
    stdout_b64: str
    stderr_b64: str
    error: str | None
    stdout: str
    stderr: str
    raw: str
    client_correlation_id: str | None = None
    run_id: str | None = None
    call_id: str | None = None
    decision_id: str | None = None
    evidence_id: str | None = None
    input_digest: str | None = None
    outcome: str | None = None
    result_available: bool = False
    broker_receipt: dict[str, Any] | None = None
    broker_envelope: dict[str, Any] | None = None
    control_plane_status: str | None = None
    control_plane_raw: str = ""


# Cache for MAINFRAME root path
_mainframe_root: Path | None = None
_FUNCTION_NAME_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_:]*$")
_LIBRARY_NAME_PATTERN = re.compile(r"^[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*$")
_BROKER_FUNCTION_NAME_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")
_CANONICAL_ID_PATTERN = re.compile(
    r"^mf:[a-z][a-z0-9-]*:[A-Za-z0-9_-]+:[a-z_][a-z0-9_]*$"
)
_BROKER_AUDIT_ID_PATTERN = re.compile(r"^inv-[A-Za-z0-9._:-]{1,120}$")
_DURABLE_ID_PATTERNS = {
    "run_id": re.compile(r"^run-[0-9a-f]{32}$"),
    "call_id": re.compile(r"^call-[0-9a-f]{32}$"),
    "decision_id": re.compile(r"^decision-[0-9a-f]{32}$"),
    "evidence_id": re.compile(r"^evidence-[0-9a-f]{32}$"),
}
_CLIENT_CORRELATION_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_BROKER_STATUSES = frozenset({
    "success",
    "function_error",
    "timeout",
    "output_limit",
    "audit_error",
    "invalid_input",
    "invalid_id",
    "invalid_manifest",
    "unknown_id",
    "invalid_contract",
    "unreviewed_contract",
    "owner_mismatch",
    "unsupported_platform",
    "invalid_owner",
    "broker_error",
})
_BROKER_FIXED_EXIT_CODES = {
    "success": 0,
    "timeout": 124,
    "output_limit": 74,
    "audit_error": 74,
    "invalid_input": 65,
    "invalid_id": 126,
    "invalid_manifest": 126,
    "unknown_id": 126,
    "invalid_contract": 126,
    "unreviewed_contract": 126,
    "owner_mismatch": 126,
    "unsupported_platform": 126,
    "invalid_owner": 126,
    "broker_error": 70,
}
_MANIFEST_SIZE_LIMIT = 16 * 1024 * 1024
_BROKER_INPUT_LIMIT = 32 * 1024
_BROKER_ENVELOPE_LIMIT = 3 * 1024 * 1024
_BROKER_MAX_TIMEOUT_MS = 30_000
_BROKER_OUTER_TIMEOUT_SECONDS = 35.0
_BROKER_MAX_OUTPUT_LIMIT = 1024 * 1024
_BROKER_TERM_GRACE_SECONDS = 0.5
_BROKER_KILL_REAP_SECONDS = 1.0
_BROKER_ENVELOPE_KEYS = frozenset({
    "audit_id",
    "canonical_id",
    "duration_ms",
    "error",
    "exit_code",
    "name",
    "ok",
    "output_exceeded",
    "owner",
    "schema_version",
    "status",
    "stderr_b64",
    "stdout_b64",
    "timed_out",
})
_CONTROL_PLANE_OUTER_KEYS = frozenset({"command", "ok", "result"})
_CONTROL_PLANE_ERROR_KEYS = frozenset({"code", "message"})
_CONTROL_PLANE_RESULT_KEYS = frozenset({
    "schema_version",
    "status",
    "client_correlation_id",
    "run_id",
    "call_id",
    "decision_id",
    "evidence_id",
    "input_digest",
    "outcome",
    "result_available",
    "broker_receipt",
    "broker_envelope",
})
_BROKER_RECEIPT_KEYS = frozenset({
    "schema_version",
    "ok",
    "status",
    "canonical_id",
    "name",
    "owner",
    "exit_code",
    "timed_out",
    "output_exceeded",
    "duration_ms",
    "audit_id",
    "stdout_bytes",
    "stdout_sha256",
    "stderr_bytes",
    "stderr_sha256",
    "error_bytes",
    "error_sha256",
})
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
    "control_plane/mainframe_control_plane/memory_executor.py",
    "control_plane/mainframe_control_plane/memory_transient.py",
    "control_plane/mainframe_control_plane/memory_worker.py",
    "control_plane/mainframe_control_plane/transient.py",
    "control_plane/mainframe_control_plane/worker.py",
)
_REVIEWED_CONVENIENCE_NAMES = frozenset({
    "array_contains", "array_join", "is_numeric", "output_json", "output_success",
    "usop_error_validation", "path_sanitize", "is_empty", "to_lower", "to_upper",
    "trim_left", "trim_right", "json_array", "json_escape", "json_get", "json_merge",
    "json_object", "json_string", "json_valid", "validate_email", "validate_int",
    "validate_json", "validate_path", "validate_regex", "validate_semver", "validate_url",
})


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

    # An explicitly set environment value is authoritative, including after a
    # previous discovery was cached. Never replace an invalid explicit root
    # with a managed or legacy installation.
    env_root = os.environ.get("MAINFRAME_ROOT")
    if env_root is not None:
        if env_root:
            root = Path(env_root)
            if _validate_mainframe_root(root):
                _mainframe_root = root
                return root
        raise MainframeNotFoundError(
            "MAINFRAME_ROOT is set but does not identify a valid MAINFRAME installation"
        )

    if _mainframe_root is not None:
        return _mainframe_root

    # A managed candidate launcher is the canonical installed-product pointer
    # and must win over a stale legacy ~/.mainframe tree.
    managed_root: Path | None = None
    try:
        launcher_target = (Path.home() / ".local" / "bin" / "mainframe").resolve(
            strict=True
        )
        candidate_root = launcher_target.parent.parent
        if (
            launcher_target.is_file()
            and os.access(launcher_target, os.X_OK)
            and launcher_target.name == "mainframe"
            and launcher_target.parent.name == "bin"
            and (candidate_root / "lib" / "common.sh").is_file()
            and (candidate_root / "MANIFEST.json").is_file()
        ):
            managed_root = candidate_root
    except OSError:
        managed_root = None

    # Check default locations
    candidates = [
        managed_root,
        Path.home() / ".mainframe",
        Path("/usr/local/share/mainframe"),
        Path("/opt/mainframe"),
    ]

    for candidate in candidates:
        if candidate is not None and _validate_mainframe_root(candidate):
            _mainframe_root = candidate
            return candidate

    raise MainframeNotFoundError(
        "MAINFRAME installation not found. "
        "Set MAINFRAME_ROOT environment variable or install to ~/.mainframe"
    )


def _validate_mainframe_root(path: Path) -> bool:
    """Require the fixed durable control-plane closure, not a legacy shell tree."""
    try:
        root = path.resolve(strict=True)
        if root != path.absolute() or not root.is_dir() or path.is_symlink():
            return False
        permitted_owners = {0, os.geteuid()} if hasattr(os, "geteuid") else {0}
        for relative in _DURABLE_CLOSURE_FILES:
            candidate = root / relative
            metadata = candidate.lstat()
            if (
                candidate.is_symlink()
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid not in permitted_owners
                or stat.S_IMODE(metadata.st_mode) & 0o022
                or metadata.st_nlink != 1
                or metadata.st_size <= 0
            ):
                return False
        return os.access(root / "bin" / "mainframe", os.X_OK) and os.access(
            root / "control_plane" / "mainframe-control-plane", os.X_OK
        )
    except OSError:
        return False


_RESOLVED_BASH: "str | None" = None
_MINIMUM_BASH_VERSION = (4, 4)
_FIXED_BASH_CANDIDATES = (
    "/opt/homebrew/bin/bash",
    "/usr/local/bin/bash",
    "/home/linuxbrew/.linuxbrew/bin/bash",
    "/opt/local/bin/bash",
    "/nix/var/nix/profiles/default/bin/bash",
    "/run/current-system/sw/bin/bash",
    str(Path.home() / ".nix-profile" / "bin" / "bash"),
    "/usr/bin/bash",
    "/bin/bash",
)
# Treat inherited startup hooks and exported shell functions as untrusted.
_PROTECTED_BASH_ARGS = ("--noprofile", "--norc", "-p", "-c")
_BASH_PROBE_ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
_UNSAFE_EXECUTION_ENVIRONMENT_KEYS = frozenset({
    "BASHOPTS",
    "BASH_ENV",
    "BASH_LOADABLES_PATH",
    "BASH_XTRACEFD",
    "CDPATH",
    "ENV",
    "GLOBIGNORE",
    "NODE_OPTIONS",
    "NODE_PATH",
    "NODE_REDIRECT_WARNINGS",
    "NODE_REPL_HISTORY",
    "NODE_V8_COVERAGE",
    "PERL5LIB",
    "PERL5OPT",
    "PERLLIB",
    "PYTHONBREAKPOINT",
    "PYTHONHOME",
    "PYTHONINSPECT",
    "PYTHONPATH",
    "PYTHONSTARTUP",
    "PYTHONUSERBASE",
    "PYTHONWARNINGS",
    "RUBYLIB",
    "RUBYOPT",
    "SHELLOPTS",
})
_UNSAFE_EXECUTION_ENVIRONMENT_PREFIXES = ("BASH_FUNC_", "LD_", "DYLD_")


def _approved_bash_layout(candidate: str) -> bool:
    """Return whether Bash is in a reviewed system/package-manager layout."""
    return (
        candidate in {
            "/usr/bin/bash",
            "/bin/bash",
            "/usr/local/bin/bash",
            "/opt/local/bin/bash",
        }
        or re.fullmatch(
            r"/(?:opt/homebrew|usr/local|home/linuxbrew/\.linuxbrew)/"
            r"Cellar/[^/]+/[^/]+/bin/bash",
            candidate,
        )
        is not None
        or re.fullmatch(r"/nix/store/[^/]+/bin/bash", candidate) is not None
    )


def _canonical_bash_candidate(candidate: str) -> "str | None":
    """Return an executable candidate's canonical absolute path."""
    if not os.path.isabs(candidate):
        return None

    try:
        canonical = os.path.realpath(candidate, strict=True)
    except (OSError, TypeError, ValueError):
        return None

    try:
        metadata = os.stat(canonical)
    except OSError:
        return None
    mode = stat.S_IMODE(metadata.st_mode)
    if (
        not _approved_bash_layout(canonical)
        or not os.path.isfile(canonical)
        or not os.access(canonical, os.X_OK)
        or metadata.st_uid not in {0, os.geteuid()}
        or mode & 0o022
        or metadata.st_mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX)
        or not mode & stat.S_IXUSR
    ):
        return None
    return canonical


def _bash_version(candidate: str) -> "tuple[int, int] | None":
    """Return a candidate's Bash major/minor version, or None if unusable."""
    if not os.path.isabs(candidate):
        return None

    try:
        probe = subprocess.run(
            [
                candidate,
                *_PROTECTED_BASH_ARGS,
                'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
            ],
            capture_output=True,
            text=True,
            timeout=5,
            env=_BASH_PROBE_ENV,
        )
        if probe.returncode != 0:
            return None
        major, minor = (int(value) for value in probe.stdout.split())
        return major, minor
    except (OSError, subprocess.SubprocessError, TypeError, ValueError):
        return None


def _resolve_bash() -> str:
    """Resolve a Bash 4.4+ executable or fail closed.

    macOS still ships /bin/bash 3.2, while MAINFRAME requires Bash 4.4+.
    An explicit MAINFRAME_BASH override must be absolute. Otherwise only fixed
    reviewed package-manager and system locations are checked; ambient PATH is
    never searched.
    The selected executable is cached by its canonical absolute path.
    """
    global _RESOLVED_BASH
    if _RESOLVED_BASH:
        return _RESOLVED_BASH

    override = os.environ.get("MAINFRAME_BASH")
    if override:
        if not os.path.isabs(override):
            raise RuntimeError("MAINFRAME_BASH must be an absolute path")
        canonical = _canonical_bash_candidate(override)
        if canonical is None:
            raise RuntimeError(
                "MAINFRAME_BASH must resolve to an owner-safe Bash 4.4+ "
                "approved installation layout"
            )
        version = _bash_version(canonical)
        if version is None or version < _MINIMUM_BASH_VERSION:
            raise RuntimeError(
                "MAINFRAME_BASH must resolve to an owner-safe Bash 4.4+ "
                "approved installation layout"
            )
        _RESOLVED_BASH = canonical
        return canonical

    for candidate in _FIXED_BASH_CANDIDATES:
        canonical = _canonical_bash_candidate(candidate)
        if canonical is None:
            continue
        version = _bash_version(canonical)
        if version is not None and version >= _MINIMUM_BASH_VERSION:
            _RESOLVED_BASH = canonical
            return canonical

    raise RuntimeError(
        "MAINFRAME Python bindings require Bash 4.4 or newer at a supported "
        "absolute path; set MAINFRAME_BASH to an intentional trusted executable"
    )


def _protected_execution_environment(
    overrides: "dict[str, str] | None" = None,
) -> dict[str, str]:
    """Build a child environment without passive interpreter injection hooks."""
    proc_env = os.environ.copy()
    if overrides:
        proc_env.update(overrides)
    for key in tuple(proc_env):
        if key in _UNSAFE_EXECUTION_ENVIRONMENT_KEYS or key.startswith(
            _UNSAFE_EXECUTION_ENVIRONMENT_PREFIXES
        ):
            proc_env.pop(key, None)
    return proc_env


@dataclass(frozen=True)
class _ReviewedContract:
    canonical_id: str
    name: str
    owner: str
    result_kind: str
    required: frozenset[str]
    properties: dict[str, dict[str, Any]]
    call_arguments: tuple[tuple[str, str], ...]
    timeout_ms: int
    output_limit: int


def _canonical_mainframe_root() -> Path:
    """Return the configured installation as a canonical directory."""
    try:
        root = get_mainframe_root().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise MainframeNotFoundError("MAINFRAME root is missing or invalid") from exc
    if not root.is_dir():
        raise MainframeNotFoundError("MAINFRAME root is missing or invalid")
    return root


def _load_manifest(root: Path) -> dict[str, Any]:
    """Load a bounded, regular canonical manifest."""
    path = root / "MANIFEST.json"
    try:
        metadata = path.lstat()
        if path.is_symlink() or not path.is_file() or metadata.st_size > _MANIFEST_SIZE_LIMIT:
            raise OSError("unsafe manifest")
        raw = path.read_bytes()
        if len(raw) > _MANIFEST_SIZE_LIMIT:
            raise OSError("oversized manifest")
        value = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MainframeBrokerError(
            "MAINFRAME canonical manifest is missing, oversized, or malformed"
        ) from exc
    if (
        not isinstance(value, dict)
        or type(value.get("manifest_version")) is not int
        or value.get("manifest_version") != 1
        or not isinstance(value.get("exports"), dict)
        or not isinstance(value.get("name_index"), dict)
    ):
        raise MainframeBrokerError("MAINFRAME canonical manifest is malformed")
    return value


def _load_reviewed_contract(
    root: Path,
    canonical_id: str,
    expected_name: "str | None" = None,
    manifest: "dict[str, Any] | None" = None,
) -> _ReviewedContract:
    """Validate and return one closed stable-core invocation contract."""
    if not _CANONICAL_ID_PATTERN.fullmatch(canonical_id):
        raise MainframeBrokerError(f"Invalid MAINFRAME canonical ID: {canonical_id}")
    manifest = manifest if manifest is not None else _load_manifest(root)
    exports = manifest["exports"]
    name_index = manifest["name_index"]
    value = exports.get(canonical_id)
    if not isinstance(value, dict):
        raise MainframeBrokerError(f"Canonical ID is not registered: {canonical_id}")

    name = value.get("name")
    owner = value.get("owner")
    if (
        not isinstance(name, str)
        or not _BROKER_FUNCTION_NAME_PATTERN.fullmatch(name)
        or not isinstance(owner, str)
        or re.fullmatch(r"[A-Za-z0-9_-]+", owner) is None
        or (expected_name is not None and name != expected_name)
        or name_index.get(name) != canonical_id
    ):
        raise MainframeBrokerError("Canonical manifest name/owner parity check failed")

    profiles = value.get("profiles")
    effects = value.get("effects")
    capabilities = value.get("capabilities")
    if (
        value.get("contract_status") != "reviewed"
        or not isinstance(profiles, list)
        or "stable-core" not in profiles
        or not isinstance(effects, list)
        or len(effects) != 1
        or any(effect not in {"pure", "read"} for effect in effects)
        or not isinstance(capabilities, list)
        or capabilities
    ):
        raise MainframeBrokerError(
            f"MAINFRAME function is not reviewed for stable-core: {name}"
        )

    result_contract = value.get("result")
    if (
        not isinstance(result_contract, dict)
        or set(result_contract) != {"kind"}
        or result_contract.get("kind") not in {"stdout", "exit", "none"}
    ):
        raise MainframeBrokerError(
            f"Reviewed contract has an invalid result contract: {canonical_id}"
        )

    schema = value.get("input_schema")
    if not isinstance(schema, dict):
        raise MainframeBrokerError(f"Reviewed contract has an invalid schema: {canonical_id}")
    properties_value = schema.get("properties")
    required_value = schema.get("required")
    if (
        set(schema) != {"type", "properties", "required", "additionalProperties"}
        or schema.get("type") != "object"
        or schema.get("additionalProperties") is not False
        or not isinstance(properties_value, dict)
        or not isinstance(required_value, list)
        or any(not isinstance(field, str) for field in required_value)
        or len(set(required_value)) != len(required_value)
    ):
        raise MainframeBrokerError(f"Reviewed contract has an invalid schema: {canonical_id}")

    required = frozenset(required_value)
    properties: dict[str, dict[str, Any]] = {}
    for field, property_value in properties_value.items():
        if (
            not isinstance(field, str)
            or not _BROKER_FUNCTION_NAME_PATTERN.fullmatch(field)
            or not isinstance(property_value, dict)
        ):
            raise MainframeBrokerError(
                f"Reviewed contract has an invalid property: {canonical_id}"
            )
        if property_value.get("type") == "string":
            default = property_value.get("default")
            enum = property_value.get("enum")
            if (
                not set(property_value) <= {"type", "default", "enum"}
                or (isinstance(default, str) and "\0" in default)
                or
                ("default" in property_value and not isinstance(default, str))
                or (
                    "enum" in property_value
                    and (
                        not isinstance(enum, list)
                        or any(
                            not isinstance(entry, str) or "\0" in entry
                            for entry in enum
                        )
                    )
                )
                or (field not in required and not isinstance(default, str))
            ):
                raise MainframeBrokerError(
                    f"Reviewed contract has an invalid string property: {canonical_id}"
                )
            properties[field] = {
                "type": "string",
                **({"default": default} if isinstance(default, str) else {}),
                **({"enum": enum} if isinstance(enum, list) else {}),
            }
        elif property_value.get("type") == "array":
            items = property_value.get("items")
            default = property_value.get("default")
            if (
                not set(property_value) <= {"type", "items", "default"}
                or not isinstance(items, dict)
                or set(items) != {"type"}
                or items.get("type") != "string"
                or (
                    "default" in property_value
                    and (
                        not isinstance(default, list)
                        or any(
                            not isinstance(entry, str) or "\0" in entry
                            for entry in default
                        )
                    )
                )
                or (field not in required and default != [])
            ):
                raise MainframeBrokerError(
                    f"Reviewed contract has an invalid array property: {canonical_id}"
                )
            properties[field] = {
                "type": "array",
                **({"default": default} if isinstance(default, list) else {}),
            }
        else:
            raise MainframeBrokerError(
                f"Reviewed contract has an unsupported property: {canonical_id}"
            )

    if any(field not in properties for field in required):
        raise MainframeBrokerError(
            f"Reviewed contract requires an unknown property: {canonical_id}"
        )

    call_shape = value.get("call_shape")
    if (
        not isinstance(call_shape, dict)
        or set(call_shape) != {"kind", "arguments"}
        or call_shape.get("kind") != "argv"
        or not isinstance(call_shape.get("arguments"), list)
    ):
        raise MainframeBrokerError(
            f"Reviewed contract has an invalid call shape: {canonical_id}"
        )
    arguments_value = call_shape["arguments"]
    call_arguments: list[tuple[str, str]] = []
    for index, argument in enumerate(arguments_value):
        if not isinstance(argument, dict) or set(argument) != {"field", "mode"}:
            raise MainframeBrokerError(
                f"Reviewed contract has an invalid call argument: {canonical_id}"
            )
        field = argument.get("field")
        mode = argument.get("mode")
        property_value = properties.get(field) if isinstance(field, str) else None
        if (
            not isinstance(field, str)
            or mode not in {"scalar", "spread"}
            or property_value is None
            or (mode == "scalar" and property_value["type"] != "string")
            or (mode == "spread" and property_value["type"] != "array")
            or (mode == "spread" and index != len(arguments_value) - 1)
        ):
            raise MainframeBrokerError(
                f"Reviewed contract call shape is not positional: {canonical_id}"
            )
        call_arguments.append((field, mode))
    shape_fields = [field for field, _ in call_arguments]
    if len(set(shape_fields)) != len(shape_fields) or set(shape_fields) != set(properties):
        raise MainframeBrokerError(
            f"Reviewed contract call shape is not closed: {canonical_id}"
        )

    timeout_ms = value.get("timeout_ms")
    output_limit = value.get("output_limit")
    if (
        type(timeout_ms) is not int
        or not 1 <= timeout_ms <= _BROKER_MAX_TIMEOUT_MS
        or type(output_limit) is not int
        or not 1 <= output_limit <= _BROKER_MAX_OUTPUT_LIMIT
    ):
        raise MainframeBrokerError(
            f"Reviewed contract has invalid execution bounds: {canonical_id}"
        )
    return _ReviewedContract(
        canonical_id=canonical_id,
        name=name,
        owner=owner,
        result_kind=result_contract["kind"],
        required=required,
        properties=properties,
        call_arguments=tuple(call_arguments),
        timeout_ms=timeout_ms,
        output_limit=output_limit,
    )


def _resolve_function_contract(root: Path, function_name: str) -> _ReviewedContract:
    """Resolve a public Bash name through the canonical name index."""
    manifest = _load_manifest(root)
    canonical_id = manifest["name_index"].get(function_name)
    if not isinstance(canonical_id, str):
        raise MainframeBrokerError(
            f"MAINFRAME function is not broker-invocable: {function_name}"
        )
    return _load_reviewed_contract(
        root, canonical_id, expected_name=function_name, manifest=manifest
    )


def _positional_input(
    contract: _ReviewedContract, args: list[str]
) -> dict[str, str | list[str]]:
    """Map legacy positional arguments through the reviewed call shape."""
    payload: dict[str, str | list[str]] = {}
    position = 0
    for field, mode in contract.call_arguments:
        property_value = contract.properties[field]
        if mode == "spread":
            payload[field] = args[position:]
            position = len(args)
        elif position < len(args):
            payload[field] = args[position]
            position += 1
        elif field in contract.required and "default" not in property_value:
            raise MainframeBrokerError(
                f"Missing required argument '{field}' for {contract.name}"
            )
    if position != len(args):
        raise MainframeBrokerError(f"Too many positional arguments for {contract.name}")
    return payload


def _validate_canonical_input(
    contract: _ReviewedContract, input_data: dict[str, Any]
) -> dict[str, str | list[str]]:
    """Validate and copy the closed input object before serialization."""
    if not isinstance(input_data, dict):
        raise MainframeBrokerError("Canonical invocation input must be an object")
    normalized: dict[str, str | list[str]] = {}
    for field, value in input_data.items():
        property_value = contract.properties.get(field)
        if property_value is None:
            raise MainframeBrokerError(
                f"Canonical input contains undeclared field '{field}'"
            )
        if property_value["type"] == "string":
            if (
                not isinstance(value, str)
                or "\0" in value
                or (
                    isinstance(property_value.get("enum"), list)
                    and value not in property_value["enum"]
                )
            ):
                raise MainframeBrokerError(
                    f"Canonical input field '{field}' must be a permitted string"
                )
            normalized[field] = value
        else:
            if (
                not isinstance(value, list)
                or any(not isinstance(entry, str) or "\0" in entry for entry in value)
            ):
                raise MainframeBrokerError(
                    f"Canonical input field '{field}' must be an array of strings"
                )
            normalized[field] = value.copy()
    for field in contract.required:
        if field not in normalized:
            raise MainframeBrokerError(
                f"Canonical input is missing required field '{field}'"
            )
    for field, property_value in contract.properties.items():
        if field not in normalized and "default" in property_value:
            default_value = property_value["default"]
            normalized[field] = (
                default_value.copy() if isinstance(default_value, list) else default_value
            )
    return normalized


def _decode_broker_base64(value: str, field: str) -> bytes:
    """Decode strict canonical RFC 4648 base64."""
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise MainframeBrokerError(
            f"Broker envelope contains invalid {field}"
        ) from exc
    if base64.b64encode(decoded).decode("ascii") != value:
        raise MainframeBrokerError(
            f"Broker envelope contains non-canonical {field}"
        )
    return decoded


def _parse_broker_envelope(
    stdout: bytes,
    process_stderr: bytes,
    process_returncode: int,
    contract: _ReviewedContract,
) -> BrokerInvocationResult:
    """Strictly validate broker-json-v1 and decode its confined output."""
    if not stdout or len(stdout) > _BROKER_ENVELOPE_LIMIT:
        raise MainframeBrokerError(
            "Broker response is empty or exceeds the envelope limit"
        )
    if process_stderr:
        raise MainframeBrokerError(
            "Broker wrote outside the versioned response envelope"
        )
    try:
        raw = stdout.decode("utf-8", errors="strict").strip()
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MainframeBrokerError("Broker response is not valid JSON") from exc
    if not isinstance(value, dict) or set(value) != _BROKER_ENVELOPE_KEYS:
        raise MainframeBrokerError("Broker response does not match broker-json-v1")

    schema_version = value["schema_version"]
    ok = value["ok"]
    status = value["status"]
    canonical_id = value["canonical_id"]
    name = value["name"]
    owner = value["owner"]
    exit_code = value["exit_code"]
    timed_out = value["timed_out"]
    output_exceeded = value["output_exceeded"]
    duration_ms = value["duration_ms"]
    audit_id = value["audit_id"]
    stdout_b64 = value["stdout_b64"]
    stderr_b64 = value["stderr_b64"]
    error = value["error"]
    if (
        type(schema_version) is not int
        or schema_version != 1
        or type(ok) is not bool
        or not isinstance(status, str)
        or status not in _BROKER_STATUSES
        or canonical_id != contract.canonical_id
        or name != contract.name
        or owner != contract.owner
        or type(exit_code) is not int
        or not 0 <= exit_code <= 255
        or type(timed_out) is not bool
        or type(output_exceeded) is not bool
        or type(duration_ms) is not int
        or duration_ms < 0
        or not isinstance(audit_id, str)
        or _BROKER_AUDIT_ID_PATTERN.fullmatch(audit_id) is None
        or not isinstance(stdout_b64, str)
        or not isinstance(stderr_b64, str)
        or (error is not None and not isinstance(error, str))
        or (timed_out and output_exceeded)
        or (
            ok
            and (
                status != "success"
                or exit_code != 0
                or timed_out
                or output_exceeded
                or error is not None
            )
        )
        or (not ok and (status == "success" or exit_code == 0))
        or timed_out != (status == "timeout")
        or output_exceeded != (status == "output_limit")
        or (status == "function_error" and exit_code == 0)
        or (
            status != "function_error"
            and _BROKER_FIXED_EXIT_CODES.get(status) != exit_code
        )
        or process_returncode != exit_code
    ):
        raise MainframeBrokerError(
            "Broker response failed identity or semantic validation"
        )

    stdout_bytes = _decode_broker_base64(stdout_b64, "stdout_b64")
    stderr_bytes = _decode_broker_base64(stderr_b64, "stderr_b64")
    if len(stdout_bytes) + len(stderr_bytes) > contract.output_limit:
        raise MainframeBrokerError(
            "Broker response exceeds the reviewed output bound"
        )
    if contract.result_kind != "stdout" and stdout_bytes:
        raise MainframeBrokerError(
            "Broker output contradicts the reviewed result contract"
        )
    try:
        decoded_stdout = stdout_bytes.decode("utf-8", errors="strict")
        decoded_stderr = stderr_bytes.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise MainframeBrokerError("Broker output is not valid UTF-8") from exc
    return BrokerInvocationResult(
        schema_version=schema_version,
        ok=ok,
        status=status,
        canonical_id=canonical_id,
        name=name,
        owner=owner,
        result_kind=contract.result_kind,
        exit_code=exit_code,
        timed_out=timed_out,
        output_exceeded=output_exceeded,
        duration_ms=duration_ms,
        audit_id=audit_id,
        stdout_b64=stdout_b64,
        stderr_b64=stderr_b64,
        error=error,
        stdout=decoded_stdout,
        stderr=decoded_stderr,
        raw=raw,
        broker_envelope=dict(value),
    )


def _reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Build one JSON object while rejecting ambiguous duplicate keys."""
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _canonical_input_bytes(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _validate_durable_id(value: Any, field: str) -> str:
    pattern = _DURABLE_ID_PATTERNS[field]
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise MainframeBrokerError(f"Control-plane response contains an invalid {field}")
    return value


def _validate_broker_receipt(
    value: Any,
    envelope: dict[str, Any] | None,
    contract: _ReviewedContract,
) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != _BROKER_RECEIPT_KEYS:
        raise MainframeBrokerError("Control-plane broker receipt fields are not exact")
    for field in ("schema_version", "exit_code", "duration_ms", "stdout_bytes", "stderr_bytes", "error_bytes"):
        if type(value[field]) is not int or value[field] < 0:
            raise MainframeBrokerError("Control-plane broker receipt has invalid numeric fields")
    for field in ("ok", "timed_out", "output_exceeded"):
        if type(value[field]) is not bool:
            raise MainframeBrokerError("Control-plane broker receipt has invalid boolean fields")
    if (
        value["schema_version"] != 1
        or value["canonical_id"] != contract.canonical_id
        or value["name"] != contract.name
        or value["owner"] != contract.owner
        or not isinstance(value["status"], str)
        or not isinstance(value["audit_id"], str)
    ):
        raise MainframeBrokerError("Control-plane broker receipt identity is invalid")
    expected_exit = _BROKER_FIXED_EXIT_CODES.get(value["status"])
    if (
        value["status"] not in _BROKER_STATUSES
        or _BROKER_AUDIT_ID_PATTERN.fullmatch(value["audit_id"]) is None
        or value["exit_code"] > 255
        or value["duration_ms"] > contract.timeout_ms + 5_000
        or value["stdout_bytes"] + value["stderr_bytes"] > contract.output_limit
        or value["error_bytes"] > 4_096
        or value["ok"] is not (value["status"] == "success")
        or (value["exit_code"] != 0 if value["ok"] else value["exit_code"] == 0)
        or value["timed_out"] is not (value["status"] == "timeout")
        or value["output_exceeded"] is not (value["status"] == "output_limit")
        or (
            value["exit_code"] == 0
            if value["status"] == "function_error"
            else expected_exit is None or value["exit_code"] != expected_exit
        )
    ):
        raise MainframeBrokerError("Control-plane broker receipt semantics are invalid")
    for field in ("stdout_sha256", "stderr_sha256", "error_sha256"):
        if not isinstance(value[field], str) or _DIGEST_PATTERN.fullmatch(value[field]) is None:
            raise MainframeBrokerError("Control-plane broker receipt digest is invalid")
    if envelope is None:
        return dict(value)
    parity_fields = (
        "schema_version", "ok", "status", "canonical_id", "name", "owner", "exit_code",
        "timed_out", "output_exceeded", "duration_ms", "audit_id",
    )
    if any(value[field] != envelope[field] for field in parity_fields):
        raise MainframeBrokerError("Control-plane receipt does not bind the broker envelope")
    decoded_stdout = _decode_broker_base64(envelope["stdout_b64"], "stdout_b64")
    decoded_stderr = _decode_broker_base64(envelope["stderr_b64"], "stderr_b64")
    error_bytes = b"" if envelope["error"] is None else envelope["error"].encode("utf-8")
    byte_bindings = (
        ("stdout", decoded_stdout),
        ("stderr", decoded_stderr),
        ("error", error_bytes),
    )
    for prefix, payload in byte_bindings:
        if (
            value[prefix + "_bytes"] != len(payload)
            or value[prefix + "_sha256"] != hashlib.sha256(payload).hexdigest()
        ):
            raise MainframeBrokerError("Control-plane receipt payload digest is invalid")
    return dict(value)


def _parse_control_plane_response(
    stdout: bytes,
    process_stderr: bytes,
    process_returncode: int,
    contract: _ReviewedContract,
    *,
    correlation_id: str,
    input_digest: str,
) -> BrokerInvocationResult:
    """Validate the exact durable response before exposing any broker output."""
    if not stdout or len(stdout) > _BROKER_ENVELOPE_LIMIT or not stdout.endswith(b"\n"):
        raise MainframeBrokerError("Control-plane response is empty, unterminated, or oversized")
    if process_stderr:
        raise MainframeBrokerError("Control-plane wrote outside its structured response")
    try:
        raw = stdout[:-1].decode("utf-8", errors="strict")
        outer = json.loads(raw, object_pairs_hook=_reject_duplicate_object_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise MainframeBrokerError("Control-plane response is not unambiguous JSON") from exc
    if not isinstance(outer, dict):
        raise MainframeBrokerError("Control-plane response is not an object")
    if process_returncode != 0:
        if set(outer) != {"command", "error", "ok"} or outer.get("ok") is not False or outer.get("command") != "canonical-invoke":
            raise MainframeBrokerError("Control-plane error response fields are not exact")
        error = outer.get("error")
        if (
            not isinstance(error, dict)
            or set(error) != _CONTROL_PLANE_ERROR_KEYS
            or not isinstance(error.get("code"), str)
            or not isinstance(error.get("message"), str)
        ):
            raise MainframeBrokerError("Control-plane error response is invalid")
        raise MainframeBrokerError("{}: {}".format(error["code"], error["message"]))
    if set(outer) != _CONTROL_PLANE_OUTER_KEYS or outer.get("ok") is not True or outer.get("command") != "canonical-invoke":
        raise MainframeBrokerError("Control-plane success response fields are not exact")
    result = outer.get("result")
    if not isinstance(result, dict) or set(result) != _CONTROL_PLANE_RESULT_KEYS:
        raise MainframeBrokerError("Control-plane durable result fields are not exact")
    if type(result["schema_version"]) is not int or result["schema_version"] != 1:
        raise MainframeBrokerError("Control-plane schema version is invalid")
    status_value = result["status"]
    if status_value not in ("in_progress", "completed"):
        raise MainframeBrokerError("Control-plane durable status is invalid")
    returned_correlation = result["client_correlation_id"]
    if (
        not isinstance(returned_correlation, str)
        or _CLIENT_CORRELATION_PATTERN.fullmatch(returned_correlation) is None
        or returned_correlation != correlation_id
    ):
        raise MainframeBrokerError("Control-plane client correlation binding is invalid")
    run_id = _validate_durable_id(result["run_id"], "run_id")
    call_id = _validate_durable_id(result["call_id"], "call_id")
    decision_id = _validate_durable_id(result["decision_id"], "decision_id")
    if result["input_digest"] != input_digest or _DIGEST_PATTERN.fullmatch(input_digest) is None:
        raise MainframeBrokerError("Control-plane input digest binding is invalid")
    if type(result["result_available"]) is not bool:
        raise MainframeBrokerError("Control-plane result availability is invalid")
    evidence_id: str | None = None
    outcome = result["outcome"]
    receipt_value = result["broker_receipt"]
    envelope_value = result["broker_envelope"]
    if status_value == "in_progress":
        if (
            result["evidence_id"] is not None
            or outcome is not None
            or result["result_available"] is not False
            or receipt_value is not None
            or envelope_value is not None
        ):
            raise MainframeBrokerError("Control-plane in-progress result is contradictory")
    else:
        evidence_id = _validate_durable_id(result["evidence_id"], "evidence_id")
        if outcome not in ("succeeded", "failed", "timed_out", "interrupted"):
            raise MainframeBrokerError("Control-plane terminal outcome is invalid")
        if result["result_available"] is not (envelope_value is not None):
            raise MainframeBrokerError("Control-plane result availability contradicts its envelope")
    envelope: dict[str, Any] | None = None
    decoded: BrokerInvocationResult | None = None
    if envelope_value is not None:
        if not isinstance(envelope_value, dict):
            raise MainframeBrokerError("Control-plane broker envelope is invalid")
        envelope = dict(envelope_value)
        candidate_exit = envelope.get("exit_code")
        if type(candidate_exit) is not int:
            raise MainframeBrokerError("Control-plane broker envelope has invalid exit code")
        serialized = json.dumps(envelope, allow_nan=False, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        decoded = _parse_broker_envelope(serialized, b"", candidate_exit, contract)
        expected_outcome = "succeeded" if decoded.ok else ("timed_out" if decoded.timed_out else "failed")
        if outcome != expected_outcome:
            raise MainframeBrokerError("Control-plane outcome contradicts the broker envelope")
    receipt = _validate_broker_receipt(receipt_value, envelope, contract)
    if envelope is not None and receipt is None:
        raise MainframeBrokerError("Control-plane available result lacks its durable receipt")
    if receipt is not None:
        receipt_outcome = "succeeded" if receipt["ok"] else (
            "timed_out" if receipt["timed_out"] else "failed"
        )
        if outcome != receipt_outcome:
            raise MainframeBrokerError("Control-plane outcome contradicts its durable receipt")
    if decoded is None:
        decoded = BrokerInvocationResult(
            schema_version=1,
            ok=False,
            status="in_progress" if status_value == "in_progress" else "result_unavailable",
            canonical_id=contract.canonical_id,
            name=contract.name,
            owner=contract.owner,
            result_kind=contract.result_kind,
            exit_code=75 if status_value == "in_progress" else 66,
            timed_out=outcome == "timed_out",
            output_exceeded=False,
            duration_ms=0,
            audit_id="",
            stdout_b64="",
            stderr_b64="",
            error=None,
            stdout="",
            stderr="",
            raw="",
        )
    return replace(
        decoded,
        client_correlation_id=returned_correlation,
        run_id=run_id,
        call_id=call_id,
        decision_id=decision_id,
        evidence_id=evidence_id,
        input_digest=input_digest,
        outcome=outcome,
        result_available=result["result_available"],
        broker_receipt=receipt,
        broker_envelope=envelope,
        control_plane_status=status_value,
        control_plane_raw=raw,
    )


def _terminate_broker_process(process: subprocess.Popen[bytes]) -> None:
    """Cooperatively terminate the broker group, hard-stop it, and reap."""
    # The leader may already have exited while a descendant keeps inherited
    # stdout/stderr pipes open. Address the process group unconditionally.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        if process.poll() is None:
            try:
                process.terminate()
            except OSError:
                pass
    try:
        process.wait(timeout=_BROKER_TERM_GRACE_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        pass

    # lib/invoke.sh's TERM trap has now had a bounded opportunity to clean and
    # reap its nested process group. Enforce the outer group boundary even if
    # the direct broker leader has already exited.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except OSError:
        if process.poll() is None:
            try:
                process.kill()
            except OSError:
                pass
    try:
        process.wait(timeout=_BROKER_KILL_REAP_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        pass


def _run_bounded_broker_process(
    command: list[str],
    request: bytes,
    *,
    timeout: float,
    env: dict[str, str],
) -> tuple[bytes, bytes, int]:
    """Run the broker with a hard combined stdout/stderr memory bound."""
    with tempfile.TemporaryFile() as request_file:
        request_file.write(request)
        request_file.seek(0)
        try:
            process = subprocess.Popen(
                command,
                stdin=request_file,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                start_new_session=True,
            )
        except OSError as exc:
            raise MainframeBrokerError(f"Broker process failed: {exc}") from exc

        if process.stdout is None or process.stderr is None:
            _terminate_broker_process(process)
            raise MainframeBrokerError("Broker pipes are unavailable")

        streams = selectors.DefaultSelector()
        streams.register(process.stdout, selectors.EVENT_READ, "stdout")
        streams.register(process.stderr, selectors.EVENT_READ, "stderr")
        buffers = {"stdout": bytearray(), "stderr": bytearray()}
        deadline = time.monotonic() + timeout
        try:
            while streams.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    _terminate_broker_process(process)
                    raise subprocess.TimeoutExpired(
                        command,
                        timeout,
                        output=bytes(buffers["stdout"]),
                        stderr=bytes(buffers["stderr"]),
                    )
                events = streams.select(remaining)
                if not events:
                    continue
                for key, _ in events:
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        streams.unregister(key.fileobj)
                        continue
                    buffers[key.data].extend(chunk)
                    if sum(len(buffer) for buffer in buffers.values()) > _BROKER_ENVELOPE_LIMIT:
                        _terminate_broker_process(process)
                        raise MainframeBrokerError(
                            "Broker response exceeds the envelope limit"
                        )

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _terminate_broker_process(process)
                raise subprocess.TimeoutExpired(
                    command,
                    timeout,
                    output=bytes(buffers["stdout"]),
                    stderr=bytes(buffers["stderr"]),
                )
            try:
                returncode = process.wait(timeout=remaining)
            except subprocess.TimeoutExpired as exc:
                _terminate_broker_process(process)
                raise subprocess.TimeoutExpired(
                    command,
                    timeout,
                    output=bytes(buffers["stdout"]),
                    stderr=bytes(buffers["stderr"]),
                ) from exc
        except BaseException:
            _terminate_broker_process(process)
            raise
        finally:
            streams.close()
            for stream in (process.stdout, process.stderr):
                if not stream.closed:
                    stream.close()

    return bytes(buffers["stdout"]), bytes(buffers["stderr"]), returncode


def _invoke_reviewed_contract(
    root: Path,
    contract: _ReviewedContract,
    input_data: dict[str, Any],
    *,
    timeout: "float | None" = None,
    env: "dict[str, str] | None" = None,
) -> BrokerInvocationResult:
    """Run the exact local canonical broker entrypoint."""
    normalized = _validate_canonical_input(contract, input_data)
    request = json.dumps(normalized, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    canonical_request = _canonical_input_bytes(normalized)
    input_digest = hashlib.sha256(canonical_request).hexdigest()
    correlation_id = f"client-python-{uuid_module.uuid4().hex}"
    if len(request) > _BROKER_INPUT_LIMIT:
        raise MainframeBrokerError("Canonical invocation input exceeds 32768 bytes")

    executable = root / "bin" / "mainframe"
    try:
        metadata = executable.lstat()
        if executable.is_symlink() or not executable.is_file() or not os.access(
            executable, os.X_OK
        ):
            raise OSError("unsafe executable")
        if metadata.st_size <= 0:
            raise OSError("empty executable")
    except OSError as exc:
        raise MainframeBrokerError(
            "MAINFRAME canonical broker is missing or unsafe"
        ) from exc

    effective_timeout = (
        timeout if timeout is not None else (contract.timeout_ms / 1000.0) + 5.0
    )
    if (
        isinstance(effective_timeout, bool)
        or not isinstance(effective_timeout, int | float)
        or not math.isfinite(effective_timeout)
        or effective_timeout <= 0
        or effective_timeout > _BROKER_OUTER_TIMEOUT_SECONDS
    ):
        raise ValueError("Broker timeout must be greater than 0 and at most 35 seconds")
    proc_env = _protected_execution_environment(env)
    proc_env["MAINFRAME_ROOT"] = str(root)
    command = [
        str(executable),
        "invoke",
        contract.canonical_id,
        "--input-json",
        "-",
        "--profile",
        "stable-core",
        "--format",
        "control-plane-json-v1",
        "--caller",
        "python",
        "--client-correlation-id",
        correlation_id,
    ]
    stdout, stderr, returncode = _run_bounded_broker_process(
        command,
        request,
        timeout=float(effective_timeout),
        env=proc_env,
    )
    return _parse_control_plane_response(
        stdout,
        stderr,
        returncode,
        contract,
        correlation_id=correlation_id,
        input_digest=input_digest,
    )


def invoke_canonical(
    canonical_id: str,
    input_data: dict[str, Any],
    *,
    timeout: "float | None" = None,
    env: "dict[str, str] | None" = None,
) -> BrokerInvocationResult:
    """Invoke one reviewed stable-core export by canonical ID.

    This structured adapter never evaluates shell text. The input must match
    the closed object schema recorded in the canonical manifest.
    """
    root = _canonical_mainframe_root()
    contract = _load_reviewed_contract(root, canonical_id)
    return _invoke_reviewed_contract(
        root, contract, input_data, timeout=timeout, env=env
    )


def _build_bash_script(function_name: str, args: list[str], *,
                       source_libs: list[str] | None = None) -> str:
    """
    Build a bash script that sources MAINFRAME and calls a function.

    Args:
        function_name: Name of the bash function to call.
        args: Arguments to pass to the function.
        source_libs: Additional libraries to source (optional).

    Returns:
        Complete bash script as string.
    """
    if not _FUNCTION_NAME_PATTERN.fullmatch(function_name):
        raise ValueError(f"Invalid MAINFRAME function name: {function_name}")

    root = get_mainframe_root()

    # Escape arguments for bash
    escaped_args = " ".join(_bash_escape(arg) for arg in args)

    script_parts = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        # Force a full library load: bindings call arbitrary registry
        # functions, and a lean MAINFRAME_LIBS leaked from the parent
        # environment silently leaves most functions undefined.
        'export MAINFRAME_LIBS="all"',
        'source "$MAINFRAME_ROOT/lib/common.sh"',
    ]

    # Source additional libraries if needed
    if source_libs:
        for lib in source_libs:
            if not _LIBRARY_NAME_PATTERN.fullmatch(lib):
                raise ValueError(f"Invalid MAINFRAME library name: {lib}")
            lib_path = root / "lib" / f"{lib}.sh"
            if lib_path.exists():
                script_parts.append(f'source "$MAINFRAME_ROOT/lib/{lib}.sh"')

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


def exec_bash(
    script: str,
    *,
    capture_stderr: bool = False,
    timeout: "float | None" = None,
    env: "dict[str, str] | None" = None,
) -> tuple[str, int]:
    """Execute application-owned Bash text with MAINFRAME sourced.

    This is an explicitly unbrokered escape hatch for trusted code. Never pass
    agent-, model-, or user-generated shell text to this function.
    """
    root = _canonical_mainframe_root()
    proc_env = _protected_execution_environment(env)
    proc_env["MAINFRAME_ROOT"] = str(root)
    proc_env["NO_COLOR"] = "1"
    proc_env["TERM"] = "dumb"
    full_script = "\n".join([
        "set -euo pipefail",
        'export MAINFRAME_LIBS="all"',
        'source "$MAINFRAME_ROOT/lib/common.sh"',
        script,
    ])
    result = subprocess.run(
        [_resolve_bash(), *_PROTECTED_BASH_ARGS, full_script],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=proc_env,
    )
    output = result.stdout
    if capture_stderr and result.stderr:
        output += result.stderr
    return output.rstrip("\n"), result.returncode


def _legacy_call_function(
    function_name: str,
    *args: str | int | float | bool,
    capture_stderr: bool = False,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
) -> tuple[str, int]:
    """Run one source-fixed typed-wrapper function through protected Bash.

    This private compatibility path is deliberately absent from ``__all__``.
    It is quote-safe but unbrokered and must never become a dynamic dispatch
    surface for agent-, model-, or user-selected function names.
    """
    if not _FUNCTION_NAME_PATTERN.fullmatch(function_name):
        raise ValueError(f"Invalid fixed legacy function name: {function_name}")
    converted = [_convert_arg(argument) for argument in args]
    if any("\0" in argument for argument in converted):
        raise ValueError("Legacy wrapper arguments cannot contain NUL bytes")
    quoted = " ".join(_bash_escape(argument) for argument in converted)
    script = function_name if not quoted else f"{function_name} {quoted}"
    # exec_bash supplies protected interpreter flags/environment and preserves
    # the historical Python trimming rule of removing trailing newlines only.
    return exec_bash(
        script,
        capture_stderr=capture_stderr,
        timeout=timeout,
        env=env,
    )


def _legacy_call_function_json(
    function_name: str,
    *args: str | int | float | bool,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
) -> Any:
    """Parse JSON from the private fixed-name legacy compatibility path."""
    output, code = _legacy_call_function(
        function_name,
        *args,
        timeout=timeout,
        env=env,
    )
    if code != 0:
        raise MainframeFunctionError(
            function_name,
            f"Function returned non-zero exit code: {code}",
            code,
        )
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise MainframeFunctionError(
            function_name,
            f"Invalid JSON output: {exc}",
            code,
        ) from exc


def _fixed_convenience_call(
    function_name: str,
    *args: str | int | float | bool,
    capture_stderr: bool = False,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
) -> tuple[str, int]:
    """Route reviewed convenience calls atomically; retain fixed legacy others."""
    if function_name in _REVIEWED_CONVENIENCE_NAMES:
        return call_function(
            function_name,
            *args,
            capture_stderr=capture_stderr,
            timeout=timeout,
            env=env,
        )
    return _legacy_call_function(
        function_name,
        *args,
        capture_stderr=capture_stderr,
        timeout=timeout,
        env=env,
    )


def _fixed_convenience_json(
    function_name: str,
    *args: str | int | float | bool,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
) -> Any:
    """Parse JSON after the fixed convenience route selects durable or legacy."""
    output, code = _fixed_convenience_call(
        function_name,
        *args,
        timeout=timeout,
        env=env,
    )
    if code != 0:
        raise MainframeFunctionError(
            function_name,
            f"Function returned non-zero exit code: {code}",
            code,
        )
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise MainframeFunctionError(
            function_name,
            f"Invalid JSON output: {exc}",
            code,
        ) from exc


def call_function(
    function_name: str,
    *args: str | int | float | bool,
    capture_stderr: bool = False,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
    source_libs: list[str] | None = None,
) -> tuple[str, int]:
    """
    Call a reviewed stable-core MAINFRAME function through the broker.

    Args:
        function_name: Name of the bash function to call.
        *args: Arguments to pass to the function.
        capture_stderr: If True, capture stderr in the output.
        timeout: Maximum seconds to wait for completion.
        env: Additional environment variables to set.
        source_libs: Deprecated. Brokered calls cannot source caller-selected
            libraries; use exec_bash only for application-owned trusted code.

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
    if not _FUNCTION_NAME_PATTERN.fullmatch(function_name):
        raise ValueError(f"Invalid MAINFRAME function name: {function_name}")
    if source_libs:
        for library in source_libs:
            if not _LIBRARY_NAME_PATTERN.fullmatch(library):
                raise ValueError(f"Invalid MAINFRAME library name: {library}")
        raise ValueError(
            "source_libs is unavailable for brokered calls; "
            "use exec_bash only for trusted application-owned code"
        )

    root = _canonical_mainframe_root()
    try:
        contract = _resolve_function_contract(root, function_name)
        input_data = _positional_input(
            contract, [_convert_arg(argument) for argument in args]
        )
        invocation = _invoke_reviewed_contract(
            root, contract, input_data, timeout=timeout, env=env
        )
    except MainframeBrokerError as exc:
        return (str(exc) if capture_stderr else ""), 126

    output = invocation.stdout if contract.result_kind == "stdout" else ""
    if capture_stderr and invocation.stderr:
        output += invocation.stderr
    return output, invocation.exit_code


def call_function_json(
    function_name: str,
    *args: str | int | float | bool,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
    source_libs: list[str] | None = None,
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


def _convert_arg(value: str | int | float | bool | None) -> str:
    """Convert Python value to bash argument string."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)

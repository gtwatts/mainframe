#!/usr/bin/env python3
"""Run one shared stable-core corpus through every first-party adapter.

The gate intentionally compares UTF-8 bytes, not trimmed display strings. It
also verifies that the corpus still covers the complete reviewed invocation
policy and that Pi's positional mapping is identical to the structured input
used by the CLI, Node, Python, and MCP adapters.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import importlib
import json
import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, Callable


SOURCE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = (
    SOURCE_ROOT / "tests" / "fixtures" / "stable-core-conformance-v1.json"
)
NODE_HELPER = (
    SOURCE_ROOT / "tests" / "helpers" / "stable_core_conformance_node.ts"
)
ADAPTERS = ("cli", "node", "python", "mcp", "pi")
NODE_SENTINEL = "@@MAINFRAME_CONFORMANCE@@"
MCP_SDK_DISCOVERY_PROBE = (
    "import importlib.machinery as machinery,sys;"
    "package=machinery.PathFinder.find_spec('mcp');"
    "locations=package.submodule_search_locations if package is not None else None;"
    "server=machinery.PathFinder.find_spec('mcp.server', locations) "
    "if locations is not None else None;"
    "sys.exit(server is None)"
)
BROKER_ENVELOPE_FIELDS = frozenset({
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
    "stdout_b64",
    "stderr_b64",
    "error",
})
BROKER_CLIENT_OBSERVATION_FIELDS = frozenset({
    "adapter",
    "case_id",
    *BROKER_ENVELOPE_FIELDS,
    "result_kind",
})
CLI_OBSERVATION_FIELDS = frozenset({
    "adapter",
    "case_id",
    "envelope",
    "control_plane",
    "process_exit_code",
    "process_stderr_b64",
})
CONTROL_PLANE_RESULT_FIELDS = frozenset({
    "schema_version", "status", "client_correlation_id", "run_id", "call_id",
    "decision_id", "evidence_id", "input_digest", "outcome", "result_available",
    "broker_receipt", "broker_envelope",
})
BROKER_RECEIPT_FIELDS = frozenset({
    "schema_version", "ok", "status", "canonical_id", "name", "owner", "exit_code",
    "timed_out", "output_exceeded", "duration_ms", "audit_id", "stdout_bytes",
    "stdout_sha256", "stderr_bytes", "stderr_sha256", "error_bytes", "error_sha256",
})
MCP_OBSERVATION_FIELDS = frozenset({"adapter", "case_id", "response"})
PI_OBSERVATION_FIELDS = frozenset({
    "adapter",
    "case_id",
    "content_text",
    "details",
})
EXCEPTION_OBSERVATION_FIELDS = frozenset({"adapter", "case_id", "exception"})
CASE_FIELDS = frozenset({
    "case_id",
    "canonical_id",
    "function_name",
    "owner",
    "result_kind",
    "input",
    "positional_args",
    "expected_exit_code",
    "expected_stdout_b64",
    "tags",
})


class ConformanceFailure(RuntimeError):
    """Raised for a corpus, adapter, or byte-level conformance failure."""


@dataclass(frozen=True)
class NodeBuild:
    """Fresh Node artifact and current-run provenance recorded beside it."""

    artifact: Path
    provenance: Path
    source_sha256: str
    artifact_sha256: str


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = _parse_json_exact(path.read_text(encoding="utf-8"), str(path))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConformanceFailure(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ConformanceFailure(f"expected a JSON object: {path}")
    return value


def _parse_json_exact(payload: str, label: str) -> Any:
    def no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ConformanceFailure(f"{label} contains duplicate key {key!r}")
            value[key] = item
        return value

    return json.loads(payload, object_pairs_hook=no_duplicates)


def _validate_runtime_root(value: Path | str) -> Path:
    """Resolve and validate the runtime under test without executing it."""
    value = Path(value)
    try:
        root = value.expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise argparse.ArgumentTypeError(
            f"runtime root does not resolve: {value}: {error}"
        ) from error
    if not root.is_dir() or root == root.parent:
        raise argparse.ArgumentTypeError(f"runtime root is not a directory: {root}")
    if any(ord(character) < 32 or ord(character) == 127 for character in str(root)):
        raise argparse.ArgumentTypeError("runtime root contains a control character")

    required_files = (
        "FUNCTIONS.json",
        "MANIFEST.json",
        "config/invocation-policy.json",
        "lib/common.sh",
        "skills/pi/extensions/mainframe.ts",
    )
    missing = []
    for relative in required_files:
        artifact = root / relative
        try:
            inside_root = artifact.resolve(strict=True).is_relative_to(root)
        except (OSError, RuntimeError):
            inside_root = False
        if artifact.is_symlink() or not artifact.is_file() or not inside_root:
            missing.append(relative)
    cli = root / "bin" / "mainframe"
    if cli.is_symlink() or not cli.is_file() or not os.access(cli, os.X_OK):
        missing.append("bin/mainframe (regular executable)")
    if missing:
        raise argparse.ArgumentTypeError(
            f"runtime root is missing conformance artifacts: {', '.join(missing)}"
        )
    return root


def _find_utf8_locale() -> str:
    """Return a locale that the host proves has a UTF-8 character map."""
    locale_command = _find_executable(
        "locale", [Path("/usr/bin/locale"), Path("/bin/locale")]
    )
    if locale_command is None:
        raise ConformanceFailure("cannot probe a supported UTF-8 locale")
    candidates = ["C.UTF-8", "C.utf8", "en_US.UTF-8", "en_US.utf8"]
    inventory = subprocess.run(
        [locale_command, "-a"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=5,
        check=False,
        text=True,
    )
    if inventory.returncode == 0:
        candidates.extend(
            line.strip()
            for line in inventory.stdout.splitlines()
            if re.fullmatch(r"[A-Za-z0-9_.@-]+", line.strip())
            and "utf" in line.lower()
        )
    for candidate in dict.fromkeys(candidates):
        environment = os.environ.copy()
        environment.update({"LC_ALL": candidate, "LANG": candidate})
        probe = subprocess.run(
            [locale_command, "charmap"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=environment,
            timeout=5,
            check=False,
            text=True,
        )
        charmap = re.sub(r"[-_]", "", probe.stdout.strip()).lower()
        if probe.returncode == 0 and charmap == "utf8":
            return candidate
    raise ConformanceFailure("host has no supported UTF-8 locale")


@contextmanager
def _process_environment(environment: dict[str, str]):
    """Temporarily align in-process Python bindings with child adapters."""
    managed = ("MAINFRAME_ROOT", "XDG_STATE_HOME", "LC_ALL", "LANG")
    previous = {key: os.environ.get(key) for key in managed}
    os.environ.update({key: environment[key] for key in managed})
    try:
        yield
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _canonical_b64(value: str, label: str) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ConformanceFailure(f"{label} is not strict base64") from error
    if base64.b64encode(decoded).decode("ascii") != value:
        raise ConformanceFailure(f"{label} is not canonical base64")
    try:
        decoded.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ConformanceFailure(f"{label} is not UTF-8 output") from error
    return decoded


def _positional_input(contract: dict[str, Any], args: list[str]) -> dict[str, Any]:
    mapped: dict[str, Any] = {}
    position = 0
    required = set(contract["input_schema"]["required"])
    for argument in contract["call_shape"]["arguments"]:
        field = argument["field"]
        if argument["mode"] == "spread":
            mapped[field] = args[position:]
            position = len(args)
        elif position < len(args):
            mapped[field] = args[position]
            position += 1
        elif field in required:
            raise ConformanceFailure(f"Pi positional mapping omits required field {field}")
    if position != len(args):
        raise ConformanceFailure("Pi positional mapping leaves unused arguments")
    return mapped


def _validate_case_input(case: dict[str, Any], contract: dict[str, Any]) -> None:
    input_data = case["input"]
    schema = contract["input_schema"]
    if not isinstance(input_data, dict):
        raise ConformanceFailure(f"{case['case_id']}: input must be an object")
    properties = schema["properties"]
    extras = set(input_data) - set(properties)
    missing = set(schema["required"]) - set(input_data)
    if extras or missing:
        raise ConformanceFailure(
            f"{case['case_id']}: closed input mismatch extras={sorted(extras)} missing={sorted(missing)}"
        )
    for field, value in input_data.items():
        property_schema = properties[field]
        if property_schema["type"] == "string":
            if not isinstance(value, str) or "\0" in value:
                raise ConformanceFailure(f"{case['case_id']}: {field} must be a NUL-free string")
            if "enum" in property_schema and value not in property_schema["enum"]:
                raise ConformanceFailure(f"{case['case_id']}: {field} is outside its enum")
        elif property_schema["type"] == "array":
            if not isinstance(value, list) or not all(
                isinstance(item, str) and "\0" not in item for item in value
            ):
                raise ConformanceFailure(
                    f"{case['case_id']}: {field} must be an array of NUL-free strings"
                )
        else:
            raise ConformanceFailure(f"{case['case_id']}: unsupported property type")
    encoded = json.dumps(
        input_data, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    if len(encoded) > 32_768:
        raise ConformanceFailure(f"{case['case_id']}: input exceeds broker limit")


def validate_corpus(
    corpus: dict[str, Any],
    policy: dict[str, Any],
    manifest: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    if set(corpus) != {"schema_version", "profile", "description", "cases"}:
        raise ConformanceFailure("corpus top-level shape changed")
    if corpus["schema_version"] != 1 or corpus["profile"] != "stable-core":
        raise ConformanceFailure("unsupported corpus version or profile")
    cases = corpus["cases"]
    if not isinstance(cases, list) or not cases:
        raise ConformanceFailure("corpus cases must be a non-empty array")
    contracts = policy.get("exports")
    if policy.get("schema_version") != 1 or not isinstance(contracts, dict):
        raise ConformanceFailure("invocation policy is malformed")
    if len(contracts) != 26:
        raise ConformanceFailure(
            f"reviewed stable-core contract count changed: expected 26, got {len(contracts)}"
        )

    by_case: dict[str, dict[str, Any]] = {}
    covered_ids: set[str] = set()
    has_stdout_empty = False
    has_stdout_whitespace_only = False
    has_unicode_output = False
    for case in cases:
        if not isinstance(case, dict) or set(case) != CASE_FIELDS:
            raise ConformanceFailure("each corpus case must have the exact v1 shape")
        case_id = case["case_id"]
        if not isinstance(case_id, str) or not re.fullmatch(r"[a-z0-9_]{1,80}", case_id):
            raise ConformanceFailure(f"invalid case ID: {case_id!r}")
        if case_id in by_case:
            raise ConformanceFailure(f"duplicate case ID: {case_id}")
        canonical_id = case["canonical_id"]
        contract = contracts.get(canonical_id)
        if not isinstance(contract, dict) or contract.get("contract_status") != "reviewed":
            raise ConformanceFailure(f"{case_id}: canonical contract is not reviewed")
        manifest_export = manifest.get("exports", {}).get(canonical_id)
        if not isinstance(manifest_export, dict):
            raise ConformanceFailure(f"{case_id}: canonical manifest export is missing")
        result_kind = contract.get("result", {}).get("kind")
        if (
            case["function_name"] != manifest_export.get("name")
            or case["owner"] != manifest_export.get("owner")
            or case["result_kind"] != result_kind
            or result_kind not in {"stdout", "exit", "none"}
            or case["expected_exit_code"] != 0
        ):
            raise ConformanceFailure(f"{case_id}: manifest/result identity drift")
        if not isinstance(case["positional_args"], list) or not all(
            isinstance(value, str) for value in case["positional_args"]
        ):
            raise ConformanceFailure(f"{case_id}: positional_args must be strings")
        _validate_case_input(case, contract)
        if _positional_input(contract, case["positional_args"]) != case["input"]:
            raise ConformanceFailure(
                f"{case_id}: Pi positional arguments do not reconstruct structured input"
            )
        expected = _canonical_b64(
            case["expected_stdout_b64"], f"{case_id}.expected_stdout_b64"
        )
        tags = case["tags"]
        if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            raise ConformanceFailure(f"{case_id}: tags must be strings")
        if "empty-stdout" in tags and expected:
            raise ConformanceFailure(f"{case_id}: empty-stdout tag contradicts bytes")
        if "whitespace-only" in tags and (
            not expected or expected.strip(b" \t\r\n")
        ):
            raise ConformanceFailure(f"{case_id}: whitespace-only tag contradicts bytes")
        if "unicode" in tags and not any(byte >= 0x80 for byte in expected):
            raise ConformanceFailure(f"{case_id}: unicode tag lacks non-ASCII output bytes")
        has_stdout_empty |= result_kind == "stdout" and expected == b""
        has_stdout_whitespace_only |= (
            result_kind == "stdout"
            and bool(expected)
            and not expected.strip(b" \t\r\n")
        )
        has_unicode_output |= any(byte >= 0x80 for byte in expected)
        covered_ids.add(canonical_id)
        by_case[case_id] = case

    policy_ids = set(contracts)
    if covered_ids != policy_ids:
        raise ConformanceFailure(
            "corpus/policy coverage mismatch "
            f"missing={sorted(policy_ids - covered_ids)} extra={sorted(covered_ids - policy_ids)}"
        )
    if not has_stdout_empty or not has_stdout_whitespace_only or not has_unicode_output:
        raise ConformanceFailure(
            "corpus must include stdout-kind empty, whitespace-only, and Unicode byte cases"
        )
    return by_case


def _exception_observation(
    adapter: str, case: dict[str, Any], error: Exception
) -> dict[str, Any]:
    return {
        "adapter": adapter,
        "case_id": case["case_id"],
        "exception": f"{type(error).__name__}: {error}",
    }


def _strict_text(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise ConformanceFailure(f"{label} must be a string")
    value.encode("utf-8", errors="strict")
    return value


def _validate_broker_envelope(
    value: Any, label: str
) -> dict[str, Any]:
    """Validate the exact broker-json-v1 transport shape without defaults."""
    if not isinstance(value, dict) or set(value) != BROKER_ENVELOPE_FIELDS:
        raise ConformanceFailure(f"{label} does not have the exact broker-json-v1 shape")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        raise ConformanceFailure(f"{label}.schema_version is invalid")
    if type(value["ok"]) is not bool:
        raise ConformanceFailure(f"{label}.ok is invalid")
    for field in ("status", "canonical_id", "stdout_b64", "stderr_b64"):
        _strict_text(value[field], f"{label}.{field}")
    for field in ("name", "owner"):
        if value[field] is not None:
            _strict_text(value[field], f"{label}.{field}")
    if (
        type(value["exit_code"]) is not int
        or not 0 <= value["exit_code"] <= 255
        or type(value["duration_ms"]) is not int
        or value["duration_ms"] < 0
    ):
        raise ConformanceFailure(f"{label} has invalid numeric metadata")
    if type(value["timed_out"]) is not bool or type(value["output_exceeded"]) is not bool:
        raise ConformanceFailure(f"{label} has invalid boolean metadata")
    _strict_text(value["audit_id"], f"{label}.audit_id")
    if value["error"] is not None:
        _strict_text(value["error"], f"{label}.error")
    _canonical_b64(value["stdout_b64"], f"{label}.stdout_b64")
    _canonical_b64(value["stderr_b64"], f"{label}.stderr_b64")
    return value


def _broker_client_observation(
    adapter: str,
    case: dict[str, Any],
    result: Any,
) -> dict[str, Any]:
    """Copy every binding broker field exactly; absence is a gate failure."""
    values = {
        "adapter": adapter,
        "case_id": case["case_id"],
        "schema_version": result.schema_version,
        "ok": result.ok,
        "status": result.status,
        "canonical_id": result.canonical_id,
        "name": result.name,
        "owner": result.owner,
        "result_kind": result.result_kind,
        "exit_code": result.exit_code,
        "timed_out": result.timed_out,
        "output_exceeded": result.output_exceeded,
        "duration_ms": result.duration_ms,
        "audit_id": result.audit_id,
        "stdout_b64": result.stdout_b64,
        "stderr_b64": result.stderr_b64,
        "error": result.error,
    }
    if set(values) != BROKER_CLIENT_OBSERVATION_FIELDS:
        raise ConformanceFailure(f"{adapter} observation shape is invalid")
    _validate_broker_envelope(
        {field: values[field] for field in BROKER_ENVELOPE_FIELDS},
        f"{adapter}.{case['case_id']}",
    )
    if not isinstance(values["result_kind"], str):
        raise ConformanceFailure(
            f"{adapter}.{case['case_id']}.result_kind must be a string"
        )
    if _strict_text(result.stdout, f"{adapter}.stdout").encode("utf-8") != _canonical_b64(
        values["stdout_b64"], f"{adapter}.stdout_b64"
    ):
        raise ConformanceFailure(f"{adapter}.{case['case_id']} stdout decode drift")
    if _strict_text(result.stderr, f"{adapter}.stderr").encode("utf-8") != _canonical_b64(
        values["stderr_b64"], f"{adapter}.stderr_b64"
    ):
        raise ConformanceFailure(f"{adapter}.{case['case_id']} stderr decode drift")
    return values


def run_cli(
    cases: list[dict[str, Any]],
    environment: dict[str, str],
    runtime_root: Path,
) -> list[dict[str, Any]]:
    executable = runtime_root / "bin" / "mainframe"
    observations = []
    for case in cases:
        correlation_id = f"client-conformance-{uuid.uuid4().hex}"
        request = json.dumps(
            case["input"], ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
        command = [
            str(executable),
            "invoke",
            case["canonical_id"],
            "--input-json",
            "-",
            "--profile",
            "stable-core",
            "--format",
            "control-plane-json-v1",
            "--caller",
            "conformance",
            "--client-correlation-id",
            correlation_id,
        ]
        try:
            process = subprocess.run(
                command,
                input=request,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=SOURCE_ROOT,
                env=environment,
                timeout=15,
                check=False,
            )
            if not process.stdout.endswith(b"\n") or process.stdout.count(b"\n") != 1:
                raise ConformanceFailure("CLI broker response framing is not one JSON line")
            parsed_outer = _parse_json_exact(
                    process.stdout.decode("utf-8", errors="strict"),
                    f"cli.{case['case_id']}",
                )
            if isinstance(parsed_outer, dict) and set(parsed_outer) == {"ok", "command", "error"}:
                raise ConformanceFailure(
                    "CLI control-plane denied invocation: "
                    + json.dumps(parsed_outer["error"], sort_keys=True)
                )
            outer = _require_exact_shape(
                parsed_outer,
                frozenset({"ok", "command", "result"}),
                f"cli.{case['case_id']} control-plane outer",
            )
            if outer["ok"] is not True or outer["command"] != "canonical-invoke":
                raise ConformanceFailure("CLI control-plane outer identity is invalid")
            control_plane = _require_exact_shape(
                outer["result"], CONTROL_PLANE_RESULT_FIELDS,
                f"cli.{case['case_id']} durable result",
            )
            envelope = _validate_broker_envelope(
                control_plane["broker_envelope"], f"cli.{case['case_id']} broker envelope"
            )
            observations.append({
                "adapter": "cli",
                "case_id": case["case_id"],
                "envelope": envelope,
                "control_plane": control_plane,
                "process_exit_code": process.returncode,
                "process_stderr_b64": base64.b64encode(process.stderr).decode("ascii"),
            })
        except Exception as error:  # Keep the complete corpus diagnostic.
            observations.append(_exception_observation("cli", case, error))
    return observations


def run_python(
    cases: list[dict[str, Any]], environment: dict[str, str]
) -> list[dict[str, Any]]:
    del environment
    binding_path = str(SOURCE_ROOT / "bindings" / "python")
    if binding_path not in sys.path:
        sys.path.insert(0, binding_path)
    binding = importlib.import_module("mainframe_bash")
    observations = []
    for case in cases:
        try:
            result = binding.invoke_canonical(case["canonical_id"], case["input"])
            observations.append(_broker_client_observation("python", case, result))
        except Exception as error:
            observations.append(_exception_observation("python", case, error))
    return observations


def run_mcp(
    cases: list[dict[str, Any]],
    environment: dict[str, str],
    runtime_root: Path,
) -> list[dict[str, Any]] | None:
    """Exercise the real MCP SDK stdio boundary and server dispatch."""
    python = _find_mcp_python()
    if python is None:
        return None
    server = SOURCE_ROOT / "mcp" / "mainframe-mcp-server"
    messages: list[dict[str, Any]] = [{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "mainframe-conformance", "version": "1"},
        },
    }, {
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": {},
    }]
    request_ids: dict[int, dict[str, Any]] = {}
    for index, case in enumerate(cases, start=1000):
        request_ids[index] = case
        messages.append({
            "jsonrpc": "2.0",
            "id": index,
            "method": "tools/call",
            "params": {
                "name": f"mainframe_{case['function_name']}",
                "arguments": case["input"],
            },
        })

    child_environment = environment.copy()
    # The public MCP executable is permanently stable-core-only. An inherited
    # legacy tier selector is rejected by design, so remove it instead of
    # relying on the caller's ambient environment.
    child_environment.pop("MAINFRAME_MCP_TIER", None)
    child_environment.update({
        "PYTHONUNBUFFERED": "1",
    })
    for key in ("PYTHONHOME", "PYTHONINSPECT", "PYTHONPATH", "PYTHONSTARTUP"):
        child_environment.pop(key, None)
    process = subprocess.Popen(
        [
            python,
            str(server),
            "--mainframe-root",
            str(runtime_root),
            "--allow-development-root",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=SOURCE_ROOT,
        env=child_environment,
        bufsize=0,
    )
    if process.stdin is None or process.stdout is None or process.stderr is None:
        process.kill()
        process.wait(timeout=5)
        raise ConformanceFailure("MCP stdio pipes were not created")

    responses: dict[int, dict[str, Any]] = {}
    output_buffer = b""
    expected_ids = {1, *request_ids}
    try:
        request_stream = "".join(
            json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n"
            for message in messages
        ).encode("utf-8")
        process.stdin.write(request_stream)
        process.stdin.flush()
        deadline = time.monotonic() + 240
        while set(responses) != expected_ids:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ConformanceFailure("timed out waiting for MCP stdio responses")
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            if not readable:
                raise ConformanceFailure("timed out waiting for MCP stdio responses")
            chunk = os.read(process.stdout.fileno(), 65_536)
            if not chunk:
                raise ConformanceFailure("MCP server exited before all responses arrived")
            output_buffer += chunk
            if len(output_buffer) > 4 * 1024 * 1024:
                raise ConformanceFailure("MCP stdio frame exceeds the conformance bound")
            while b"\n" in output_buffer:
                raw_line, output_buffer = output_buffer.split(b"\n", 1)
                if not raw_line:
                    raise ConformanceFailure("MCP server emitted an empty stdio frame")
                message = _parse_json_exact(
                    raw_line.decode("utf-8", errors="strict"), "MCP stdio response"
                )
                if not isinstance(message, dict):
                    raise ConformanceFailure("MCP stdio response is not an object")
                response_id = message.get("id")
                if response_id is None:
                    continue
                if type(response_id) is not int or response_id not in expected_ids:
                    raise ConformanceFailure(f"MCP returned unexpected response ID {response_id!r}")
                if response_id in responses:
                    raise ConformanceFailure(f"MCP returned duplicate response ID {response_id}")
                responses[response_id] = message
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    process_stderr = process.stderr.read()
    if process_stderr:
        raise ConformanceFailure("MCP server wrote outside the JSON-RPC stdio channel")
    if output_buffer:
        raise ConformanceFailure("MCP server left an unterminated stdio frame")

    initialize = responses[1]
    if (
        set(initialize) != {"jsonrpc", "id", "result"}
        or initialize["jsonrpc"] != "2.0"
        or initialize["id"] != 1
        or not isinstance(initialize["result"], dict)
        or not isinstance(initialize["result"].get("serverInfo"), dict)
        or initialize["result"]["serverInfo"].get("name") != "mainframe-mcp-server"
    ):
        raise ConformanceFailure("MCP initialize response shape or identity is invalid")
    return [
        {
            "adapter": "mcp",
            "case_id": case["case_id"],
            "response": responses[request_id],
        }
        for request_id, case in request_ids.items()
    ]


def _find_mcp_python() -> str | None:
    explicit = os.environ.get("MAINFRAME_MCP_PYTHON")
    candidates = (
        [explicit]
        if explicit is not None
        else [
            str(SOURCE_ROOT / "mcp" / ".venv" / "bin" / "python"),
            sys.executable,
            shutil.which("python3"),
        ]
    )
    for raw_candidate in candidates:
        if not raw_candidate:
            continue
        candidate = Path(os.path.abspath(Path(raw_candidate).expanduser()))
        try:
            resolved = candidate.resolve(strict=True)
        except (OSError, RuntimeError):
            if explicit is not None:
                raise ConformanceFailure("MAINFRAME_MCP_PYTHON does not resolve")
            continue
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            if explicit is not None:
                raise ConformanceFailure("MAINFRAME_MCP_PYTHON is not executable")
            continue
        probe_environment = os.environ.copy()
        for key in ("PYTHONHOME", "PYTHONINSPECT", "PYTHONPATH", "PYTHONSTARTUP"):
            probe_environment.pop(key, None)
        try:
            with tempfile.TemporaryDirectory(prefix="mainframe-mcp-probe-") as probe_cwd:
                probe = subprocess.run(
                    [str(candidate), "-I", "-c", MCP_SDK_DISCOVERY_PROBE],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    cwd=probe_cwd,
                    env=probe_environment,
                    timeout=10,
                    check=False,
                )
        except subprocess.TimeoutExpired as error:
            if explicit is not None:
                raise ConformanceFailure(
                    "MAINFRAME_MCP_PYTHON SDK discovery timed out"
                ) from error
            continue
        except OSError as error:
            if explicit is not None:
                raise ConformanceFailure(
                    "MAINFRAME_MCP_PYTHON SDK discovery failed"
                ) from error
            continue
        if probe.returncode == 0:
            return str(candidate)
        if explicit is not None:
            raise ConformanceFailure("MAINFRAME_MCP_PYTHON lacks the MCP SDK")
    return None


def _find_executable(name: str, fixed: list[Path]) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    for candidate in fixed:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _find_pi_executable(environment: dict[str, str]) -> str | None:
    explicit = environment.get("MAINFRAME_PI_BIN")
    if explicit is not None:
        candidate = Path(explicit)
        if not candidate.is_absolute():
            raise ConformanceFailure("MAINFRAME_PI_BIN must be an absolute path")
        try:
            resolved = candidate.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ConformanceFailure("MAINFRAME_PI_BIN does not resolve") from error
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            raise ConformanceFailure("MAINFRAME_PI_BIN is not executable")
        return str(resolved)
    return _find_executable(
        "pi",
        [
            Path("/opt/homebrew/bin/pi"),
            Path("/usr/local/bin/pi"),
            Path("/home/linuxbrew/.linuxbrew/bin/pi"),
            Path.home() / ".bun" / "bin" / "pi",
        ],
    )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ConformanceFailure(f"cannot hash Node build artifact {path}: {error}") from error
    return digest.hexdigest()


def _node_source_sha256() -> str:
    """Fingerprint every local input used to produce the ESM binding bundle."""
    binding_root = SOURCE_ROOT / "bindings" / "nodejs"
    required = [binding_root / "package.json", binding_root / "tsconfig.json"]
    source_root = binding_root / "src"
    try:
        source_files = sorted(
            path for path in source_root.rglob("*") if path.is_file()
        )
    except OSError as error:
        raise ConformanceFailure(f"cannot inventory Node binding source: {error}") from error
    inputs = [*required, *source_files]
    if not source_files or any(path.is_symlink() or not path.is_file() for path in inputs):
        raise ConformanceFailure("Node binding build inputs are missing or symbolic links")

    digest = hashlib.sha256()
    for path in inputs:
        relative = path.relative_to(binding_root).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        try:
            digest.update(path.read_bytes())
        except OSError as error:
            raise ConformanceFailure(f"cannot read Node binding source {path}: {error}") from error
        digest.update(b"\0")
    return digest.hexdigest()


def _find_bun() -> str | None:
    explicit = os.environ.get("MAINFRAME_CONFORMANCE_BUN")
    if explicit is not None:
        candidate = Path(explicit).expanduser()
        try:
            resolved = candidate.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ConformanceFailure(
                f"MAINFRAME_CONFORMANCE_BUN does not resolve: {error}"
            ) from error
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            raise ConformanceFailure("MAINFRAME_CONFORMANCE_BUN is not executable")
        return str(resolved)
    return _find_executable(
        "bun",
        [
            Path.home() / ".bun" / "bin" / "bun",
            Path("/opt/homebrew/bin/bun"),
            Path("/usr/local/bin/bun"),
            Path("/home/linuxbrew/.linuxbrew/bin/bun"),
        ],
    )


def _prepare_node_build(
    environment: dict[str, str], build_root: Path, required: bool
) -> NodeBuild | None:
    """Build the Node adapter from current source into this run's private root."""
    bun = _find_bun()
    if bun is None:
        if required:
            raise ConformanceFailure(
                "required Node adapter lacks Bun for a current-run source build"
            )
        return None

    binding_root = SOURCE_ROOT / "bindings" / "nodejs"
    entrypoint = binding_root / "src" / "index.ts"
    build_root.mkdir(mode=0o700, parents=True, exist_ok=False)
    artifact = build_root / "mainframe-node-current-source.mjs"
    source_before = _node_source_sha256()
    process = subprocess.run(
        [
            bun,
            "build",
            str(entrypoint),
            "--outfile",
            str(artifact),
            "--target",
            "node",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=binding_root,
        env=environment,
        timeout=120,
        check=False,
        text=True,
    )
    if process.returncode != 0 or artifact.is_symlink() or not artifact.is_file():
        diagnostic = (process.stderr or process.stdout).strip()
        raise ConformanceFailure(
            "fresh Node binding build failed"
            + (f": {diagnostic}" if diagnostic else "")
        )
    source_after = _node_source_sha256()
    if source_after != source_before:
        raise ConformanceFailure("Node binding source changed during the current-run build")

    artifact_sha256 = _sha256_file(artifact)
    provenance = build_root / "provenance.json"
    try:
        provenance.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "source_sha256": source_after,
                    "artifact_sha256": artifact_sha256,
                },
                separators=(",", ":"),
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        provenance.chmod(0o600)
    except OSError as error:
        raise ConformanceFailure(f"cannot record Node build provenance: {error}") from error
    return NodeBuild(
        artifact=artifact,
        provenance=provenance,
        source_sha256=source_after,
        artifact_sha256=artifact_sha256,
    )


def _verify_node_build(build: NodeBuild) -> None:
    """Fail if current source, the fresh artifact, or its marker has drifted."""
    marker = _read_json(build.provenance)
    expected = {
        "schema_version": 1,
        "source_sha256": build.source_sha256,
        "artifact_sha256": build.artifact_sha256,
    }
    if marker != expected:
        raise ConformanceFailure("current-run Node build provenance marker drifted")
    if _node_source_sha256() != build.source_sha256:
        raise ConformanceFailure("Node binding source changed after its current-run build")
    if (
        build.artifact.is_symlink()
        or not build.artifact.is_file()
        or _sha256_file(build.artifact) != build.artifact_sha256
    ):
        raise ConformanceFailure("current-run Node build artifact drifted")


def run_node_helper(
    adapter: str,
    cases: list[dict[str, Any]],
    environment: dict[str, str],
    corpus_path: Path,
    runtime_root: Path,
    node_build: NodeBuild | None,
) -> list[dict[str, Any]] | None:
    del cases
    node = _find_executable(
        "node",
        [
            Path("/opt/homebrew/bin/node"),
            Path("/usr/local/bin/node"),
            Path("/usr/bin/node"),
        ],
    )
    if not node:
        return None
    command_tail = [
        adapter,
        str(SOURCE_ROOT),
        str(runtime_root),
        str(corpus_path),
    ]
    if adapter == "node":
        if node_build is None:
            return None
        _verify_node_build(node_build)
        command_tail.append(str(node_build.artifact))
    elif adapter == "pi":
        pi_bin = _find_pi_executable(environment)
        if not pi_bin:
            return None
        command_tail.append(pi_bin)
    else:
        raise ConformanceFailure(f"unsupported Node helper adapter: {adapter}")
    with tempfile.TemporaryDirectory(prefix="mainframe-node-helper-") as helper_dir:
        helper = Path(helper_dir) / "stable_core_conformance_node.mjs"
        shutil.copyfile(NODE_HELPER, helper)
        process = subprocess.run(
            [node, str(helper), *command_tail],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=SOURCE_ROOT,
            env=environment,
            timeout=240,
            check=False,
            text=True,
        )
    if process.returncode != 0:
        raise ConformanceFailure(
            f"{adapter} helper failed exit={process.returncode}: "
            f"{process.stderr.strip() or process.stdout.strip()}"
        )
    if process.stderr:
        raise ConformanceFailure(f"{adapter} helper wrote unexpected stderr")
    if (
        not process.stdout.endswith("\n")
        or process.stdout.count("\n") != 1
        or not process.stdout.startswith(NODE_SENTINEL)
    ):
        raise ConformanceFailure(
            f"{adapter} helper framing is not exactly one sentinel JSON line"
        )
    payload_line = process.stdout[:-1]
    try:
        observations = _parse_json_exact(
            payload_line[len(NODE_SENTINEL) :], f"{adapter} helper response"
        )
    except json.JSONDecodeError as error:
        raise ConformanceFailure(f"{adapter} helper returned malformed JSON") from error
    if not isinstance(observations, list):
        raise ConformanceFailure(f"{adapter} helper response is not an array")
    return observations


def assert_adapter(
    adapter: str,
    cases_by_id: dict[str, dict[str, Any]],
    observations: list[dict[str, Any]],
    runtime_root: Path,
) -> None:
    seen: set[str] = set()
    failures: list[str] = []
    for observation in observations:
        if not isinstance(observation, dict):
            failures.append("non-object observation")
            continue
        if set(observation) == EXCEPTION_OBSERVATION_FIELDS:
            failures.append(
                f"{observation.get('case_id')}: {observation.get('exception')}"
            )
            continue
        case_id = observation.get("case_id")
        case = cases_by_id.get(case_id)
        if case is None:
            failures.append(f"unexpected case {case_id!r}")
            continue
        if case_id in seen:
            failures.append(f"duplicate case {case_id}")
            continue
        seen.add(case_id)
        try:
            if observation.get("adapter") != adapter:
                raise ConformanceFailure("observation adapter identity is invalid")
            if adapter == "cli":
                _assert_cli_observation(observation, case)
            elif adapter in {"node", "python"}:
                _assert_broker_client_observation(observation, case)
            elif adapter == "mcp":
                _assert_mcp_observation(observation, case)
            elif adapter == "pi":
                _assert_pi_observation(observation, case, runtime_root)
            else:  # Guard changes to ADAPTERS.
                raise ConformanceFailure(f"unsupported adapter assertion: {adapter}")
        except ConformanceFailure as error:
            failures.append(f"{case_id}: {error}")
    missing = set(cases_by_id) - seen
    if missing:
        failures.append(f"missing cases: {sorted(missing)}")
    if failures:
        raise ConformanceFailure(
            f"{adapter} conformance failed ({len(failures)}):\n  "
            + "\n  ".join(failures)
        )


def _require_exact_shape(value: Any, fields: frozenset[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise ConformanceFailure(
            f"{label} shape is not exact expected={sorted(fields)!r} actual={actual!r}"
        )
    return value


def _assert_expected_fields(
    actual: dict[str, Any], expected: dict[str, Any], label: str
) -> None:
    differences = {
        key: {"expected": value, "actual": actual[key]}
        for key, value in expected.items()
        if actual[key] != value
    }
    if differences:
        raise ConformanceFailure(
            f"{label} mismatch "
            + json.dumps(differences, ensure_ascii=True, sort_keys=True)
        )


def _assert_cli_observation(
    observation: dict[str, Any], case: dict[str, Any]
) -> None:
    _require_exact_shape(observation, CLI_OBSERVATION_FIELDS, "CLI observation")
    envelope = _validate_broker_envelope(observation["envelope"], "CLI envelope")
    control_plane = _require_exact_shape(
        observation["control_plane"], CONTROL_PLANE_RESULT_FIELDS,
        "CLI durable control-plane result",
    )
    _canonical_b64(observation["process_stderr_b64"], "CLI process_stderr_b64")
    _assert_expected_fields(
        envelope,
        {
            "schema_version": 1,
            "ok": True,
            "status": "success",
            "canonical_id": case["canonical_id"],
            "name": case["function_name"],
            "owner": case["owner"],
            "exit_code": case["expected_exit_code"],
            "timed_out": False,
            "output_exceeded": False,
            "stdout_b64": case["expected_stdout_b64"],
            "stderr_b64": "",
            "error": None,
        },
        "CLI broker envelope",
    )
    _assert_expected_fields(
        observation,
        {
            "process_exit_code": 0,
            "process_stderr_b64": "",
        },
        "CLI process transport",
    )
    expected_digest = hashlib.sha256(
        json.dumps(
            case["input"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()
    _assert_expected_fields(
        control_plane,
        {
            "schema_version": 1,
            "status": "completed",
            "input_digest": expected_digest,
            "outcome": "succeeded",
            "result_available": True,
            "broker_envelope": envelope,
        },
        "CLI durable control-plane result",
    )
    for field, pattern in {
        "client_correlation_id": r"^client-conformance-[0-9a-f]{32}$",
        "run_id": r"^run-[0-9a-f]{32}$",
        "call_id": r"^call-[0-9a-f]{32}$",
        "decision_id": r"^decision-[0-9a-f]{32}$",
        "evidence_id": r"^evidence-[0-9a-f]{32}$",
    }.items():
        if not isinstance(control_plane[field], str) or not re.fullmatch(
            pattern, control_plane[field]
        ):
            raise ConformanceFailure(f"CLI durable {field} is invalid")
    receipt = _require_exact_shape(
        control_plane["broker_receipt"], BROKER_RECEIPT_FIELDS,
        "CLI durable broker receipt",
    )
    for field in (
        "schema_version", "ok", "status", "canonical_id", "name", "owner", "exit_code",
        "timed_out", "output_exceeded", "duration_ms", "audit_id",
    ):
        if receipt[field] != envelope[field]:
            raise ConformanceFailure(f"CLI receipt does not bind envelope field {field}")
    for prefix, payload in {
        "stdout": _canonical_b64(envelope["stdout_b64"], "CLI stdout_b64"),
        "stderr": _canonical_b64(envelope["stderr_b64"], "CLI stderr_b64"),
        "error": b"" if envelope["error"] is None else envelope["error"].encode("utf-8"),
    }.items():
        if (
            receipt[f"{prefix}_bytes"] != len(payload)
            or receipt[f"{prefix}_sha256"] != hashlib.sha256(payload).hexdigest()
        ):
            raise ConformanceFailure(f"CLI receipt does not bind {prefix} bytes")


def _assert_broker_client_observation(
    observation: dict[str, Any], case: dict[str, Any]
) -> None:
    _require_exact_shape(
        observation, BROKER_CLIENT_OBSERVATION_FIELDS, "binding observation"
    )
    _validate_broker_envelope(
        {field: observation[field] for field in BROKER_ENVELOPE_FIELDS},
        "binding envelope",
    )
    _assert_expected_fields(
        observation,
        {
            "schema_version": 1,
            "ok": True,
            "status": "success",
            "canonical_id": case["canonical_id"],
            "name": case["function_name"],
            "owner": case["owner"],
            "result_kind": case["result_kind"],
            "exit_code": case["expected_exit_code"],
            "timed_out": False,
            "output_exceeded": False,
            "stdout_b64": case["expected_stdout_b64"],
            "stderr_b64": "",
            "error": None,
        },
        "binding broker observation",
    )


def _expected_adapter_text(case: dict[str, Any], kind: str) -> str:
    stdout = _canonical_b64(
        case["expected_stdout_b64"], f"{case['case_id']}.expected_stdout_b64"
    ).decode("utf-8", errors="strict")
    if case["result_kind"] == "stdout":
        if stdout.strip():
            return stdout
        return json.dumps(
            {
                "schema_version": 1,
                "kind": f"mainframe-{kind}-stdout",
                "function": case["function_name"],
                "encoding": "base64",
                "stdout_b64": case["expected_stdout_b64"],
            },
            separators=(",", ":"),
        )
    return f"Function {case['function_name']} completed successfully"


def _assert_mcp_observation(
    observation: dict[str, Any], case: dict[str, Any]
) -> None:
    _require_exact_shape(observation, MCP_OBSERVATION_FIELDS, "MCP observation")
    response = _require_exact_shape(
        observation["response"], frozenset({"jsonrpc", "id", "result"}), "MCP response"
    )
    if response["jsonrpc"] != "2.0" or type(response["id"]) is not int:
        raise ConformanceFailure("MCP response identity is invalid")
    result = _require_exact_shape(
        response["result"], frozenset({"content", "isError", "structuredContent"}),
        "MCP result",
    )
    if result["isError"] is not False or not isinstance(result["content"], list):
        raise ConformanceFailure("MCP result success shape is invalid")
    if len(result["content"]) != 1:
        raise ConformanceFailure("MCP result must have exactly one content block")
    content = _require_exact_shape(
        result["content"][0], frozenset({"type", "text"}), "MCP text content"
    )
    if content["type"] != "text" or not isinstance(content["text"], str):
        raise ConformanceFailure("MCP content is not exact text")
    expected_text = _expected_adapter_text(case, "mcp")
    if content["text"] != expected_text:
        raise ConformanceFailure("MCP text does not preserve the reviewed result bytes")
    structured = _require_exact_shape(
        result["structuredContent"],
        frozenset({
            "schema_version", "kind", "ok", "function", "canonical_id",
            "effect_contract", "result", "correlation", "terminal",
        }),
        "MCP durable structured result",
    )
    _assert_expected_fields(
        structured,
        {
            "schema_version": 2,
            "kind": "mainframe-mcp-result",
            "ok": True,
            "function": case["function_name"],
            "canonical_id": case["canonical_id"],
            "effect_contract": {
                "effects": [
                    "read" if case["canonical_id"] == "mf:std:validation:validate_path" else "pure"
                ],
                "read_only": True,
            },
        },
        "MCP durable structured result",
    )
    expected_stdout = _canonical_b64(
        case["expected_stdout_b64"], f"{case['case_id']}.expected_stdout_b64"
    ).decode("utf-8", errors="strict")
    if structured["result"] != {
        "kind": case["result_kind"],
        "encoding": "utf-8",
        "stdout": expected_stdout,
    }:
        raise ConformanceFailure("MCP structured output changed reviewed result bytes")
    correlation = _require_exact_shape(
        structured["correlation"],
        frozenset({
            "mcp_request_id", "client_correlation_id", "binding_status",
            "client_metadata_status", "run_id", "call_id", "decision_id",
            "evidence_id", "input_digest",
        }),
        "MCP durable correlation",
    )
    expected_digest = hashlib.sha256(
        json.dumps(
            case["input"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()
    _assert_expected_fields(
        correlation,
        {
            "mcp_request_id": response["id"],
            "binding_status": "kernel-authoritative",
            "client_metadata_status": "absent",
            "input_digest": expected_digest,
        },
        "MCP durable correlation",
    )
    for field, pattern in {
        "client_correlation_id": r"^mcp-[0-9a-f]{32}$",
        "run_id": r"^run-[0-9a-f]{32}$",
        "call_id": r"^call-[0-9a-f]{32}$",
        "decision_id": r"^decision-[0-9a-f]{32}$",
        "evidence_id": r"^evidence-[0-9a-f]{32}$",
    }.items():
        if not isinstance(correlation[field], str) or not re.fullmatch(
            pattern, correlation[field]
        ):
            raise ConformanceFailure(f"MCP durable {field} is invalid")
    terminal = _require_exact_shape(
        structured["terminal"],
        frozenset({"outcome", "result_available", "broker_receipt"}),
        "MCP durable terminal result",
    )
    if terminal["outcome"] != "succeeded" or terminal["result_available"] is not True:
        raise ConformanceFailure("MCP terminal result is not a delivered success")
    receipt = _require_exact_shape(
        terminal["broker_receipt"], BROKER_RECEIPT_FIELDS,
        "MCP durable broker receipt",
    )
    _assert_expected_fields(
        receipt,
        {
            "schema_version": 1,
            "ok": True,
            "status": "success",
            "canonical_id": case["canonical_id"],
            "name": case["function_name"],
            "owner": case["owner"],
            "exit_code": case["expected_exit_code"],
            "timed_out": False,
            "output_exceeded": False,
        },
        "MCP durable broker receipt",
    )
    expected_payloads = {"stdout": expected_stdout.encode(), "stderr": b"", "error": b""}
    for prefix, payload in expected_payloads.items():
        if (
            receipt[f"{prefix}_bytes"] != len(payload)
            or receipt[f"{prefix}_sha256"] != hashlib.sha256(payload).hexdigest()
        ):
            raise ConformanceFailure(f"MCP receipt does not bind {prefix} bytes")


def _assert_pi_observation(
    observation: dict[str, Any], case: dict[str, Any], runtime_root: Path
) -> None:
    _require_exact_shape(observation, PI_OBSERVATION_FIELDS, "Pi observation")
    if not isinstance(observation["content_text"], str):
        raise ConformanceFailure("Pi content_text is not a string")
    details = _require_exact_shape(
        observation["details"],
        frozenset({
            "root",
            "functionName",
            "argumentMetadata",
            "risk",
            "canonicalId",
            "result",
            "broker",
            "controlPlane",
        }),
        "Pi details",
    )
    metadata = _require_exact_shape(
        details["argumentMetadata"],
        frozenset({"count", "inputBytes", "fields"}),
        "Pi argument metadata",
    )
    result = _require_exact_shape(
        details["result"],
        frozenset({
            "code",
            "signal",
            "stdout",
            "stderr",
            "timedOut",
            "command",
            "argumentCount",
        }),
        "Pi public run result",
    )
    broker = _require_exact_shape(
        details["broker"],
        frozenset({
            "schemaVersion",
            "canonicalId",
            "resultKind",
            "status",
            "auditId",
            "durationMs",
            "outputExceeded",
            "error",
        }),
        "Pi broker metadata",
    )
    control_plane = _require_exact_shape(
        details["controlPlane"],
        frozenset({
            "schemaVersion",
            "status",
            "clientCorrelationId",
            "runId",
            "callId",
            "decisionId",
            "evidenceId",
            "inputDigest",
            "outcome",
            "resultAvailable",
            "brokerReceipt",
        }),
        "Pi durable control-plane metadata",
    )
    expected_stdout = _canonical_b64(
        case["expected_stdout_b64"], f"{case['case_id']}.expected_stdout_b64"
    ).decode("utf-8", errors="strict")
    expected_input = json.dumps(
        case["input"], ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    _assert_expected_fields(
        details,
        {
            "root": str(runtime_root),
            "functionName": case["function_name"],
            "risk": "low",
            "canonicalId": case["canonical_id"],
        },
        "Pi details",
    )
    _assert_expected_fields(
        metadata,
        {
            "count": len(case["positional_args"]),
            "inputBytes": len(expected_input),
            "fields": list(case["input"]),
        },
        "Pi argument metadata",
    )
    _assert_expected_fields(
        result,
        {
            "code": case["expected_exit_code"],
            "signal": None,
            "stdout": expected_stdout,
            "stderr": "",
            "timedOut": False,
            "command": str(runtime_root / "bin" / "mainframe"),
            "argumentCount": 12,
        },
        "Pi public run result",
    )
    _assert_expected_fields(
        broker,
        {
            "schemaVersion": 1,
            "canonicalId": case["canonical_id"],
            "resultKind": case["result_kind"],
            "status": "success",
            "outputExceeded": False,
            "error": None,
        },
        "Pi broker metadata",
    )
    if (
        not isinstance(broker["auditId"], str)
        or type(broker["durationMs"]) is not int
        or broker["durationMs"] < 0
    ):
        raise ConformanceFailure("Pi broker audit metadata is invalid")
    expected_digest = hashlib.sha256(
        json.dumps(
            case["input"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()
    _assert_expected_fields(
        control_plane,
        {
            "schemaVersion": 1,
            "status": "completed",
            "inputDigest": expected_digest,
            "outcome": "succeeded",
            "resultAvailable": True,
        },
        "Pi durable control-plane metadata",
    )
    for field, pattern in {
        "clientCorrelationId": r"^client-pi-[0-9a-f]{32}$",
        "runId": r"^run-[0-9a-f]{32}$",
        "callId": r"^call-[0-9a-f]{32}$",
        "decisionId": r"^decision-[0-9a-f]{32}$",
        "evidenceId": r"^evidence-[0-9a-f]{32}$",
    }.items():
        if not isinstance(control_plane[field], str) or not re.fullmatch(
            pattern, control_plane[field]
        ):
            raise ConformanceFailure(f"Pi durable {field} is invalid")
    receipt = control_plane["brokerReceipt"]
    if not isinstance(receipt, dict) or receipt.get("audit_id") != broker["auditId"]:
        raise ConformanceFailure("Pi durable receipt is absent or contradicts broker metadata")
    if observation["content_text"] != _expected_adapter_text(case, "pi"):
        raise ConformanceFailure("Pi text does not preserve the reviewed result bytes")


def _adapter_set(value: str) -> tuple[str, ...]:
    selected = tuple(part.strip() for part in value.split(",") if part.strip())
    unknown = set(selected) - set(ADAPTERS)
    if unknown or not selected or len(set(selected)) != len(selected):
        raise argparse.ArgumentTypeError(f"unknown/empty adapter set: {value}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument(
        "--runtime-root",
        type=_validate_runtime_root,
        default=_validate_runtime_root(SOURCE_ROOT),
        help=(
            "validated MAINFRAME runtime under test; clients remain loaded "
            "from the source repository (default: repository root)"
        ),
    )
    parser.add_argument(
        "--adapters",
        type=_adapter_set,
        default=ADAPTERS,
        help="comma-separated adapters (default: cli,node,python,mcp,pi)",
    )
    parser.add_argument(
        "--require-adapters",
        type=_adapter_set,
        default=("cli", "python", "mcp"),
        help="fail instead of skip when an adapter runtime is unavailable",
    )
    args = parser.parse_args()
    missing_required = set(args.require_adapters) - set(args.adapters)
    if missing_required:
        parser.error(f"required adapters were not selected: {sorted(missing_required)}")

    corpus_path = args.corpus.resolve(strict=True)
    runtime_root = args.runtime_root
    corpus = _read_json(corpus_path)
    policy = _read_json(runtime_root / "config" / "invocation-policy.json")
    manifest = _read_json(runtime_root / "MANIFEST.json")
    cases_by_id = validate_corpus(corpus, policy, manifest)
    cases = corpus["cases"]
    utf8_locale = _find_utf8_locale()
    print(
        f"corpus_ok contracts={len(policy['exports'])} cases={len(cases)} "
        f"edge_bytes=empty,whitespace,unicode locale={utf8_locale}",
        flush=True,
    )
    print(
        f"runtime_ok root={runtime_root} source_clients={SOURCE_ROOT}",
        flush=True,
    )

    runners: dict[str, Callable[[], list[dict[str, Any]] | None]] = {}
    with tempfile.TemporaryDirectory(prefix="mainframe-conformance-") as state_home_raw:
        state_home = str(Path(state_home_raw).resolve(strict=True))
        os.chmod(state_home, 0o700)
        environment = os.environ.copy()
        environment["MAINFRAME_ROOT"] = str(runtime_root)
        environment["XDG_STATE_HOME"] = state_home
        environment["LC_ALL"] = utf8_locale
        environment["LANG"] = utf8_locale
        node_build = (
            _prepare_node_build(
                environment,
                Path(state_home) / "node-build",
                "node" in args.require_adapters,
            )
            if "node" in args.adapters
            else None
        )
        if node_build is not None:
            print(
                "node_build_ok provenance=current-run-private "
                f"source_sha256={node_build.source_sha256} "
                f"artifact_sha256={node_build.artifact_sha256}",
                flush=True,
            )
        runners.update({
            "cli": lambda: run_cli(cases, environment, runtime_root),
            "node": lambda: run_node_helper(
                "node", cases, environment, corpus_path, runtime_root, node_build
            ),
            "python": lambda: run_python(cases, environment),
            "mcp": lambda: run_mcp(cases, environment, runtime_root),
            "pi": lambda: run_node_helper(
                "pi", cases, environment, corpus_path, runtime_root, node_build
            ),
        })
        exercised: list[str] = []
        skipped: list[str] = []
        with _process_environment(environment):
            for adapter in args.adapters:
                print(f"adapter_start name={adapter} cases={len(cases)}", flush=True)
                observations = runners[adapter]()
                if observations is None:
                    if adapter in args.require_adapters:
                        raise ConformanceFailure(
                            f"required adapter runtime is unavailable: {adapter}"
                        )
                    skipped.append(adapter)
                    print(
                        f"adapter_skip name={adapter} reason=runtime-unavailable",
                        flush=True,
                    )
                    continue
                assert_adapter(adapter, cases_by_id, observations, runtime_root)
                exercised.append(adapter)
                scope = {
                    "node": "client=built-node-package runtime=node",
                    "mcp": "transport=stdio dispatch=server",
                    "pi": "extension=runtime-root loader=installed-pi",
                }.get(adapter, "client=source-repo")
                print(
                    f"adapter_ok name={adapter} cases={len(observations)} {scope}",
                    flush=True,
                )

    print(
        "stable_core_conformance=PASS "
        f"contracts=26 cases={len(cases)} adapters={','.join(exercised)} "
        f"skipped={','.join(skipped) or 'none'}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConformanceFailure as error:
        print(f"stable_core_conformance=FAIL {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)

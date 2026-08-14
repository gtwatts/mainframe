#!/usr/bin/env python3
"""Prepare or verify a privacy-safe synthetic Pi/AWM transition receipt.

Both actions are offline transformations.  This program does not import Pi,
start MAINFRAME, launch an agent, load a provider adapter, or contact a
provider.  The separately explicit run-agent-impact-awm-fixture.py command
creates the private raw execution record consumed here.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import json
import os
import pathlib
import re
import stat
import sys
from typing import Any, NoReturn


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTOCOL_ROOT = PROJECT_ROOT / "evals" / "agent-impact"
SUPPORT_PATH = pathlib.Path(__file__).resolve().with_name("run-agent-impact-awm-fixture.py")
CLAIM_SCOPE = "synthetic-treatment-investigate-awm-mechanism-conformance-only"
RAW_KIND = "mainframe-agent-impact-pi-awm-transition-private-record"
RECEIPT_KIND = "mainframe-agent-impact-awm-transition-receipt"
PUBLIC_KIND = "mainframe-agent-impact-awm-transition-public"
NEUTRAL_KIND = "mainframe-agent-impact-neutral-continuation"
SNAPSHOT_ALGORITHM = "mainframe-agent-impact-private-tree-sha256-v1"
PACKAGE_TREE_ALGORITHM = "mainframe-package-tree-sha256-v1"
SEQUENCE_ALGORITHM = "sha256-canonical-json-previous-record-v1"
COMMITMENT_ALGORITHM = "hmac-sha256-domain-separated-v1"
MAX_CONTEXT_BYTES = 8192
MAX_AUDIT_KEY_BYTES = 1024
MIN_AUDIT_KEY_BYTES = 32
MAX_PUBLIC_BYTES = 1024 * 1024
ZERO_SHA256 = "0" * 64
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MODE_RE = re.compile(r"^[0-7]{4}$")
RELATIVE_RE = re.compile(r"^(?!/)(?!.*(?:^|/)\.\.?(?:/|$))(?!.*\\)[^\x00-\x1f\x7f]+$")
ABSOLUTE_WINDOWS_RE = re.compile(r"^[A-Za-z]:[\\/]")
BASH_VERSION_RE = re.compile(r"^\d+\.\d+(?:\.\d+)?\(\d+\)-[A-Za-z0-9._+-]+$")
SESSION_RE = re.compile(r"^[0-9a-f]{12}$")
HANDOFF_ID_RE = re.compile(r"^handoff_[0-9]+_[A-Za-z0-9_-]+$")
ISO_TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$")
NPM_PACKAGE_RE = re.compile(r"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]{0,127}$")
VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/+:-]{0,255}$")
EXPECTED_AWM_SCRIPT_SHA256 = "0fd94d0fbe44e42b33a773959593017aff4724c04cc11a850a82ec1f6b07543c"
EXPECTED_BASH_ARGUMENT_PREFIX = ["--noprofile", "--norc", "-p", "-c"]
AWM_SCHEMA_VERSION = 2
AWM_CHARS_PER_TOKEN = 4

RAW_TOP_LEVEL_KEYS = (
    "schema_version",
    "kind",
    "claim_scope",
    "binding",
    "runtime_expected",
    "budget",
    "fixture",
    "request",
    "environment",
    "runtime_observed",
    "paths",
    "snapshots",
    "sequence",
    "handoff",
    "non_claims",
)
EXPECTED_TOOLS = [
    "mainframe_awm",
    "mainframe_bash_safety_check",
    "mainframe_exec",
    "mainframe_help",
    "mainframe_install_commands",
    "mainframe_search",
    "mainframe_status",
]
EXPECTED_FIXTURE = {
    "session_name": "pi-impact-handoff",
    "namespace": "pi-impact-test",
    "checkpoint_key": "implementation-root-cause",
    "checkpoint_value": "subtract used capacity from total capacity",
    "checkpoint_importance": "critical",
    "handoff_target": "implementer",
}
EXPECTED_NON_CLAIMS = {
    "real_provider_inference": "not-run",
    "live_agent_sessions": 0,
    "agent_quality": "not-measured",
    "comparative_agent_performance": "not-measured",
    "developer_productivity": "not-measured",
    "machine_safety": "not-established",
    "network_containment": "best-effort-node-api-guards-not-os-isolation",
}
PUBLIC_NON_CLAIMS = {
    "real_provider_inference": "not-run",
    "live_agent_sessions": 0,
    "agent_quality": "not-measured",
    "comparative_performance": "not-measured",
    "developer_productivity": "not-measured",
    "safety_improvement": "not-measured",
}
SCOPE_BOUNDARY = {
    "control_transition_receipt": "absent",
    "implement_phase_receipt": "absent",
    "claim_quality_isolation": "absent",
    "live_study_eligibility": "ineligible-preregistration-v2-does-not-prebind-receipt-runtime",
}
CHECKS = {
    "committed_treatment_assignment": True,
    "real_pi_loader_surface_bound": True,
    "ordered_init_checkpoint_handoff": True,
    "all_operations_succeeded": True,
    "operation_chain_valid": True,
    "awm_state_changed_each_operation": True,
    "private_awm_modes_valid": True,
    "installed_tree_unchanged": True,
    "workspace_unchanged": True,
    "emitted_handoff_matches_persisted": True,
    "neutral_payload_matches_source_context": True,
    "neutral_envelope_within_budget": True,
    "bound_driver_declares_provider_requests_zero": True,
}


def load_support() -> Any:
    spec = importlib.util.spec_from_file_location("mainframe_awm_fixture_support", SUPPORT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the AWM fixture validation support module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SUPPORT = load_support()


class ReceiptError(RuntimeError):
    """A fail-closed receipt validation error."""


def die(message: str) -> NoReturn:
    raise ReceiptError(message)


def exact_keys(value: Any, keys: tuple[str, ...], label: str) -> dict[str, Any]:
    try:
        return SUPPORT.exact_keys(value, keys, label)
    except SUPPORT.FixtureError as error:
        die(str(error))


def canonical_bytes(value: Any) -> bytes:
    try:
        return SUPPORT.canonical_bytes(value)
    except SUPPORT.FixtureError as error:
        die(str(error))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require_string(value: Any, label: str, pattern: re.Pattern[str] | None = None) -> str:
    try:
        return SUPPORT.require_string(value, label, pattern)
    except SUPPORT.FixtureError as error:
        die(str(error))


def require_integer(value: Any, label: str, minimum: int = 0, maximum: int | None = None) -> int:
    try:
        result = SUPPORT.require_integer(value, label, minimum)
    except SUPPORT.FixtureError as error:
        die(str(error))
    if maximum is not None and result > maximum:
        die(f"{label} must not exceed {maximum}")
    return result


def require_bool(value: Any, expected: bool, label: str) -> None:
    if not isinstance(value, bool) or value is not expected:
        die(f"{label} must be the JSON boolean {str(expected).lower()}")


def require_integer_constant(value: Any, expected: int, label: str) -> int:
    result = require_integer(value, label, expected, expected)
    if result != expected:
        die(f"{label} must equal {expected}")
    return result


def load_json(path: pathlib.Path, label: str, mode: int | None = None) -> tuple[Any, bytes]:
    try:
        return SUPPORT.load_json(path, label, mode=mode)
    except SUPPORT.FixtureError as error:
        die(str(error))


def read_file(path: pathlib.Path, label: str, mode: int | None = None) -> bytes:
    try:
        path = SUPPORT.require_regular_file(path, label, maximum_bytes=None, mode=mode)
        return SUPPORT.read_file(path, label, maximum_bytes=None)
    except SUPPORT.FixtureError as error:
        die(str(error))


def strict_json_bytes(payload: bytes, label: str) -> Any:
    try:
        value = json.loads(
            payload.decode("utf-8", errors="strict"),
            object_pairs_hook=SUPPORT.reject_duplicate_pairs,
            parse_constant=SUPPORT.reject_nonfinite,
        )
        SUPPORT.enforce_json_bounds(value)
        return value
    except SUPPORT.FixtureError as error:
        die(str(error))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        die(f"{label} is not strict UTF-8 JSON: {error}")


def lexical_absolute_path(value: Any, label: str) -> str:
    value = require_string(value, label)
    if not value.startswith("/") or "\\" in value or "//" in value:
        die(f"{label} must be a normalized absolute POSIX path")
    parts = value.split("/")[1:]
    if any(part in ("", ".", "..") for part in parts):
        die(f"{label} must be a normalized absolute POSIX path")
    return value


def path_is_within(root: str, candidate: str) -> bool:
    return candidate == root or candidate.startswith(root.rstrip("/") + "/")


def validate_relative_path(value: Any, label: str) -> str:
    value = require_string(value, label, RELATIVE_RE)
    if value != pathlib.PurePosixPath(value).as_posix():
        die(f"{label} must be a canonical POSIX-relative path")
    return value


def validate_snapshot(value: Any, label: str) -> dict[str, Any]:
    snapshot = exact_keys(
        value,
        (
            "algorithm",
            "present",
            "root_mode",
            "entry_count",
            "file_count",
            "directory_count",
            "total_file_bytes",
            "tree_sha256",
            "entries",
        ),
        label,
    )
    if snapshot["algorithm"] != SNAPSHOT_ALGORITHM:
        die(f"{label} uses an unsupported tree algorithm")
    if not isinstance(snapshot["present"], bool):
        die(f"{label}.present must be a JSON boolean")
    entry_count = require_integer(snapshot["entry_count"], f"{label}.entry_count", 0, 100_000)
    file_count = require_integer(snapshot["file_count"], f"{label}.file_count", 0, entry_count)
    directory_count = require_integer(snapshot["directory_count"], f"{label}.directory_count", 0, entry_count)
    total_file_bytes = require_integer(snapshot["total_file_bytes"], f"{label}.total_file_bytes", 0, 1024 * 1024 * 1024)
    require_string(snapshot["tree_sha256"], f"{label}.tree_sha256", SHA256_RE)
    entries = snapshot["entries"]
    if not isinstance(entries, list) or len(entries) != entry_count:
        die(f"{label}.entries does not match entry_count")
    if file_count + directory_count != entry_count:
        die(f"{label} file and directory counts do not cover every entry")
    if not snapshot["present"]:
        if snapshot["root_mode"] is not None or entries or total_file_bytes != 0:
            die(f"{label} absent-tree representation is inconsistent")
    else:
        require_string(snapshot["root_mode"], f"{label}.root_mode", MODE_RE)

    observed_files = 0
    observed_directories = 0
    observed_bytes = 0
    observed_paths: list[str] = []
    for index, entry_value in enumerate(entries):
        if not isinstance(entry_value, dict) or entry_value.get("type") not in ("directory", "file"):
            die(f"{label}.entries[{index}] has an invalid type")
        if entry_value["type"] == "directory":
            entry = exact_keys(entry_value, ("path", "type", "mode"), f"{label} directory entry")
            observed_directories += 1
        else:
            entry = exact_keys(
                entry_value,
                ("path", "type", "mode", "size_bytes", "sha256"),
                f"{label} file entry",
            )
            observed_files += 1
            observed_bytes += require_integer(entry["size_bytes"], f"{label} file size", 0, 128 * 1024 * 1024)
            require_string(entry["sha256"], f"{label} file digest", SHA256_RE)
        observed_paths.append(validate_relative_path(entry["path"], f"{label} entry path"))
        require_string(entry["mode"], f"{label} entry mode", MODE_RE)
    if len(set(observed_paths)) != len(observed_paths):
        die(f"{label} contains duplicate paths")
    if observed_paths != sorted(observed_paths, key=lambda item: item.encode("utf-8")):
        die(f"{label} paths are not in canonical UTF-8 order")
    if observed_files != file_count or observed_directories != directory_count or observed_bytes != total_file_bytes:
        die(f"{label} derived counts do not match the declared counts")
    if sha256_bytes(canonical_bytes(entries)) != snapshot["tree_sha256"]:
        die(f"{label} tree digest does not reproduce from its entries")
    return snapshot


def validate_package_snapshot(value: Any, label: str, expected_sha256: str) -> dict[str, Any]:
    package = exact_keys(value, ("algorithm", "sha256", "entry_count"), label)
    if package["algorithm"] != PACKAGE_TREE_ALGORITHM:
        die(f"{label} uses an unsupported package-tree algorithm")
    require_string(package["sha256"], f"{label}.sha256", SHA256_RE)
    require_integer(package["entry_count"], f"{label}.entry_count", 1, 100_000)
    if package["sha256"] != expected_sha256:
        die(f"{label} does not match the committed installed-tree digest")
    return package


def validate_binding_and_release(
    raw: dict[str, Any],
    preregistration: Any,
    preregistration_payload: bytes,
    assignments_value: Any,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(raw.get("binding"), dict):
        die("private raw record binding must be an object")
    try:
        assignments = SUPPORT.validate_private_assignments(assignments_value)
        expected_binding, release = SUPPORT.select_treatment_binding(
            preregistration,
            assignments,
            raw.get("binding", {}).get("pair_id", ""),
            raw.get("binding", {}).get("opaque_arm_id", ""),
            sha256_bytes(preregistration_payload),
        )
    except SUPPORT.FixtureError as error:
        die(str(error))
    raw_binding = exact_keys(raw["binding"], tuple(expected_binding), "private raw record binding")
    require_integer(raw_binding["replicate"], "private raw record binding replicate", 1, 1000)
    if canonical_bytes(raw_binding) != canonical_bytes(expected_binding):
        die("private raw record does not exactly match the committed treatment assignment")
    runtime = raw["runtime_expected"]
    if runtime.get("mainframe_archive_sha256") != release["archive_sha256"]:
        die("raw runtime archive digest differs from the preregistration")
    if runtime.get("installed_tree_algorithm") != release["installed_tree_algorithm"]:
        die("raw runtime installed-tree algorithm differs from the preregistration")
    if runtime.get("installed_tree_sha256") != release["installed_tree_sha256"]:
        die("raw runtime installed-tree digest differs from the preregistration")
    return expected_binding, release


def validate_runtime(raw: dict[str, Any]) -> None:
    runtime_expected = exact_keys(
        raw["runtime_expected"],
        (
            "mainframe_archive_sha256",
            "installed_tree_algorithm",
            "installed_tree_sha256",
            "pi_package",
            "pi_version",
            "pi_executable_sha256",
            "pi_loader_sha256",
            "pi_extension_sha256",
            "transition_driver_sha256",
            "node_executable_sha256",
            "node_version",
        ),
        "raw runtime_expected",
    )
    for key in (
        "mainframe_archive_sha256",
        "installed_tree_sha256",
        "pi_executable_sha256",
        "pi_loader_sha256",
        "pi_extension_sha256",
        "transition_driver_sha256",
        "node_executable_sha256",
    ):
        require_string(runtime_expected[key], f"raw runtime_expected.{key}", SHA256_RE)
    if runtime_expected["installed_tree_algorithm"] != PACKAGE_TREE_ALGORITHM:
        die("raw runtime expected installed-tree algorithm is invalid")
    require_string(runtime_expected["pi_package"], "raw runtime_expected.pi_package", NPM_PACKAGE_RE)
    for key in ("pi_version", "node_version"):
        require_string(runtime_expected[key], f"raw runtime_expected.{key}", VERSION_RE)

    observed = exact_keys(
        raw["runtime_observed"],
        (
            "mainframe_archive_sha256",
            "mainframe_version",
            "installed_tree_algorithm",
            "installed_tree_sha256",
            "pi_package",
            "pi_version",
            "pi_executable",
            "pi_executable_sha256",
            "pi_package_manifest_sha256",
            "pi_loader",
            "pi_loader_sha256",
            "pi_extension",
            "pi_extension_sha256",
            "transition_driver",
            "transition_driver_sha256",
            "node_executable",
            "node_executable_sha256",
            "node_version",
            "bash_executable",
            "bash_executable_sha256",
            "bash_version",
            "registered_tools",
            "loaded_mainframe_awm",
            "network_api_guards",
            "provider_adapter_loaded",
            "provider_inference_requests",
        ),
        "raw runtime_observed",
    )
    for key in (
        "pi_executable",
        "pi_loader",
        "pi_extension",
        "transition_driver",
        "node_executable",
        "bash_executable",
    ):
        lexical_absolute_path(observed[key], f"raw runtime_observed.{key}")
    for key in (
        "pi_executable_sha256",
        "pi_package_manifest_sha256",
        "pi_loader_sha256",
        "pi_extension_sha256",
        "transition_driver_sha256",
        "node_executable_sha256",
        "bash_executable_sha256",
        "installed_tree_sha256",
        "mainframe_archive_sha256",
    ):
        require_string(observed[key], f"raw runtime_observed.{key}", SHA256_RE)
    comparisons = {
        "mainframe_archive_sha256": "mainframe_archive_sha256",
        "installed_tree_sha256": "installed_tree_sha256",
        "pi_package": "pi_package",
        "pi_version": "pi_version",
        "pi_executable_sha256": "pi_executable_sha256",
        "pi_loader_sha256": "pi_loader_sha256",
        "pi_extension_sha256": "pi_extension_sha256",
        "transition_driver_sha256": "transition_driver_sha256",
        "node_executable_sha256": "node_executable_sha256",
    }
    for observed_key, expected_key in comparisons.items():
        if observed[observed_key] != runtime_expected[expected_key]:
            die(f"raw observed runtime {observed_key} differs from its expected binding")
    observed_node_version = require_string(observed["node_version"], "raw observed Node version", VERSION_RE)
    if observed_node_version.removeprefix("v") != runtime_expected["node_version"].removeprefix("v"):
        die("raw observed Node version differs from its expected binding")
    if observed["installed_tree_algorithm"] != PACKAGE_TREE_ALGORITHM:
        die("raw observed installed-tree algorithm is invalid")
    require_string(observed["mainframe_version"], "raw observed MAINFRAME version", VERSION_RE)
    require_string(observed["bash_version"], "raw observed Bash version", BASH_VERSION_RE)
    if observed["registered_tools"] != EXPECTED_TOOLS:
        die("raw observed Pi tool surface is not the exact seven-tool contract")
    require_bool(observed["loaded_mainframe_awm"], True, "raw loaded_mainframe_awm")
    require_bool(observed["provider_adapter_loaded"], False, "raw provider_adapter_loaded")
    if require_integer(observed["provider_inference_requests"], "raw provider request count", 0) != 0:
        die("raw record reports provider inference")
    guards = observed["network_api_guards"]
    if (
        not isinstance(guards, list)
        or not 8 <= len(guards) <= 32
        or len(set(guards)) != len(guards)
        or guards != sorted(guards)
        or not all(isinstance(item, str) and item for item in guards)
    ):
        die("raw record lacks the bounded Node network API guard inventory")


def validate_environment_and_paths(raw: dict[str, Any]) -> None:
    paths = exact_keys(
        raw["paths"],
        ("mainframe_root", "pi_bin", "node_bin", "workspace", "awm_root", "tmp_root"),
        "raw paths",
    )
    for key, value in paths.items():
        lexical_absolute_path(value, f"raw paths.{key}")
    if not path_is_within(paths["mainframe_root"], raw["runtime_observed"]["pi_extension"]):
        die("observed Pi extension is outside the extracted MAINFRAME tree")
    if not path_is_within(paths["mainframe_root"], raw["runtime_observed"]["transition_driver"]):
        die("observed transition driver is outside the extracted MAINFRAME tree")
    environment = exact_keys(raw["environment"], ("allowed_names", "values", "isolated_paths"), "raw environment")
    allowed = environment["allowed_names"]
    if not isinstance(allowed, list) or len(set(allowed)) != len(allowed) or allowed != sorted(allowed):
        die("raw environment allowlist is invalid")
    forbidden_names = [
        name for name in allowed
        if re.search(r"(?:TOKEN|SECRET|PASSWORD|CREDENTIAL|API_KEY|AUTH|COOKIE)", str(name), re.IGNORECASE)
    ]
    if forbidden_names:
        die("raw environment allowlist contains a credential-like name")
    values = exact_keys(
        environment["values"],
        (
            "USER",
            "LOGNAME",
            "PI_OFFLINE",
            "PATH",
            "LC_ALL",
            "LANG",
            "NO_COLOR",
            "CI",
            "MAINFRAME_EVAL_PROTOCOL",
            "__CF_USER_TEXT_ENCODING",
        ),
        "raw environment values",
    )
    expected_values = {
        "USER": "mainframe-eval",
        "LOGNAME": "mainframe-eval",
        "PI_OFFLINE": "1",
        "PATH": SUPPORT.SAFE_PATH,
        "LC_ALL": "C",
        "LANG": "C",
        "NO_COLOR": "1",
        "CI": "1",
        "MAINFRAME_EVAL_PROTOCOL": "1",
    }
    if any(values.get(key) != expected for key, expected in expected_values.items()):
        die("raw environment does not bind offline fixture mode")
    cf_value = values["__CF_USER_TEXT_ENCODING"]
    if cf_value is not None and (
        not isinstance(cf_value, str)
        or re.fullmatch(r"0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+", cf_value) is None
    ):
        die("raw Darwin text-encoding environment value is invalid")
    isolated = exact_keys(
        environment["isolated_paths"],
        ("HOME", "PI_CODING_AGENT_DIR", "TMPDIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"),
        "raw isolated environment paths",
    )
    for key, value in isolated.items():
        lexical_absolute_path(value, f"raw isolated environment path {key}")
    expected_allowed = sorted([*expected_values, *isolated, *( ["__CF_USER_TEXT_ENCODING"] if cf_value is not None else [])])
    if allowed != expected_allowed:
        die("raw environment allowlist does not exactly match the serialized scrubbed environment")
    if isolated.get("TMPDIR") != paths["tmp_root"]:
        die("raw environment TMPDIR differs from the request")
    if not str(paths["awm_root"]).startswith(str(isolated.get("HOME", "")).rstrip("/") + "/"):
        die("raw AWM root is outside the isolated HOME")

    scratch = pathlib.PurePosixPath(paths["mainframe_root"]).parent
    if scratch == pathlib.PurePosixPath("/"):
        die("raw runtime scratch graph has no private parent")
    expected_scratch_paths = {
        "paths.mainframe_root": scratch / "install",
        "paths.workspace": scratch / "workspace",
        "paths.awm_root": scratch / "home" / ".mainframe" / "awm",
        "paths.tmp_root": scratch / "tmp",
        "environment.HOME": scratch / "home",
        "environment.PI_CODING_AGENT_DIR": scratch / "pi-agent",
        "environment.TMPDIR": scratch / "tmp",
        "environment.XDG_CONFIG_HOME": scratch / "xdg-config",
        "environment.XDG_STATE_HOME": scratch / "xdg-state",
        "environment.XDG_CACHE_HOME": scratch / "xdg-cache",
        "request.path": scratch / "private" / "request.json",
    }
    observed_scratch_paths = {
        "paths.mainframe_root": paths["mainframe_root"],
        "paths.workspace": paths["workspace"],
        "paths.awm_root": paths["awm_root"],
        "paths.tmp_root": paths["tmp_root"],
        "environment.HOME": isolated["HOME"],
        "environment.PI_CODING_AGENT_DIR": isolated["PI_CODING_AGENT_DIR"],
        "environment.TMPDIR": isolated["TMPDIR"],
        "environment.XDG_CONFIG_HOME": isolated["XDG_CONFIG_HOME"],
        "environment.XDG_STATE_HOME": isolated["XDG_STATE_HOME"],
        "environment.XDG_CACHE_HOME": isolated["XDG_CACHE_HOME"],
        "request.path": raw["request"]["path"],
    }
    for label, expected in expected_scratch_paths.items():
        if pathlib.PurePosixPath(observed_scratch_paths[label]) != expected:
            die(f"raw runtime path graph differs at {label}")

    observed_runtime = raw["runtime_observed"]
    expected_runtime_paths = {
        "pi_executable": pathlib.PurePosixPath(paths["pi_bin"]),
        "node_executable": pathlib.PurePosixPath(paths["node_bin"]),
        "pi_loader": pathlib.PurePosixPath(paths["pi_bin"]).parent / "core" / "extensions" / "loader.js",
        "pi_extension": pathlib.PurePosixPath(paths["mainframe_root"]) / "skills" / "pi" / "extensions" / "mainframe.ts",
        "transition_driver": pathlib.PurePosixPath(paths["mainframe_root"])
        / "evals"
        / "agent-impact"
        / "runners"
        / "pi-awm-transition-driver.mjs",
    }
    for key, expected in expected_runtime_paths.items():
        if pathlib.PurePosixPath(observed_runtime[key]) != expected:
            die(f"raw observed runtime path graph differs at {key}")


def validate_request_binding(raw: dict[str, Any]) -> None:
    request = exact_keys(raw["request"], ("path", "file_sha256", "canonical_sha256"), "raw request")
    lexical_absolute_path(request["path"], "raw request path")
    require_string(request["file_sha256"], "raw request file digest", SHA256_RE)
    require_string(request["canonical_sha256"], "raw request canonical digest", SHA256_RE)
    reconstructed = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-pi-awm-transition-request",
        "claim_scope": CLAIM_SCOPE,
        "binding": raw["binding"],
        "paths": raw["paths"],
        "runtime_expected": raw["runtime_expected"],
        "budget": raw["budget"],
        "fixture": raw["fixture"],
    }
    canonical = canonical_bytes(reconstructed)
    if request["canonical_sha256"] != sha256_bytes(canonical):
        die("raw request canonical digest does not reproduce")
    if request["file_sha256"] != sha256_bytes(canonical + b"\n"):
        die("raw request file digest does not reproduce")


def process_result_keys(value: Any, label: str) -> dict[str, Any]:
    result = exact_keys(value, ("code", "signal", "stdout", "stderr", "timedOut", "command", "args"), label)
    require_integer_constant(result["code"], 0, f"{label}.code")
    if result["signal"] is not None:
        die(f"{label} was terminated by a signal")
    require_bool(result["timedOut"], False, f"{label}.timedOut")
    if not isinstance(result["stdout"], str) or not isinstance(result["stderr"], str):
        die(f"{label} stdout/stderr must be strings")
    lexical_absolute_path(result["command"], f"{label}.command")
    arguments = result["args"]
    if (
        not isinstance(arguments, list)
        or len(arguments) != 5
        or arguments[:4] != EXPECTED_BASH_ARGUMENT_PREFIX
        or not isinstance(arguments[4], str)
        or not arguments[4]
        or len(arguments[4].encode("utf-8")) > 32_768
    ):
        die(f"{label}.args must be the protected five-argument Bash invocation")
    return result


def validate_sequence(raw: dict[str, Any], snapshots: dict[str, Any]) -> None:
    sequence = exact_keys(
        raw["sequence"],
        ("algorithm", "genesis_sha256", "record_count", "head_sha256", "records"),
        "raw sequence",
    )
    if sequence["algorithm"] != SEQUENCE_ALGORITHM or sequence["genesis_sha256"] != ZERO_SHA256:
        die("raw operation sequence algorithm or genesis is invalid")
    if require_integer(sequence["record_count"], "raw sequence record count", 0) != 3:
        die("raw operation sequence must contain exactly three records")
    require_string(sequence["head_sha256"], "raw sequence head", SHA256_RE)
    records = sequence["records"]
    if not isinstance(records, list) or len(records) != 3:
        die("raw operation sequence record list is invalid")
    expected_actions = ["init", "checkpoint", "handoff_prepare"]
    state_pairs = [
        (snapshots["awm_before"], snapshots["awm_after_init"]),
        (snapshots["awm_after_init"], snapshots["awm_after_checkpoint"]),
        (snapshots["awm_after_checkpoint"], snapshots["awm_after_handoff"]),
    ]
    prior = ZERO_SHA256
    session_id = require_string(raw["handoff"]["session_id"], "raw sequence session id", SESSION_RE)
    commands: list[str] = []
    scripts: list[str] = []
    for offset, (record_value, action, state_pair) in enumerate(zip(records, expected_actions, state_pairs), 1):
        record = exact_keys(
            record_value,
            (
                "index",
                "action",
                "call_id",
                "previous_record_sha256",
                "tool_params",
                "awm_before_sha256",
                "awm_after_sha256",
                "process_result",
                "stdout_binding",
                "stderr_binding",
                "record_sha256",
            ),
            f"raw sequence record {offset}",
        )
        if require_integer(record["index"], f"raw sequence record {offset} index", 1, 3) != offset or record["action"] != action:
            die("raw operation sequence is missing, reordered, or duplicated")
        expected_call_id = f"{raw['binding']['opaque_arm_id']}-awm-{offset}-{action}"
        if record["call_id"] != expected_call_id or record["previous_record_sha256"] != prior:
            die("raw operation sequence identity or previous-record chain is invalid")
        if record["awm_before_sha256"] != state_pair[0]["tree_sha256"] or record["awm_after_sha256"] != state_pair[1]["tree_sha256"]:
            die("raw operation sequence does not bind the exact AWM state transition")
        if record["awm_before_sha256"] == record["awm_after_sha256"]:
            die("raw AWM state did not change during a required operation")
        params = record["tool_params"]
        common = {
            "root": raw["paths"]["mainframe_root"],
            "timeoutMs": raw["budget"]["tool_timeout_ms"],
            "action": action,
        }
        if action == "init":
            expected_params = {
                **common,
                "name": raw["fixture"]["session_name"],
                "namespace": raw["fixture"]["namespace"],
                "model": "fixture-no-provider",
            }
        elif action == "checkpoint":
            expected_params = {
                **common,
                "session": session_id,
                "key": raw["fixture"]["checkpoint_key"],
                "value": raw["fixture"]["checkpoint_value"],
                "importance": raw["fixture"]["checkpoint_importance"],
            }
        else:
            expected_params = {
                **common,
                "session": session_id,
                "message": raw["fixture"]["handoff_target"],
                "tokens": raw["budget"]["maximum_context_bytes"] // 4,
            }
        if params != expected_params:
            die(f"raw {action} tool parameters differ from the fixed fixture contract")
        process = process_result_keys(record["process_result"], f"raw {action} process result")
        commands.append(process["command"])
        scripts.append(process["args"][4])
        if action == "init" and process["stdout"] != session_id:
            die("raw init stdout is not the exact bound session id")
        if action == "checkpoint" and process["stdout"] != "":
            die("raw checkpoint operation emitted unexpected stdout")
        stdout_bytes = process["stdout"].encode("utf-8")
        stderr_bytes = process["stderr"].encode("utf-8")
        for field, payload in (("stdout_binding", stdout_bytes), ("stderr_binding", stderr_bytes)):
            binding = exact_keys(record[field], ("size_bytes", "sha256"), f"raw {action} {field}")
            size_bytes = require_integer(binding["size_bytes"], f"raw {action} {field} size", 0, 1024 * 1024)
            if size_bytes != len(payload) or binding["sha256"] != sha256_bytes(payload):
                die(f"raw {action} {field} does not reproduce")
        if process["stderr"] != "":
            die(f"raw {action} operation emitted stderr")
        body = dict(record)
        declared = body.pop("record_sha256")
        if require_string(declared, f"raw {action} record digest", SHA256_RE) != sha256_bytes(canonical_bytes(body)):
            die(f"raw {action} record digest does not reproduce")
        prior = declared
    if len(set(commands)) != 1 or commands[0] != raw["runtime_observed"]["bash_executable"]:
        die("raw operations do not share the bound Bash executable")
    if (
        len(set(scripts)) != 1
        or sha256_bytes(scripts[0].encode("utf-8")) != EXPECTED_AWM_SCRIPT_SHA256
    ):
        die("raw operations do not share the exact protected MAINFRAME AWM Bash script")
    if prior != sequence["head_sha256"]:
        die("raw operation sequence head does not match its final record")


def validate_awm_provenance(
    value: Any,
    raw: dict[str, Any],
    label: str,
    *,
    include_source_agent: bool,
) -> None:
    keys = ("schema_version", "namespace", "backend", "source_agent") if include_source_agent else (
        "schema_version",
        "namespace",
        "backend",
    )
    provenance = exact_keys(value, keys, label)
    require_integer_constant(provenance["schema_version"], AWM_SCHEMA_VERSION, f"{label}.schema_version")
    if provenance["namespace"] != raw["fixture"]["namespace"] or provenance["backend"] != "file":
        die(f"{label} does not bind the fixed namespace and file backend")
    if include_source_agent and provenance["source_agent"] != "mainframe-eval":
        die(f"{label} does not bind the isolated fixture agent")


def validate_awm_budget(
    value: Any,
    label: str,
    *,
    requested_tokens: int,
    actual_chars: int,
    truncated: bool,
) -> None:
    budget = exact_keys(
        value,
        ("requested_tokens", "chars_per_token", "max_chars", "actual_chars", "actual_tokens", "truncated"),
        label,
    )
    require_integer_constant(budget["requested_tokens"], requested_tokens, f"{label}.requested_tokens")
    require_integer_constant(budget["chars_per_token"], AWM_CHARS_PER_TOKEN, f"{label}.chars_per_token")
    require_integer_constant(
        budget["max_chars"],
        requested_tokens * AWM_CHARS_PER_TOKEN,
        f"{label}.max_chars",
    )
    require_integer_constant(budget["actual_chars"], actual_chars, f"{label}.actual_chars")
    require_integer_constant(
        budget["actual_tokens"],
        (actual_chars + AWM_CHARS_PER_TOKEN - 1) // AWM_CHARS_PER_TOKEN,
        f"{label}.actual_tokens",
    )
    require_bool(budget["truncated"], truncated, f"{label}.truncated")


def validate_awm_status(value: Any, raw: dict[str, Any]) -> None:
    status = exact_keys(
        value,
        (
            "session_id",
            "schema_version",
            "status",
            "namespace",
            "backend",
            "manifest",
            "discoveries",
            "checkpoints",
            "handoffs",
            "logs",
            "token_estimate",
        ),
        "raw emitted handoff status",
    )
    if status["session_id"] != raw["handoff"]["session_id"]:
        die("raw emitted handoff status changes the session id")
    require_integer_constant(status["schema_version"], AWM_SCHEMA_VERSION, "raw emitted handoff status schema_version")
    if status["status"] != "active" or status["namespace"] != raw["fixture"]["namespace"] or status["backend"] != "file":
        die("raw emitted handoff status changes the active file-backed fixture identity")
    expected_manifest = (
        raw["paths"]["awm_root"].rstrip("/")
        + "/sessions/"
        + raw["fixture"]["namespace"]
        + "/"
        + raw["handoff"]["session_id"]
        + "/manifest.json"
    )
    if lexical_absolute_path(status["manifest"], "raw emitted handoff status manifest") != expected_manifest:
        die("raw emitted handoff status manifest path is invalid")
    for key in ("discoveries", "checkpoints", "handoffs", "logs", "token_estimate"):
        require_integer(status[key], f"raw emitted handoff status {key}", 0, 100_000)
    require_integer_constant(status["handoffs"], 0, "raw emitted handoff status handoffs")


def validate_handoff(raw: dict[str, Any], snapshots: dict[str, Any]) -> tuple[dict[str, Any], bytes]:
    handoff = exact_keys(
        raw["handoff"],
        (
            "session_id",
            "handoff_id",
            "persisted_path",
            "emitted_size_bytes",
            "emitted_sha256",
            "emitted_raw_utf8",
            "persisted_size_bytes",
            "persisted_sha256",
            "persisted_raw_utf8",
            "emitted_equals_persisted",
            "maximum_context_bytes",
        ),
        "raw handoff",
    )
    require_string(handoff["session_id"], "raw handoff session id", SESSION_RE)
    require_string(handoff["handoff_id"], "raw handoff id", HANDOFF_ID_RE)
    persisted_path = lexical_absolute_path(handoff["persisted_path"], "raw persisted handoff path")
    if not path_is_within(raw["paths"]["awm_root"], persisted_path):
        die("persisted handoff is outside the private AWM root")
    emitted = handoff["emitted_raw_utf8"]
    persisted = handoff["persisted_raw_utf8"]
    if not isinstance(emitted, str) or not isinstance(persisted, str) or not emitted or emitted != persisted:
        die("raw emitted and persisted handoff text must be non-empty and byte-identical")
    emitted_bytes = emitted.encode("utf-8")
    persisted_bytes = persisted.encode("utf-8")
    emitted_size = require_integer(handoff["emitted_size_bytes"], "raw emitted handoff size", 1, MAX_CONTEXT_BYTES)
    persisted_size = require_integer(handoff["persisted_size_bytes"], "raw persisted handoff size", 1, MAX_CONTEXT_BYTES)
    if emitted_size != len(emitted_bytes) or persisted_size != len(persisted_bytes):
        die("raw handoff byte measurements do not reproduce")
    if handoff["emitted_sha256"] != sha256_bytes(emitted_bytes) or handoff["persisted_sha256"] != sha256_bytes(persisted_bytes):
        die("raw handoff digests do not reproduce")
    require_bool(handoff["emitted_equals_persisted"], True, "raw emitted_equals_persisted")
    require_integer_constant(handoff["maximum_context_bytes"], MAX_CONTEXT_BYTES, "raw maximum context bytes")
    if len(emitted_bytes) > MAX_CONTEXT_BYTES:
        die("raw handoff exceeds or changes the fixed byte budget")
    expected_path = (
        raw["paths"]["awm_root"].rstrip("/")
        + "/sessions/"
        + raw["fixture"]["namespace"]
        + "/"
        + handoff["session_id"]
        + "/handoffs/"
        + handoff["handoff_id"]
        + ".json"
    )
    if persisted_path != expected_path:
        die("raw persisted handoff path is not the direct fixed AWM artifact path")
    relative = persisted_path[len(raw["paths"]["awm_root"].rstrip("/") + "/") :]
    matching_entries = [entry for entry in snapshots["awm_after_handoff"]["entries"] if entry["path"] == relative]
    if len(matching_entries) != 1:
        die("persisted handoff is absent or duplicated in the terminal AWM snapshot")
    entry = matching_entries[0]
    if entry.get("type") != "file" or entry.get("mode") != "0600" or entry.get("size_bytes") != len(persisted_bytes) or entry.get("sha256") != sha256_bytes(persisted_bytes):
        die("terminal AWM snapshot does not bind the private persisted handoff")
    document = exact_keys(
        strict_json_bytes(emitted_bytes, "raw emitted handoff"),
        (
            "type",
            "handoff_id",
            "created_at",
            "parent_session",
            "parent_agent",
            "target_agent",
            "budget_remaining",
            "provenance",
            "budget",
            "status",
            "open_questions",
            "context",
        ),
        "raw emitted handoff document",
    )
    if document["type"] != "handoff":
        die("raw emitted handoff is not a MAINFRAME handoff object")
    if document["parent_session"] != handoff["session_id"] or document["handoff_id"] != handoff["handoff_id"]:
        die("raw emitted handoff identity is inconsistent")
    require_string(document["created_at"], "raw emitted handoff creation timestamp", ISO_TIMESTAMP_RE)
    if document["parent_agent"] != "mainframe-eval":
        die("raw emitted handoff does not bind the isolated fixture agent")
    if document["target_agent"] != raw["fixture"]["handoff_target"]:
        die("raw emitted handoff target is inconsistent")
    require_integer(document["budget_remaining"], "raw emitted handoff remaining token budget", 0, 1_000_000)
    validate_awm_provenance(document["provenance"], raw, "raw emitted handoff provenance", include_source_agent=False)
    validate_awm_budget(
        document["budget"],
        "raw emitted handoff budget",
        requested_tokens=MAX_CONTEXT_BYTES // AWM_CHARS_PER_TOKEN,
        actual_chars=len(emitted_bytes),
        truncated=False,
    )
    validate_awm_status(document["status"], raw)
    if document["open_questions"] != []:
        die("raw emitted handoff contains unexpected open questions")
    context = exact_keys(
        document["context"],
        (
            "task",
            "session_id",
            "max_tokens",
            "provenance",
            "budget",
            "discoveries",
            "progress",
            "checkpoints",
            "logs",
            "related",
            "summary",
        ),
        "raw emitted handoff context",
    )
    if context["task"] != raw["fixture"]["handoff_target"] or context["session_id"] != handoff["session_id"]:
        die("raw emitted handoff context identity is inconsistent")
    require_integer_constant(
        context["max_tokens"],
        MAX_CONTEXT_BYTES // AWM_CHARS_PER_TOKEN,
        "raw emitted handoff context max_tokens",
    )
    validate_awm_provenance(
        context["provenance"],
        raw,
        "raw emitted handoff context provenance",
        include_source_agent=True,
    )
    validate_awm_budget(
        context["budget"],
        "raw emitted handoff context budget",
        requested_tokens=MAX_CONTEXT_BYTES // AWM_CHARS_PER_TOKEN,
        actual_chars=len(canonical_bytes(context)),
        truncated=False,
    )
    for key in ("discoveries", "checkpoints", "logs", "related"):
        if not isinstance(context[key], list):
            die(f"raw emitted handoff context {key} must be an array")
    for key in ("progress", "summary"):
        if not isinstance(context[key], dict):
            die(f"raw emitted handoff context {key} must be an object")
    reject_absolute_strings(
        context,
        "source handoff context",
        forbidden_substrings=list(raw["paths"].values()) + list(raw["environment"]["isolated_paths"].values()),
    )
    neutral = {
        "schema_version": 1,
        "kind": NEUTRAL_KIND,
        "payload": context,
    }
    neutral_payload = canonical_bytes(neutral) + b"\n"
    if len(neutral_payload) <= 0 or len(neutral_payload) > MAX_CONTEXT_BYTES:
        die("derived neutral continuation envelope violates the byte budget")
    return document, neutral_payload


def reject_absolute_strings(
    value: Any,
    label: str,
    forbidden_substrings: list[str] | None = None,
) -> None:
    stack = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
        elif isinstance(current, str):
            if current.startswith("/") or current.startswith("~") or ABSOLUTE_WINDOWS_RE.match(current):
                die(f"{label} contains an absolute or home-relative path")
            if forbidden_substrings and any(item and item in current for item in forbidden_substrings):
                die(f"{label} contains a private runtime path")


def validate_raw(
    raw: Any,
    raw_payload: bytes,
    preregistration: Any,
    preregistration_payload: bytes,
    assignments: Any,
) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    raw = exact_keys(raw, RAW_TOP_LEVEL_KEYS, "private raw record")
    require_integer_constant(raw["schema_version"], 1, "private raw record schema version")
    if raw["kind"] != RAW_KIND or raw["claim_scope"] != CLAIM_SCOPE:
        die("private raw record kind, version, or claim scope is invalid")
    binding, _release = validate_binding_and_release(raw, preregistration, preregistration_payload, assignments)
    validate_runtime(raw)
    budget = exact_keys(raw["budget"], ("maximum_context_bytes", "tool_timeout_ms"), "raw budget")
    require_integer_constant(
        budget["maximum_context_bytes"],
        MAX_CONTEXT_BYTES,
        "raw maximum context bytes",
    )
    require_integer(budget["tool_timeout_ms"], "raw tool timeout", 1000, 300_000)
    fixture = exact_keys(raw["fixture"], tuple(EXPECTED_FIXTURE), "raw fixture")
    if canonical_bytes(fixture) != canonical_bytes(EXPECTED_FIXTURE):
        die("raw record changes the fixed non-secret synthetic fixture")
    non_claims = exact_keys(raw["non_claims"], tuple(EXPECTED_NON_CLAIMS), "raw non-claims")
    require_integer_constant(non_claims["live_agent_sessions"], 0, "raw non-claims live_agent_sessions")
    for key in set(EXPECTED_NON_CLAIMS) - {"live_agent_sessions"}:
        require_string(non_claims[key], f"raw non-claims {key}")
    if canonical_bytes(non_claims) != canonical_bytes(EXPECTED_NON_CLAIMS):
        die("raw record changes the mandatory non-claims")
    validate_request_binding(raw)
    validate_environment_and_paths(raw)
    snapshots = exact_keys(
        raw["snapshots"],
        (
            "installed_before",
            "installed_after",
            "installed_package_before",
            "installed_package_after",
            "workspace_before",
            "workspace_after",
            "awm_before",
            "awm_after_init",
            "awm_after_checkpoint",
            "awm_after_handoff",
            "tmp_before",
            "tmp_after",
            "installed_unchanged",
            "workspace_unchanged",
        ),
        "raw snapshots",
    )
    for key in (
        "installed_before",
        "installed_after",
        "workspace_before",
        "workspace_after",
        "awm_before",
        "awm_after_init",
        "awm_after_checkpoint",
        "awm_after_handoff",
        "tmp_before",
        "tmp_after",
    ):
        snapshots[key] = validate_snapshot(snapshots[key], f"raw snapshots.{key}")
    installed_package_before = validate_package_snapshot(
        snapshots["installed_package_before"],
        "raw installed package before",
        raw["runtime_expected"]["installed_tree_sha256"],
    )
    installed_package_after = validate_package_snapshot(
        snapshots["installed_package_after"],
        "raw installed package after",
        raw["runtime_expected"]["installed_tree_sha256"],
    )
    if installed_package_before != installed_package_after:
        die("raw installed package tree changed")
    if snapshots["installed_before"] != snapshots["installed_after"]:
        die("raw installed snapshot changed")
    if snapshots["workspace_before"] != snapshots["workspace_after"]:
        die("raw workspace changed during the read-only investigate fixture")
    require_bool(snapshots["installed_unchanged"], True, "raw installed_unchanged")
    require_bool(snapshots["workspace_unchanged"], True, "raw workspace_unchanged")
    if installed_package_before["entry_count"] != snapshots["installed_before"]["entry_count"]:
        die("raw installed package and private snapshot entry counts differ")
    if (
        not snapshots["workspace_before"]["present"]
        or snapshots["workspace_before"]["root_mode"] != "0700"
        or snapshots["workspace_before"]["entry_count"] != 0
    ):
        die("raw synthetic workspace was not a fresh empty private directory")
    if (
        not snapshots["tmp_before"]["present"]
        or snapshots["tmp_before"]["root_mode"] != "0700"
        or snapshots["tmp_before"]["entry_count"] != 0
    ):
        die("raw synthetic TMPDIR was not a fresh empty private directory")
    awm_before = snapshots["awm_before"]
    if awm_before["present"] or awm_before["entry_count"] != 0:
        die("raw AWM state was not absent before the fixture")
    for key in ("awm_after_init", "awm_after_checkpoint", "awm_after_handoff"):
        snapshot = snapshots[key]
        if not snapshot["present"] or snapshot["root_mode"] != "0700" or snapshot["entry_count"] <= 0:
            die(f"raw {key} is not a populated private AWM tree")
        for entry in snapshot["entries"]:
            expected_mode = "0700" if entry["type"] == "directory" else "0600"
            if entry["mode"] != expected_mode:
                die(f"raw {key} contains a non-private AWM entry mode")
    validate_sequence(raw, snapshots)
    handoff_document, neutral_payload = validate_handoff(raw, snapshots)
    if raw["sequence"]["records"][2]["process_result"]["stdout"] != raw["handoff"]["emitted_raw_utf8"]:
        die("handoff operation stdout differs from the bound emitted handoff")
    derived = {
        "raw_record_sha256": sha256_bytes(raw_payload),
        "awm_before_sha256": snapshots["awm_before"]["tree_sha256"],
        "awm_after_sha256": snapshots["awm_after_handoff"]["tree_sha256"],
        "workspace_before_sha256": snapshots["workspace_before"]["tree_sha256"],
        "workspace_after_sha256": snapshots["workspace_after"]["tree_sha256"],
        "installed_before_sha256": snapshots["installed_before"]["tree_sha256"],
        "installed_after_sha256": snapshots["installed_after"]["tree_sha256"],
        "operation_chain_head_sha256": raw["sequence"]["head_sha256"],
        "emitted_handoff_sha256": raw["handoff"]["emitted_sha256"],
        "emitted_handoff_size_bytes": raw["handoff"]["emitted_size_bytes"],
        "source_context_sha256": sha256_bytes(canonical_bytes(handoff_document["context"])),
        "neutral_envelope_sha256": sha256_bytes(neutral_payload),
        "neutral_envelope_size_bytes": len(neutral_payload),
        "maximum_bytes": MAX_CONTEXT_BYTES,
    }
    return binding, neutral_payload, derived


def audit_key(path: pathlib.Path, randomization_context_sha256: str) -> tuple[bytes, str]:
    secret = read_file(path, "audit key", mode=0o600)
    if len(secret) < MIN_AUDIT_KEY_BYTES or len(secret) > MAX_AUDIT_KEY_BYTES:
        die(f"audit key must contain {MIN_AUDIT_KEY_BYTES} to {MAX_AUDIT_KEY_BYTES} bytes")
    key = hmac.new(
        secret,
        b"MAINFRAME-AGENT-IMPACT-AWM-RECEIPT-KEY-V1\0"
        + randomization_context_sha256.encode("ascii"),
        hashlib.sha256,
    ).digest()
    key_id = sha256_bytes(b"MAINFRAME-AGENT-IMPACT-AWM-RECEIPT-KEY-ID-V1\0" + key)
    return key, key_id


def commitment(key: bytes, binding: dict[str, Any], label: str, payload: bytes) -> str:
    message = (
        b"MAINFRAME-AGENT-IMPACT-AWM-COMMITMENT-V1\0"
        + canonical_bytes(binding)
        + b"\0"
        + label.encode("ascii")
        + b"\0"
        + payload
    )
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def protocol_bindings() -> dict[str, str]:
    paths = {
        "fixture_harness_sha256": SUPPORT_PATH,
        "receipt_tool_sha256": pathlib.Path(__file__).resolve(),
        "raw_schema_sha256": PROTOCOL_ROOT / "awm-transition-raw.schema.json",
        "receipt_schema_sha256": PROTOCOL_ROOT / "awm-transition-receipt.schema.json",
        "public_schema_sha256": PROTOCOL_ROOT / "awm-transition-public.schema.json",
        "neutral_schema_sha256": PROTOCOL_ROOT / "neutral-continuation.schema.json",
    }
    result: dict[str, str] = {}
    for label, path in paths.items():
        result[label] = sha256_bytes(read_file(path, label.replace("_", " ")))
    return result


def public_runtime(runtime: dict[str, Any], observed: dict[str, Any]) -> dict[str, Any]:
    return {
        "mainframe_archive_sha256": runtime["mainframe_archive_sha256"],
        "installed_tree_algorithm": runtime["installed_tree_algorithm"],
        "installed_tree_sha256": runtime["installed_tree_sha256"],
        "pi_package": runtime["pi_package"],
        "pi_version": runtime["pi_version"],
        "pi_executable_sha256": runtime["pi_executable_sha256"],
        "pi_loader_sha256": runtime["pi_loader_sha256"],
        "pi_extension_sha256": runtime["pi_extension_sha256"],
        "transition_driver_sha256": runtime["transition_driver_sha256"],
        "node_executable_sha256": runtime["node_executable_sha256"],
        "node_version": str(runtime["node_version"]).removeprefix("v"),
        "bash_executable_sha256": observed["bash_executable_sha256"],
        "bash_version": observed["bash_version"],
    }


def build_artifacts(
    raw: dict[str, Any],
    raw_payload: bytes,
    preregistration: Any,
    preregistration_payload: bytes,
    assignments: Any,
    key_path: pathlib.Path,
) -> tuple[bytes, dict[str, Any], dict[str, Any]]:
    binding, neutral_payload, measurements = validate_raw(
        raw,
        raw_payload,
        preregistration,
        preregistration_payload,
        assignments,
    )
    key, key_id = audit_key(key_path, binding["randomization_context_sha256"])
    protocol = protocol_bindings()
    commitments = {
        "algorithm": COMMITMENT_ALGORITHM,
        "key_id_sha256": key_id,
        "raw_record_hmac_sha256": commitment(key, binding, "raw-record", raw_payload),
        "awm_before_hmac_sha256": commitment(key, binding, "awm-before", measurements["awm_before_sha256"].encode("ascii")),
        "awm_after_hmac_sha256": commitment(key, binding, "awm-after", measurements["awm_after_sha256"].encode("ascii")),
        "workspace_before_hmac_sha256": commitment(key, binding, "workspace-before", measurements["workspace_before_sha256"].encode("ascii")),
        "workspace_after_hmac_sha256": commitment(key, binding, "workspace-after", measurements["workspace_after_sha256"].encode("ascii")),
        "operation_chain_hmac_sha256": commitment(key, binding, "operation-chain", measurements["operation_chain_head_sha256"].encode("ascii")),
        "emitted_handoff_hmac_sha256": commitment(key, binding, "emitted-handoff", raw["handoff"]["emitted_raw_utf8"].encode("utf-8")),
        "neutral_envelope_hmac_sha256": commitment(key, binding, "neutral-envelope", neutral_payload),
    }
    receipt = {
        "schema_version": 1,
        "kind": RECEIPT_KIND,
        "claim_scope": CLAIM_SCOPE,
        "binding": binding,
        "runtime": public_runtime(raw["runtime_expected"], raw["runtime_observed"]),
        "protocol": protocol,
        "source": {"raw_record_sha256": measurements["raw_record_sha256"]},
        "private_measurements": measurements,
        "checks": CHECKS,
        "commitments": commitments,
        "scope_boundary": SCOPE_BOUNDARY,
        "non_claims": PUBLIC_NON_CLAIMS,
    }
    receipt_payload = canonical_bytes(receipt) + b"\n"
    public_commitments = dict(commitments)
    public_commitments["private_receipt_hmac_sha256"] = commitment(
        key,
        binding,
        "private-receipt",
        receipt_payload,
    )
    public = {
        "schema_version": 1,
        "kind": PUBLIC_KIND,
        "claim_scope": CLAIM_SCOPE,
        "binding": binding,
        "runtime": public_runtime(raw["runtime_expected"], raw["runtime_observed"]),
        "protocol": protocol,
        "publication_boundary": "post-scoring-and-assignment-reveal-only",
        "commitments": public_commitments,
        "measurements": {
            "operation_count": 3,
            "emitted_handoff_size_bytes": measurements["emitted_handoff_size_bytes"],
            "neutral_envelope_size_bytes": measurements["neutral_envelope_size_bytes"],
            "maximum_bytes": MAX_CONTEXT_BYTES,
        },
        "checks": CHECKS,
        "scope_boundary": SCOPE_BOUNDARY,
        "non_claims": PUBLIC_NON_CLAIMS,
        "privacy": {
            "raw_awm_content": "private-hmac-committed",
            "raw_handoff": "private-hmac-committed",
            "environment_values": "excluded",
            "absolute_paths": "excluded",
            "provider_credentials": "not-present",
        },
    }
    validate_public_privacy(public, raw)
    return neutral_payload, receipt, public


def validate_public_privacy(public: dict[str, Any], raw: dict[str, Any]) -> None:
    reject_absolute_strings(public, "public projection")
    encoded = canonical_bytes(public)
    sensitive = set(raw["paths"].values())
    sensitive.update(raw["environment"]["isolated_paths"].values())
    sensitive.update(
        (
            raw["handoff"]["session_id"],
            raw["handoff"]["handoff_id"],
            raw["handoff"]["persisted_path"],
            raw["fixture"]["checkpoint_value"],
            raw["request"]["path"],
            "mainframe-eval",
        )
    )
    for value in sensitive:
        if isinstance(value, str) and len(value) >= 6 and value.encode("utf-8") in encoded:
            die("public projection leaks private runtime or AWM content")
    forbidden_keys = {
        "path",
        "paths",
        "stdout",
        "stderr",
        "args",
        "environment",
        "session_id",
        "handoff_id",
        "emitted_raw_utf8",
        "persisted_raw_utf8",
        "checkpoint_value",
    }
    stack: list[Any] = [public]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if forbidden_keys.intersection(current):
                die("public projection contains a forbidden private field")
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
    if len(encoded) > MAX_PUBLIC_BYTES:
        die("public projection exceeds its size limit")


def require_output_absent(path: pathlib.Path, label: str, private_parent: bool) -> pathlib.Path:
    absolute = path.absolute()
    try:
        parent = SUPPORT.require_real_directory(absolute.parent, f"{label} parent")
    except SUPPORT.FixtureError as error:
        die(str(error))
    if private_parent and stat.S_IMODE(parent.lstat().st_mode) != 0o700:
        die(f"{label} parent mode must be exactly 0700")
    if not private_parent:
        metadata = parent.lstat()
        if metadata.st_uid != os.getuid() or (stat.S_IMODE(metadata.st_mode) & 0o022) != 0:
            die(f"{label} parent must be user-owned and not group/world writable")
    if absolute.exists() or absolute.is_symlink():
        die(f"refusing to overwrite existing {label}: {absolute}")
    if parent / absolute.name != absolute:
        die(f"{label} path must use a canonical existing parent")
    return absolute


def write_new(path: pathlib.Path, payload: bytes, mode: int, label: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags, mode)
    except FileExistsError:
        die(f"refusing to overwrite existing {label}: {path}")
    try:
        os.fchmod(descriptor, mode)
        cursor = 0
        while cursor < len(payload):
            cursor += os.write(descriptor, payload[cursor:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def load_inputs(args: argparse.Namespace) -> tuple[Any, bytes, Any, Any, bytes]:
    prereg, prereg_payload = load_json(pathlib.Path(args.preregistration), "preregistration")
    assignments, _ = load_json(pathlib.Path(args.assignments), "private assignments", mode=0o600)
    raw, raw_payload = load_json(pathlib.Path(args.raw_record), "private raw record", mode=0o600)
    return prereg, prereg_payload, assignments, raw, raw_payload


def prepare(args: argparse.Namespace) -> None:
    prereg, prereg_payload, assignments, raw, raw_payload = load_inputs(args)
    neutral_payload, receipt, public = build_artifacts(
        raw,
        raw_payload,
        prereg,
        prereg_payload,
        assignments,
        pathlib.Path(args.audit_key),
    )
    neutral_output = require_output_absent(pathlib.Path(args.neutral_output), "neutral envelope", True)
    receipt_output = require_output_absent(pathlib.Path(args.receipt_output), "private receipt", True)
    public_output = require_output_absent(pathlib.Path(args.public_output), "public projection", False)
    outputs = [
        (neutral_output, neutral_payload, 0o400, "neutral envelope"),
        (receipt_output, canonical_bytes(receipt) + b"\n", 0o600, "private receipt"),
        (public_output, canonical_bytes(public) + b"\n", 0o644, "public projection"),
    ]
    created: list[pathlib.Path] = []
    try:
        for path, payload, mode, label in outputs:
            write_new(path, payload, mode, label)
            created.append(path)
    except Exception:
        for path in created:
            try:
                path.unlink()
            except OSError:
                pass
        raise
    print(
        canonical_bytes(
            {
                "schema_version": 1,
                "kind": "mainframe-agent-impact-awm-transition-prepare-result",
                "claim_scope": CLAIM_SCOPE,
                "private_receipt_sha256": sha256_bytes(canonical_bytes(receipt) + b"\n"),
                "public_projection_sha256": sha256_bytes(canonical_bytes(public) + b"\n"),
                "real_provider_inference": "not-run",
                "live_agent_sessions": 0,
            }
        ).decode("utf-8")
    )


def verify(args: argparse.Namespace) -> None:
    prereg, prereg_payload, assignments, raw, raw_payload = load_inputs(args)
    expected_neutral, expected_receipt, expected_public = build_artifacts(
        raw,
        raw_payload,
        prereg,
        prereg_payload,
        assignments,
        pathlib.Path(args.audit_key),
    )
    observed_neutral = read_file(pathlib.Path(args.neutral), "neutral envelope", mode=0o400)
    observed_receipt, observed_receipt_payload = load_json(pathlib.Path(args.receipt), "private receipt", mode=0o600)
    observed_public, observed_public_payload = load_json(pathlib.Path(args.public_projection), "public projection", mode=0o644)
    expected_receipt_payload = canonical_bytes(expected_receipt) + b"\n"
    expected_public_payload = canonical_bytes(expected_public) + b"\n"
    if observed_neutral != expected_neutral:
        die("neutral envelope does not exactly reproduce from the private raw record")
    if observed_receipt != expected_receipt or observed_receipt_payload != expected_receipt_payload:
        die("private receipt does not exactly reproduce")
    if observed_public != expected_public or observed_public_payload != expected_public_payload:
        die("public projection does not exactly reproduce")
    print(
        canonical_bytes(
            {
                "schema_version": 1,
                "kind": "mainframe-agent-impact-awm-transition-verification",
                "claim_scope": CLAIM_SCOPE,
                "status": "private-bundle-and-public-projection-valid",
                "offline_only": True,
                "real_provider_inference": "not-run",
                "live_agent_sessions": 0,
            }
        ).decode("utf-8")
    )


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--preregistration", required=True)
    parser.add_argument("--assignments", required=True)
    parser.add_argument("--audit-key", required=True)
    parser.add_argument("--raw-record", required=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare or verify an offline synthetic Pi/AWM transition receipt."
    )
    subparsers = parser.add_subparsers(dest="action", required=True)
    prepare_parser = subparsers.add_parser("prepare", help="create new private/public receipt artifacts")
    add_common(prepare_parser)
    prepare_parser.add_argument("--neutral-output", required=True)
    prepare_parser.add_argument("--receipt-output", required=True)
    prepare_parser.add_argument("--public-output", required=True)
    verify_parser = subparsers.add_parser("verify", help="reproduce existing artifacts without execution")
    add_common(verify_parser)
    verify_parser.add_argument("--neutral", required=True)
    verify_parser.add_argument("--receipt", required=True)
    verify_parser.add_argument("--public-projection", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    try:
        if args.action == "prepare":
            prepare(args)
        else:
            verify(args)
    except (ReceiptError, SUPPORT.FixtureError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2) from None
    except (OSError, UnicodeError, ValueError) as error:
        print(f"ERROR: receipt infrastructure failure: {error}", file=sys.stderr)
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()

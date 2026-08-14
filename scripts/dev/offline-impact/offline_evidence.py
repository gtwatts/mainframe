#!/usr/bin/env python3
"""Build and verify deterministic, mechanism-only MAINFRAME evidence."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any, NoReturn, Sequence


TOOL_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOL_DIR.parents[2]
FIXTURE_PATH = TOOL_DIR / "fixtures.json"
SCHEMA_PATH = TOOL_DIR / "evidence.schema.json"
RUNTIME_INPUT_PATHS = ("VERSION", "lib/agent_safety.sh")
IMPLEMENTATION_PATHS = (
    "scripts/dev/offline-impact/build-evidence.py",
    "scripts/dev/offline-impact/verify-evidence.py",
    "scripts/dev/offline-impact/offline_evidence.py",
    "scripts/dev/native-host/safe-extract.py",
)
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_RUNTIME_INPUT_BYTES = 8 * 1024 * 1024
CASE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
RULE_RE = re.compile(r"^[a-z0-9-]+$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?$")
RISK_LEVELS = {"critical", "high", "medium", "low"}


class EvidenceError(RuntimeError):
    """Raised when an evidence input or artifact is invalid."""


def die(message: str) -> NoReturn:
    raise EvidenceError(message)


def require_real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die(f"{label} is unavailable: {path}: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        die(f"{label} must be a real directory: {path}")
    return path.resolve(strict=True)


def require_regular_file(
    path: Path,
    label: str,
    *,
    maximum_bytes: int = MAX_JSON_BYTES,
    allow_empty: bool = False,
) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die(f"{label} is unavailable: {path}: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die(f"{label} must be a regular, non-symlink file: {path}")
    if (not allow_empty and metadata.st_size == 0) or metadata.st_size > maximum_bytes:
        die(f"{label} has an unsupported size: {path} ({metadata.st_size} bytes)")
    return path


def load_json(path: Path, label: str) -> Any:
    path = require_regular_file(path, label)

    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                die(f"{label} contains duplicate key {key!r}: {path}")
            result[key] = value
        return result

    try:
        return json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        die(f"cannot parse {label} {path}: {error}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        die(f"cannot hash {path}: {error}")
    return digest.hexdigest()


def evidence_input_path(root: Path, relative_path: str) -> Path:
    pure_path = PurePosixPath(relative_path)
    if (
        pure_path.is_absolute()
        or ".." in pure_path.parts
        or str(pure_path) != relative_path
    ):
        die(f"internal evidence path is not canonical: {relative_path}")

    current = root
    for part in pure_path.parts:
        current = current / part
        if current.is_symlink():
            die(f"evidence input path contains a symbolic link: {relative_path}")
    return require_regular_file(
        current,
        f"evidence input {relative_path}",
        maximum_bytes=MAX_RUNTIME_INPUT_BYTES,
    )


def file_descriptor(root: Path, relative_path: str) -> dict[str, Any]:
    path = evidence_input_path(root, relative_path)
    return {
        "path": relative_path,
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def descriptor_set(
    root: Path, paths: Sequence[str]
) -> tuple[str, list[dict[str, Any]]]:
    descriptors = [file_descriptor(root, path) for path in sorted(paths)]
    digest = hashlib.sha256()
    for descriptor in descriptors:
        digest.update(descriptor["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(descriptor["size_bytes"]).encode("ascii"))
        digest.update(b"\0")
        digest.update(descriptor["sha256"].encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest(), descriptors


def snapshot_runtime_inputs(source_root: Path, destination: Path) -> None:
    """Copy the exact source bytes that will be hashed and classified."""

    destination = require_real_directory(destination, "runtime snapshot directory")
    for relative_path in RUNTIME_INPUT_PATHS:
        source = evidence_input_path(source_root, relative_path)
        try:
            before = source.stat()
            data = source.read_bytes()
            after = source.stat()
        except OSError as error:
            die(f"cannot snapshot selected source input {relative_path}: {error}")
        stable_fields_before = (
            before.st_dev,
            before.st_ino,
            before.st_size,
            before.st_mtime_ns,
        )
        stable_fields_after = (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
        )
        if stable_fields_before != stable_fields_after or len(data) != after.st_size:
            die(
                f"selected source input changed while it was being snapshotted: {relative_path}"
            )

        target = destination.joinpath(*PurePosixPath(relative_path).parts)
        target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(target, flags, 0o600)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            target.chmod(0o644)
        except OSError as error:
            die(f"cannot create runtime snapshot input {relative_path}: {error}")


def resolve_schema_reference(root: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ValueError(f"unsupported non-local schema reference: {reference}")
    current: Any = root
    for encoded_part in reference[2:].split("/"):
        part = encoded_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise ValueError(f"unresolvable schema reference: {reference}")
        current = current[part]
    if not isinstance(current, dict):
        raise ValueError(f"schema reference does not resolve to an object: {reference}")
    return current


def json_type_matches(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def validate_schema(
    schema: dict[str, Any],
    value: Any,
    path: str = "$",
    root: dict[str, Any] | None = None,
) -> None:
    """Validate the JSON Schema keywords used by evidence.schema.json."""

    root = schema if root is None else root
    if "$ref" in schema:
        validate_schema(
            resolve_schema_reference(root, schema["$ref"]), value, path, root
        )
        return

    alternatives = schema.get("anyOf")
    if alternatives is not None:
        failures: list[str] = []
        for alternative in alternatives:
            try:
                validate_schema(alternative, value, path, root)
                break
            except ValueError as error:
                failures.append(str(error))
        else:
            raise ValueError(
                f"{path}: no anyOf alternative matched ({'; '.join(failures)})"
            )

    if "const" in schema:
        expected = schema["const"]
        same_value = value == expected
        same_boolean_type = not (
            isinstance(value, bool) != isinstance(expected, bool)
            and isinstance(value, (bool, int))
            and isinstance(expected, (bool, int))
        )
        if not (same_value and same_boolean_type):
            raise ValueError(f"{path}: expected constant {expected!r}, got {value!r}")

    if "enum" in schema and not any(
        value == candidate and isinstance(value, bool) == isinstance(candidate, bool)
        for candidate in schema["enum"]
    ):
        raise ValueError(f"{path}: value {value!r} is not in the allowed enum")

    expected_type = schema.get("type")
    if expected_type is not None and not json_type_matches(value, expected_type):
        raise ValueError(
            f"{path}: expected {expected_type}, got {type(value).__name__}"
        )

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise ValueError(f"{path}: is less than minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            raise ValueError(f"{path}: is greater than maximum {schema['maximum']}")

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ValueError(f"{path}: is shorter than minLength")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise ValueError(f"{path}: is longer than maxLength")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise ValueError(f"{path}: does not match {schema['pattern']!r}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise ValueError(f"{path}: missing required keys {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise ValueError(f"{path}: unexpected keys {extras}")
        for key, child_schema in properties.items():
            if key in value:
                validate_schema(child_schema, value[key], f"{path}.{key}", root)

    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ValueError(f"{path}: has fewer than minItems entries")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise ValueError(f"{path}: has more than maxItems entries")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_schema(schema["items"], item, f"{path}[{index}]", root)


def validate_classification(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"risk", "rule", "blocked"}:
        die(f"{label} must contain exactly risk, rule, and blocked")
    risk = value["risk"]
    rule = value["rule"]
    blocked = value["blocked"]
    if not isinstance(risk, str) or risk not in RISK_LEVELS:
        die(f"{label}.risk is unsupported: {risk!r}")
    if not isinstance(rule, str) or RULE_RE.fullmatch(rule) is None or len(rule) > 128:
        die(f"{label}.rule is invalid: {rule!r}")
    if not isinstance(blocked, bool):
        die(f"{label}.blocked must be a boolean")
    expected_blocked = risk in {"critical", "high"}
    if blocked is not expected_blocked:
        die(f"{label}.blocked is inconsistent with the fixed high block tier")
    return {"risk": risk, "rule": rule, "blocked": blocked}


def validate_fixture(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, dict) or set(value) != {
        "schema_version",
        "block_tier",
        "cases",
    }:
        die("fixture root must contain exactly schema_version, block_tier, and cases")
    if value["schema_version"] != 1 or isinstance(value["schema_version"], bool):
        die("fixture schema_version must be integer 1")
    if value["block_tier"] != "high":
        die("fixture block_tier must be high")
    cases = value["cases"]
    if not isinstance(cases, list) or not 1 <= len(cases) <= 1000:
        die("fixture cases must contain between 1 and 1000 entries")

    normalized: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for index, case in enumerate(cases):
        label = f"fixture cases[{index}]"
        if not isinstance(case, dict) or set(case) != {"id", "command", "expected"}:
            die(f"{label} must contain exactly id, command, and expected")
        case_id = case["id"]
        command = case["command"]
        if (
            not isinstance(case_id, str)
            or CASE_ID_RE.fullmatch(case_id) is None
            or len(case_id) > 128
        ):
            die(f"{label}.id is invalid: {case_id!r}")
        if case_id in seen_ids:
            die(f"fixture case id is duplicated: {case_id}")
        seen_ids.add(case_id)
        if (
            not isinstance(command, str)
            or not 1 <= len(command) <= 4096
            or "\0" in command
            or "\n" in command
            or "\r" in command
        ):
            die(f"{label}.command must be a non-empty, single-line string")
        normalized.append(
            {
                "id": case_id,
                "command": command,
                "expected": validate_classification(
                    case["expected"], f"{label}.expected"
                ),
            }
        )
    return normalized


def resolve_bash(requested: str | None) -> tuple[Path, str]:
    candidate = requested or os.environ.get("MAINFRAME_BASH") or shutil.which("bash")
    if not candidate:
        die("Bash was not found; pass --bash with a Bash 4.4+ executable")
    if os.sep not in candidate:
        candidate = shutil.which(candidate) or candidate
    path = Path(candidate)
    try:
        resolved = path.resolve(strict=True)
        metadata = resolved.stat()
    except OSError as error:
        die(f"Bash executable is unavailable: {path}: {error}")
    if not stat.S_ISREG(metadata.st_mode) or not os.access(resolved, os.X_OK):
        die(f"Bash path is not an executable regular file: {resolved}")

    try:
        completed = subprocess.run(
            [str(resolved), "--version"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "LC_ALL": "C",
                "LANG": "C",
            },
        )
    except (OSError, subprocess.SubprocessError) as error:
        die(f"cannot identify Bash executable {resolved}: {error}")
    first_line = (
        completed.stdout.splitlines()[0] if completed.stdout.splitlines() else ""
    )
    version_match = re.match(r"^GNU bash, version ([0-9]+)\.([0-9]+)", first_line)
    if version_match is None:
        die(f"unrecognized Bash version output: {first_line!r}")
    version = (int(version_match.group(1)), int(version_match.group(2)))
    if version < (4, 4):
        die(f"Bash 4.4+ is required, found: {first_line}")
    return resolved, first_line


def classify_case(
    bash_path: Path,
    agent_safety_path: Path,
    command: str,
    scratch_root: Path,
) -> dict[str, Any]:
    shell_program = 'set -euo pipefail\nsource "$1"\nagent_gate_classify "$2"\n'
    environment = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(scratch_root / "home"),
        "LC_ALL": "C",
        "LANG": "C",
        "AGENT_GATE_BLOCK_TIER": "high",
        "AGENT_AUDIT_LOG": str(scratch_root / "agent-audit.jsonl"),
    }
    try:
        completed = subprocess.run(
            [
                str(bash_path),
                "--noprofile",
                "--norc",
                "-c",
                shell_program,
                "mainframe-offline-mechanism",
                str(agent_safety_path),
                command,
            ],
            cwd=scratch_root,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as error:
        die(f"classifier process failed to run: {error}")
    if completed.returncode != 0:
        die(
            "classifier process failed "
            f"with exit {completed.returncode}: {completed.stderr.strip() or '<no stderr>'}"
        )
    if completed.stderr:
        die(f"classifier emitted unexpected stderr: {completed.stderr.strip()}")
    try:
        observed = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        die(f"classifier emitted invalid JSON: {error}")
    return validate_classification(observed, "classifier output")


def verify_archive_checksum(archive: Path) -> dict[str, Any]:
    archive = require_regular_file(
        archive,
        "release archive",
        maximum_bytes=540 * 1024 * 1024,
    )
    sidecar = require_regular_file(
        Path(f"{archive}.sha256"),
        "release archive checksum sidecar",
        maximum_bytes=1024,
    )
    try:
        sidecar_text = sidecar.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as error:
        die(f"cannot read release archive checksum sidecar {sidecar}: {error}")
    lines = sidecar_text.splitlines()
    if len(lines) != 1:
        die("release archive checksum sidecar must contain exactly one line")
    match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", lines[0])
    if match is None or match.group(2) != archive.name:
        die("release archive checksum sidecar has an invalid record")
    actual_digest = sha256_file(archive)
    if not hmac.compare_digest(match.group(1), actual_digest):
        die("release archive checksum does not match the archive bytes")
    return {
        "path_basename": archive.name,
        "sha256": actual_digest,
        "checksum_sidecar_basename": sidecar.name,
        "checksum_verified": True,
    }


def extract_archive(archive: Path, destination: Path) -> None:
    helper = PROJECT_ROOT / "scripts/dev/native-host/safe-extract.py"
    require_regular_file(helper, "bounded archive extractor", maximum_bytes=1024 * 1024)
    try:
        completed = subprocess.run(
            [sys.executable, str(helper), str(archive), str(destination)],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "LC_ALL": "C",
                "LANG": "C",
            },
        )
    except (OSError, subprocess.SubprocessError) as error:
        die(f"bounded archive extraction failed to run: {error}")
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic"
        die(f"bounded archive extraction failed: {detail}")


def read_version(runtime_root: Path) -> str:
    version_path = require_regular_file(
        runtime_root / "VERSION",
        "runtime VERSION",
        maximum_bytes=256,
    )
    try:
        version = version_path.read_text(encoding="ascii").strip()
    except (OSError, UnicodeDecodeError) as error:
        die(f"cannot read runtime VERSION: {error}")
    if VERSION_RE.fullmatch(version) is None:
        die(f"runtime VERSION is invalid: {version!r}")
    return version


def validate_report_semantics(report: dict[str, Any]) -> None:
    rows = report["rows"]
    summary = report["summary"]
    execution = report["execution"]
    if len({row["id"] for row in rows}) != len(rows):
        die("evidence rows contain duplicate ids")
    if execution["case_count"] != len(rows) or summary["case_count"] != len(rows):
        die("evidence case counts do not match the raw rows")

    exact_matches = sum(row["expected"] == row["observed"] for row in rows)
    mismatches = len(rows) - exact_matches
    expected_blocks = sum(row["expected"]["blocked"] for row in rows)
    observed_blocks = sum(row["observed"]["blocked"] for row in rows)
    false_positives = sum(
        not row["expected"]["blocked"] and row["observed"]["blocked"] for row in rows
    )
    false_negatives = sum(
        row["expected"]["blocked"] and not row["observed"]["blocked"] for row in rows
    )
    expected_summary = {
        "case_count": len(rows),
        "exact_match_count": exact_matches,
        "mismatch_count": mismatches,
        "expected_block_count": expected_blocks,
        "observed_block_count": observed_blocks,
        "fixture_false_positive_count": false_positives,
        "fixture_false_negative_count": false_negatives,
    }
    if summary != expected_summary:
        die("evidence summary does not derive exactly from the raw rows")
    for row in rows:
        if row["exact_match"] is not (row["expected"] == row["observed"]):
            die(f"evidence exact_match is inconsistent for row {row['id']}")
        if row["executed"] is not False:
            die(f"evidence row incorrectly says its command was executed: {row['id']}")
    expected_result = "pass" if mismatches == 0 else "fail"
    if report["result"] != expected_result:
        die("evidence result is inconsistent with the raw rows")
    if (
        report["runtime"]["origin"] == "source-tree"
        and report["runtime"]["archive"] is not None
    ):
        die("source-tree evidence must not include archive metadata")
    if (
        report["runtime"]["origin"] == "release-archive"
        and report["runtime"]["archive"] is None
    ):
        die("release-archive evidence must include archive metadata")


def build_report_for_runtime(
    runtime_root: Path,
    origin: str,
    archive_metadata: dict[str, Any] | None,
    bash_path: Path,
    bash_version_line: str,
) -> dict[str, Any]:
    fixture = load_json(FIXTURE_PATH, "offline mechanism fixture")
    cases = validate_fixture(fixture)
    schema = load_json(SCHEMA_PATH, "offline mechanism evidence schema")
    if not isinstance(schema, dict):
        die("offline mechanism evidence schema root must be an object")

    source_digest, source_files = descriptor_set(runtime_root, RUNTIME_INPUT_PATHS)
    implementation_digest, implementation_files = descriptor_set(
        PROJECT_ROOT, IMPLEMENTATION_PATHS
    )
    fixture_descriptor = file_descriptor(
        PROJECT_ROOT, str(FIXTURE_PATH.relative_to(PROJECT_ROOT))
    )
    schema_descriptor = file_descriptor(
        PROJECT_ROOT, str(SCHEMA_PATH.relative_to(PROJECT_ROOT))
    )

    rows: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="mainframe-offline-classifier-") as scratch:
        scratch_root = Path(scratch)
        (scratch_root / "home").mkdir(mode=0o700)
        agent_safety_path = runtime_root / "lib/agent_safety.sh"
        for case in cases:
            observed = classify_case(
                bash_path, agent_safety_path, case["command"], scratch_root
            )
            rows.append(
                {
                    "id": case["id"],
                    "command": case["command"],
                    "expected": case["expected"],
                    "observed": observed,
                    "exact_match": case["expected"] == observed,
                    "executed": False,
                }
            )

    exact_matches = sum(row["exact_match"] for row in rows)
    false_positives = sum(
        not row["expected"]["blocked"] and row["observed"]["blocked"] for row in rows
    )
    false_negatives = sum(
        row["expected"]["blocked"] and not row["observed"]["blocked"] for row in rows
    )
    report: dict[str, Any] = {
        "schema_version": 1,
        "kind": "mainframe-offline-agent-mechanism-evidence",
        "claim_scope": "deterministic-policy-classification-fixtures-only",
        "protocol": {
            "fixture": fixture_descriptor,
            "schema": schema_descriptor,
            "implementation": {
                "digest_sha256": implementation_digest,
                "files": implementation_files,
            },
        },
        "runtime": {
            "origin": origin,
            "version": read_version(runtime_root),
            "evaluated_source_digest_sha256": source_digest,
            "evaluated_source_files": source_files,
            "archive": archive_metadata,
            "bash": {
                "executable_basename": bash_path.name,
                "version_line": bash_version_line,
            },
            "platform": {
                "system": platform.system() or "unknown",
                "release": platform.release() or "unknown",
                "machine": platform.machine() or "unknown",
            },
        },
        "execution": {
            "classifier_function": "agent_gate_classify",
            "block_tier": "high",
            "commands_executed": False,
            "case_count": len(rows),
        },
        "rows": rows,
        "summary": {
            "case_count": len(rows),
            "exact_match_count": exact_matches,
            "mismatch_count": len(rows) - exact_matches,
            "expected_block_count": sum(row["expected"]["blocked"] for row in rows),
            "observed_block_count": sum(row["observed"]["blocked"] for row in rows),
            "fixture_false_positive_count": false_positives,
            "fixture_false_negative_count": false_negatives,
        },
        "result": "pass" if exact_matches == len(rows) else "fail",
        "non_claims": {
            "real_provider_inference": "not-run",
            "agent_quality": "not-measured",
            "productivity": "not-measured",
            "comparative_agent_performance": "not-measured",
            "live_agent_sessions": 0,
        },
        "limitations": {
            "synthetic_fixture_corpus": True,
            "policy_classification_only": True,
            "command_execution_prevention": "not-tested",
            "os_sandbox_containment": "not-tested",
            "generalization_beyond_fixtures": "not-established",
        },
    }
    try:
        validate_schema(schema, report)
    except ValueError as error:
        die(f"generated report does not satisfy evidence schema: {error}")
    validate_report_semantics(report)
    return report


def create_report(
    *,
    source_root: Path | None,
    archive: Path | None,
    bash_request: str | None,
) -> dict[str, Any]:
    bash_path, bash_version_line = resolve_bash(bash_request)
    if source_root is not None and archive is not None:
        die("select either --source-root or --archive, not both")
    if archive is None:
        selected_root = require_real_directory(
            source_root or PROJECT_ROOT, "source root"
        )
        with tempfile.TemporaryDirectory(
            prefix="mainframe-offline-source-"
        ) as temporary:
            runtime_root = Path(temporary) / "runtime"
            runtime_root.mkdir(mode=0o700)
            snapshot_runtime_inputs(selected_root, runtime_root)
            return build_report_for_runtime(
                runtime_root,
                "source-tree",
                None,
                bash_path,
                bash_version_line,
            )

    if not archive.is_absolute():
        archive = Path.cwd() / archive
    archive_metadata = verify_archive_checksum(archive)
    with tempfile.TemporaryDirectory(prefix="mainframe-offline-archive-") as temporary:
        runtime_root = Path(temporary) / "runtime"
        runtime_root.mkdir(mode=0o700)
        extract_archive(archive, runtime_root)
        if not hmac.compare_digest(archive_metadata["sha256"], sha256_file(archive)):
            die("release archive changed while it was being extracted")
        return build_report_for_runtime(
            runtime_root,
            "release-archive",
            archive_metadata,
            bash_path,
            bash_version_line,
        )


def write_new_report(output: Path, report: dict[str, Any]) -> None:
    parent = require_real_directory(output.parent, "evidence output directory")
    target = parent / output.name
    if target.name in {"", ".", ".."}:
        die("evidence output must name a file")
    try:
        target.lstat()
    except FileNotFoundError:
        pass
    except OSError as error:
        die(f"cannot inspect evidence output path {target}: {error}")
    else:
        die(f"refusing to overwrite existing evidence output: {target}")

    payload = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode("utf-8")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(temporary, target, follow_symlinks=False)
        except FileExistsError:
            die(f"refusing to overwrite existing evidence output: {target}")
        except OSError as error:
            die(f"cannot publish evidence output {target}: {error}")
        target.chmod(0o644)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def first_difference(expected: Any, actual: Any, path: str = "$") -> str | None:
    if type(expected) is not type(actual):
        return (
            f"{path}: expected {type(expected).__name__}, found {type(actual).__name__}"
        )
    if isinstance(expected, dict):
        expected_keys = set(expected)
        actual_keys = set(actual)
        if expected_keys != actual_keys:
            return f"{path}: key sets differ"
        for key in sorted(expected):
            difference = first_difference(expected[key], actual[key], f"{path}.{key}")
            if difference:
                return difference
        return None
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return f"{path}: expected {len(expected)} entries, found {len(actual)}"
        for index, (expected_item, actual_item) in enumerate(zip(expected, actual)):
            difference = first_difference(
                expected_item, actual_item, f"{path}[{index}]"
            )
            if difference:
                return difference
        return None
    if expected != actual:
        return f"{path}: value differs"
    return None


def verify_report(
    evidence_path: Path,
    *,
    source_root: Path | None,
    archive: Path | None,
    bash_request: str | None,
) -> dict[str, Any]:
    evidence = load_json(evidence_path, "offline mechanism evidence")
    schema = load_json(SCHEMA_PATH, "offline mechanism evidence schema")
    if not isinstance(evidence, dict) or not isinstance(schema, dict):
        die("evidence and schema roots must be objects")
    try:
        validate_schema(schema, evidence)
    except ValueError as error:
        die(f"evidence does not satisfy the schema: {error}")
    validate_report_semantics(evidence)

    expected = create_report(
        source_root=source_root, archive=archive, bash_request=bash_request
    )
    difference = first_difference(expected, evidence)
    if difference:
        die(f"evidence does not match the selected current inputs: {difference}")
    if evidence["result"] != "pass":
        die("evidence matches its inputs but the fixture result is fail")
    return evidence


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build deterministic offline mechanism evidence; fixture commands are classified, never run."
    )
    parser.add_argument(
        "--output", required=True, type=Path, help="new evidence JSON path"
    )
    input_group = parser.add_mutually_exclusive_group()
    input_group.add_argument(
        "--source-root",
        type=Path,
        help="source tree to evaluate (default: the repository containing this tool)",
    )
    input_group.add_argument(
        "--archive",
        type=Path,
        help="release .tar.gz to checksum, safely extract, and evaluate",
    )
    parser.add_argument("--bash", dest="bash_request", help="Bash 4.4+ executable")
    return parser


def verify_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Schema-check and reproduce offline mechanism evidence from the selected exact inputs."
    )
    parser.add_argument(
        "--evidence", required=True, type=Path, help="evidence JSON to verify"
    )
    input_group = parser.add_mutually_exclusive_group()
    input_group.add_argument(
        "--source-root",
        type=Path,
        help="source tree expected by the evidence (default: current repository)",
    )
    input_group.add_argument(
        "--archive",
        type=Path,
        help="release .tar.gz expected by the evidence",
    )
    parser.add_argument("--bash", dest="bash_request", help="Bash 4.4+ executable")
    return parser


def build_main(argv: Sequence[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)
    try:
        report = create_report(
            source_root=args.source_root,
            archive=args.archive,
            bash_request=args.bash_request,
        )
        write_new_report(args.output, report)
    except EvidenceError as error:
        print(f"offline mechanism evidence error: {error}", file=sys.stderr)
        return 1
    print(
        f"wrote {args.output}: {report['result']} "
        f"({report['summary']['exact_match_count']}/{report['summary']['case_count']} exact rows)"
    )
    return 0 if report["result"] == "pass" else 1


def verify_main(argv: Sequence[str] | None = None) -> int:
    args = verify_argument_parser().parse_args(argv)
    try:
        report = verify_report(
            args.evidence,
            source_root=args.source_root,
            archive=args.archive,
            bash_request=args.bash_request,
        )
    except EvidenceError as error:
        print(f"offline mechanism evidence error: {error}", file=sys.stderr)
        return 1
    print(
        f"offline mechanism evidence verified: {report['result']} "
        f"({report['summary']['exact_match_count']}/{report['summary']['case_count']} exact rows)"
    )
    return 0

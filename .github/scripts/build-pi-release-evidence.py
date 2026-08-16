#!/usr/bin/env python3
"""Create or verify MAINFRAME's compact exact-candidate Pi evidence receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
from typing import Any, NoReturn


TREE_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
NODE_BINDING_ALGORITHM = "MAINFRAME-NATIVE-EXECUTABLE-BINDING-V1"
NODE_BINDING_KIND = "mainframe-pi-pre-test-node-binding"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
RUN_ID_RE = re.compile(r"^[1-9][0-9]*$")
NPM_INTEGRITY_RE = re.compile(r"^sha512-[A-Za-z0-9+/]+={0,2}$")
TEST_PATH_RE = re.compile(r"^tests/[A-Za-z0-9_.-]+\.bats$")
MAX_JSON_BYTES = 256 * 1024
MAX_TAP_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024
MAX_EXECUTABLE_BYTES = 512 * 1024 * 1024


class EvidenceError(ValueError):
    """A fail-closed evidence-contract violation."""


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid Pi release evidence: {message}")


def exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        raise EvidenceError(
            f"{label} keys differ: missing={sorted(expected - actual)} "
            f"extra={sorted(actual - expected)}"
        )
    return value


def read_regular_bytes(path: Path, maximum: int, label: str) -> bytes:
    descriptor = -1
    try:
        flags = os.O_RDONLY
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(path, flags)
        before = os.fstat(descriptor)
    except OSError as error:
        if descriptor >= 0:
            os.close(descriptor)
        raise EvidenceError(f"{label} is unavailable: {path}: {error}") from error
    try:
        if not stat.S_ISREG(before.st_mode):
            raise EvidenceError(f"{label} must be a regular non-symlink file: {path}")
        if before.st_nlink != 1:
            raise EvidenceError(f"{label} must not be hard-linked: {path}")
        if before.st_size > maximum:
            raise EvidenceError(f"{label} exceeds {maximum} bytes: {path}")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
    except OSError as error:
        raise EvidenceError(f"could not read {label}: {path}: {error}") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    if len(raw) > maximum:
        raise EvidenceError(f"{label} exceeds {maximum} bytes: {path}")
    if len(raw) != before.st_size:
        raise EvidenceError(f"{label} was truncated or is dataless: {path}")
    identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
    identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    if identity_before != identity_after or not stat.S_ISREG(after.st_mode) or after.st_nlink != 1:
        raise EvidenceError(f"{label} changed while it was read: {path}")
    return raw


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_file(path: Path, maximum: int, label: str) -> str:
    return sha256_bytes(read_regular_bytes(path, maximum, label))


def load_json(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    raw = read_regular_bytes(path, MAX_JSON_BYTES, label)

    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise EvidenceError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not strict UTF-8 JSON: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} root must be an object")
    return value, raw


def canonical_json(value: dict[str, Any]) -> bytes:
    return (
        json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def strict_equal(actual: Any, expected: Any) -> bool:
    """Compare JSON values without Python's bool/int equivalence."""
    if type(actual) is not type(expected):
        return False
    if isinstance(actual, dict):
        return set(actual) == set(expected) and all(
            strict_equal(actual[key], expected[key]) for key in actual
        )
    if isinstance(actual, list):
        return len(actual) == len(expected) and all(
            strict_equal(left, right) for left, right in zip(actual, expected)
        )
    return actual == expected


def validate_schema_definition(schema: Any, label: str = "schema") -> None:
    if not isinstance(schema, dict):
        raise EvidenceError(f"{label} must be an object")
    supported = {
        "$schema", "$id", "$defs", "$ref", "type", "additionalProperties",
        "required", "properties", "const", "pattern", "minLength", "minimum",
        "maximum", "items", "minItems", "maxItems", "uniqueItems", "anyOf", "allOf",
    }
    extras = set(schema) - supported
    if extras:
        raise EvidenceError(f"{label} uses unsupported keywords: {sorted(extras)}")
    for container in ("$defs", "properties"):
        if container in schema:
            if not isinstance(schema[container], dict):
                raise EvidenceError(f"{label}.{container} must be an object")
            for name, child in schema[container].items():
                validate_schema_definition(child, f"{label}.{container}.{name}")
    if "items" in schema:
        validate_schema_definition(schema["items"], f"{label}.items")
    for container in ("anyOf", "allOf"):
        if container in schema:
            if not isinstance(schema[container], list) or not schema[container]:
                raise EvidenceError(f"{label}.{container} must be a nonempty array")
            for index, child in enumerate(schema[container]):
                validate_schema_definition(child, f"{label}.{container}[{index}]")


def resolve_schema_ref(root: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise EvidenceError(f"unsupported non-local schema reference: {reference}")
    current: Any = root
    for encoded in reference[2:].split("/"):
        part = encoded.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise EvidenceError(f"unresolvable schema reference: {reference}")
        current = current[part]
    if not isinstance(current, dict):
        raise EvidenceError(f"schema reference is not an object: {reference}")
    return current


def validate_against_schema(
    schema: dict[str, Any], value: Any, root: dict[str, Any], path: str = "$"
) -> None:
    if "$ref" in schema:
        validate_against_schema(resolve_schema_ref(root, schema["$ref"]), value, root, path)
        return
    alternatives = schema.get("anyOf")
    if alternatives is not None:
        if not any(_schema_matches(item, value, root, path) for item in alternatives):
            raise EvidenceError(f"{path} does not match any allowed schema alternative")
    for item in schema.get("allOf", []):
        validate_against_schema(item, value, root, path)
    if "const" in schema and not strict_equal(value, schema["const"]):
        raise EvidenceError(f"{path} does not equal the required constant")
    expected_type = schema.get("type")
    type_matches = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }
    if expected_type is not None and not type_matches.get(expected_type, False):
        raise EvidenceError(f"{path} must be {expected_type}")
    if isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise EvidenceError(f"{path} is below its minimum")
        if "maximum" in schema and value > schema["maximum"]:
            raise EvidenceError(f"{path} is above its maximum")
    if isinstance(value, str):
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise EvidenceError(f"{path} does not match its schema pattern")
        if len(value) < schema.get("minLength", 0):
            raise EvidenceError(f"{path} is shorter than its schema minimum")
    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise EvidenceError(f"{path} is missing required keys: {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = set(value) - set(properties)
            if extras:
                raise EvidenceError(f"{path} has unexpected keys: {sorted(extras)}")
        for key, child in properties.items():
            if key in value:
                validate_against_schema(child, value[key], root, f"{path}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise EvidenceError(f"{path} has too few items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise EvidenceError(f"{path} has too many items")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(encoded) != len(set(encoded)):
                raise EvidenceError(f"{path} must contain unique items")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_against_schema(schema["items"], item, root, f"{path}[{index}]")


def _schema_matches(schema: dict[str, Any], value: Any, root: dict[str, Any], path: str) -> bool:
    try:
        validate_against_schema(schema, value, root, path)
        return True
    except EvidenceError:
        return False


def canonical_relative_path(value: str, label: str) -> PurePosixPath:
    candidate = PurePosixPath(value)
    if (
        not value
        or candidate.is_absolute()
        or candidate.as_posix() != value
        or any(part in ("", ".", "..") for part in candidate.parts)
    ):
        raise EvidenceError(f"{label} is not a canonical relative path: {value!r}")
    return candidate


def validate_contract(
    contract: dict[str, Any], repo_root: Path, mainframe_version: str
) -> tuple[list[str], list[dict[str, Any]], list[dict[str, Any]]]:
    exact_keys(
        contract,
        {
            "schema_version",
            "kind",
            "claim_scope",
            "test_tree_algorithm",
            "test_paths",
            "plan_per_run",
            "bats_core_commit",
            "platforms",
            "pi_versions",
        },
        "contract",
    )
    if contract["schema_version"] != 1:
        raise EvidenceError("contract schema_version must equal 1")
    if contract["kind"] != "mainframe-pi-exact-candidate-contract":
        raise EvidenceError("contract kind is unsupported")
    if contract["claim_scope"] != "exact-candidate-pi-integration-conformance-only":
        raise EvidenceError("contract claim_scope is unsupported")
    if contract["test_tree_algorithm"] != "MAINFRAME-PACKAGE-TREE-SHA256-V1":
        raise EvidenceError("contract test-tree algorithm is unsupported")
    if not isinstance(contract["plan_per_run"], int) or isinstance(
        contract["plan_per_run"], bool
    ) or contract["plan_per_run"] < 1:
        raise EvidenceError("contract plan_per_run must be a positive integer")
    if not isinstance(contract["bats_core_commit"], str) or not re.fullmatch(
        r"[0-9a-f]{40}", contract["bats_core_commit"]
    ):
        raise EvidenceError("contract Bats commit must be a 40-character Git SHA")

    test_paths = contract["test_paths"]
    if (
        not isinstance(test_paths, list)
        or not test_paths
        or any(not isinstance(path, str) or not TEST_PATH_RE.fullmatch(path) for path in test_paths)
        or len(test_paths) != len(set(test_paths))
    ):
        raise EvidenceError("contract test_paths must be nonempty, ordered, unique Bats paths")
    for relative in test_paths:
        canonical_relative_path(relative, "test path")
    test_cases = source_test_inventory(repo_root, test_paths)
    test_names = [case["name"] for case in test_cases]
    if len(test_cases) != contract["plan_per_run"]:
        raise EvidenceError(
            f"contract plan {contract['plan_per_run']} does not match "
            f"{len(test_cases)} strictly parsed source tests"
        )
    if len(test_names) != len(set(test_names)):
        raise EvidenceError("exact-candidate source test names must be unique")

    platforms = contract["platforms"]
    if not isinstance(platforms, list) or len(platforms) != 3:
        raise EvidenceError("contract must contain exactly three platforms")
    platform_keys = {"id", "os", "arch", "system_libc"}
    for index, platform in enumerate(platforms):
        exact_keys(platform, platform_keys, f"platform[{index}]")
        expected_id = f"{platform['os']}-{platform['arch']}-{platform['system_libc']}"
        if platform["id"] != expected_id or not re.fullmatch(
            r"[A-Za-z0-9_.-]+", platform["id"]
        ):
            raise EvidenceError(f"platform[{index}] identity is not canonical")
    if platforms != sorted(platforms, key=lambda item: item["id"]):
        raise EvidenceError("contract platforms must be sorted by id")
    if len({platform["id"] for platform in platforms}) != len(platforms):
        raise EvidenceError("contract platform ids must be unique")

    pi_versions = contract["pi_versions"]
    if not isinstance(pi_versions, list) or len(pi_versions) != 2:
        raise EvidenceError("contract must contain exactly two Pi versions")
    pi_keys = {
        "id",
        "package",
        "version",
        "npm_integrity",
        "profile",
        "expected_skips",
        "expected_skip",
        "limitations",
    }
    for index, pi_record in enumerate(pi_versions):
        exact_keys(pi_record, pi_keys, f"pi_versions[{index}]")
        if not isinstance(pi_record["id"], str) or not re.fullmatch(
            r"[A-Za-z0-9_.-]+", pi_record["id"]
        ):
            raise EvidenceError(f"pi_versions[{index}] id is invalid")
        if not isinstance(pi_record["package"], str) or not re.fullmatch(
            r"@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", pi_record["package"]
        ):
            raise EvidenceError(f"pi_versions[{index}] package is invalid")
        if not isinstance(pi_record["version"], str) or not VERSION_RE.fullmatch(
            pi_record["version"]
        ):
            raise EvidenceError(f"pi_versions[{index}] version is invalid")
        if not isinstance(pi_record["npm_integrity"], str) or not NPM_INTEGRITY_RE.fullmatch(
            pi_record["npm_integrity"]
        ):
            raise EvidenceError(f"pi_versions[{index}] npm_integrity is invalid")
        if not isinstance(pi_record["profile"], str) or not re.fullmatch(
            r"[a-z0-9-]+", pi_record["profile"]
        ):
            raise EvidenceError(f"pi_versions[{index}] profile is invalid")
        if not isinstance(pi_record["expected_skips"], int) or isinstance(
            pi_record["expected_skips"], bool
        ) or pi_record["expected_skips"] < 0:
            raise EvidenceError(f"pi_versions[{index}] expected_skips is invalid")
        expected_skip = pi_record["expected_skip"]
        if pi_record["expected_skips"] == 0:
            if expected_skip is not None:
                raise EvidenceError(f"pi_versions[{index}] expected_skip must be null")
        elif pi_record["expected_skips"] == 1:
            exact_keys(expected_skip, {"test", "reason"}, f"pi_versions[{index}].expected_skip")
            if any(not isinstance(expected_skip[key], str) or not expected_skip[key] for key in ("test", "reason")):
                raise EvidenceError(f"pi_versions[{index}] expected_skip is invalid")
            if test_names.count(expected_skip["test"]) != 1:
                raise EvidenceError(
                    f"pi_versions[{index}] expected skipped test must exist exactly once"
                )
        else:
            raise EvidenceError(f"pi_versions[{index}] supports at most one expected skip")
        if not isinstance(pi_record["limitations"], list) or any(
            not isinstance(item, str) or not item for item in pi_record["limitations"]
        ):
            raise EvidenceError(f"pi_versions[{index}] limitations are invalid")
    if pi_versions != sorted(pi_versions, key=lambda item: item["id"]):
        raise EvidenceError("contract Pi versions must be sorted by id")
    if len({record["id"] for record in pi_versions}) != len(pi_versions):
        raise EvidenceError("contract Pi ids must be unique")

    compatibility, _raw = load_json(
        repo_root / "config/pi-compatibility.json", "Pi compatibility manifest"
    )
    if compatibility.get("mainframe_version") != mainframe_version:
        raise EvidenceError("Pi compatibility manifest Mainframe version does not match")
    certifications = compatibility.get("certifications")
    if not isinstance(certifications, list):
        raise EvidenceError("Pi compatibility manifest certifications are invalid")
    for pi_record in pi_versions:
        matches = [
            record
            for record in certifications
            if isinstance(record, dict)
            and record.get("package") == pi_record["package"]
            and record.get("version") == pi_record["version"]
            and record.get("npm_integrity") == pi_record["npm_integrity"]
            and record.get("profile") == pi_record["profile"]
            and record.get("mainframe_version") == mainframe_version
        ]
        if len(matches) != 1:
            raise EvidenceError(
                f"contract Pi identity is not unique in compatibility manifest: {pi_record['id']}"
            )
        selected = matches[0]
        if selected.get("support") not in {"certified", "limited"}:
            raise EvidenceError(f"compatibility support is invalid: {pi_record['id']}")
        if not isinstance(selected.get("id"), str) or not re.fullmatch(
            r"[A-Za-z0-9_.-]+", selected["id"]
        ):
            raise EvidenceError(f"compatibility record id is invalid: {pi_record['id']}")
        declared_platforms = selected.get("platforms")
        if (
            not isinstance(declared_platforms, list)
            or not declared_platforms
            or any(
                not isinstance(platform, str)
                or platform not in {item["id"] for item in platforms}
                for platform in declared_platforms
            )
            or len(declared_platforms) != len(set(declared_platforms))
        ):
            raise EvidenceError(f"compatibility platforms are invalid: {pi_record['id']}")
        pi_record["manifest_record"] = selected
    return test_paths, platforms, pi_versions


def source_test_inventory(repo_root: Path, test_paths: list[str]) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    for relative in test_paths:
        raw = read_regular_bytes(repo_root / relative, MAX_TAP_BYTES, "test source")
        text = raw.decode("utf-8")
        for line in text.splitlines():
            match = re.match(r'^\s*@test\s+"([^"]+)"\s*\{\s*$', line)
            if match:
                cases.append(
                    {"number": len(cases) + 1, "source": relative, "name": match.group(1)}
                )
    return cases


def source_test_names(repo_root: Path, test_paths: list[str]) -> list[str]:
    return [case["name"] for case in source_test_inventory(repo_root, test_paths)]


def test_tree_sha256(repo_root: Path, test_paths: list[str]) -> str:
    directories: set[str] = set()
    files: list[tuple[str, bytes]] = []
    for relative in test_paths:
        posix = canonical_relative_path(relative, "test path")
        for parent in posix.parents:
            if parent.as_posix() != ".":
                directories.add(parent.as_posix())
        files.append(
            (
                relative,
                read_regular_bytes(repo_root / relative, MAX_TAP_BYTES, "test source"),
            )
        )
    digest = hashlib.sha256(TREE_DOMAIN)
    entries: list[tuple[str, str, bytes | None]] = [
        (relative, "D", None) for relative in directories
    ] + [(relative, "F", raw) for relative, raw in files]
    for relative, kind, raw in sorted(entries):
        encoded = relative.encode("utf-8")
        if b"\0" in encoded:
            raise EvidenceError(f"test path contains NUL: {relative!r}")
        if kind == "D":
            digest.update(b"D\0" + encoded + b"\0")
        else:
            assert raw is not None
            digest.update(b"F\0" + encoded + b"\0")
            digest.update(str(len(raw)).encode("ascii") + b"\0")
            digest.update(raw)
    return digest.hexdigest()


def read_digest_binding(path: Path, label: str) -> tuple[str, str]:
    raw = read_regular_bytes(path, 128, label)
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as error:
        raise EvidenceError(f"{label} is not ASCII: {path}") from error
    if not text.endswith("\n") or text.count("\n") != 1:
        raise EvidenceError(f"{label} must contain one digest line: {path}")
    digest = text[:-1]
    if not SHA256_RE.fullmatch(digest):
        raise EvidenceError(f"{label} is not a lowercase SHA-256 digest: {path}")
    return digest, sha256_bytes(raw)


def parse_tap(
    path: Path,
    expected_names: list[str],
    expected_skip: dict[str, str] | None,
) -> dict[str, Any]:
    expected_plan = len(expected_names)
    raw = read_regular_bytes(path, MAX_TAP_BYTES, "Pi TAP artifact")
    if b"\xef\xbb\xbf" in raw or any(
        (byte < 32 and byte not in (9, 10, 13)) or byte == 127 for byte in raw
    ):
        raise EvidenceError(
            f"Pi TAP artifact contains a BOM or unsafe control character: {path.name}"
        )
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise EvidenceError(f"Pi TAP artifact is not UTF-8: {path.name}: {error}") from error
    if any(
        ((ord(character) < 32 and character not in "\t\n\r") or
         0x7F <= ord(character) <= 0x9F)
        for character in text
    ):
        raise EvidenceError(
            f"Pi TAP artifact contains an unsafe Unicode control character: {path.name}"
        )
    lines = text.splitlines()
    plans: list[int] = []
    ok_records: list[tuple[int, str]] = []
    not_ok = 0
    skip_details: list[dict[str, Any]] = []
    for line in lines:
        stripped = line.lstrip()
        if re.match(r"^Bail out!", stripped, re.IGNORECASE) or re.search(
            r"#\s*TODO(?:\s|$)", line, re.IGNORECASE
        ):
            raise EvidenceError(f"Pi TAP contains a bailout or TODO directive: {path.name}")
        if re.match(r"^1\.\.", stripped):
            plan_match = re.fullmatch(r"1\.\.(\d+)", line)
            if plan_match is None:
                raise EvidenceError(f"Pi TAP contains a malformed or indented plan: {path.name}")
            plans.append(int(plan_match.group(1)))
            continue
        if re.match(r"^not ok(?:\s|$)", stripped, re.IGNORECASE):
            if line != stripped or re.fullmatch(r"not ok\s+[0-9]+(?:\s+.*)?", line) is None:
                raise EvidenceError(f"Pi TAP contains a malformed failure record: {path.name}")
            not_ok += 1
            continue
        if re.match(r"^ok(?:\s|$)", stripped, re.IGNORECASE) and line != stripped:
            raise EvidenceError(f"Pi TAP contains an indented result record: {path.name}")
        match = re.fullmatch(r"ok\s+([0-9]+)\s+(.+)", line)
        if match:
            number = int(match.group(1))
            description = match.group(2)
            skip_match = re.fullmatch(r"(.+?)\s+#\s+skip\s+(.+)", description, re.IGNORECASE)
            if skip_match:
                test_name = skip_match.group(1)
                skip_details.append(
                    {"number": number, "test": test_name, "reason": skip_match.group(2)}
                )
            else:
                test_name = description
            ok_records.append((number, test_name))
            continue
        if re.match(r"^ok(?:\s|$)", stripped, re.IGNORECASE):
            raise EvidenceError(f"Pi TAP contains a malformed result record: {path.name}")
    if plans != [expected_plan]:
        raise EvidenceError(
            f"Pi TAP artifact must contain one 1..{expected_plan} plan: {path.name}"
        )
    if not_ok:
        raise EvidenceError(f"Pi TAP artifact contains {not_ok} failing tests: {path.name}")
    expected_records = list(enumerate(expected_names, start=1))
    if ok_records != expected_records:
        raise EvidenceError(f"Pi TAP test names or numbers are incomplete or out of order: {path.name}")
    expected_skip_details: list[dict[str, Any]] = []
    if expected_skip is not None:
        expected_number = expected_names.index(expected_skip["test"]) + 1
        expected_skip_details = [
            {"number": expected_number, "test": expected_skip["test"], "reason": expected_skip["reason"]}
        ]
    if skip_details != expected_skip_details:
        raise EvidenceError(
            f"Pi TAP skip details do not match the compatibility contract: {path.name}"
        )
    return {
        "plan": expected_plan,
        "ok": len(ok_records),
        "executed": len(ok_records) - len(skip_details),
        "not_ok": 0,
        "skipped": len(skip_details),
        "skip_details": skip_details,
    }


def expected_artifact_names(
    platforms: list[dict[str, Any]], pi_versions: list[dict[str, Any]]
) -> set[str]:
    names: set[str] = set()
    for pi_record in pi_versions:
        for platform in platforms:
            suffix = f"{pi_record['id']}-{platform['id']}"
            names.update(
                {
                    f"pi-candidate-{suffix}.sha256",
                    f"pi-candidate-{suffix}.tap",
                    f"pi-tests-{suffix}.sha256",
                    f"pi-cell-{suffix}.json",
                    f"pi-node-pre-{suffix}.json",
                    f"pi-runtime-pre-{suffix}.json",
                }
            )
    return names


def validate_artifact_inventory(artifacts_dir: Path, expected: set[str]) -> None:
    try:
        metadata = artifacts_dir.lstat()
        entries = list(artifacts_dir.iterdir())
    except OSError as error:
        raise EvidenceError(f"could not inspect Pi artifact directory: {error}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise EvidenceError("Pi artifact directory must be a real directory")
    actual = {entry.name for entry in entries}
    if actual != expected or len(entries) != len(expected):
        raise EvidenceError(
            f"Pi artifact inventory differs: missing={sorted(expected - actual)} "
            f"extra={sorted(actual - expected)}"
        )
    for entry in entries:
        entry_metadata = entry.lstat()
        if stat.S_ISLNK(entry_metadata.st_mode) or not stat.S_ISREG(entry_metadata.st_mode):
            raise EvidenceError(f"Pi artifact must be a regular non-symlink file: {entry.name}")


def validate_common_arguments(arguments: argparse.Namespace, repo_root: Path) -> None:
    if not VERSION_RE.fullmatch(arguments.version):
        raise EvidenceError("version must be semantic X.Y.Z")
    if arguments.tag != f"v{arguments.version}":
        raise EvidenceError("tag must equal vVERSION")
    if not REPOSITORY_RE.fullmatch(arguments.repository):
        raise EvidenceError("repository must be owner/name")
    if not GIT_SHA_RE.fullmatch(arguments.tag_ref_sha):
        raise EvidenceError("tag-ref-sha must be a 40- or 64-character lowercase Git SHA")
    if not GIT_SHA_RE.fullmatch(arguments.tag_commit_sha):
        raise EvidenceError("tag-commit-sha must be a 40- or 64-character lowercase Git SHA")
    if not RUN_ID_RE.fullmatch(arguments.workflow_run_id):
        raise EvidenceError("workflow-run-id must be a positive decimal identifier")
    if arguments.workflow_run_attempt < 1:
        raise EvidenceError("workflow-run-attempt must be positive")
    version_bytes = read_regular_bytes(repo_root / "VERSION", 128, "VERSION")
    try:
        checked_version = version_bytes.decode("ascii").strip()
    except UnicodeDecodeError as error:
        raise EvidenceError("VERSION is not ASCII") from error
    if checked_version != arguments.version:
        raise EvidenceError("VERSION does not match the requested evidence version")
    if arguments.archive.name != f"mainframe-{arguments.version}.tar.gz":
        raise EvidenceError("archive basename does not match VERSION")
    try:
        head = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        tag_ref = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", f"refs/tags/{arguments.tag}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        tag_commit = subprocess.run(
            [
                "git", "-C", str(repo_root), "rev-parse",
                f"refs/tags/{arguments.tag}^{{commit}}",
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise EvidenceError("source repository HEAD/tag identity cannot be resolved") from error
    if head != arguments.tag_commit_sha or tag_commit != arguments.tag_commit_sha:
        raise EvidenceError("source repository HEAD/tag commit does not match tag-commit-sha")
    if tag_ref != arguments.tag_ref_sha:
        raise EvidenceError("source repository tag ref does not match tag-ref-sha")


def validate_source_inputs(
    arguments: argparse.Namespace, repo_root: Path, test_paths: list[str]
) -> None:
    expected_paths = {
        "contract": repo_root / ".github/pi-evidence-contract.json",
        "schema": repo_root / ".github/schemas/pi-release-evidence.schema.json",
        "cell_schema": repo_root / ".github/schemas/pi-cell-evidence.schema.json",
        "generator": repo_root / ".github/scripts/build-pi-release-evidence.py",
    }
    actual_paths = {
        "contract": arguments.contract.resolve(strict=True),
        "schema": arguments.schema.resolve(strict=True),
        "cell_schema": arguments.cell_schema.resolve(strict=True),
        "generator": Path(__file__).resolve(strict=True),
    }
    for name, expected in expected_paths.items():
        if actual_paths[name] != expected.resolve(strict=True):
            raise EvidenceError(f"{name} must be the canonical source-repository file")
    relative_paths = [
        "VERSION",
        "config/pi-compatibility.json",
        ".github/pi-evidence-contract.json",
        ".github/schemas/pi-release-evidence.schema.json",
        ".github/schemas/pi-cell-evidence.schema.json",
        ".github/scripts/build-pi-release-evidence.py",
        ".github/scripts/build-pi-cell-evidence.py",
        "scripts/dev/native-host/validate-native-executable.py",
        *test_paths,
    ]
    try:
        subprocess.run(
            ["git", "-C", str(repo_root), "ls-files", "--error-unmatch", *relative_paths],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["git", "-C", str(repo_root), "diff", "--quiet", "HEAD", "--", *relative_paths],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise EvidenceError("source evidence inputs are untracked or differ from tag commit") from error


def expected_cell_source_files(repo_root: Path, test_paths: list[str]) -> list[dict[str, str]]:
    relative_paths = sorted(
        [
            "VERSION",
            ".github/pi-evidence-contract.json",
            ".github/schemas/pi-cell-evidence.schema.json",
            ".github/scripts/build-pi-cell-evidence.py",
            "config/pi-compatibility.json",
            "scripts/dev/native-host/validate-native-executable.py",
            *test_paths,
        ]
    )
    return [
        {
            "path": relative,
            "sha256": sha256_file(
                repo_root / relative, MAX_TAP_BYTES, "Pi cell source input"
            ),
        }
        for relative in relative_paths
    ]


def validate_node_executable(value: Any, label: str) -> dict[str, Any]:
    executable = exact_keys(
        value,
        {
            "architectures", "basename", "format", "mode", "sha256",
            "size_bytes", "type",
        },
        label,
    )
    architectures = executable["architectures"]
    if (
        not isinstance(architectures, list)
        or not architectures
        or architectures != sorted(set(architectures))
        or any(item not in {"arm64", "x86_64"} for item in architectures)
        or executable["basename"] != "node"
        or executable["format"] not in {"elf", "mach-o", "mach-o-universal"}
        or not isinstance(executable["mode"], str)
        or re.fullmatch(r"0[0-7]{3}", executable["mode"]) is None
        or not isinstance(executable["sha256"], str)
        or SHA256_RE.fullmatch(executable["sha256"]) is None
        or not isinstance(executable["size_bytes"], int)
        or isinstance(executable["size_bytes"], bool)
        or not 20 <= executable["size_bytes"] <= MAX_EXECUTABLE_BYTES
        or executable["type"] != "file"
    ):
        raise EvidenceError(f"{label} is invalid")
    return executable


def validate_node_observation(
    value: Any, platform: dict[str, Any], label: str
) -> dict[str, Any]:
    observation = exact_keys(
        value, {"expected_arch", "observed_process_arch", "executable"}, label
    )
    if (
        observation["expected_arch"] != platform["arch"]
        or observation["observed_process_arch"] != platform["arch"]
    ):
        raise EvidenceError(f"{label} architecture does not match the matrix platform")
    executable = validate_node_executable(observation["executable"], f"{label}.executable")
    if platform["arch"] not in executable["architectures"]:
        raise EvidenceError(f"{label} executable omits the matrix architecture")
    if platform["os"] == "Darwin" and not executable["format"].startswith("mach-o"):
        raise EvidenceError(f"{label} executable is not Mach-O")
    if platform["os"] == "Linux" and executable["format"] != "elf":
        raise EvidenceError(f"{label} executable is not ELF")
    return observation


def validate_cell_node_runtime(
    cell: dict[str, Any], platform: dict[str, Any], suffix: str, raw_path: Path
) -> dict[str, Any]:
    proof = exact_keys(
        cell.get("node_runtime"),
        {
            "algorithm", "pre_test_binding", "pre_test", "post_test",
            "executable_unchanged", "process_arch_unchanged", "result",
        },
        f"Pi cell Node runtime {suffix}",
    )
    binding = exact_keys(
        proof["pre_test_binding"], {"name", "file_sha256"},
        f"Pi cell Node pre-test binding {suffix}",
    )
    snapshot, snapshot_raw = load_json(raw_path, "pre-test Pi Node binding")
    expected_name = f"pi-node-pre-{suffix}.json"
    pre_test = validate_node_observation(
        proof["pre_test"], platform, f"Pi cell Node pre-test observation {suffix}"
    )
    post_test = validate_node_observation(
        proof["post_test"], platform, f"Pi cell Node post-test observation {suffix}"
    )
    expected_snapshot = {
        "schema_version": 1,
        "kind": NODE_BINDING_KIND,
        **pre_test,
    }
    if (
        snapshot_raw != canonical_json(snapshot)
        or not strict_equal(snapshot, expected_snapshot)
        or proof["algorithm"] != NODE_BINDING_ALGORITHM
        or binding["name"] != expected_name
        or binding["file_sha256"] != sha256_bytes(snapshot_raw)
        or not strict_equal(pre_test, post_test)
        or proof["executable_unchanged"] is not True
        or proof["process_arch_unchanged"] is not True
        or proof["result"] != "unchanged"
    ):
        raise EvidenceError(f"Pi cell Node pre/post proof does not match: {suffix}")
    return proof


def validate_cell_receipt(
    cell_path: Path,
    arguments: argparse.Namespace,
    contract: dict[str, Any],
    contract_raw: bytes,
    test_paths: list[str],
    pi_record: dict[str, Any],
    platform: dict[str, Any],
    repo_root: Path,
    archive_sha: str,
    archive_size: int,
    source_tree_sha: str,
    raw_artifacts: dict[str, Path],
) -> tuple[dict[str, Any], str]:
    cell, cell_raw = load_json(cell_path, "Pi cell evidence receipt")
    if cell_raw != canonical_json(cell):
        raise EvidenceError(f"Pi cell receipt is not canonical JSON: {cell_path.name}")
    cell_schema, _cell_schema_raw = load_json(arguments.cell_schema, "Pi cell schema")
    validate_schema_definition(cell_schema, "cell schema")
    validate_against_schema(cell_schema, cell, cell_schema)

    suffix = f"{pi_record['id']}-{platform['id']}"
    expected_cell_id = f"{pi_record['id']}@{platform['id']}"
    if cell.get("schema_version") != 1 or cell.get("kind") != (
        "mainframe-pi-exact-candidate-cell-evidence"
    ) or cell.get("claim_scope") != (
        "exact-candidate-single-cell-pi-integration-conformance-only"
    ) or cell.get("cell_id") != expected_cell_id:
        raise EvidenceError(f"Pi cell receipt identity does not match: {cell_path.name}")
    expected_mainframe = {
        "version": arguments.version,
        "archive_name": arguments.archive.name,
        "archive_size": archive_size,
        "archive_sha256": archive_sha,
    }
    if not strict_equal(cell.get("mainframe"), expected_mainframe):
        raise EvidenceError(f"Pi cell archive identity does not match: {cell_path.name}")
    expected_source = {
        "repository": arguments.repository,
        "ref": f"refs/tags/{arguments.tag}",
        "ref_sha": arguments.tag_ref_sha,
        "commit_sha": arguments.tag_commit_sha,
        "workflow_run_id": arguments.workflow_run_id,
        "workflow_run_attempt": arguments.workflow_run_attempt,
        "binding_mode": "git-head-clean-tracked-files",
        "files": expected_cell_source_files(repo_root, test_paths),
    }
    if not strict_equal(cell.get("source"), expected_source):
        raise EvidenceError(f"Pi cell source identity does not match: {cell_path.name}")

    host = exact_keys(
        cell.get("host"),
        {"observation_mode", "platform", "commands", "test_override"},
        f"Pi cell host {cell_path.name}",
    )
    if not strict_equal(host["platform"], platform):
        raise EvidenceError(f"Pi cell platform does not match: {cell_path.name}")
    commands = exact_keys(
        host["commands"],
        {"uname_system", "uname_machine", "getconf_long_bit", "getconf_gnu_libc_version"},
        f"Pi cell host commands {cell_path.name}",
    )
    if host["observation_mode"] == "test-override":
        if (
            os.environ.get("MAINFRAME_PI_CELL_TEST_MODE") != "1"
            or host["test_override"] != platform["id"]
            or any(value is not None for value in commands.values())
        ):
            raise EvidenceError(f"Pi cell test override is not authorized: {cell_path.name}")
    else:
        if host["observation_mode"] != "native" or host["test_override"] is not None:
            raise EvidenceError(f"Pi cell must contain a native host observation: {cell_path.name}")
        normalized_arch = {
            "arm64": "arm64",
            "aarch64": "arm64",
            "x86_64": "x86_64",
            "amd64": "x86_64",
        }.get(commands["uname_machine"])
        if (
            commands["uname_system"] != platform["os"]
            or normalized_arch != platform["arch"]
            or commands["getconf_long_bit"] != "64"
        ):
            raise EvidenceError(f"Pi cell observed host commands do not match: {cell_path.name}")
        libc_value = commands["getconf_gnu_libc_version"]
        if platform["os"] == "Linux":
            if not isinstance(libc_value, str) or re.fullmatch(
                r"glibc [0-9]+(?:\.[0-9]+)+", libc_value
            ) is None:
                raise EvidenceError(f"Pi cell did not observe glibc: {cell_path.name}")
        elif libc_value is not None:
            raise EvidenceError(f"Darwin Pi cell must not claim libc: {cell_path.name}")

    node_runtime = validate_cell_node_runtime(
        cell, platform, suffix, raw_artifacts["node_binding"]
    )

    pi = exact_keys(
        cell.get("pi"),
        {
            "id", "package", "version", "profile", "npm_integrity",
            "package_json_name", "package_json_sha256", "package_tree_sha256",
            "runtime_root_name", "runtime_tree_sha256", "runtime_entry", "integrity_input",
        },
        f"Pi cell package {cell_path.name}",
    )
    expected_pi = {
        "id": pi_record["id"],
        "package": pi_record["package"],
        "version": pi_record["version"],
        "profile": pi_record["profile"],
        "npm_integrity": pi_record["npm_integrity"],
    }
    if any(pi.get(key) != value for key, value in expected_pi.items()):
        raise EvidenceError(f"Pi cell package identity does not match: {cell_path.name}")
    if (
        pi.get("package_json_name") != "package.json"
        or pi.get("runtime_root_name") != "node_modules"
        or pi.get("runtime_entry") != ".bin/pi"
        or any(
            not isinstance(pi.get(key), str) or SHA256_RE.fullmatch(pi[key]) is None
            for key in (
                "package_json_sha256", "package_tree_sha256", "runtime_tree_sha256"
            )
        )
    ):
        raise EvidenceError(f"Pi cell package manifest digest is invalid: {cell_path.name}")
    integrity_input = exact_keys(
        pi.get("integrity_input"), {"name", "file_sha256", "binding_value"},
        f"Pi cell integrity input {cell_path.name}",
    )
    integrity_name = f"pi-npm-integrity-{suffix}.txt"
    expected_integrity_hash = sha256_bytes(
        f"{pi_record['npm_integrity']}\n".encode("ascii")
    )
    if not strict_equal(
        integrity_input,
        {
            "name": integrity_name,
            "file_sha256": expected_integrity_hash,
            "binding_value": pi_record["npm_integrity"],
        },
    ):
        raise EvidenceError(f"Pi cell npm integrity binding does not match: {cell_path.name}")

    runtime_proof = exact_keys(
        cell.get("runtime_proof"),
        {
            "algorithm", "pre_test_snapshot", "pre_test", "post_test",
            "package_unchanged", "runtime_unchanged", "result",
        },
        f"Pi cell runtime proof {cell_path.name}",
    )
    snapshot_binding = exact_keys(
        runtime_proof["pre_test_snapshot"], {"name", "file_sha256"},
        f"Pi cell pre-test runtime snapshot {cell_path.name}",
    )
    pre_test = exact_keys(
        runtime_proof["pre_test"], {"package_tree_sha256", "runtime_tree_sha256"},
        f"Pi cell pre-test runtime digests {cell_path.name}",
    )
    post_test = exact_keys(
        runtime_proof["post_test"], {"package_tree_sha256", "runtime_tree_sha256"},
        f"Pi cell post-test runtime digests {cell_path.name}",
    )
    runtime_snapshot, runtime_snapshot_raw = load_json(
        raw_artifacts["runtime_snapshot"], "pre-test Pi runtime snapshot"
    )
    if runtime_snapshot_raw != canonical_json(runtime_snapshot):
        raise EvidenceError(
            f"pre-test Pi runtime snapshot is not canonical: {cell_path.name}"
        )
    expected_snapshot = {
        "schema_version": 1,
        "kind": "mainframe-pi-pre-test-runtime-snapshot",
        "algorithm": "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1",
        "package": pi_record["package"],
        "version": pi_record["version"],
        "runtime_root_name": "node_modules",
        "runtime_entry": ".bin/pi",
        "package_tree_sha256": pre_test["package_tree_sha256"],
        "runtime_tree_sha256": pre_test["runtime_tree_sha256"],
    }
    expected_snapshot_name = f"pi-runtime-pre-{suffix}.json"
    if (
        runtime_proof["algorithm"] != "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1"
        or snapshot_binding.get("name") != expected_snapshot_name
        or snapshot_binding.get("file_sha256") != sha256_bytes(runtime_snapshot_raw)
        or not strict_equal(runtime_snapshot, expected_snapshot)
        or not strict_equal(pre_test, post_test)
        or post_test.get("package_tree_sha256") != pi["package_tree_sha256"]
        or post_test.get("runtime_tree_sha256") != pi["runtime_tree_sha256"]
        or runtime_proof["package_unchanged"] is not True
        or runtime_proof["runtime_unchanged"] is not True
        or runtime_proof["result"] != "unchanged"
    ):
        raise EvidenceError(f"Pi cell pre/post runtime proof does not match: {cell_path.name}")

    manifest_record = pi_record["manifest_record"]
    declared = platform["id"] in manifest_record["platforms"]
    support = manifest_record["support"] if declared else "unverified"
    expected_compatibility = {
        "manifest_record_id": manifest_record["id"],
        "platform_declared": declared,
        "support": support,
        "runtime_state": {
            "certified": "READY",
            "limited": "LIMITED",
            "unverified": "COMPATIBILITY_UNVERIFIED",
        }[support],
    }
    if not strict_equal(cell.get("compatibility"), expected_compatibility):
        raise EvidenceError(f"Pi cell compatibility state does not match: {cell_path.name}")

    config_raw = read_regular_bytes(
        repo_root / "config/pi-compatibility.json", MAX_JSON_BYTES,
        "Pi compatibility manifest",
    )
    expected_producer = {
        "contract_sha256": sha256_bytes(contract_raw),
        "config_sha256": sha256_bytes(config_raw),
        "schema_sha256": sha256_file(
            arguments.cell_schema, MAX_JSON_BYTES, "Pi cell schema"
        ),
        "generator_sha256": sha256_file(
            repo_root / ".github/scripts/build-pi-cell-evidence.py",
            MAX_JSON_BYTES,
            "Pi cell generator",
        ),
    }
    if not strict_equal(cell.get("producer"), expected_producer):
        raise EvidenceError(f"Pi cell producer identity does not match: {cell_path.name}")
    expected_tests = {
        "canonicalization": contract["test_tree_algorithm"],
        "paths": list(test_paths),
        "source_tree_sha256": source_tree_sha,
        "plan": contract["plan_per_run"],
        "bats_core_commit": contract["bats_core_commit"],
        "cases": source_test_inventory(repo_root, test_paths),
    }
    if not strict_equal(cell.get("tests"), expected_tests):
        raise EvidenceError(f"Pi cell test-source identity does not match: {cell_path.name}")

    parsed_result = parse_tap(
        raw_artifacts["tap"], source_test_names(repo_root, test_paths),
        pi_record["expected_skip"],
    )
    expected_result = {"status": "pass", **parsed_result}
    if not strict_equal(cell.get("result"), expected_result):
        raise EvidenceError(f"Pi cell TAP result does not match: {cell_path.name}")
    artifacts = exact_keys(
        cell.get("artifacts"), {"archive_binding", "test_binding", "tap"},
        f"Pi cell raw artifacts {cell_path.name}",
    )
    expected_artifacts = {
        "archive_binding": {
            "name": raw_artifacts["archive_binding"].name,
            "file_sha256": sha256_file(
                raw_artifacts["archive_binding"], 128, "archive-binding artifact"
            ),
            "binding_value": archive_sha,
        },
        "test_binding": {
            "name": raw_artifacts["test_binding"].name,
            "file_sha256": sha256_file(
                raw_artifacts["test_binding"], 128, "test-binding artifact"
            ),
            "binding_value": source_tree_sha,
        },
        "tap": {
            "name": raw_artifacts["tap"].name,
            "file_sha256": sha256_file(
                raw_artifacts["tap"], MAX_TAP_BYTES, "Pi TAP artifact"
            ),
            "binding_value": None,
        },
    }
    if not strict_equal(artifacts, expected_artifacts):
        raise EvidenceError(f"Pi cell raw artifact binding does not match: {cell_path.name}")
    expected_limitations = [
        "This receipt proves one exact-candidate Pi integration conformance cell only; it does not prove live user activation, general agent safety, agent quality, or adoption.",
        "A passing cell does not upgrade compatibility support; support and runtime state are copied from the bound compatibility manifest for this platform.",
        "Package identity, npm integrity, candidate/test bindings, and TAP are represented by bounded values and SHA-256 digests, not by an installed-user attestation.",
    ]
    if not strict_equal(cell.get("limitations"), expected_limitations):
        raise EvidenceError(f"Pi cell limitations do not match: {cell_path.name}")
    return cell, sha256_bytes(cell_raw)


def build_receipt(
    arguments: argparse.Namespace,
    contract: dict[str, Any],
    contract_raw: bytes,
    test_paths: list[str],
    platforms: list[dict[str, Any]],
    pi_versions: list[dict[str, Any]],
    repo_root: Path,
) -> dict[str, Any]:
    archive_raw = read_regular_bytes(arguments.archive, MAX_ARCHIVE_BYTES, "release archive")
    archive_sha = sha256_bytes(archive_raw)
    source_tree_sha = test_tree_sha256(repo_root, test_paths)
    expected_names = source_test_names(repo_root, test_paths)
    if len(expected_names) != contract["plan_per_run"]:
        raise EvidenceError("source test-name inventory does not match the contract plan")
    expected_artifacts = expected_artifact_names(platforms, pi_versions)
    validate_artifact_inventory(arguments.artifacts_dir, expected_artifacts)
    rows: list[dict[str, Any]] = []
    for pi_record in pi_versions:
        for platform in platforms:
            suffix = f"{pi_record['id']}-{platform['id']}"
            archive_name = f"pi-candidate-{suffix}.sha256"
            test_name = f"pi-tests-{suffix}.sha256"
            tap_name = f"pi-candidate-{suffix}.tap"
            cell_name = f"pi-cell-{suffix}.json"
            runtime_snapshot_name = f"pi-runtime-pre-{suffix}.json"
            node_binding_name = f"pi-node-pre-{suffix}.json"
            bound_archive, archive_binding_sha = read_digest_binding(
                arguments.artifacts_dir / archive_name, "archive-binding artifact"
            )
            if bound_archive != archive_sha:
                raise EvidenceError(f"archive binding does not match release archive: {archive_name}")
            bound_tests, test_binding_sha = read_digest_binding(
                arguments.artifacts_dir / test_name, "test-binding artifact"
            )
            if bound_tests != source_tree_sha:
                raise EvidenceError(f"test binding does not match source tree: {test_name}")
            tap_path = arguments.artifacts_dir / tap_name
            result = parse_tap(tap_path, expected_names, pi_record["expected_skip"])
            cell_path = arguments.artifacts_dir / cell_name
            cell, cell_sha = validate_cell_receipt(
                cell_path,
                arguments,
                contract,
                contract_raw,
                test_paths,
                pi_record,
                platform,
                repo_root,
                archive_sha,
                len(archive_raw),
                source_tree_sha,
                {
                    "archive_binding": arguments.artifacts_dir / archive_name,
                    "test_binding": arguments.artifacts_dir / test_name,
                    "tap": tap_path,
                    "node_binding": arguments.artifacts_dir / node_binding_name,
                    "runtime_snapshot": arguments.artifacts_dir / runtime_snapshot_name,
                },
            )
            manifest_record = pi_record["manifest_record"]
            platform_declared = platform["id"] in manifest_record["platforms"]
            support = manifest_record["support"] if platform_declared else "unverified"
            runtime_state = {
                "certified": "READY",
                "limited": "LIMITED",
                "unverified": "COMPATIBILITY_UNVERIFIED",
            }[support]
            rows.append(
                {
                    "id": f"{pi_record['id']}@{platform['id']}",
                    "pi": {
                        "id": pi_record["id"],
                        "package": pi_record["package"],
                        "version": pi_record["version"],
                        "npm_integrity": pi_record["npm_integrity"],
                        "profile": pi_record["profile"],
                    },
                    "platform": dict(platform),
                    "observation": {
                        "mode": cell["host"]["observation_mode"],
                        "commands": dict(cell["host"]["commands"]),
                        "package_json_sha256": cell["pi"]["package_json_sha256"],
                        "package_tree_sha256": cell["pi"]["package_tree_sha256"],
                        "runtime_tree_sha256": cell["pi"]["runtime_tree_sha256"],
                        "runtime_proof": dict(cell["runtime_proof"]),
                        "node_runtime": dict(cell["node_runtime"]),
                        "npm_integrity_input_sha256": cell["pi"]["integrity_input"][
                            "file_sha256"
                        ],
                        "source_files_sha256": sha256_bytes(
                            canonical_json({"files": cell["source"]["files"]})
                        ),
                    },
                    "compatibility": {
                        "manifest_record_id": manifest_record["id"],
                        "platform_declared": platform_declared,
                        "support": support,
                        "runtime_state": runtime_state,
                    },
                    "artifacts": {
                        "archive_binding": {
                            "name": archive_name,
                            "file_sha256": archive_binding_sha,
                        },
                        "test_binding": {
                            "name": test_name,
                            "file_sha256": test_binding_sha,
                        },
                        "tap": {
                            "name": tap_name,
                            "file_sha256": sha256_file(
                                tap_path, MAX_TAP_BYTES, "Pi TAP artifact"
                            ),
                        },
                        "cell_receipt": {
                            "name": cell_name,
                            "file_sha256": cell_sha,
                        },
                        "runtime_snapshot": {
                            "name": runtime_snapshot_name,
                            "file_sha256": sha256_file(
                                arguments.artifacts_dir / runtime_snapshot_name,
                                MAX_JSON_BYTES,
                                "pre-test Pi runtime snapshot",
                            ),
                        },
                        "node_binding": {
                            "name": node_binding_name,
                            "file_sha256": sha256_file(
                                arguments.artifacts_dir / node_binding_name,
                                MAX_JSON_BYTES,
                                "pre-test Pi Node binding",
                            ),
                        },
                    },
                    "result": {"status": "pass", **result},
                    "limitations": list(pi_record["limitations"]),
                }
            )
    rows.sort(key=lambda row: row["id"])
    return {
        "schema_version": 1,
        "kind": "mainframe-pi-exact-candidate-evidence",
        "claim_scope": contract["claim_scope"],
        "mainframe": {
            "version": arguments.version,
            "archive_name": arguments.archive.name,
            "archive_size": len(archive_raw),
            "archive_sha256": archive_sha,
        },
        "source": {
            "repository": arguments.repository,
            "tag": arguments.tag,
            "tag_ref_sha": arguments.tag_ref_sha,
            "tag_commit_sha": arguments.tag_commit_sha,
            "workflow_run_id": arguments.workflow_run_id,
            "workflow_run_attempt": arguments.workflow_run_attempt,
        },
        "producer": {
            "contract_sha256": sha256_bytes(contract_raw),
            "config_sha256": sha256_file(
                repo_root / "config/pi-compatibility.json",
                MAX_JSON_BYTES,
                "Pi compatibility manifest",
            ),
            "generator_sha256": sha256_file(
                Path(__file__).resolve(strict=True), MAX_JSON_BYTES, "evidence generator"
            ),
            "schema_sha256": sha256_file(
                arguments.schema, MAX_JSON_BYTES, "evidence schema"
            ),
            "cell_generator_sha256": sha256_file(
                repo_root / ".github/scripts/build-pi-cell-evidence.py",
                MAX_JSON_BYTES,
                "Pi cell generator",
            ),
            "cell_schema_sha256": sha256_file(
                arguments.cell_schema, MAX_JSON_BYTES, "Pi cell schema"
            ),
        },
        "tests": {
            "canonicalization": contract["test_tree_algorithm"],
            "paths": list(test_paths),
            "source_tree_sha256": source_tree_sha,
            "plan_per_run": contract["plan_per_run"],
            "bats_core_commit": contract["bats_core_commit"],
            "cases": source_test_inventory(repo_root, test_paths),
        },
        "matrix": rows,
        "summary": {
            "matrix_rows": len(rows),
            "passed_rows": len(rows),
            "failed_rows": 0,
            "planned_tests": sum(row["result"]["plan"] for row in rows),
            "ok": sum(row["result"]["ok"] for row in rows),
            "executed": sum(row["result"]["executed"] for row in rows),
            "not_ok": 0,
            "skipped": sum(row["result"]["skipped"] for row in rows),
        },
        "limitations": [
            "This receipt proves exact-candidate Pi integration conformance on the listed matrix; it does not prove live user activation, general agent safety, agent quality, or adoption.",
            "Raw TAP remains a short-lived workflow artifact and is represented here by SHA-256 and a bounded result summary.",
        ],
    }


def validate_receipt(
    receipt: dict[str, Any],
    arguments: argparse.Namespace,
    contract: dict[str, Any],
    contract_raw: bytes,
    test_paths: list[str],
    platforms: list[dict[str, Any]],
    pi_versions: list[dict[str, Any]],
    repo_root: Path,
) -> None:
    top_keys = {
        "schema_version",
        "kind",
        "claim_scope",
        "mainframe",
        "source",
        "producer",
        "tests",
        "matrix",
        "summary",
        "limitations",
    }
    exact_keys(receipt, top_keys, "receipt")
    if receipt["schema_version"] != 1 or receipt["kind"] != "mainframe-pi-exact-candidate-evidence":
        raise EvidenceError("receipt identity is unsupported")
    if receipt["claim_scope"] != contract["claim_scope"]:
        raise EvidenceError("receipt claim scope does not match contract")
    mainframe = exact_keys(
        receipt["mainframe"],
        {"version", "archive_name", "archive_size", "archive_sha256"},
        "mainframe",
    )
    archive_raw = read_regular_bytes(arguments.archive, MAX_ARCHIVE_BYTES, "release archive")
    archive_sha = sha256_bytes(archive_raw)
    if not strict_equal(mainframe, {
        "version": arguments.version,
        "archive_name": arguments.archive.name,
        "archive_size": len(archive_raw),
        "archive_sha256": archive_sha,
    }):
        raise EvidenceError("receipt release archive identity does not match")
    source = exact_keys(
        receipt["source"],
        {
            "repository",
            "tag",
            "tag_ref_sha",
            "tag_commit_sha",
            "workflow_run_id",
            "workflow_run_attempt",
        },
        "source",
    )
    expected_source = {
        "repository": arguments.repository,
        "tag": arguments.tag,
        "tag_ref_sha": arguments.tag_ref_sha,
        "tag_commit_sha": arguments.tag_commit_sha,
        "workflow_run_id": arguments.workflow_run_id,
        "workflow_run_attempt": arguments.workflow_run_attempt,
    }
    if not strict_equal(source, expected_source):
        raise EvidenceError("receipt source identity does not match")
    producer = exact_keys(
        receipt["producer"],
        {
            "contract_sha256", "config_sha256", "generator_sha256", "schema_sha256",
            "cell_generator_sha256", "cell_schema_sha256",
        },
        "producer",
    )
    expected_producer = {
        "contract_sha256": sha256_bytes(contract_raw),
        "config_sha256": sha256_file(
            repo_root / "config/pi-compatibility.json",
            MAX_JSON_BYTES,
            "Pi compatibility manifest",
        ),
        "generator_sha256": sha256_file(
            Path(__file__).resolve(strict=True), MAX_JSON_BYTES, "evidence generator"
        ),
        "schema_sha256": sha256_file(arguments.schema, MAX_JSON_BYTES, "evidence schema"),
        "cell_generator_sha256": sha256_file(
            repo_root / ".github/scripts/build-pi-cell-evidence.py",
            MAX_JSON_BYTES,
            "Pi cell generator",
        ),
        "cell_schema_sha256": sha256_file(
            arguments.cell_schema, MAX_JSON_BYTES, "Pi cell schema"
        ),
    }
    if not strict_equal(producer, expected_producer):
        raise EvidenceError("receipt producer identity does not match")
    tests = exact_keys(
        receipt["tests"],
        {
            "canonicalization",
            "paths",
            "source_tree_sha256",
            "plan_per_run",
            "bats_core_commit",
            "cases",
        },
        "tests",
    )
    expected_tests = {
        "canonicalization": contract["test_tree_algorithm"],
        "paths": test_paths,
        "source_tree_sha256": test_tree_sha256(repo_root, test_paths),
        "plan_per_run": contract["plan_per_run"],
        "bats_core_commit": contract["bats_core_commit"],
        "cases": source_test_inventory(repo_root, test_paths),
    }
    if not strict_equal(tests, expected_tests):
        raise EvidenceError("receipt test-source identity does not match")

    expected_rows = len(platforms) * len(pi_versions)
    matrix = receipt["matrix"]
    if not isinstance(matrix, list) or len(matrix) != expected_rows:
        raise EvidenceError(f"receipt matrix must contain exactly {expected_rows} rows")
    expected_pairs = {
        f"{pi_record['id']}@{platform['id']}": (pi_record, platform)
        for pi_record in pi_versions
        for platform in platforms
    }
    ids: list[str] = []
    for index, row in enumerate(matrix):
        exact_keys(
            row,
            {
                "id", "pi", "platform", "observation", "compatibility", "artifacts",
                "result", "limitations",
            },
            f"matrix[{index}]",
        )
        row_id = row["id"]
        if row_id not in expected_pairs:
            raise EvidenceError(f"matrix[{index}] has unexpected id {row_id!r}")
        ids.append(row_id)
        pi_record, platform = expected_pairs[row_id]
        expected_pi = {
            "id": pi_record["id"],
            "package": pi_record["package"],
            "version": pi_record["version"],
            "npm_integrity": pi_record["npm_integrity"],
            "profile": pi_record["profile"],
        }
        exact_keys(row["pi"], set(expected_pi), f"matrix[{index}].pi")
        if not strict_equal(row["pi"], expected_pi) or not strict_equal(row["platform"], platform):
            raise EvidenceError(f"matrix[{index}] Pi/platform identity does not match")
        exact_keys(
            row["platform"], {"id", "os", "arch", "system_libc"}, f"matrix[{index}].platform"
        )
        observation = exact_keys(
            row["observation"],
            {
                "mode", "commands", "package_json_sha256",
                "package_tree_sha256", "runtime_tree_sha256",
                "runtime_proof", "node_runtime", "npm_integrity_input_sha256",
                "source_files_sha256",
            },
            f"matrix[{index}].observation",
        )
        commands = exact_keys(
            observation["commands"],
            {
                "uname_system", "uname_machine", "getconf_long_bit",
                "getconf_gnu_libc_version",
            },
            f"matrix[{index}].observation.commands",
        )
        if observation["mode"] == "test-override":
            if (
                os.environ.get("MAINFRAME_PI_CELL_TEST_MODE") != "1"
                or any(value is not None for value in commands.values())
            ):
                raise EvidenceError(f"matrix[{index}] test override is not authorized")
        else:
            normalized_arch = {
                "arm64": "arm64",
                "aarch64": "arm64",
                "x86_64": "x86_64",
                "amd64": "x86_64",
            }.get(commands["uname_machine"])
            if (
                observation["mode"] != "native"
                or commands["uname_system"] != platform["os"]
                or normalized_arch != platform["arch"]
                or commands["getconf_long_bit"] != "64"
            ):
                raise EvidenceError(f"matrix[{index}] native host observation does not match")
            libc_value = commands["getconf_gnu_libc_version"]
            if platform["os"] == "Linux":
                if not isinstance(libc_value, str) or re.fullmatch(
                    r"glibc [0-9]+(?:\.[0-9]+)+", libc_value
                ) is None:
                    raise EvidenceError(f"matrix[{index}] glibc observation does not match")
            elif libc_value is not None:
                raise EvidenceError(f"matrix[{index}] Darwin observation must have null libc")
        for digest_key in (
            "package_json_sha256", "package_tree_sha256", "runtime_tree_sha256",
            "npm_integrity_input_sha256", "source_files_sha256"
        ):
            if not isinstance(observation[digest_key], str) or SHA256_RE.fullmatch(
                observation[digest_key]
            ) is None:
                raise EvidenceError(f"matrix[{index}] observation digest is invalid")
        node_runtime = exact_keys(
            observation["node_runtime"],
            {
                "algorithm", "pre_test_binding", "pre_test", "post_test",
                "executable_unchanged", "process_arch_unchanged", "result",
            },
            f"matrix[{index}].observation.node_runtime",
        )
        node_binding = exact_keys(
            node_runtime["pre_test_binding"], {"name", "file_sha256"},
            f"matrix[{index}].observation.node_runtime.pre_test_binding",
        )
        node_pre = validate_node_observation(
            node_runtime["pre_test"], platform,
            f"matrix[{index}].observation.node_runtime.pre_test",
        )
        node_post = validate_node_observation(
            node_runtime["post_test"], platform,
            f"matrix[{index}].observation.node_runtime.post_test",
        )
        node_suffix = f"{pi_record['id']}-{platform['id']}"
        expected_node_snapshot = {
            "schema_version": 1,
            "kind": NODE_BINDING_KIND,
            **node_pre,
        }
        if (
            node_runtime["algorithm"] != NODE_BINDING_ALGORITHM
            or node_binding["name"] != f"pi-node-pre-{node_suffix}.json"
            or node_binding["file_sha256"] != sha256_bytes(
                canonical_json(expected_node_snapshot)
            )
            or not strict_equal(node_pre, node_post)
            or node_runtime["executable_unchanged"] is not True
            or node_runtime["process_arch_unchanged"] is not True
            or node_runtime["result"] != "unchanged"
        ):
            raise EvidenceError(f"matrix[{index}] Node runtime proof does not match")
        runtime_proof = exact_keys(
            observation["runtime_proof"],
            {
                "algorithm", "pre_test_snapshot", "pre_test", "post_test",
                "package_unchanged", "runtime_unchanged", "result",
            },
            f"matrix[{index}].observation.runtime_proof",
        )
        pre_test = exact_keys(
            runtime_proof["pre_test"],
            {"package_tree_sha256", "runtime_tree_sha256"},
            f"matrix[{index}].observation.runtime_proof.pre_test",
        )
        post_test = exact_keys(
            runtime_proof["post_test"],
            {"package_tree_sha256", "runtime_tree_sha256"},
            f"matrix[{index}].observation.runtime_proof.post_test",
        )
        snapshot_binding = exact_keys(
            runtime_proof["pre_test_snapshot"], {"name", "file_sha256"},
            f"matrix[{index}].observation.runtime_proof.pre_test_snapshot",
        )
        suffix = f"{pi_record['id']}-{platform['id']}"
        if (
            runtime_proof["algorithm"] != "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1"
            or snapshot_binding["name"] != f"pi-runtime-pre-{suffix}.json"
            or not isinstance(snapshot_binding["file_sha256"], str)
            or SHA256_RE.fullmatch(snapshot_binding["file_sha256"]) is None
            or not strict_equal(pre_test, post_test)
            or post_test["package_tree_sha256"] != observation["package_tree_sha256"]
            or post_test["runtime_tree_sha256"] != observation["runtime_tree_sha256"]
            or runtime_proof["package_unchanged"] is not True
            or runtime_proof["runtime_unchanged"] is not True
            or runtime_proof["result"] != "unchanged"
        ):
            raise EvidenceError(f"matrix[{index}] runtime proof does not match")
        for digest_key in ("package_tree_sha256", "runtime_tree_sha256"):
            if not isinstance(pre_test[digest_key], str) or SHA256_RE.fullmatch(
                pre_test[digest_key]
            ) is None:
                raise EvidenceError(f"matrix[{index}] runtime proof digest is invalid")
        expected_runtime_snapshot = {
            "schema_version": 1,
            "kind": "mainframe-pi-pre-test-runtime-snapshot",
            "algorithm": "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1",
            "package": pi_record["package"],
            "version": pi_record["version"],
            "runtime_root_name": "node_modules",
            "runtime_entry": ".bin/pi",
            "package_tree_sha256": pre_test["package_tree_sha256"],
            "runtime_tree_sha256": pre_test["runtime_tree_sha256"],
        }
        if snapshot_binding["file_sha256"] != sha256_bytes(
            canonical_json(expected_runtime_snapshot)
        ):
            raise EvidenceError(
                f"matrix[{index}] runtime snapshot digest is not derivable from its proof"
            )
        expected_integrity_hash = sha256_bytes(
            f"{pi_record['npm_integrity']}\n".encode("ascii")
        )
        expected_source_files_hash = sha256_bytes(
            canonical_json({"files": expected_cell_source_files(repo_root, test_paths)})
        )
        if (
            observation["npm_integrity_input_sha256"] != expected_integrity_hash
            or observation["source_files_sha256"] != expected_source_files_hash
        ):
            raise EvidenceError(f"matrix[{index}] observation bindings do not match")
        manifest_record = pi_record["manifest_record"]
        platform_declared = platform["id"] in manifest_record["platforms"]
        support = manifest_record["support"] if platform_declared else "unverified"
        expected_compatibility = {
            "manifest_record_id": manifest_record["id"],
            "platform_declared": platform_declared,
            "support": support,
            "runtime_state": {
                "certified": "READY",
                "limited": "LIMITED",
                "unverified": "COMPATIBILITY_UNVERIFIED",
            }[support],
        }
        exact_keys(
            row["compatibility"],
            {"manifest_record_id", "platform_declared", "support", "runtime_state"},
            f"matrix[{index}].compatibility",
        )
        if not strict_equal(row["compatibility"], expected_compatibility):
            raise EvidenceError(f"matrix[{index}] compatibility state does not match")
        artifacts = exact_keys(
            row["artifacts"],
            {
                "archive_binding", "test_binding", "tap", "cell_receipt",
                "runtime_snapshot", "node_binding",
            },
            f"matrix[{index}].artifacts",
        )
        suffix = f"{pi_record['id']}-{platform['id']}"
        expected_artifact_basenames = {
            "archive_binding": f"pi-candidate-{suffix}.sha256",
            "test_binding": f"pi-tests-{suffix}.sha256",
            "tap": f"pi-candidate-{suffix}.tap",
            "cell_receipt": f"pi-cell-{suffix}.json",
            "runtime_snapshot": f"pi-runtime-pre-{suffix}.json",
            "node_binding": f"pi-node-pre-{suffix}.json",
        }
        for artifact_kind, artifact in artifacts.items():
            exact_keys(
                artifact,
                {"name", "file_sha256"},
                f"matrix[{index}].artifacts.{artifact_kind}",
            )
            if artifact["name"] != expected_artifact_basenames[artifact_kind] or not isinstance(
                artifact["file_sha256"], str
            ) or not SHA256_RE.fullmatch(artifact["file_sha256"]):
                raise EvidenceError(f"matrix[{index}] artifact identity is invalid")
        expected_binding_hashes = {
            "archive_binding": sha256_bytes(f"{archive_sha}\n".encode("ascii")),
            "test_binding": sha256_bytes(
                f"{expected_tests['source_tree_sha256']}\n".encode("ascii")
            ),
        }
        for artifact_kind, expected_hash in expected_binding_hashes.items():
            if artifacts[artifact_kind]["file_sha256"] != expected_hash:
                raise EvidenceError(
                    f"matrix[{index}] {artifact_kind} digest is not derivable from its binding"
                )
        if artifacts["runtime_snapshot"]["file_sha256"] != snapshot_binding["file_sha256"]:
            raise EvidenceError(
                f"matrix[{index}] runtime snapshot artifact digest does not match proof"
            )
        if artifacts["node_binding"]["file_sha256"] != node_binding["file_sha256"]:
            raise EvidenceError(
                f"matrix[{index}] Node binding artifact digest does not match proof"
            )
        result = exact_keys(
            row["result"],
            {"status", "plan", "ok", "executed", "not_ok", "skipped", "skip_details"},
            f"matrix[{index}].result",
        )
        expected_skip_details: list[dict[str, Any]] = []
        if pi_record["expected_skip"] is not None:
            expected_names = source_test_names(repo_root, test_paths)
            expected_skip_details = [{
                "number": expected_names.index(pi_record["expected_skip"]["test"]) + 1,
                "test": pi_record["expected_skip"]["test"],
                "reason": pi_record["expected_skip"]["reason"],
            }]
        expected_result = {
            "status": "pass",
            "plan": contract["plan_per_run"],
            "ok": contract["plan_per_run"],
            "executed": contract["plan_per_run"] - pi_record["expected_skips"],
            "not_ok": 0,
            "skipped": pi_record["expected_skips"],
            "skip_details": expected_skip_details,
        }
        if not strict_equal(result, expected_result) or not strict_equal(
            row["limitations"], pi_record["limitations"]
        ):
            raise EvidenceError(f"matrix[{index}] result or limitations do not match")
    if ids != sorted(ids) or len(ids) != len(set(ids)) or set(ids) != set(expected_pairs):
        raise EvidenceError("receipt matrix ids must be sorted, unique, and complete")

    summary = exact_keys(
        receipt["summary"],
        {
            "matrix_rows",
            "passed_rows",
            "failed_rows",
            "planned_tests",
            "ok",
            "executed",
            "not_ok",
            "skipped",
        },
        "summary",
    )
    expected_summary = {
        "matrix_rows": expected_rows,
        "passed_rows": expected_rows,
        "failed_rows": 0,
        "planned_tests": expected_rows * contract["plan_per_run"],
        "ok": expected_rows * contract["plan_per_run"],
        "executed": expected_rows * contract["plan_per_run"]
        - sum(record["expected_skips"] for record in pi_versions) * len(platforms),
        "not_ok": 0,
        "skipped": sum(record["expected_skips"] for record in pi_versions) * len(platforms),
    }
    if not strict_equal(summary, expected_summary):
        raise EvidenceError("receipt summary does not match the matrix contract")
    expected_limitations = [
        "This receipt proves exact-candidate Pi integration conformance on the listed matrix; it does not prove live user activation, general agent safety, agent quality, or adoption.",
        "Raw TAP remains a short-lived workflow artifact and is represented here by SHA-256 and a bounded result summary.",
    ]
    if not strict_equal(receipt["limitations"], expected_limitations):
        raise EvidenceError("receipt limitations do not match the bounded claim")


def expected_durable_cell_receipt(
    receipt: dict[str, Any],
    row: dict[str, Any],
    repo_root: Path,
    test_paths: list[str],
) -> dict[str, Any]:
    """Project one aggregate row back to its complete canonical cell receipt."""
    pi = row["pi"]
    platform = row["platform"]
    observation = row["observation"]
    artifacts = row["artifacts"]
    suffix = f"{pi['id']}-{platform['id']}"
    source_files = expected_cell_source_files(repo_root, test_paths)
    return {
        "schema_version": 1,
        "kind": "mainframe-pi-exact-candidate-cell-evidence",
        "claim_scope": "exact-candidate-single-cell-pi-integration-conformance-only",
        "cell_id": row["id"],
        "mainframe": dict(receipt["mainframe"]),
        "source": {
            "repository": receipt["source"]["repository"],
            "ref": f"refs/tags/{receipt['source']['tag']}",
            "ref_sha": receipt["source"]["tag_ref_sha"],
            "commit_sha": receipt["source"]["tag_commit_sha"],
            "workflow_run_id": receipt["source"]["workflow_run_id"],
            "workflow_run_attempt": receipt["source"]["workflow_run_attempt"],
            "binding_mode": "git-head-clean-tracked-files",
            "files": source_files,
        },
        "host": {
            "observation_mode": observation["mode"],
            "platform": dict(platform),
            "commands": dict(observation["commands"]),
            "test_override": (
                platform["id"] if observation["mode"] == "test-override" else None
            ),
        },
        "pi": {
            **dict(pi),
            "package_json_name": "package.json",
            "package_json_sha256": observation["package_json_sha256"],
            "package_tree_sha256": observation["package_tree_sha256"],
            "runtime_root_name": "node_modules",
            "runtime_tree_sha256": observation["runtime_tree_sha256"],
            "runtime_entry": ".bin/pi",
            "integrity_input": {
                "name": f"pi-npm-integrity-{suffix}.txt",
                "file_sha256": observation["npm_integrity_input_sha256"],
                "binding_value": pi["npm_integrity"],
            },
        },
        "node_runtime": dict(observation["node_runtime"]),
        "runtime_proof": dict(observation["runtime_proof"]),
        "compatibility": dict(row["compatibility"]),
        "producer": {
            "contract_sha256": receipt["producer"]["contract_sha256"],
            "config_sha256": receipt["producer"]["config_sha256"],
            "schema_sha256": receipt["producer"]["cell_schema_sha256"],
            "generator_sha256": receipt["producer"]["cell_generator_sha256"],
        },
        "tests": {
            "canonicalization": receipt["tests"]["canonicalization"],
            "paths": list(receipt["tests"]["paths"]),
            "source_tree_sha256": receipt["tests"]["source_tree_sha256"],
            "plan": receipt["tests"]["plan_per_run"],
            "bats_core_commit": receipt["tests"]["bats_core_commit"],
            "cases": list(receipt["tests"]["cases"]),
        },
        "artifacts": {
            "archive_binding": {
                **dict(artifacts["archive_binding"]),
                "binding_value": receipt["mainframe"]["archive_sha256"],
            },
            "test_binding": {
                **dict(artifacts["test_binding"]),
                "binding_value": receipt["tests"]["source_tree_sha256"],
            },
            "tap": {
                **dict(artifacts["tap"]),
                "binding_value": None,
            },
        },
        "result": dict(row["result"]),
        "limitations": [
            "This receipt proves one exact-candidate Pi integration conformance cell only; it does not prove live user activation, general agent safety, agent quality, or adoption.",
            "A passing cell does not upgrade compatibility support; support and runtime state are copied from the bound compatibility manifest for this platform.",
            "Package identity, npm integrity, candidate/test bindings, and TAP are represented by bounded values and SHA-256 digests, not by an installed-user attestation.",
        ],
    }


def validate_durable_cell_receipts(
    receipt: dict[str, Any],
    cell_receipts_dir: Path,
    cell_schema_path: Path,
    repo_root: Path,
    test_paths: list[str],
) -> None:
    """Validate the six durable receipt bytes transitively against the aggregate."""
    try:
        metadata = cell_receipts_dir.lstat()
        entries = list(cell_receipts_dir.iterdir())
    except OSError as error:
        raise EvidenceError(f"could not inspect durable Pi cell directory: {error}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise EvidenceError("durable Pi cell receipt directory must be a real directory")

    expected_rows = {
        row["artifacts"]["cell_receipt"]["name"]: row
        for row in receipt["matrix"]
    }
    if len(expected_rows) != 6:
        raise EvidenceError("aggregate must bind exactly six unique durable Pi cell receipts")
    cell_entries = [entry for entry in entries if entry.name.startswith("pi-cell-")]
    actual_names = {entry.name for entry in cell_entries}
    expected_names = set(expected_rows)
    if actual_names != expected_names or len(cell_entries) != len(expected_names):
        raise EvidenceError(
            "durable Pi cell receipt inventory differs: "
            f"missing={sorted(expected_names - actual_names)} "
            f"extra={sorted(actual_names - expected_names)}"
        )

    cell_schema, _cell_schema_raw = load_json(cell_schema_path, "Pi cell schema")
    validate_schema_definition(cell_schema, "cell schema")
    for name in sorted(expected_names):
        path = cell_receipts_dir / name
        cell, raw = load_json(path, f"durable Pi cell receipt {name}")
        if raw != canonical_json(cell):
            raise EvidenceError(f"durable Pi cell receipt is not canonical JSON: {name}")
        validate_against_schema(cell_schema, cell, cell_schema)
        row = expected_rows[name]
        expected_sha = row["artifacts"]["cell_receipt"]["file_sha256"]
        if sha256_bytes(raw) != expected_sha:
            raise EvidenceError(
                f"durable Pi cell receipt digest does not match aggregate: {name}"
            )
        expected_cell = expected_durable_cell_receipt(
            receipt, row, repo_root, test_paths
        )
        if not strict_equal(cell, expected_cell):
            raise EvidenceError(
                f"durable Pi cell receipt content does not match aggregate: {name}"
            )


def atomic_write(path: Path, raw: bytes) -> None:
    parent = path.parent
    if parent.is_symlink() or not parent.is_dir():
        raise EvidenceError(f"output parent must be a real directory: {parent}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            view = memoryview(raw)
            while view:
                written = output.write(view)
                if written is None or written <= 0:
                    raise EvidenceError("could not write complete Pi evidence output")
                view = view[written:]
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o644)
        try:
            os.link(temporary, path)
        except FileExistsError as error:
            raise EvidenceError(f"output must be absent: {path}") from error
        directory_descriptor = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    for action in ("create", "verify"):
        command = subparsers.add_parser(action)
        command.add_argument("--contract", type=Path, required=True)
        command.add_argument("--schema", type=Path, required=True)
        command.add_argument("--cell-schema", type=Path, required=True)
        command.add_argument("--repo-root", type=Path, required=True)
        command.add_argument("--archive", type=Path, required=True)
        command.add_argument("--repository", required=True)
        command.add_argument("--version", required=True)
        command.add_argument("--tag", required=True)
        command.add_argument("--tag-ref-sha", required=True)
        command.add_argument("--tag-commit-sha", required=True)
        command.add_argument("--workflow-run-id", required=True)
        command.add_argument("--workflow-run-attempt", type=int, required=True)
        command.add_argument("--artifacts-dir", type=Path)
        if action == "create":
            command.add_argument("--output", type=Path, required=True)
        else:
            command.add_argument("--evidence", type=Path, required=True)
            command.add_argument(
                "--cell-receipts-dir",
                type=Path,
                help=(
                    "verify exactly the six pi-cell-* release assets in this directory; "
                    "unrelated release assets may coexist"
                ),
            )
            command.add_argument(
                "--summary-only",
                action="store_true",
                help="validate the signed receipt summary without short-lived raw artifacts",
            )
    return parser


def main() -> int:
    arguments = build_parser().parse_args()
    try:
        repo_root_input = arguments.repo_root.absolute()
        repo_root_metadata = repo_root_input.lstat()
        if stat.S_ISLNK(repo_root_metadata.st_mode) or not stat.S_ISDIR(
            repo_root_metadata.st_mode
        ):
            raise EvidenceError("repo-root must be a real directory")
        repo_root = repo_root_input.resolve(strict=True)
        arguments.contract = arguments.contract.absolute()
        arguments.schema = arguments.schema.absolute()
        arguments.cell_schema = arguments.cell_schema.absolute()
        arguments.archive = arguments.archive.absolute()
        if arguments.artifacts_dir is not None:
            arguments.artifacts_dir = arguments.artifacts_dir.absolute()
        if getattr(arguments, "cell_receipts_dir", None) is not None:
            arguments.cell_receipts_dir = arguments.cell_receipts_dir.absolute()
        validate_common_arguments(arguments, repo_root)
        contract, contract_raw = load_json(arguments.contract, "Pi evidence contract")
        schema, _schema_raw = load_json(arguments.schema, "Pi evidence schema")
        validate_schema_definition(schema)
        test_paths, platforms, pi_versions = validate_contract(
            contract, repo_root, arguments.version
        )
        validate_source_inputs(arguments, repo_root, test_paths)
        if arguments.action == "create":
            if arguments.artifacts_dir is None:
                raise EvidenceError("create requires --artifacts-dir")
            receipt = build_receipt(
                arguments,
                contract,
                contract_raw,
                test_paths,
                platforms,
                pi_versions,
                repo_root,
            )
            validate_receipt(
                receipt,
                arguments,
                contract,
                contract_raw,
                test_paths,
                platforms,
                pi_versions,
                repo_root,
            )
            validate_against_schema(schema, receipt, schema)
            atomic_write(arguments.output, canonical_json(receipt))
            print(f"Pi release evidence created: {arguments.output}")
            return 0

        evidence_path = arguments.evidence.absolute()
        receipt, receipt_raw = load_json(evidence_path, "Pi evidence receipt")
        if receipt_raw != canonical_json(receipt):
            raise EvidenceError("Pi evidence receipt is not canonical sorted-key JSON")
        verification_modes = sum(
            (
                arguments.artifacts_dir is not None,
                arguments.cell_receipts_dir is not None,
                arguments.summary_only,
            )
        )
        if verification_modes != 1:
            raise EvidenceError(
                "verify requires exactly one of --artifacts-dir, "
                "--cell-receipts-dir, or --summary-only"
            )
        validate_receipt(
            receipt,
            arguments,
            contract,
            contract_raw,
            test_paths,
            platforms,
            pi_versions,
            repo_root,
        )
        validate_against_schema(schema, receipt, schema)
        if arguments.artifacts_dir is not None:
            reconstructed = build_receipt(
                arguments,
                contract,
                contract_raw,
                test_paths,
                platforms,
                pi_versions,
                repo_root,
            )
            if not strict_equal(receipt, reconstructed):
                raise EvidenceError("Pi evidence receipt does not match the raw artifacts")
            print("Pi release evidence and raw artifacts valid")
            return 0
        if arguments.cell_receipts_dir is not None:
            validate_durable_cell_receipts(
                receipt,
                arguments.cell_receipts_dir,
                arguments.cell_schema,
                repo_root,
                test_paths,
            )
            print(
                "Pi release evidence and six durable cell receipts valid; "
                "raw TAP not reverified"
            )
            return 0
        print("Pi release evidence summary valid; raw artifacts not reverified")
        return 0
    except (EvidenceError, OSError) as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())

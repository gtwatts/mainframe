#!/usr/bin/env python3
"""Validate a closed MAINFRAME host conformance receipt and its claim ceilings.

An artifact ``result`` is an assertion made by the receipt, not proof that an
external host executed. This validator checks closed structure, local byte
bindings, registry ceilings, and a minimum exact release-attestation content
binding. A future evidence validator must still verify live transcript content
and release-attestation provenance, signature, and public availability before
either claim is promoted.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any, NoReturn


EVIDENCE_LEVELS = (
    "unverified",
    "instructions",
    "configured",
    "enforced",
    "live",
    "released",
)
EVIDENCE_RANKS = {level: rank for rank, level in enumerate(EVIDENCE_LEVELS)}
CAPABILITIES = ("approval", "cancel", "progress", "memory", "audit")
REQUIRED_ARTIFACT = {
    "instructions": "instruction",
    "configured": "configuration",
    "enforced": "deterministic-test",
    "live": "live-transcript",
    "released": "release-attestation",
}


class ReceiptError(ValueError):
    """A closed-structure or semantic receipt validation failure."""


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid host conformance receipt: {message}")


def _reject_constant(value: str) -> NoReturn:
    raise ReceiptError(f"non-finite JSON number {value!r} is forbidden")


def load_json(path: Path, label: str, maximum_bytes: int) -> Any:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ReceiptError(f"{label} is unavailable: {error}") from error
    if path.is_symlink() or not path.is_file():
        raise ReceiptError(f"{label} must be a regular non-symbolic-link file")
    if metadata.st_size > maximum_bytes:
        raise ReceiptError(f"{label} exceeds {maximum_bytes} bytes")

    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ReceiptError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicates,
            parse_constant=_reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReceiptError(f"{label} is not strict UTF-8 JSON: {error}") from error


def json_equal(left: Any, right: Any) -> bool:
    if isinstance(left, bool) != isinstance(right, bool):
        if isinstance(left, (bool, int)) and isinstance(right, (bool, int)):
            return False
    return type(left) is type(right) and left == right


def matches_type(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def resolve_ref(root: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ReceiptError(f"unsupported non-local schema reference {reference!r}")
    current: Any = root
    for encoded_part in reference[2:].split("/"):
        part = encoded_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            raise ReceiptError(f"unresolvable schema reference {reference!r}")
        current = current[part]
    if not isinstance(current, dict):
        raise ReceiptError(f"schema reference is not an object: {reference!r}")
    return current


def validate_schema(
    schema: dict[str, Any], value: Any, path: str, root: dict[str, Any]
) -> None:
    if "$ref" in schema:
        validate_schema(resolve_ref(root, schema["$ref"]), value, path, root)
        return

    alternatives = schema.get("anyOf")
    if alternatives is not None:
        errors: list[str] = []
        for alternative in alternatives:
            try:
                validate_schema(alternative, value, path, root)
                break
            except ReceiptError as error:
                errors.append(str(error))
        else:
            raise ReceiptError(
                f"{path}: no anyOf alternative matched ({'; '.join(errors)})"
            )

    if "const" in schema and not json_equal(value, schema["const"]):
        raise ReceiptError(
            f"{path}: expected constant {schema['const']!r}, got {value!r}"
        )
    if "enum" in schema and not any(json_equal(value, item) for item in schema["enum"]):
        raise ReceiptError(f"{path}: value {value!r} is outside the closed enum")

    expected_type = schema.get("type")
    if expected_type is not None and not matches_type(value, expected_type):
        raise ReceiptError(f"{path}: expected {expected_type}, got {type(value).__name__}")

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ReceiptError(f"{path}: is shorter than minLength")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise ReceiptError(f"{path}: is longer than maxLength")
        pattern = schema.get("pattern")
        if pattern is not None:
            try:
                matched = re.search(pattern, value)
            except re.error as error:
                raise ReceiptError(f"schema contains invalid pattern {pattern!r}: {error}")
            if matched is None:
                raise ReceiptError(f"{path}: does not match {pattern!r}")
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError as error:
                raise ReceiptError(f"{path}: invalid date-time: {error}") from error
            if parsed.tzinfo is None:
                raise ReceiptError(f"{path}: date-time must include a timezone")

    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ReceiptError(f"{path}: has fewer than minItems")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise ReceiptError(f"{path}: has more than maxItems")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_schema(schema["items"], item, f"{path}[{index}]", root)

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = [key for key in schema.get("required", []) if key not in value]
        if missing:
            raise ReceiptError(f"{path}: missing required keys {missing}")
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise ReceiptError(f"{path}: unexpected keys {extras}")
        for key, child_schema in properties.items():
            if key in value:
                validate_schema(child_schema, value[key], f"{path}.{key}", root)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_repository_file(root: Path, relative: str, label: str) -> Path:
    logical = PurePosixPath(relative)
    if (
        logical.is_absolute()
        or logical.as_posix() != relative
        or not logical.parts
        or any(part in {"", ".", ".."} for part in logical.parts)
    ):
        raise ReceiptError(f"{label} is not a normalized repository-relative path")
    candidate = root.joinpath(*logical.parts)
    try:
        metadata = candidate.lstat()
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError) as error:
        raise ReceiptError(f"{label} is unavailable or escapes the repository: {error}") from error
    if candidate.is_symlink() or not candidate.is_file() or not metadata:
        raise ReceiptError(f"{label} must be a regular non-symbolic-link file")
    return resolved


def artifact_kinds(claim: dict[str, Any]) -> set[str]:
    return {artifact["kind"] for artifact in claim["artifacts"]}


def validate_release_attestation(
    root: Path, claim: dict[str, Any], label: str
) -> None:
    release = claim["release"]
    if release is None:
        raise ReceiptError(f"{label}: released evidence requires a release binding")
    candidates = [
        artifact
        for artifact in claim["artifacts"]
        if artifact["kind"] == "release-attestation"
    ]
    if not candidates:
        raise ReceiptError(
            f"{label}: released evidence requires a release-attestation artifact"
        )
    expected = {
        "schema_version": 1,
        "kind": "mainframe-host-release-attestation",
        "version": release["version"],
        "archive_sha256": release["archive_sha256"],
        "attestation_uri": release["attestation_uri"],
    }
    for index, artifact in enumerate(candidates):
        path = safe_repository_file(
            root,
            artifact["path"],
            f"{label}.release_attestation[{index}]",
        )
        try:
            document = load_json(path, f"{label} release-attestation", 256 * 1024)
        except ReceiptError:
            continue
        if document == expected:
            return
    raise ReceiptError(f"{label}: release-attestation content does not bind release")


def validate_artifacts(root: Path, receipt: dict[str, Any]) -> None:
    artifacts = [receipt["instruction"]["artifact"]]
    for claim in receipt["tool_classes"].values():
        artifacts.extend(claim["artifacts"])
    for claim in receipt["capabilities"].values():
        artifacts.extend(claim["artifacts"])

    seen: set[tuple[str, str, str]] = set()
    for index, artifact in enumerate(artifacts):
        label = f"artifact[{index}]"
        path = safe_repository_file(root, artifact["path"], f"{label}.path")
        actual = sha256(path)
        if artifact["sha256"] != actual:
            raise ReceiptError(f"{label}.sha256 does not bind {artifact['path']}")
        identity = (artifact["kind"], artifact["path"], artifact["sha256"])
        if identity in seen:
            continue
        seen.add(identity)
        if receipt["verdict"] == "pass" and artifact["result"] != "pass":
            raise ReceiptError("a passing receipt cannot contain a failed artifact")


def require_claim_evidence(
    claim: dict[str, Any], label: str, subject: dict[str, Any]
) -> None:
    level = claim["evidence_level"]
    rank = EVIDENCE_RANKS[level]
    kinds = artifact_kinds(claim)

    if level == "released":
        if claim["release"] is None:
            raise ReceiptError(f"{label}: released evidence requires a release binding")
        if "release-attestation" not in kinds:
            raise ReceiptError(f"{label}: released evidence requires a release-attestation artifact")
        if claim["release"]["version"] != subject["mainframe_version"]:
            raise ReceiptError(f"{label}: release version does not bind mainframe_version")
        if subject["payload_status"] != "released":
            raise ReceiptError(f"{label}: released evidence requires released payload status")
    elif claim["release"] is not None:
        raise ReceiptError(f"{label}: only released evidence may contain a release binding")

    if rank >= EVIDENCE_RANKS["live"]:
        if subject["host_version"] is None:
            raise ReceiptError(f"{label}: live evidence requires an exact host_version")
        if claim["observed_at"] is None:
            raise ReceiptError(f"{label}: live evidence requires observed_at")
    elif claim["observed_at"] is not None:
        raise ReceiptError(f"{label}: observed_at is reserved for live or released evidence")

    if rank > 0:
        required = REQUIRED_ARTIFACT[level]
        if required not in kinds:
            raise ReceiptError(f"{label}: {level} evidence requires a {required} artifact")
    elif claim["artifacts"]:
        raise ReceiptError(f"{label}: unverified evidence cannot carry qualifying artifacts")


def validate_route_claims(
    root: Path,
    receipt: dict[str, Any],
    registry: dict[str, Any],
    host: dict[str, Any],
) -> None:
    subject = receipt["subject"]
    platform = host["platform_evidence"][subject["platform"]]
    platform_level = platform["evidence_level"]
    intercepted = set(host["intercepted_tool_classes"])
    fail_open_routes = {record["route"] for record in host["fail_open_routes"]}

    for tool_class, claim in receipt["tool_classes"].items():
        label = f"tool_classes.{tool_class}"
        level = claim["evidence_level"]
        rank = EVIDENCE_RANKS[level]

        require_claim_evidence(claim, label, subject)
        if level == "released":
            validate_release_attestation(root, claim, label)
        if level == "released" and platform["released"] is not True:
            raise ReceiptError(f"{label}: registry platform is not released")
        if rank > EVIDENCE_RANKS[platform_level]:
            raise ReceiptError(
                f"{label}: evidence {level} exceeds platform level {platform_level}"
            )

        if tool_class not in intercepted:
            if level != "unverified" or claim["interception"] != "none":
                raise ReceiptError(
                    f"{label}: registry does not declare {tool_class} interception"
                )
            if (
                claim["mechanism"] is not None
                or claim["route"] is not None
                or claim["fail_behavior"] != "not-intercepted"
                or claim["artifacts"]
                or claim["observed_at"] is not None
                or claim["release"] is not None
            ):
                raise ReceiptError(f"{label}: non-intercepted routes must remain empty")
            continue

        if level == "unverified":
            if (
                claim["interception"] != "none"
                or claim["mechanism"] is not None
                or claim["route"] is not None
                or claim["fail_behavior"] != "not-intercepted"
            ):
                raise ReceiptError(f"{label}: unverified route must not claim interception")
            continue

        if rank == EVIDENCE_RANKS["instructions"]:
            if claim["interception"] not in {"none", "declared"}:
                raise ReceiptError(f"{label}: instructions cannot claim observed interception")
        elif rank == EVIDENCE_RANKS["configured"]:
            if claim["interception"] not in {"declared", "observed"}:
                raise ReceiptError(f"{label}: configured route requires declared interception")
        elif claim["interception"] != "observed":
            raise ReceiptError(f"{label}: {level} route requires observed interception")

        if claim["mechanism"] is None or claim["route"] is None:
            raise ReceiptError(f"{label}: qualified route requires mechanism and route")
        if claim["fail_behavior"] not in {"fail-closed", "fail-open"}:
            raise ReceiptError(f"{label}: qualified route requires explicit fail behavior")

        route = claim["route"]
        if claim["fail_behavior"] == "fail-open" or route in fail_open_routes:
            if route not in fail_open_routes or claim["fail_behavior"] != "fail-open":
                raise ReceiptError(f"{label}: fail-open route binding disagrees with registry")
            if rank > EVIDENCE_RANKS["instructions"]:
                raise ReceiptError(f"{label}: fail-open route is capped at instructions")


def validate_capability_claims(
    root: Path, receipt: dict[str, Any], host: dict[str, Any]
) -> None:
    subject = receipt["subject"]
    platform = host["platform_evidence"][subject["platform"]]
    platform_level = platform["evidence_level"]

    for capability in CAPABILITIES:
        claim = receipt["capabilities"][capability]
        registry_claim = host["capabilities"][capability]
        label = f"capabilities.{capability}"
        level = claim["evidence_level"]
        rank = EVIDENCE_RANKS[level]

        require_claim_evidence(claim, label, subject)
        if level == "released":
            validate_release_attestation(root, claim, label)
        if level == "released" and platform["released"] is not True:
            raise ReceiptError(f"{label}: registry platform is not released")
        registry_level = registry_claim["evidence_level"]
        if rank > EVIDENCE_RANKS[registry_level]:
            raise ReceiptError(
                f"{label}: {capability} evidence {level} exceeds registry level {registry_level}"
            )
        if rank > EVIDENCE_RANKS[platform_level]:
            raise ReceiptError(
                f"{label}: evidence {level} exceeds platform level {platform_level}"
            )
        if level == "unverified":
            if claim["mechanism"] is not None:
                raise ReceiptError(f"{label}: unverified capability must not claim a mechanism")
            continue
        if claim["mechanism"] != registry_claim["mechanism"]:
            raise ReceiptError(f"{label}: mechanism does not bind the registry claim")


def validate_semantics(
    root: Path,
    schema_path: Path,
    registry_path: Path,
    schema: dict[str, Any],
    registry: dict[str, Any],
    receipt: dict[str, Any],
) -> None:
    if not isinstance(registry, dict):
        raise ReceiptError("host registry root must be an object")
    expected_ranks = {
        level: registry.get("evidence_levels", {}).get(level, {}).get("rank")
        for level in EVIDENCE_LEVELS
    }
    if expected_ranks != EVIDENCE_RANKS:
        raise ReceiptError("host registry evidence ranks do not match receipt v1")
    registry_tool_classes = registry.get("tool_classes")
    if (
        not isinstance(registry_tool_classes, list)
        or len(registry_tool_classes) != len(set(registry_tool_classes))
        or set(registry_tool_classes) != set(receipt["tool_classes"])
    ):
        raise ReceiptError("receipt tool classes do not bind the closed registry set")

    contract = receipt["contract"]
    if contract["registry_sha256"] != sha256(registry_path):
        raise ReceiptError("contract.registry_sha256 does not bind the registry bytes")
    if contract["receipt_schema_sha256"] != sha256(schema_path):
        raise ReceiptError("contract.receipt_schema_sha256 does not bind the schema bytes")
    if contract["registry_schema_version"] != registry.get("schema_version"):
        raise ReceiptError("contract.registry_schema_version does not bind the registry")
    if contract["registry_contract_version"] != registry.get("contract_version"):
        raise ReceiptError("contract.registry_contract_version does not bind the registry")

    subject = receipt["subject"]
    try:
        host = registry["hosts"][subject["host_id"]]
    except (KeyError, TypeError) as error:
        raise ReceiptError(f"unknown registry host {subject['host_id']!r}") from error
    if subject["platform"] not in registry.get("platforms", []):
        raise ReceiptError(f"unknown registry platform {subject['platform']!r}")
    if subject["platform"] not in host.get("platform_evidence", {}):
        raise ReceiptError("host has no platform evidence record for the subject platform")
    if subject["adapter_path"] != host["static_adapter"]:
        raise ReceiptError("subject.adapter_path does not bind the registry host")
    adapter = safe_repository_file(root, subject["adapter_path"], "subject.adapter_path")
    if subject["adapter_sha256"] != sha256(adapter):
        raise ReceiptError("subject.adapter_sha256 does not bind the adapter bytes")
    version_path = safe_repository_file(root, "VERSION", "VERSION")
    if subject["mainframe_version"] != version_path.read_text(encoding="utf-8").strip():
        raise ReceiptError("subject.mainframe_version does not bind VERSION")
    inventory_path = safe_repository_file(root, "SHA256SUMS", "SHA256SUMS")
    if subject["payload_sha256"] != sha256(inventory_path):
        raise ReceiptError("subject.payload_sha256 does not bind SHA256SUMS bytes")

    instruction = receipt["instruction"]
    artifact = instruction["artifact"]
    if (
        artifact["kind"] != "instruction"
        or artifact["path"] != subject["adapter_path"]
        or artifact["sha256"] != subject["adapter_sha256"]
        or artifact["result"] != "pass"
    ):
        raise ReceiptError("instruction artifact does not bind the subject adapter")

    validate_artifacts(root, receipt)
    validate_route_claims(root, receipt, registry, host)
    validate_capability_claims(root, receipt, host)
    claims = [
        *receipt["tool_classes"].values(),
        *receipt["capabilities"].values(),
    ]
    if subject["payload_status"] == "released" and not any(
        claim["evidence_level"] == "released" for claim in claims
    ):
        raise ReceiptError(
            "subject.payload_status: released payload status requires a validated released claim"
        )


def exact_repository_root(path: Path) -> Path:
    if not path.is_absolute():
        raise ReceiptError("repo-root must be an exact non-symbolic-link path")
    try:
        metadata = path.lstat()
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise ReceiptError(f"repo-root is unavailable: {error}") from error
    if path.is_symlink() or not path.is_dir() or not metadata or path != resolved:
        raise ReceiptError("repo-root must be an exact non-symbolic-link path")
    return resolved


def require_canonical_contract_path(
    provided: Path, expected: Path, label: str
) -> Path:
    try:
        resolved = provided.resolve(strict=True)
    except OSError as error:
        raise ReceiptError(f"{label} is unavailable: {error}") from error
    if (
        not provided.is_absolute()
        or provided.is_symlink()
        or provided != expected
        or resolved != expected
    ):
        raise ReceiptError(f"{label} must be the canonical repository path")
    return expected


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Validate one closed MAINFRAME host conformance receipt."
    )
    result.add_argument("--repo-root", required=True, type=Path)
    result.add_argument("--schema", required=True, type=Path)
    result.add_argument("--registry", required=True, type=Path)
    result.add_argument("--receipt", required=True, type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        root = exact_repository_root(arguments.repo_root)
        schema_path = require_canonical_contract_path(
            arguments.schema,
            root / "config" / "host-conformance-receipt.schema.json",
            "schema",
        )
        registry_path = require_canonical_contract_path(
            arguments.registry,
            root / "config" / "host-capabilities.json",
            "registry",
        )
        schema = load_json(schema_path, "receipt schema", 512 * 1024)
        registry = load_json(registry_path, "host registry", 2 * 1024 * 1024)
        receipt = load_json(arguments.receipt, "receipt", 2 * 1024 * 1024)
        if not isinstance(schema, dict):
            raise ReceiptError("receipt schema root must be an object")
        if not isinstance(receipt, dict):
            raise ReceiptError("receipt root must be an object")
        validate_schema(schema, receipt, "$", schema)
        validate_semantics(
            root,
            schema_path,
            registry_path,
            schema,
            registry,
            receipt,
        )
    except ReceiptError as error:
        fail(str(error))
    print("host conformance receipt valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

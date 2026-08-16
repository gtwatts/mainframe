#!/usr/bin/env python3
"""Create and verify MAINFRAME's deterministic release-evidence bundle."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
from typing import Any, NoReturn


sys.dont_write_bytecode = True

KIND = "mainframe-release-evidence-manifest"
CANONICALIZATION = "mainframe-certifier-input-bundle-v1"
PREDICATE_TYPE = (
    "https://github.com/gtwatts/mainframe/attestations/release-evidence/v1"
)
DEFAULT_INPUT_DEFINITION = "scripts/dev/native-host/certifier-inputs.json"
DEFAULT_MANIFEST_SCHEMA = "scripts/dev/native-host/release-evidence.schema.json"
DEFAULT_PLATFORM_DEFINITION = "scripts/dev/native-host/release-platforms.json"
DEFAULT_WORKFLOW = ".github/workflows/test.yml"
BUILDER_PATH = "scripts/dev/native-host/build-release-evidence.py"
VALIDATOR_PATH = "scripts/dev/native-host/validate-evidence.py"
AWM_SCHEMA = "scripts/dev/native-host/awm-chain-evidence.schema.json"
SAFETY_SCHEMAS = {
    "gemini": "scripts/dev/native-host/evidence.schema.json",
    "codex": "scripts/dev/native-host/codex-evidence.schema.json",
    "copilot": "scripts/dev/native-host/copilot-evidence.schema.json",
    "claude": "scripts/dev/native-host/claude-evidence.schema.json",
}
ADVERTISED_PLATFORM_TUPLES = (
    ("Darwin", "arm64", "none"),
    ("Darwin", "x86_64", "none"),
    ("Linux", "x86_64", "glibc"),
)
EXPECTED_SAFETY_CERTIFICATES = len(SAFETY_SCHEMAS) * len(ADVERTISED_PLATFORM_TUPLES)
EXPECTED_AWM_CERTIFICATES = len(ADVERTISED_PLATFORM_TUPLES)
EXPECTED_CERTIFICATE_COUNT = EXPECTED_SAFETY_CERTIFICATES + EXPECTED_AWM_CERTIFICATES
EXPECTED_BUNDLE_FILE_COUNT = EXPECTED_CERTIFICATE_COUNT + 1
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_BUNDLE_BYTES = 64 * 1024 * 1024
MAX_BUNDLE_MEMBERS = 16
MAX_BUNDLE_EXPANDED_BYTES = 64 * 1024 * 1024
MAX_RUNTIME_ARCHIVE_MEMBERS = 131_072
MAX_RUNTIME_ARCHIVE_MEMBER_BYTES = 2 * 1024 * 1024 * 1024
MAX_RUNTIME_ARCHIVE_EXPANDED_BYTES = 16 * 1024 * 1024 * 1024
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
RUN_ID_RE = re.compile(r"^[0-9]+$")
ROLE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
REPOSITORY_PATH_RE = re.compile(r"^[A-Za-z0-9._/-]+$")


class ReleaseEvidenceError(ValueError):
    """A fail-closed release-evidence validation error."""


def error(message: str) -> NoReturn:
    raise ReleaseEvidenceError(message)


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def pretty_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            error(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def load_json_bytes(contents: bytes, label: str) -> Any:
    if len(contents) > MAX_JSON_BYTES:
        error(f"{label} exceeds the JSON size limit")
    try:
        return json.loads(
            contents.decode("utf-8"), object_pairs_hook=reject_duplicate_keys
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        error(f"{label} is not valid UTF-8 JSON: {exc}")


def sha256_bytes(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def require_regular_file(path: Path, label: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as exc:
        error(f"{label} is unavailable: {path}: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        error(f"{label} must be a regular, non-symlink file: {path}")
    return metadata


def read_regular_file(
    path: Path, label: str, maximum: int | None = None
) -> bytes:
    metadata = require_regular_file(path, label)
    if maximum is not None and metadata.st_size > maximum:
        error(f"{label} exceeds its size limit: {path}")
    try:
        with path.open("rb") as handle:
            contents = handle.read() if maximum is None else handle.read(maximum + 1)
    except OSError as exc:
        error(f"could not read {label}: {path}: {exc}")
    if maximum is not None and len(contents) > maximum:
        error(f"{label} exceeds its size limit: {path}")
    if len(contents) != metadata.st_size:
        error(f"{label} changed while it was read: {path}")
    return contents


def validate_relative_path(value: str, label: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or not REPOSITORY_PATH_RE.fullmatch(value):
        error(f"{label} is not a canonical repository-relative path: {value!r}")
    if "\\" in value:
        error(f"{label} contains a backslash: {value!r}")
    parsed = PurePosixPath(value)
    if (
        parsed.is_absolute()
        or str(parsed) != value
        or any(part in ("", ".", "..") for part in parsed.parts)
    ):
        error(f"{label} is unsafe: {value!r}")
    return parsed


def resolve_repo_root(path: str) -> Path:
    candidate = Path(path)
    try:
        metadata = candidate.lstat()
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        error(f"repository root is unavailable: {candidate}: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not resolved.is_dir():
        error(f"repository root must be a real directory: {candidate}")
    return resolved


def repository_file(root: Path, relative: str, label: str) -> Path:
    parsed = validate_relative_path(relative, label)
    current = root
    for index, part in enumerate(parsed.parts):
        current = current / part
        try:
            metadata = current.lstat()
        except OSError as exc:
            error(f"{label} is unavailable: {relative}: {exc}")
        if stat.S_ISLNK(metadata.st_mode):
            error(f"{label} traverses a symbolic link: {relative}")
        if index < len(parsed.parts) - 1 and not stat.S_ISDIR(metadata.st_mode):
            error(f"{label} has a non-directory parent: {relative}")
    require_regular_file(current, label)
    try:
        resolved = current.resolve(strict=True)
    except OSError as exc:
        error(f"{label} cannot be resolved: {relative}: {exc}")
    if os.path.commonpath((str(root), str(resolved))) != str(root):
        error(f"{label} escapes the repository root: {relative}")
    return resolved


def git_output(root: Path, *arguments: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(root), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        error(f"git {' '.join(arguments)} failed: {detail}")
    return completed.stdout


def git_text(root: Path, *arguments: str) -> str:
    try:
        return git_output(root, *arguments).decode("utf-8").strip()
    except UnicodeDecodeError as exc:
        error(f"git {' '.join(arguments)} returned non-UTF-8 output: {exc}")


def git_blob(root: Path, commit: str, relative: str) -> bytes:
    validate_relative_path(relative, "git blob path")
    return git_output(root, "show", f"{commit}:{relative}")


def require_tag_bound_file(root: Path, commit: str, relative: str, label: str) -> bytes:
    path = repository_file(root, relative, label)
    working = read_regular_file(path, label, MAX_JSON_BYTES if relative.endswith(".json") else None)
    committed = git_blob(root, commit, relative)
    if working != committed:
        error(f"{label} does not match the peeled tag commit: {relative}")
    return working


def stable_file_identity(metadata: os.stat_result) -> tuple[int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
    )


def inspect_runtime_archive(
    path: Path,
    expected_files: dict[str, bytes],
) -> tuple[int, str]:
    """Safely bind tag/worktree control bytes to the final runtime archive."""
    path_metadata = require_regular_file(path, "release archive")
    seen: set[str] = set()
    matched: set[str] = set()
    member_count = 0
    expanded_bytes = 0
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            opened = os.fstat(handle.fileno())
            if not stat.S_ISREG(opened.st_mode):
                error("release archive changed to a non-regular file while opening")
            if (opened.st_dev, opened.st_ino) != (
                path_metadata.st_dev,
                path_metadata.st_ino,
            ):
                error("release archive changed while it was opened")
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
            handle.seek(0)
            with tarfile.open(fileobj=handle, mode="r|gz") as archive:
                if archive.pax_headers:
                    error("release archive has unsupported global PAX metadata")
                for member in archive:
                    member_count += 1
                    if member_count > MAX_RUNTIME_ARCHIVE_MEMBERS:
                        error("release archive has too many members")
                    name = member.name
                    validate_relative_path(name, "release archive member")
                    if name in seen:
                        error(f"duplicate release archive member: {name}")
                    seen.add(name)
                    if not member.isfile():
                        error(f"release archive member is not a regular file: {name}")
                    if stat.S_IMODE(member.mode) not in (0o644, 0o755):
                        error(f"release archive member mode is not normalized: {name}")
                    if member.mtime != 0:
                        error(f"release archive member timestamp is not normalized: {name}")
                    if member.uid != 0 or member.gid != 0 or member.uname or member.gname:
                        error(f"release archive member ownership is not normalized: {name}")
                    if member.linkname or member.pax_headers:
                        error(f"release archive member has unsupported metadata: {name}")
                    if member.size < 0 or member.size > MAX_RUNTIME_ARCHIVE_MEMBER_BYTES:
                        error(f"release archive member size is invalid: {name}")
                    expanded_bytes += member.size
                    if expanded_bytes > MAX_RUNTIME_ARCHIVE_EXPANDED_BYTES:
                        error("release archive exceeds the expanded size limit")
                    expected = expected_files.get(name)
                    if expected is None:
                        continue
                    if member.size != len(expected):
                        error(
                            "release archive control member size does not match "
                            f"the peeled tag input: {name}"
                        )
                    source = archive.extractfile(member)
                    if source is None:
                        error(f"release archive control member has no contents: {name}")
                    contents = source.read(len(expected) + 1)
                    source.close()
                    if contents != expected:
                        error(
                            "release archive control member is not byte-equal to "
                            f"the peeled tag input: {name}"
                        )
                    matched.add(name)
                if archive.pax_headers:
                    error("release archive has unsupported global PAX metadata")
            closed = os.fstat(handle.fileno())
            if stable_file_identity(opened) != stable_file_identity(closed):
                error("release archive changed while it was inspected")
    except (tarfile.TarError, EOFError, OSError) as exc:
        error(f"release archive is not a valid deterministic gzip tar: {exc}")

    current = require_regular_file(path, "release archive")
    if stable_file_identity(path_metadata) != stable_file_identity(current):
        error("release archive changed while it was inspected")
    missing = sorted(set(expected_files) - matched)
    if missing:
        error(f"release archive is missing certifier control members: {missing}")
    if member_count == 0:
        error("release archive must not be empty")
    return path_metadata.st_size, digest.hexdigest()


def load_input_definition(contents: bytes) -> list[dict[str, str]]:
    definition = load_json_bytes(contents, "certifier input definition")
    if not isinstance(definition, dict) or set(definition) != {
        "schema_version",
        "scope",
        "files",
    }:
        error("certifier input definition has unexpected or missing keys")
    if definition["schema_version"] != 1:
        error("certifier input definition schema_version must be 1")
    if not isinstance(definition["scope"], str) or not definition["scope"].strip():
        error("certifier input definition scope must be non-empty")
    raw_files = definition["files"]
    if not isinstance(raw_files, list) or not raw_files:
        error("certifier input definition files must be a non-empty array")
    files: list[dict[str, str]] = []
    for index, record in enumerate(raw_files):
        if not isinstance(record, dict) or set(record) != {"path", "role"}:
            error(f"certifier input definition files[{index}] is malformed")
        path = record["path"]
        role = record["role"]
        validate_relative_path(path, f"certifier input files[{index}].path")
        if not isinstance(role, str) or not ROLE_RE.fullmatch(role):
            error(f"certifier input files[{index}].role is invalid: {role!r}")
        files.append({"path": path, "role": role})
    paths = [record["path"] for record in files]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        error("certifier input definition paths must be sorted and unique")
    return files


def platform_id(operating_system: str, architecture: str, system_libc: str) -> str:
    return f"{operating_system}-{architecture}-{system_libc}"


def load_platform_definition(contents: bytes) -> list[dict[str, str]]:
    definition = load_json_bytes(contents, "release platform definition")
    if not isinstance(definition, dict) or set(definition) != {
        "schema_version",
        "platforms",
    }:
        error("release platform definition has unexpected or missing keys")
    if definition["schema_version"] != 1:
        error("release platform definition schema_version must be 1")
    raw_platforms = definition["platforms"]
    if not isinstance(raw_platforms, list) or not raw_platforms:
        error("release platform definition platforms must be a non-empty array")

    platforms: list[dict[str, str]] = []
    for index, record in enumerate(raw_platforms):
        if not isinstance(record, dict) or set(record) != {
            "id",
            "os",
            "arch",
            "system_libc",
        }:
            error(f"release platform definition platforms[{index}] is malformed")
        operating_system = record["os"]
        architecture = record["arch"]
        system_libc = record["system_libc"]
        if operating_system not in ("Darwin", "Linux"):
            error(f"release platform definition OS is invalid: {operating_system!r}")
        if architecture not in ("arm64", "x86_64"):
            error(f"release platform definition architecture is invalid: {architecture!r}")
        if system_libc not in ("none", "glibc"):
            error(f"release platform definition system_libc is invalid: {system_libc!r}")
        expected_id = platform_id(operating_system, architecture, system_libc)
        if record["id"] != expected_id:
            error(
                "release platform definition id does not match its platform tuple: "
                f"{record['id']!r} != {expected_id!r}"
            )
        platforms.append(
            {
                "id": expected_id,
                "os": operating_system,
                "arch": architecture,
                "system_libc": system_libc,
            }
        )

    ids = [record["id"] for record in platforms]
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        error("release platform definition ids must be sorted and unique")
    actual_tuples = tuple(
        (record["os"], record["arch"], record["system_libc"])
        for record in platforms
    )
    if actual_tuples != ADVERTISED_PLATFORM_TUPLES:
        error(
            "release platform definition must contain exactly the advertised "
            f"platform tuples: {ADVERTISED_PLATFORM_TUPLES!r}"
        )
    return platforms


def git_object_length(object_format: str) -> int:
    if object_format == "sha1":
        return 40
    if object_format == "sha256":
        return 64
    error(f"unsupported Git object format: {object_format}")


def validate_oid(value: str, object_format: str, label: str) -> None:
    expected_length = git_object_length(object_format)
    if not isinstance(value, str) or not re.fullmatch(
        rf"[0-9a-f]{{{expected_length}}}", value
    ):
        error(f"{label} is not a lowercase {object_format} object id")


def build_context(args: argparse.Namespace) -> dict[str, Any]:
    root = resolve_repo_root(args.repo_root)
    if args.certifier_inputs != DEFAULT_INPUT_DEFINITION:
        error(f"certifier_inputs must be {DEFAULT_INPUT_DEFINITION}")
    if args.manifest_schema != DEFAULT_MANIFEST_SCHEMA:
        error(f"manifest_schema must be {DEFAULT_MANIFEST_SCHEMA}")
    expected_builder = repository_file(root, BUILDER_PATH, "release evidence builder")
    try:
        executing_builder = Path(__file__).resolve(strict=True)
    except OSError as exc:
        error(f"could not resolve the executing release evidence builder: {exc}")
    if executing_builder != expected_builder:
        error("the executing release evidence builder is not the repository-bound builder")
    if not REPOSITORY_RE.fullmatch(args.repository):
        error(f"invalid repository identity: {args.repository!r}")
    if not SEMVER_RE.fullmatch(args.version):
        error(f"version must be stable SemVer: {args.version!r}")
    expected_tag = f"v{args.version}"
    expected_ref = f"refs/tags/{expected_tag}"
    if args.tag != expected_tag or args.tag_ref != expected_ref:
        error("tag and tag_ref must exactly match the release version")
    if not RUN_ID_RE.fullmatch(args.workflow_run_id):
        error("workflow_run_id must contain only decimal digits")
    if args.workflow_run_attempt < 1:
        error("workflow_run_attempt must be positive")

    object_format = git_text(root, "rev-parse", "--show-object-format")
    validate_oid(args.tag_ref_sha, object_format, "tag_ref_sha")
    validate_oid(args.tag_commit_sha, object_format, "tag_commit_sha")
    actual_ref_sha = git_text(root, "rev-parse", args.tag_ref)
    actual_commit = git_text(root, "rev-parse", f"{args.tag_ref}^{{commit}}")
    actual_head = git_text(root, "rev-parse", "HEAD")
    if actual_ref_sha != args.tag_ref_sha:
        error("tag_ref_sha does not match the repository tag object")
    if actual_commit != args.tag_commit_sha:
        error("tag_commit_sha does not match the peeled repository tag")
    if actual_head != args.tag_commit_sha:
        error("repository HEAD does not match the peeled release-tag commit")
    epoch_text = git_text(root, "show", "-s", "--format=%ct", args.tag_commit_sha)
    if not epoch_text.isdigit():
        error("tag commit timestamp is not a non-negative integer")
    source_date_epoch = int(epoch_text)
    if source_date_epoch > 0xFFFFFFFF:
        error("tag commit timestamp cannot be represented in the gzip header")
    if args.source_date_epoch is not None and args.source_date_epoch != source_date_epoch:
        error("source_date_epoch does not match the peeled tag commit timestamp")

    workflow_path = args.workflow_path
    workflow_bytes = require_tag_bound_file(
        root, args.tag_commit_sha, workflow_path, "release workflow"
    )
    schema_bytes = require_tag_bound_file(
        root, args.tag_commit_sha, args.manifest_schema, "release evidence schema"
    )
    definition_bytes = require_tag_bound_file(
        root,
        args.tag_commit_sha,
        args.certifier_inputs,
        "certifier input definition",
    )
    input_definition = load_input_definition(definition_bytes)
    platform_definition_bytes = require_tag_bound_file(
        root,
        args.tag_commit_sha,
        DEFAULT_PLATFORM_DEFINITION,
        "release platform definition",
    )
    advertised_platforms = load_platform_definition(platform_definition_bytes)
    required_controls = {
        BUILDER_PATH,
        DEFAULT_INPUT_DEFINITION,
        DEFAULT_MANIFEST_SCHEMA,
        DEFAULT_PLATFORM_DEFINITION,
    }
    definition_paths = {record["path"] for record in input_definition}
    missing_controls = sorted(required_controls - definition_paths)
    if missing_controls:
        error(
            "certifier input definition omits release-evidence control files: "
            f"{missing_controls}"
        )
    input_files: list[dict[str, str]] = []
    input_contents: dict[str, bytes] = {}
    for record in input_definition:
        contents = require_tag_bound_file(
            root,
            args.tag_commit_sha,
            record["path"],
            f"certifier input {record['path']}",
        )
        input_files.append(
            {
                "path": record["path"],
                "role": record["role"],
                "sha256": sha256_bytes(contents),
            }
        )
        input_contents[record["path"]] = contents
    input_digest_payload = {"schema_version": 1, "files": input_files}

    archive = Path(args.archive)
    expected_archive_name = f"mainframe-{args.version}.tar.gz"
    if archive.name != expected_archive_name:
        error(f"release archive must be named {expected_archive_name}")
    archive_size, archive_sha256 = inspect_runtime_archive(archive, input_contents)

    expected_manifest_asset = f"mainframe-{args.version}.release-evidence.json"
    expected_bundle_asset = f"mainframe-{args.version}.release-evidence.tar.gz"
    if Path(args.manifest).name != expected_manifest_asset:
        error(f"release evidence manifest must be named {expected_manifest_asset}")
    if Path(args.bundle).name != expected_bundle_asset:
        error(f"release evidence bundle must be named {expected_bundle_asset}")

    validator_path = repository_file(root, VALIDATOR_PATH, "evidence validator")
    return {
        "root": root,
        "validator_path": validator_path,
        "manifest_schema_path": repository_file(
            root, args.manifest_schema, "release evidence schema"
        ),
        "manifest_schema": {
            "path": args.manifest_schema,
            "sha256": sha256_bytes(schema_bytes),
        },
        "release": {
            "repository": args.repository,
            "version": args.version,
            "tag": args.tag,
            "tag_ref": args.tag_ref,
            "git_object_format": object_format,
            "tag_ref_sha": args.tag_ref_sha,
            "tag_commit_sha": args.tag_commit_sha,
            "source_date_epoch": source_date_epoch,
            "workflow": {
                "path": workflow_path,
                "sha256": sha256_bytes(workflow_bytes),
                "run_id": args.workflow_run_id,
                "run_attempt": args.workflow_run_attempt,
            },
        },
        "archive": {
            "name": expected_archive_name,
            "media_type": "application/gzip",
            "size_bytes": archive_size,
            "sha256": archive_sha256,
        },
        "certifier_input_bundle": {
            "definition_path": args.certifier_inputs,
            "definition_sha256": sha256_bytes(definition_bytes),
            "canonicalization": CANONICALIZATION,
            "sha256": sha256_bytes(canonical_json(input_digest_payload)),
            "files": input_files,
        },
        "platform_matrix": {
            "definition_path": DEFAULT_PLATFORM_DEFINITION,
            "definition_sha256": sha256_bytes(platform_definition_bytes),
            "platforms": advertised_platforms,
        },
        "publication": {
            "manifest_asset": expected_manifest_asset,
            "certificate_bundle_asset": expected_bundle_asset,
            "attestation_predicate_type": PREDICATE_TYPE,
        },
    }


def load_validator(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("mainframe_evidence_validator", path)
    if spec is None or spec.loader is None:
        error(f"could not load evidence validator: {path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:  # pragma: no cover - import failures are environment-specific
        error(f"could not import evidence validator: {exc}")
    if not callable(getattr(module, "validate", None)):
        error("evidence validator does not expose validate()")
    return module


def validate_document(
    document: Any,
    schema_path: Path,
    validator: Any,
    label: str,
) -> None:
    schema = load_json_bytes(
        read_regular_file(schema_path, f"{label} schema", MAX_JSON_BYTES),
        f"{label} schema",
    )
    if not isinstance(schema, dict):
        error(f"{label} schema root must be an object")
    try:
        validator.validate(schema, document, "$", schema)
    except (ValueError, SystemExit) as exc:
        error(f"{label} failed schema validation: {exc}")


def load_evidence_source(path_value: str, label: str) -> tuple[str, bytes, Any]:
    path = Path(path_value)
    contents = read_regular_file(path, label, MAX_JSON_BYTES)
    return str(path.resolve(strict=True)), contents, load_json_bytes(contents, label)


def analyze_evidence(
    safety_sources: list[tuple[str, bytes, Any]],
    awm_sources: list[tuple[str, bytes, Any]],
    context: dict[str, Any],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, bytes]]:
    if len(safety_sources) != EXPECTED_SAFETY_CERTIFICATES:
        error(
            "release evidence requires exactly "
            f"{EXPECTED_SAFETY_CERTIFICATES} safety certificates, "
            f"got {len(safety_sources)}"
        )
    if len(awm_sources) != EXPECTED_AWM_CERTIFICATES:
        error(
            "release evidence requires exactly "
            f"{EXPECTED_AWM_CERTIFICATES} AWM certificates, got {len(awm_sources)}"
        )
    labels = [label for label, _, _ in safety_sources + awm_sources]
    if len(labels) != len(set(labels)):
        error("the same evidence source was supplied more than once")

    validator = load_validator(context["validator_path"])
    root = context["root"]
    version = context["release"]["version"]
    tag_commit = context["release"]["tag_commit_sha"]
    archive_sha = context["archive"]["sha256"]
    advertised_platforms = {
        (record["os"], record["arch"], record["system_libc"])
        for record in context["platform_matrix"]["platforms"]
    }
    expected_safety_coverage = {
        (host, *platform)
        for host in SAFETY_SCHEMAS
        for platform in advertised_platforms
    }
    safety_records: list[dict[str, Any]] = []
    awm_records: list[dict[str, Any]] = []
    bundle_files: dict[str, bytes] = {}

    for label, contents, document in safety_sources:
        if not isinstance(document, dict):
            error(f"safety evidence root must be an object: {label}")
        host = document.get("host")
        schema_relative = SAFETY_SCHEMAS.get(host)
        if schema_relative is None:
            error(f"unsupported safety evidence host in {label}: {host!r}")
        validate_document(
            document,
            repository_file(root, schema_relative, f"{host} evidence schema"),
            validator,
            f"{host} safety evidence {label}",
        )
        operating_system = document.get("os")
        if operating_system not in ("Darwin", "Linux"):
            error(f"unsupported safety evidence OS in {label}: {operating_system!r}")
        if document.get("certification") != "execution-certified":
            error(f"safety evidence is not execution-certified: {label}")
        if document.get("mainframe_version") != version:
            error(f"safety evidence version does not match release: {label}")
        if document.get("archive_sha256") != archive_sha:
            error(f"safety evidence archive digest does not match release: {label}")
        if document.get("archive_origin") != "workspace-build":
            error(f"safety evidence archive_origin must be workspace-build: {label}")
        if document.get("source_git_commit") != tag_commit:
            error(f"safety evidence source commit does not match release tag: {label}")
        if document.get("source_git_dirty") is not False:
            error(f"safety evidence source checkout was not clean: {label}")
        architecture = document.get("arch")
        if not isinstance(architecture, str) or not architecture:
            error(f"safety evidence architecture is missing: {label}")
        system_libc = document.get("system_libc")
        platform = (operating_system, architecture, system_libc)
        if platform not in advertised_platforms:
            error(
                "safety evidence platform is not advertised for this release: "
                f"{label}: {platform_id(operating_system, architecture, str(system_libc))}"
            )
        legacy_libc = document.get("libc")
        if "libc" in document and legacy_libc != system_libc:
            error(f"safety evidence libc and system_libc disagree: {label}")
        platform_name = platform_id(operating_system, architecture, system_libc)
        bundle_path = f"evidence/safety/{host}-{platform_name}.json"
        if bundle_path in bundle_files:
            error(f"duplicate safety evidence coverage: {host}/{platform_name}")
        bundle_files[bundle_path] = contents
        safety_records.append(
            {
                "path": bundle_path,
                "schema_path": schema_relative,
                "host": host,
                "os": operating_system,
                "arch": architecture,
                "libc": system_libc,
                "system_libc": system_libc,
                "certification": "execution-certified",
                "archive_origin": "workspace-build",
                "source_git_commit": tag_commit,
                "source_git_dirty": False,
                "archive_sha256": archive_sha,
                "evidence_sha256": sha256_bytes(contents),
            }
        )

    safety_coverage = {
        (record["host"], record["os"], record["arch"], record["system_libc"])
        for record in safety_records
    }
    if safety_coverage != expected_safety_coverage:
        missing = sorted(expected_safety_coverage - safety_coverage)
        extras = sorted(safety_coverage - expected_safety_coverage)
        error(f"safety evidence coverage mismatch; missing={missing}, extras={extras}")

    for label, contents, document in awm_sources:
        if not isinstance(document, dict):
            error(f"AWM evidence root must be an object: {label}")
        validate_document(
            document,
            repository_file(root, AWM_SCHEMA, "AWM evidence schema"),
            validator,
            f"AWM evidence {label}",
        )
        mainframe = document.get("mainframe")
        platform = document.get("platform")
        if not isinstance(mainframe, dict) or not isinstance(platform, dict):
            error(f"AWM evidence release or platform binding is malformed: {label}")
        operating_system = platform.get("os")
        if operating_system not in ("Darwin", "Linux"):
            error(f"unsupported AWM evidence OS in {label}: {operating_system!r}")
        if document.get("certification") != "native-awm-chain-execution-certified":
            error(f"AWM evidence is not execution-certified: {label}")
        if mainframe.get("version") != version:
            error(f"AWM evidence version does not match release: {label}")
        if mainframe.get("archive_sha256") != archive_sha:
            error(f"AWM evidence archive digest does not match release: {label}")
        if mainframe.get("archive_origin") != "external-input":
            error(f"AWM evidence archive_origin must remain external-input: {label}")
        architecture = platform.get("arch")
        system_libc = platform.get("system_libc")
        if not isinstance(architecture, str) or not architecture:
            error(f"AWM evidence architecture is missing: {label}")
        platform_tuple = (operating_system, architecture, system_libc)
        if platform_tuple not in advertised_platforms:
            error(
                "AWM evidence platform is not advertised for this release: "
                f"{label}: {platform_id(operating_system, architecture, str(system_libc))}"
            )
        if platform.get("libc") != system_libc:
            error(f"AWM evidence libc and system_libc disagree: {label}")
        platform_name = platform_id(operating_system, architecture, system_libc)
        bundle_path = f"evidence/awm-chain/{platform_name}.json"
        if bundle_path in bundle_files:
            error(f"duplicate AWM evidence coverage: {platform_name}")
        bundle_files[bundle_path] = contents
        awm_records.append(
            {
                "path": bundle_path,
                "schema_path": AWM_SCHEMA,
                "os": operating_system,
                "arch": architecture,
                "libc": system_libc,
                "system_libc": system_libc,
                "certification": "native-awm-chain-execution-certified",
                "archive_origin": "external-input",
                "archive_sha256": archive_sha,
                "evidence_sha256": sha256_bytes(contents),
            }
        )

    awm_coverage = {
        (record["os"], record["arch"], record["system_libc"])
        for record in awm_records
    }
    if awm_coverage != advertised_platforms:
        missing = sorted(advertised_platforms - awm_coverage)
        extras = sorted(awm_coverage - advertised_platforms)
        error(f"AWM evidence coverage mismatch; missing={missing}, extras={extras}")

    safety_records.sort(
        key=lambda record: (
            record["host"],
            record["os"],
            record["arch"],
            record["system_libc"],
        )
    )
    awm_records.sort(
        key=lambda record: (record["os"], record["arch"], record["system_libc"])
    )
    return {"safety": safety_records, "awm_chain": awm_records}, bundle_files


def manifest_for(
    context: dict[str, Any], evidence: dict[str, list[dict[str, Any]]]
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "kind": KIND,
        "manifest_schema": context["manifest_schema"],
        "release": context["release"],
        "archive": context["archive"],
        "certifier_input_bundle": context["certifier_input_bundle"],
        "platform_matrix": context["platform_matrix"],
        "evidence": evidence,
        "publication": context["publication"],
    }


def validate_release_manifest(
    manifest: Any, context: dict[str, Any]
) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        error("release evidence manifest root must be an object")
    validator = load_validator(context["validator_path"])
    validate_document(
        manifest,
        context["manifest_schema_path"],
        validator,
        "release evidence manifest",
    )
    expected_static = {
        "schema_version": 1,
        "kind": KIND,
        "manifest_schema": context["manifest_schema"],
        "release": context["release"],
        "archive": context["archive"],
        "certifier_input_bundle": context["certifier_input_bundle"],
        "platform_matrix": context["platform_matrix"],
        "publication": context["publication"],
    }
    for key, expected in expected_static.items():
        if manifest.get(key) != expected:
            error(f"release evidence manifest {key} binding does not match expected input")
    evidence = manifest.get("evidence")
    if not isinstance(evidence, dict) or set(evidence) != {"safety", "awm_chain"}:
        error("release evidence manifest evidence section is malformed")
    if (
        not isinstance(evidence["safety"], list)
        or len(evidence["safety"]) != EXPECTED_SAFETY_CERTIFICATES
    ):
        error(
            "release evidence manifest must contain exactly "
            f"{EXPECTED_SAFETY_CERTIFICATES} safety records"
        )
    if (
        not isinstance(evidence["awm_chain"], list)
        or len(evidence["awm_chain"]) != EXPECTED_AWM_CERTIFICATES
    ):
        error(
            "release evidence manifest must contain exactly "
            f"{EXPECTED_AWM_CERTIFICATES} AWM records"
        )
    paths = [record.get("path") for record in evidence["safety"] + evidence["awm_chain"]]
    if len(paths) != len(set(paths)) or any(not isinstance(path, str) for path in paths):
        error("release evidence manifest paths must be strings and unique")
    for path in paths:
        validate_relative_path(path, "release evidence bundle path")
    return manifest


def build_tar_stream(entries: dict[str, bytes], source_date_epoch: int) -> bytes:
    names = sorted(entries)
    if not names or len(names) != len(set(names)):
        error("release evidence bundle inventory must be non-empty and unique")
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name in names:
            validate_relative_path(name, "release evidence tar member")
            contents = entries[name]
            info = tarfile.TarInfo(name)
            info.size = len(contents)
            info.mode = 0o644
            info.mtime = source_date_epoch
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            info.type = tarfile.REGTYPE
            archive.addfile(info, io.BytesIO(contents))
    return output.getvalue()


def stored_gzip(contents: bytes, source_date_epoch: int) -> bytes:
    output = io.BytesIO()
    output.write(b"\x1f\x8b\x08\x00")
    output.write(struct.pack("<I", source_date_epoch))
    output.write(b"\x00\xff")
    checksum = 0
    total_size = 0
    offset = 0
    if not contents:
        output.write(b"\x01\x00\x00\xff\xff")
    while offset < len(contents):
        chunk = contents[offset : offset + 65535]
        offset += len(chunk)
        final = offset == len(contents)
        output.write(b"\x01" if final else b"\x00")
        output.write(struct.pack("<HH", len(chunk), len(chunk) ^ 0xFFFF))
        output.write(chunk)
        checksum = binascii.crc32(chunk, checksum)
        total_size = (total_size + len(chunk)) & 0xFFFFFFFF
    output.write(struct.pack("<II", checksum & 0xFFFFFFFF, total_size))
    return output.getvalue()


def build_bundle(
    manifest_bytes: bytes,
    evidence_files: dict[str, bytes],
    source_date_epoch: int,
) -> bytes:
    entries = {"release-evidence.json": manifest_bytes, **evidence_files}
    if len(entries) != EXPECTED_BUNDLE_FILE_COUNT:
        error(
            "release evidence bundle must contain exactly "
            f"{EXPECTED_BUNDLE_FILE_COUNT} files, got {len(entries)}"
        )
    expanded = sum(len(contents) for contents in entries.values())
    if expanded > MAX_BUNDLE_EXPANDED_BYTES:
        error("release evidence bundle exceeds the expanded size limit")
    bundle = stored_gzip(build_tar_stream(entries, source_date_epoch), source_date_epoch)
    if len(bundle) > MAX_BUNDLE_BYTES:
        error("release evidence bundle exceeds the compressed size limit")
    return bundle


def parse_bundle(
    bundle_bytes: bytes,
    expected_names: set[str],
    source_date_epoch: int,
) -> dict[str, bytes]:
    if len(bundle_bytes) > MAX_BUNDLE_BYTES:
        error("release evidence bundle exceeds the compressed size limit")
    entries: dict[str, bytes] = {}
    member_names: list[str] = []
    expanded = 0
    try:
        with tarfile.open(fileobj=io.BytesIO(bundle_bytes), mode="r|gz") as archive:
            for member in archive:
                if len(member_names) >= MAX_BUNDLE_MEMBERS:
                    error("release evidence bundle has too many members")
                name = member.name
                validate_relative_path(name, "release evidence bundle member")
                if name in entries:
                    error(f"duplicate release evidence bundle member: {name}")
                member_names.append(name)
                if not member.isfile():
                    error(f"release evidence bundle member is not a regular file: {name}")
                if stat.S_IMODE(member.mode) != 0o644:
                    error(f"release evidence bundle member mode is not 0644: {name}")
                if member.mtime != source_date_epoch:
                    error(f"release evidence bundle member timestamp is not deterministic: {name}")
                if member.uid != 0 or member.gid != 0 or member.uname or member.gname:
                    error(f"release evidence bundle member ownership is not normalized: {name}")
                if member.linkname or member.pax_headers:
                    error(f"release evidence bundle member has unsupported metadata: {name}")
                if member.size < 0 or member.size > MAX_JSON_BYTES:
                    error(f"release evidence bundle member size is invalid: {name}")
                expanded += member.size
                if expanded > MAX_BUNDLE_EXPANDED_BYTES:
                    error("release evidence bundle exceeds the expanded size limit")
                source = archive.extractfile(member)
                if source is None:
                    error(f"release evidence bundle member has no contents: {name}")
                contents = source.read(MAX_JSON_BYTES + 1)
                source.close()
                if len(contents) != member.size:
                    error(f"release evidence bundle member is truncated: {name}")
                entries[name] = contents
    except (tarfile.TarError, EOFError, OSError) as exc:
        error(f"release evidence bundle is not a valid gzip-compressed tar: {exc}")
    if member_names != sorted(member_names):
        error("release evidence bundle members are not deterministically ordered")
    actual_names = set(entries)
    if actual_names != expected_names:
        missing = sorted(expected_names - actual_names)
        extras = sorted(actual_names - expected_names)
        error(f"release evidence bundle inventory mismatch; missing={missing}, extras={extras}")
    expected_bundle = stored_gzip(
        build_tar_stream(entries, source_date_epoch), source_date_epoch
    )
    if bundle_bytes != expected_bundle:
        error("release evidence bundle bytes are not in canonical deterministic form")
    return entries


def evidence_sources_from_bundle(
    entries: dict[str, bytes],
) -> tuple[list[tuple[str, bytes, Any]], list[tuple[str, bytes, Any]]]:
    safety: list[tuple[str, bytes, Any]] = []
    awm: list[tuple[str, bytes, Any]] = []
    for name, contents in entries.items():
        if name == "release-evidence.json":
            continue
        document = load_json_bytes(contents, f"bundled evidence {name}")
        item = (name, contents, document)
        if name.startswith("evidence/safety/"):
            safety.append(item)
        elif name.startswith("evidence/awm-chain/"):
            awm.append(item)
        else:
            error(f"unexpected release evidence bundle path: {name}")
    return safety, awm


def verify_payload(
    manifest_bytes: bytes,
    bundle_bytes: bytes,
    context: dict[str, Any],
) -> dict[str, str]:
    manifest = validate_release_manifest(
        load_json_bytes(manifest_bytes, "release evidence manifest"), context
    )
    evidence_records = manifest["evidence"]["safety"] + manifest["evidence"]["awm_chain"]
    expected_names = {"release-evidence.json"}
    expected_names.update(record["path"] for record in evidence_records)
    if len(expected_names) != EXPECTED_BUNDLE_FILE_COUNT:
        error(
            "release evidence manifest does not describe exactly "
            f"{EXPECTED_CERTIFICATE_COUNT} unique certificates"
        )
    entries = parse_bundle(
        bundle_bytes,
        expected_names,
        context["release"]["source_date_epoch"],
    )
    if entries["release-evidence.json"] != manifest_bytes:
        error("bundled release evidence manifest is not byte-equal to the published manifest")
    safety_sources, awm_sources = evidence_sources_from_bundle(entries)
    recomputed, _ = analyze_evidence(safety_sources, awm_sources, context)
    if manifest["evidence"] != recomputed:
        error("release evidence records do not match the bundled certificate bytes")
    return {
        "manifest_sha256": sha256_bytes(manifest_bytes),
        "bundle_sha256": sha256_bytes(bundle_bytes),
    }


def output_path(path_value: str, label: str) -> Path:
    requested = Path(path_value)
    try:
        parent = requested.parent.resolve(strict=True)
    except OSError as exc:
        error(f"{label} parent directory is unavailable: {requested.parent}: {exc}")
    if not parent.is_dir():
        error(f"{label} parent must be a directory: {requested.parent}")
    candidate = parent / requested.name
    if candidate.exists() or candidate.is_symlink():
        error(f"refusing to overwrite existing {label}: {candidate}")
    return candidate


def write_new_file(path: Path, contents: bytes, label: str) -> None:
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", dir=path.parent, delete=False
        ) as handle:
            temporary_name = handle.name
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o644)
        os.link(temporary_name, path)
        os.unlink(temporary_name)
        temporary_name = None
    except FileExistsError:
        error(f"refusing to overwrite existing {label}: {path}")
    except OSError as exc:
        error(f"could not write {label}: {path}: {exc}")
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def create_command(args: argparse.Namespace) -> int:
    context = build_context(args)
    manifest_path = output_path(args.manifest, "release evidence manifest")
    bundle_path = output_path(args.bundle, "release evidence bundle")
    if manifest_path == bundle_path:
        error("manifest and bundle output paths must differ")
    safety_sources = [
        load_evidence_source(path, f"safety evidence {path}")
        for path in args.safety_evidence
    ]
    awm_sources = [
        load_evidence_source(path, f"AWM evidence {path}")
        for path in args.awm_evidence
    ]
    evidence, bundle_files = analyze_evidence(safety_sources, awm_sources, context)
    manifest_bytes = pretty_json(manifest_for(context, evidence))
    bundle_bytes = build_bundle(
        manifest_bytes,
        bundle_files,
        context["release"]["source_date_epoch"],
    )
    result = verify_payload(manifest_bytes, bundle_bytes, context)
    write_new_file(bundle_path, bundle_bytes, "release evidence bundle")
    try:
        write_new_file(manifest_path, manifest_bytes, "release evidence manifest")
    except ReleaseEvidenceError:
        try:
            bundle_path.unlink()
        except OSError:
            pass
        raise
    print(
        json.dumps(
            {
                "status": "created",
                "manifest": str(manifest_path),
                "bundle": str(bundle_path),
                **result,
            },
            sort_keys=True,
        )
    )
    return 0


def verify_command(args: argparse.Namespace) -> int:
    context = build_context(args)
    manifest_path = Path(args.manifest)
    bundle_path = Path(args.bundle)
    manifest_bytes = read_regular_file(
        manifest_path, "release evidence manifest", MAX_JSON_BYTES
    )
    bundle_bytes = read_regular_file(
        bundle_path, "release evidence bundle", MAX_BUNDLE_BYTES
    )
    result = verify_payload(manifest_bytes, bundle_bytes, context)
    print(
        json.dumps(
            {
                "status": "valid",
                "manifest": str(manifest_path.resolve(strict=True)),
                "bundle": str(bundle_path.resolve(strict=True)),
                **result,
            },
            sort_keys=True,
        )
    )
    return 0


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    default_root = str(Path(__file__).resolve().parents[3])
    parser.add_argument("--repo-root", default=default_root)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--tag-ref", required=True)
    parser.add_argument("--tag-ref-sha", required=True)
    parser.add_argument("--tag-commit-sha", required=True)
    parser.add_argument("--workflow-path", default=DEFAULT_WORKFLOW)
    parser.add_argument("--workflow-run-id", required=True)
    parser.add_argument("--workflow-run-attempt", type=int, required=True)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--certifier-inputs", default=DEFAULT_INPUT_DEFINITION)
    parser.add_argument("--manifest-schema", default=DEFAULT_MANIFEST_SCHEMA)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Create or verify a deterministic MAINFRAME release-evidence manifest "
            "and certificate bundle."
        )
    )
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create", help="create new no-clobber evidence assets")
    add_common_arguments(create)
    create.add_argument("--safety-evidence", action="append", default=[], metavar="PATH")
    create.add_argument("--awm-evidence", action="append", default=[], metavar="PATH")
    create.set_defaults(handler=create_command)
    verify = commands.add_parser("verify", help="verify existing evidence assets")
    add_common_arguments(verify)
    verify.set_defaults(handler=verify_command)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.handler(args)
    except ReleaseEvidenceError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

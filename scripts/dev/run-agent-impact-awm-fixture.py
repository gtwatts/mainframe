#!/usr/bin/env python3
"""Run one credentials-free Pi -> MAINFRAME AWM transition fixture.

This is an explicit local execution command.  It never starts an agent or a
provider.  It extracts the preregistered MAINFRAME archive into a fresh private
directory, invokes the driver shipped in that archive with Pi's real extension
loader, and writes one private raw record.  Receipt preparation and verification
are deliberately separate, offline-only operations.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
from typing import Any, NoReturn


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
CLAIM_SCOPE = "synthetic-treatment-investigate-awm-mechanism-conformance-only"
REQUEST_KIND = "mainframe-agent-impact-pi-awm-transition-request"
RAW_KIND = "mainframe-agent-impact-pi-awm-transition-private-record"
TREE_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 640 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 10_000
MAX_EXPANDED_BYTES = 512 * 1024 * 1024
MAX_TAR_STREAM_BYTES = MAX_EXPANDED_BYTES + (MAX_ARCHIVE_MEMBERS * 2048) + (1024 * 1024)
MAX_RECORD_BYTES = 16 * 1024 * 1024
MAX_DEPTH = 64
MAX_ITEMS = 200_000
MAX_CONTEXT_BYTES = 8192
MIN_TIMEOUT_SECONDS = 10
MAX_TIMEOUT_SECONDS = 300
SAFE_PATH = "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PAIR_RE = re.compile(r"^pair-[0-9a-f]{16}$")
ARM_RE = re.compile(r"^arm-[0-9a-f]{16}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,127}$")
MODE_RE = re.compile(r"^0[0-7]{3}$")
BASH_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+\([0-9]+\)-release$")
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
RUNTIME_OBSERVED_KEYS = (
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
    "bash_executable",
    "bash_executable_sha256",
    "bash_version",
    "node_executable",
    "node_executable_sha256",
    "node_version",
    "registered_tools",
    "loaded_mainframe_awm",
    "network_api_guards",
    "provider_adapter_loaded",
    "provider_inference_requests",
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
EXPECTED_NON_CLAIMS = {
    "real_provider_inference": "not-run",
    "live_agent_sessions": 0,
    "agent_quality": "not-measured",
    "comparative_agent_performance": "not-measured",
    "developer_productivity": "not-measured",
    "machine_safety": "not-established",
    "network_containment": "best-effort-node-api-guards-not-os-isolation",
}


class FixtureError(RuntimeError):
    """A fail-closed mechanism-fixture error."""


def die(message: str) -> NoReturn:
    raise FixtureError(message)


def exact_keys(value: Any, keys: tuple[str, ...], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        die(f"{label} must be a JSON object")
    expected = set(keys)
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        die(f"{label} has invalid keys (missing={missing}, extra={extra})")
    return value


def reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            die(f"JSON contains duplicate key: {key}")
        result[key] = value
    return result


def reject_nonfinite(value: str) -> NoReturn:
    die(f"JSON contains non-finite number: {value}")


def enforce_json_bounds(value: Any) -> None:
    stack: list[tuple[Any, int]] = [(value, 1)]
    count = 0
    while stack:
        current, depth = stack.pop()
        count += 1
        if count > MAX_ITEMS:
            die("JSON contains too many values")
        if depth > MAX_DEPTH:
            die("JSON nesting is too deep")
        if isinstance(current, dict):
            stack.extend((item, depth + 1) for item in current.values())
        elif isinstance(current, list):
            stack.extend((item, depth + 1) for item in current)


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        die(f"value cannot be encoded as canonical JSON: {error}")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require_real_directory(path: pathlib.Path, label: str, mode: int | None = None) -> pathlib.Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die(f"{label} is unavailable: {path}: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        die(f"{label} must be a real directory: {path}")
    resolved = path.resolve(strict=True)
    if mode is not None and stat.S_IMODE(metadata.st_mode) != mode:
        die(f"{label} mode must be exactly {mode:04o}: {resolved}")
    return resolved


def require_regular_file(
    path: pathlib.Path,
    label: str,
    maximum_bytes: int | None = MAX_JSON_BYTES,
    mode: int | None = None,
    executable: bool = False,
) -> pathlib.Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die(f"{label} is unavailable: {path}: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die(f"{label} must be a regular, non-symlink file: {path}")
    if metadata.st_nlink != 1:
        die(f"{label} must not be hard-linked: {path}")
    if metadata.st_size <= 0:
        die(f"{label} must not be empty: {path}")
    if maximum_bytes is not None and metadata.st_size > maximum_bytes:
        die(f"{label} exceeds its size limit: {path}")
    if mode is not None and stat.S_IMODE(metadata.st_mode) != mode:
        die(f"{label} mode must be exactly {mode:04o}: {path}")
    if executable and not os.access(path, os.X_OK):
        die(f"{label} must be executable: {path}")
    return path.resolve(strict=True)


def read_file(path: pathlib.Path, label: str, maximum_bytes: int | None = MAX_JSON_BYTES) -> bytes:
    path = require_regular_file(path, label, maximum_bytes=maximum_bytes)
    initial = path.lstat()
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        opened = os.fstat(descriptor)
        identity = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if any(getattr(opened, field) != getattr(initial, field) for field in identity):
            die(f"{label} changed before it was read: {path}")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if maximum_bytes is not None and total > maximum_bytes:
                die(f"{label} exceeds its size limit: {path}")
            chunks.append(chunk)
        final = os.fstat(descriptor)
        if total != opened.st_size or any(
            getattr(final, field) != getattr(opened, field) for field in identity
        ):
            die(f"{label} changed while it was read: {path}")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def sha256_file(path: pathlib.Path, label: str) -> str:
    return sha256_bytes(read_file(path, label, maximum_bytes=None))


def load_json(path: pathlib.Path, label: str, mode: int | None = None) -> tuple[Any, bytes]:
    path = require_regular_file(path, label, mode=mode)
    payload = read_file(path, label)
    try:
        text = payload.decode("utf-8", errors="strict")
        value = json.loads(
            text,
            object_pairs_hook=reject_duplicate_pairs,
            parse_constant=reject_nonfinite,
        )
    except FixtureError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        die(f"{label} is not strict UTF-8 JSON: {error}")
    enforce_json_bounds(value)
    return value, payload


def require_string(value: Any, label: str, pattern: re.Pattern[str] | None = None) -> str:
    if not isinstance(value, str) or not value:
        die(f"{label} must be a non-empty string")
    if pattern is not None and pattern.fullmatch(value) is None:
        die(f"{label} has an invalid format")
    return value


def require_integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        die(f"{label} must be an integer >= {minimum}")
    return value


def require_exact(value: Any, expected: Any, label: str) -> Any:
    if type(value) is not type(expected) or value != expected:
        die(f"{label} must equal {expected!r} with the exact JSON type")
    return value


def mode_text(path: pathlib.Path) -> str:
    return f"{stat.S_IMODE(path.lstat().st_mode):04o}"


def safe_relative_path(value: Any, label: str) -> pathlib.PurePosixPath:
    value = require_string(value, label)
    relative = pathlib.PurePosixPath(value)
    if (
        relative.is_absolute()
        or value != relative.as_posix()
        or "\\" in value
        or any(part in ("", ".", "..") for part in relative.parts)
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        die(f"{label} must be a canonical relative POSIX path")
    return relative


def validate_preregistered_release_files(
    archive_value: str,
    release: dict[str, Any],
) -> pathlib.Path:
    archive_relative = safe_relative_path(release["archive_path"], "release archive path")
    sidecar_relative = safe_relative_path(
        release["checksum_sidecar_path"],
        "release checksum sidecar path",
    )
    archive_mode = require_string(release["archive_mode"], "release archive mode", MODE_RE)
    sidecar_mode = require_string(
        release["checksum_sidecar_mode"],
        "release checksum sidecar mode",
        MODE_RE,
    )
    archive = require_regular_file(
        pathlib.Path(archive_value),
        "release archive",
        maximum_bytes=MAX_ARCHIVE_BYTES,
    )
    suffix = archive_relative.parts
    if tuple(archive.parts[-len(suffix) :]) != suffix:
        die("release archive path does not match the preregistration binding")
    study_root = require_real_directory(
        archive.parents[len(suffix) - 1],
        "preregistered study root",
    )
    if mode_text(archive) != archive_mode:
        die("release archive mode does not match the preregistration binding")
    sidecar = require_regular_file(
        study_root.joinpath(*sidecar_relative.parts),
        "release checksum sidecar",
        maximum_bytes=4096,
    )
    if sidecar == archive:
        die("release archive and checksum sidecar must be different files")
    if mode_text(sidecar) != sidecar_mode:
        die("release checksum sidecar mode does not match the preregistration binding")
    sidecar_payload = read_file(sidecar, "release checksum sidecar", maximum_bytes=4096)
    if sha256_bytes(sidecar_payload) != release["checksum_sidecar_sha256"]:
        die("release checksum sidecar does not match the preregistration binding")
    try:
        sidecar_text = sidecar_payload.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        die(f"release checksum sidecar must be ASCII: {error}")
    match = re.fullmatch(
        r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._+-]*)\n?",
        sidecar_text,
    )
    if match is None:
        die("release checksum sidecar must contain exactly one canonical record")
    if match.group(1) != release["archive_sha256"] or match.group(2) != archive.name:
        die("release checksum sidecar record differs from the bound archive")
    return archive


def validate_private_assignments(value: Any) -> dict[str, Any]:
    assignments = exact_keys(
        value,
        (
            "schema_version",
            "kind",
            "study_id",
            "study_spec_sha256",
            "corpus_sha256",
            "randomization_context_sha256",
            "seed_commitment_sha256",
            "assignments",
        ),
        "private assignments",
    )
    require_exact(assignments["schema_version"], 2, "private assignment schema version")
    if assignments["kind"] != "mainframe-agent-impact-live-assignments":
        die("private assignment kind is invalid")
    require_string(assignments["study_id"], "assignment study id", ID_RE)
    for field in (
        "study_spec_sha256",
        "corpus_sha256",
        "randomization_context_sha256",
        "seed_commitment_sha256",
    ):
        require_string(assignments[field], f"assignment {field}", SHA256_RE)
    rows = assignments["assignments"]
    if not isinstance(rows, list) or not rows or len(rows) > 100_000:
        die("private assignments must contain a bounded non-empty row list")
    seen_pairs: set[str] = set()
    seen_arms: set[str] = set()
    seen_task_replicates: set[tuple[str, int]] = set()
    for index, row_value in enumerate(rows):
        row = exact_keys(
            row_value,
            ("pair_id", "task_id", "replicate", "arms"),
            f"private assignment row {index}",
        )
        pair_id = require_string(row["pair_id"], "assignment pair id", PAIR_RE)
        task_id = require_string(row["task_id"], "assignment task id", ID_RE)
        replicate = require_integer(row["replicate"], "assignment replicate", 1)
        if replicate > 1000:
            die("assignment replicate must not exceed 1000")
        if pair_id in seen_pairs:
            die("private assignments contain a duplicate pair id")
        seen_pairs.add(pair_id)
        task_replicate = (task_id, replicate)
        if task_replicate in seen_task_replicates:
            die("private assignments contain a duplicate task/replicate pair")
        seen_task_replicates.add(task_replicate)
        arms = row["arms"]
        if not isinstance(arms, list) or len(arms) != 2:
            die("each private assignment must contain exactly two arms")
        modes: list[str] = []
        for arm_value in arms:
            arm = exact_keys(arm_value, ("opaque_arm_id", "mode"), "private arm")
            arm_id = require_string(arm["opaque_arm_id"], "opaque arm id", ARM_RE)
            if arm_id in seen_arms:
                die("private assignments contain a duplicate opaque arm id")
            seen_arms.add(arm_id)
            if arm["mode"] not in ("control", "treatment"):
                die("private arm mode is invalid")
            modes.append(arm["mode"])
        if sorted(modes) != ["control", "treatment"]:
            die("each pair must map exactly one control and one treatment arm")
    return assignments


def select_treatment_binding(
    preregistration: Any,
    assignments: dict[str, Any],
    pair_id: str,
    opaque_arm_id: str,
    preregistration_sha256: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    prereg = exact_keys(
        preregistration,
        (
            "schema_version",
            "kind",
            "study_id",
            "title",
            "claim_scope",
            "execution_status",
            "non_claims",
            "design",
            "bindings",
            "randomization_context_sha256",
            "seed_commitment_sha256",
            "assignment_commitment_sha256",
            "planned_pair_count",
            "pairs",
        ),
        "preregistration",
    )
    require_exact(prereg["schema_version"], 2, "preregistration schema version")
    if prereg["kind"] != "mainframe-agent-impact-preregistration":
        die("preregistration kind or schema version is invalid")
    if prereg["claim_scope"] != "preregistered-live-study-not-run" or prereg["execution_status"] != "not-run":
        die("receipt fixture requires an unexecuted live-study preregistration")
    study_id = require_string(prereg["study_id"], "preregistration study id", ID_RE)
    if assignments["study_id"] != study_id:
        die("private assignments do not belong to the preregistration study")
    for field in (
        "randomization_context_sha256",
        "seed_commitment_sha256",
        "assignment_commitment_sha256",
    ):
        require_string(prereg[field], f"preregistration {field}", SHA256_RE)
    assignment_commitment = sha256_bytes(canonical_bytes(assignments))
    if prereg["assignment_commitment_sha256"] != assignment_commitment:
        die("private assignments do not match the preregistration commitment")
    if prereg["randomization_context_sha256"] != assignments["randomization_context_sha256"]:
        die("randomization context differs between preregistration and assignments")
    if prereg["seed_commitment_sha256"] != assignments["seed_commitment_sha256"]:
        die("seed commitment differs between preregistration and assignments")

    bindings = prereg.get("bindings")
    if not isinstance(bindings, dict):
        die("preregistration bindings are missing")
    study_spec = exact_keys(
        bindings.get("study_spec"),
        ("path", "mode", "sha256"),
        "preregistered study specification",
    )
    safe_relative_path(study_spec["path"], "study specification path")
    require_string(study_spec["mode"], "study specification mode", MODE_RE)
    require_string(study_spec["sha256"], "study specification digest", SHA256_RE)
    corpus = bindings.get("corpus")
    if not isinstance(corpus, dict):
        die("preregistration corpus binding is missing")
    corpus_sha256 = require_string(
        corpus.get("corpus_sha256"),
        "preregistered corpus digest",
        SHA256_RE,
    )
    corpus_body = dict(corpus)
    corpus_body.pop("corpus_sha256")
    if sha256_bytes(canonical_bytes(corpus_body)) != corpus_sha256:
        die("preregistration corpus digest does not reproduce")
    if assignments["study_spec_sha256"] != study_spec["sha256"]:
        die("private assignments study specification digest differs from the preregistration")
    if assignments["corpus_sha256"] != corpus_sha256:
        die("private assignments corpus digest differs from the preregistration")
    expected_randomization = sha256_bytes(
        canonical_bytes(
            {
                "domain": "mainframe-agent-impact-live-v2-randomization-context",
                "study_id": study_id,
                "bindings": bindings,
            }
        )
    )
    if prereg["randomization_context_sha256"] != expected_randomization:
        die("preregistration randomization context digest does not reproduce")

    corpus_tasks = corpus.get("tasks")
    if not isinstance(corpus_tasks, list) or not corpus_tasks:
        die("preregistration corpus must bind at least one task")
    task_bundles: dict[str, str] = {}
    for index, task in enumerate(corpus_tasks):
        if not isinstance(task, dict):
            die(f"preregistered corpus task {index} must be an object")
        task_id_value = require_string(task.get("task_id"), "corpus task id", ID_RE)
        task_bundle = require_string(
            task.get("task_bundle_sha256"),
            "corpus task bundle digest",
            SHA256_RE,
        )
        if task_id_value in task_bundles:
            die("preregistration corpus contains a duplicate task id")
        task_bundles[task_id_value] = task_bundle

    pair_budget = exact_keys(
        prereg.get("design", {}).get("budgets") if isinstance(prereg.get("design"), dict) else None,
        (
            "wall_seconds_per_phase",
            "maximum_tool_calls_per_phase",
            "maximum_context_bytes",
            "maximum_input_tokens_per_phase",
            "maximum_output_tokens_per_phase",
            "maximum_cost_usd_per_pair",
        ),
        "preregistered design budgets",
    )
    for field in (
        "maximum_tool_calls_per_phase",
        "maximum_context_bytes",
        "maximum_input_tokens_per_phase",
        "maximum_output_tokens_per_phase",
    ):
        require_integer(pair_budget[field], f"design budget {field}", 1)
    for field in ("wall_seconds_per_phase", "maximum_cost_usd_per_pair"):
        value = pair_budget[field]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
            die(f"design budget {field} must be a positive JSON number")
    if require_integer(pair_budget["maximum_context_bytes"], "maximum context bytes", 1) != MAX_CONTEXT_BYTES:
        die(f"synthetic transition contract requires exactly {MAX_CONTEXT_BYTES} context bytes")

    planned_pair_count = require_integer(prereg["planned_pair_count"], "planned pair count", 1)
    public_pairs = prereg["pairs"]
    private_pairs = assignments["assignments"]
    if (
        not isinstance(public_pairs, list)
        or len(public_pairs) != planned_pair_count
        or len(private_pairs) != planned_pair_count
    ):
        die("public and private schedules must cover every planned pair")
    public_by_id: dict[str, dict[str, Any]] = {}
    private_by_id = {row["pair_id"]: row for row in private_pairs}
    seen_task_replicates: set[tuple[str, int]] = set()
    seen_public_arms: set[str] = set()
    for index, public_value in enumerate(public_pairs):
        public = exact_keys(
            public_value,
            ("pair_id", "task_id", "replicate", "instance_sha256", "opaque_arm_order", "budgets"),
            f"public pair {index}",
        )
        public_id = require_string(public["pair_id"], "public pair id", PAIR_RE)
        public_task = require_string(public["task_id"], "public task id", ID_RE)
        public_replicate = require_integer(public["replicate"], "public replicate", 1)
        if public_replicate > 1000:
            die("public replicate must not exceed 1000")
        if public_id in public_by_id:
            die("preregistration contains a duplicate public pair id")
        task_replicate = (public_task, public_replicate)
        if task_replicate in seen_task_replicates:
            die("preregistration contains a duplicate public task/replicate pair")
        seen_task_replicates.add(task_replicate)
        if public_task not in task_bundles:
            die("public pair names a task absent from the corpus binding")
        expected_instance = sha256_bytes(
            canonical_bytes(
                {
                    "task_bundle_sha256": task_bundles[public_task],
                    "replicate": public_replicate,
                }
            )
        )
        if require_string(public["instance_sha256"], "pair instance digest", SHA256_RE) != expected_instance:
            die("public pair instance digest does not reproduce")
        arm_order = public["opaque_arm_order"]
        if not isinstance(arm_order, list) or len(arm_order) != 2:
            die("public pair must contain exactly two opaque arm ids")
        for arm in arm_order:
            arm_id = require_string(arm, "public opaque arm id", ARM_RE)
            if arm_id in seen_public_arms:
                die("preregistration contains a duplicate public opaque arm id")
            seen_public_arms.add(arm_id)
        if canonical_bytes(public["budgets"]) != canonical_bytes(pair_budget):
            die("public pair budgets do not exactly match the preregistered design")
        private = private_by_id.get(public_id)
        if private is None:
            die("public pair is absent from the private assignment reveal")
        if public_task != private["task_id"] or public_replicate != private["replicate"]:
            die("public and private pair identities differ")
        if arm_order != [arm["opaque_arm_id"] for arm in private["arms"]]:
            die("public opaque arm order differs from the private assignment reveal")
        public_by_id[public_id] = public
    if set(public_by_id) != set(private_by_id):
        die("public and private schedules contain different pair ids")

    public_pair = public_by_id.get(pair_id)
    private_pair = private_by_id.get(pair_id)
    if public_pair is None or private_pair is None:
        die("selected pair is absent from the committed schedule")
    selected_arm = next(
        (arm for arm in private_pair["arms"] if arm["opaque_arm_id"] == opaque_arm_id),
        None,
    )
    if selected_arm is None:
        die("selected opaque arm does not belong to the selected pair")
    if selected_arm["mode"] != "treatment":
        die("AWM transition fixture requires the committed treatment arm")

    release = exact_keys(
        bindings.get("mainframe_release"),
        (
            "archive_path",
            "archive_mode",
            "archive_sha256",
            "checksum_sidecar_path",
            "checksum_sidecar_mode",
            "checksum_sidecar_sha256",
            "installed_tree_algorithm",
            "installed_tree_sha256",
        ),
        "preregistered MAINFRAME release",
    )
    if release["installed_tree_algorithm"] != "mainframe-package-tree-sha256-v1":
        die("unsupported preregistered installed-tree algorithm")
    safe_relative_path(release["archive_path"], "release archive path")
    safe_relative_path(release["checksum_sidecar_path"], "release checksum sidecar path")
    require_string(release["archive_mode"], "release archive mode", MODE_RE)
    require_string(release["checksum_sidecar_mode"], "release checksum sidecar mode", MODE_RE)
    for field in ("archive_sha256", "checksum_sidecar_sha256", "installed_tree_sha256"):
        require_string(release[field], f"release {field}", SHA256_RE)
    policies = bindings.get("policies")
    if not isinstance(policies, dict):
        die("preregistration policy bindings are missing")
    policy = policies.get("awm_mechanism_contract")
    controls = policy.get("controls") if isinstance(policy, dict) else None
    if not isinstance(controls, dict) or controls.get("treatment_intervention") != "mainframe-awm-handoff":
        die("preregistration does not bind the MAINFRAME AWM treatment intervention")
    if controls.get("context_limit_unit") != "bytes-under-LC_ALL-C":
        die("preregistration does not bind the byte-based context limit")

    binding = {
        "preregistration_sha256": preregistration_sha256,
        "randomization_context_sha256": prereg["randomization_context_sha256"],
        "assignment_commitment_sha256": assignment_commitment,
        "study_id": study_id,
        "pair_id": pair_id,
        "task_id": public_pair["task_id"],
        "replicate": public_pair["replicate"],
        "instance_sha256": public_pair["instance_sha256"],
        "opaque_arm_id": opaque_arm_id,
        "arm_mode": "treatment",
        "phase": "investigate",
    }
    return binding, release


class BoundedReader:
    def __init__(self, source: gzip.GzipFile, limit: int) -> None:
        self.source = source
        self.limit = limit
        self.consumed = 0

    def read(self, size: int = -1) -> bytes:
        remaining = self.limit - self.consumed
        request = remaining + 1 if size < 0 else min(size, remaining + 1)
        data = self.source.read(request)
        self.consumed += len(data)
        if self.consumed > self.limit:
            die("release archive tar stream exceeds the size limit")
        return data


def safe_member_path(member: tarfile.TarInfo) -> pathlib.PurePosixPath:
    path = pathlib.PurePosixPath(member.name)
    source_name = member.name.rstrip("/") if member.isdir() else member.name
    if (
        not source_name
        or path.is_absolute()
        or ".." in path.parts
        or "." in path.parts
        or "\\" in member.name
        or source_name != path.as_posix()
        or any(ord(character) < 32 or ord(character) == 127 for character in member.name)
    ):
        die(f"unsafe release archive path: {member.name!r}")
    return path


def safe_extract(archive: pathlib.Path, destination: pathlib.Path) -> None:
    archive = require_regular_file(archive, "release archive", maximum_bytes=MAX_ARCHIVE_BYTES)
    destination = require_real_directory(destination, "release destination", mode=0o700)
    if any(destination.iterdir()):
        die("release destination must be empty")
    names: set[str] = set()
    member_count = 0
    expanded = 0
    with archive.open("rb") as compressed:
        with gzip.GzipFile(fileobj=compressed, mode="rb") as uncompressed:
            bounded = BoundedReader(uncompressed, MAX_TAR_STREAM_BYTES)
            with tarfile.open(fileobj=bounded, mode="r|") as handle:
                for member in handle:
                    member_count += 1
                    if member_count > MAX_ARCHIVE_MEMBERS:
                        die("release archive has too many entries")
                    relative = safe_member_path(member)
                    canonical = relative.as_posix()
                    if canonical in names:
                        die(f"duplicate release archive path: {canonical}")
                    names.add(canonical)
                    if not (member.isfile() or member.isdir()):
                        die(f"unsupported release archive entry: {canonical}")
                    mode = member.mode & 0o7777
                    allowed = {0o644, 0o755} if member.isfile() else {0o755}
                    if mode not in allowed:
                        die(f"unsupported release archive mode {mode:o}: {canonical}")
                    target = destination.joinpath(*relative.parts)
                    if member.isdir():
                        target.mkdir(mode=0o700, parents=True, exist_ok=True)
                        target.chmod(mode)
                        continue
                    expanded += member.size
                    if expanded > MAX_EXPANDED_BYTES:
                        die("release archive expands beyond the size limit")
                    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    source = handle.extractfile(member)
                    if source is None:
                        die(f"release archive file has no data: {canonical}")
                    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                    if hasattr(os, "O_NOFOLLOW"):
                        flags |= os.O_NOFOLLOW
                    descriptor = os.open(target, flags, 0o600)
                    remaining = member.size
                    try:
                        with os.fdopen(descriptor, "wb") as output:
                            while remaining:
                                chunk = source.read(min(1024 * 1024, remaining))
                                if not chunk:
                                    die(f"truncated release archive file: {canonical}")
                                output.write(chunk)
                                remaining -= len(chunk)
                            output.flush()
                            os.fsync(output.fileno())
                    finally:
                        source.close()
                    target.chmod(mode)
    if member_count == 0:
        die("release archive is empty")


def package_tree_sha256(root: pathlib.Path) -> str:
    root = require_real_directory(root, "extracted MAINFRAME root")
    entries: list[tuple[str, pathlib.Path, os.stat_result]] = []
    for current, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current_path = pathlib.Path(current)
        for name in directory_names + file_names:
            path = current_path / name
            metadata = path.lstat()
            relative = path.relative_to(root).as_posix()
            if any(ord(character) < 32 or ord(character) == 127 for character in relative):
                die("installed tree contains a control character in a path")
            if stat.S_ISLNK(metadata.st_mode):
                die(f"installed tree contains a symbolic link: {relative}")
            if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
                die(f"installed tree contains an unsupported entry: {relative}")
            if stat.S_ISREG(metadata.st_mode) and metadata.st_nlink != 1:
                die(f"installed tree contains a hard-linked file: {relative}")
            entries.append((relative, path, metadata))
    digest = hashlib.sha256(TREE_DOMAIN)
    for relative, path, metadata in sorted(entries, key=lambda item: item[0].encode("utf-8")):
        encoded = relative.encode("utf-8")
        if stat.S_ISDIR(metadata.st_mode):
            digest.update(b"D\0" + encoded + b"\0")
            continue
        digest.update(b"F\0" + encoded + b"\0")
        digest.update(str(metadata.st_size).encode("ascii") + b"\0")
        payload = read_file(path, f"installed tree file {relative}", maximum_bytes=None)
        if len(payload) != metadata.st_size:
            die(f"installed tree file changed while hashing: {relative}")
        digest.update(payload)
    return digest.hexdigest()


def platform_key() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    if machine in ("aarch64", "arm64"):
        architecture = "arm64"
    elif machine in ("amd64", "x86_64"):
        architecture = "x86_64"
    else:
        architecture = machine
    if system == "Darwin":
        abi = "none"
    elif system == "Linux":
        libc_name = platform.libc_ver()[0].lower()
        abi = "glibc" if libc_name in ("glibc", "gnu libc") else (libc_name or "unknown")
    else:
        abi = "unknown"
    return f"{system}-{architecture}-{abi}"


def version_output(executable: pathlib.Path, arguments: list[str], label: str) -> str:
    try:
        completed = subprocess.run(
            [str(executable), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": SAFE_PATH, "LC_ALL": "C", "LANG": "C"},
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        die(f"cannot inspect {label} version: {error}")
    if completed.returncode != 0:
        die(f"cannot inspect {label} version")
    output = completed.stdout.decode("utf-8", errors="strict").strip()
    if not output or len(output) > 1024 or "\n" in output:
        die(f"{label} returned an invalid version")
    return output


def runtime_bindings(
    root: pathlib.Path,
    archive_sha256: str,
    installed_tree_sha256: str,
    pi_bin: pathlib.Path,
    node_bin: pathlib.Path,
) -> tuple[dict[str, Any], pathlib.Path, pathlib.Path]:
    real_pi = require_regular_file(pi_bin.resolve(strict=True), "Pi executable", maximum_bytes=None, executable=True)
    real_node = require_regular_file(node_bin.resolve(strict=True), "Node executable", maximum_bytes=None, executable=True)
    pi_package_root = real_pi.parent.parent
    package_value, _ = load_json(pi_package_root / "package.json", "Pi package manifest")
    if not isinstance(package_value, dict):
        die("Pi package manifest must be an object")
    pi_package = require_string(package_value.get("name"), "Pi package name")
    pi_version = require_string(package_value.get("version"), "Pi package version")
    loader = require_regular_file(
        real_pi.parent / "core" / "extensions" / "loader.js",
        "Pi extension loader",
        maximum_bytes=None,
    )
    extension = require_regular_file(
        root / "skills" / "pi" / "extensions" / "mainframe.ts",
        "MAINFRAME Pi extension",
        maximum_bytes=None,
    )
    driver = require_regular_file(
        root / "evals" / "agent-impact" / "runners" / "pi-awm-transition-driver.mjs",
        "Pi AWM transition driver",
        maximum_bytes=None,
        executable=True,
    )
    compatibility, _ = load_json(root / "config" / "pi-compatibility.json", "Pi compatibility contract")
    if not isinstance(compatibility, dict) or compatibility.get("mainframe_version") != (root / "VERSION").read_text(encoding="utf-8").strip():
        die("Pi compatibility contract does not match the extracted MAINFRAME version")
    certification = next(
        (
            record
            for record in compatibility.get("certifications", [])
            if isinstance(record, dict)
            and record.get("package") == pi_package
            and record.get("version") == pi_version
            and platform_key() in record.get("platforms", [])
        ),
        None,
    )
    if certification is None or certification.get("support") != "certified":
        die(f"Pi {pi_package} {pi_version} is not certified for {platform_key()}")
    if certification.get("capabilities", {}).get("seven_tool_surface") != "verified":
        die("Pi certification does not verify the seven-tool surface")
    node_version = version_output(real_node, ["--version"], "Node")
    runtime = {
        "mainframe_archive_sha256": archive_sha256,
        "installed_tree_algorithm": "mainframe-package-tree-sha256-v1",
        "installed_tree_sha256": installed_tree_sha256,
        "pi_package": pi_package,
        "pi_version": pi_version,
        "pi_executable_sha256": sha256_file(real_pi, "Pi executable"),
        "pi_loader_sha256": sha256_file(loader, "Pi extension loader"),
        "pi_extension_sha256": sha256_file(extension, "MAINFRAME Pi extension"),
        "transition_driver_sha256": sha256_file(driver, "Pi AWM transition driver"),
        "node_executable_sha256": sha256_file(real_node, "Node executable"),
        "node_version": node_version,
    }
    return runtime, real_pi, real_node


def mkdir_private(path: pathlib.Path) -> pathlib.Path:
    path.mkdir(mode=0o700, parents=False, exist_ok=False)
    path.chmod(0o700)
    return require_real_directory(path, "private fixture directory", mode=0o700)


def write_new_file(path: pathlib.Path, payload: bytes, mode: int, label: str) -> None:
    parent = require_real_directory(path.parent, f"{label} parent", mode=0o700)
    target = parent / path.name
    if target != path.absolute():
        die(f"{label} path must use a canonical existing parent")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(target, flags, mode)
    except FileExistsError:
        die(f"refusing to overwrite existing {label}: {target}")
    try:
        os.fchmod(descriptor, mode)
        total = 0
        while total < len(payload):
            total += os.write(descriptor, payload[total:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def validate_driver_record(
    raw_value: Any,
    raw_payload: bytes,
    request: dict[str, Any],
    request_path: pathlib.Path,
    environment: dict[str, str],
) -> tuple[dict[str, Any], int, int]:
    raw = exact_keys(raw_value, RAW_TOP_LEVEL_KEYS, "Pi AWM transition driver record")
    require_exact(raw["schema_version"], 1, "driver record schema version")
    require_exact(raw["kind"], RAW_KIND, "driver record kind")
    require_exact(raw["claim_scope"], CLAIM_SCOPE, "driver record claim scope")
    for field in ("binding", "runtime_expected", "budget", "fixture", "paths"):
        if canonical_bytes(raw[field]) != canonical_bytes(request[field]):
            die(f"Pi AWM transition driver changed request field {field}")

    request_record = exact_keys(
        raw["request"],
        ("path", "file_sha256", "canonical_sha256"),
        "driver request binding",
    )
    request_canonical = canonical_bytes(request)
    require_exact(request_record["path"], str(request_path), "driver request path")
    require_exact(
        request_record["canonical_sha256"],
        sha256_bytes(request_canonical),
        "driver request canonical digest",
    )
    require_exact(
        request_record["file_sha256"],
        sha256_bytes(request_canonical + b"\n"),
        "driver request file digest",
    )

    observed = exact_keys(
        raw["runtime_observed"],
        RUNTIME_OBSERVED_KEYS,
        "driver observed runtime",
    )
    for field in (
        "mainframe_archive_sha256",
        "installed_tree_sha256",
        "pi_executable_sha256",
        "pi_package_manifest_sha256",
        "pi_loader_sha256",
        "pi_extension_sha256",
        "transition_driver_sha256",
        "bash_executable_sha256",
        "node_executable_sha256",
    ):
        require_string(observed[field], f"driver observed runtime {field}", SHA256_RE)
    for field in ("mainframe_version", "pi_package", "pi_version", "node_version"):
        require_string(observed[field], f"driver observed runtime {field}")
    require_string(observed["bash_version"], "driver observed Bash version", BASH_VERSION_RE)
    runtime_expected = request["runtime_expected"]
    for field in (
        "mainframe_archive_sha256",
        "installed_tree_sha256",
        "pi_package",
        "pi_version",
        "pi_executable_sha256",
        "pi_loader_sha256",
        "pi_extension_sha256",
        "transition_driver_sha256",
        "node_executable_sha256",
    ):
        require_exact(
            observed[field],
            runtime_expected[field],
            f"driver observed runtime {field}",
        )
    require_exact(
        observed["installed_tree_algorithm"],
        "mainframe-package-tree-sha256-v1",
        "driver installed-tree algorithm",
    )
    if observed["node_version"].removeprefix("v") != runtime_expected["node_version"].removeprefix("v"):
        die("driver observed Node version differs from its request binding")
    expected_paths = {
        "pi_executable": request["paths"]["pi_bin"],
        "node_executable": request["paths"]["node_bin"],
        "pi_loader": str(pathlib.PurePosixPath(request["paths"]["pi_bin"]).parent / "core/extensions/loader.js"),
        "pi_extension": str(pathlib.PurePosixPath(request["paths"]["mainframe_root"]) / "skills/pi/extensions/mainframe.ts"),
        "transition_driver": str(
            pathlib.PurePosixPath(request["paths"]["mainframe_root"])
            / "evals/agent-impact/runners/pi-awm-transition-driver.mjs"
        ),
    }
    for field, expected in expected_paths.items():
        require_exact(observed[field], expected, f"driver observed runtime {field}")
    require_string(observed["bash_executable"], "driver observed Bash executable")
    if not observed["bash_executable"].startswith("/"):
        die("driver observed Bash executable must be an absolute path")
    if canonical_bytes(observed["registered_tools"]) != canonical_bytes(EXPECTED_TOOLS):
        die("driver observed Pi tool surface differs from the exact seven-tool contract")
    require_exact(observed["loaded_mainframe_awm"], True, "driver loaded_mainframe_awm")
    require_exact(observed["provider_adapter_loaded"], False, "driver provider_adapter_loaded")
    provider_requests = require_integer(
        observed["provider_inference_requests"],
        "driver provider inference request count",
        0,
    )
    if provider_requests != 0:
        die("driver record reports provider inference")
    guards = observed["network_api_guards"]
    if (
        not isinstance(guards, list)
        or not 8 <= len(guards) <= 32
        or not all(isinstance(item, str) and item for item in guards)
        or len(set(guards)) != len(guards)
        or guards != sorted(guards)
    ):
        die("driver record contains an invalid network API guard inventory")

    environment_record = exact_keys(
        raw["environment"],
        ("allowed_names", "values", "isolated_paths"),
        "driver environment record",
    )
    isolated = exact_keys(
        environment_record["isolated_paths"],
        ("HOME", "PI_CODING_AGENT_DIR", "TMPDIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"),
        "driver isolated paths",
    )
    expected_isolated = {key: environment[key] for key in isolated}
    if canonical_bytes(isolated) != canonical_bytes(expected_isolated):
        die("driver changed an isolated environment path")
    fixed_value_keys = (
        "USER",
        "LOGNAME",
        "PI_OFFLINE",
        "PATH",
        "LC_ALL",
        "LANG",
        "NO_COLOR",
        "CI",
        "MAINFRAME_EVAL_PROTOCOL",
    )
    values = exact_keys(
        environment_record["values"],
        (*fixed_value_keys, "__CF_USER_TEXT_ENCODING"),
        "driver environment values",
    )
    for key in fixed_value_keys:
        require_exact(values[key], environment[key], f"driver environment value {key}")
    cf_value = values["__CF_USER_TEXT_ENCODING"]
    if cf_value is not None and (
        not isinstance(cf_value, str)
        or re.fullmatch(r"0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+", cf_value) is None
    ):
        die("driver Darwin text-encoding environment value is invalid")
    expected_allowed = sorted([*environment, *( ["__CF_USER_TEXT_ENCODING"] if cf_value is not None else [])])
    if environment_record["allowed_names"] != expected_allowed:
        die("driver environment allowlist differs from the scrubbed environment")

    for field in ("snapshots", "sequence", "handoff"):
        if not isinstance(raw[field], dict):
            die(f"driver record {field} must be an object")
    sequence = raw["sequence"]
    record_count = require_integer(sequence.get("record_count"), "driver operation count", 0)
    if record_count != 3 or not isinstance(sequence.get("records"), list) or len(sequence["records"]) != 3:
        die("driver record must contain exactly three operation records")
    non_claims = exact_keys(raw["non_claims"], tuple(EXPECTED_NON_CLAIMS), "driver non-claims")
    for field, expected in EXPECTED_NON_CLAIMS.items():
        require_exact(non_claims[field], expected, f"driver non-claim {field}")
    live_agent_sessions = require_integer(
        non_claims["live_agent_sessions"],
        "driver live agent session count",
        0,
    )
    if live_agent_sessions != 0:
        die("driver record reports a live agent session")

    canonical_raw = canonical_bytes(raw) + b"\n"
    if raw_payload != canonical_raw:
        die("Pi AWM transition driver stdout must be exactly one canonical JSON line")
    return raw, provider_requests, live_agent_sessions


def execute_driver(
    node_bin: pathlib.Path,
    driver: pathlib.Path,
    request_path: pathlib.Path,
    environment: dict[str, str],
    timeout_seconds: int,
) -> bytes:
    process = subprocess.Popen(
        [str(node_bin), str(driver), str(request_path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        cwd=str(request_path.parent),
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        die("Pi AWM transition driver exceeded the harness wall timeout")
    if len(stdout) > MAX_RECORD_BYTES or len(stderr) > 64 * 1024:
        die("Pi AWM transition driver output exceeded its harness limit")
    if process.returncode != 0:
        diagnostic = stderr.decode("utf-8", errors="replace").strip()
        if len(diagnostic) > 2000:
            diagnostic = diagnostic[:2000] + "..."
        die(f"Pi AWM transition driver failed with exit {process.returncode}: {diagnostic}")
    if stderr:
        die("Pi AWM transition driver wrote unexpected stderr")
    return stdout


def find_executable(explicit: str | None, candidates: tuple[str, ...], label: str) -> pathlib.Path:
    if explicit:
        return require_regular_file(pathlib.Path(explicit).resolve(strict=True), label, maximum_bytes=None, executable=True)
    for candidate in candidates:
        path = pathlib.Path(candidate)
        try:
            resolved = path.resolve(strict=True)
        except OSError:
            continue
        if resolved.is_file() and os.access(resolved, os.X_OK):
            return require_regular_file(resolved, label, maximum_bytes=None, executable=True)
    located = shutil.which(label.lower())
    if located:
        return require_regular_file(pathlib.Path(located).resolve(strict=True), label, maximum_bytes=None, executable=True)
    die(f"{label} executable was not found")


def run_fixture(args: argparse.Namespace) -> None:
    pair_id = require_string(args.pair_id, "pair id", PAIR_RE)
    opaque_arm_id = require_string(args.opaque_arm_id, "opaque arm id", ARM_RE)
    prereg_value, prereg_payload = load_json(pathlib.Path(args.preregistration), "preregistration")
    assignments_value, _ = load_json(pathlib.Path(args.assignments), "private assignments", mode=0o600)
    assignments = validate_private_assignments(assignments_value)
    binding, release = select_treatment_binding(
        prereg_value,
        assignments,
        pair_id,
        opaque_arm_id,
        sha256_bytes(prereg_payload),
    )
    archive = validate_preregistered_release_files(args.archive, release)
    archive_digest = sha256_file(archive, "release archive")
    if archive_digest != release["archive_sha256"]:
        die("release archive does not match the preregistration binding")
    timeout_seconds = require_integer(args.timeout_seconds, "wall timeout", MIN_TIMEOUT_SECONDS)
    if timeout_seconds > MAX_TIMEOUT_SECONDS:
        die(f"wall timeout must not exceed {MAX_TIMEOUT_SECONDS} seconds")
    tool_timeout_ms = min(timeout_seconds * 1000 - 1000, 300_000)
    if tool_timeout_ms < 1000:
        die("tool timeout derived from wall timeout is invalid")
    pi_bin = find_executable(
        args.pi_bin,
        (
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "/home/linuxbrew/.linuxbrew/bin/pi",
            str(pathlib.Path.home() / ".bun" / "bin" / "pi"),
        ),
        "Pi",
    )
    node_bin = find_executable(
        args.node_bin,
        (
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/home/linuxbrew/.linuxbrew/bin/node",
            "/usr/bin/node",
        ),
        "Node",
    )
    output = pathlib.Path(args.output).absolute()
    require_real_directory(output.parent, "raw-record output parent", mode=0o700)
    if output.exists() or output.is_symlink():
        die(f"refusing to overwrite existing raw record: {output}")

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="mainframe-awm-transition-"))
    scratch = scratch.resolve(strict=True)
    scratch.chmod(0o700)
    try:
        install_root = mkdir_private(scratch / "install")
        home = mkdir_private(scratch / "home")
        workspace = mkdir_private(scratch / "workspace")
        pi_agent = mkdir_private(scratch / "pi-agent")
        xdg_config = mkdir_private(scratch / "xdg-config")
        xdg_state = mkdir_private(scratch / "xdg-state")
        xdg_cache = mkdir_private(scratch / "xdg-cache")
        tmp_root = mkdir_private(scratch / "tmp")
        private_root = mkdir_private(scratch / "private")
        safe_extract(archive, install_root)
        installed_digest = package_tree_sha256(install_root)
        if installed_digest != release["installed_tree_sha256"]:
            die("extracted MAINFRAME tree does not match the preregistration binding")
        runtime, real_pi, real_node = runtime_bindings(
            install_root,
            archive_digest,
            installed_digest,
            pi_bin,
            node_bin,
        )
        driver = install_root / "evals" / "agent-impact" / "runners" / "pi-awm-transition-driver.mjs"
        awm_root = home / ".mainframe" / "awm"
        fixture = {
            "session_name": "pi-impact-handoff",
            "namespace": "pi-impact-test",
            "checkpoint_key": "implementation-root-cause",
            "checkpoint_value": "subtract used capacity from total capacity",
            "checkpoint_importance": "critical",
            "handoff_target": "implementer",
        }
        request = {
            "schema_version": 1,
            "kind": REQUEST_KIND,
            "claim_scope": CLAIM_SCOPE,
            "binding": binding,
            "paths": {
                "mainframe_root": str(install_root),
                "pi_bin": str(real_pi),
                "node_bin": str(real_node),
                "workspace": str(workspace),
                "awm_root": str(awm_root),
                "tmp_root": str(tmp_root),
            },
            "runtime_expected": runtime,
            "budget": {
                "maximum_context_bytes": MAX_CONTEXT_BYTES,
                "tool_timeout_ms": tool_timeout_ms,
            },
            "fixture": fixture,
        }
        request_path = private_root / "request.json"
        write_new_file(request_path, canonical_bytes(request) + b"\n", 0o600, "fixture request")
        environment = {
            "HOME": str(home),
            "USER": "mainframe-eval",
            "LOGNAME": "mainframe-eval",
            "PI_CODING_AGENT_DIR": str(pi_agent),
            "PI_OFFLINE": "1",
            "XDG_CONFIG_HOME": str(xdg_config),
            "XDG_STATE_HOME": str(xdg_state),
            "XDG_CACHE_HOME": str(xdg_cache),
            "TMPDIR": str(tmp_root),
            "PATH": SAFE_PATH,
            "LC_ALL": "C",
            "LANG": "C",
            "NO_COLOR": "1",
            "CI": "1",
            "MAINFRAME_EVAL_PROTOCOL": "1",
        }
        raw_payload = execute_driver(real_node, driver, request_path, environment, timeout_seconds)
        try:
            raw_value = json.loads(
                raw_payload.decode("utf-8", errors="strict"),
                object_pairs_hook=reject_duplicate_pairs,
                parse_constant=reject_nonfinite,
            )
        except FixtureError:
            raise
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            die(f"Pi AWM transition driver did not return strict JSON: {error}")
        enforce_json_bounds(raw_value)
        raw_value, provider_requests, live_agent_sessions = validate_driver_record(
            raw_value,
            raw_payload,
            request,
            request_path,
            environment,
        )
        if len(raw_payload) > MAX_RECORD_BYTES:
            die("canonical private raw record exceeds its size limit")
        write_new_file(output, raw_payload, 0o600, "private raw record")
        result = {
            "schema_version": 1,
            "kind": "mainframe-agent-impact-awm-transition-fixture-result",
            "claim_scope": CLAIM_SCOPE,
            "private_raw_record_sha256": sha256_bytes(raw_payload),
            "provider_requests": provider_requests,
            "live_agent_sessions": live_agent_sessions,
        }
        print(canonical_bytes(result).decode("utf-8"))
    finally:
        shutil.rmtree(scratch)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one credentials-free real-Pi MAINFRAME AWM transition fixture."
    )
    parser.add_argument("--preregistration", required=True)
    parser.add_argument("--assignments", required=True)
    parser.add_argument("--pair-id", required=True)
    parser.add_argument("--opaque-arm-id", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--pi-bin")
    parser.add_argument("--node-bin")
    parser.add_argument("--timeout-seconds", type=int, default=90)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def main() -> None:
    try:
        run_fixture(parse_arguments())
    except FixtureError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2) from None
    except (OSError, UnicodeError, ValueError) as error:
        print(f"ERROR: fixture infrastructure failure: {error}", file=sys.stderr)
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()

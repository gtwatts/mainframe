#!/usr/bin/env python3
"""MAINFRAME local paired-development smoke protocol.

The only execution mode in this version is ``run --fake-transport``. It starts
the checked-in deterministic transport, never Pi, Ollama, a provider, or a real
agent. The protocol is deliberately separate from Agent Impact Protocol v1 and
the live-study preregistration.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import re
import resource
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, Dict, Iterable, List, NoReturn, Optional, Sequence, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PROTOCOL_ROOT = PROJECT_ROOT / "evals" / "agent-impact"
DEFAULT_STUDY = PROTOCOL_ROOT / "suites" / "local-development-smoke-v1.json"
SCHEMA_NAMES = (
    "local-study.schema.json",
    "local-task.schema.json",
    "local-plan.schema.json",
    "local-assignments.schema.json",
    "local-runner-request.schema.json",
    "local-runner-result.schema.json",
    "local-transition-receipt.schema.json",
    "local-ledger-record.schema.json",
    "local-private-records.schema.json",
    "local-evidence.schema.json",
)
ALLOWED_ENVIRONMENT_NAMES = sorted([
    "CI", "HOME", "LANG", "LC_ALL", "LOGNAME", "MAINFRAME_LOCAL_PROTOCOL",
    "NO_COLOR", "PATH", "PYTHONDONTWRITEBYTECODE", "TMPDIR", "USER",
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "__CF_USER_TEXT_ENCODING",
])
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
PLAN_RE = re.compile(r"^plan-[0-9a-f]{16}$")
PAIR_RE = re.compile(r"^pair-[0-9a-f]{16}$")
ARM_RE = re.compile(r"^arm-[0-9a-f]{16}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_FILE_BYTES = 8 * 1024 * 1024
OUTPUT_LIMIT_BYTES = 8 * 1024 * 1024
PROCESS_GROUP_GRACE_SECONDS = 0.15
ZERO_SHA = "0" * 64


class ProtocolError(RuntimeError):
    pass


def die(message: str) -> NoReturn:
    raise ProtocolError(message)


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        die("value cannot be canonicalized: {}".format(error))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("digest input is unavailable: {}: {}".format(path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or \
            metadata.st_nlink != 1 or metadata.st_size > MAX_FILE_BYTES:
        die("digest input must be a bounded regular, non-symlink, single-link file: {}".format(path))
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_binding(path: Path) -> Dict[str, Any]:
    path = require_regular_file(path, "bound file")
    return {
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def require_private_file(path: Path, label: str) -> Path:
    path = require_regular_file(path, label)
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        die("{} must not grant group or other permissions: {}".format(label, path))
    return path


def require_real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        die("{} must be a real directory: {}".format(label, path))
    return path.resolve(strict=True)


def require_regular_file(path: Path, label: str, *, maximum: int = MAX_FILE_BYTES) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die("{} must be a regular, non-symlink file: {}".format(label, path))
    if metadata.st_nlink != 1:
        die("{} must have exactly one hard link: {}".format(label, path))
    if metadata.st_size <= 0 or metadata.st_size > maximum:
        die("{} has an unsupported size: {}".format(label, path))
    return path.resolve(strict=True)


def load_json_text(text: str, label: str) -> Any:
    def reject_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
        value: Dict[str, Any] = {}
        for key, child in pairs:
            if key in value:
                die("{} contains duplicate key {!r}".format(label, key))
            value[key] = child
        return value

    try:
        return json.loads(text, object_pairs_hook=reject_duplicates)
    except json.JSONDecodeError as error:
        die("{} is not valid JSON: {}".format(label, error))


def load_json(path: Path, label: str) -> Any:
    path = require_regular_file(path, label)
    try:
        return load_json_text(path.read_text(encoding="utf-8"), label)
    except (OSError, UnicodeDecodeError) as error:
        die("{} cannot be read as UTF-8: {}".format(label, error))


def exact_keys(value: Any, expected: Iterable[str], label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        die("{} must be an object".format(label))
    expected_set = set(expected)
    actual_set = set(value)
    if actual_set != expected_set:
        die("{} keys differ (missing={}, extras={})".format(
            label, sorted(expected_set - actual_set), sorted(actual_set - expected_set)))
    return value


def require_string(value: Any, label: str, pattern: Optional[re.Pattern] = None) -> str:
    if not isinstance(value, str) or not value:
        die("{} must be a non-empty string".format(label))
    if pattern is not None and pattern.fullmatch(value) is None:
        die("{} has an invalid value: {!r}".format(label, value))
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        die("{} contains a control character".format(label))
    return value


def require_integer(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        die("{} must be an integer in [{}, {}]".format(label, minimum, maximum))
    return value


def require_digest(value: Any, label: str) -> str:
    return require_string(value, label, SHA_RE)


def safe_relative(value: Any, label: str) -> PurePosixPath:
    text = require_string(value, label)
    if "\\" in text:
        die("{} must use POSIX separators".format(label))
    path = PurePosixPath(text)
    if path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in path.parts):
        die("{} is not a safe relative path".format(label))
    return path


def resolve_regular(root: Path, relative: PurePosixPath, label: str) -> Path:
    root = require_real_directory(root, "{} root".format(label))
    current = root
    for index, part in enumerate(relative.parts):
        current = current / part
        try:
            metadata = current.lstat()
        except OSError as error:
            die("{} is unavailable: {}".format(label, error))
        if stat.S_ISLNK(metadata.st_mode):
            die("{} traverses a symbolic link: {}".format(label, current))
        if index < len(relative.parts) - 1 and not stat.S_ISDIR(metadata.st_mode):
            die("{} parent is not a directory".format(label))
    return require_regular_file(current, label)


def resolve_directory(root: Path, relative: PurePosixPath, label: str) -> Path:
    root = require_real_directory(root, "{} root".format(label))
    current = root
    for part in relative.parts:
        current = current / part
        try:
            metadata = current.lstat()
        except OSError as error:
            die("{} is unavailable: {}".format(label, error))
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            die("{} traverses a non-directory or symbolic link".format(label))
    return require_real_directory(current, label)


def atomic_bytes(path: Path, payload: bytes, mode: int) -> None:
    parent = require_real_directory(path.parent, "output parent")
    if path.exists() or path.is_symlink():
        die("refusing to overwrite existing output: {}".format(path))
    descriptor, temporary_name = tempfile.mkstemp(prefix=".{}.tmp.".format(path.name),
                                                  dir=str(parent))
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        identity = os.fstat(descriptor)
        temporary_identity = temporary.lstat()
        if (identity.st_dev, identity.st_ino) != \
                (temporary_identity.st_dev, temporary_identity.st_ino):
            die("temporary output identity changed before placement")
        try:
            os.link(str(temporary), str(path))
        except FileExistsError:
            die("refusing to overwrite existing output: {}".format(path))
        target_identity = path.lstat()
        if (identity.st_dev, identity.st_ino) != (target_identity.st_dev, target_identity.st_ino) or \
                stat.S_IMODE(target_identity.st_mode) != mode:
            die("placed output identity or mode differs from the held file descriptor")
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def atomic_json(path: Path, value: Any, mode: int) -> None:
    atomic_bytes(path, canonical_bytes(value) + b"\n", mode)


def mkdir_new(path: Path, mode: int = 0o700) -> Path:
    require_real_directory(path.parent, "new directory parent")
    try:
        path.mkdir(mode=mode)
    except FileExistsError:
        die("refusing to reuse existing directory: {}".format(path))
    os.chmod(str(path), mode)
    return require_real_directory(path, "new directory")


def tree_records(root: Path) -> List[Dict[str, Any]]:
    root = require_real_directory(root, "tree root")
    records: List[Dict[str, Any]] = []
    for current_text, directories, files in os.walk(str(root), topdown=True, followlinks=False):
        current = Path(current_text)
        directories.sort()
        files.sort()
        for name in directories:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                die("tree contains unsafe directory: {}".format(path))
            records.append({
                "path": path.relative_to(root).as_posix(),
                "type": "directory",
                "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
            })
        for name in files:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                die("tree contains unsafe file: {}".format(path))
            if metadata.st_nlink != 1 or metadata.st_size > MAX_FILE_BYTES:
                die("tree contains hard-linked or oversized file: {}".format(path))
            records.append({
                "path": path.relative_to(root).as_posix(),
                "type": "file",
                "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
                "size_bytes": metadata.st_size,
                "sha256": sha256_file(path),
            })
    records.sort(key=lambda item: (item["path"], item["type"]))
    return records


def tree_digest(root: Path) -> str:
    return sha256_bytes(canonical_bytes(tree_records(root)))


def tree_snapshot(path: Path, root: Path) -> Dict[str, Any]:
    records = tree_records(root)
    value = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-tree-snapshot",
        "tree_sha256": sha256_bytes(canonical_bytes(records)),
        "records": records,
    }
    atomic_json(path, value, 0o600)
    return {"tree_sha256": value["tree_sha256"], **file_binding(path)}


def verify_tree_snapshot(path: Path, expected_binding: Dict[str, Any],
                         current_root: Optional[Path] = None) -> Dict[str, Any]:
    if file_binding(path) != {"size_bytes": expected_binding["size_bytes"],
                              "sha256": expected_binding["sha256"]}:
        die("tree snapshot file digest changed: {}".format(path))
    value = exact_keys(load_json(path, "tree snapshot"),
                       ("schema_version", "kind", "tree_sha256", "records"),
                       "tree snapshot")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-tree-snapshot":
        die("tree snapshot identity is unsupported")
    if not isinstance(value["records"], list) or \
            sha256_bytes(canonical_bytes(value["records"])) != value["tree_sha256"]:
        die("tree snapshot digest does not derive from its records")
    if value["tree_sha256"] != expected_binding["tree_sha256"]:
        die("tree snapshot binding changed")
    if current_root is not None and tree_records(current_root) != value["records"]:
        die("current workspace does not match its final tree snapshot")
    return value


def copy_repository(source: Path, destination: Path) -> None:
    tree_records(source)
    if destination.exists() or destination.is_symlink():
        die("workspace destination already exists")
    shutil.copytree(str(source), str(destination), symlinks=False)
    if tree_records(source) != tree_records(destination):
        die("copied workspace differs from task repository")


def protocol_root_for_study(path: Path) -> Path:
    path = require_regular_file(path, "local study")
    if path.parent.name != "suites":
        die("local study must be directly under a suites directory")
    root = require_real_directory(path.parent.parent, "local protocol root")
    for name in SCHEMA_NAMES:
        require_regular_file(root / name, "local schema {}".format(name))
    return root


def validate_task(path: Path, root: Path) -> Dict[str, Any]:
    value = exact_keys(load_json(path, "local task"),
                       ("schema_version", "kind", "id", "title", "repository", "phases", "grader"),
                       "local task")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-task":
        die("local task identity is unsupported")
    if value["id"] != "local-001" or value["repository"] != "repository":
        die("local task must be the fixed local-001 task")
    require_string(value["title"], "task title")
    task_dir = require_real_directory(path.parent, "task directory")
    repository = resolve_directory(task_dir, safe_relative(value["repository"], "repository"),
                                   "task repository")
    phases = value["phases"]
    if not isinstance(phases, list) or len(phases) != 2:
        die("local task must contain exactly two phases")
    expected_phases = (("investigate", "investigate.md", False),
                       ("implement", "implement.md", True))
    phase_records = []
    for item, expected in zip(phases, expected_phases):
        item = exact_keys(item, ("id", "prompt", "workspace_edits"), "task phase")
        if (item["id"], item["prompt"], item["workspace_edits"]) != expected:
            die("local task phase contract changed")
        prompt = resolve_regular(task_dir, safe_relative(item["prompt"], "phase prompt"),
                                 "phase prompt")
        phase_records.append({**item, "prompt_path": prompt,
                              "prompt_binding": file_binding(prompt)})
    grader_value = exact_keys(value["grader"], ("command", "maximum_score"), "task grader")
    if grader_value != {"command": "grade.py", "maximum_score": 100}:
        die("local grader contract changed")
    grader = resolve_regular(task_dir, safe_relative(grader_value["command"], "grader"),
                             "task grader")
    repository_records = tree_records(repository)
    bundle = {
        "task_file": file_binding(path),
        "prompts": [phase["prompt_binding"] for phase in phase_records],
        "grader": file_binding(grader),
        "repository_tree_sha256": sha256_bytes(canonical_bytes(repository_records)),
    }
    return {
        "id": value["id"], "path": path, "directory": task_dir,
        "repository": repository, "repository_records": repository_records,
        "repository_tree_sha256": bundle["repository_tree_sha256"],
        "phases": phase_records, "grader": grader, "maximum_score": 100,
        "bundle": bundle, "bundle_sha256": sha256_bytes(canonical_bytes(bundle)),
    }


def load_study(path: Path) -> Dict[str, Any]:
    path = require_regular_file(path, "local study")
    root = protocol_root_for_study(path)
    value = exact_keys(load_json(path, "local study"),
                       ("schema_version", "kind", "id", "claim_scope", "task",
                        "replicates", "transport", "budgets", "statistics"),
                       "local study")
    expected_identity = (1, "mainframe-agent-impact-local-study",
                         "local-development-smoke-v1",
                         "local-development-smoke-protocol-conformance-only")
    if (value["schema_version"], value["kind"], value["id"], value["claim_scope"]) != expected_identity:
        die("local study identity or claim scope changed")
    if value["task"] != "tasks/local-001/task.json" or value["replicates"] != 3 or \
            value["transport"] != "runners/local-fake-transport.py":
        die("local study task, replicate, or fake-transport contract changed")
    budgets = exact_keys(value["budgets"],
                         ("wall_seconds_per_phase", "maximum_tool_calls_per_phase",
                          "maximum_continuation_bytes"), "study budgets")
    if budgets != {"wall_seconds_per_phase": 5, "maximum_tool_calls_per_phase": 10,
                   "maximum_continuation_bytes": 4096}:
        die("local study budgets changed")
    statistics = exact_keys(value["statistics"],
                            ("bootstrap_seed", "bootstrap_resamples", "confidence_level"),
                            "study statistics")
    if statistics != {"bootstrap_seed": "local-development-smoke-v1",
                      "bootstrap_resamples": 1000, "confidence_level": 0.95}:
        die("local study statistics changed")
    task = validate_task(resolve_regular(root, safe_relative(value["task"], "study task"),
                                         "study task"), root)
    transport = resolve_regular(root, safe_relative(value["transport"], "fake transport"),
                                "fake transport")
    protocol_inputs = []
    for name in SCHEMA_NAMES:
        protocol_inputs.append({"name": name, **file_binding(root / name)})
    binding = {
        "study_sha256": sha256_file(path),
        "task_bundle_sha256": task["bundle_sha256"],
        "repository_tree_sha256": task["repository_tree_sha256"],
        "harness_basename": Path(__file__).name,
        "harness_sha256": sha256_file(Path(__file__).resolve()),
        "transport_sha256": sha256_file(transport),
        "protocol_inputs_sha256": sha256_bytes(canonical_bytes(protocol_inputs)),
    }
    return {"path": path, "root": root, "id": value["id"],
            "claim_scope": value["claim_scope"], "replicates": 3,
            "budgets": budgets, "statistics": statistics, "task": task,
            "transport": transport, "protocol_inputs": protocol_inputs,
            "binding": binding}


def derive_id(domain: str, context: bytes, index: int) -> str:
    return hashlib.sha256(domain.encode("ascii") + b"\0" + context + b"\0" +
                          str(index).encode("ascii")).hexdigest()[:16]


def build_plan(study: Dict[str, Any], seed: str) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    require_string(seed, "plan seed")
    context = canonical_bytes({"domain": "mainframe-local-smoke-plan-v1",
                               "study": study["binding"], "seed": seed})
    plan_id = "plan-" + derive_id("plan", context, 0)
    pairs = []
    assignment_rows = []
    seen = {plan_id}
    for replicate in range(1, 4):
        pair_id = "pair-" + derive_id("pair", context, replicate)
        arm_a = "arm-" + derive_id("arm-a", context, replicate)
        arm_b = "arm-" + derive_id("arm-b", context, replicate)
        if any(identifier in seen for identifier in (pair_id, arm_a, arm_b)):
            die("derived local plan identifiers collided")
        seen.update((pair_id, arm_a, arm_b))
        order = [arm_a, arm_b]
        if int(derive_id("order", context, replicate), 16) & 1:
            order.reverse()
        control_first = bool(int(derive_id("assignment", context, replicate), 16) & 1)
        modes = ["control", "treatment"] if control_first else ["treatment", "control"]
        mapping = {order[0]: modes[0], order[1]: modes[1]}
        pairs.append({
            "pair_id": pair_id,
            "task_id": study["task"]["id"],
            "replicate": replicate,
            "instance_sha256": sha256_bytes(canonical_bytes({
                "task_bundle_sha256": study["task"]["bundle_sha256"],
                "replicate": replicate,
            })),
            "repository_tree_sha256": study["task"]["repository_tree_sha256"],
            "opaque_arm_order": order,
            "budgets": study["budgets"],
        })
        assignment_rows.append({
            "pair_id": pair_id,
            "opaque_arms": [{"opaque_arm_id": arm, "mode": mapping[arm]} for arm in order],
        })
    assignments = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-assignments",
        "study_id": study["id"],
        "plan_id": plan_id,
        "assignments": assignment_rows,
    }
    commitment = sha256_bytes(canonical_bytes(assignments))
    plan = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-plan",
        "study_id": study["id"],
        "claim_scope": study["claim_scope"],
        "plan_id": plan_id,
        "binding": study["binding"],
        "assignment_commitment_sha256": commitment,
        "pair_count": 3,
        "pairs": pairs,
    }
    if any(term in canonical_bytes(plan).decode("utf-8").lower()
           for term in ('"control"', '"treatment"', '"arm_mode"')):
        die("public local plan leaked a mechanism assignment")
    return plan, assignments


def validate_plan(path: Path, study: Dict[str, Any]) -> Dict[str, Any]:
    value = exact_keys(load_json(path, "local plan"),
                       ("schema_version", "kind", "study_id", "claim_scope", "plan_id",
                        "binding", "assignment_commitment_sha256", "pair_count", "pairs"),
                       "local plan")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-plan" or \
            value["study_id"] != study["id"] or value["claim_scope"] != study["claim_scope"]:
        die("local plan identity or claim scope changed")
    require_string(value["plan_id"], "plan ID", PLAN_RE)
    if value["binding"] != study["binding"]:
        die("local plan binding does not match selected current inputs")
    require_digest(value["assignment_commitment_sha256"], "assignment commitment")
    if value["pair_count"] != 3 or not isinstance(value["pairs"], list) or len(value["pairs"]) != 3:
        die("local plan must contain exactly three pairs")
    seen = set()
    for expected_replicate, pair in enumerate(value["pairs"], 1):
        pair = exact_keys(pair, ("pair_id", "task_id", "replicate", "instance_sha256",
                                 "repository_tree_sha256", "opaque_arm_order", "budgets"),
                          "plan pair")
        pair_id = require_string(pair["pair_id"], "pair ID", PAIR_RE)
        if pair_id in seen or pair["task_id"] != study["task"]["id"] or \
                pair["replicate"] != expected_replicate:
            die("local plan pair identity, task, or replicate is invalid")
        seen.add(pair_id)
        if pair["repository_tree_sha256"] != study["task"]["repository_tree_sha256"] or \
                pair["budgets"] != study["budgets"]:
            die("local plan repository or budgets changed")
        require_digest(pair["instance_sha256"], "instance digest")
        expected_instance = sha256_bytes(canonical_bytes({
            "task_bundle_sha256": study["task"]["bundle_sha256"],
            "replicate": expected_replicate,
        }))
        if pair["instance_sha256"] != expected_instance:
            die("local plan instance digest does not derive from task and replicate")
        arms = pair["opaque_arm_order"]
        if not isinstance(arms, list) or len(arms) != 2:
            die("plan pair must contain two opaque arms")
        for arm in arms:
            require_string(arm, "opaque arm ID", ARM_RE)
            if arm in seen:
                die("local plan reuses an opaque identifier")
            seen.add(arm)
    return value


def validate_assignments(path: Path, plan: Dict[str, Any]) -> Dict[str, Any]:
    value = exact_keys(load_json(path, "local assignments"),
                       ("schema_version", "kind", "study_id", "plan_id", "assignments"),
                       "local assignments")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-assignments" or \
            value["study_id"] != plan["study_id"] or value["plan_id"] != plan["plan_id"]:
        die("local assignments refer to another plan")
    if sha256_bytes(canonical_bytes(value)) != plan["assignment_commitment_sha256"]:
        die("local assignment reveal does not match its public commitment")
    rows = value["assignments"]
    if not isinstance(rows, list) or len(rows) != 3:
        die("local assignments must cover exactly three pairs")
    planned = {pair["pair_id"]: pair for pair in plan["pairs"]}
    seen = set()
    for row in rows:
        row = exact_keys(row, ("pair_id", "opaque_arms"), "assignment row")
        if row["pair_id"] in seen or row["pair_id"] not in planned:
            die("assignment contains duplicate or unknown pair")
        seen.add(row["pair_id"])
        arms = row["opaque_arms"]
        if not isinstance(arms, list) or len(arms) != 2:
            die("assignment row must contain two opaque arms")
        if [arm.get("opaque_arm_id") for arm in arms] != planned[row["pair_id"]]["opaque_arm_order"]:
            die("assignment arm order differs from public plan")
        modes = []
        for arm in arms:
            arm = exact_keys(arm, ("opaque_arm_id", "mode"), "assignment arm")
            if arm["mode"] not in ("control", "treatment"):
                die("assignment mode is unsupported")
            modes.append(arm["mode"])
        if sorted(modes) != ["control", "treatment"]:
            die("every pair must contain one control and one treatment")
    if seen != set(planned):
        die("assignment reveal does not cover every pair")
    return value


def assignment_map(assignments: Dict[str, Any]) -> Dict[str, Dict[str, str]]:
    return {row["pair_id"]: {arm["opaque_arm_id"]: arm["mode"]
                             for arm in row["opaque_arms"]}
            for row in assignments["assignments"]}


def controlled_environment(phase_root: Path) -> Tuple[Dict[str, str], str]:
    state = mkdir_new(phase_root / "state")
    home = mkdir_new(state / "home")
    temporary = mkdir_new(state / "tmp")
    config = mkdir_new(state / "xdg-config")
    state_home = mkdir_new(state / "xdg-state")
    cache = mkdir_new(state / "xdg-cache")
    environment = {
        "CI": "1", "HOME": str(home), "LANG": "C", "LC_ALL": "C",
        "LOGNAME": "mainframe-local-smoke", "MAINFRAME_LOCAL_PROTOCOL": "1",
        "NO_COLOR": "1", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONDONTWRITEBYTECODE": "1", "TMPDIR": str(temporary),
        "USER": "mainframe-local-smoke", "XDG_CACHE_HOME": str(cache),
        "XDG_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(state_home),
        "__CF_USER_TEXT_ENCODING": "0x0:0:0",
    }
    if sorted(environment) != ALLOWED_ENVIRONMENT_NAMES:
        die("internal environment allowlist drift")
    state_id = sha256_bytes(canonical_bytes({
        "home": str(home), "tmp": str(temporary), "config": str(config),
        "state": str(state_home), "cache": str(cache),
    }))
    return environment, state_id


def output_binding(path: Path) -> Dict[str, Any]:
    if not path.exists() and not path.is_symlink():
        return {"present": False, "size_bytes": 0, "sha256": None}
    try:
        metadata = path.lstat()
    except OSError as error:
        die("output file is unavailable: {}: {}".format(path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or \
            metadata.st_nlink != 1 or metadata.st_size > OUTPUT_LIMIT_BYTES:
        die("output must be a bounded regular, non-symlink, single-link file: {}".format(path))
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"present": True, "size_bytes": metadata.st_size, "sha256": digest}


def process_preexec() -> None:
    resource.setrlimit(resource.RLIMIT_FSIZE, (OUTPUT_LIMIT_BYTES, OUTPUT_LIMIT_BYTES))


def terminate_group(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + PROCESS_GROUP_GRACE_SECONDS
    while time.monotonic() < deadline:
        try:
            os.killpg(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.01)
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_process(command: Sequence[str], environment: Dict[str, str], timeout: float,
                cwd: Path, stdout_path: Path, stderr_path: Path) -> Tuple[str, Optional[int]]:
    stdout_descriptor = os.open(str(stdout_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    stderr_descriptor = os.open(str(stderr_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    process: Optional[subprocess.Popen] = None
    try:
        with os.fdopen(stdout_descriptor, "wb") as stdout_handle, \
                os.fdopen(stderr_descriptor, "wb") as stderr_handle:
            process = subprocess.Popen(list(command), cwd=str(cwd), env=environment,
                                       stdin=subprocess.DEVNULL, stdout=stdout_handle,
                                       stderr=stderr_handle, start_new_session=True,
                                       preexec_fn=process_preexec)
            try:
                exit_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                terminate_group(process.pid)
                process.wait()
                return "timeout", None
            terminate_group(process.pid)
            return "completed", exit_code
    except OSError as error:
        if process is not None:
            terminate_group(process.pid)
        die("fake transport launch failed: {}".format(error))


def validate_runner_result(path: Path, phase: str) -> Dict[str, Any]:
    value = exact_keys(load_json(path, "local runner result"),
                       ("schema_version", "kind", "status", "continuation_relative_path",
                        "usage", "tool_calls", "observed_environment_names",
                        "provider_requests", "pi_sessions", "network_requests"),
                       "local runner result")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-runner-result" or \
            value["status"] != "completed":
        die("local fake runner did not report a completed supported result")
    usage = exact_keys(value["usage"],
                       ("input_tokens", "input_tokens_reason", "output_tokens", "output_tokens_reason"),
                       "runner usage")
    expected_reason = "deterministic-fake-transport-no-provider-usage"
    if usage != {"input_tokens": None, "input_tokens_reason": expected_reason,
                 "output_tokens": None, "output_tokens_reason": expected_reason}:
        die("fake transport usage contract changed")
    require_integer(value["tool_calls"], "runner tool calls", 0, 10)
    if value["observed_environment_names"] != ALLOWED_ENVIRONMENT_NAMES:
        die("fake transport observed an environment outside the strict allowlist")
    if (value["provider_requests"], value["pi_sessions"], value["network_requests"]) != (0, 0, 0):
        die("fake transport reported a provider, Pi, or network operation")
    if phase == "investigate":
        if value["continuation_relative_path"] != "agent-continuation.txt":
            die("investigation result did not declare the fixed continuation")
    elif value["continuation_relative_path"] is not None:
        die("implementation result must not declare a continuation")
    return value


class Ledger:
    def __init__(self, path: Path, study_id: str, plan_id: str, transport_sha256: str):
        self.path = path
        self.study_id = study_id
        self.plan_id = plan_id
        self.transport_sha256 = transport_sha256
        self.previous = ZERO_SHA
        self.count = 0
        descriptor = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        self.handle = os.fdopen(descriptor, "wb")

    def append(self, pair_id: str, arm_id: str, phase: str,
               request: Dict[str, Any], result: Dict[str, Any],
               stdout: Dict[str, Any], stderr: Dict[str, Any]) -> Dict[str, Any]:
        self.count += 1
        base = {
            "schema_version": 1,
            "kind": "mainframe-agent-impact-local-attempt-ledger-record",
            "sequence": self.count,
            "previous_record_sha256": self.previous,
            "study_id": self.study_id,
            "plan_id": self.plan_id,
            "pair_id": pair_id,
            "opaque_arm_id": arm_id,
            "phase": phase,
            "attempt": 1,
            "transport_sha256": self.transport_sha256,
            "request_sha256": request["sha256"],
            "result_sha256": result["sha256"],
            "stdout": stdout,
            "stderr": stderr,
            "status": "completed",
            "provider_requests": 0,
            "pi_sessions": 0,
            "network_requests": 0,
        }
        record_sha = sha256_bytes(canonical_bytes(base))
        record = {**base, "record_sha256": record_sha}
        self.handle.write(canonical_bytes(record) + b"\n")
        self.handle.flush()
        os.fsync(self.handle.fileno())
        self.previous = record_sha
        return record

    def close(self) -> Dict[str, Any]:
        self.handle.close()
        return {"entry_count": self.count, "head_sha256": self.previous,
                **file_binding(self.path)}


def validate_adapter_request(value: Any, expected: Dict[str, Any]) -> Dict[str, Any]:
    request = exact_keys(value,
                         ("schema_version", "kind", "study_id", "plan_id", "pair_id",
                          "opaque_arm_id", "task_id", "phase", "workspace", "prompt_path",
                          "context_path", "artifact_dir", "result_path", "budgets",
                          "environment_contract"), "adapter request")
    for key in ("schema_version", "kind", "study_id", "plan_id", "pair_id", "opaque_arm_id",
                "task_id", "phase", "workspace", "prompt_path", "context_path",
                "artifact_dir", "result_path", "budgets"):
        if request[key] != expected[key]:
            die("adapter request {} does not match its bound invocation".format(key))
    contract = exact_keys(request["environment_contract"],
                          ("fresh_per_phase", "allowed_environment_names"),
                          "adapter environment contract")
    if contract != {"fresh_per_phase": True,
                    "allowed_environment_names": ALLOWED_ENVIRONMENT_NAMES}:
        die("adapter request environment contract changed")
    lowered = canonical_bytes(request).decode("utf-8").lower()
    for term in ('"control"', '"treatment"', '"arm_mode"', '"mechanism"'):
        if term in lowered:
            die("adapter request leaked a mechanism assignment")
    return request


def invoke_phase(study: Dict[str, Any], plan: Dict[str, Any], pair: Dict[str, Any],
                 arm_id: str, phase_index: int, workspace: Path, arm_root: Path,
                 context_path: Optional[Path], ledger: Ledger, fake_behavior: str,
                 child_marker: Optional[Path]) -> Dict[str, Any]:
    phase = study["task"]["phases"][phase_index]
    phase_root = mkdir_new(arm_root / "phase-{}".format(phase["id"]))
    environment, state_id = controlled_environment(phase_root)
    prompt_copy = phase_root / "prompt.md"
    atomic_bytes(prompt_copy, phase["prompt_path"].read_bytes(), 0o600)
    if sha256_file(prompt_copy) != phase["prompt_binding"]["sha256"]:
        die("phase prompt changed while copying")
    artifact_dir = phase_root / "artifacts"
    result_path = phase_root / "result.json"
    request_path = phase_root / "request.json"
    stdout_path = phase_root / "transport.stdout"
    stderr_path = phase_root / "transport.stderr"
    request = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-run-request",
        "study_id": study["id"],
        "plan_id": plan["plan_id"],
        "pair_id": pair["pair_id"],
        "opaque_arm_id": arm_id,
        "task_id": study["task"]["id"],
        "phase": phase["id"],
        "workspace": str(workspace),
        "prompt_path": str(prompt_copy),
        "context_path": str(context_path) if context_path is not None else None,
        "artifact_dir": str(artifact_dir),
        "result_path": str(result_path),
        "budgets": {
            "wall_seconds": study["budgets"]["wall_seconds_per_phase"],
            "maximum_tool_calls": study["budgets"]["maximum_tool_calls_per_phase"],
            "maximum_continuation_bytes": study["budgets"]["maximum_continuation_bytes"],
        },
        "environment_contract": {
            "fresh_per_phase": True,
            "allowed_environment_names": ALLOWED_ENVIRONMENT_NAMES,
        },
    }
    validate_adapter_request(request, request)
    atomic_json(request_path, request, 0o600)
    before_tree = tree_digest(workspace)
    command = [sys.executable, str(study["transport"]), str(request_path)]
    if fake_behavior == "orphan-on-success":
        if child_marker is None:
            die("orphan behavior requires an explicit absolute child marker")
        command.extend([fake_behavior, str(child_marker)])
    process_status, exit_code = run_process(
        command, environment, float(study["budgets"]["wall_seconds_per_phase"]),
        workspace, stdout_path, stderr_path,
    )
    if process_status != "completed" or exit_code != 0:
        die("deterministic fake transport did not complete (status={}, exit={})".format(
            process_status, exit_code))
    if phase["id"] == "investigate" and tree_digest(workspace) != before_tree:
        die("fake transport mutated the read-only investigation workspace")
    result = validate_runner_result(result_path, phase["id"])
    request_binding = file_binding(request_path)
    result_binding = file_binding(result_path)
    stdout_binding = output_binding(stdout_path)
    stderr_binding = output_binding(stderr_path)
    ledger_record = ledger.append(pair["pair_id"], arm_id, phase["id"],
                                  request_binding, result_binding,
                                  stdout_binding, stderr_binding)
    continuation_binding = None
    continuation_path = None
    if phase["id"] == "investigate":
        continuation_path = resolve_regular(
            artifact_dir, safe_relative(result["continuation_relative_path"], "continuation"),
            "agent continuation")
        if continuation_path.stat().st_size > study["budgets"]["maximum_continuation_bytes"]:
            die("agent continuation exceeds the fixed byte budget")
        continuation_binding = file_binding(continuation_path)
    return {
        "phase": phase["id"], "status": "completed", "fresh_state_id": state_id,
        "fresh_state_per_phase": True,
        "assignment_not_in_request_or_environment": True,
        "request": request_binding, "result": result_binding,
        "stdout": stdout_binding, "stderr": stderr_binding,
        "continuation": continuation_binding,
        "usage": result["usage"], "tool_calls": result["tool_calls"],
        "provider_requests": 0, "pi_sessions": 0, "network_requests": 0,
        "ledger_sequence": ledger_record["sequence"],
        "ledger_record_sha256": ledger_record["record_sha256"],
        "_continuation_path": continuation_path,
    }


def build_transition(study: Dict[str, Any], plan: Dict[str, Any], pair: Dict[str, Any],
                     arm_id: str, mode: str, arm_root: Path,
                     investigation: Dict[str, Any]) -> Tuple[Path, Dict[str, Any]]:
    transition_root = mkdir_new(arm_root / "transition")
    source_path = investigation["_continuation_path"]
    if source_path is None:
        die("completed investigation has no continuation")
    payload = require_regular_file(source_path, "source continuation").read_bytes()
    continuation_path = transition_root / "neutral-continuation.txt"
    atomic_bytes(continuation_path, payload, 0o600)
    continuation_binding = file_binding(continuation_path)
    if continuation_binding != investigation["continuation"]:
        die("neutral continuation differs from the adapter continuation")
    if mode == "control":
        mechanism = "native-bounded-continuation"
        operations = ["capture-native-continuation", "export-neutral-continuation"]
    else:
        mechanism = "awm-shaped-fixture-transition"
        operations = ["fixture-init", "fixture-checkpoint", "fixture-export-neutral-continuation"]
    receipt = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-transition-receipt",
        "study_id": study["id"], "plan_id": plan["plan_id"],
        "pair_id": pair["pair_id"], "opaque_arm_id": arm_id,
        "mechanism": mechanism,
        "synthetic_fixture": True,
        "mainframe_runtime_exercised": False,
        "mainframe_awm_exercised": False,
        "source_result_sha256": investigation["result"]["sha256"],
        "source_continuation": investigation["continuation"],
        "neutral_continuation": continuation_binding,
        "operations": operations,
    }
    receipt_path = transition_root / "receipt.json"
    atomic_json(receipt_path, receipt, 0o600)
    return continuation_path, {
        "mechanism": mechanism, "synthetic_fixture": True,
        "mainframe_runtime_exercised": False, "mainframe_awm_exercised": False,
        "continuation": continuation_binding,
        "receipt": file_binding(receipt_path),
        "operation_count": len(operations),
    }


def grader_environment(root: Path) -> Dict[str, str]:
    home = mkdir_new(root / "home")
    temporary = mkdir_new(root / "tmp")
    return {"HOME": str(home), "USER": "mainframe-local-grader",
            "LOGNAME": "mainframe-local-grader", "TMPDIR": str(temporary),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C",
            "NO_COLOR": "1", "CI": "1", "PYTHONDONTWRITEBYTECODE": "1"}


def run_grader(study: Dict[str, Any], workspace: Path, arm_root: Path) -> Dict[str, Any]:
    grader = require_regular_file(study["task"]["grader"], "hidden grader")
    try:
        common = Path(os.path.commonpath([str(grader), str(workspace)]))
    except ValueError:
        common = Path("/")
    if common == workspace or grader == workspace:
        die("hidden grader is inside the adapter workspace")
    before = sha256_file(grader)
    grader_root = mkdir_new(arm_root / "grader")
    stdout_path = grader_root / "grader.stdout"
    stderr_path = grader_root / "grader.stderr"
    status_value, exit_code = run_process(
        [sys.executable, str(grader), str(workspace)], grader_environment(grader_root),
        30.0, workspace, stdout_path, stderr_path,
    )
    if status_value != "completed" or exit_code != 0 or sha256_file(grader) != before:
        die("hidden grader failed or changed during scoring")
    try:
        result = load_json_text(stdout_path.read_text(encoding="utf-8"), "grader output")
    except (OSError, UnicodeDecodeError) as error:
        die("grader output is not readable UTF-8: {}".format(error))
    result = exact_keys(result, ("score", "maximum_score", "solved", "tests_passed", "tests_total"),
                        "grader output")
    score = require_integer(result["score"], "grader score", 0, 100)
    if result["maximum_score"] != 100 or not isinstance(result["solved"], bool) or \
            result["solved"] != (score == 100):
        die("grader output contract changed")
    tests_total = require_integer(result["tests_total"], "grader tests total", 1, 100)
    tests_passed = require_integer(result["tests_passed"], "grader tests passed", 0, tests_total)
    return {
        "score": score, "maximum_score": 100,
        "normalized_score": round(score / 100, 8), "solved": result["solved"],
        "tests_passed": tests_passed, "tests_total": tests_total,
        "grader_sha256": before, "grader_outside_workspace": True,
        "stdout": output_binding(stdout_path), "stderr": output_binding(stderr_path),
    }


def public_phase(value: Dict[str, Any]) -> Dict[str, Any]:
    return {key: child for key, child in value.items() if not key.startswith("_")}


def run_arm(study: Dict[str, Any], plan: Dict[str, Any], pair: Dict[str, Any],
            arm_id: str, mode: str, pair_root: Path, ledger: Ledger,
            fake_behavior: str, child_marker: Optional[Path]) -> Dict[str, Any]:
    arm_root = mkdir_new(pair_root / arm_id)
    workspace = arm_root / "workspace"
    copy_repository(study["task"]["repository"], workspace)
    snapshots = mkdir_new(arm_root / "snapshots")
    initial = tree_snapshot(snapshots / "initial.json", workspace)
    if initial["tree_sha256"] != pair["repository_tree_sha256"]:
        die("opaque arm did not start from the planned repository")
    investigate = invoke_phase(study, plan, pair, arm_id, 0, workspace, arm_root,
                               None, ledger, fake_behavior, child_marker)
    after_investigate = tree_snapshot(snapshots / "after-investigate.json", workspace)
    if after_investigate["tree_sha256"] != initial["tree_sha256"]:
        die("investigation changed the workspace")
    continuation_path, transition = build_transition(
        study, plan, pair, arm_id, mode, arm_root, investigate)
    implement = invoke_phase(study, plan, pair, arm_id, 1, workspace, arm_root,
                             continuation_path, ledger, fake_behavior, child_marker)
    grade = run_grader(study, workspace, arm_root)
    final = tree_snapshot(snapshots / "final.json", workspace)
    return {
        "opaque_arm_id": arm_id, "revealed_mode": mode,
        "initial_snapshot": initial, "after_investigate_snapshot": after_investigate,
        "final_snapshot": final,
        "equal_planned_budgets": True,
        "fresh_process_per_phase": True,
        "transition": transition,
        "phases": [public_phase(investigate), public_phase(implement)],
        "grade": grade,
    }


def aggregate_pairs(pairs: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    rows = []
    for pair in pairs:
        arms = {arm["revealed_mode"]: arm for arm in pair["arms"]}
        if set(arms) != {"control", "treatment"}:
            die("paired record lacks one control and one treatment")
        rows.append((pair, arms))
    deltas = [round(arms["treatment"]["grade"]["normalized_score"] -
                    arms["control"]["grade"]["normalized_score"], 8)
              for _, arms in rows]
    return {
        "pair_count": len(rows), "valid_pair_count": len(rows), "invalid_pair_count": 0,
        "control_solved_count": sum(arms["control"]["grade"]["solved"] for _, arms in rows),
        "treatment_solved_count": sum(arms["treatment"]["grade"]["solved"] for _, arms in rows),
        "control_mean_normalized_score": round(sum(arms["control"]["grade"]["normalized_score"]
                                                       for _, arms in rows) / len(rows), 8),
        "treatment_mean_normalized_score": round(sum(arms["treatment"]["grade"]["normalized_score"]
                                                         for _, arms in rows) / len(rows), 8),
        "paired_mean_normalized_score_delta": round(sum(deltas) / len(deltas), 8),
        "treatment_wins": sum(delta > 0 for delta in deltas),
        "ties": sum(delta == 0 for delta in deltas),
        "treatment_losses": sum(delta < 0 for delta in deltas),
    }


def deterministic_statistics(pairs: Sequence[Dict[str, Any]], study: Dict[str, Any]) -> Dict[str, Any]:
    deltas = []
    binary = []
    for pair in pairs:
        arms = {arm["revealed_mode"]: arm for arm in pair["arms"]}
        deltas.append(arms["treatment"]["grade"]["normalized_score"] -
                      arms["control"]["grade"]["normalized_score"])
        binary.append((arms["control"]["grade"]["solved"],
                       arms["treatment"]["grade"]["solved"]))
    observed = abs(sum(deltas) / len(deltas))
    permuted = []
    for signs in itertools.product((-1, 1), repeat=len(deltas)):
        permuted.append(abs(sum(sign * delta for sign, delta in zip(signs, deltas)) /
                            len(deltas)))
    extreme = sum(value >= observed for value in permuted)
    bootstrap_values = []
    seed = study["statistics"]["bootstrap_seed"].encode("utf-8")
    for counter in range(study["statistics"]["bootstrap_resamples"]):
        sample = []
        for draw in range(len(deltas)):
            digest = hashlib.sha256(seed + b"\0" + str(counter).encode("ascii") +
                                    b"\0" + str(draw).encode("ascii")).digest()
            sample.append(deltas[int.from_bytes(digest[:8], "big") % len(deltas)])
        bootstrap_values.append(sum(sample) / len(sample))
    bootstrap_values.sort()
    alpha = 1.0 - study["statistics"]["confidence_level"]
    lower_index = max(0, math.floor((alpha / 2.0) * len(bootstrap_values)))
    upper_index = min(len(bootstrap_values) - 1,
                      math.ceil((1.0 - alpha / 2.0) * len(bootstrap_values)) - 1)
    control_only = sum(control and not treatment for control, treatment in binary)
    treatment_only = sum(treatment and not control for control, treatment in binary)
    discordant = control_only + treatment_only
    mcnemar_p = 1.0
    if discordant:
        smaller = min(control_only, treatment_only)
        probability = sum(math.comb(discordant, index) for index in range(smaller + 1)) / (2 ** discordant)
        mcnemar_p = min(1.0, 2.0 * probability)
    return {
        "primary": {
            "estimator": "paired-mean-normalized-score-delta",
            "value": round(sum(deltas) / len(deltas), 8),
            "exact_sign_flip": {
                "two_sided": True,
                "assignments_enumerated": len(permuted),
                "extreme_assignments": extreme,
                "p_value": round(extreme / len(permuted), 8),
            },
            "bootstrap": {
                "algorithm": "sha256-counter-prng-v1",
                "seed": study["statistics"]["bootstrap_seed"],
                "resamples": len(bootstrap_values),
                "confidence_level": study["statistics"]["confidence_level"],
                "lower": round(bootstrap_values[lower_index], 8),
                "upper": round(bootstrap_values[upper_index], 8),
            },
        },
        "secondary": {
            "test": "two-sided-exact-mcnemar",
            "control_only_solves": control_only,
            "treatment_only_solves": treatment_only,
            "discordant_pairs": discordant,
            "p_value": round(mcnemar_p, 8),
        },
    }


def validate_ledger(path: Path, expected: Dict[str, Any], records: Dict[str, Any],
                    study: Dict[str, Any], plan: Dict[str, Any]) -> None:
    if file_binding(path) != {"size_bytes": expected["size_bytes"], "sha256": expected["sha256"]}:
        die("attempt ledger file digest changed")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        die("attempt ledger is unreadable: {}".format(error))
    if len(lines) != 12 or expected["entry_count"] != 12:
        die("attempt ledger must contain exactly twelve phase attempts")
    phase_lookup = {}
    for pair in records["pairs"]:
        for arm in pair["arms"]:
            for phase in arm["phases"]:
                phase_lookup[phase["ledger_sequence"]] = (pair, arm, phase)
    previous = ZERO_SHA
    for index, line in enumerate(lines, 1):
        record = exact_keys(load_json_text(line, "ledger record"),
                            ("schema_version", "kind", "sequence", "previous_record_sha256",
                             "study_id", "plan_id", "pair_id", "opaque_arm_id", "phase",
                             "attempt", "transport_sha256", "request_sha256", "result_sha256",
                             "stdout", "stderr", "status", "provider_requests", "pi_sessions",
                             "network_requests", "record_sha256"), "ledger record")
        claimed = record.pop("record_sha256")
        actual = sha256_bytes(canonical_bytes(record))
        record["record_sha256"] = claimed
        if claimed != actual or record["previous_record_sha256"] != previous:
            die("attempt ledger hash chain is invalid at sequence {}".format(index))
        if record["sequence"] != index or record["study_id"] != study["id"] or \
                record["plan_id"] != plan["plan_id"] or record["attempt"] != 1 or \
                record["transport_sha256"] != study["binding"]["transport_sha256"] or \
                record["status"] != "completed" or \
                (record["provider_requests"], record["pi_sessions"], record["network_requests"]) != (0, 0, 0):
            die("attempt ledger record contract changed at sequence {}".format(index))
        if index not in phase_lookup:
            die("attempt ledger contains an unrepresented phase")
        pair, arm, phase = phase_lookup[index]
        if (record["pair_id"], record["opaque_arm_id"], record["phase"],
                record["request_sha256"], record["result_sha256"], record["stdout"],
                record["stderr"], claimed) != \
                (pair["pair_id"], arm["opaque_arm_id"], phase["phase"],
                 phase["request"]["sha256"], phase["result"]["sha256"], phase["stdout"],
                 phase["stderr"], phase["ledger_record_sha256"]):
            die("attempt ledger record differs from its phase evidence")
        previous = claimed
    if previous != expected["head_sha256"]:
        die("attempt ledger head changed")


def validate_transition(path: Path, binding: Dict[str, Any], study: Dict[str, Any],
                        plan: Dict[str, Any], pair: Dict[str, Any], arm: Dict[str, Any],
                        investigation: Dict[str, Any]) -> None:
    receipt_path = path / "receipt.json"
    continuation_path = path / "neutral-continuation.txt"
    if file_binding(receipt_path) != binding["receipt"] or \
            file_binding(continuation_path) != binding["continuation"]:
        die("transition receipt or neutral continuation digest changed")
    receipt = exact_keys(load_json(receipt_path, "transition receipt"),
                         ("schema_version", "kind", "study_id", "plan_id", "pair_id",
                          "opaque_arm_id", "mechanism", "synthetic_fixture",
                          "mainframe_runtime_exercised", "mainframe_awm_exercised",
                          "source_result_sha256", "source_continuation",
                          "neutral_continuation", "operations"), "transition receipt")
    expected_mechanism = "native-bounded-continuation" if arm["revealed_mode"] == "control" \
        else "awm-shaped-fixture-transition"
    expected_operations = ["capture-native-continuation", "export-neutral-continuation"] \
        if arm["revealed_mode"] == "control" else \
        ["fixture-init", "fixture-checkpoint", "fixture-export-neutral-continuation"]
    if receipt != {
        "schema_version": 1, "kind": "mainframe-agent-impact-local-transition-receipt",
        "study_id": study["id"], "plan_id": plan["plan_id"],
        "pair_id": pair["pair_id"], "opaque_arm_id": arm["opaque_arm_id"],
        "mechanism": expected_mechanism, "synthetic_fixture": True,
        "mainframe_runtime_exercised": False, "mainframe_awm_exercised": False,
        "source_result_sha256": investigation["result"]["sha256"],
        "source_continuation": investigation["continuation"],
        "neutral_continuation": binding["continuation"],
        "operations": expected_operations,
    }:
        die("transition receipt does not reproduce from its committed arm")
    if binding["mechanism"] != expected_mechanism or binding["operation_count"] != len(expected_operations):
        die("transition public binding changed")


def validate_run_records(study: Dict[str, Any], plan: Dict[str, Any],
                         assignments: Dict[str, Any], run_dir: Path,
                         records: Dict[str, Any]) -> Dict[str, Any]:
    records = exact_keys(records, ("schema_version", "kind", "study_id", "plan_id",
                                    "platform", "python_version", "fake_behavior",
                                    "allowed_environment_names", "transport_sha256",
                                    "ledger", "pairs"), "local private records")
    if records["schema_version"] != 1 or records["kind"] != "mainframe-agent-impact-local-private-records" or \
            records["study_id"] != study["id"] or records["plan_id"] != plan["plan_id"]:
        die("local private record identity changed")
    if records["fake_behavior"] not in ("normal", "orphan-on-success") or \
            records["allowed_environment_names"] != ALLOWED_ENVIRONMENT_NAMES or \
            records["transport_sha256"] != study["binding"]["transport_sha256"]:
        die("local private runtime contract changed")
    if not isinstance(records["pairs"], list) or len(records["pairs"]) != 3:
        die("local private records must contain exactly three pairs")
    mapping = assignment_map(assignments)
    seen_states = set()
    planned_pairs = {pair["pair_id"]: pair for pair in plan["pairs"]}
    for pair_record in records["pairs"]:
        pair_record = exact_keys(pair_record, ("pair_id", "task_id", "replicate",
                                               "repository_tree_sha256", "planned_budgets", "arms"),
                                 "private pair")
        if pair_record["pair_id"] not in planned_pairs:
            die("private records contain unknown pair")
        pair = planned_pairs[pair_record["pair_id"]]
        if (pair_record["task_id"], pair_record["replicate"],
                pair_record["repository_tree_sha256"], pair_record["planned_budgets"]) != \
                (pair["task_id"], pair["replicate"], pair["repository_tree_sha256"], pair["budgets"]):
            die("private pair differs from its plan")
        arms = pair_record["arms"]
        if not isinstance(arms, list) or len(arms) != 2 or \
                [arm.get("opaque_arm_id") for arm in arms] != pair["opaque_arm_order"]:
            die("private arm order differs from public plan")
        pair_root = run_dir / pair["pair_id"]
        for arm in arms:
            arm = exact_keys(arm, ("opaque_arm_id", "revealed_mode", "initial_snapshot",
                                   "after_investigate_snapshot", "final_snapshot",
                                   "equal_planned_budgets", "fresh_process_per_phase",
                                   "transition", "phases", "grade"), "private arm")
            arm_id = arm["opaque_arm_id"]
            if arm["revealed_mode"] != mapping[pair["pair_id"]][arm_id] or \
                    arm["equal_planned_budgets"] is not True or arm["fresh_process_per_phase"] is not True:
                die("private arm assignment or fairness assertion changed")
            arm_root = pair_root / arm_id
            workspace = require_real_directory(arm_root / "workspace", "arm workspace")
            snapshots = require_real_directory(arm_root / "snapshots", "snapshot directory")
            initial_value = verify_tree_snapshot(snapshots / "initial.json", arm["initial_snapshot"])
            investigate_value = verify_tree_snapshot(snapshots / "after-investigate.json",
                                                     arm["after_investigate_snapshot"])
            verify_tree_snapshot(snapshots / "final.json", arm["final_snapshot"], workspace)
            if initial_value["tree_sha256"] != pair["repository_tree_sha256"] or \
                    investigate_value["tree_sha256"] != initial_value["tree_sha256"]:
                die("initial or investigation tree equality changed")
            phases = arm["phases"]
            if not isinstance(phases, list) or len(phases) != 2:
                die("private arm must contain two phases")
            for phase_index, phase_record in enumerate(phases):
                phase_name = ("investigate", "implement")[phase_index]
                phase_record = exact_keys(phase_record,
                    ("phase", "status", "fresh_state_id", "fresh_state_per_phase",
                     "assignment_not_in_request_or_environment", "request", "result", "stdout", "stderr",
                     "continuation", "usage", "tool_calls", "provider_requests", "pi_sessions",
                     "network_requests", "ledger_sequence", "ledger_record_sha256"),
                    "private phase")
                if phase_record["phase"] != phase_name or phase_record["status"] != "completed" or \
                        phase_record["fresh_state_per_phase"] is not True or \
                        phase_record["assignment_not_in_request_or_environment"] is not True or \
                        (phase_record["provider_requests"], phase_record["pi_sessions"],
                         phase_record["network_requests"]) != (0, 0, 0):
                    die("private phase execution contract changed")
                state_id = require_digest(phase_record["fresh_state_id"], "fresh state ID")
                if state_id in seen_states:
                    die("phase reused home/XDG/tmp state")
                seen_states.add(state_id)
                phase_root = arm_root / "phase-{}".format(phase_name)
                request_path = phase_root / "request.json"
                result_path = phase_root / "result.json"
                prompt_path = phase_root / "prompt.md"
                if file_binding(prompt_path) != study["task"]["phases"][phase_index]["prompt_binding"]:
                    die("phase prompt copy differs from the committed task prompt")
                if file_binding(request_path) != phase_record["request"] or \
                        file_binding(result_path) != phase_record["result"] or \
                        output_binding(phase_root / "transport.stdout") != phase_record["stdout"] or \
                        output_binding(phase_root / "transport.stderr") != phase_record["stderr"]:
                    die("phase request, result, stdout, or stderr digest changed")
                expected_request = {
                    "schema_version": 1, "kind": "mainframe-agent-impact-local-run-request",
                    "study_id": study["id"], "plan_id": plan["plan_id"],
                    "pair_id": pair["pair_id"], "opaque_arm_id": arm_id,
                    "task_id": study["task"]["id"], "phase": phase_name,
                    "workspace": str(workspace), "prompt_path": str(prompt_path),
                    "context_path": None if phase_name == "investigate" else
                                    str(arm_root / "transition" / "neutral-continuation.txt"),
                    "artifact_dir": str(phase_root / "artifacts"),
                    "result_path": str(result_path),
                    "budgets": {"wall_seconds": 5, "maximum_tool_calls": 10,
                                "maximum_continuation_bytes": 4096},
                    "environment_contract": {"fresh_per_phase": True,
                                             "allowed_environment_names": ALLOWED_ENVIRONMENT_NAMES},
                }
                validate_adapter_request(load_json(request_path, "adapter request"), expected_request)
                result = validate_runner_result(result_path, phase_name)
                if phase_name == "investigate":
                    continuation_path = phase_root / "artifacts" / "agent-continuation.txt"
                    if file_binding(continuation_path) != phase_record["continuation"]:
                        die("adapter continuation digest changed")
                elif phase_record["continuation"] is not None:
                    die("implementation phase contains an unexpected continuation")
                if phase_record["usage"] != result["usage"] or phase_record["tool_calls"] != result["tool_calls"]:
                    die("phase usage or tool count changed")
            validate_transition(arm_root / "transition", arm["transition"], study, plan,
                                pair, arm, phases[0])
            grade = arm["grade"]
            grade = exact_keys(grade, ("score", "maximum_score", "normalized_score", "solved",
                                       "tests_passed", "tests_total", "grader_sha256",
                                       "grader_outside_workspace", "stdout", "stderr"), "arm grade")
            grader_root = arm_root / "grader"
            if grade["grader_sha256"] != sha256_file(study["task"]["grader"]) or \
                    grade["grader_outside_workspace"] is not True or \
                    output_binding(grader_root / "grader.stdout") != grade["stdout"] or \
                    output_binding(grader_root / "grader.stderr") != grade["stderr"]:
                die("grader binding changed")
            grader_value = exact_keys(load_json_text(
                (grader_root / "grader.stdout").read_text(encoding="utf-8"), "grader output"),
                ("score", "maximum_score", "solved", "tests_passed", "tests_total"),
                "grader output")
            expected_grade = {"score": grade["score"], "maximum_score": grade["maximum_score"],
                              "solved": grade["solved"], "tests_passed": grade["tests_passed"],
                              "tests_total": grade["tests_total"]}
            if grader_value != expected_grade or grade["normalized_score"] != round(grade["score"] / 100, 8):
                die("grader result does not derive from captured output")
    if len(seen_states) != 12:
        die("local smoke did not use twelve fresh per-phase state roots")
    validate_ledger(run_dir / "attempt-ledger.jsonl", records["ledger"], records, study, plan)
    return records


def public_pair_records(records: Dict[str, Any]) -> List[Dict[str, Any]]:
    return records["pairs"]


def scan_public_evidence(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.startswith("_"):
                die("public evidence contains a private field")
            scan_public_evidence(child)
    elif isinstance(value, list):
        for child in value:
            scan_public_evidence(child)
    elif isinstance(value, str) and value.startswith("/"):
        die("public evidence contains an absolute private path")


def build_evidence(study: Dict[str, Any], plan_path: Path, plan: Dict[str, Any],
                   assignments_path: Path, run_dir: Path,
                   records: Dict[str, Any]) -> Dict[str, Any]:
    pairs = public_pair_records(records)
    evidence = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-evidence",
        "claim_scope": "local-development-smoke-protocol-conformance-only",
        "protocol": {
            "version": "local-development-smoke-v1",
            "study_id": study["id"], "study_sha256": study["binding"]["study_sha256"],
            "task_bundle_sha256": study["binding"]["task_bundle_sha256"],
            "repository_tree_sha256": study["binding"]["repository_tree_sha256"],
            "protocol_inputs_sha256": study["binding"]["protocol_inputs_sha256"],
            "planned_harness_basename": study["binding"]["harness_basename"],
            "planned_harness_sha256": study["binding"]["harness_sha256"],
            "plan_id": plan["plan_id"], "plan_sha256": sha256_file(plan_path),
            "assignment_commitment_sha256": plan["assignment_commitment_sha256"],
            "assignment_reveal_sha256": sha256_file(assignments_path),
            "assignment_reveal_embedded_in_local_evidence": True,
            "external_publication": "not-performed",
            "private_reveal_available_to_harness": True,
        },
        "runtime": {
            "harness_basename": Path(__file__).name,
            "harness_sha256": sha256_file(Path(__file__).resolve()),
            "transport_basename": study["transport"].name,
            "transport_sha256": study["binding"]["transport_sha256"],
            "records_sha256": sha256_file(run_dir / "records.json"),
            "raw_run_bundle_sha256": tree_digest(run_dir),
            "platform": records["platform"], "python_version": records["python_version"],
            "mainframe_runtime_exercised": False, "mainframe_awm_exercised": False,
            "pi_runtime_exercised": False, "ollama_runtime_exercised": False,
        },
        "execution": {
            "mode": "deterministic-fake-transport-only",
            "fake_behavior": records["fake_behavior"],
            "designed_future_boundary": "pi-plus-ollama-local-adapter",
            "assignment_not_in_request_or_environment": True,
            "mechanism_transition_outside_adapter": True,
            "fresh_home_xdg_tmp_process_per_phase": True,
            "strict_environment_allowlist": ALLOWED_ENVIRONMENT_NAMES,
            "attempt_count": 12, "pair_count": 3,
            "live_agent_sessions": 0, "pi_sessions": 0,
            "provider_sessions": 0, "provider_requests": 0, "network_requests": 0,
            "actual_provider": None, "actual_model": None,
        },
        "ledger": records["ledger"],
        "pairs": pairs,
        "aggregate": aggregate_pairs(pairs),
        "statistics": deterministic_statistics(pairs, study),
        "non_claims": {
            "real_provider_inference": "not-run", "agent_quality": "not-measured",
            "productivity": "not-measured", "comparative_agent_performance": "not-measured",
            "mainframe_benefit": "not-measured", "live_agent_sessions": 0,
        },
        "limitations": {
            "deterministic_fake_transport": True, "single_toy_task": True,
            "same_uid_execution": True, "os_isolation": "not-provided",
            "network_denial": "not-enforced-by-os-sandbox",
            "grader_isolation": "path-separated-same-uid-not-adversarial",
            "assignment_blinding": "request-and-environment-omission-only-same-uid-not-adversarial",
            "treatment_receipt": "awm-shaped-synthetic-fixture-not-mainframe-awm",
            "generalization": "not-established",
            "pi_ollama": "design-boundary-only-not-executed",
        },
    }
    scan_public_evidence(evidence)
    return validate_public_evidence(evidence)


def validate_public_evidence(value: Any) -> Dict[str, Any]:
    value = exact_keys(value, ("schema_version", "kind", "claim_scope", "protocol",
                               "runtime", "execution", "ledger", "pairs", "aggregate",
                               "statistics", "non_claims", "limitations"), "local evidence")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-local-evidence" or \
            value["claim_scope"] != "local-development-smoke-protocol-conformance-only":
        die("local evidence identity or claim scope changed")
    expected_non_claims = {
        "real_provider_inference": "not-run", "agent_quality": "not-measured",
        "productivity": "not-measured", "comparative_agent_performance": "not-measured",
        "mainframe_benefit": "not-measured", "live_agent_sessions": 0,
    }
    if value["non_claims"] != expected_non_claims:
        die("local evidence non-claims were weakened")
    expected_limitations = {
        "deterministic_fake_transport": True, "single_toy_task": True,
        "same_uid_execution": True, "os_isolation": "not-provided",
        "network_denial": "not-enforced-by-os-sandbox",
        "grader_isolation": "path-separated-same-uid-not-adversarial",
        "assignment_blinding": "request-and-environment-omission-only-same-uid-not-adversarial",
        "treatment_receipt": "awm-shaped-synthetic-fixture-not-mainframe-awm",
        "generalization": "not-established", "pi_ollama": "design-boundary-only-not-executed",
    }
    if value["limitations"] != expected_limitations:
        die("local evidence limitations changed")
    execution = exact_keys(value["execution"],
        ("mode", "fake_behavior", "designed_future_boundary", "assignment_not_in_request_or_environment",
         "mechanism_transition_outside_adapter", "fresh_home_xdg_tmp_process_per_phase",
         "strict_environment_allowlist", "attempt_count", "pair_count", "live_agent_sessions",
         "pi_sessions", "provider_sessions", "provider_requests", "network_requests",
         "actual_provider", "actual_model"), "local evidence execution")
    if execution["mode"] != "deterministic-fake-transport-only" or \
            execution["designed_future_boundary"] != "pi-plus-ollama-local-adapter" or \
            execution["assignment_not_in_request_or_environment"] is not True or \
            execution["mechanism_transition_outside_adapter"] is not True or \
            execution["fresh_home_xdg_tmp_process_per_phase"] is not True or \
            execution["strict_environment_allowlist"] != ALLOWED_ENVIRONMENT_NAMES or \
            (execution["attempt_count"], execution["pair_count"], execution["live_agent_sessions"],
             execution["pi_sessions"], execution["provider_sessions"],
             execution["provider_requests"], execution["network_requests"],
             execution["actual_provider"], execution["actual_model"]) != \
            (12, 3, 0, 0, 0, 0, 0, None, None):
        die("local evidence fake-only execution contract changed")
    runtime = value["runtime"]
    if any(runtime.get(name) is not False for name in
           ("mainframe_runtime_exercised", "mainframe_awm_exercised",
            "pi_runtime_exercised", "ollama_runtime_exercised")):
        die("local evidence falsely claims a real runtime was exercised")
    if runtime.get("harness_basename") != value["protocol"].get("planned_harness_basename") or \
            runtime.get("harness_sha256") != value["protocol"].get("planned_harness_sha256"):
        die("executed harness differs from the harness bound by the plan")
    if value["aggregate"] != aggregate_pairs(value["pairs"]):
        die("local evidence aggregate does not derive from paired rows")
    expected_aggregate = {
        "pair_count": 3, "valid_pair_count": 3, "invalid_pair_count": 0,
        "control_solved_count": 3, "treatment_solved_count": 3,
        "control_mean_normalized_score": 1.0,
        "treatment_mean_normalized_score": 1.0,
        "paired_mean_normalized_score_delta": 0.0,
        "treatment_wins": 0, "ties": 3, "treatment_losses": 0,
    }
    if value["aggregate"] != expected_aggregate:
        die("local fake conformance requires equal perfect scores and zero paired delta")
    if value["statistics"] != deterministic_statistics(value["pairs"], {
            "statistics": {"bootstrap_seed": "local-development-smoke-v1",
                           "bootstrap_resamples": 1000, "confidence_level": 0.95}}):
        die("local evidence statistics do not derive deterministically")
    expected_statistics = {
        "primary": {
            "estimator": "paired-mean-normalized-score-delta", "value": 0.0,
            "exact_sign_flip": {"two_sided": True, "assignments_enumerated": 8,
                                "extreme_assignments": 8, "p_value": 1.0},
            "bootstrap": {"algorithm": "sha256-counter-prng-v1",
                          "seed": "local-development-smoke-v1", "resamples": 1000,
                          "confidence_level": 0.95, "lower": 0.0, "upper": 0.0},
        },
        "secondary": {"test": "two-sided-exact-mcnemar", "control_only_solves": 0,
                      "treatment_only_solves": 0, "discordant_pairs": 0,
                      "p_value": 1.0},
    }
    if value["statistics"] != expected_statistics:
        die("local fake conformance statistics must remain the fixed all-tie vector")
    scan_public_evidence(value)
    return value


def prepare(args: argparse.Namespace) -> None:
    study = load_study(Path(args.study))
    output = Path(args.output)
    assignments_output = Path(args.assignments_output)
    if output == assignments_output:
        die("plan and assignment outputs must differ")
    require_real_directory(output.parent, "plan output parent")
    require_real_directory(assignments_output.parent, "assignment output parent")
    plan, assignments = build_plan(study, args.seed)
    atomic_json(assignments_output, assignments, 0o600)
    atomic_json(output, plan, 0o644)
    print("prepared exactly 3 opaque local-smoke pairs")
    print("plan: {}".format(output))
    print("private assignments: {}".format(assignments_output))


def run_fake(args: argparse.Namespace) -> None:
    study = load_study(Path(args.study))
    plan_path = require_regular_file(Path(args.plan), "local plan")
    plan = validate_plan(plan_path, study)
    assignments_path = require_private_file(Path(args.assignments), "local assignments")
    assignments = validate_assignments(assignments_path, plan)
    evidence_path = Path(args.evidence)
    require_real_directory(evidence_path.parent, "evidence output parent")
    if evidence_path.exists() or evidence_path.is_symlink():
        die("refusing to overwrite existing evidence output: {}".format(evidence_path))
    run_dir = mkdir_new(Path(args.output_dir))
    try:
        if Path(os.path.commonpath([str(run_dir), str(evidence_path.resolve(strict=False))])) == run_dir:
            die("public evidence must be outside the private run directory")
    except ValueError:
        pass
    fake_behavior = args.fake_behavior
    child_marker = run_dir / ".orphan-survived.marker" \
        if fake_behavior == "orphan-on-success" else None
    if child_marker is not None and (child_marker.exists() or child_marker.is_symlink()):
        die("internal orphan marker target must begin absent")
    ledger = Ledger(run_dir / "attempt-ledger.jsonl", study["id"], plan["plan_id"],
                    study["binding"]["transport_sha256"])
    mappings = assignment_map(assignments)
    pair_records = []
    for pair in plan["pairs"]:
        pair_root = mkdir_new(run_dir / pair["pair_id"])
        arms = []
        for arm_id in pair["opaque_arm_order"]:
            arms.append(run_arm(study, plan, pair, arm_id,
                                mappings[pair["pair_id"]][arm_id], pair_root, ledger,
                                fake_behavior, child_marker))
        pair_records.append({
            "pair_id": pair["pair_id"], "task_id": pair["task_id"],
            "replicate": pair["replicate"],
            "repository_tree_sha256": pair["repository_tree_sha256"],
            "planned_budgets": pair["budgets"], "arms": arms,
        })
    ledger_binding = ledger.close()
    if child_marker is not None and (child_marker.exists() or child_marker.is_symlink()):
        die("fake transport child escaped process-group cleanup")
    records = {
        "schema_version": 1, "kind": "mainframe-agent-impact-local-private-records",
        "study_id": study["id"], "plan_id": plan["plan_id"],
        "platform": "{} {}".format(platform.system(), platform.machine()),
        "python_version": platform.python_version(), "fake_behavior": fake_behavior,
        "allowed_environment_names": ALLOWED_ENVIRONMENT_NAMES,
        "transport_sha256": study["binding"]["transport_sha256"],
        "ledger": ledger_binding, "pairs": pair_records,
    }
    validate_run_records(study, plan, assignments, run_dir, records)
    atomic_json(run_dir / "records.json", records, 0o600)
    evidence = build_evidence(study, plan_path, plan, assignments_path, run_dir, records)
    atomic_json(evidence_path, evidence, 0o600)
    print("local development smoke complete: 3 pairs, 12 fake phase attempts")
    print("verified outcome shape: 3 ties; paired delta 0")
    print("evidence: {}".format(evidence_path))


def verify(args: argparse.Namespace) -> None:
    study = load_study(Path(args.study))
    plan_path = require_regular_file(Path(args.plan), "local plan")
    plan = validate_plan(plan_path, study)
    assignments_path = require_private_file(Path(args.assignments), "local assignments")
    assignments = validate_assignments(assignments_path, plan)
    run_dir = require_real_directory(Path(args.output_dir), "private local run directory")
    records_path = require_regular_file(run_dir / "records.json", "private local records")
    records = validate_run_records(study, plan, assignments, run_dir,
                                   load_json(records_path, "private local records"))
    actual = validate_public_evidence(load_json(Path(args.evidence), "local evidence"))
    expected = build_evidence(study, plan_path, plan, assignments_path, run_dir, records)
    if canonical_bytes(actual) != canonical_bytes(expected):
        die("local evidence does not reproduce exactly from the selected bound inputs")
    print("verified: local-development-smoke-protocol-conformance-only")
    print("real agent/provider/Pi/Ollama sessions: 0")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="MAINFRAME local paired-development smoke (fake transport only)")
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare", help="prepare exactly three opaque pairs; runs nothing")
    prepare_parser.add_argument("--study", default=str(DEFAULT_STUDY))
    prepare_parser.add_argument("--seed", required=True)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--assignments-output", required=True)
    prepare_parser.set_defaults(handler=prepare)

    run_parser = subparsers.add_parser("run", help="explicitly run the checked-in deterministic fake transport")
    run_parser.add_argument("--fake-transport", action="store_true", required=True,
                            help="required; no real adapter mode exists in this protocol")
    run_parser.add_argument("--study", default=str(DEFAULT_STUDY))
    run_parser.add_argument("--plan", required=True)
    run_parser.add_argument("--assignments", required=True)
    run_parser.add_argument("--output-dir", required=True)
    run_parser.add_argument("--evidence", required=True)
    run_parser.add_argument("--fake-behavior", choices=("normal", "orphan-on-success"),
                            default="normal", help=argparse.SUPPRESS)
    run_parser.set_defaults(handler=run_fake)

    verify_parser = subparsers.add_parser("verify", help="offline exact verification; starts nothing")
    verify_parser.add_argument("--study", default=str(DEFAULT_STUDY))
    verify_parser.add_argument("--plan", required=True)
    verify_parser.add_argument("--assignments", required=True)
    verify_parser.add_argument("--output-dir", required=True)
    verify_parser.add_argument("--evidence", required=True)
    verify_parser.set_defaults(handler=verify)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.handler(args)
    except ProtocolError as error:
        print("local agent-impact protocol error: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

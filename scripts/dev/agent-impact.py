#!/usr/bin/env python3
"""Credentials-free foundation for MAINFRAME Agent Impact Protocol v1.

The only command that starts an agent runner is ``run --runner``. ``prepare``
and ``verify`` are strictly local. The checked-in conformance suite is fixture
only and can never produce measured agent-quality evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
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
from typing import Any, Dict, Iterable, List, NoReturn, Optional, Sequence, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROTOCOL_ROOT = PROJECT_ROOT / "evals" / "agent-impact"
DEFAULT_SUITE = DEFAULT_PROTOCOL_ROOT / "suites" / "conformance-v1.json"
SCHEMA_NAMES = (
    "suite.schema.json",
    "task.schema.json",
    "runner-request.schema.json",
    "runner-result.schema.json",
    "evidence.schema.json",
)
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
PAIR_RE = re.compile(r"^pair-[0-9a-f]{16}$")
ARM_RE = re.compile(r"^arm-[0-9a-f]{16}$")
ENV_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_PROTOCOL_FILE_BYTES = 8 * 1024 * 1024
MAX_RUNNER_OUTPUT_BYTES = 8 * 1024 * 1024
PROCESS_GROUP_GRACE_SECONDS = 0.5
BASE_RUNNER_ENV = {
    "CI",
    "HOME",
    "LANG",
    "LC_ALL",
    "LOGNAME",
    "MAINFRAME_EVAL_PROTOCOL",
    "NO_COLOR",
    "PATH",
    "TMPDIR",
    "USER",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_STATE_HOME",
}


class ProtocolError(RuntimeError):
    """A fail-closed protocol validation error."""


def die(message: str) -> NoReturn:
    raise ProtocolError(message)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("digest input is unavailable: {}: {}".format(path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die("digest input must be a regular, non-symlink file: {}".format(path))
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_mode(path: Path) -> int:
    return stat.S_IMODE(path.lstat().st_mode)


def require_real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        die("{} must be a real directory: {}".format(label, path))
    return path.resolve(strict=True)


def require_regular_file(path: Path, label: str,
                         maximum_bytes: int = MAX_PROTOCOL_FILE_BYTES,
                         executable: bool = False) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die("{} must be a regular, non-symlink file: {}".format(label, path))
    if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
        die("{} has an unsupported size: {} ({} bytes)".format(
            label, path, metadata.st_size))
    if executable and not os.access(str(path), os.X_OK):
        die("{} must be executable: {}".format(label, path))
    return path.resolve(strict=True)


def load_json_text(text: str, label: str) -> Any:
    def reject_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                die("{} contains duplicate key {!r}".format(label, key))
            result[key] = value
        return result

    try:
        return json.loads(text, object_pairs_hook=reject_duplicates)
    except json.JSONDecodeError as error:
        die("{} is not valid JSON: {}".format(label, error))


def load_json(path: Path, label: str, maximum_bytes: int = MAX_JSON_BYTES) -> Any:
    path = require_regular_file(path, label, maximum_bytes=maximum_bytes)
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        die("{} cannot be read as UTF-8: {}".format(label, error))
    return load_json_text(text, label)


def exact_keys(value: Any, expected: Iterable[str], label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        die("{} must be a JSON object".format(label))
    expected_set = set(expected)
    actual_set = set(value)
    if actual_set != expected_set:
        missing = sorted(expected_set - actual_set)
        extras = sorted(actual_set - expected_set)
        die("{} keys differ (missing={}, extras={})".format(label, missing, extras))
    return value


def require_string(value: Any, label: str, pattern: Optional[re.Pattern] = None) -> str:
    if not isinstance(value, str) or not value:
        die("{} must be a non-empty string".format(label))
    if pattern is not None and pattern.fullmatch(value) is None:
        die("{} has an invalid value: {!r}".format(label, value))
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        die("{} contains a control character".format(label))
    return value


def require_integer(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        die("{} must be an integer".format(label))
    if value < minimum or value > maximum:
        die("{} is outside [{}, {}]".format(label, minimum, maximum))
    return value


def require_number(value: Any, label: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        die("{} must be a number".format(label))
    number = float(value)
    if number < minimum or number > maximum:
        die("{} is outside [{}, {}]".format(label, minimum, maximum))
    return number


def safe_relative_path(value: Any, label: str) -> PurePosixPath:
    text = require_string(value, label)
    if "\\" in text:
        die("{} must use POSIX separators".format(label))
    relative = PurePosixPath(text)
    if relative.is_absolute() or not relative.parts:
        die("{} must be a relative path".format(label))
    if any(part in ("", ".", "..") for part in relative.parts):
        die("{} contains an unsafe path component".format(label))
    return relative


def resolve_confined(root: Path, relative: PurePosixPath, label: str,
                     want_directory: bool = False) -> Path:
    root = require_real_directory(root, "{} root".format(label))
    current = root
    for index, component in enumerate(relative.parts):
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            die("{} is unavailable: {}: {}".format(label, current, error))
        if stat.S_ISLNK(metadata.st_mode):
            die("{} traverses a symbolic link: {}".format(label, current))
        is_last = index == len(relative.parts) - 1
        if not is_last and not stat.S_ISDIR(metadata.st_mode):
            die("{} parent is not a directory: {}".format(label, current))
    if want_directory:
        return require_real_directory(current, label)
    return require_regular_file(current, label)


def tree_records(root: Path) -> List[Dict[str, Any]]:
    root = require_real_directory(root, "tree root")
    records: List[Dict[str, Any]] = []
    for current, directories, files in os.walk(str(root), topdown=True, followlinks=False):
        current_path = Path(current)
        directories.sort()
        files.sort()
        for name in list(directories):
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                die("tree contains an unsafe directory entry: {}".format(path))
            relative = path.relative_to(root).as_posix()
            records.append({"path": relative, "type": "directory",
                            "mode": format(stat.S_IMODE(metadata.st_mode), "04o")})
        for name in files:
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                die("tree contains an unsafe file entry: {}".format(path))
            if metadata.st_size > MAX_PROTOCOL_FILE_BYTES:
                die("tree file is oversized: {}".format(path))
            relative = path.relative_to(root).as_posix()
            records.append({
                "path": relative,
                "type": "file",
                "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
                "size_bytes": metadata.st_size,
                "sha256": sha256_file(path),
            })
    records.sort(key=lambda record: (record["path"], record["type"]))
    return records


def tree_digest(root: Path) -> str:
    return sha256_bytes(canonical_bytes(tree_records(root)))


def atomic_json(path: Path, value: Any, mode: int) -> None:
    parent = require_real_directory(path.parent, "output parent")
    target = parent / path.name
    if target.exists() or target.is_symlink():
        die("refusing to overwrite existing output: {}".format(target))
    descriptor, temporary_name = tempfile.mkstemp(prefix=".{}.tmp.".format(path.name),
                                                  dir=str(parent))
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        payload = canonical_bytes(value) + b"\n"
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        descriptor = -1
        try:
            os.link(str(temporary), str(target))
        except FileExistsError:
            die("refusing to overwrite existing output: {}".format(target))
        os.chmod(str(target), mode)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def protocol_root_for_suite(suite_path: Path) -> Path:
    suite_path = require_regular_file(suite_path, "suite")
    if suite_path.parent.name != "suites":
        die("suite must be a regular file directly under a suites directory")
    protocol_root = require_real_directory(suite_path.parent.parent, "protocol root")
    for schema_name in SCHEMA_NAMES:
        require_regular_file(protocol_root / schema_name,
                             "protocol schema {}".format(schema_name))
    return protocol_root


def validate_task(task_path: Path, protocol_root: Path) -> Dict[str, Any]:
    task = exact_keys(load_json(task_path, "task"), (
        "schema_version", "kind", "id", "title", "category", "repository",
        "phases", "transition", "budgets", "grader",
    ), "task")
    if task["schema_version"] != 1 or task["kind"] != "mainframe-agent-impact-task":
        die("task schema_version or kind is unsupported")
    task_id = require_string(task["id"], "task.id", ID_RE)
    require_string(task["title"], "task.title")
    if task["category"] != "fresh-session-handoff":
        die("task.category must be fresh-session-handoff")
    task_directory = require_real_directory(task_path.parent, "task directory")
    repository_relative = safe_relative_path(task["repository"], "task.repository")
    repository = resolve_confined(task_directory, repository_relative,
                                  "task repository", want_directory=True)
    repository_records = tree_records(repository)
    if not any(record["type"] == "file" for record in repository_records):
        die("task repository must contain at least one regular file")

    phases = task["phases"]
    if not isinstance(phases, list) or len(phases) != 2:
        die("task.phases must contain exactly investigate and implement")
    expected_phases = (("investigate", False), ("implement", True))
    prompt_bindings: List[Dict[str, Any]] = []
    phase_records: List[Dict[str, Any]] = []
    for index, (expected_id, expected_edits) in enumerate(expected_phases):
        phase = exact_keys(phases[index], ("id", "prompt", "workspace_edits"),
                           "task.phases[{}]".format(index))
        if phase["id"] != expected_id or phase["workspace_edits"] is not expected_edits:
            die("task phase {} has an invalid contract".format(index))
        prompt_relative = safe_relative_path(phase["prompt"],
                                             "task phase prompt")
        if len(prompt_relative.parts) != 1 or not prompt_relative.name.endswith(".md"):
            die("task prompt must be a direct Markdown child of the task directory")
        prompt = resolve_confined(task_directory, prompt_relative, "task prompt")
        prompt_bindings.append({"path": prompt_relative.as_posix(),
                                "sha256": sha256_file(prompt)})
        phase_records.append({"id": expected_id, "prompt_path": prompt,
                              "workspace_edits": expected_edits})

    transition = exact_keys(task["transition"], (
        "fresh_host_state", "preserve_workspace", "context_budget", "control",
        "treatment",
    ), "task.transition")
    if transition["fresh_host_state"] is not True or transition["preserve_workspace"] is not True:
        die("task transition must preserve the workspace across fresh host state")
    if transition["control"] != "native-bounded-handoff" or \
            transition["treatment"] != "mainframe-awm-handoff":
        die("task transition arm contracts are unsupported")
    context_budget = exact_keys(transition["context_budget"], ("unit", "maximum"),
                                "task.transition.context_budget")
    if context_budget["unit"] != "bytes-under-LC_ALL-C":
        die("task context budget unit is unsupported")
    maximum_context_bytes = require_integer(context_budget["maximum"],
                                            "maximum context bytes", 1, 65536)

    budgets = exact_keys(task["budgets"], (
        "wall_seconds_per_phase", "maximum_tool_calls_per_phase",
    ), "task.budgets")
    wall_seconds = require_number(budgets["wall_seconds_per_phase"],
                                  "wall seconds per phase", 0.1, 7200)
    maximum_tool_calls = require_integer(budgets["maximum_tool_calls_per_phase"],
                                         "maximum tool calls", 1, 1000)

    grader = exact_keys(task["grader"], ("command", "maximum_score"), "task.grader")
    grader_relative = safe_relative_path(grader["command"], "task.grader.command")
    if len(grader_relative.parts) != 1 or not grader_relative.name.endswith(".py"):
        die("task grader must be a direct Python child of the task directory")
    grader_path = resolve_confined(task_directory, grader_relative, "task grader")
    maximum_score = require_integer(grader["maximum_score"], "grader maximum score",
                                    1, 1000000)

    binding = {
        "task_path": task_path.relative_to(protocol_root).as_posix(),
        "task_sha256": sha256_file(task_path),
        "task_id": task_id,
        "prompt_files": prompt_bindings,
        "repository_path": repository_relative.as_posix(),
        "repository_tree_sha256": sha256_bytes(canonical_bytes(repository_records)),
        "grader_path": grader_relative.as_posix(),
        "grader_sha256": sha256_file(grader_path),
    }
    binding["task_bundle_sha256"] = sha256_bytes(canonical_bytes(binding))
    return {
        "id": task_id,
        "path": task_path,
        "directory": task_directory,
        "repository": repository,
        "phases": phase_records,
        "maximum_context_bytes": maximum_context_bytes,
        "wall_seconds": wall_seconds,
        "maximum_tool_calls": maximum_tool_calls,
        "grader": grader_path,
        "maximum_score": maximum_score,
        "binding": binding,
    }


def load_suite(suite_path: Path) -> Dict[str, Any]:
    suite_path = require_regular_file(suite_path, "suite")
    protocol_root = protocol_root_for_suite(suite_path)
    suite = exact_keys(load_json(suite_path, "suite"),
                       ("schema_version", "kind", "id", "description", "tasks"),
                       "suite")
    if suite["schema_version"] != 1 or suite["kind"] != "mainframe-agent-impact-suite":
        die("suite schema_version or kind is unsupported")
    suite_id = require_string(suite["id"], "suite.id", ID_RE)
    require_string(suite["description"], "suite.description")
    task_values = suite["tasks"]
    if not isinstance(task_values, list) or not task_values:
        die("suite.tasks must be a non-empty array")
    if len(task_values) != len(set(task_values)):
        die("suite.tasks contains duplicates")
    tasks: List[Dict[str, Any]] = []
    for index, task_value in enumerate(task_values):
        relative = safe_relative_path(task_value, "suite.tasks[{}]".format(index))
        if len(relative.parts) != 3 or relative.parts[0] != "tasks" or \
                relative.parts[2] != "task.json":
            die("suite task path must be tasks/ID/task.json")
        task_path = resolve_confined(protocol_root, relative, "suite task")
        task = validate_task(task_path, protocol_root)
        if relative.parts[1] != task["id"]:
            die("task directory name must match task.id")
        tasks.append(task)
    task_ids = [task["id"] for task in tasks]
    if len(task_ids) != len(set(task_ids)):
        die("suite contains duplicate task IDs")
    binding = {
        "suite_path": suite_path.relative_to(protocol_root).as_posix(),
        "suite_sha256": sha256_file(suite_path),
        "suite_id": suite_id,
        "tasks": [task["binding"] for task in tasks],
    }
    binding["suite_bundle_sha256"] = sha256_bytes(canonical_bytes(binding))
    return {"id": suite_id, "path": suite_path, "protocol_root": protocol_root,
            "tasks": tasks, "binding": binding}


def protocol_bindings(protocol_root: Path) -> List[Dict[str, str]]:
    paths = [PROJECT_ROOT / "scripts" / "dev" / "agent-impact.py"]
    paths.extend(protocol_root / name for name in SCHEMA_NAMES)
    bindings: List[Dict[str, str]] = []
    for path in paths:
        path = require_regular_file(path, "protocol input")
        try:
            relative = path.relative_to(PROJECT_ROOT).as_posix()
        except ValueError:
            relative = path.relative_to(protocol_root).as_posix()
            relative = "protocol-root/{}".format(relative)
        bindings.append({"path": relative, "sha256": sha256_file(path)})
    bindings.sort(key=lambda item: item["path"])
    return bindings


def derive_hex(seed: str, purpose: str, length: int = 64) -> str:
    return hmac.new(seed.encode("utf-8"), purpose.encode("utf-8"),
                    hashlib.sha256).hexdigest()[:length]


def build_plan(suite: Dict[str, Any], seed: str, replicates: int) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    seed = require_string(seed, "seed")
    if len(seed.encode("utf-8")) > 4096:
        die("seed is too long")
    seed_sha = sha256_bytes(seed.encode("utf-8"))
    plan_id = "plan-{}".format(derive_hex(seed,
        "plan\0{}\0{}".format(suite["binding"]["suite_bundle_sha256"], replicates), 16))
    assignment_salt = derive_hex(seed, "assignment-salt\0{}".format(plan_id))
    pairs: List[Dict[str, Any]] = []
    assignment_pairs: List[Dict[str, Any]] = []
    for task in suite["tasks"]:
        for replicate in range(1, replicates + 1):
            material = "{}\0{}\0{}".format(plan_id, task["id"], replicate)
            pair_id = "pair-{}".format(derive_hex(seed, "pair\0" + material, 16))
            arms = [
                "arm-{}".format(derive_hex(seed, "arm-0\0" + material, 16)),
                "arm-{}".format(derive_hex(seed, "arm-1\0" + material, 16)),
            ]
            if int(derive_hex(seed, "order\0" + material, 2), 16) % 2:
                arms.reverse()
            control_index = int(derive_hex(seed, "assignment\0" + material, 2), 16) % 2
            mapping = [
                {"opaque_arm_id": arms[index],
                 "mode": "control" if index == control_index else "treatment"}
                for index in range(2)
            ]
            pairs.append({
                "pair_id": pair_id,
                "task_id": task["id"],
                "replicate": replicate,
                "instance_seed_sha256": sha256_bytes(
                    (seed + "\0instance\0" + material).encode("utf-8")),
                "task_bundle_sha256": task["binding"]["task_bundle_sha256"],
                "repository_tree_sha256": task["binding"]["repository_tree_sha256"],
                "opaque_arm_order": arms,
                "budgets": {
                    "wall_seconds_per_phase": task["wall_seconds"],
                    "maximum_tool_calls_per_phase": task["maximum_tool_calls"],
                    "maximum_context_bytes": task["maximum_context_bytes"],
                },
            })
            assignment_pairs.append({"pair_id": pair_id, "arms": mapping})
    assignments = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-private-assignments",
        "plan_id": plan_id,
        "salt": assignment_salt,
        "pairs": assignment_pairs,
    }
    commitment = sha256_bytes(canonical_bytes(assignments))
    plan = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-plan",
        "plan_id": plan_id,
        "suite": suite["binding"],
        "protocol_inputs": protocol_bindings(suite["protocol_root"]),
        "seed_sha256": seed_sha,
        "replicates": replicates,
        "assignment_commitment_sha256": commitment,
        "pairs": pairs,
    }
    return plan, assignments


def validate_binding_digest(value: Any, label: str) -> str:
    return require_string(value, label, SHA_RE)


def validate_plan(plan_path: Path, suite: Dict[str, Any]) -> Dict[str, Any]:
    plan = exact_keys(load_json(plan_path, "plan"), (
        "schema_version", "kind", "plan_id", "suite", "protocol_inputs",
        "seed_sha256", "replicates", "assignment_commitment_sha256", "pairs",
    ), "plan")
    if plan["schema_version"] != 1 or plan["kind"] != "mainframe-agent-impact-plan":
        die("plan schema_version or kind is unsupported")
    require_string(plan["plan_id"], "plan.plan_id",
                   re.compile(r"^plan-[0-9a-f]{16}$"))
    validate_binding_digest(plan["seed_sha256"], "plan.seed_sha256")
    validate_binding_digest(plan["assignment_commitment_sha256"],
                            "plan.assignment_commitment_sha256")
    replicates = require_integer(plan["replicates"], "plan.replicates", 1, 100)
    if plan["suite"] != suite["binding"]:
        die("plan suite binding does not match the selected current suite")
    current_protocol = protocol_bindings(suite["protocol_root"])
    if plan["protocol_inputs"] != current_protocol:
        die("plan protocol inputs do not match the selected current implementation")
    pairs = plan["pairs"]
    if not isinstance(pairs, list) or not pairs:
        die("plan.pairs must be a non-empty array")
    expected_count = len(suite["tasks"]) * replicates
    if len(pairs) != expected_count:
        die("plan pair count does not match suite tasks and replicates")
    task_map = {task["id"]: task for task in suite["tasks"]}
    seen_pairs = set()
    seen_arms = set()
    task_replicates = set()
    for index, pair_value in enumerate(pairs):
        pair = exact_keys(pair_value, (
            "pair_id", "task_id", "replicate", "instance_seed_sha256",
            "task_bundle_sha256", "repository_tree_sha256", "opaque_arm_order",
            "budgets",
        ), "plan.pairs[{}]".format(index))
        pair_id = require_string(pair["pair_id"], "plan pair ID", PAIR_RE)
        if pair_id in seen_pairs:
            die("plan contains duplicate pair ID")
        seen_pairs.add(pair_id)
        task_id = require_string(pair["task_id"], "plan task ID", ID_RE)
        if task_id not in task_map:
            die("plan refers to an unknown task: {}".format(task_id))
        task = task_map[task_id]
        replicate = require_integer(pair["replicate"], "plan replicate", 1, replicates)
        if (task_id, replicate) in task_replicates:
            die("plan repeats a task/replicate pair")
        task_replicates.add((task_id, replicate))
        validate_binding_digest(pair["instance_seed_sha256"], "instance seed digest")
        if pair["task_bundle_sha256"] != task["binding"]["task_bundle_sha256"] or \
                pair["repository_tree_sha256"] != task["binding"]["repository_tree_sha256"]:
            die("plan task binding drifted for {}".format(task_id))
        arms = pair["opaque_arm_order"]
        if not isinstance(arms, list) or len(arms) != 2 or len(set(arms)) != 2:
            die("each plan pair must contain two unique opaque arms")
        for arm in arms:
            require_string(arm, "opaque arm ID", ARM_RE)
            if arm in seen_arms:
                die("opaque arm ID is reused across pairs")
            seen_arms.add(arm)
        budgets = exact_keys(pair["budgets"], (
            "wall_seconds_per_phase", "maximum_tool_calls_per_phase",
            "maximum_context_bytes",
        ), "plan pair budgets")
        if float(budgets["wall_seconds_per_phase"]) != task["wall_seconds"] or \
                budgets["maximum_tool_calls_per_phase"] != task["maximum_tool_calls"] or \
                budgets["maximum_context_bytes"] != task["maximum_context_bytes"]:
            die("plan pair budgets do not equal the bound task budgets")
    if len(task_replicates) != expected_count:
        die("plan does not cover every task/replicate exactly once")
    return plan


def validate_assignments(assignments_path: Path, plan: Dict[str, Any]) -> Dict[str, Any]:
    assignments = exact_keys(load_json(assignments_path, "private assignments"), (
        "schema_version", "kind", "plan_id", "salt", "pairs",
    ), "private assignments")
    if assignments["schema_version"] != 1 or \
            assignments["kind"] != "mainframe-agent-impact-private-assignments":
        die("private assignment schema_version or kind is unsupported")
    if assignments["plan_id"] != plan["plan_id"]:
        die("private assignments refer to a different plan")
    require_string(assignments["salt"], "assignment salt", SHA_RE)
    if sha256_bytes(canonical_bytes(assignments)) != plan["assignment_commitment_sha256"]:
        die("private assignment commitment does not match the plan")
    values = assignments["pairs"]
    if not isinstance(values, list) or len(values) != len(plan["pairs"]):
        die("private assignment pair count does not match the plan")
    plan_pairs = {pair["pair_id"]: pair for pair in plan["pairs"]}
    seen = set()
    for index, value in enumerate(values):
        assignment = exact_keys(value, ("pair_id", "arms"),
                                "private assignments pair {}".format(index))
        pair_id = require_string(assignment["pair_id"], "assignment pair ID", PAIR_RE)
        if pair_id in seen or pair_id not in plan_pairs:
            die("private assignments contain duplicate or unknown pair ID")
        seen.add(pair_id)
        arms = assignment["arms"]
        if not isinstance(arms, list) or len(arms) != 2:
            die("private assignment pair must contain two arms")
        mapped = {}
        for arm_value in arms:
            arm = exact_keys(arm_value, ("opaque_arm_id", "mode"), "assignment arm")
            arm_id = require_string(arm["opaque_arm_id"], "assignment arm ID", ARM_RE)
            if arm_id in mapped or arm["mode"] not in ("control", "treatment"):
                die("private assignment arm mapping is invalid")
            mapped[arm_id] = arm["mode"]
        if set(mapped) != set(plan_pairs[pair_id]["opaque_arm_order"]) or \
                sorted(mapped.values()) != ["control", "treatment"]:
            die("private assignment arms do not exactly map the plan pair")
    if seen != set(plan_pairs):
        die("private assignments do not cover every plan pair")
    return assignments


def assignment_map(assignments: Dict[str, Any]) -> Dict[str, Dict[str, str]]:
    return {
        pair["pair_id"]: {arm["opaque_arm_id"]: arm["mode"] for arm in pair["arms"]}
        for pair in assignments["pairs"]
    }


def safe_runner_path(path: Path) -> Path:
    return require_regular_file(path, "runner", executable=True)


def controlled_path() -> str:
    values = [str(Path(sys.executable).resolve().parent), "/usr/local/bin", "/usr/bin", "/bin"]
    unique: List[str] = []
    for value in values:
        if value not in unique:
            unique.append(value)
    return os.pathsep.join(unique)


def mkdir_no_clobber(path: Path, mode: int = 0o700) -> Path:
    parent = require_real_directory(path.parent, "directory output parent")
    target = parent / path.name
    try:
        target.mkdir(mode=mode)
    except FileExistsError:
        die("refusing to reuse existing output directory: {}".format(target))
    return target.resolve(strict=True)


def copy_repository(source: Path, destination: Path) -> None:
    tree_records(source)
    if destination.exists() or destination.is_symlink():
        die("workspace destination already exists: {}".format(destination))
    shutil.copytree(str(source), str(destination), symlinks=False,
                    copy_function=shutil.copy2)
    tree_records(destination)


def validate_usage(value: Any, label: str) -> Dict[str, Any]:
    usage = exact_keys(value, (
        "input_tokens", "input_tokens_reason", "output_tokens", "output_tokens_reason",
    ), label)
    for name in ("input", "output"):
        tokens = usage["{}_tokens".format(name)]
        reason = usage["{}_tokens_reason".format(name)]
        if tokens is None:
            require_string(reason, "{}.{}_tokens_reason".format(label, name))
        else:
            require_integer(tokens, "{}.{}_tokens".format(label, name), 0, 10 ** 12)
            if reason is not None:
                die("{} token reason must be null when tokens are reported".format(name))
    return usage


def validate_runner_result(path: Path, phase: str, maximum_tool_calls: int) -> Dict[str, Any]:
    result = exact_keys(load_json(path, "runner result"), (
        "schema_version", "kind", "status", "handoff_relative_path", "usage",
        "tool_calls", "ambient_probe_seen",
    ), "runner result")
    if result["schema_version"] != 1 or \
            result["kind"] != "mainframe-agent-impact-runner-result":
        die("runner result schema_version or kind is unsupported")
    if result["status"] not in ("completed", "agent_failure"):
        die("runner result status is unsupported")
    validate_usage(result["usage"], "runner result usage")
    tool_calls = require_integer(result["tool_calls"], "runner result tool_calls", 0,
                                 10 ** 9)
    if result["ambient_probe_seen"] is not False:
        die("runner observed an ambient environment value that should have been scrubbed")
    handoff = result["handoff_relative_path"]
    if result["status"] == "completed" and phase == "investigate":
        relative = safe_relative_path(handoff, "runner handoff path")
        if len(relative.parts) != 1:
            die("runner handoff must be a direct child of its artifact directory")
    elif handoff is not None:
        die("only a completed investigate phase may return a handoff")
    result["budget_exhausted"] = tool_calls > maximum_tool_calls
    return result


def runner_environment(phase_root: Path, pass_names: Sequence[str]) -> Dict[str, str]:
    home = mkdir_no_clobber(phase_root / "home")
    config = mkdir_no_clobber(phase_root / "config")
    state = mkdir_no_clobber(phase_root / "state")
    cache = mkdir_no_clobber(phase_root / "cache")
    temporary = mkdir_no_clobber(phase_root / "tmp")
    environment = {
        "HOME": str(home),
        "USER": "mainframe-eval",
        "LOGNAME": "mainframe-eval",
        "XDG_CONFIG_HOME": str(config),
        "XDG_STATE_HOME": str(state),
        "XDG_CACHE_HOME": str(cache),
        "TMPDIR": str(temporary),
        "PATH": controlled_path(),
        "LC_ALL": "C",
        "LANG": "C",
        "NO_COLOR": "1",
        "CI": "1",
        "MAINFRAME_EVAL_PROTOCOL": "1",
    }
    for name in pass_names:
        environment[name] = os.environ[name]
    return environment


def run_process(command: Sequence[str], environment: Dict[str, str], timeout: float,
                stdout_path: Path, stderr_path: Path) -> Tuple[str, Optional[int]]:
    def apply_limits() -> None:
        resource.setrlimit(resource.RLIMIT_FSIZE,
                           (MAX_RUNNER_OUTPUT_BYTES, MAX_RUNNER_OUTPUT_BYTES))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    def stop_process_group(process: subprocess.Popen) -> bool:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        try:
            process.wait(timeout=PROCESS_GROUP_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError:
                return False
            try:
                process.wait(timeout=PROCESS_GROUP_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                return False
        # The group leader is reaped. Kill any non-detached descendants that
        # retained the runner's process group before proceeding to scoring.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return True
        except PermissionError:
            # Darwin can report EPERM for a group containing only an adopted
            # zombie after TERM. TERM was delivered while the leader was ours,
            # so no same-UID group member can continue executing at this point.
            return True
        return True

    with stdout_path.open("wb") as stdout_handle, stderr_path.open("wb") as stderr_handle:
        try:
            process = subprocess.Popen(
                list(command), env=environment, stdin=subprocess.DEVNULL,
                stdout=stdout_handle, stderr=stderr_handle,
                start_new_session=True, preexec_fn=apply_limits,
            )
        except OSError as error:
            stderr_handle.write(("runner launch failed: {}\n".format(error)).encode("utf-8"))
            return "infrastructure_failure", None
        try:
            return_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            group_stopped = stop_process_group(process)
            if not group_stopped:
                return "infrastructure_failure", None
            return "timeout", None
        group_stopped = stop_process_group(process)
        if not group_stopped:
            return "infrastructure_failure", return_code
    return ("completed", return_code) if return_code == 0 else \
        ("infrastructure_failure", return_code)


def output_digest(path: Path) -> Dict[str, Any]:
    try:
        metadata = path.lstat()
    except OSError:
        return {"present": False, "size_bytes": 0, "sha256": None}
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die("runner output is not a regular, non-symlink file: {}".format(path))
    if metadata.st_size > MAX_RUNNER_OUTPUT_BYTES:
        die("runner output exceeds the maximum evidence size: {}".format(path))
    if metadata.st_size == 0:
        return {"present": True, "size_bytes": 0,
                "sha256": sha256_bytes(b"")}
    return {"present": True, "size_bytes": metadata.st_size, "sha256": sha256_file(path)}


def invoke_phase(runner: Path, pair_id: str, arm_id: str, mode: str,
                 task: Dict[str, Any], phase_index: int, workspace: Path,
                 arm_root: Path, context_path: Optional[Path], timeout: float,
                 pass_names: Sequence[str]) -> Dict[str, Any]:
    phase = task["phases"][phase_index]
    phase_root = mkdir_no_clobber(arm_root / "phase-{}-{}".format(
        phase_index + 1, phase["id"]))
    artifact_dir = mkdir_no_clobber(phase_root / "artifacts")
    result_path = phase_root / "result.json"
    request_path = phase_root / "request.json"
    stdout_path = phase_root / "runner.stdout"
    stderr_path = phase_root / "runner.stderr"
    prompt_copy = phase_root / "prompt.md"
    shutil.copyfile(str(phase["prompt_path"]), str(prompt_copy))
    os.chmod(str(prompt_copy), 0o400)
    if sha256_file(prompt_copy) != sha256_file(phase["prompt_path"]):
        die("phase prompt changed while copying into the private run")
    environment = runner_environment(phase_root, pass_names)
    allowed_names = sorted(environment)
    request = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-run-request",
        "pair_id": pair_id,
        "opaque_arm_id": arm_id,
        "arm_mode": mode,
        "task_id": task["id"],
        "phase": phase["id"],
        "workspace": str(workspace),
        "prompt_path": str(prompt_copy),
        "context_path": str(context_path) if context_path is not None else None,
        "artifact_dir": str(artifact_dir),
        "result_path": str(result_path),
        "budgets": {
            "wall_seconds": timeout,
            "maximum_tool_calls": task["maximum_tool_calls"],
            "maximum_context_bytes": task["maximum_context_bytes"],
        },
        "environment_contract": {
            "fresh_host_state": True,
            "allowed_environment_names": allowed_names,
        },
    }
    atomic_json(request_path, request, 0o600)
    workspace_before = tree_digest(workspace)
    process_status, exit_code = run_process(
        [str(runner), str(request_path)], environment, timeout,
        stdout_path, stderr_path,
    )
    stdout_binding = output_digest(stdout_path)
    stderr_binding = output_digest(stderr_path)
    workspace_after = tree_digest(workspace)
    record: Dict[str, Any] = {
        "phase": phase["id"],
        "process_status": process_status,
        "runner_exit_code": exit_code,
        "request_sha256": sha256_file(request_path),
        "result_sha256": None,
        "stdout": stdout_binding,
        "stderr": stderr_binding,
        "workspace_before_sha256": workspace_before,
        "workspace_after_sha256": workspace_after,
        "status": process_status,
        "usage": None,
        "tool_calls": None,
        "context": None,
    }
    if not phase["workspace_edits"] and workspace_after != workspace_before:
        record["status"] = "infrastructure_failure"
        record["failure_reason"] = "workspace-edited-during-read-only-phase"
        return record
    if process_status != "completed":
        record["failure_reason"] = "runner-timeout" if process_status == "timeout" \
            else "runner-process-failure"
        return record
    if not result_path.exists() and not result_path.is_symlink():
        record["status"] = "infrastructure_failure"
        record["failure_reason"] = "runner-result-missing"
        return record
    try:
        result = validate_runner_result(result_path, phase["id"],
                                        task["maximum_tool_calls"])
    except ProtocolError as error:
        record["status"] = "infrastructure_failure"
        record["failure_reason"] = "invalid-runner-result: {}".format(error)
        record["result_sha256"] = sha256_file(result_path) \
            if result_path.is_file() and not result_path.is_symlink() else None
        return record
    record["result_sha256"] = sha256_file(result_path)
    record["usage"] = result["usage"]
    record["tool_calls"] = result["tool_calls"]
    if result["budget_exhausted"]:
        record["status"] = "budget_exhausted"
        record["failure_reason"] = "maximum-tool-calls-exceeded"
        return record
    if result["status"] == "agent_failure":
        record["status"] = "agent_failure"
        record["failure_reason"] = "runner-reported-agent-failure"
        return record
    record["status"] = "completed"
    if phase["id"] == "investigate":
        relative = safe_relative_path(result["handoff_relative_path"], "runner handoff")
        handoff = resolve_confined(artifact_dir, relative, "runner handoff")
        size = handoff.stat().st_size
        if size > task["maximum_context_bytes"]:
            record["status"] = "budget_exhausted"
            record["failure_reason"] = "maximum-context-bytes-exceeded"
            return record
        record["context"] = {
            "size_bytes": size,
            "sha256": sha256_file(handoff),
            "budget_bytes": task["maximum_context_bytes"],
        }
        record["private_handoff_path"] = str(handoff)
    return record


def grader_environment(grader_root: Path) -> Dict[str, str]:
    home = mkdir_no_clobber(grader_root / "home")
    temporary = mkdir_no_clobber(grader_root / "tmp")
    return {
        "HOME": str(home),
        "USER": "mainframe-eval-grader",
        "LOGNAME": "mainframe-eval-grader",
        "TMPDIR": str(temporary),
        "PATH": controlled_path(),
        "LC_ALL": "C",
        "LANG": "C",
        "NO_COLOR": "1",
        "CI": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }


def run_grader(task: Dict[str, Any], workspace: Path, arm_root: Path) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    grader = require_regular_file(task["grader"], "task grader")
    before_digest = sha256_file(grader)
    if before_digest != task["binding"]["grader_sha256"]:
        return None, "grader-digest-changed-before-scoring"
    try:
        common = Path(os.path.commonpath([str(grader), str(workspace)]))
    except ValueError:
        common = Path("/")
    if common == workspace or grader == workspace:
        return None, "grader-is-inside-agent-workspace"
    grader_root = mkdir_no_clobber(arm_root / "grader")
    stdout_path = grader_root / "grader.stdout"
    stderr_path = grader_root / "grader.stderr"
    environment = grader_environment(grader_root)
    process_status, exit_code = run_process(
        [sys.executable, str(grader), str(workspace)], environment, 30.0,
        stdout_path, stderr_path,
    )
    if process_status != "completed" or exit_code != 0:
        return None, "grader-process-failure"
    stdout_binding = output_digest(stdout_path)
    stderr_binding = output_digest(stderr_path)
    if stdout_binding["size_bytes"] > 65536:
        return None, "grader-output-oversized"
    try:
        text = stdout_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None, "grader-output-not-utf8"
    try:
        result = exact_keys(load_json_text(text, "grader output"), (
            "score", "maximum_score", "solved", "tests_passed", "tests_total",
        ), "grader output")
        score = require_integer(result["score"], "grader score", 0,
                                task["maximum_score"])
        maximum_score = require_integer(result["maximum_score"],
                                        "grader maximum score", 1, 1000000)
        tests_total = require_integer(result["tests_total"], "grader tests_total", 1,
                                      1000000)
        tests_passed = require_integer(result["tests_passed"], "grader tests_passed", 0,
                                       tests_total)
        if maximum_score != task["maximum_score"]:
            return None, "grader-maximum-score-drift"
        if not isinstance(result["solved"], bool):
            return None, "grader-solved-is-not-boolean"
        if result["solved"] != (score == maximum_score):
            return None, "grader-solved-does-not-match-score"
    except ProtocolError as error:
        return None, "invalid-grader-output: {}".format(error)
    if sha256_file(grader) != before_digest:
        return None, "grader-digest-changed-during-scoring"
    return {
        "score": score,
        "maximum_score": maximum_score,
        "normalized_score": round(score / maximum_score, 8),
        "solved": result["solved"],
        "tests_passed": tests_passed,
        "tests_total": tests_total,
        "grader_sha256": before_digest,
        "stdout": stdout_binding,
        "stderr": stderr_binding,
        "grader_outside_workspace": True,
    }, None


def public_phase_record(record: Dict[str, Any]) -> Dict[str, Any]:
    return {key: value for key, value in record.items()
            if key != "private_handoff_path"}


def run_arm(runner: Path, pair: Dict[str, Any], arm_id: str, mode: str,
            task: Dict[str, Any], pair_root: Path, timeout: float,
            pass_names: Sequence[str]) -> Dict[str, Any]:
    arm_root = mkdir_no_clobber(pair_root / arm_id)
    workspace = arm_root / "workspace"
    copy_repository(task["repository"], workspace)
    initial_snapshot = tree_digest(workspace)
    if initial_snapshot != pair["repository_tree_sha256"]:
        die("copied workspace does not match the planned repository snapshot")

    first = invoke_phase(runner, pair["pair_id"], arm_id, mode, task, 0,
                         workspace, arm_root, None, timeout, pass_names)
    phases = [public_phase_record(first)]
    outcome_status = first["status"]
    grader_result: Optional[Dict[str, Any]] = None
    infrastructure_reason: Optional[str] = None

    if first["status"] == "completed":
        private_handoff = Path(first["private_handoff_path"])
        context_root = mkdir_no_clobber(arm_root / "transition")
        context_path = context_root / "continuation-context.txt"
        if context_path.exists() or context_path.is_symlink():
            die("context destination already exists")
        shutil.copyfile(str(private_handoff), str(context_path))
        os.chmod(str(context_path), 0o600)
        if context_path.stat().st_size > task["maximum_context_bytes"] or \
                sha256_file(context_path) != first["context"]["sha256"]:
            die("bounded continuation context changed during transition")
        second = invoke_phase(runner, pair["pair_id"], arm_id, mode, task, 1,
                              workspace, arm_root, context_path, timeout, pass_names)
        phases.append(public_phase_record(second))
        outcome_status = second["status"]
        if second["status"] == "completed":
            grader_result, infrastructure_reason = run_grader(task, workspace, arm_root)
            if infrastructure_reason is not None:
                outcome_status = "infrastructure_failure"

    if outcome_status in ("agent_failure", "timeout", "budget_exhausted"):
        grader_result = {
            "score": 0,
            "maximum_score": task["maximum_score"],
            "normalized_score": 0.0,
            "solved": False,
            "tests_passed": 0,
            "tests_total": 0,
            "grader_sha256": task["binding"]["grader_sha256"],
            "stdout": {"present": False, "size_bytes": 0, "sha256": None},
            "stderr": {"present": False, "size_bytes": 0, "sha256": None},
            "grader_outside_workspace": True,
            "not_run_reason": "agent-outcome-{}".format(outcome_status),
        }
    elif outcome_status == "infrastructure_failure":
        grader_result = None

    usage = []
    for phase_record in phases:
        if phase_record["usage"] is not None:
            usage.append({"phase": phase_record["phase"], **phase_record["usage"]})
    result = {
        "opaque_arm_id": arm_id,
        "revealed_mode": mode,
        "initial_snapshot_sha256": initial_snapshot,
        "final_workspace_sha256": tree_digest(workspace),
        "fresh_host_state_per_phase": True,
        "equal_planned_budgets": True,
        "outcome_status": outcome_status,
        "infrastructure_failure_reason": infrastructure_reason,
        "phases": phases,
        "usage": usage,
        "grade": grader_result,
    }
    return result


def aggregate_pairs(pairs: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    valid = []
    invalid = []
    for pair in pairs:
        arms = {arm["revealed_mode"]: arm for arm in pair["arms"]}
        if set(arms) != {"control", "treatment"}:
            die("evidence pair does not contain exactly one control and treatment")
        if any(arm["outcome_status"] == "infrastructure_failure" or arm["grade"] is None
               for arm in arms.values()):
            invalid.append(pair["pair_id"])
        else:
            valid.append((pair, arms))
    control_solved = sum(1 for _, arms in valid if arms["control"]["grade"]["solved"])
    treatment_solved = sum(1 for _, arms in valid if arms["treatment"]["grade"]["solved"])
    control_score = sum(arms["control"]["grade"]["normalized_score"]
                        for _, arms in valid)
    treatment_score = sum(arms["treatment"]["grade"]["normalized_score"]
                          for _, arms in valid)
    wins = ties = losses = 0
    for _, arms in valid:
        delta = (arms["treatment"]["grade"]["normalized_score"] -
                 arms["control"]["grade"]["normalized_score"])
        if delta > 0:
            wins += 1
        elif delta < 0:
            losses += 1
        else:
            ties += 1
    count = len(valid)
    return {
        "pair_count": len(pairs),
        "valid_pair_count": count,
        "invalid_pair_count": len(invalid),
        "invalid_pair_ids": invalid,
        "control_solved_count": control_solved,
        "treatment_solved_count": treatment_solved,
        "control_success_rate": round(control_solved / count, 8) if count else None,
        "treatment_success_rate": round(treatment_solved / count, 8) if count else None,
        "paired_success_rate_delta": round((treatment_solved - control_solved) / count, 8)
        if count else None,
        "control_mean_normalized_score": round(control_score / count, 8) if count else None,
        "treatment_mean_normalized_score": round(treatment_score / count, 8) if count else None,
        "paired_mean_normalized_score_delta": round((treatment_score - control_score) / count, 8)
        if count else None,
        "treatment_wins": wins,
        "ties": ties,
        "treatment_losses": losses,
        "inference_statistics": "not-computed-for-fixture-conformance",
    }


def validate_public_evidence(evidence: Any) -> Dict[str, Any]:
    value = exact_keys(evidence, (
        "schema_version", "kind", "claim_scope", "protocol", "runtime",
        "execution", "pairs", "aggregate", "non_claims", "limitations",
    ), "evidence")
    if value["schema_version"] != 1 or value["kind"] != "mainframe-agent-impact-evidence":
        die("evidence schema_version or kind is unsupported")
    if value["claim_scope"] != "fixture-runner-protocol-conformance-only":
        die("v1 evidence claim scope must be fixture-runner protocol conformance only")
    non_claims = exact_keys(value["non_claims"], (
        "real_provider_inference", "agent_quality", "productivity",
        "comparative_agent_performance", "live_agent_sessions",
    ), "evidence.non_claims")
    expected_non_claims = {
        "real_provider_inference": "not-run",
        "agent_quality": "not-measured",
        "productivity": "not-measured",
        "comparative_agent_performance": "not-measured",
        "live_agent_sessions": 0,
    }
    if non_claims != expected_non_claims:
        die("fixture evidence non-claims were weakened")
    if not isinstance(value["pairs"], list) or not value["pairs"]:
        die("evidence pairs must be a non-empty array")
    if value["aggregate"] != aggregate_pairs(value["pairs"]):
        die("evidence aggregate does not derive exactly from its paired rows")

    def scan(item: Any) -> None:
        if isinstance(item, dict):
            for child in item.values():
                scan(child)
        elif isinstance(item, list):
            for child in item:
                scan(child)
        elif isinstance(item, str):
            if item.startswith("/"):
                die("public evidence contains an absolute private path")
            if "MAINFRAME_SHOULD_NOT_LEAK" in item:
                die("public evidence contains the ambient probe name")

    scan(value)
    return value


def raw_bundle_digest(run_dir: Path) -> str:
    return tree_digest(run_dir)


def build_evidence(suite: Dict[str, Any], plan_path: Path, plan: Dict[str, Any],
                   assignments_path: Path, assignments: Dict[str, Any], runner: Path,
                   run_dir: Path, records: Dict[str, Any]) -> Dict[str, Any]:
    pairs = records["pairs"]
    evidence = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-evidence",
        "claim_scope": "fixture-runner-protocol-conformance-only",
        "protocol": {
            "version": 1,
            "suite": suite["binding"],
            "protocol_inputs": protocol_bindings(suite["protocol_root"]),
            "plan_basename": plan_path.name,
            "plan_sha256": sha256_file(plan_path),
            "plan_id": plan["plan_id"],
            "assignment_commitment_sha256": plan["assignment_commitment_sha256"],
            "assignment_reveal_sha256": sha256_file(assignments_path),
            "assignment_publicly_revealed_after_scoring": True,
        },
        "runtime": {
            "harness_path": "scripts/dev/agent-impact.py",
            "harness_sha256": sha256_file(Path(__file__).resolve()),
            "runner_basename": runner.name,
            "runner_sha256": sha256_file(runner),
            "records_sha256": sha256_file(run_dir / "records.json"),
            "raw_run_bundle_sha256": raw_bundle_digest(run_dir),
            "platform": records["platform"],
            "python_version": records["python_version"],
            "mainframe_runtime_exercised": False,
            "awm_mechanism_exercised": False,
        },
        "execution": {
            "provider_mode": "fixture",
            "runner_invocation": "explicit-run-subcommand-only",
            "runner_received_arm_mode": True,
            "runner_was_not_blinded": True,
            "environment_scrubbed": True,
            "passed_environment_names": records["passed_environment_names"],
            "phase_timeout_seconds": records["phase_timeout_seconds"],
            "runner_output_file_limit_bytes": MAX_RUNNER_OUTPUT_BYTES,
            "pair_count": len(pairs),
            "live_agent_sessions": 0,
        },
        "pairs": pairs,
        "aggregate": aggregate_pairs(pairs),
        "non_claims": {
            "real_provider_inference": "not-run",
            "agent_quality": "not-measured",
            "productivity": "not-measured",
            "comparative_agent_performance": "not-measured",
            "live_agent_sessions": 0,
        },
        "limitations": {
            "toy_conformance_task_only": True,
            "fixture_runner_is_not_an_agent": True,
            "hidden_grader_not_mounted_in_workspace": True,
            "same_uid_not_os_sandbox": True,
            "detached_child_can_escape_process_group": True,
            "runner_and_agent_not_blinded_to_arm_configuration": True,
            "provider_tokens_and_cost": "not-measured",
            "generalization_beyond_fixture": "not-established",
            "machine_safety": "not-established",
        },
    }
    return validate_public_evidence(evidence)


def validate_pass_environment(names: Sequence[str]) -> List[str]:
    values: List[str] = []
    for name in names:
        require_string(name, "passed environment name", ENV_RE)
        if name in BASE_RUNNER_ENV:
            die("cannot override controlled runner environment name: {}".format(name))
        if name not in os.environ:
            die("requested passed environment name is unset: {}".format(name))
        if name in values:
            die("passed environment name is duplicated: {}".format(name))
        values.append(name)
    values.sort()
    return values


def validate_records(records: Any, plan: Dict[str, Any]) -> Dict[str, Any]:
    value = exact_keys(records, (
        "schema_version", "kind", "plan_id", "platform", "python_version",
        "passed_environment_names", "phase_timeout_seconds", "pairs",
    ), "private records")
    if value["schema_version"] != 1 or \
            value["kind"] != "mainframe-agent-impact-private-records":
        die("private record schema_version or kind is unsupported")
    if value["plan_id"] != plan["plan_id"]:
        die("private records refer to a different plan")
    require_string(value["platform"], "records.platform")
    require_string(value["python_version"], "records.python_version")
    if not isinstance(value["passed_environment_names"], list) or \
            value["passed_environment_names"] != sorted(set(value["passed_environment_names"])):
        die("private record environment names must be a sorted unique array")
    for name in value["passed_environment_names"]:
        require_string(name, "record environment name", ENV_RE)
    require_number(value["phase_timeout_seconds"], "record phase timeout", 0.1, 7200)
    pairs = value["pairs"]
    if not isinstance(pairs, list) or len(pairs) != len(plan["pairs"]):
        die("private record pair count does not match plan")
    planned = {pair["pair_id"]: pair for pair in plan["pairs"]}
    seen = set()
    for pair in pairs:
        if not isinstance(pair, dict):
            die("private record pair must be an object")
        pair_id = require_string(pair.get("pair_id"), "record pair ID", PAIR_RE)
        if pair_id in seen or pair_id not in planned:
            die("private records contain duplicate or unknown pair ID")
        seen.add(pair_id)
        if pair.get("task_id") != planned[pair_id]["task_id"] or \
                pair.get("replicate") != planned[pair_id]["replicate"]:
            die("private record task/replicate does not match plan")
        if pair.get("repository_tree_sha256") != planned[pair_id]["repository_tree_sha256"]:
            die("private record repository binding does not match plan")
        arms = pair.get("arms")
        if not isinstance(arms, list) or len(arms) != 2:
            die("private record pair must contain two arms")
        if [arm.get("opaque_arm_id") for arm in arms] != planned[pair_id]["opaque_arm_order"]:
            die("private record arm order does not match plan")
        initial = {arm.get("initial_snapshot_sha256") for arm in arms}
        if initial != {planned[pair_id]["repository_tree_sha256"]}:
            die("paired arms did not begin from one equal planned snapshot")
        if any(arm.get("equal_planned_budgets") is not True for arm in arms):
            die("paired arm does not assert equal planned budgets")
    if seen != set(planned):
        die("private records do not cover every plan pair")
    return value


def run_fixture(args: argparse.Namespace) -> None:
    suite = load_suite(Path(args.suite))
    plan_path = require_regular_file(Path(args.plan), "plan")
    plan = validate_plan(plan_path, suite)
    assignments_path = require_regular_file(Path(args.assignments), "private assignments")
    assignments = validate_assignments(assignments_path, plan)
    runner = safe_runner_path(Path(args.runner))
    pass_names = validate_pass_environment(args.pass_env)
    evidence_path = Path(args.evidence)
    if evidence_path.exists() or evidence_path.is_symlink():
        die("refusing to overwrite existing evidence output: {}".format(evidence_path))
    require_real_directory(evidence_path.parent, "evidence output parent")
    run_dir_path = Path(args.output_dir)
    run_dir = mkdir_no_clobber(run_dir_path)
    try:
        if Path(os.path.commonpath([str(run_dir), str(evidence_path.resolve(strict=False))])) == run_dir:
            die("evidence output must be outside the private run directory")
    except ValueError:
        pass
    task_map = {task["id"]: task for task in suite["tasks"]}
    mappings = assignment_map(assignments)
    pair_records: List[Dict[str, Any]] = []
    effective_timeout: Optional[float] = None
    for pair in plan["pairs"]:
        planned_timeout = float(pair["budgets"]["wall_seconds_per_phase"])
        timeout = planned_timeout
        if args.phase_timeout_override is not None:
            override = require_number(args.phase_timeout_override,
                                      "phase timeout override", 0.1, planned_timeout)
            timeout = override
        if effective_timeout is None:
            effective_timeout = timeout
        elif timeout != effective_timeout:
            die("all pairs must use one equal effective phase timeout")
        pair_root = mkdir_no_clobber(run_dir / pair["pair_id"])
        task = task_map[pair["task_id"]]
        arms = []
        for arm_id in pair["opaque_arm_order"]:
            mode = mappings[pair["pair_id"]][arm_id]
            arms.append(run_arm(runner, pair, arm_id, mode, task, pair_root,
                                timeout, pass_names))
        if {arm["initial_snapshot_sha256"] for arm in arms} != \
                {pair["repository_tree_sha256"]}:
            die("paired arm snapshots are not byte-identical")
        pair_records.append({
            "pair_id": pair["pair_id"],
            "task_id": pair["task_id"],
            "replicate": pair["replicate"],
            "repository_tree_sha256": pair["repository_tree_sha256"],
            "planned_budgets": pair["budgets"],
            "effective_wall_seconds_per_phase": timeout,
            "arms": arms,
        })
    records = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-private-records",
        "plan_id": plan["plan_id"],
        "platform": "{} {}".format(platform.system(), platform.machine()),
        "python_version": platform.python_version(),
        "passed_environment_names": pass_names,
        "phase_timeout_seconds": effective_timeout,
        "pairs": pair_records,
    }
    validate_records(records, plan)
    records_path = run_dir / "records.json"
    atomic_json(records_path, records, 0o600)
    evidence = build_evidence(suite, plan_path, plan, assignments_path,
                              assignments, runner, run_dir, records)
    atomic_json(evidence_path, evidence, 0o600)
    print("fixture protocol run complete: {} pair(s)".format(len(pair_records)))
    print("evidence: {}".format(evidence_path))


def verify_fixture(args: argparse.Namespace) -> None:
    suite = load_suite(Path(args.suite))
    plan_path = require_regular_file(Path(args.plan), "plan")
    plan = validate_plan(plan_path, suite)
    assignments_path = require_regular_file(Path(args.assignments), "private assignments")
    assignments = validate_assignments(assignments_path, plan)
    runner = safe_runner_path(Path(args.runner))
    run_dir = require_real_directory(Path(args.output_dir), "private run directory")
    records_path = require_regular_file(run_dir / "records.json", "private records")
    records = validate_records(load_json(records_path, "private records"), plan)
    actual = validate_public_evidence(load_json(Path(args.evidence), "evidence"))
    expected = build_evidence(suite, plan_path, plan, assignments_path,
                              assignments, runner, run_dir, records)
    if actual != expected:
        actual_bytes = canonical_bytes(actual)
        expected_bytes = canonical_bytes(expected)
        if sha256_bytes(actual_bytes) != sha256_bytes(expected_bytes):
            die("evidence does not reproduce exactly from the selected bound inputs")
    print("verified: fixture-runner protocol conformance only (agent impact not measured)")


def prepare(args: argparse.Namespace) -> None:
    suite = load_suite(Path(args.suite))
    replicates = require_integer(args.replicates, "replicates", 1, 100)
    plan_path = Path(args.output)
    assignments_path = Path(args.assignments_output)
    if plan_path == assignments_path:
        die("plan and private assignment outputs must be different paths")
    require_real_directory(plan_path.parent, "plan output parent")
    require_real_directory(assignments_path.parent, "assignment output parent")
    if plan_path.exists() or plan_path.is_symlink():
        die("refusing to overwrite existing plan output: {}".format(plan_path))
    if assignments_path.exists() or assignments_path.is_symlink():
        die("refusing to overwrite existing assignment output: {}".format(assignments_path))
    plan, assignments = build_plan(suite, args.seed, replicates)
    atomic_json(assignments_path, assignments, 0o600)
    atomic_json(plan_path, plan, 0o644)
    print("prepared {} deterministic pair(s)".format(len(plan["pairs"])))
    print("plan: {}".format(plan_path))
    print("private assignments: {}".format(assignments_path))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="MAINFRAME Agent Impact Protocol v1 credentials-free foundation")
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser(
        "prepare", help="deterministically prepare an opaque paired plan; never runs a runner")
    prepare_parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    prepare_parser.add_argument("--seed", required=True)
    prepare_parser.add_argument("--replicates", type=int, default=1)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--assignments-output", required=True)
    prepare_parser.set_defaults(handler=prepare)

    run_parser = subparsers.add_parser(
        "run", help="explicitly run a supplied runner; there is no implicit provider path")
    run_parser.add_argument("--fixture", action="store_true", required=True,
                            help="required in v1; generated evidence is fixture-only")
    run_parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    run_parser.add_argument("--plan", required=True)
    run_parser.add_argument("--assignments", required=True)
    run_parser.add_argument("--runner", required=True)
    run_parser.add_argument("--output-dir", required=True)
    run_parser.add_argument("--evidence", required=True)
    run_parser.add_argument("--pass-env", action="append", default=[])
    run_parser.add_argument("--phase-timeout-override", type=float)
    run_parser.set_defaults(handler=run_fixture)

    verify_parser = subparsers.add_parser(
        "verify", help="reproduce fixture evidence without starting a runner")
    verify_parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    verify_parser.add_argument("--plan", required=True)
    verify_parser.add_argument("--assignments", required=True)
    verify_parser.add_argument("--runner", required=True)
    verify_parser.add_argument("--output-dir", required=True)
    verify_parser.add_argument("--evidence", required=True)
    verify_parser.set_defaults(handler=verify_fixture)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.handler(args)
    except ProtocolError as error:
        print("agent-impact protocol error: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

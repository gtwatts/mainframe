#!/usr/bin/env python3
"""Validate the closed, receipt-derived MAINFRAME claim promotion contract."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import NoReturn, TypedDict


PROMOTION_ORDER = (
    "source-candidate",
    "control-plane-preview",
    "host-preview",
    "stable-release",
    "category-claim",
)
TOP_LEVEL_KEYS = {
    "schema_version", "contract_version", "receipt_schema", "target_claim",
    "advertised_claim", "promotions", "gates",
}
GATE_KEYS = {"summary", "evidence_paths", "receipt_refs", "remaining"}
RECEIPT_REF_KEYS = {"path", "sha256"}
RECEIPT_KEYS = {
    "schema_version", "receipt_type", "receipt_id", "gate_id", "proof_kind",
    "protocol_version", "subject", "command", "environment", "issued_at",
    "expires_at", "evidence", "result", "authority", "limitations",
}
SUBJECT_KEYS = {
    "kind", "source_revision", "source_tree_sha256", "inventory_sha256",
    "payload_sha256", "version",
}
COMMAND_KEYS = {"identity", "argv"}
ENVIRONMENT_KEYS = {"os", "architecture", "runner_class"}
EVIDENCE_KEYS = {"path", "sha256", "role"}
AUTHORITY_KEYS = {"class", "signer_id", "independence", "signature"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$")
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{7,127}$")
TOKEN_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{2,63}$")
COMMAND_PATTERN = re.compile(r"^mainframe\.[a-z0-9.-]+\.v[1-9][0-9]*$")
VERSION_PATTERN = re.compile(r"^[1-9][0-9]*\.[0-9]+\.[0-9]+$")
RECEIPT_SCHEMA_PATH = "config/control-plane-claim-receipt.schema.json"
ATTESTATION_EXCLUSIONS_PATH = "config/release-attestation-exclusions.txt"
EXPECTED_ATTESTATION_EXCLUSIONS = (
    "SHA256SUMS",
    "config/control-plane-claim.json",
    "config/control-plane-claim-receipts/",
)
DETACHED_ATTESTATION_COMMIT_PATHS = (
    "config/control-plane-claim.json",
    "config/control-plane-claim-receipts/",
)
RECEIPT_TYPE = "mainframe-control-plane-gate-receipt"
RECEIPT_PROTOCOL_VERSION = "1.0.0"
SOURCE_AUTHORITIES = ("local-verifier",)
MAX_LOCAL_RECEIPT_TTL = timedelta(days=7)
MAX_VERIFIER_OUTPUT = 65536
LOCAL_VERIFIER_CANDIDATES = {
    "python3": ("/usr/bin/python3", "/bin/python3"),
    "bats": (
        "/usr/bin/bats",
        "/usr/local/bin/bats",
        "/opt/homebrew/bin/bats",
        "/opt/local/bin/bats",
        "/home/linuxbrew/.linuxbrew/bin/bats",
    ),
}
FIXED_BASH_CANDIDATES = (
    "/opt/homebrew/bin/bash",
    "/usr/local/bin/bash",
    "/home/linuxbrew/.linuxbrew/bin/bash",
    "/opt/local/bin/bash",
    "/usr/bin/bash",
    "/bin/bash",
)
FIXED_VERIFIER_PATH = os.pathsep.join((
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/opt/local/bin",
    "/opt/local/sbin",
    "/home/linuxbrew/.linuxbrew/bin",
    "/home/linuxbrew/.linuxbrew/sbin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
))
MINIMUM_BASH_VERSION = (4, 4)


def proof(
    subject_kind: str,
    command_identity: str,
    argv: tuple[str, ...],
    authorities: tuple[str, ...] = SOURCE_AUTHORITIES,
    *,
    external_verifier: bool = False,
    forbidden_output: tuple[str, ...] = (),
) -> dict[str, object]:
    return {
        "subject_kind": subject_kind,
        "command_identity": command_identity,
        "argv": argv,
        "authorities": authorities,
        "external_verifier": external_verifier,
        "forbidden_output": forbidden_output,
    }


GATE_POLICIES: dict[str, dict[str, object]] = {
    "release-integrity": {
        "evidence_paths": (
            "scripts/dev/release.sh", "scripts/dev/release-payload.sh",
            "scripts/generate-sbom.sh", "scripts/build-release-archive.sh",
            "tests/release-archive.bats", ATTESTATION_EXCLUSIONS_PATH,
            "SHA256SUMS",
        ),
        "required": ("inventory-suite", "archive-reproducibility"), "partial": (),
        "proofs": {
            "inventory-suite": proof("source", "mainframe.release-integrity.inventory.v1", ("/bin/bash", "--noprofile", "--norc", "-p", "scripts/generate-sbom.sh", "--check")),
            "archive-reproducibility": proof("source", "mainframe.release-integrity.archive.v1", ("/bin/bash", "--noprofile", "--norc", "-p", "scripts/build-release-archive.sh", "--verify")),
        },
    },
    "semantic-authority": {
        "evidence_paths": ("config/semantic-trust-policy.json", "scripts/generate-manifest.py", "tests/owner-parity.bats"),
        "required": ("source-suite",), "partial": (),
        "proofs": {"source-suite": proof("source", "mainframe.semantic-authority.source.v1", ("python3", "-I", "-S", "-B", "scripts/check-owner-parity.py"))},
    },
    "runtime-closure": {
        "evidence_paths": ("config/runtime-closure.json", "scripts/generate-runtime-closure.py", "tests/runtime_closure.bats"),
        "required": ("source-suite",), "partial": (),
        "proofs": {"source-suite": proof("source", "mainframe.runtime-closure.source.v1", ("python3", "-I", "-S", "-B", "scripts/generate-runtime-closure.py", "--check"))},
    },
    "durable-authority-kernel": {
        "evidence_paths": (
            "control_plane/mainframe_control_plane/kernel.py",
            "control_plane/mainframe_control_plane/executor.py",
            "control_plane/mainframe_control_plane/worker.py",
            "tests/control_plane/test_kernel.py",
            "tests/control_plane/test_policy_lifecycle.py",
            "tests/control_plane/test_stable_core.py",
            "tests/control_plane/test_supervised_executor.py",
        ),
        "required": (
            "kernel-lifecycle", "atomic-stable-core", "supervised-worker-cleanup",
            "coding-approval-authority-integration",
        ),
        "partial": ("kernel-foundation",),
        "proofs": {
            "kernel-foundation": proof("source", "mainframe.durable-kernel.foundation.v1", ("python3", "-I", "-S", "-B", "tests/control_plane/test_kernel.py")),
            "kernel-lifecycle": proof("source", "mainframe.durable-kernel.lifecycle.v1", ("python3", "-I", "-S", "-B", "tests/control_plane/test_policy_lifecycle.py")),
            "atomic-stable-core": proof("source", "mainframe.durable-kernel.atomic-stable-core.v1", ("python3", "-I", "-S", "-B", "tests/control_plane/test_stable_core.py")),
            "supervised-worker-cleanup": proof(
                "source", "mainframe.durable-kernel.supervised-cleanup.v1",
                ("python3", "-I", "-S", "-B", "tests/control_plane/test_supervised_executor.py"),
                forbidden_output=("expected failure", "expected failures=", "skipped="),
            ),
            "coding-approval-authority-integration": proof(
                "payload", "mainframe.durable-kernel.coding-approval-authority.v1",
                ("mainframe", "control-plane", "coding-approval-authority", "verify"),
                ("host-operator",), external_verifier=True,
            ),
        },
    },
    "reviewed-broker-routing": {
        "evidence_paths": ("config/stable-core.json", "tests/control_plane/public_cli.bats"),
        "required": ("kernel-routed-stable-core",), "partial": (),
        "proofs": {"kernel-routed-stable-core": proof("source", "mainframe.reviewed-broker.kernel-route.v1", ("python3", "-I", "-S", "-B", "tests/control_plane/test_stable_core.py"))},
    },
    "coding-agent-contract": {
        "evidence_paths": (
            "control_plane/mainframe_control_plane/coding.py",
            "control_plane/mainframe_control_plane/cli.py",
            "control_plane/mainframe_control_plane/kernel.py",
            "tests/control_plane/test_coding_agent.py",
            "tests/control_plane/test_coding_public.py",
        ),
        "required": (
            "public-safe-read-search", "approval-required-fail-closed",
        ),
        "partial": (),
        "proofs": {
            "public-safe-read-search": proof(
                "source", "mainframe.coding-agent.public-safe-reads.v1",
                ("python3", "-I", "-S", "-B", "tests/control_plane/test_coding_public.py"),
            ),
            "approval-required-fail-closed": proof(
                "source", "mainframe.coding-agent.approval-required.v1",
                ("python3", "-I", "-S", "-B", "tests/control_plane/test_coding_public.py"),
            ),
        },
    },
    "project-memory-contract": {
        "evidence_paths": (
            "bin/mainframe",
            "lib/durable_awm.sh",
            "control_plane/mainframe_control_plane/memory.py",
            "control_plane/mainframe_control_plane/memory_executor.py",
            "control_plane/mainframe_control_plane/memory_transient.py",
            "control_plane/mainframe_control_plane/cli.py",
            "control_plane/mainframe_control_plane/kernel.py",
            "tests/control_plane/test_project_memory.py",
            "tests/control_plane/test_project_memory_reads.py",
            "tests/control_plane/test_project_memory_integration.py",
            "tests/durable_project_memory_route.bats",
        ),
        "required": (
            "twelve-operation-route", "privacy-recovery-no-fallback",
        ),
        "partial": (),
        "proofs": {
            "twelve-operation-route": proof(
                "source", "mainframe.project-memory.twelve-operation-route.v1",
                ("bats", "tests/durable_project_memory_route.bats"),
                forbidden_output=("# skip", "expected failure"),
            ),
            "privacy-recovery-no-fallback": proof(
                "source", "mainframe.project-memory.privacy-recovery.v1",
                ("bats", "tests/durable_project_memory_route.bats"),
                forbidden_output=("# skip", "expected failure"),
            ),
        },
    },
    "adapter-contract": {
        "evidence_paths": ("config/host-capabilities.json", "scripts/generate-host-adapters.sh", "tests/host_capabilities.bats"),
        "required": ("kernel-routed-adapters", "durable-correlation"),
        "partial": ("instruction-contract",),
        "proofs": {
            "instruction-contract": proof("source", "mainframe.adapter-contract.instructions.v1", ("/bin/bash", "--noprofile", "--norc", "-p", "scripts/generate-host-adapters.sh", "--check")),
            "kernel-routed-adapters": proof("source", "mainframe.adapter-contract.kernel-route.v1", ("bats", "tests/adapter_kernel_route.bats")),
            "durable-correlation": proof("source", "mainframe.adapter-contract.correlation.v1", ("bats", "tests/adapter_kernel_route.bats")),
        },
    },
    "host-conformance": {
        "evidence_paths": ("config/host-capabilities.json", "tests/native_host_certification.bats", "tests/pi_cell_evidence.bats"),
        "required": ("installed-host-conformance",), "partial": (),
        "proofs": {"installed-host-conformance": proof("source", "mainframe.host-conformance.installed.v1", ("mainframe", "host", "conformance", "verify"), ("host-operator",), external_verifier=True)},
    },
    "immutable-distribution": {
        "evidence_paths": ("scripts/build-release-archive.sh", "scripts/dev/release-candidate.sh", "tests/release-archive.bats"),
        "required": ("published-release-attestation", "channel-recovery"), "partial": (),
        "proofs": {
            "published-release-attestation": proof("payload", "mainframe.immutable-distribution.release.v1", ("mainframe", "release", "verify"), ("release-authority",), external_verifier=True),
            "channel-recovery": proof("payload", "mainframe.immutable-distribution.recovery.v1", ("mainframe", "release", "recovery", "verify"), ("release-authority",), external_verifier=True),
        },
    },
    "independent-outcomes": {
        "evidence_paths": ("docs/AGENT_IMPACT_EVALUATION.md", "docs/CLAIMS_AND_BENCHMARKS.md"),
        "required": ("independent-outcome-study",), "partial": (),
        "proofs": {"independent-outcome-study": proof("payload", "mainframe.independent-outcomes.study.v1", ("mainframe", "claim", "independent-study", "verify"), ("independent-evaluator",), external_verifier=True)},
    },
}


class ContractError(ValueError):
    """The claim contract is malformed or overclaims its evidence."""


class VerifierUnavailable(RuntimeError):
    """A reviewed local verifier is not safely executable on this host."""


class CheckResult(TypedDict):
    ok: bool
    schema_version: int
    contract_version: str
    target_claim: str
    advertised_claim: str
    highest_eligible_claim: str
    blocking_gates: list[str]
    gate_states: dict[str, str]


def fail(message: str) -> NoReturn:
    raise ContractError(message)


def require_closed_object(value: object, keys: set[str], label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    unknown = sorted(set(value) - keys)
    missing = sorted(keys - set(value))
    if unknown:
        fail(f"unknown {label} keys: {unknown}")
    if missing:
        fail(f"missing {label} keys: {missing}")
    return value


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        fail(f"{label} must be a non-empty trimmed string")
    return value


def require_nullable_string(value: object, label: str) -> str | None:
    if value is None:
        return None
    return require_string(value, label)


def require_string_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        fail(f"{label} must be an array")
    result = [require_string(item, f"{label} item") for item in value]
    if len(result) != len(set(result)):
        fail(f"{label} must not contain duplicates")
    return result


def validate_relative_regular_file(root: Path, relative: str, label: str) -> Path:
    if "\x00" in relative or relative.startswith("/"):
        fail(f"{label} must be relative: {relative}")
    parts = Path(relative).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        fail(f"{label} is unsafe: {relative}")
    candidate = root.joinpath(*parts)
    current = root
    try:
        for part in parts:
            current = current / part
            metadata = os.lstat(current)
            if stat.S_ISLNK(metadata.st_mode):
                fail(f"{label} is missing or not a regular non-symlink file: {relative}")
        if not stat.S_ISREG(os.lstat(candidate).st_mode):
            fail(f"{label} is missing or not a regular non-symlink file: {relative}")
    except OSError:
        fail(f"{label} is missing or not a regular non-symlink file: {relative}")
    try:
        candidate.resolve(strict=True).relative_to(root)
    except (OSError, ValueError):
        fail(f"{label} escapes the project root: {relative}")
    return candidate


def validate_evidence_path(root: Path, relative: str, gate_id: str) -> Path:
    return validate_relative_regular_file(root, relative, f"gate {gate_id} evidence path")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        fail(f"cannot hash {path}: {exc}")
    return digest.hexdigest()


def attestation_exclusions(root: Path) -> tuple[str, ...]:
    path = validate_relative_regular_file(
        root,
        ATTESTATION_EXCLUSIONS_PATH,
        "release attestation exclusion registry",
    )
    try:
        entries = tuple(
            line
            for raw_line in path.read_text(encoding="utf-8").splitlines()
            if (line := raw_line.strip()) and not line.startswith("#")
        )
    except (OSError, UnicodeError) as exc:
        fail(f"release attestation exclusion registry is unreadable: {exc}")
    if entries != EXPECTED_ATTESTATION_EXCLUSIONS:
        fail("release attestation exclusion registry has unexpected entries")
    return entries


def is_attestation_metadata(relative: str, exclusions: tuple[str, ...]) -> bool:
    return any(
        relative.startswith(excluded) if excluded.endswith("/")
        else relative == excluded
        for excluded in exclusions
    )


def validate_release_inventory(root: Path) -> str:
    exclusions = attestation_exclusions(root)
    inventory = validate_relative_regular_file(root, "SHA256SUMS", "canonical SHA256SUMS")
    try:
        lines = inventory.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        fail(f"canonical SHA256SUMS is unreadable: {exc}")
    seen: set[str] = set()
    entries = 0
    for line_number, line in enumerate(lines, 1):
        if not line or line.startswith("#"):
            continue
        if len(line) < 67 or line[64:66] != "  " or SHA256_PATTERN.fullmatch(line[:64]) is None:
            fail(f"canonical SHA256SUMS line {line_number} is malformed")
        claimed, relative = line[:64], line[66:]
        if not relative or relative in seen:
            fail(f"canonical SHA256SUMS line {line_number} has a missing or duplicate path")
        if is_attestation_metadata(relative, exclusions):
            fail(
                "canonical SHA256SUMS includes detached attestation metadata: "
                f"{relative}"
            )
        seen.add(relative)
        candidate = validate_relative_regular_file(root, relative, "SHA256SUMS payload entry")
        if sha256_file(candidate) != claimed:
            fail(f"canonical SHA256SUMS payload drift: {relative}")
        entries += 1
    if entries == 0:
        fail("canonical SHA256SUMS must contain payload entries")
    return sha256_file(inventory)


def source_tree_sha256(root: Path) -> str:
    exclusions = attestation_exclusions(root)
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        fail(f"cannot enumerate the source tree: {exc}")
    if result.returncode != 0:
        fail("cannot enumerate the exact git source tree")
    digest = hashlib.sha256()
    for encoded in sorted(item for item in result.stdout.split(b"\0") if item):
        relative = os.fsdecode(encoded)
        if is_attestation_metadata(relative, exclusions):
            continue
        if "\x00" in relative or relative.startswith("/") or any(
            part in {"", ".", ".."} for part in Path(relative).parts
        ):
            fail(f"git returned an unsafe source path: {relative}")
        path = root.joinpath(*Path(relative).parts)
        try:
            metadata = os.lstat(path)
        except FileNotFoundError:
            digest.update(encoded + b"\0missing\0")
            continue
        except OSError as exc:
            fail(f"cannot inspect source path {relative}: {exc}")
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            fail(f"source tree path must be a regular non-symlink file: {relative}")
        # Git records only the executable class for regular files. Normalize
        # owner/group/world read bits so a clean 0600/0700 maintainer checkout
        # and Git's reconstructed 0644/0755 checkout bind the same source.
        canonical_mode = 0o755 if metadata.st_mode & 0o111 else 0o644
        digest.update(
            encoded + b"\0" + f"{canonical_mode:04o}".encode("ascii") + b"\0"
        )
        digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def resolve_safe_executable(candidates: tuple[str, ...], label: str) -> str:
    """Resolve one fixed, owner-trusted, non-writable executable."""
    for candidate_value in candidates:
        candidate = Path(candidate_value)
        try:
            resolved = candidate.resolve(strict=True)
            metadata = os.lstat(resolved)
        except OSError:
            continue
        if (
            not resolved.is_absolute()
            or not stat.S_ISREG(metadata.st_mode)
            or stat.S_ISLNK(metadata.st_mode)
            or metadata.st_uid not in (0, os.geteuid())
            or stat.S_IMODE(metadata.st_mode) & 0o7022
            or not os.access(resolved, os.X_OK)
        ):
            continue
        return str(resolved)
    raise VerifierUnavailable(
        f"local verifier requires a fixed safe {label} executable"
    )


def resolve_fixed_bash() -> str:
    """Resolve a fixed safe Bash that satisfies the runtime's 4.4 floor."""
    for candidate in FIXED_BASH_CANDIDATES:
        try:
            executable = resolve_safe_executable((candidate,), "Bash")
        except VerifierUnavailable:
            continue
        try:
            probe = subprocess.run(
                [
                    executable,
                    "--noprofile",
                    "--norc",
                    "-p",
                    "-c",
                    'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=5,
                env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
            )
            major, minor = (int(value) for value in probe.stdout.split())
        except (OSError, subprocess.SubprocessError, TypeError, ValueError):
            continue
        if probe.returncode == 0 and (major, minor) >= MINIMUM_BASH_VERSION:
            return executable
    raise VerifierUnavailable(
        "local verifier requires fixed safe Bash 4.4 or newer"
    )


def execute_local_verifier(
    root: Path,
    argv: tuple[str, ...],
    forbidden_output: tuple[str, ...],
    cache: dict[tuple[tuple[str, ...], tuple[str, ...]], bool | None],
) -> bool | None:
    cache_key = (argv, forbidden_output)
    if cache_key in cache:
        return cache[cache_key]
    executable = argv[0]
    candidates = LOCAL_VERIFIER_CANDIDATES.get(executable)
    try:
        if candidates is not None:
            executable = resolve_safe_executable(candidates, executable)
        elif not executable.startswith("/"):
            fail(f"local verifier executable is not fixed: {executable}")
    except VerifierUnavailable:
        cache[cache_key] = None
        return None
    command = (executable,) + argv[1:]
    environment = os.environ.copy()
    for key in tuple(environment):
        if key in {"BASH_ENV", "ENV", "CDPATH", "PYTHONHOME", "PYTHONPATH"} or key.startswith("BASH_FUNC_"):
            environment.pop(key, None)
    environment["LC_ALL"] = "C"
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["PATH"] = FIXED_VERIFIER_PATH
    if argv[0] == "bats":
        try:
            fixed_bash = resolve_fixed_bash()
        except VerifierUnavailable:
            cache[cache_key] = None
            return None
        command = (fixed_bash, executable) + argv[1:]
        environment["BATS_TEST_SHELL"] = fixed_bash
    try:
        result = subprocess.run(
            command,
            cwd=root,
            env=environment,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        fail(f"local verifier timed out: {' '.join(argv)}")
    except OSError as exc:
        fail(f"local verifier could not execute {' '.join(argv)}: {exc}")
    if len(result.stdout) > MAX_VERIFIER_OUTPUT:
        fail(f"local verifier exceeded output limit: {' '.join(argv)}")
    rendered_output = result.stdout.decode("utf-8", errors="replace").lower()
    passed = result.returncode == 0 and not any(
        marker.lower() in rendered_output for marker in forbidden_output
    )
    cache[cache_key] = passed
    return passed


def load_json_file(path: Path, label: str) -> dict[str, object]:
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"{label} is missing: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        fail(f"{label} must be a regular non-symlink file")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{label} is unreadable or invalid JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def load_contract(path: Path) -> dict[str, object]:
    return require_closed_object(load_json_file(path, "contract"), TOP_LEVEL_KEYS, "top-level")


def current_revision(root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
            check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        fail(f"cannot resolve source revision: {exc}")
    revision = result.stdout.strip()
    if result.returncode != 0 or REVISION_PATTERN.fullmatch(revision) is None:
        fail("cannot resolve exact git HEAD source revision")
    return revision


def source_revision_is_current_or_detached_parent(
    root: Path, source_revision: str, revision: str
) -> bool:
    """Accept HEAD or its sole parent when HEAD is only detached attestations.

    Receipt files cannot contain the hash of the commit that contains those same
    bytes.  A release therefore uses a subject commit followed by one detached
    attestation commit.  The exception is deliberately one generation deep and
    permits only the claim contract and its receipt directory; release payload,
    inventory, source, and test changes remain part of the bound subject commit.
    """
    if source_revision == revision:
        return True
    try:
        parents = subprocess.run(
            ["git", "-C", str(root), "rev-list", "--parents", "-n", "1", "HEAD"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    fields = parents.stdout.decode("ascii", errors="strict").strip().split()
    if parents.returncode != 0 or len(fields) != 2 or fields[0] != revision:
        return False
    parent_revision = fields[1]
    if source_revision != parent_revision:
        return False
    try:
        changed = subprocess.run(
            [
                "git", "-C", str(root), "diff-tree", "--no-commit-id",
                "--name-only", "--no-renames", "-r", "-z",
                parent_revision, revision,
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    if changed.returncode != 0:
        return False
    paths = tuple(
        os.fsdecode(item) for item in changed.stdout.split(b"\0") if item
    )
    return bool(paths) and all(
        any(
            relative.startswith(allowed) if allowed.endswith("/")
            else relative == allowed
            for allowed in DETACHED_ATTESTATION_COMMIT_PATHS
        )
        for relative in paths
    )


def project_version(root: Path) -> str:
    path = validate_relative_regular_file(root, "VERSION", "VERSION")
    try:
        value = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        fail(f"VERSION is unreadable: {exc}")
    if VERSION_PATTERN.fullmatch(value) is None:
        fail("VERSION must contain stable SemVer")
    return value


def parse_timestamp(value: object, label: str) -> datetime:
    raw = require_string(value, label)
    if not raw.endswith("Z"):
        fail(f"{label} must use UTC Z notation")
    try:
        parsed = datetime.fromisoformat(raw[:-1] + "+00:00")
    except ValueError:
        fail(f"{label} must be an RFC 3339 date-time")
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        fail(f"{label} must be UTC")
    return parsed


def validate_receipt(
    document: dict[str, object], *, root: Path, gate_id: str,
    policy: dict[str, object], revision: str, version: str,
    inventory_digest: str, source_tree_digest: str,
    verifier_cache: dict[
        tuple[tuple[str, ...], tuple[str, ...]], bool | None
    ],
) -> tuple[str, str, bool]:
    receipt = require_closed_object(document, RECEIPT_KEYS, "receipt")
    if receipt["schema_version"] != 1:
        fail("receipt schema_version must be 1")
    if receipt["receipt_type"] != RECEIPT_TYPE:
        fail(f"receipt_type must be {RECEIPT_TYPE}")
    receipt_id = require_string(receipt["receipt_id"], "receipt_id")
    if ID_PATTERN.fullmatch(receipt_id) is None:
        fail("receipt_id has an invalid format")
    if require_string(receipt["gate_id"], "receipt gate_id") != gate_id:
        fail(f"receipt gate_id does not match {gate_id}")
    proof_kind = require_string(receipt["proof_kind"], f"gate {gate_id} proof_kind")
    if TOKEN_PATTERN.fullmatch(proof_kind) is None:
        fail(f"gate {gate_id} proof_kind has an invalid format")
    proofs = policy["proofs"]
    if proof_kind not in proofs:
        fail(f"gate {gate_id} proof_kind is not reviewed: {proof_kind}")
    proof_policy = proofs[proof_kind]
    if receipt["protocol_version"] != RECEIPT_PROTOCOL_VERSION:
        fail(f"gate {gate_id} receipt protocol_version must be {RECEIPT_PROTOCOL_VERSION}")

    subject = require_closed_object(receipt["subject"], SUBJECT_KEYS, "receipt subject")
    subject_kind = require_string(subject["kind"], "receipt subject kind")
    if subject_kind != proof_policy["subject_kind"]:
        fail(f"gate {gate_id} receipt subject kind must be {proof_policy['subject_kind']}")
    source_revision = require_nullable_string(subject["source_revision"], "source_revision")
    claimed_source_tree = require_nullable_string(subject["source_tree_sha256"], "source_tree_sha256")
    claimed_inventory = require_nullable_string(subject["inventory_sha256"], "inventory_sha256")
    payload_sha256 = require_nullable_string(subject["payload_sha256"], "payload_sha256")
    if claimed_inventory is not None and SHA256_PATTERN.fullmatch(claimed_inventory) is None:
        fail(f"gate {gate_id} inventory_sha256 must be lowercase SHA-256")
    if require_string(subject["version"], "receipt subject version") != version:
        fail(f"gate {gate_id} receipt version does not match VERSION")
    if subject_kind == "source":
        if source_revision is None or REVISION_PATTERN.fullmatch(source_revision) is None:
            fail(f"gate {gate_id} source receipt requires an exact 40-hex revision")
        if not source_revision_is_current_or_detached_parent(
            root, source_revision, revision
        ):
            fail(
                f"gate {gate_id} source revision does not match HEAD or its "
                "sole detached-attestation parent"
            )
        if claimed_source_tree is None or SHA256_PATTERN.fullmatch(claimed_source_tree) is None:
            fail(f"gate {gate_id} source receipt requires source_tree_sha256")
        if claimed_inventory is not None:
            fail(f"gate {gate_id} source receipt cannot set inventory_sha256")
        if payload_sha256 is not None:
            fail(f"gate {gate_id} source receipt cannot set payload_sha256")
    else:
        if source_revision is not None:
            fail(f"gate {gate_id} payload receipt cannot set source_revision")
        if claimed_source_tree is not None:
            fail(f"gate {gate_id} payload receipt cannot set source_tree_sha256")
        if payload_sha256 is None or SHA256_PATTERN.fullmatch(payload_sha256) is None:
            fail(f"gate {gate_id} payload receipt requires a SHA-256 digest")
        if claimed_inventory is None:
            fail(f"gate {gate_id} payload receipt requires inventory_sha256")

    command = require_closed_object(receipt["command"], COMMAND_KEYS, "receipt command")
    identity = require_string(command["identity"], "receipt command identity")
    if COMMAND_PATTERN.fullmatch(identity) is None:
        fail("receipt command identity has an invalid format")
    argv = require_string_list(command["argv"], "receipt command argv")
    if identity != proof_policy["command_identity"]:
        fail(f"gate {gate_id} command identity does not match reviewed policy")
    if tuple(argv) != proof_policy["argv"]:
        fail(f"gate {gate_id} command argv does not match reviewed policy")

    environment = require_closed_object(receipt["environment"], ENVIRONMENT_KEYS, "receipt environment")
    if environment["os"] not in {"darwin", "linux"}:
        fail("receipt environment os is unknown")
    if environment["architecture"] not in {"arm64", "x86_64"}:
        fail("receipt environment architecture is unknown")
    if environment["runner_class"] not in {"maintainer-local", "repository-ci", "installed-host", "release-verifier", "independent-lab"}:
        fail("receipt environment runner_class is unknown")
    # Environment is issuance provenance, not current execution authority.
    # Every source proof is content-bound and rerun below, so a receipt issued
    # on Darwin can be independently checked on Linux (and vice versa) without
    # trusting its authored result.

    issued_at = parse_timestamp(receipt["issued_at"], "receipt issued_at")
    expires_at = parse_timestamp(receipt["expires_at"], "receipt expires_at")
    now = datetime.now(timezone.utc)
    if expires_at <= issued_at:
        fail(f"gate {gate_id} receipt expiry must be after issuance")
    if expires_at - issued_at > MAX_LOCAL_RECEIPT_TTL:
        fail(f"gate {gate_id} receipt TTL exceeds seven days")
    if issued_at > now:
        fail(f"gate {gate_id} receipt issuance is in the future")
    if expires_at <= now:
        fail(f"gate {gate_id} receipt is expired")

    evidence_value = receipt["evidence"]
    if not isinstance(evidence_value, list) or not evidence_value:
        fail(f"gate {gate_id} receipt evidence must be a non-empty array")
    evidence_paths: list[str] = []
    for index, raw_item in enumerate(evidence_value):
        item = require_closed_object(raw_item, EVIDENCE_KEYS, f"receipt evidence {index}")
        relative = require_string(item["path"], f"receipt evidence {index} path")
        claimed_digest = require_string(item["sha256"], f"receipt evidence {index} sha256")
        if SHA256_PATTERN.fullmatch(claimed_digest) is None:
            fail(f"receipt evidence {index} sha256 must be lowercase SHA-256")
        if TOKEN_PATTERN.fullmatch(require_string(item["role"], f"receipt evidence {index} role")) is None:
            fail(f"receipt evidence {index} role has an invalid format")
        if relative in evidence_paths:
            fail(f"gate {gate_id} receipt evidence paths must be unique")
        evidence_paths.append(relative)
        if sha256_file(validate_evidence_path(root, relative, gate_id)) != claimed_digest:
            fail(f"gate {gate_id} evidence digest mismatch: {relative}")
    if tuple(evidence_paths) != policy["evidence_paths"]:
        fail(f"gate {gate_id} evidence paths do not match the reviewed policy")
    if subject_kind == "payload" and claimed_inventory != inventory_digest:
        fail(f"gate {gate_id} inventory digest does not match canonical SHA256SUMS")
    if subject_kind == "source" and claimed_source_tree != source_tree_digest:
        fail(f"gate {gate_id} source tree digest does not match the current working tree")

    result = require_string(receipt["result"], "receipt result")
    if result not in {"pass", "fail"}:
        fail("receipt result must be pass or fail")
    authority = require_closed_object(receipt["authority"], AUTHORITY_KEYS, "receipt authority")
    authority_class = require_string(authority["class"], "receipt authority class")
    if authority_class == "self-asserted":
        fail(f"gate {gate_id} self-asserted authority is not admissible")
    if authority_class not in proof_policy["authorities"]:
        fail(f"gate {gate_id} authority class {authority_class} is not permitted")
    require_string(authority["signer_id"], "receipt authority signer_id")
    independence = require_string(authority["independence"], "receipt authority independence")
    signature = require_nullable_string(authority["signature"], "receipt authority signature")
    if proof_policy["external_verifier"]:
        if independence != "external" or signature is None:
            fail(f"gate {gate_id} requires externally signed authority")
        fail(
            f"gate {gate_id} external attestation verifier is not configured; "
            "authored authority fields cannot promote this gate"
        )
    if independence != "project":
        fail(f"gate {gate_id} source proof must use project authority")
    if authority_class != "local-verifier":
        fail(f"gate {gate_id} local source proof requires recomputed verifier authority")
    if authority["signer_id"] != "scripts/check-control-plane-claim.py" or signature is not None:
        fail(f"gate {gate_id} local verifier identity is invalid")
    if environment["runner_class"] != "maintainer-local":
        fail(f"gate {gate_id} local verifier runner_class must be maintainer-local")
    require_string_list(receipt["limitations"], "receipt limitations")
    actual_pass = execute_local_verifier(
        root, tuple(argv), proof_policy["forbidden_output"], verifier_cache
    )
    if actual_pass is None:
        return receipt_id, proof_kind, True
    if (result == "pass") != actual_pass:
        fail(f"gate {gate_id} receipt result does not match fixed verifier execution")
    return receipt_id, proof_kind if actual_pass else "", False


def validate_contract(document: dict[str, object], root: Path) -> CheckResult:
    if document["schema_version"] != 2:
        fail("schema_version must be 2")
    version = require_string(document["contract_version"], "contract_version")
    if version != "2.1.0":
        fail("contract_version must be 2.1.0")
    if document["receipt_schema"] != RECEIPT_SCHEMA_PATH:
        fail(f"receipt_schema must be {RECEIPT_SCHEMA_PATH}")
    validate_relative_regular_file(root, RECEIPT_SCHEMA_PATH, "receipt schema")
    target_claim = require_string(document["target_claim"], "target_claim")
    advertised_claim = require_string(document["advertised_claim"], "advertised_claim")
    if target_claim != "category-claim":
        fail("target_claim must be category-claim")
    if advertised_claim not in PROMOTION_ORDER:
        fail(f"advertised_claim is unknown: {advertised_claim}")

    gates_value = document["gates"]
    if not isinstance(gates_value, dict):
        fail("gates must be an object")
    if tuple(gates_value) != tuple(GATE_POLICIES):
        fail(f"gates must use the exact reviewed order: {list(GATE_POLICIES)}")
    revision = current_revision(root)
    release_version = project_version(root)
    inventory_digest = validate_release_inventory(root)
    source_tree_digest = source_tree_sha256(root)
    verifier_cache: dict[
        tuple[tuple[str, ...], tuple[str, ...]], bool | None
    ] = {}
    gate_states: dict[str, str] = {}
    seen_receipt_paths: set[str] = set()
    seen_receipt_ids: set[str] = set()
    for gate_id, policy in GATE_POLICIES.items():
        gate = require_closed_object(gates_value[gate_id], GATE_KEYS, f"gate {gate_id}")
        require_string(gate["summary"], f"gate {gate_id} summary")
        evidence_paths = require_string_list(gate["evidence_paths"], f"gate {gate_id} evidence_paths")
        if tuple(evidence_paths) != policy["evidence_paths"]:
            fail(f"gate {gate_id} evidence_paths do not match the reviewed policy")
        for relative in evidence_paths:
            validate_evidence_path(root, relative, gate_id)
        remaining = require_string_list(gate["remaining"], f"gate {gate_id} remaining")
        refs_value = gate["receipt_refs"]
        if not isinstance(refs_value, list):
            fail(f"gate {gate_id} receipt_refs must be an array")
        passing_proofs: set[str] = set()
        unavailable_proofs: set[str] = set()
        for index, raw_ref in enumerate(refs_value):
            ref = require_closed_object(raw_ref, RECEIPT_REF_KEYS, f"gate {gate_id} receipt_ref {index}")
            relative = require_string(ref["path"], f"gate {gate_id} receipt_ref path")
            claimed_digest = require_string(ref["sha256"], f"gate {gate_id} receipt_ref sha256")
            if SHA256_PATTERN.fullmatch(claimed_digest) is None:
                fail(f"gate {gate_id} receipt_ref sha256 must be lowercase SHA-256")
            if relative in seen_receipt_paths:
                fail(f"receipt path is reused across gates: {relative}")
            seen_receipt_paths.add(relative)
            path = validate_relative_regular_file(root, relative, f"gate {gate_id} receipt")
            if sha256_file(path) != claimed_digest:
                fail(f"gate {gate_id} receipt digest mismatch: {relative}")
            receipt_id, observed_proof, verifier_unavailable = validate_receipt(
                load_json_file(path, f"gate {gate_id} receipt"), root=root,
                gate_id=gate_id, policy=policy, revision=revision, version=release_version,
                inventory_digest=inventory_digest, source_tree_digest=source_tree_digest,
                verifier_cache=verifier_cache,
            )
            if receipt_id in seen_receipt_ids:
                fail(f"receipt_id is reused: {receipt_id}")
            seen_receipt_ids.add(receipt_id)
            if verifier_unavailable:
                unavailable_proofs.add(observed_proof)
            elif observed_proof:
                if observed_proof in passing_proofs:
                    fail(f"gate {gate_id} repeats proof_kind {observed_proof}")
                passing_proofs.add(observed_proof)
        required = set(policy["required"])
        allowed = required | set(policy["partial"])
        if not passing_proofs.issubset(allowed):
            fail(f"gate {gate_id} contains an inadmissible passing proof")
        if required.issubset(passing_proofs):
            state = "green"
        elif passing_proofs:
            state = "amber"
        else:
            state = "red"
        if state == "green" and remaining:
            fail(f"derived-green gate {gate_id} cannot retain remaining proof")
        if state != "green" and not remaining and not unavailable_proofs:
            fail(f"derived non-green gate {gate_id} must name remaining proof")
        gate_states[gate_id] = state

    promotions = document["promotions"]
    if not isinstance(promotions, dict):
        fail("promotions must be an object")
    if tuple(promotions) != PROMOTION_ORDER:
        fail(f"promotions must use the exact ordered ladder: {list(PROMOTION_ORDER)}")
    previous: list[str] = []
    for claim in PROMOTION_ORDER:
        required = require_string_list(promotions[claim], f"promotion {claim}")
        unknown = sorted(set(required) - set(gate_states))
        if unknown:
            fail(f"promotion {claim} references unknown gates: {unknown}")
        if required[:len(previous)] != previous:
            fail(f"promotion {claim} must extend the prior promotion without reordering")
        if len(required) <= len(previous) and claim != PROMOTION_ORDER[0]:
            fail(f"promotion {claim} must add at least one gate")
        previous = required
    if set(previous) != set(gate_states):
        fail("category-claim promotion must include every gate exactly once")

    highest: str | None = None
    for claim in PROMOTION_ORDER:
        required = promotions[claim]
        if all(gate_states[gate_id] == "green" for gate_id in required):
            highest = claim
        else:
            break
    if highest is None:
        fail("source-candidate gates are not all green")
    if advertised_claim != highest:
        if PROMOTION_ORDER.index(advertised_claim) > PROMOTION_ORDER.index(highest):
            fail(f"advertised claim {advertised_claim} exceeds highest eligible {highest}")
        fail(f"advertised claim {advertised_claim} is stale; highest eligible is {highest}")
    target_gates = promotions[target_claim]
    blocking = [gate_id for gate_id in target_gates if gate_states[gate_id] != "green"]
    return {
        "ok": True, "schema_version": 2, "contract_version": version,
        "target_claim": target_claim, "advertised_claim": advertised_claim,
        "highest_eligible_claim": highest, "blocking_gates": blocking,
        "gate_states": gate_states,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--contract")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def resolve_root(raw: str) -> Path:
    path = Path(raw)
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"project root is missing: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail("project root must be a real non-symlink directory")
    return path.resolve(strict=True)


def main() -> int:
    args = parse_args()
    try:
        root = resolve_root(args.root)
        contract = Path(args.contract) if args.contract else root / "config/control-plane-claim.json"
        result = validate_contract(load_contract(contract), root)
    except (ContractError, OSError) as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True))
        else:
            print(f"control-plane claim check failed: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(
            "Control-plane claim contract valid: "
            f"advertised={result['advertised_claim']} target={result['target_claim']} "
            f"blocking={len(result['blocking_gates'])}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

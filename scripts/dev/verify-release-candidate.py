#!/usr/bin/env python3
"""Verify one coherent local release-candidate artifact set.

This verifier is deliberately local and non-publishing.  The candidate manifest
is written only after the archive, checksum, SBOM, and Homebrew formula agree on
the same version and archive digest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
from typing import Any, NoReturn
import uuid


SCHEMA = "https://github.com/gtwatts/mainframe/schemas/release-candidate/v2"
REPOSITORY = "gtwatts/mainframe"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FORMULA_URL_RE = re.compile(r'^\s*url\s+"([^"]+)"\s*$')
FORMULA_SHA_RE = re.compile(r'^\s*sha256\s+"([^"]+)"\s*$')
PLACEHOLDER_RE = re.compile(r"@[A-Z][A-Z0-9_]*@")
SOURCE_FORMAT = "mainframe-release-source-provenance-v1"
SOURCE_SCOPE = "canonical-release-payload-v1"
SOURCE_PATH_DISCLOSURE = "digest-only"
SOURCE_SNAPSHOT_KIND = "mainframe-release-source-snapshot"
CHANGE_PATH_SET_DOMAIN = b"MAINFRAME-RELEASE-PAYLOAD-CHANGE-PATH-SET-SHA256-V1\0"
SOURCE_STATE_DOMAIN = b"MAINFRAME-RELEASE-SOURCE-STATE-SHA256-V1\0"
MAX_SOURCE_SCOPE_BYTES = 16 * 1024 * 1024
MAX_GIT_OUTPUT_BYTES = 64 * 1024 * 1024
SOURCE_KEYS = (
    "format",
    "availability",
    "base_commit",
    "object_format",
    "scope",
    "release_root_state",
    "clean_checkout_reproducible",
    "tracked_change_path_count",
    "untracked_payload_file_count",
    "change_path_set_sha256",
    "path_disclosure",
)
ATTESTATION_EXCLUSIONS_PATH = "config/release-attestation-exclusions.txt"
EXPECTED_ATTESTATION_EXCLUSIONS = (
    "SHA256SUMS",
    "config/control-plane-claim.json",
    "config/control-plane-claim-receipts/",
)


class GitUnavailable(RuntimeError):
    """The fixed local Git observation could not be made."""


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid release candidate: {message}")


def regular_file(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        fail(f"{label} is unavailable: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        fail(f"{label} must be a regular, non-symlink file: {path}")
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as error:
        fail(f"cannot hash {path}: {error}")
    return digest.hexdigest()


def canonical_bytes(value: object) -> bytes:
    try:
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        ).encode("ascii")
    except (TypeError, ValueError) as error:
        fail(f"source snapshot is not canonical JSON: {error}")


def exact_object(value: object, keys: tuple[str, ...], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    if set(value) != set(keys):
        fail(f"{label} must contain exactly: {', '.join(keys)}")
    return value


def source_unavailable() -> dict[str, object]:
    return {
        "format": SOURCE_FORMAT,
        "availability": False,
        "base_commit": None,
        "object_format": None,
        "scope": SOURCE_SCOPE,
        "release_root_state": "unavailable",
        "clean_checkout_reproducible": False,
        "tracked_change_path_count": None,
        "untracked_payload_file_count": None,
        "change_path_set_sha256": None,
        "path_disclosure": SOURCE_PATH_DISCLOSURE,
    }


def validate_source(value: object) -> dict[str, Any]:
    source = exact_object(value, SOURCE_KEYS, "source provenance")
    if source["format"] != SOURCE_FORMAT:
        fail("source provenance format is unsupported")
    if type(source["availability"]) is not bool:
        fail("source provenance availability must be boolean")
    if source["scope"] != SOURCE_SCOPE:
        fail("source provenance scope is unsupported")
    if source["path_disclosure"] != SOURCE_PATH_DISCLOSURE:
        fail("source provenance path disclosure must be digest-only")

    if source["availability"] is False:
        if source != source_unavailable():
            fail("unavailable source provenance must use the closed null projection")
        return source

    object_format = source["object_format"]
    if object_format not in ("sha1", "sha256"):
        fail("available source provenance has an unsupported Git object format")
    oid_length = 40 if object_format == "sha1" else 64
    base_commit = source["base_commit"]
    if not isinstance(base_commit, str) or re.fullmatch(
        rf"[0-9a-f]{{{oid_length}}}", base_commit
    ) is None:
        fail("available source provenance has a malformed base commit")
    for key in ("tracked_change_path_count", "untracked_payload_file_count"):
        count = source[key]
        if type(count) is not int or count < 0:
            fail(f"available source provenance has an invalid {key}")
    digest = source["change_path_set_sha256"]
    if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
        fail("available source provenance has a malformed change-path digest")
    clean = (
        source["tracked_change_path_count"] == 0
        and source["untracked_payload_file_count"] == 0
    )
    if source["release_root_state"] != ("clean" if clean else "dirty"):
        fail("source provenance release-root state disagrees with its counts")
    if source["clean_checkout_reproducible"] is not clean:
        fail("source provenance reproducibility disagrees with its state")
    return source


def read_limited(path: Path, label: str, maximum: int) -> bytes:
    regular_file(path, label)
    try:
        metadata = path.stat()
        if metadata.st_size > maximum:
            fail(f"{label} exceeds its size ceiling")
        return path.read_bytes()
    except OSError as error:
        fail(f"{label} cannot be read: {error}")


def safe_relative_path(raw: bytes, label: str) -> tuple[str, bytes]:
    try:
        name = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        fail(f"{label} is not UTF-8: {error}")
    posix_name = PurePosixPath(name)
    if (
        not name
        or posix_name.is_absolute()
        or str(posix_name) != name
        or any(part in ("", ".", "..") for part in posix_name.parts)
    ):
        fail(f"{label} is not a canonical relative payload path")
    return name, raw


def read_source_inventory(root: Path, path: Path) -> tuple[list[str], str]:
    payload = read_limited(path, "source payload inventory", MAX_SOURCE_SCOPE_BYTES)
    if not payload or not payload.endswith(b"\n") or b"\0" in payload:
        fail("source payload inventory must be a non-empty newline-terminated list")
    raw_names = payload[:-1].split(b"\n")
    names = [safe_relative_path(raw, "source payload inventory path")[0] for raw in raw_names]
    if names != sorted(names, key=lambda item: item.encode("utf-8")):
        fail("source payload inventory must be byte-sorted")
    if len(names) != len(set(names)):
        fail("source payload inventory contains duplicate paths")

    digest = hashlib.sha256()
    digest.update(b"MAINFRAME-RELEASE-PAYLOAD-SOURCE-STATE-V1\0")
    root_text = str(root)
    for name in names:
        source = root.joinpath(*PurePosixPath(name).parts)
        try:
            metadata = source.lstat()
        except OSError as error:
            fail(f"source payload file is unavailable: {error}")
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            fail("source payload inventory contains a non-regular file")
        try:
            resolved = source.resolve(strict=True)
        except OSError as error:
            fail(f"source payload file cannot be resolved: {error}")
        if os.path.commonpath((root_text, str(resolved))) != root_text:
            fail("source payload file escapes the release root")
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(f"{stat.S_IMODE(metadata.st_mode):04o}".encode("ascii"))
        digest.update(b"\0")
        digest.update(str(metadata.st_size).encode("ascii"))
        digest.update(b"\0")
        digest.update(sha256(resolved).encode("ascii"))
        digest.update(b"\0")
    return names, digest.hexdigest()


def read_git_pathspecs(path: Path) -> tuple[list[str], str]:
    payload = read_limited(path, "source Git pathspecs", MAX_SOURCE_SCOPE_BYTES)
    if not payload or not payload.endswith(b"\0"):
        fail("source Git pathspecs must be a non-empty NUL-terminated list")
    raw_items = payload[:-1].split(b"\0")
    if any(not item for item in raw_items):
        fail("source Git pathspecs contain an empty item")
    try:
        items = [item.decode("utf-8", errors="strict") for item in raw_items]
    except UnicodeDecodeError as error:
        fail(f"source Git pathspecs are not UTF-8: {error}")
    if len(items) != len(set(items)):
        fail("source Git pathspecs contain duplicates")
    for item in items:
        match = re.fullmatch(
            r":\(top,(?:literal|exclude,literal|glob,exclude)\)(.+)", item
        )
        if match is None or match.group(1).startswith("/") or "\n" in item or "\r" in item:
            fail("source Git pathspecs contain an unsupported item")
    return items, hashlib.sha256(payload).hexdigest()


def fixed_system_git() -> Path | None:
    candidate = Path("/usr/bin/git")
    try:
        metadata = candidate.lstat()
    except OSError:
        return None
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_mode & 0o111 == 0
    ):
        return None
    return candidate


def git_environment() -> dict[str, str]:
    # Build a new environment instead of attempting a blacklist. In particular,
    # no caller-supplied GIT_* variable, credential helper, prompt, or PATH is
    # inherited by the fixed local-only commands below.
    return {
        "GIT_ATTR_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
        "HOME": "/",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
    }


def run_local_git(git: Path, root: Path, arguments: list[str]) -> bytes:
    command = [
        str(git),
        "--no-pager",
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.untrackedCache=false",
        "-C",
        str(root),
        *arguments,
    ]
    try:
        result = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            env=git_environment(),
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GitUnavailable(str(error)) from error
    if result.returncode != 0 or len(result.stdout) > MAX_GIT_OUTPUT_BYTES:
        raise GitUnavailable("fixed local Git observation failed")
    return result.stdout


def parse_nul_paths(payload: bytes, label: str) -> set[str]:
    if not payload:
        return set()
    if not payload.endswith(b"\0"):
        raise GitUnavailable(f"{label} was not NUL terminated")
    result: set[str] = set()
    for raw in payload[:-1].split(b"\0"):
        try:
            name, _ = safe_relative_path(raw, label)
        except SystemExit as error:
            raise GitUnavailable(str(error)) from error
        result.add(name)
    return result


def observe_git(root: Path, pathspecs: list[str]) -> dict[str, object] | None:
    git = fixed_system_git()
    if git is None:
        return None
    try:
        inside = run_local_git(git, root, ["rev-parse", "--is-inside-work-tree"])
        top_raw = run_local_git(git, root, ["rev-parse", "--show-toplevel"])
        if inside != b"true\n":
            return None
        top = Path(top_raw.decode("utf-8", errors="strict").rstrip("\n")).resolve(strict=True)
        if top != root:
            return None
        object_format = run_local_git(git, root, ["rev-parse", "--show-object-format"])
        object_format_text = object_format.decode("ascii", errors="strict").strip()
        if object_format_text not in ("sha1", "sha256"):
            return None
        base_commit = run_local_git(
            git, root, ["rev-parse", "--verify", "HEAD^{commit}"]
        ).decode("ascii", errors="strict").strip()
        oid_length = 40 if object_format_text == "sha1" else 64
        if re.fullmatch(rf"[0-9a-f]{{{oid_length}}}", base_commit) is None:
            return None

        common_diff = [
            "--name-only",
            "-z",
            "--no-renames",
            "--no-ext-diff",
            "--no-textconv",
        ]
        staged = parse_nul_paths(
            run_local_git(
                git,
                root,
                ["diff", "--cached", *common_diff, "HEAD", "--", *pathspecs],
            ),
            "staged payload path",
        )
        unstaged = parse_nul_paths(
            run_local_git(
                git, root, ["diff", *common_diff, "--", *pathspecs]
            ),
            "unstaged payload path",
        )
        untracked = parse_nul_paths(
            run_local_git(git, root, ["ls-files", "--others", "-z", "--", *pathspecs]),
            "untracked payload path",
        )
        index = run_local_git(
            git, root, ["ls-files", "--stage", "-z", "--", *pathspecs]
        )
    except (GitUnavailable, OSError, UnicodeError):
        return None

    tracked = staged | unstaged
    changed = tracked | untracked
    change_digest = hashlib.sha256()
    change_digest.update(CHANGE_PATH_SET_DOMAIN)
    for name in sorted(changed, key=lambda item: item.encode("utf-8")):
        change_digest.update(name.encode("utf-8"))
        change_digest.update(b"\0")
    clean = not tracked and not untracked
    return {
        "base_commit": base_commit,
        "change_path_set_sha256": change_digest.hexdigest(),
        "index_sha256": hashlib.sha256(index).hexdigest(),
        "object_format": object_format_text,
        "release_root_state": "clean" if clean else "dirty",
        "tracked_change_path_count": len(tracked),
        "untracked_payload_file_count": len(untracked),
    }


def capture_source_snapshot(
    root_arg: Path, inventory: Path, pathspec_path: Path
) -> dict[str, object]:
    try:
        metadata = root_arg.lstat()
    except OSError as error:
        fail(f"source root is unavailable: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail("source root must be a non-symlink directory")
    root = root_arg.resolve(strict=True)
    _, inventory_digest_before = read_source_inventory(root, inventory)
    pathspecs, pathspec_digest = read_git_pathspecs(pathspec_path)
    git_before = observe_git(root, pathspecs)
    _, inventory_digest_after = read_source_inventory(root, inventory)
    git_after = observe_git(root, pathspecs)
    if inventory_digest_before != inventory_digest_after or git_before != git_after:
        fail("release source or Git index changed while provenance was captured")

    if git_before is None:
        source = source_unavailable()
        git_state = {"availability": False}
    else:
        source = {
            "format": SOURCE_FORMAT,
            "availability": True,
            "base_commit": git_before["base_commit"],
            "object_format": git_before["object_format"],
            "scope": SOURCE_SCOPE,
            "release_root_state": git_before["release_root_state"],
            "clean_checkout_reproducible": (
                git_before["release_root_state"] == "clean"
            ),
            "tracked_change_path_count": git_before["tracked_change_path_count"],
            "untracked_payload_file_count": git_before["untracked_payload_file_count"],
            "change_path_set_sha256": git_before["change_path_set_sha256"],
            "path_disclosure": SOURCE_PATH_DISCLOSURE,
        }
        git_state = {"availability": True, **git_before}
    validate_source(source)
    state = {
        "git": git_state,
        "inventory_sha256": inventory_digest_before,
        "pathspec_sha256": pathspec_digest,
    }
    state_sha256 = hashlib.sha256(SOURCE_STATE_DOMAIN + canonical_bytes(state)).hexdigest()
    return {
        "schema_version": 1,
        "kind": SOURCE_SNAPSHOT_KIND,
        "source": source,
        "state_sha256": state_sha256,
    }


def load_json_closed(path: Path, label: str) -> object:
    payload = read_limited(path, label, MAX_SOURCE_SCOPE_BYTES)

    def pairs(values: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in values:
            if key in result:
                fail(f"{label} contains a duplicate key")
            result[key] = value
        return result

    try:
        return json.loads(payload.decode("utf-8", errors="strict"), object_pairs_hook=pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} is not canonical JSON: {error}")


def load_source_snapshot(path: Path) -> dict[str, Any]:
    snapshot = exact_object(
        load_json_closed(path, "source snapshot"),
        ("schema_version", "kind", "source", "state_sha256"),
        "source snapshot",
    )
    if snapshot["schema_version"] != 1 or snapshot["kind"] != SOURCE_SNAPSHOT_KIND:
        fail("source snapshot identity is unsupported")
    validate_source(snapshot["source"])
    state_digest = snapshot["state_sha256"]
    if not isinstance(state_digest, str) or SHA256_RE.fullmatch(state_digest) is None:
        fail("source snapshot state digest is malformed")
    return snapshot


def parse_checksum(path: Path, asset_name: str) -> str:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        fail(f"checksum cannot be read: {error}")
    if len(lines) != 1:
        fail("checksum must contain exactly one record")
    match = re.fullmatch(r"([0-9a-f]{64})  ([^/\s]+)", lines[0])
    if match is None or match.group(2) != asset_name:
        fail(f"checksum must be the canonical record for {asset_name}")
    return match.group(1)


def parse_formula(path: Path, expected_url: str, archive_digest: str) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        fail(f"formula cannot be read: {error}")
    if PLACEHOLDER_RE.search(text):
        fail("formula contains an unresolved template placeholder")
    urls = [match.group(1) for line in text.splitlines() if (match := FORMULA_URL_RE.fullmatch(line))]
    digests = [match.group(1) for line in text.splitlines() if (match := FORMULA_SHA_RE.fullmatch(line))]
    if urls != [expected_url]:
        fail("formula version or release URL does not match the candidate archive")
    if digests != [archive_digest]:
        fail("formula SHA-256 does not match the candidate archive")


def parse_inner_checksums(contents: bytes) -> dict[str, str]:
    try:
        lines = contents.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"archive SHA256SUMS is not UTF-8: {error}")
    records: dict[str, str] = {}
    for line in lines:
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  ([^\s]+)", line)
        if match is None:
            fail("archive SHA256SUMS contains a malformed record")
        name = match.group(2)
        posix_name = PurePosixPath(name)
        if posix_name.is_absolute() or any(part in ("", ".", "..") for part in posix_name.parts):
            fail(f"archive SHA256SUMS contains an unsafe path: {name}")
        if name in records:
            fail(f"archive SHA256SUMS contains a duplicate path: {name}")
        records[name] = match.group(1)
    if not records:
        fail("archive SHA256SUMS contains no file records")
    return records


def parse_sbom_file_inventory(
    document: dict[str, object],
) -> dict[str, tuple[str, int]]:
    components = document.get("components")
    if not isinstance(components, list):
        fail("SBOM components must be an array")

    inventory: dict[str, tuple[str, int]] = {}
    for component in components:
        if not isinstance(component, dict) or component.get("type") != "file":
            continue
        name = component.get("name")
        if not isinstance(name, str) or not name:
            fail("SBOM file component has an invalid name")
        posix_name = PurePosixPath(name)
        if posix_name.is_absolute() or any(
            part in ("", ".", "..") for part in posix_name.parts
        ):
            fail(f"SBOM file component has an unsafe name: {name}")
        if name in inventory:
            fail(f"SBOM file component is duplicated: {name}")

        hashes = component.get("hashes")
        if (
            not isinstance(hashes, list)
            or len(hashes) != 1
            or not isinstance(hashes[0], dict)
            or hashes[0].get("alg") != "SHA-256"
            or not isinstance(hashes[0].get("content"), str)
            or SHA256_RE.fullmatch(hashes[0]["content"]) is None
        ):
            fail(f"SBOM file component has a non-canonical SHA-256 hash: {name}")

        properties = component.get("properties")
        if (
            not isinstance(properties, list)
            or len(properties) != 1
            or not isinstance(properties[0], dict)
            or properties[0].get("name") != "size"
            or not isinstance(properties[0].get("value"), str)
            or re.fullmatch(r"0|[1-9][0-9]*", properties[0]["value"]) is None
        ):
            fail(f"SBOM file component has a non-canonical size: {name}")

        inventory[name] = (hashes[0]["content"], int(properties[0]["value"]))

    if not inventory:
        fail("SBOM file component inventory is empty")
    return inventory


def summarize_names(names: set[str]) -> str:
    ordered = sorted(names, key=lambda name: name.encode("utf-8"))
    shown = ", ".join(ordered[:5])
    if len(ordered) > 5:
        shown += f", ... ({len(ordered)} total)"
    return shown


def parse_attestation_exclusions(contents: bytes) -> tuple[str, ...]:
    try:
        lines = contents.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"release attestation exclusion registry is not UTF-8: {error}")
    exclusions = tuple(
        line for line in lines if line and not line.startswith("#")
    )
    if exclusions != EXPECTED_ATTESTATION_EXCLUSIONS:
        fail("release attestation exclusion registry has unexpected entries")
    return exclusions


def is_attestation_metadata(name: str, exclusions: tuple[str, ...]) -> bool:
    for excluded in exclusions:
        if excluded.endswith("/"):
            if name.startswith(excluded):
                return True
        elif name == excluded:
            return True
    return False


def verify_sbom_archive_identity(
    document: dict[str, object],
    version: str,
    members: dict[str, tuple[str, int]],
) -> None:
    inventory = parse_sbom_file_inventory(document)
    expected_names = set(members)
    actual_names = set(inventory)
    missing = expected_names.difference(actual_names)
    invented = actual_names.difference(expected_names)
    if missing or invented:
        details = []
        if missing:
            details.append(f"missing: {summarize_names(missing)}")
        if invented:
            details.append(f"invented: {summarize_names(invented)}")
        fail(f"SBOM file inventory does not match archive payload ({'; '.join(details)})")

    for name in sorted(expected_names, key=lambda value: value.encode("utf-8")):
        expected_digest, expected_size = members[name]
        recorded_digest, recorded_size = inventory[name]
        if recorded_digest != expected_digest:
            fail(f"SBOM SHA-256 does not match archive member: {name}")
        if recorded_size != expected_size:
            fail(f"SBOM size does not match archive member: {name}")

    checksum_manifest = "".join(
        f"{members[name][0]}  {name}\n"
        for name in sorted(expected_names, key=lambda value: value.encode("utf-8"))
    ).encode("utf-8")
    payload_digest = hashlib.sha256(checksum_manifest).hexdigest()
    identity = f"https://github.com/{REPOSITORY}/sbom/{version}/{payload_digest}"
    expected_serial = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, identity)}"
    if document.get("serialNumber") != expected_serial:
        fail("SBOM serialNumber does not match the generator identity for the archive payload")


def verify_archive(
    archive: Path,
    version: str,
    sbom_bytes: bytes,
    sbom_document: dict[str, object],
) -> None:
    try:
        with tarfile.open(archive, mode="r:gz") as package:
            members = package.getmembers()
            names = [member.name for member in members]
            if len(names) != len(set(names)):
                fail("archive contains duplicate members")
            for member in members:
                posix_name = PurePosixPath(member.name)
                if (
                    posix_name.is_absolute()
                    or any(part in ("", ".", "..") for part in posix_name.parts)
                    or not member.isfile()
                ):
                    fail(f"archive contains an unsafe or non-regular member: {member.name}")

            by_name = {member.name: member for member in members}
            required = {
                "VERSION",
                "FUNCTIONS.json",
                "MANIFEST.json",
                "INVOCATION_INDEX.json",
                "sbom.json",
                "SHA256SUMS",
                "bin/mainframe",
                "get-mainframe.sh",
                "install.sh",
                "scripts/upgrade-release.sh",
                "hooks/agent-gateway.sh",
                "lib/agent_safety.sh",
                "lib/launch.sh",
                "security/gate-rules.json",
                "security/gate-normalizer.mjs",
                ATTESTATION_EXCLUSIONS_PATH,
            }
            missing = required.difference(by_name)
            if missing:
                fail(f"archive is missing required members: {', '.join(sorted(missing))}")

            def read_member(name: str) -> bytes:
                extracted = package.extractfile(by_name[name])
                if extracted is None:
                    fail(f"archive member cannot be read: {name}")
                return extracted.read()

            try:
                archived_version = read_member("VERSION").decode("utf-8").strip()
            except UnicodeDecodeError as error:
                fail(f"archive VERSION is not UTF-8: {error}")
            if archived_version != version:
                fail("archive VERSION does not match the candidate version")
            if read_member("sbom.json") != sbom_bytes:
                fail("outer SBOM does not match the SBOM embedded in the archive")
            for name in (
                "bin/mainframe",
                "get-mainframe.sh",
                "install.sh",
                "scripts/upgrade-release.sh",
                "hooks/agent-gateway.sh",
            ):
                if by_name[name].mode & 0o111 == 0:
                    fail(f"critical archive entry is not executable: {name}")
            for name in (
                "MANIFEST.json",
                "INVOCATION_INDEX.json",
                "security/gate-rules.json",
            ):
                try:
                    identity = json.loads(read_member(name))
                except json.JSONDecodeError as error:
                    fail(f"critical archive JSON is malformed ({name}): {error}")
                if identity.get("version") != version:
                    fail(f"critical archive JSON version mismatch: {name}")

            records = parse_inner_checksums(read_member("SHA256SUMS"))
            attestation_exclusions = parse_attestation_exclusions(
                read_member(ATTESTATION_EXCLUSIONS_PATH)
            )
            payload_names = set(names).difference({"SHA256SUMS"})
            if set(records) != payload_names:
                fail("archive SHA256SUMS does not exactly cover the payload")
            payload_identity: dict[str, tuple[str, int]] = {}
            for name in sorted(payload_names):
                contents = read_member(name)
                actual = hashlib.sha256(contents).hexdigest()
                if actual != records[name]:
                    fail(f"archive payload checksum mismatch: {name}")
                if name != "sbom.json":
                    payload_identity[name] = (actual, len(contents))
            subject_identity = {
                name: identity
                for name, identity in payload_identity.items()
                if not is_attestation_metadata(name, attestation_exclusions)
            }
            verify_sbom_archive_identity(
                sbom_document,
                version,
                subject_identity,
            )
    except (OSError, tarfile.TarError) as error:
        fail(f"archive cannot be inspected: {error}")


def run_strong_sbom_validator(contents: bytes, version: str) -> None:
    """Validate the exact candidate bytes with the attestation SBOM contract."""
    validator = Path(__file__).resolve().with_name("validate-release-sbom.py")
    regular_file(validator, "release SBOM validator")
    environment = os.environ.copy()
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["PYTHONNOUSERSITE"] = "1"

    try:
        with tempfile.TemporaryDirectory(prefix="mainframe-release-sbom-") as directory:
            validation_input = Path(directory) / "candidate-sbom.json"
            validation_input.write_bytes(contents)
            os.chmod(validation_input, 0o600)
            result = subprocess.run(
                [sys.executable, str(validator), str(validation_input), version],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )
    except OSError as error:
        fail(f"strong SBOM validator could not run: {error}")

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        fail(f"strong SBOM validation failed: {detail}")


def verify_sbom(path: Path, version: str) -> tuple[bytes, dict[str, object]]:
    try:
        contents = path.read_bytes()
    except OSError as error:
        fail(f"SBOM cannot be read: {error}")
    run_strong_sbom_validator(contents, version)
    try:
        document = json.loads(contents)
    except json.JSONDecodeError as error:
        fail(f"SBOM cannot be read: {error}")
    if not isinstance(document, dict):
        fail("SBOM document must be an object")
    return contents, document


def write_manifest(path: Path, document: dict[str, object]) -> None:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        fail(f"manifest output must be absent or a regular, non-symlink file: {path}")
    parent = path.parent
    if not parent.is_dir() or parent.is_symlink():
        fail(f"manifest output parent must be an existing, non-symlink directory: {parent}")
    payload = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--checksum", type=Path)
    parser.add_argument("--sbom", type=Path)
    parser.add_argument("--formula", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--source-inventory", type=Path)
    parser.add_argument("--source-pathspecs", type=Path)
    parser.add_argument("--source-snapshot", type=Path)
    parser.add_argument("--capture-source-snapshot", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_inputs = (args.source_root, args.source_inventory, args.source_pathspecs)
    if args.capture_source_snapshot is not None:
        if any(value is None for value in source_inputs):
            fail("source capture requires root, inventory, and pathspecs")
        if any(
            value is not None
            for value in (
                args.version,
                args.archive,
                args.checksum,
                args.sbom,
                args.formula,
                args.manifest,
                args.source_snapshot,
            )
        ):
            fail("source capture cannot be combined with candidate verification")
        snapshot = capture_source_snapshot(
            args.source_root, args.source_inventory, args.source_pathspecs
        )
        write_manifest(args.capture_source_snapshot, snapshot)
        print("release source provenance captured")
        return 0

    required = {
        "version": args.version,
        "archive": args.archive,
        "checksum": args.checksum,
        "sbom": args.sbom,
        "formula": args.formula,
        "manifest": args.manifest,
    }
    missing = sorted(key for key, value in required.items() if value is None)
    if missing:
        fail(f"candidate verification is missing required arguments: {', '.join(missing)}")
    if args.source_snapshot is None:
        if any(value is not None for value in source_inputs):
            fail("source root, inventory, and pathspecs require a source snapshot")
        source = source_unavailable()
    else:
        if any(value is None for value in source_inputs):
            fail("a source snapshot requires root, inventory, and pathspecs")
        expected_snapshot = load_source_snapshot(args.source_snapshot)
        observed_snapshot = capture_source_snapshot(
            args.source_root, args.source_inventory, args.source_pathspecs
        )
        if observed_snapshot != expected_snapshot:
            fail("source snapshot no longer matches the release root or Git index")
        source = expected_snapshot["source"]

    if re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", args.version) is None:
        fail("version must be stable SemVer")

    archive_name = f"mainframe-{args.version}.tar.gz"
    checksum_name = f"{archive_name}.sha256"
    sbom_name = f"mainframe-{args.version}.sbom.json"
    expected_names = {
        "archive": archive_name,
        "checksum": checksum_name,
        "sbom": sbom_name,
        "formula": "mainframe.rb",
        "manifest": f"mainframe-{args.version}.candidate.json",
    }
    for label, path in (
        ("archive", args.archive),
        ("checksum", args.checksum),
        ("sbom", args.sbom),
        ("formula", args.formula),
    ):
        if path.name != expected_names[label]:
            fail(f"{label} must be named exactly {expected_names[label]}")
        regular_file(path, label)
    if args.manifest.name != expected_names["manifest"]:
        fail(f"manifest must be named exactly {expected_names['manifest']}")

    archive_digest = sha256(args.archive)
    if not SHA256_RE.fullmatch(archive_digest):
        fail("archive digest is malformed")
    if parse_checksum(args.checksum, archive_name) != archive_digest:
        fail("checksum SHA-256 does not match the candidate archive")
    expected_url = (
        f"https://github.com/{REPOSITORY}/releases/download/"
        f"v{args.version}/{archive_name}"
    )
    parse_formula(args.formula, expected_url, archive_digest)
    sbom_bytes, sbom_document = verify_sbom(args.sbom, args.version)
    verify_archive(args.archive, args.version, sbom_bytes, sbom_document)

    manifest = {
        "artifacts": {
            "archive": {"name": archive_name, "sha256": archive_digest},
            "checksum": {"name": checksum_name, "sha256": sha256(args.checksum)},
            "formula": {"name": "mainframe.rb", "sha256": sha256(args.formula)},
            "sbom": {"name": sbom_name, "sha256": sha256(args.sbom)},
        },
        "schema": SCHEMA,
        "source": source,
        "version": args.version,
    }
    write_manifest(args.manifest, manifest)
    print(f"release candidate valid: v{args.version} ({archive_digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Inventory and enforce MAINFRAME's top-level shell function exports.

The checker intentionally scans only direct ``lib/*.sh`` children and only
column-zero Bash definitions in the form ``name() {``.  That is the loadable
standard-library surface whose existing collision set is frozen by the policy.
"""

from __future__ import print_function

import argparse
import collections
import dataclasses
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
DEFAULT_POLICY = "config/function-export-policy.json"
FUNCTION_RE = re.compile(
    r"^([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*)\s*\(\)\s*\{\s*(?:#.*)?$"
)
CLASSIFICATIONS = {
    "guarded-equivalent",
    "legacy-same-file",
    "legacy-unresolved",
}


class InputError(Exception):
    """An invalid path, source file, or policy document."""


@dataclasses.dataclass(frozen=True)
class Definition:
    name: str
    path: str
    line: int
    guarded: bool

    @property
    def location(self) -> str:
        return "{}:{}".format(self.path, self.line)


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inventory or enforce top-level lib/*.sh function exports."
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--check",
        action="store_true",
        help="fail when discovered collisions differ from the checked-in policy",
    )
    mode.add_argument(
        "--inventory",
        action="store_true",
        help="print a deterministic human-readable collision inventory",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="repository root (defaults to the parent of this script's directory)",
    )
    parser.add_argument(
        "--lib-dir",
        default="lib",
        help="direct library directory, relative to --root (default: lib)",
    )
    parser.add_argument(
        "--policy",
        default=DEFAULT_POLICY,
        help="policy JSON, relative to --root (default: %(default)s)",
    )
    return parser.parse_args(argv)


def resolve_under_root(root: Path, value: str, label: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = candidate.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise InputError("{} must be inside --root: {}".format(label, candidate)) from exc
    return candidate


def repo_relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError as exc:
        raise InputError("source file is outside --root: {}".format(path)) from exc


def is_direct_declare_guard(lines: Sequence[str], index: int, name: str) -> bool:
    """Return whether a definition is directly wrapped by an existence guard."""

    guard = re.compile(
        r"^if\s+!\s+(?:builtin\s+)?declare\s+-F(?:\s+--)?\s+"
        r"(?:['\"])?{}(?:['\"])?(?:\s|[&;>]).*;\s*then\s*$".format(
            re.escape(name)
        )
    )
    for prior in range(index - 1, max(-1, index - 8), -1):
        stripped = lines[prior].strip()
        if not stripped or stripped.startswith("#"):
            continue
        return bool(guard.match(stripped))
    return False


def discover(root: Path, lib_dir: Path) -> Tuple[List[Path], Dict[str, List[Definition]]]:
    if not lib_dir.is_dir():
        raise InputError("library directory does not exist: {}".format(lib_dir))

    files = sorted(path for path in lib_dir.glob("*.sh") if path.is_file())
    definitions: Dict[str, List[Definition]] = collections.defaultdict(list)
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as exc:
            raise InputError("could not read {}: {}".format(path, exc)) from exc
        relative = repo_relative(root, path)
        for index, line in enumerate(lines):
            match = FUNCTION_RE.match(line)
            if not match:
                continue
            name = match.group(1)
            definitions[name].append(
                Definition(
                    name=name,
                    path=relative,
                    line=index + 1,
                    guarded=is_direct_declare_guard(lines, index, name),
                )
            )
    return files, dict(definitions)


def collisions(
    definitions: Mapping[str, Sequence[Definition]],
) -> Dict[str, List[Definition]]:
    return {
        name: list(items)
        for name, items in definitions.items()
        if len(items) > 1
    }


def valid_repo_path(value: object) -> bool:
    if not isinstance(value, str) or not value or "\\" in value:
        return False
    path = PurePosixPath(value)
    return (
        not path.is_absolute()
        and len(path.parts) == 2
        and path.parts[0] == "lib"
        and all(part not in ("", ".", "..") for part in path.parts)
        and path.suffix == ".sh"
    )


def load_policy(path: Path) -> Dict[str, Mapping[str, object]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise InputError("policy file does not exist: {}".format(path)) from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise InputError("could not read policy {}: {}".format(path, exc)) from exc

    if not isinstance(document, dict):
        raise InputError("policy root must be a JSON object")
    if document.get("schema_version") != SCHEMA_VERSION:
        raise InputError(
            "policy schema_version must be {}".format(SCHEMA_VERSION)
        )
    entries = document.get("collisions")
    if not isinstance(entries, dict):
        raise InputError("policy collisions must be a JSON object")

    for name, entry in entries.items():
        if not isinstance(name, str) or not FUNCTION_RE.match(name + "() {"):
            raise InputError("invalid function name in policy: {!r}".format(name))
        if not isinstance(entry, dict):
            raise InputError("policy entry for {} must be an object".format(name))
        classification = entry.get("classification")
        if classification not in CLASSIFICATIONS:
            raise InputError(
                "policy entry for {} has invalid classification: {!r}".format(
                    name, classification
                )
            )
        expected = entry.get("definitions")
        if not isinstance(expected, list) or len(expected) < 2:
            raise InputError(
                "policy entry for {} must list at least two definitions".format(name)
            )
        if any(not valid_repo_path(value) for value in expected):
            raise InputError(
                "policy entry for {} contains an invalid definition path".format(name)
            )
        if expected != sorted(expected):
            raise InputError(
                "policy entry for {} definitions must be sorted".format(name)
            )
        rationale = entry.get("rationale")
        if not isinstance(rationale, str) or not rationale.strip():
            raise InputError(
                "policy entry for {} must include a rationale".format(name)
            )
    return entries


def repeated_paths(items: Iterable[Definition]) -> List[str]:
    counts = collections.Counter(item.path for item in items)
    return sorted(path for path, count in counts.items() if count > 1)


def check_policy(
    found: Mapping[str, Sequence[Definition]],
    policy: Mapping[str, Mapping[str, object]],
) -> List[str]:
    errors: List[str] = []
    found_names = set(found)
    policy_names = set(policy)

    for name in sorted(found_names - policy_names):
        locations = ", ".join(item.location for item in found[name])
        errors.append("unlisted collision {}: {}".format(name, locations))
    for name in sorted(policy_names - found_names):
        errors.append("listed collision {} no longer has multiple definitions".format(name))

    for name in sorted(found_names & policy_names):
        items = found[name]
        entry = policy[name]
        classification = str(entry["classification"])
        expected = list(entry["definitions"])
        actual = sorted(item.path for item in items)
        if expected != actual:
            errors.append(
                "definition set changed for {}: expected [{}]; found [{}]".format(
                    name, ", ".join(expected), ", ".join(actual)
                )
            )

        same_file = repeated_paths(items)
        if same_file and classification != "legacy-same-file":
            errors.append(
                "same-file duplicate {} in {} requires legacy-same-file classification".format(
                    name, ", ".join(same_file)
                )
            )
        if classification == "legacy-same-file" and not same_file:
            errors.append(
                "legacy-same-file classification for {} has no same-file duplicate".format(
                    name
                )
            )
        if classification == "guarded-equivalent":
            if not name.startswith("_"):
                errors.append(
                    "guarded-equivalent collision {} must be private".format(name)
                )
            unguarded = [item.location for item in items if not item.guarded]
            if unguarded:
                errors.append(
                    "guarded-equivalent collision {} has unguarded definitions: {}".format(
                        name, ", ".join(unguarded)
                    )
                )
    return errors


def print_inventory(
    files: Sequence[Path],
    definitions: Mapping[str, Sequence[Definition]],
    found: Mapping[str, Sequence[Definition]],
    policy: Optional[Mapping[str, Mapping[str, object]]],
) -> None:
    public = sum(not name.startswith("_") for name in found)
    private = len(found) - public
    total_definitions = sum(len(items) for items in definitions.values())
    print("Function export inventory")
    print("Scope: direct top-level definitions in lib/*.sh")
    print(
        "Summary: {} files, {} definitions, {} unique names, {} collisions "
        "({} public, {} private)".format(
            len(files),
            total_definitions,
            len(definitions),
            len(found),
            public,
            private,
        )
    )
    for name in sorted(found):
        items = found[name]
        visibility = "private" if name.startswith("_") else "public"
        classification = "unlisted"
        if policy is not None and name in policy:
            classification = str(policy[name]["classification"])
        locations = ", ".join(
            item.location + (" [guarded]" if item.guarded else "") for item in items
        )
        print("- {} [{}; {}]: {}".format(name, visibility, classification, locations))


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    root = (
        Path(args.root).expanduser().resolve()
        if args.root
        else Path(__file__).resolve().parent.parent
    )
    if not root.is_dir():
        print("error: repository root does not exist: {}".format(root), file=sys.stderr)
        return 2

    try:
        lib_dir = resolve_under_root(root, args.lib_dir, "--lib-dir")
        policy_path = resolve_under_root(root, args.policy, "--policy")
        files, definitions = discover(root, lib_dir)
        found = collisions(definitions)
        policy = load_policy(policy_path)
    except InputError as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 2

    if args.inventory:
        print_inventory(files, definitions, found, policy)
        return 0

    errors = check_policy(found, policy)
    if errors:
        print(
            "Function export policy check failed ({} violation{}):".format(
                len(errors), "" if len(errors) == 1 else "s"
            ),
            file=sys.stderr,
        )
        for error in errors:
            print("- {}".format(error), file=sys.stderr)
        return 1

    public = sum(not name.startswith("_") for name in found)
    private = len(found) - public
    print(
        "Function export policy check passed: {} exact collision entries "
        "({} public, {} private).".format(len(found), public, private)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

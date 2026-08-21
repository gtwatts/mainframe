#!/usr/bin/env python3
"""Generate the deterministic Bash runtime closure from reviewed config.

``load_time_dependencies`` contains fixed module-to-module sources evaluated
while a library is imported. Those edges are transitively expanded before the
dependent module. Sources of ``common.sh`` are omitted because common is the
loader bootstrap, not a library module.

Fixed modules loaded only after a public function is called belong in
``conditional_tool_time_dependencies`` and do not enter the startup closure.
Dynamic session, mock, wrapper, and caller-provided files are not module edges
and intentionally remain outside both maps.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Optional, Sequence


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = ROOT / "config" / "runtime-closure.json"
DEFAULT_OUTPUT = ROOT / "lib" / "runtime-closure.generated.bash"
EXPECTED_TIER_ORDER = ("preload", "core", "standard", "extended", "ai")
EXPECTED_CONFIG_KEYS = {
    "schema_version",
    "tier_order",
    "tiers",
    "load_time_dependencies",
    "conditional_tool_time_dependencies",
}
MODULE_NAME = re.compile(r"^[A-Za-z0-9_-]+$")


class ClosureError(ValueError):
    """Raised when runtime-closure input violates the closed schema."""


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ClosureError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _validate_module_name(module: Any, context: str) -> str:
    if not isinstance(module, str) or not MODULE_NAME.fullmatch(module):
        raise ClosureError(f"invalid module name in {context}: {module!r}")
    return module


def _validate_module_file(module: str) -> None:
    module_path = ROOT / "lib" / f"{module}.sh"
    if not module_path.is_file():
        raise ClosureError(f"configured module does not exist: {module_path}")


def _validate_dependency_list(owner: str, dependencies: Any, context: str) -> list[str]:
    if not isinstance(dependencies, list):
        raise ClosureError(f"{context} for {owner!r} must be an array")
    result: list[str] = []
    seen: set[str] = set()
    for dependency in dependencies:
        dependency = _validate_module_name(dependency, f"{context} for {owner!r}")
        if dependency in seen:
            raise ClosureError(
                f"duplicate {context} for {owner!r}: {dependency}"
            )
        seen.add(dependency)
        result.append(dependency)
    return result


def resolve_load_order(
    roots: Sequence[str], dependencies: dict[str, list[str]]
) -> list[str]:
    """Return a stable dependency-first transitive closure or reject a cycle."""

    resolved: list[str] = []
    complete: set[str] = set()
    active: list[str] = []

    def visit(module: str) -> None:
        if module in complete:
            return
        if module in active:
            cycle_start = active.index(module)
            cycle = active[cycle_start:] + [module]
            raise ClosureError("load-time dependency cycle: " + " -> ".join(cycle))

        active.append(module)
        for dependency in dependencies.get(module, []):
            visit(dependency)
        active.pop()
        complete.add(module)
        resolved.append(module)

    for root in roots:
        visit(root)

    positions = {module: index for index, module in enumerate(resolved)}
    for owner in resolved:
        for dependency in dependencies.get(owner, []):
            if positions[dependency] >= positions[owner]:
                raise ClosureError(
                    f"dependency ordering failed: {dependency} must precede {owner}"
                )
    return resolved


def load_config(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle, object_pairs_hook=_object_without_duplicate_keys)
    except (OSError, json.JSONDecodeError, ClosureError) as exc:
        raise ClosureError(f"cannot read {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ClosureError("top-level config must be an object")
    if set(data) != EXPECTED_CONFIG_KEYS:
        raise ClosureError(
            "top-level keys must be exactly: "
            + ", ".join(sorted(EXPECTED_CONFIG_KEYS))
        )
    if data["schema_version"] != 2 or isinstance(data["schema_version"], bool):
        raise ClosureError("schema_version must be 2")
    if data["tier_order"] != list(EXPECTED_TIER_ORDER):
        raise ClosureError(
            "tier_order must be: " + ", ".join(EXPECTED_TIER_ORDER)
        )

    tiers = data["tiers"]
    if not isinstance(tiers, dict) or set(tiers) != set(EXPECTED_TIER_ORDER):
        raise ClosureError(
            "tiers must contain exactly: " + ", ".join(EXPECTED_TIER_ORDER)
        )

    seen: set[str] = set()
    for tier_name in EXPECTED_TIER_ORDER:
        modules = tiers[tier_name]
        if not isinstance(modules, list) or not modules:
            raise ClosureError(f"tier {tier_name!r} must be a non-empty array")
        for module in modules:
            module = _validate_module_name(module, repr(tier_name))
            if module in seen:
                raise ClosureError(f"module appears more than once: {module}")
            _validate_module_file(module)
            seen.add(module)

    load_dependencies = data["load_time_dependencies"]
    if not isinstance(load_dependencies, dict):
        raise ClosureError("load_time_dependencies must be an object")
    validated_load_dependencies: dict[str, list[str]] = {}
    for owner, raw_dependencies in load_dependencies.items():
        owner = _validate_module_name(owner, "load_time_dependencies")
        _validate_module_file(owner)
        validated_load_dependencies[owner] = _validate_dependency_list(
            owner, raw_dependencies, "load-time dependency"
        )

    known_load_modules = seen | set(validated_load_dependencies)
    for owner, dependencies in validated_load_dependencies.items():
        for dependency in dependencies:
            if dependency not in known_load_modules:
                raise ClosureError(
                    f"unknown load-time dependency {dependency!r} required by {owner!r}"
                )

    roots = [module for tier in EXPECTED_TIER_ORDER for module in tiers[tier]]
    closure = resolve_load_order(roots, validated_load_dependencies)
    unreachable = sorted(set(validated_load_dependencies) - set(closure))
    if unreachable:
        raise ClosureError(
            "load-time dependency metadata is unreachable: " + ", ".join(unreachable)
        )

    tool_dependencies = data["conditional_tool_time_dependencies"]
    if not isinstance(tool_dependencies, dict):
        raise ClosureError("conditional_tool_time_dependencies must be an object")
    validated_tool_dependencies: dict[str, list[str]] = {}
    for owner, raw_dependencies in tool_dependencies.items():
        owner = _validate_module_name(owner, "conditional_tool_time_dependencies")
        if owner not in seen:
            raise ClosureError(f"unknown tool-time dependency owner: {owner}")
        dependencies = _validate_dependency_list(
            owner, raw_dependencies, "conditional tool-time dependency"
        )
        overlap = set(dependencies) & set(validated_load_dependencies.get(owner, []))
        if overlap:
            raise ClosureError(
                f"dependency cannot be both load-time and tool-time for {owner!r}: "
                + ", ".join(sorted(overlap))
            )
        for dependency in dependencies:
            _validate_module_file(dependency)
        validated_tool_dependencies[owner] = dependencies

    data["load_time_dependencies"] = validated_load_dependencies
    data["conditional_tool_time_dependencies"] = validated_tool_dependencies

    return data


def _render_array(name: str, modules: Sequence[str]) -> list[str]:
    lines = [f"{name}=("]
    lines.extend(f"    {module}" for module in modules)
    lines.append(")")
    return lines


def render(config: dict[str, Any]) -> str:
    tiers: dict[str, list[str]] = config["tiers"]
    dependencies: dict[str, list[str]] = config["load_time_dependencies"]
    roots = [module for tier in EXPECTED_TIER_ORDER for module in tiers[tier]]
    closure = resolve_load_order(roots, dependencies)
    lines = [
        "#!/usr/bin/env bash",
        "# Generated by scripts/generate-runtime-closure.py.",
        "# Source config: config/runtime-closure.json. DO NOT EDIT.",
        "# Load-time dependencies are expanded transitively before dependents.",
        "# Conditional tool-time dependencies are intentionally excluded.",
        "",
    ]
    for tier_name in EXPECTED_TIER_ORDER:
        variable_name = (
            "_MAINFRAME_FULL_PRELOAD"
            if tier_name == "preload"
            else f"_MAINFRAME_TIER_{tier_name.upper()}"
        )
        lines.extend(
            _render_array(
                variable_name,
                resolve_load_order(tiers[tier_name], dependencies),
            )
        )
        lines.append("")
    lines.extend(_render_array("_MAINFRAME_FULL_CLOSURE", closure))
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if output is stale")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    try:
        generated = render(load_config(args.config))
    except ClosureError as exc:
        print(f"runtime-closure: {exc}", file=sys.stderr)
        return 2

    if args.check:
        try:
            current = args.output.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"runtime-closure: cannot read {args.output}: {exc}", file=sys.stderr)
            return 1
        if current != generated:
            print(
                f"runtime-closure: {args.output} is stale; "
                "run scripts/generate-runtime-closure.py",
                file=sys.stderr,
            )
            return 1
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

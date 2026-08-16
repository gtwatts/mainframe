#!/usr/bin/env python3
"""Validate native-host evidence against the repository's JSON Schema subset."""

from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import re
import sys
from typing import Any, NoReturn


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid native-host evidence: {message}")


def load_json(path: Path) -> Any:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                fail(f"{path}: duplicate key {key!r}")
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path}: {error}")


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
        fail(f"unsupported non-local schema reference: {reference}")
    current: Any = root
    for encoded_part in reference[2:].split("/"):
        part = encoded_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            fail(f"unresolvable schema reference: {reference}")
        current = current[part]
    if not isinstance(current, dict):
        fail(f"schema reference is not an object: {reference}")
    return current


def validate(schema: dict[str, Any], value: Any, path: str, root: dict[str, Any]) -> None:
    if "$ref" in schema:
        validate(resolve_ref(root, schema["$ref"]), value, path, root)
        return

    alternatives = schema.get("anyOf")
    if alternatives is not None:
        failures: list[str] = []
        matched = False
        for alternative in alternatives:
            try:
                validate(alternative, value, path, root)
                matched = True
                break
            except ValueError as error:
                failures.append(str(error))
        if not matched:
            raise ValueError(f"{path}: no anyOf alternative matched ({'; '.join(failures)})")

    for conjunct in schema.get("allOf", []):
        validate(conjunct, value, path, root)

    if "const" in schema:
        expected = schema["const"]
        same_value = value == expected
        # JSON Schema does not treat booleans as the integers 0 and 1.
        same_json_type = not (
            isinstance(value, bool) != isinstance(expected, bool)
            and isinstance(value, (bool, int))
            and isinstance(expected, (bool, int))
        )
        if not (same_value and same_json_type):
            raise ValueError(f"{path}: expected constant {expected!r}, got {value!r}")

    expected_type = schema.get("type")
    if expected_type is not None and not matches_type(value, expected_type):
        raise ValueError(f"{path}: expected {expected_type}, got {type(value).__name__}")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and value < minimum:
            raise ValueError(f"{path}: is less than minimum {minimum!r}")
        if maximum is not None and value > maximum:
            raise ValueError(f"{path}: is greater than maximum {maximum!r}")

    if isinstance(value, str):
        pattern = schema.get("pattern")
        if pattern is not None and re.search(pattern, value) is None:
            raise ValueError(f"{path}: does not match {pattern!r}")
        if len(value) < schema.get("minLength", 0):
            raise ValueError(f"{path}: is shorter than minLength")
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError as error:
                raise ValueError(f"{path}: invalid date-time: {error}") from error
            if parsed.tzinfo is None:
                raise ValueError(f"{path}: date-time must include a timezone")

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise ValueError(f"{path}: missing required keys {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise ValueError(f"{path}: unexpected keys {extras}")
        for key, child_schema in properties.items():
            if key in value:
                validate(child_schema, value[key], f"{path}.{key}", root)

    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            validate(schema["items"], item, f"{path}[{index}]", root)


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: validate-evidence.py SCHEMA EVIDENCE")
    schema = load_json(Path(sys.argv[1]))
    evidence = load_json(Path(sys.argv[2]))
    if not isinstance(schema, dict):
        fail("schema root must be an object")
    try:
        validate(schema, evidence, "$", schema)
    except ValueError as error:
        fail(str(error))
    print("native-host evidence valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

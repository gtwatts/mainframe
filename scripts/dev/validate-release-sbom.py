#!/usr/bin/env python3
"""Validate the CycloneDX contract consumed by GitHub SBOM attestations."""

from __future__ import annotations

import json
from pathlib import Path
import sys
from typing import NoReturn
import uuid


RUNTIME_CONTRACTS = {
    "runtime:bash": {
        "type": "application",
        "name": "Bash",
        "version": "4.4",
        "properties": {"mainframe:version-constraint": ">=4.4"},
    },
    "runtime:jq": {
        "type": "application",
        "name": "jq",
        "properties": {
            "mainframe:requirement": (
                "required for agent enforcement and full metadata support"
            )
        },
    },
    "runtime:python": {
        "type": "application",
        "name": "Python",
        "version": "3.9",
        "properties": {
            "mainframe:version-constraint": ">=3.9 for Pi diagnosis and lifecycle",
            "mainframe:managed-host-version-constraint": ">=3.10",
            "mainframe:requirement": (
                "Pi diagnosis/lifecycle and managed-host install, remove, and restore"
            ),
        },
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid release SBOM: {message}")


def component_properties(
    component: dict[str, object], reference: str
) -> dict[str, str]:
    properties = component.get("properties")
    if not isinstance(properties, list):
        fail(f"{reference} properties must be an array")

    values: dict[str, str] = {}
    for item in properties:
        if not isinstance(item, dict):
            fail(f"{reference} properties must contain objects")
        name = item.get("name")
        value = item.get("value")
        if not isinstance(name, str) or not name or not isinstance(value, str):
            fail(f"{reference} properties must have non-empty string names and values")
        if name in values:
            fail(f"{reference} property {name!r} is duplicated")
        values[name] = value
    return values


def validate_runtime_components(components: list[object]) -> None:
    for reference, contract in RUNTIME_CONTRACTS.items():
        matches = [
            item
            for item in components
            if isinstance(item, dict) and item.get("bom-ref") == reference
        ]
        if len(matches) != 1:
            fail(f"exactly one {reference} component is required")

        component = matches[0]
        for field in ("type", "name", "version"):
            if field not in contract:
                continue
            expected = contract[field]
            if component.get(field) != expected:
                fail(f"{reference} {field} must be {expected!r}")

        properties = component_properties(component, reference)
        expected_properties = contract["properties"]
        assert isinstance(expected_properties, dict)
        for name, expected in expected_properties.items():
            if properties.get(name) != expected:
                fail(f"{reference} property {name!r} must be {expected!r}")


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: validate-release-sbom.py SBOM VERSION")
    path = Path(sys.argv[1])
    expected_version = sys.argv[2]
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(str(error))

    if document.get("bomFormat") != "CycloneDX":
        fail("bomFormat must be CycloneDX")
    if document.get("specVersion") != "1.5":
        fail("specVersion must be 1.5")
    serial = document.get("serialNumber")
    if not isinstance(serial, str) or not serial.startswith("urn:uuid:"):
        fail("serialNumber must be an RFC 4122 urn:uuid")
    try:
        parsed_serial = uuid.UUID(serial.removeprefix("urn:uuid:"))
    except (ValueError, AttributeError) as error:
        fail(f"serialNumber is malformed: {error}")
    if serial != f"urn:uuid:{parsed_serial}" or parsed_serial.version != 5:
        fail("serialNumber must be a canonical deterministic UUIDv5")

    component = document.get("metadata", {}).get("component", {})
    if (
        component.get("name") != "mainframe"
        or component.get("version") != expected_version
    ):
        fail("metadata component does not match VERSION")
    expected_ref = f"mainframe@{expected_version}"
    if component.get("bom-ref") != expected_ref:
        fail("metadata component bom-ref does not match VERSION")

    components = document.get("components")
    if not isinstance(components, list):
        fail("components must be an array")
    validate_runtime_components(components)
    file_names = [
        item.get("name")
        for item in components
        if isinstance(item, dict) and item.get("type") == "file"
    ]
    if not file_names or any(
        not isinstance(name, str) or not name for name in file_names
    ):
        fail("file component inventory is empty or malformed")
    if len(file_names) != len(set(file_names)):
        fail("file component inventory contains duplicates")

    dependencies = document.get("dependencies")
    expected_dependencies = {
        "ref": expected_ref,
        "dependsOn": ["runtime:bash", "runtime:jq", "runtime:python"],
    }
    if not isinstance(dependencies, list) or expected_dependencies not in dependencies:
        fail("runtime dependency relationship is missing")
    print(f"release SBOM valid: {serial} ({len(file_names)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
